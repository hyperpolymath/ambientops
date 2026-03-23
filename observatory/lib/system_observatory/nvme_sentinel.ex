# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule SystemObservatory.NvmeSentinel do
  @moduledoc """
  Continuous NVMe health monitoring via SMART data polling.

  Polls NVMe SMART attributes at configurable intervals and feeds metrics
  into the Metrics.Store. Emits system-weather category updates and fires
  correlator events when thresholds cross.

  ## Monitored Attributes

  - Composite temperature (warn 65C, crit 75C, poll 30s)
  - Available spare percent (warn 30%, crit 15%, poll 3600s)
  - Media and data integrity errors (warn delta 100/day, crit delta 1000/day)
  - Unsafe shutdown count (warn 3, crit 5, per 24h)

  ## CRITICAL: Advisory Data Only (CRIT-003 compliance)

  NVMe sentinel data is advisory. It reports observed SMART attributes
  but is NOT authoritative — drives may fail without warning, and SMART
  data can be unreliable. The Ward UI uses this to set ambient mood.

  ## Requirements

  Requires `smartctl` (smartmontools) installed and accessible.
  On Fedora: `sudo dnf install smartmontools`
  Requires root/sudo for NVMe SMART access.

  ## Author

  Jonathan D.A. Jewell
  """

  use GenServer

  require Logger

  alias SystemObservatory.Metrics.Store
  alias SystemObservatory.Correlator

  # --- Thresholds (from STATE.a2ml) ---

  @temp_warn_c 65
  @temp_crit_c 75
  @temp_poll_ms 30_000

  @spare_warn_pct 30
  @spare_crit_pct 15
  @spare_poll_ms 3_600_000

  @media_errors_warn_per_day 100
  @media_errors_crit_per_day 1_000

  @unsafe_shutdowns_warn 3
  @unsafe_shutdowns_crit 5
  @unsafe_shutdowns_window_ms 86_400_000

  # Delta tracking poll interval (aligned with temperature for simplicity)
  @delta_poll_ms 30_000

  @source "nvme-sentinel"

  @type threshold_state :: :calm | :watch | :act

  # --- Client API ---

  @doc """
  Start the NVMe sentinel.

  ## Options

  - `:devices` - List of NVMe device paths (default: auto-detect via `nvme list`)
  - `:enabled` - Whether to start polling (default: true)
  - `:smartctl_path` - Path to smartctl binary (default: "smartctl")
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get the latest health snapshot for all monitored devices.
  """
  @spec health_snapshot() :: map()
  def health_snapshot do
    GenServer.call(__MODULE__, :health_snapshot)
  end

  @doc """
  Force an immediate poll of all devices.
  """
  @spec poll_now() :: :ok
  def poll_now do
    GenServer.cast(__MODULE__, :poll_now)
  end

  @doc """
  Get the current threshold evaluation as a system-weather category.

  Returns a map conforming to the `category_status` shape in
  system-weather.schema.json.
  """
  @spec weather_category() :: map()
  def weather_category do
    GenServer.call(__MODULE__, :weather_category)
  end

  # --- Server Callbacks ---

  @impl true
  def init(opts) do
    enabled = Keyword.get(opts, :enabled, true)
    smartctl_path = Keyword.get(opts, :smartctl_path, "smartctl")
    devices = Keyword.get(opts, :devices, [])

    state = %{
      devices: devices,
      enabled: enabled,
      smartctl_path: smartctl_path,
      last_readings: %{},
      # Delta tracking: {device => %{metric => {last_value, last_timestamp}}}
      delta_baselines: %{},
      # Accumulated deltas per window
      delta_accumulators: %{}
    }

    if enabled do
      # Initial poll after a short delay to let supervision tree settle
      Process.send_after(self(), :poll_temperature, 1_000)
      Process.send_after(self(), :poll_spare, 2_000)
      Process.send_after(self(), :poll_deltas, 3_000)
    end

    {:ok, state}
  end

  @impl true
  def handle_call(:health_snapshot, _from, state) do
    {:reply, state.last_readings, state}
  end

  @impl true
  def handle_call(:weather_category, _from, state) do
    category = build_weather_category(state.last_readings)
    {:reply, category, state}
  end

  @impl true
  def handle_cast(:poll_now, state) do
    state = do_poll_all(state)
    {:noreply, state}
  end

  @impl true
  def handle_info(:poll_temperature, state) do
    state = do_poll_temperature(state)
    if state.enabled, do: Process.send_after(self(), :poll_temperature, @temp_poll_ms)
    {:noreply, state}
  end

  @impl true
  def handle_info(:poll_spare, state) do
    state = do_poll_spare(state)
    if state.enabled, do: Process.send_after(self(), :poll_spare, @spare_poll_ms)
    {:noreply, state}
  end

  @impl true
  def handle_info(:poll_deltas, state) do
    state = do_poll_deltas(state)
    if state.enabled, do: Process.send_after(self(), :poll_deltas, @delta_poll_ms)
    {:noreply, state}
  end

  # --- Polling Implementation ---

  defp do_poll_all(state) do
    state
    |> do_poll_temperature()
    |> do_poll_spare()
    |> do_poll_deltas()
  end

  defp do_poll_temperature(state) do
    devices = resolve_devices(state)

    readings =
      Enum.reduce(devices, state.last_readings, fn device, acc ->
        case read_smart_attribute(state.smartctl_path, device, "temperature") do
          {:ok, temp_c} ->
            Store.record("nvme_composite_temperature_celsius", temp_c,
              %{"device" => device}, source: @source, ttl: 60)

            threshold_state = evaluate_threshold(temp_c, @temp_warn_c, @temp_crit_c)

            if threshold_state != :calm do
              Correlator.record_event_async(:anomaly, @source, %{
                "metric" => "nvme_composite_temperature_celsius",
                "device" => device,
                "value" => temp_c,
                "state" => Atom.to_string(threshold_state)
              })
            end

            put_in(acc, [Access.key(device, %{}), :temperature_c], temp_c)

          {:error, reason} ->
            Logger.warning("NVMe sentinel: failed to read temperature for #{device}: #{inspect(reason)}")
            acc
        end
      end)

    %{state | last_readings: readings}
  end

  defp do_poll_spare(state) do
    devices = resolve_devices(state)

    readings =
      Enum.reduce(devices, state.last_readings, fn device, acc ->
        case read_smart_attribute(state.smartctl_path, device, "available_spare") do
          {:ok, spare_pct} ->
            Store.record("nvme_available_spare_percent", spare_pct,
              %{"device" => device}, source: @source, ttl: 7200)

            # Note: for spare, lower is worse, so thresholds are inverted
            threshold_state = evaluate_threshold_inverted(spare_pct, @spare_warn_pct, @spare_crit_pct)

            if threshold_state != :calm do
              Correlator.record_event_async(:anomaly, @source, %{
                "metric" => "nvme_available_spare_percent",
                "device" => device,
                "value" => spare_pct,
                "state" => Atom.to_string(threshold_state)
              })
            end

            put_in(acc, [Access.key(device, %{}), :available_spare_pct], spare_pct)

          {:error, reason} ->
            Logger.warning("NVMe sentinel: failed to read spare for #{device}: #{inspect(reason)}")
            acc
        end
      end)

    %{state | last_readings: readings}
  end

  defp do_poll_deltas(state) do
    devices = resolve_devices(state)

    {readings, baselines, accumulators} =
      Enum.reduce(devices, {state.last_readings, state.delta_baselines, state.delta_accumulators},
        fn device, {r_acc, b_acc, d_acc} ->
          {r_acc, b_acc, d_acc} =
            poll_media_errors(state.smartctl_path, device, r_acc, b_acc, d_acc)

          poll_unsafe_shutdowns(state.smartctl_path, device, r_acc, b_acc, d_acc)
        end)

    %{state | last_readings: readings, delta_baselines: baselines, delta_accumulators: accumulators}
  end

  defp poll_media_errors(smartctl_path, device, readings, baselines, accumulators) do
    case read_smart_attribute(smartctl_path, device, "media_errors") do
      {:ok, current_count} ->
        key = {device, :media_errors}
        now = System.monotonic_time(:millisecond)

        {delta_per_day, new_baselines} =
          case Map.get(baselines, key) do
            {prev_count, prev_time} ->
              elapsed_ms = now - prev_time
              delta = max(0, current_count - prev_count)
              # Extrapolate to per-day rate
              rate = if elapsed_ms > 0, do: delta / elapsed_ms * 86_400_000, else: 0.0
              {rate, Map.put(baselines, key, {current_count, now})}

            nil ->
              {0.0, Map.put(baselines, key, {current_count, now})}
          end

        Store.record("nvme_media_and_data_integrity_errors", current_count,
          %{"device" => device, "delta_per_day" => delta_per_day}, source: @source, ttl: 120)

        threshold_state =
          cond do
            delta_per_day >= @media_errors_crit_per_day -> :act
            delta_per_day >= @media_errors_warn_per_day -> :watch
            true -> :calm
          end

        if threshold_state != :calm do
          Correlator.record_event_async(:anomaly, @source, %{
            "metric" => "nvme_media_and_data_integrity_errors",
            "device" => device,
            "total" => current_count,
            "delta_per_day" => delta_per_day,
            "state" => Atom.to_string(threshold_state)
          })
        end

        new_readings = put_in(readings, [Access.key(device, %{}), :media_errors], current_count)
        {new_readings, new_baselines, accumulators}

      {:error, _reason} ->
        {readings, baselines, accumulators}
    end
  end

  defp poll_unsafe_shutdowns(smartctl_path, device, readings, baselines, accumulators) do
    case read_smart_attribute(smartctl_path, device, "unsafe_shutdowns") do
      {:ok, current_count} ->
        key = {device, :unsafe_shutdowns}
        now = System.monotonic_time(:millisecond)

        {delta_in_window, new_baselines, new_accumulators} =
          case Map.get(baselines, key) do
            {prev_count, prev_time} ->
              _elapsed_ms = now - prev_time
              delta = max(0, current_count - prev_count)

              # Accumulate deltas within the 24h window
              window_acc = Map.get(accumulators, key, {0, now})
              {window_delta, window_start} = window_acc

              {new_delta, new_start} =
                if now - window_start > @unsafe_shutdowns_window_ms do
                  # Reset window
                  {delta, now}
                else
                  {window_delta + delta, window_start}
                end

              new_b = Map.put(baselines, key, {current_count, now})
              new_a = Map.put(accumulators, key, {new_delta, new_start})
              {new_delta, new_b, new_a}

            nil ->
              new_b = Map.put(baselines, key, {current_count, now})
              new_a = Map.put(accumulators, key, {0, now})
              {0, new_b, new_a}
          end

        Store.record("nvme_unsafe_shutdowns_delta", delta_in_window,
          %{"device" => device, "total" => current_count}, source: @source, ttl: 120)

        threshold_state =
          cond do
            delta_in_window >= @unsafe_shutdowns_crit -> :act
            delta_in_window >= @unsafe_shutdowns_warn -> :watch
            true -> :calm
          end

        if threshold_state != :calm do
          Correlator.record_event_async(:anomaly, @source, %{
            "metric" => "nvme_unsafe_shutdowns_delta",
            "device" => device,
            "delta_24h" => delta_in_window,
            "total" => current_count,
            "state" => Atom.to_string(threshold_state)
          })
        end

        new_readings = put_in(readings, [Access.key(device, %{}), :unsafe_shutdowns], current_count)
        {new_readings, new_baselines, new_accumulators}

      {:error, _reason} ->
        {readings, baselines, accumulators}
    end
  end

  # --- SMART Data Access ---

  @doc false
  # Reads a SMART attribute from an NVMe device using smartctl.
  # Returns {:ok, numeric_value} or {:error, reason}.
  @spec read_smart_attribute(String.t(), String.t(), String.t()) ::
          {:ok, number()} | {:error, term()}
  def read_smart_attribute(smartctl_path, device, attribute) do
    # smartctl -A outputs SMART attributes in a parseable format
    # For NVMe, smartctl -a /dev/nvmeXnY --json gives JSON output
    case System.cmd(smartctl_path, ["-a", device, "--json"], stderr_to_stdout: true) do
      {output, 0} ->
        parse_smart_json(output, attribute)

      {output, exit_code} when exit_code in [1, 2, 4, 64] ->
        # smartctl returns non-zero for various warnings, but JSON may still be valid
        parse_smart_json(output, attribute)

      {output, exit_code} ->
        {:error, {:smartctl_failed, exit_code, String.slice(output, 0, 200)}}
    end
  rescue
    e in ErlangError ->
      {:error, {:command_not_found, smartctl_path, Exception.message(e)}}
  end

  defp parse_smart_json(json_str, attribute) do
    case Jason.decode(json_str) do
      {:ok, data} ->
        extract_nvme_attribute(data, attribute)

      {:error, reason} ->
        {:error, {:json_parse_failed, reason}}
    end
  end

  defp extract_nvme_attribute(data, "temperature") do
    case get_in(data, ["temperature", "current"]) do
      nil -> {:error, :attribute_not_found}
      value when is_number(value) -> {:ok, value}
      _ -> {:error, :unexpected_type}
    end
  end

  defp extract_nvme_attribute(data, "available_spare") do
    case get_in(data, ["nvme_smart_health_information_log", "available_spare"]) do
      nil -> {:error, :attribute_not_found}
      value when is_number(value) -> {:ok, value}
      _ -> {:error, :unexpected_type}
    end
  end

  defp extract_nvme_attribute(data, "media_errors") do
    case get_in(data, ["nvme_smart_health_information_log", "media_errors"]) do
      nil -> {:error, :attribute_not_found}
      value when is_number(value) -> {:ok, value}
      _ -> {:error, :unexpected_type}
    end
  end

  defp extract_nvme_attribute(data, "unsafe_shutdowns") do
    case get_in(data, ["nvme_smart_health_information_log", "unsafe_shutdowns"]) do
      nil -> {:error, :attribute_not_found}
      value when is_number(value) -> {:ok, value}
      _ -> {:error, :unexpected_type}
    end
  end

  defp extract_nvme_attribute(_data, attr) do
    {:error, {:unknown_attribute, attr}}
  end

  # --- Device Resolution ---

  defp resolve_devices(%{devices: [_ | _] = devices}), do: devices

  defp resolve_devices(_state) do
    # Auto-detect NVMe devices
    case System.cmd("ls", ["/dev/"], stderr_to_stdout: true) do
      {output, 0} ->
        output
        |> String.split("\n", trim: true)
        |> Enum.filter(&String.match?(&1, ~r/^nvme\d+n\d+$/))
        |> Enum.map(&("/dev/" <> &1))

      _ ->
        Logger.warning("NVMe sentinel: failed to detect NVMe devices")
        []
    end
  end

  # --- Threshold Evaluation ---

  # For metrics where higher is worse (temperature)
  defp evaluate_threshold(value, warn, crit) do
    cond do
      value >= crit -> :act
      value >= warn -> :watch
      true -> :calm
    end
  end

  # For metrics where lower is worse (available spare)
  defp evaluate_threshold_inverted(value, warn, crit) do
    cond do
      value <= crit -> :act
      value <= warn -> :watch
      true -> :calm
    end
  end

  # --- Weather Category Builder ---

  defp build_weather_category(readings) when map_size(readings) == 0 do
    %{
      "state" => "calm",
      "summary" => "No NVMe devices monitored",
      "metric_value" => 0,
      "metric_unit" => "devices"
    }
  end

  defp build_weather_category(readings) do
    # Aggregate worst state across all devices
    states =
      readings
      |> Enum.flat_map(fn {_device, attrs} ->
        temp = Map.get(attrs, :temperature_c, 0)
        spare = Map.get(attrs, :available_spare_pct, 100)

        [
          evaluate_threshold(temp, @temp_warn_c, @temp_crit_c),
          evaluate_threshold_inverted(spare, @spare_warn_pct, @spare_crit_pct)
        ]
      end)

    worst =
      cond do
        :act in states -> :act
        :watch in states -> :watch
        true -> :calm
      end

    device_count = map_size(readings)

    summary =
      case worst do
        :calm -> "#{device_count} NVMe device(s) healthy"
        :watch -> "#{device_count} NVMe device(s), some metrics elevated"
        :act -> "#{device_count} NVMe device(s), critical threshold crossed"
      end

    %{
      "state" => Atom.to_string(worst),
      "summary" => summary,
      "metric_value" => device_count,
      "metric_unit" => "devices"
    }
  end
end

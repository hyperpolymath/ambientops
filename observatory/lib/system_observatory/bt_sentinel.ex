# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule SystemObservatory.BtSentinel do
  @moduledoc """
  Bluetooth A2DP/SCO profile-switch sentinel.

  Monitors Bluetooth audio profile switches by polling `bluetoothctl info`
  at regular intervals. When the A2DP profile switch rate exceeds thresholds,
  emits Correlator events and generates a weather category for
  SystemObservatory.Weather.

  ## Approach

  Polls `bluetoothctl info` for each connected device to detect profile
  changes (A2DP-sink vs HFP/HSP-AG). When a device's active profile differs
  from the last-seen profile, a switch event is recorded in a sliding
  1-hour window.

  ## Thresholds (from STATE.a2ml, CC-005)

  - Warning: >= 5 profile switches per hour
  - Critical: >= 10 profile switches per hour

  ## Author

  Jonathan D.A. Jewell
  """

  use GenServer

  require Logger

  # --- Thresholds (from STATE.a2ml observatory-thresholds.bluetooth-profile-switches) ---

  @bt_profile_switch_warn_per_hour 5
  @bt_profile_switch_crit_per_hour 10
  @poll_interval_ms 300_000

  @source "bt-sentinel"

  # --- Client API ---

  @doc """
  Start the Bluetooth sentinel.

  ## Options

  - `:enabled` - Whether to start monitoring (default: true)
  - `:poll_interval_ms` - Override the default polling interval (default: 300_000)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get the current profile switch count within the sliding window.
  """
  @spec switch_count() :: non_neg_integer()
  def switch_count do
    GenServer.call(__MODULE__, :switch_count)
  end

  @doc """
  Get the current weather category for integration with SystemObservatory.Weather.

  Returns a map conforming to the weather category schema with state,
  summary, metric_value, and metric_unit fields.
  """
  @spec weather_category() :: map()
  def weather_category do
    GenServer.call(__MODULE__, :weather_category)
  end

  @doc """
  Get per-device profile snapshots (last-seen profile for each device).
  """
  @spec device_profiles() :: map()
  def device_profiles do
    GenServer.call(__MODULE__, :device_profiles)
  end

  # --- Server Callbacks ---

  @impl true
  def init(opts) do
    enabled = Keyword.get(opts, :enabled, true)
    poll_ms = Keyword.get(opts, :poll_interval_ms, @poll_interval_ms)

    state = %{
      enabled: enabled,
      poll_interval_ms: poll_ms,
      # Sliding window of {timestamp_ms, device_mac, from_profile, to_profile} tuples
      switch_events: [],
      # Map of device_mac => last_known_profile string
      device_profiles: %{},
      window_ms: 3_600_000,
      # Track last emitted threshold level to avoid duplicate Correlator events
      last_threshold: :calm
    }

    if enabled do
      Logger.info("BtSentinel: started — polling bluetoothctl every #{poll_ms}ms")
      # Schedule first poll immediately
      Process.send_after(self(), :poll_bluetooth, 0)
    else
      Logger.info("BtSentinel: disabled")
    end

    {:ok, state}
  end

  @impl true
  def handle_call(:switch_count, _from, state) do
    now = System.monotonic_time(:millisecond)
    count = count_in_window(state.switch_events, now, state.window_ms)
    {:reply, count, state}
  end

  @impl true
  def handle_call(:weather_category, _from, state) do
    now = System.monotonic_time(:millisecond)
    count = count_in_window(state.switch_events, now, state.window_ms)
    category = build_weather_category(count)
    {:reply, category, state}
  end

  @impl true
  def handle_call(:device_profiles, _from, state) do
    {:reply, state.device_profiles, state}
  end

  @impl true
  def handle_info(:poll_bluetooth, %{enabled: false} = state) do
    # Sentinel disabled mid-flight; stop polling.
    {:noreply, state}
  end

  @impl true
  def handle_info(:poll_bluetooth, state) do
    new_state =
      case poll_connected_devices() do
        {:ok, device_snapshots} ->
          process_snapshots(state, device_snapshots)

        {:error, reason} ->
          Logger.debug("BtSentinel: bluetoothctl poll failed — #{inspect(reason)}")
          state
      end

    # Schedule next poll
    Process.send_after(self(), :poll_bluetooth, state.poll_interval_ms)
    {:noreply, new_state}
  end

  # --- Polling Logic ---

  # Queries bluetoothctl for connected devices and their active profiles.
  # Returns a list of {mac_address, active_profile} tuples.
  @spec poll_connected_devices() ::
          {:ok, [{String.t(), String.t()}]} | {:error, term()}
  defp poll_connected_devices do
    case System.cmd("bluetoothctl", ["devices", "Connected"], stderr_to_stdout: true) do
      {output, 0} ->
        macs = parse_device_macs(output)
        snapshots = Enum.flat_map(macs, &query_device_profile/1)
        {:ok, snapshots}

      {output, code} ->
        {:error, {:bluetoothctl_exit, code, output}}
    end
  rescue
    e in ErlangError ->
      {:error, {:bluetoothctl_not_found, e}}
  end

  # Parses `bluetoothctl devices Connected` output.
  # Each line looks like: "Device AA:BB:CC:DD:EE:FF Device Name"
  @spec parse_device_macs(String.t()) :: [String.t()]
  defp parse_device_macs(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.flat_map(fn line ->
      case Regex.run(~r/^Device\s+([0-9A-Fa-f:]{17})\s+/, line) do
        [_, mac] -> [mac]
        _ -> []
      end
    end)
  end

  # Queries `bluetoothctl info <mac>` for the active audio profile.
  # Returns [{mac, profile}] or [] if no audio profile is active.
  @spec query_device_profile(String.t()) :: [{String.t(), String.t()}]
  defp query_device_profile(mac) do
    case System.cmd("bluetoothctl", ["info", mac], stderr_to_stdout: true) do
      {output, 0} ->
        profile = extract_audio_profile(output)
        if profile, do: [{mac, profile}], else: []

      _ ->
        []
    end
  rescue
    _ -> []
  end

  # Extracts the active audio profile from `bluetoothctl info` output.
  # Looks for UUID lines indicating A2DP Sink, HFP, HSP, or SCO profiles.
  # Returns the highest-priority audio profile string or nil.
  @spec extract_audio_profile(String.t()) :: String.t() | nil
  defp extract_audio_profile(output) do
    lines = String.split(output, "\n", trim: true)

    # Check for A2DP sink (high-quality audio)
    has_a2dp_sink =
      Enum.any?(lines, fn line ->
        String.contains?(line, "AudioSink") or
          String.contains?(line, "0000110b-0000-1000-8000-00805f9b34fb")
      end)

    # Check for HFP/HSP (telephony/SCO audio)
    has_hfp =
      Enum.any?(lines, fn line ->
        String.contains?(line, "HandsfreeGateway") or
          String.contains?(line, "Handsfree") or
          String.contains?(line, "0000111f-0000-1000-8000-00805f9b34fb") or
          String.contains?(line, "0000111e-0000-1000-8000-00805f9b34fb") or
          String.contains?(line, "HeadsetGateway") or
          String.contains?(line, "0000111a-0000-1000-8000-00805f9b34fb") or
          String.contains?(line, "Headset") or
          String.contains?(line, "0000110d-0000-1000-8000-00805f9b34fb")
      end)

    # Determine the active profile — A2DP and HFP are mutually exclusive
    # for audio output, so we detect which one is currently in use.
    # The "Connected" line with profile info or UUIDs determines this.
    cond do
      has_a2dp_sink and not has_hfp -> "a2dp-sink"
      has_hfp and not has_a2dp_sink -> "hfp-ag"
      has_a2dp_sink and has_hfp -> detect_active_from_output(output)
      true -> nil
    end
  end

  # When both A2DP and HFP UUIDs are present (common for headsets),
  # check which transport is actually active.
  @spec detect_active_from_output(String.t()) :: String.t()
  defp detect_active_from_output(output) do
    # If the output mentions an active audio transport, use that.
    # BlueZ typically shows the active profile via the "ServicesResolved" and
    # connected profile indicators. As a heuristic, check if A2DP transport
    # keywords appear in the output.
    cond do
      String.contains?(output, "a2dp") -> "a2dp-sink"
      String.contains?(output, "A2DP") -> "a2dp-sink"
      String.contains?(output, "hfp") -> "hfp-ag"
      String.contains?(output, "HFP") -> "hfp-ag"
      String.contains?(output, "sco") -> "hfp-ag"
      # Default to A2DP if both UUIDs present but no clear indicator
      true -> "a2dp-sink"
    end
  end

  # --- Snapshot Processing ---

  # Compares new device profiles against last-known state, records
  # switch events, and emits Correlator events on threshold breach.
  @spec process_snapshots(map(), [{String.t(), String.t()}]) :: map()
  defp process_snapshots(state, device_snapshots) do
    now = System.monotonic_time(:millisecond)

    # Detect profile switches by comparing against last-known profiles
    {new_events, updated_profiles} =
      Enum.reduce(device_snapshots, {[], state.device_profiles}, fn {mac, profile},
                                                                     {events_acc, profiles_acc} ->
        case Map.get(profiles_acc, mac) do
          nil ->
            # First time seeing this device — record profile, no switch event
            {events_acc, Map.put(profiles_acc, mac, profile)}

          ^profile ->
            # Same profile as before — no switch
            {events_acc, profiles_acc}

          old_profile ->
            # Profile changed — record a switch event
            event = {now, mac, old_profile, profile}
            Logger.info("BtSentinel: profile switch on #{mac}: #{old_profile} -> #{profile}")
            {[event | events_acc], Map.put(profiles_acc, mac, profile)}
        end
      end)

    # Merge new events into the sliding window and prune expired entries
    all_events = prune_window(new_events ++ state.switch_events, now, state.window_ms)

    # Evaluate threshold and emit Correlator events if state changed
    count = length(all_events)
    current_threshold = evaluate_threshold(count)
    new_state = maybe_emit_correlator_event(state, current_threshold, count)

    %{
      new_state
      | switch_events: all_events,
        device_profiles: updated_profiles,
        last_threshold: current_threshold
    }
  end

  # --- Threshold & Correlator Integration ---

  # Emits a Correlator event when the threshold level transitions upward.
  @spec maybe_emit_correlator_event(map(), :calm | :watch | :act, non_neg_integer()) :: map()
  defp maybe_emit_correlator_event(state, current_threshold, count) do
    severity_rank = %{calm: 0, watch: 1, act: 2}

    if Map.get(severity_rank, current_threshold, 0) >
         Map.get(severity_rank, state.last_threshold, 0) do
      # Threshold escalated — emit Correlator anomaly event
      try do
        SystemObservatory.Correlator.record_event(
          :anomaly,
          @source,
          %{
            threshold: current_threshold,
            switch_count: count,
            window_hours: 1,
            message:
              "Bluetooth profile switch rate #{threshold_label(current_threshold)}: #{count} switches/hour"
          }
        )

        Logger.warning(
          "BtSentinel: threshold escalated to #{current_threshold} (#{count} switches/hour)"
        )
      rescue
        _ ->
          Logger.debug(
            "BtSentinel: Correlator not available, skipping event emission"
          )
      end
    end

    state
  end

  # Human-readable threshold label for log messages.
  @spec threshold_label(:calm | :watch | :act) :: String.t()
  defp threshold_label(:calm), do: "normal"
  defp threshold_label(:watch), do: "warning"
  defp threshold_label(:act), do: "critical"

  # --- Window Helpers ---

  # Prunes events older than the sliding window.
  @spec prune_window(list(), integer(), integer()) :: list()
  defp prune_window(events, now, window_ms) do
    cutoff = now - window_ms

    Enum.filter(events, fn
      {ts, _mac, _from, _to} -> ts >= cutoff
      {ts, _device} -> ts >= cutoff
    end)
  end

  # Counts events within the sliding window.
  @spec count_in_window(list(), integer(), integer()) :: non_neg_integer()
  defp count_in_window(events, now, window_ms) do
    cutoff = now - window_ms

    events
    |> Enum.filter(fn
      {ts, _mac, _from, _to} -> ts >= cutoff
      {ts, _device} -> ts >= cutoff
    end)
    |> length()
  end

  # Builds a weather category map for integration with SystemObservatory.Weather.
  @spec build_weather_category(non_neg_integer()) :: map()
  defp build_weather_category(count) do
    threshold = evaluate_threshold(count)

    summary =
      case threshold do
        :calm -> "Bluetooth audio stable: #{count} profile switches/hour"
        :watch -> "Elevated Bluetooth profile switching: #{count}/hour"
        :act -> "Critical Bluetooth instability: #{count} profile switches/hour"
      end

    %{
      "state" => Atom.to_string(threshold),
      "summary" => summary,
      "metric_value" => count,
      "metric_unit" => "switches/hour",
      "threshold_warning" => @bt_profile_switch_warn_per_hour,
      "threshold_critical" => @bt_profile_switch_crit_per_hour
    }
  end

  # Evaluates threshold state from a count.
  @doc false
  @spec evaluate_threshold(non_neg_integer()) :: :calm | :watch | :act
  def evaluate_threshold(count) do
    cond do
      count >= @bt_profile_switch_crit_per_hour -> :act
      count >= @bt_profile_switch_warn_per_hour -> :watch
      true -> :calm
    end
  end

  # Returns threshold configuration for introspection and testing.
  @doc false
  def thresholds do
    %{
      warn: @bt_profile_switch_warn_per_hour,
      crit: @bt_profile_switch_crit_per_hour,
      poll_ms: @poll_interval_ms,
      source: @source
    }
  end
end

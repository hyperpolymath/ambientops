# SPDX-License-Identifier: MPL-2.0

defmodule ServiceAutopsy.Watcher do
  @moduledoc """
  Watches for systemd service failures and triggers autopsy collection.

  Uses `journalctl --follow` to monitor for service failure messages
  in real time. When a failure is detected, collects crash context
  (journal entries, coredump info, D-Bus state, dependency graph)
  and produces a structured autopsy report conforming to
  evidence-envelope.schema.json.

  ## Monitored Events

  - `systemd_boot_duration_seconds`: warn 120s, crit 300s
  - `systemd_service_restart_count`: warn 3, crit 5, per 5min

  ## CRITICAL: Advisory Data Only (CRIT-003 compliance)

  Autopsy reports are observational records. They capture what happened
  but do NOT take remedial action. The Operating Theatre decides if/how
  to act on these reports.

  ## Author

  Jonathan D.A. Jewell
  """

  use GenServer

  require Logger

  alias ServiceAutopsy.Collector
  alias ServiceAutopsy.ReportStore

  @source "service-autopsy"

  # Restart tracking window: 5 minutes
  @restart_window_ms 300_000
  @restart_warn_count 3
  @restart_crit_count 5

  # Boot duration thresholds
  @boot_warn_seconds 120
  @boot_crit_seconds 300

  # Poll interval for checking journal (fallback if --follow unavailable)
  @poll_interval_ms 10_000

  # --- Client API ---

  @doc """
  Start the service failure watcher.

  ## Options

  - `:enabled` - Whether to start watching (default: true)
  - `:units` - List of specific unit names to watch (default: all)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get summary of recent service failures.
  """
  @spec recent_failures() :: [map()]
  def recent_failures do
    GenServer.call(__MODULE__, :recent_failures)
  end

  @doc """
  Manually trigger an autopsy for a specific unit.
  """
  @spec autopsy(String.t()) :: {:ok, map()} | {:error, term()}
  def autopsy(unit_name) do
    GenServer.call(__MODULE__, {:autopsy, unit_name}, 30_000)
  end

  # --- Server Callbacks ---

  @impl true
  def init(opts) do
    enabled = Keyword.get(opts, :enabled, true)
    units = Keyword.get(opts, :units, [])

    state = %{
      enabled: enabled,
      units: units,
      # Track restart counts: %{unit_name => [{timestamp_ms, ...}]}
      restart_tracker: %{},
      # Recent failure unit names for deduplication
      recent_units: [],
      # Port for journalctl --follow (if available)
      journal_port: nil
    }

    if enabled do
      Process.send_after(self(), :start_watching, 2_000)
      Process.send_after(self(), :check_boot_duration, 5_000)
    end

    {:ok, state}
  end

  @impl true
  def handle_call(:recent_failures, _from, state) do
    reports = ReportStore.recent(10)
    {:reply, reports, state}
  end

  @impl true
  def handle_call({:autopsy, unit_name}, _from, state) do
    case Collector.collect(unit_name) do
      {:ok, report} ->
        ReportStore.store(report)
        {:reply, {:ok, report}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_info(:start_watching, state) do
    state = start_journal_watch(state)
    {:noreply, state}
  end

  @impl true
  def handle_info(:check_boot_duration, state) do
    check_boot_duration()
    {:noreply, state}
  end

  @impl true
  def handle_info(:poll_journal, state) do
    state = poll_journal_failures(state)
    if state.enabled, do: Process.send_after(self(), :poll_journal, @poll_interval_ms)
    {:noreply, state}
  end

  @impl true
  def handle_info({_port, {:data, line}}, state) when is_binary(line) do
    state = process_journal_line(String.trim(line), state)
    {:noreply, state}
  end

  @impl true
  def handle_info({_port, {:data, {:eol, line}}}, state) do
    state = process_journal_line(to_string(line), state)
    {:noreply, state}
  end

  @impl true
  def handle_info({_port, {:exit_status, _status}}, state) do
    Logger.warning("#{@source}: journalctl process exited, falling back to polling")
    Process.send_after(self(), :poll_journal, @poll_interval_ms)
    {:noreply, %{state | journal_port: nil}}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # --- Journal Watching ---

  defp start_journal_watch(state) do
    # Try to start journalctl --follow for real-time monitoring
    args = [
      "--follow",
      "--no-pager",
      "--output=short",
      "--priority=err",
      # Only systemd messages about unit failures
      "_SYSTEMD_UNIT=init.scope",
      "UNIT=*"
    ]

    try do
      port = Port.open(
        {:spawn_executable, System.find_executable("journalctl") || "/usr/bin/journalctl"},
        [:binary, :exit_status, {:line, 4096}, {:args, args}]
      )
      Logger.info("#{@source}: watching journal for service failures")
      %{state | journal_port: port}
    rescue
      _ ->
        Logger.warning("#{@source}: journalctl --follow unavailable, falling back to polling")
        Process.send_after(self(), :poll_journal, @poll_interval_ms)
        state
    end
  end

  defp process_journal_line(line, state) do
    # Look for systemd failure patterns
    cond do
      String.contains?(line, "Failed to start") or
        String.contains?(line, "entered failed state") or
        String.contains?(line, "Main process exited, code=exited, status=") ->
        case extract_unit_name(line) do
          {:ok, unit_name} ->
            handle_service_failure(unit_name, line, state)

          :error ->
            state
        end

      true ->
        state
    end
  end

  defp poll_journal_failures(state) do
    # Check for recent failures via journalctl query
    since = "5min ago"
    args = [
      "--since", since,
      "--no-pager",
      "--output=short",
      "--priority=err",
      "--grep=Failed to start|entered failed state|code=exited"
    ]

    case System.cmd("journalctl", args, stderr_to_stdout: true) do
      {output, _exit_code} ->
        output
        |> String.split("\n", trim: true)
        |> Enum.reduce(state, &process_journal_line/2)

      _ ->
        state
    end
  rescue
    _ -> state
  end

  defp extract_unit_name(line) do
    # Match patterns like "unit_name.service" in journal output
    case Regex.run(~r/(\S+\.service)/, line) do
      [_, unit_name] -> {:ok, unit_name}
      _ -> :error
    end
  end

  defp handle_service_failure(unit_name, line, state) do
    now = System.monotonic_time(:millisecond)

    # Update restart tracker
    tracker = state.restart_tracker
    timestamps = Map.get(tracker, unit_name, [])
    # Prune old entries outside the window
    recent = Enum.filter(timestamps, fn ts -> now - ts < @restart_window_ms end)
    updated = [now | recent]
    tracker = Map.put(tracker, unit_name, updated)

    restart_count = length(updated)

    Logger.info("#{@source}: service failure detected: #{unit_name} (#{restart_count} in window)")

    # Evaluate restart threshold
    _threshold_state =
      cond do
        restart_count >= @restart_crit_count ->
          Logger.error("#{@source}: CRITICAL - #{unit_name} restarted #{restart_count} times in 5min")
          :act

        restart_count >= @restart_warn_count ->
          Logger.warning("#{@source}: WARNING - #{unit_name} restarted #{restart_count} times in 5min")
          :watch

        true ->
          :calm
      end

    # Trigger autopsy collection (async to avoid blocking the watcher)
    Task.start(fn ->
      case Collector.collect(unit_name) do
        {:ok, report} ->
          report = Map.put(report, "trigger_line", line)
          report = Map.put(report, "restart_count_in_window", restart_count)
          ReportStore.store(report)

        {:error, reason} ->
          Logger.warning("#{@source}: failed to collect autopsy for #{unit_name}: #{inspect(reason)}")
      end
    end)

    %{state | restart_tracker: tracker}
  end

  # --- Boot Duration Check ---

  defp check_boot_duration do
    case System.cmd("systemd-analyze", ["time"], stderr_to_stdout: true) do
      {output, 0} ->
        case Regex.run(~r/= ([\d.]+)s/, output) do
          [_, seconds_str] ->
            {seconds, _} = Float.parse(seconds_str)
            Logger.info("#{@source}: boot duration: #{seconds}s")

            _threshold_state =
              cond do
                seconds >= @boot_crit_seconds ->
                  Logger.error("#{@source}: CRITICAL - boot took #{seconds}s (threshold: #{@boot_crit_seconds}s)")
                  :act

                seconds >= @boot_warn_seconds ->
                  Logger.warning("#{@source}: WARNING - boot took #{seconds}s (threshold: #{@boot_warn_seconds}s)")
                  :watch

                true ->
                  :calm
              end

          _ ->
            Logger.debug("#{@source}: could not parse boot duration from: #{String.slice(output, 0, 100)}")
        end

      {_output, _code} ->
        Logger.debug("#{@source}: systemd-analyze not available")
    end
  rescue
    _ -> Logger.debug("#{@source}: systemd-analyze command failed")
  end
end

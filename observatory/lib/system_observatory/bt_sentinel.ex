# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule SystemObservatory.BtSentinel do
  @moduledoc """
  WirePlumber Bluetooth A2DP profile-switch sentinel.

  Monitors Bluetooth audio profile switches via WirePlumber's D-Bus interface.
  When the A2DP profile switch rate exceeds thresholds, emits correlator events
  and updates system-weather category.

  ## Thresholds (from STATE.a2ml, CC-005)

  - Warning: >= 5 profile switches per hour
  - Critical: >= 10 profile switches per hour

  ## Status

  STUB — not yet added to supervision tree.

  TODO: implement WirePlumber D-Bus monitoring
    - Subscribe to org.freedesktop.DBus for WirePlumber property changes
    - Filter for BlueZ A2DP/SCO profile transitions
    - Track per-device switch counts within sliding 1-hour windows
    - Emit Correlator events on threshold breach
    - Feed weather_category into SystemObservatory.Weather

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

  NOT added to supervision tree yet — call manually for testing.

  ## Options

  - `:enabled` - Whether to start monitoring (default: true)
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

  # --- Server Callbacks ---

  @impl true
  def init(opts) do
    enabled = Keyword.get(opts, :enabled, true)

    state = %{
      enabled: enabled,
      # Sliding window of {timestamp_ms, device_id} tuples
      switch_events: [],
      window_ms: 3_600_000
    }

    if enabled do
      Logger.info("BtSentinel: started (stub — D-Bus monitoring not yet implemented)")
      # TODO: subscribe to WirePlumber D-Bus signals here
      # Process.send_after(self(), :poll_dbus, @poll_interval_ms)
    end

    {:ok, state}
  end

  @impl true
  def handle_call(:switch_count, _from, state) do
    now = System.monotonic_time(:millisecond)
    count = count_in_window(state.switch_events, now, state.window_ms)
    {:reply, count, state}
  end

  # --- Internal Helpers ---

  # Counts events within the sliding window.
  defp count_in_window(events, now, window_ms) do
    cutoff = now - window_ms

    events
    |> Enum.filter(fn {ts, _device} -> ts >= cutoff end)
    |> length()
  end

  # Placeholder: evaluates threshold state from a count.
  # Called when D-Bus monitoring is wired up.
  @doc false
  @spec evaluate_threshold(non_neg_integer()) :: :calm | :watch | :act
  def evaluate_threshold(count) do
    cond do
      count >= @bt_profile_switch_crit_per_hour -> :act
      count >= @bt_profile_switch_warn_per_hour -> :watch
      true -> :calm
    end
  end

  # Suppress unused attribute warnings — these are used by evaluate_threshold/1
  # and will be used by the D-Bus monitor once implemented.
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

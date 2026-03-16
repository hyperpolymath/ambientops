# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule SystemObservatory.Correlator do
  @moduledoc """
  Event correlator for change timeline.

  Correlates system events with recent changes to identify
  potential causes of anomalies.

  ## Race Condition Prevention (CRIT-001 fix)

  All operations are synchronous (handle_call) to prevent race conditions
  where events recorded via async cast could be missed during correlation
  calculations. This trades throughput for consistency - appropriate for
  an observability system where correctness matters more than speed.
  """

  use GenServer

  @type event :: %{
          id: String.t(),
          type: :change | :anomaly | :metric,
          timestamp: DateTime.t(),
          source: String.t(),
          data: map()
        }

  @type correlation :: %{
          anomaly: event(),
          related_changes: [event()],
          confidence: float(),
          calculated_at: DateTime.t()
        }

  @type state :: %{
          events: [event()],
          max_events: non_neg_integer(),
          correlation_window_seconds: non_neg_integer()
        }

  @default_max_events 1_000
  @default_window_seconds 3600

  # Client API

  @doc """
  Start the correlator.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Record an event (change or anomaly).

  This is synchronous to prevent race conditions - the caller blocks until
  the event is recorded. Use `record_event_async/3` if fire-and-forget is needed.
  """
  @spec record_event(atom(), String.t(), map()) :: {:ok, String.t()}
  def record_event(type, source, data) when type in [:change, :anomaly, :metric] do
    GenServer.call(__MODULE__, {:record, type, source, data})
  end

  @doc """
  Record an event asynchronously (fire-and-forget).

  WARNING: Events recorded this way may not be included in correlation
  calculations that run concurrently. Use `record_event/3` for consistency.
  """
  @spec record_event_async(atom(), String.t(), map()) :: :ok
  def record_event_async(type, source, data) when type in [:change, :anomaly, :metric] do
    GenServer.cast(__MODULE__, {:record, type, source, data})
  end

  @doc """
  Find correlations for recent anomalies.
  """
  @spec find_correlations() :: [correlation()]
  def find_correlations do
    GenServer.call(__MODULE__, :correlate)
  end

  @doc """
  Get all events.
  """
  @spec all_events() :: [event()]
  def all_events do
    GenServer.call(__MODULE__, :all)
  end

  @doc """
  Clear all events.
  """
  @spec clear() :: :ok
  def clear do
    GenServer.call(__MODULE__, :clear)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    {:ok,
     %{
       events: [],
       max_events: Keyword.get(opts, :max_events, @default_max_events),
       correlation_window_seconds: Keyword.get(opts, :window, @default_window_seconds)
     }}
  end

  # Group all handle_call clauses together
  @impl true
  def handle_call({:record, type, source, data}, _from, state) do
    event = %{
      id: generate_id(),
      type: type,
      timestamp: DateTime.utc_now(),
      source: source,
      data: data
    }

    events = [event | state.events] |> Enum.take(state.max_events)
    {:reply, {:ok, event.id}, %{state | events: events}}
  end

  @impl true
  def handle_call(:correlate, _from, state) do
    # Take a snapshot of events for consistent correlation calculation
    correlations = build_correlations(state.events, state.correlation_window_seconds)
    {:reply, correlations, state}
  end

  @impl true
  def handle_call(:all, _from, state) do
    {:reply, Enum.reverse(state.events), state}
  end

  @impl true
  def handle_call(:clear, _from, state) do
    {:reply, :ok, %{state | events: []}}
  end

  # handle_cast for async recording (use with caution - see module docs)
  @impl true
  def handle_cast({:record, type, source, data}, state) do
    event = %{
      id: generate_id(),
      type: type,
      timestamp: DateTime.utc_now(),
      source: source,
      data: data
    }

    events = [event | state.events] |> Enum.take(state.max_events)
    {:noreply, %{state | events: events}}
  end

  # Private Functions

  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
  end

  defp build_correlations(events, window_seconds) do
    calculated_at = DateTime.utc_now()
    anomalies = Enum.filter(events, fn e -> e.type == :anomaly end)
    changes = Enum.filter(events, fn e -> e.type == :change end)

    Enum.map(anomalies, fn anomaly ->
      related =
        changes
        |> Enum.filter(fn change ->
          diff = DateTime.diff(anomaly.timestamp, change.timestamp, :second)
          diff >= 0 and diff <= window_seconds
        end)
        |> Enum.sort_by(fn change ->
          DateTime.diff(anomaly.timestamp, change.timestamp, :second)
        end)

      %{
        anomaly: anomaly,
        related_changes: related,
        confidence: calculate_confidence(related, anomaly, window_seconds),
        calculated_at: calculated_at
      }
    end)
  end

  # CRIT-001/HIGH-006 fix: Corrected confidence scoring
  # Confidence INCREASES with:
  # - More correlated changes (up to a point - suggests causation)
  # - Temporal proximity (changes closer in time to anomaly are more suspect)
  # - Fewer total changes (noise floor consideration)
  defp calculate_confidence([], _anomaly, _window), do: 0.0

  defp calculate_confidence(related_changes, anomaly, window_seconds) do
    # Base confidence from having related changes
    count = length(related_changes)
    base_confidence = min(0.6, count * 0.2)

    # Temporal proximity bonus: closest change gets higher weight
    closest_change = List.first(related_changes)
    time_diff = DateTime.diff(anomaly.timestamp, closest_change.timestamp, :second)
    proximity_factor = 1.0 - (time_diff / window_seconds)
    proximity_bonus = proximity_factor * 0.3

    # Cap at 0.95 - never claim 100% confidence
    min(0.95, base_confidence + proximity_bonus)
  end
end

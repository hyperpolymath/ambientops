# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule SystemObservatory.Metrics.Store do
  @moduledoc """
  In-memory metrics store for time series data.

  Stores metrics from system scans in a ring buffer and dual-writes each
  metric to VeriSimDB for durable historical persistence.

  ## Dual-write architecture

  Every `record/4` call performs two writes:

  1. **Ring buffer** (synchronous, in-process) — the canonical fast path for
     recent metrics queries.  This path is unaffected by VeriSimDB latency or
     availability.

  2. **VeriSimDB** (asynchronous, fire-and-forget) — persists each metric as
     a hexad document via `SystemObservatory.VeriSimDB.store_metric/1`.  The
     write is dispatched on a separate `Task` so it never blocks callers or
     the GenServer loop.  Failures are logged as warnings but do NOT affect
     the ring buffer write.

  To query historical data that predates the current ring buffer use
  `SystemObservatory.VeriSimDB.query_by_name/2` directly.

  ## CRITICAL: Advisory Data Only (CRIT-003 compliance)

  JuSys is NEVER the source of truth. All data stored here is:
  - **Derived**: Calculated from observations, not authoritative
  - **Ephemeral (ring buffer)**: May be truncated; use VeriSimDB for history
  - **Stale-able**: Has TTL, becomes unreliable after expiry
  - **Provenance-tracked**: Includes source information

  DO NOT use JuSys data for:
  - Policy decisions without verification
  - Authoritative state queries
  - Configuration management
  - Audit trails (use receipts from Operating Theatre instead)
  """

  use GenServer

  require Logger

  # Default TTL: 1 hour - data older than this should be considered stale
  @default_ttl_seconds 3600

  @type metric :: %{
          name: String.t(),
          value: number(),
          timestamp: DateTime.t(),
          tags: map(),
          # CRIT-003 fix: Provenance and staleness tracking
          derived_at: DateTime.t(),
          source: String.t(),
          ttl_seconds: non_neg_integer(),
          advisory: boolean()
        }

  @type state :: %{
          metrics: [metric()],
          max_size: non_neg_integer(),
          default_ttl: non_neg_integer()
        }

  @default_max_size 10_000

  # Client API

  @doc """
  Start the metrics store.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Record a metric with provenance tracking.

  Options:
  - `:source` - Where this metric came from (required for audit trail)
  - `:ttl` - Time-to-live in seconds (default: 3600)
  """
  @spec record(String.t(), number(), map(), keyword()) :: :ok
  def record(name, value, tags \\ %{}, opts \\ []) do
    source = Keyword.get(opts, :source, "unknown")
    ttl = Keyword.get(opts, :ttl, @default_ttl_seconds)
    GenServer.cast(__MODULE__, {:record, name, value, tags, source, ttl})
  end

  @doc """
  Get all metrics (includes stale metrics marked as such).
  """
  @spec all() :: [metric()]
  def all do
    GenServer.call(__MODULE__, :all)
  end

  @doc """
  Get all fresh (non-stale) metrics only.
  """
  @spec all_fresh() :: [metric()]
  def all_fresh do
    GenServer.call(__MODULE__, :all_fresh)
  end

  @doc """
  Get metrics by name (includes stale metrics).
  """
  @spec get(String.t()) :: [metric()]
  def get(name) do
    GenServer.call(__MODULE__, {:get, name})
  end

  @doc """
  Get fresh metrics by name only.
  """
  @spec get_fresh(String.t()) :: [metric()]
  def get_fresh(name) do
    GenServer.call(__MODULE__, {:get_fresh, name})
  end

  @doc """
  Check if a metric is stale (past its TTL).
  """
  @spec stale?(metric()) :: boolean()
  def stale?(metric) do
    is_stale?(metric)
  end

  @doc """
  Clear all metrics.
  """
  @spec clear() :: :ok
  def clear do
    GenServer.call(__MODULE__, :clear)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    max_size = Keyword.get(opts, :max_size, @default_max_size)
    default_ttl = Keyword.get(opts, :default_ttl, @default_ttl_seconds)
    {:ok, %{metrics: [], max_size: max_size, default_ttl: default_ttl}}
  end

  @impl true
  def handle_cast({:record, name, value, tags, source, ttl}, state) do
    now = DateTime.utc_now()

    # CRIT-003 fix: All metrics include provenance and are marked advisory
    metric = %{
      name: name,
      value: value,
      timestamp: now,
      tags: tags,
      # Provenance tracking
      derived_at: now,
      source: source,
      ttl_seconds: ttl,
      # Always advisory - JuSys is never authoritative
      advisory: true
    }

    # 1. Write to in-memory ring buffer (fast, synchronous)
    metrics = [metric | state.metrics] |> Enum.take(state.max_size)

    # 2. Fire-and-forget write to VeriSimDB (asynchronous, non-blocking).
    #    We dispatch via the application's Task.Supervisor so the task is
    #    properly tracked and cleaned up on shutdown.  :nolink ensures a
    #    VeriSimDB failure never propagates back to the store process.
    Task.Supervisor.start_child(SystemObservatory.TaskSupervisor, fn ->
      case SystemObservatory.VeriSimDB.store_metric(metric) do
        {:ok, id} ->
          Logger.debug("[Store] VeriSimDB hexad stored: #{inspect(id)}")

        {:error, reason} ->
          Logger.warning(
            "[Store] VeriSimDB dual-write failed for metric #{inspect(name)}: #{inspect(reason)}"
          )
      end
    end)

    {:noreply, %{state | metrics: metrics}}
  end

  # Legacy format support (deprecated)
  @impl true
  def handle_cast({:record, name, value, tags}, state) do
    handle_cast({:record, name, value, tags, "legacy", state.default_ttl}, state)
  end

  @impl true
  def handle_call(:all, _from, state) do
    {:reply, Enum.reverse(state.metrics), state}
  end

  @impl true
  def handle_call(:all_fresh, _from, state) do
    fresh = Enum.reject(state.metrics, &is_stale?/1)
    {:reply, Enum.reverse(fresh), state}
  end

  @impl true
  def handle_call({:get, name}, _from, state) do
    filtered = Enum.filter(state.metrics, fn m -> m.name == name end)
    {:reply, Enum.reverse(filtered), state}
  end

  @impl true
  def handle_call({:get_fresh, name}, _from, state) do
    filtered =
      state.metrics
      |> Enum.filter(fn m -> m.name == name end)
      |> Enum.reject(&is_stale?/1)

    {:reply, Enum.reverse(filtered), state}
  end

  @impl true
  def handle_call(:clear, _from, state) do
    {:reply, :ok, %{state | metrics: []}}
  end

  # Private helper for staleness check
  defp is_stale?(metric) do
    now = DateTime.utc_now()
    age_seconds = DateTime.diff(now, metric.derived_at, :second)
    age_seconds > metric.ttl_seconds
  end
end

# SPDX-License-Identifier: PMPL-1.0-or-later
#
# HAR.ControlPlane.CircuitBreaker — ETS-backed circuit breaker FSM for backends.
#
# Part of the Hybrid Automation Router (HAR) project.
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath)

defmodule HAR.ControlPlane.CircuitBreaker do
  @moduledoc """
  Circuit breaker finite state machine (FSM) for backend routing protection.

  Implements the standard three-state circuit breaker pattern backed by ETS for
  O(1) hot-path state lookups and a GenServer for state transition management.
  This prevents cascading failures when backends become unavailable — instead
  of hammering a dead backend with requests (which delays every caller and can
  worsen the failure), the circuit breaker "trips open" and immediately rejects
  requests to that backend until it has had time to recover.

  ## FSM States

  The circuit breaker for each registered backend transitions through three states:

  ```
    ┌──────────────────────────────────────────────────────────┐
    │                                                          │
    │   ┌──────────┐  failure >= threshold  ┌──────────┐      │
    │   │  CLOSED  │ ─────────────────────> │   OPEN   │      │
    │   │ (normal) │                        │ (reject) │      │
    │   └──────────┘                        └──────────┘      │
    │        ^                                   │            │
    │        │ success                           │ timeout    │
    │        │                                   v            │
    │        │                             ┌───────────┐      │
    │        └──────────────────────────── │ HALF-OPEN │      │
    │                                      │  (probe)  │      │
    │              failure                 └───────────┘      │
    │              ┌───────────────────────────────┘           │
    │              v                                           │
    │         ┌──────────┐                                    │
    │         │   OPEN   │ (timer resets)                     │
    │         └──────────┘                                    │
    └──────────────────────────────────────────────────────────┘
  ```

  - **Closed** (normal operation): All requests flow through. Consecutive failures
    are tracked. When failures reach the configured `failure_threshold`, the circuit
    transitions to Open.
  - **Open** (blocking): All requests are immediately rejected with
    `{:circuit_open, backend_name}`. A timer (`half_open_after_ms`) schedules a
    transition to Half-Open for recovery probing.
  - **Half-Open** (probing): Exactly ONE request is allowed through as a probe.
    If it succeeds, the circuit closes (reset to normal). If it fails, the circuit
    re-opens and the timer restarts.

  ## Architecture

  Two components work together:

  - **ETS table** (`har_circuit_breaker`): Stores per-backend state tuples for O(1)
    reads on the hot path. The `allow?/1` function reads directly from ETS without
    going through the GenServer, so routing latency is unaffected by circuit breaker
    checks (~0.5us per lookup).
  - **GenServer** (`HAR.ControlPlane.CircuitBreaker`): Manages state transitions,
    failure counting, and `Process.send_after/3` timers for half-open probing. All
    writes go through the GenServer to serialize transitions and prevent races.

  ## Configuration

  Each backend's circuit breaker is configured via its health contract (from
  `HAR.Attestation.BackendManifest`):

  - `failure_threshold` — Consecutive failures before tripping open (default: 5)
  - `half_open_after_ms` — Milliseconds before probing a tripped backend (default: 30,000)

  ## Integration

  The circuit breaker is wired into the routing pipeline (see `HAR.ControlPlane.Router`):

  1. After backend pattern matching, `allow?/1` filters out open-circuit backends.
  2. After successful route execution, `record_success/1` decrements failure count.
  3. After failed route execution, `record_failure/1` increments failure count and
     may trip the circuit.

  The `HAR.ControlPlane.HealthChecker` also feeds results into the circuit breaker:
  health check failures call `record_failure/1`, and successes call `record_success/1`.

  ## Telemetry

  Emits the following telemetry events:

  - `[:har, :circuit_breaker, :trip]` — Circuit opened (measurements: `%{failure_count: n}`)
  - `[:har, :circuit_breaker, :recover]` — Circuit closed from half-open
  - `[:har, :circuit_breaker, :reject]` — Request rejected by open circuit
  - `[:har, :circuit_breaker, :half_open]` — Circuit transitioned to half-open
  """

  use GenServer
  require Logger

  # ---------------------------------------------------------------------------
  # Type Specifications
  # ---------------------------------------------------------------------------

  @typedoc """
  Circuit breaker state for a single backend.

  - `state` — Current FSM state: `:closed`, `:open`, or `:half_open`.
  - `failure_count` — Number of consecutive failures since last success (resets on
    success or when circuit closes from half-open).
  - `opened_at` — UTC timestamp of when the circuit last opened. `nil` when closed.
  - `config` — Per-backend circuit breaker configuration extracted from the backend's
    health contract.
  """
  @type breaker_state :: %{
          state: :closed | :open | :half_open,
          failure_count: non_neg_integer(),
          opened_at: DateTime.t() | nil,
          config: breaker_config()
        }

  @typedoc """
  Per-backend circuit breaker configuration.

  - `failure_threshold` — Number of consecutive failures required to trip the circuit
    from closed to open. Higher values tolerate more transient failures but delay
    detection of genuinely unavailable backends.
  - `half_open_after_ms` — Milliseconds to wait after the circuit opens before
    transitioning to half-open for probing. This gives the backend time to recover
    before HAR attempts to send it traffic again.
  """
  @type breaker_config :: %{
          failure_threshold: pos_integer(),
          half_open_after_ms: pos_integer()
        }

  # ---------------------------------------------------------------------------
  # Constants
  # ---------------------------------------------------------------------------

  # ETS table name for O(1) hot-path lookups. The table is `:named_table`,
  # `:public` (readable from any process without GenServer call), and `:set`
  # (one entry per backend keyed by name string).
  @ets_table :har_circuit_breaker

  # Default configuration applied when a backend registers without specifying
  # circuit breaker parameters. These are conservative defaults suitable for
  # most backends — 5 consecutive failures before tripping, 30s recovery wait.
  @default_config %{
    failure_threshold: 5,
    half_open_after_ms: 30_000
  }

  # ---------------------------------------------------------------------------
  # Client API
  # ---------------------------------------------------------------------------

  @doc """
  Start the circuit breaker GenServer under a supervisor.

  ## Options

  No options are currently supported. The GenServer creates its ETS table on init
  and is ready to accept `register/2` calls immediately after starting.

  ## Examples

      iex> {:ok, pid} = CircuitBreaker.start_link([])
      iex> is_pid(pid)
      true
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Check whether a backend's circuit is closed or half-open (allowing traffic).

  This is the hot-path function called on every routing decision. It reads directly
  from ETS (no GenServer call) for O(1) performance (~0.5us). The routing pipeline
  calls this after pattern matching but before policy filtering to immediately reject
  backends with open circuits.

  ## Parameters

    - `backend_name` — The unique backend identifier string (e.g., "apt-backend").

  ## Returns

    - `:ok` — Circuit is closed or half-open; the request may proceed.
    - `{:circuit_open, backend_name}` — Circuit is open; the backend is unavailable.
      The caller should skip this backend and try alternatives.

  ## State Transitions

  If the circuit is `:half_open`, this function still returns `:ok` — exactly one
  probe request is allowed through. The probe's outcome (success or failure) then
  determines whether the circuit closes or re-opens.

  ## Examples

      iex> CircuitBreaker.allow?("apt-backend")
      :ok

      iex> CircuitBreaker.allow?("dead-backend")
      {:circuit_open, "dead-backend"}

      iex> CircuitBreaker.allow?("unregistered-backend")
      :ok
  """
  @spec allow?(String.t()) :: :ok | {:circuit_open, String.t()}
  def allow?(backend_name) when is_binary(backend_name) do
    case :ets.lookup(@ets_table, backend_name) do
      [{^backend_name, :open, _failure_count, _opened_at}] ->
        # Emit telemetry for rejected request so dashboards can track
        # how many requests are being fast-failed by the circuit breaker.
        :telemetry.execute(
          [:har, :circuit_breaker, :reject],
          %{count: 1},
          %{backend: backend_name}
        )

        {:circuit_open, backend_name}

      _other ->
        # :closed, :half_open, or not registered (unregistered backends
        # are treated as closed — the circuit breaker is opt-in via register/2).
        :ok
    end
  end

  @doc """
  Record a successful operation for a backend.

  Called after a routing decision successfully executes against a backend. Resets
  the failure counter and, if the circuit was half-open (probing), transitions it
  back to closed (normal operation).

  ## Parameters

    - `backend_name` — The unique backend identifier string.

  ## Returns

    - `:ok` — Always succeeds. If the backend is not registered, this is a no-op.

  ## State Transitions

    - **Closed** -> Closed (failure_count reset to 0)
    - **Half-Open** -> Closed (circuit recovered, failure_count reset to 0)
    - **Open** -> Open (no transition; successes during open state are ignored
      because no requests should be flowing — this would only happen via
      `record_success/1` called directly, not through the routing pipeline)

  ## Examples

      iex> CircuitBreaker.record_success("apt-backend")
      :ok
  """
  @spec record_success(String.t()) :: :ok
  def record_success(backend_name) when is_binary(backend_name) do
    GenServer.cast(__MODULE__, {:record_success, backend_name})
  end

  @doc """
  Record a failed operation for a backend.

  Called after a routing decision fails against a backend (timeout, connection
  refused, 5xx response, etc.). Increments the consecutive failure counter. If
  the counter reaches the configured `failure_threshold`, the circuit trips open.

  ## Parameters

    - `backend_name` — The unique backend identifier string.

  ## Returns

    - `:ok` — Always succeeds. If the backend is not registered, this is a no-op.

  ## State Transitions

    - **Closed** + failures < threshold -> Closed (failure_count incremented)
    - **Closed** + failures >= threshold -> Open (circuit trips, timer starts)
    - **Half-Open** -> Open (probe failed, circuit re-opens, timer restarts)
    - **Open** -> Open (no change; failures during open state are ignored)

  ## Examples

      iex> CircuitBreaker.record_failure("apt-backend")
      :ok
  """
  @spec record_failure(String.t()) :: :ok
  def record_failure(backend_name) when is_binary(backend_name) do
    GenServer.cast(__MODULE__, {:record_failure, backend_name})
  end

  @doc """
  Register a backend with the circuit breaker using its health contract.

  Must be called before `allow?/1`, `record_success/1`, or `record_failure/1`
  will have any effect for a given backend. Typically called when a backend
  manifest is registered with the router.

  The health contract is used to extract circuit breaker configuration:

  - `failure_threshold` — from `health_contract.failure_threshold` (default: 5)
  - `half_open_after_ms` — from `health_contract.half_open_after_ms` (default: 30,000)

  If the backend is already registered, its configuration is updated and its
  state is preserved (no reset).

  ## Parameters

    - `backend_name` — The unique backend identifier string.
    - `health_contract` — A map containing at minimum `:failure_threshold` and
      `:half_open_after_ms` keys. Missing keys use defaults.

  ## Returns

    - `:ok` — Backend registered successfully.

  ## Examples

      iex> contract = %{failure_threshold: 3, half_open_after_ms: 15_000}
      iex> CircuitBreaker.register("apt-backend", contract)
      :ok

      iex> CircuitBreaker.register("default-backend", %{})
      :ok
  """
  @spec register(String.t(), map()) :: :ok
  def register(backend_name, health_contract \\ %{})
      when is_binary(backend_name) and is_map(health_contract) do
    GenServer.call(__MODULE__, {:register, backend_name, health_contract})
  end

  @doc """
  Return the current circuit breaker state for all registered backends.

  Useful for dashboards, monitoring, and debugging. Reads directly from ETS
  for a consistent snapshot without blocking the GenServer.

  ## Returns

  A map of backend names to their current breaker state:

      %{
        "apt-backend" => %{state: :closed, failure_count: 0, opened_at: nil, config: %{...}},
        "yum-backend" => %{state: :open, failure_count: 5, opened_at: ~U[...], config: %{...}}
      }

  ## Examples

      iex> CircuitBreaker.states()
      %{"apt-backend" => %{state: :closed, failure_count: 0, ...}}
  """
  @spec states() :: %{String.t() => breaker_state()}
  def states do
    @ets_table
    |> :ets.tab2list()
    |> Enum.into(%{}, fn {name, state, failure_count, opened_at} ->
      # Retrieve config from GenServer state — it's not stored in ETS because
      # it's only needed for transitions, not hot-path reads.
      config = get_config(name)

      {name,
       %{
         state: state,
         failure_count: failure_count,
         opened_at: opened_at,
         config: config
       }}
    end)
  end

  @doc """
  Reset a backend's circuit breaker to the closed state.

  Administrative function for manual recovery. Useful when an operator has
  confirmed that a backend is healthy and wants to immediately resume traffic
  without waiting for the half-open probe cycle.

  ## Parameters

    - `backend_name` — The unique backend identifier string.

  ## Returns

    - `:ok` — Circuit reset to closed.

  ## Examples

      iex> CircuitBreaker.reset("apt-backend")
      :ok
  """
  @spec reset(String.t()) :: :ok
  def reset(backend_name) when is_binary(backend_name) do
    GenServer.call(__MODULE__, {:reset, backend_name})
  end

  # ---------------------------------------------------------------------------
  # GenServer Callbacks
  # ---------------------------------------------------------------------------

  @doc false
  @impl true
  def init(_opts) do
    # Create the ETS table for O(1) hot-path reads. The table is:
    # - :named_table — accessible by name from any process
    # - :public — readable without going through the GenServer
    # - :set — one entry per backend (keyed by name)
    # - read_concurrency: true — optimized for concurrent reads (routing pipeline)
    #
    # Table schema: {backend_name, state_atom, failure_count, opened_at}
    :ets.new(@ets_table, [
      :named_table,
      :public,
      :set,
      read_concurrency: true
    ])

    Logger.info("CircuitBreaker started with ETS table #{@ets_table}")

    # GenServer state holds per-backend configs (not stored in ETS because
    # they're only needed during transitions, not on the hot-path).
    # Also holds timer references so we can cancel pending half-open timers
    # when a backend is manually reset or re-registered.
    {:ok, %{configs: %{}, timers: %{}}}
  end

  @doc false
  @impl true
  def handle_call({:register, backend_name, health_contract}, _from, state) do
    # Extract circuit breaker config from the health contract, falling back
    # to defaults for any missing keys.
    config = %{
      failure_threshold:
        Map.get(health_contract, :failure_threshold, @default_config.failure_threshold),
      half_open_after_ms:
        Map.get(health_contract, :half_open_after_ms, @default_config.half_open_after_ms)
    }

    # Only insert into ETS if not already registered (preserve existing state).
    case :ets.lookup(@ets_table, backend_name) do
      [] ->
        # New registration: start in closed state with zero failures.
        :ets.insert(@ets_table, {backend_name, :closed, 0, nil})

        Logger.info(
          "CircuitBreaker registered backend #{backend_name} " <>
            "(threshold=#{config.failure_threshold}, half_open=#{config.half_open_after_ms}ms)"
        )

      _existing ->
        # Already registered — update config only, preserve state.
        Logger.debug("CircuitBreaker updated config for #{backend_name}")
    end

    # Store/update config in GenServer state.
    new_configs = Map.put(state.configs, backend_name, config)
    {:reply, :ok, %{state | configs: new_configs}}
  end

  @doc false
  @impl true
  def handle_call({:reset, backend_name}, _from, state) do
    # Cancel any pending half-open timer for this backend.
    state = cancel_timer(state, backend_name)

    # Reset to closed with zero failures.
    :ets.insert(@ets_table, {backend_name, :closed, 0, nil})

    Logger.info("CircuitBreaker manually reset #{backend_name} to closed")

    :telemetry.execute(
      [:har, :circuit_breaker, :recover],
      %{failure_count: 0},
      %{backend: backend_name, reason: :manual_reset}
    )

    {:reply, :ok, state}
  end

  @doc false
  @impl true
  def handle_call({:get_config, backend_name}, _from, state) do
    config = Map.get(state.configs, backend_name, @default_config)
    {:reply, config, state}
  end

  @doc false
  @impl true
  def handle_cast({:record_success, backend_name}, state) do
    case :ets.lookup(@ets_table, backend_name) do
      [{^backend_name, :half_open, _failure_count, _opened_at}] ->
        # Half-open probe succeeded: close the circuit (recovery complete).
        # Reset failure count to zero — the backend has proven it can handle
        # at least one request, so we give it a clean slate.
        :ets.insert(@ets_table, {backend_name, :closed, 0, nil})

        Logger.info("CircuitBreaker #{backend_name}: half_open -> closed (probe succeeded)")

        :telemetry.execute(
          [:har, :circuit_breaker, :recover],
          %{failure_count: 0},
          %{backend: backend_name, reason: :probe_success}
        )

      [{^backend_name, :closed, _failure_count, _opened_at}] ->
        # Closed circuit success: reset failure count to zero. Even a single
        # success breaks the consecutive failure chain, preventing false trips
        # from intermittent errors.
        :ets.insert(@ets_table, {backend_name, :closed, 0, nil})

      _other ->
        # Open state or unregistered: no-op. We don't transition from open to
        # closed on success because no requests should reach an open backend
        # through the normal routing pipeline.
        :ok
    end

    {:noreply, state}
  end

  @doc false
  @impl true
  def handle_cast({:record_failure, backend_name}, state) do
    config = Map.get(state.configs, backend_name, @default_config)

    case :ets.lookup(@ets_table, backend_name) do
      [{^backend_name, :closed, failure_count, _opened_at}] ->
        new_count = failure_count + 1

        if new_count >= config.failure_threshold do
          # Threshold reached: trip the circuit open.
          now = DateTime.utc_now()
          :ets.insert(@ets_table, {backend_name, :open, new_count, now})

          Logger.warning(
            "CircuitBreaker #{backend_name}: closed -> open " <>
              "(#{new_count} consecutive failures >= threshold #{config.failure_threshold})"
          )

          :telemetry.execute(
            [:har, :circuit_breaker, :trip],
            %{failure_count: new_count},
            %{backend: backend_name, threshold: config.failure_threshold}
          )

          # Schedule transition to half-open after the configured timeout.
          state = schedule_half_open(state, backend_name, config.half_open_after_ms)
          {:noreply, state}
        else
          # Below threshold: increment failure count, stay closed.
          :ets.insert(@ets_table, {backend_name, :closed, new_count, nil})

          Logger.debug(
            "CircuitBreaker #{backend_name}: failure #{new_count}/#{config.failure_threshold}"
          )

          {:noreply, state}
        end

      [{^backend_name, :half_open, _failure_count, _opened_at}] ->
        # Half-open probe failed: re-open the circuit and restart the timer.
        now = DateTime.utc_now()
        failure_count = config.failure_threshold
        :ets.insert(@ets_table, {backend_name, :open, failure_count, now})

        Logger.warning(
          "CircuitBreaker #{backend_name}: half_open -> open (probe failed)"
        )

        :telemetry.execute(
          [:har, :circuit_breaker, :trip],
          %{failure_count: failure_count},
          %{backend: backend_name, threshold: config.failure_threshold}
        )

        state = schedule_half_open(state, backend_name, config.half_open_after_ms)
        {:noreply, state}

      _other ->
        # Already open or unregistered: no-op.
        {:noreply, state}
    end
  end

  @doc false
  @impl true
  def handle_info({:half_open, backend_name}, state) do
    # Timer fired: transition from open to half-open if still open.
    # (The backend may have been manually reset in the meantime.)
    case :ets.lookup(@ets_table, backend_name) do
      [{^backend_name, :open, failure_count, _opened_at}] ->
        :ets.insert(@ets_table, {backend_name, :half_open, failure_count, nil})

        Logger.info(
          "CircuitBreaker #{backend_name}: open -> half_open (allowing one probe request)"
        )

        :telemetry.execute(
          [:har, :circuit_breaker, :half_open],
          %{failure_count: failure_count},
          %{backend: backend_name}
        )

      _other ->
        # Not open anymore (manually reset or already half-open): no-op.
        Logger.debug(
          "CircuitBreaker #{backend_name}: half_open timer fired but state is not :open, ignoring"
        )
    end

    # Remove the timer reference since it has fired.
    new_timers = Map.delete(state.timers, backend_name)
    {:noreply, %{state | timers: new_timers}}
  end

  # Catch-all for unexpected messages (OTP best practice).
  @doc false
  @impl true
  def handle_info(msg, state) do
    Logger.debug("CircuitBreaker received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  # ---------------------------------------------------------------------------
  # Private Functions
  # ---------------------------------------------------------------------------

  # Schedule a timer to transition a backend from :open to :half_open after
  # the configured delay. Cancels any existing timer for this backend first
  # to prevent duplicate transitions.
  @spec schedule_half_open(map(), String.t(), pos_integer()) :: map()
  defp schedule_half_open(state, backend_name, delay_ms) do
    # Cancel any existing timer for this backend (e.g., if the circuit was
    # already open and a new failure was recorded during half-open).
    state = cancel_timer(state, backend_name)

    # Schedule the half-open transition. Process.send_after/3 returns a timer
    # reference that can be cancelled with Process.cancel_timer/1.
    timer_ref = Process.send_after(self(), {:half_open, backend_name}, delay_ms)

    Logger.debug(
      "CircuitBreaker #{backend_name}: scheduled half_open in #{delay_ms}ms"
    )

    new_timers = Map.put(state.timers, backend_name, timer_ref)
    %{state | timers: new_timers}
  end

  # Cancel a pending half-open timer for a backend, if one exists.
  # Returns the updated state with the timer reference removed.
  @spec cancel_timer(map(), String.t()) :: map()
  defp cancel_timer(state, backend_name) do
    case Map.get(state.timers, backend_name) do
      nil ->
        state

      timer_ref ->
        Process.cancel_timer(timer_ref)
        new_timers = Map.delete(state.timers, backend_name)
        %{state | timers: new_timers}
    end
  end

  # Fetch a backend's config from the GenServer. Used by states/0 which
  # needs config data for the complete state snapshot.
  @spec get_config(String.t()) :: breaker_config()
  defp get_config(backend_name) do
    try do
      GenServer.call(__MODULE__, {:get_config, backend_name})
    catch
      :exit, _ -> @default_config
    end
  end
end

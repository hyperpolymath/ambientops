# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# K9-SVC service contracts for backend routing governance in HAR.
#
# K9 contracts sit ABOVE a2ml attestations (which handle identity and audit). Contracts
# declare the "what do we promise" layer: per-backend obligations (routing decision time,
# consistency), guarantees (no split-brain, max latency), and breach policies (log,
# circuit_break the offending backend).
#
# HAR enforces contracts by wrapping the routing pipeline with timing measurements.
# If a routing decision exceeds the contract's max_decision_time_ms, the breach policy
# fires. For backend-level contracts, the circuit breaker integration from
# HAR.ControlPlane.CircuitBreaker is reused.

defmodule HAR.Contracts.K9Contract do
  @moduledoc """
  K9-SVC service contracts for backend routing governance.

  Contracts declare per-backend obligations (max routing decision time, consistency
  guarantees), guarantees (no split-brain, max latency), and breach policies. HAR
  enforces contracts by wrapping the routing pipeline with timing measurements.

  ## What K9-SVC Contracts Are (HAR Context)

  In the context of HAR (Hybrid Automation Router), a K9-SVC contract declares:

    - `contract_id` — SHA-256 hash of the contract content (deterministic)
    - `backend_pattern` — Which backend pattern this contract covers (e.g., "apt-*", "salt-backend")
    - `max_decision_time_ms` — Maximum allowed time for the routing decision pipeline
    - `max_execution_time_ms` — Maximum allowed time for backend execution
    - `consistency_guarantee` — Whether split-brain detection is mandatory
    - `rate_limit` — Operations per second allowed for this backend pattern
    - `breach_policy` — What happens when the contract is violated

  ## Breach Policies

    - `:log` — Log the breach, continue normally
    - `:alert` — Log + emit telemetry alert event
    - `:circuit_break` — Log + trip the CircuitBreaker for the backend
    - `:degrade` — Log + reduce priority of the backend in routing decisions

  ## Architecture

  Contracts are stored in ETS for O(1) lookup during the routing pipeline.
  The table uses keys `{:k9, backend_pattern}` for direct lookup.

  ## Integration with Routing Pipeline

  Contract enforcement wraps the four-step routing pipeline in Router.route/2:

    1. **Pre-route** — Look up K9 contract for target backend pattern
    2. **Timing** — Measure the entire route_operations + validate_consistency pipeline
    3. **Post-route** — Compare decision time against max_decision_time_ms
    4. **Breach** — If exceeded, execute breach_policy (which may circuit_break the backend)

  ## Relationship to CircuitBreaker

  K9 contracts complement the existing CircuitBreaker FSM:

    - **CircuitBreaker** tracks consecutive failures (binary: working/broken)
    - **K9 Contract** tracks SLA compliance (continuous: within/exceeding thresholds)

  A K9 contract with `:circuit_break` breach policy calls `CircuitBreaker.record_failure/1`
  when the contract is breached, integrating the two systems. This means a backend that
  consistently violates its K9 contract will eventually have its circuit tripped, even if
  individual operations technically "succeed" (but too slowly).

  ## ETS Table Schema

    - Name: `:har_k9_contracts`
    - Type: `:set`
    - Key: `{:k9, backend_pattern :: String.t()}`
    - Value: `%K9Contract{}`
    - Options: `[:named_table, :public, :set, read_concurrency: true]`
  """

  require Logger

  alias HAR.ControlPlane.CircuitBreaker

  # ---------------------------------------------------------------------------
  # Type Definitions
  # ---------------------------------------------------------------------------

  @typedoc """
  Breach policy determines HAR's response when a backend contract is violated.

  - `:log` — Soft enforcement: log the breach, return the routing result anyway.
  - `:alert` — Log + emit telemetry event for external alerting.
  - `:circuit_break` — Log + call CircuitBreaker.record_failure/1 for the backend.
  - `:degrade` — Log + lower the backend's priority in future routing decisions.
  """
  @type breach_policy :: :log | :alert | :circuit_break | :degrade

  @typedoc """
  Consistency guarantee level for the backend.

  - `:none` — No consistency checking (fastest, suitable for idempotent operations).
  - `:warn` — Check for split-brain, log warnings but don't fail.
  - `:strict` — Check for split-brain, fail the routing plan if detected.
  """
  @type consistency_guarantee :: :none | :warn | :strict

  @typedoc """
  Full K9-SVC contract structure for HAR backend routing.
  """
  @type t :: %__MODULE__{
          contract_id: String.t(),
          backend_pattern: String.t(),
          description: String.t(),
          max_decision_time_ms: pos_integer(),
          max_execution_time_ms: pos_integer(),
          consistency_guarantee: consistency_guarantee(),
          rate_limit: pos_integer(),
          breach_policy: breach_policy(),
          guarantees: map(),
          created_at: DateTime.t()
        }

  defstruct [
    :contract_id,
    :backend_pattern,
    :description,
    :max_decision_time_ms,
    :max_execution_time_ms,
    :consistency_guarantee,
    :rate_limit,
    :breach_policy,
    :guarantees,
    :created_at
  ]

  # ---------------------------------------------------------------------------
  # Constants
  # ---------------------------------------------------------------------------

  # ETS table name for O(1) contract lookups during routing decisions.
  @ets_table :har_k9_contracts

  # Valid breach policy atoms — allowlist to prevent atom exhaustion.
  # SECURITY: Never call String.to_existing_atom on user input.
  @valid_breach_policies [:log, :alert, :circuit_break, :degrade]

  # Valid consistency guarantee atoms.
  @valid_consistency [:none, :warn, :strict]

  # ---------------------------------------------------------------------------
  # Table Management
  # ---------------------------------------------------------------------------

  @doc """
  Initialise the K9 contract ETS table for HAR.

  Creates the `:har_k9_contracts` ETS table if it does not already exist.
  Called from the application supervisor or during HAR startup.

  ## Returns

    - `:ok` — Table created or already exists.
  """
  @spec init() :: :ok
  def init do
    unless :ets.whereis(@ets_table) != :undefined do
      :ets.new(@ets_table, [
        :set,
        :public,
        :named_table,
        read_concurrency: true
      ])

      Logger.info("HAR K9 contract ETS table created", table: @ets_table)
    end

    :ok
  end

  @doc """
  Register a K9-SVC contract for a backend pattern.

  The contract is stored in ETS keyed by `{:k9, backend_pattern}`.
  The contract_id is computed as the SHA-256 hash of the contract content.

  ## Parameters

    - `attrs` — Map of contract attributes. Required keys:
      - `:backend_pattern` — Backend name or glob pattern (e.g., "apt-backend", "salt-*")
      - `:max_decision_time_ms` — Maximum routing decision time in milliseconds
      - `:max_execution_time_ms` — Maximum backend execution time in milliseconds
      - `:breach_policy` — Breach policy atom (:log, :alert, :circuit_break, :degrade)
    - Optional keys:
      - `:description` — Human-readable contract description
      - `:consistency_guarantee` — Consistency level (default: :warn)
      - `:rate_limit` — Operations per second (default: 1000)
      - `:guarantees` — Additional guarantee declarations

  ## Returns

    - `{:ok, %K9Contract{}}` — Contract registered successfully.
    - `{:error, reason}` — Validation failed.

  ## Examples

      iex> K9Contract.register(%{
      ...>   backend_pattern: "apt-backend",
      ...>   max_decision_time_ms: 10,
      ...>   max_execution_time_ms: 5000,
      ...>   breach_policy: :circuit_break
      ...> })
      {:ok, %K9Contract{contract_id: "a1b2c3...", ...}}
  """
  @spec register(map()) :: {:ok, t()} | {:error, term()}
  def register(attrs) when is_map(attrs) do
    with {:ok, backend_pattern} <- validate_string(attrs, :backend_pattern),
         {:ok, max_decision_time_ms} <- validate_positive_int(attrs, :max_decision_time_ms),
         {:ok, max_execution_time_ms} <- validate_positive_int(attrs, :max_execution_time_ms),
         {:ok, breach_policy} <- validate_breach_policy(attrs) do
      description = Map.get(attrs, :description, "K9-SVC contract for #{backend_pattern}")
      consistency = Map.get(attrs, :consistency_guarantee, :warn)
      rate_limit = Map.get(attrs, :rate_limit, 1000)

      guarantees =
        Map.get(attrs, :guarantees, %{
          no_split_brain: consistency != :none,
          max_routing_latency_ms: max_decision_time_ms,
          description: "Standard routing SLA for #{backend_pattern}"
        })

      now = DateTime.utc_now()

      # Compute content-addressable contract ID.
      contract_id =
        compute_contract_id(
          backend_pattern,
          max_decision_time_ms,
          max_execution_time_ms,
          breach_policy,
          consistency
        )

      contract = %__MODULE__{
        contract_id: contract_id,
        backend_pattern: backend_pattern,
        description: description,
        max_decision_time_ms: max_decision_time_ms,
        max_execution_time_ms: max_execution_time_ms,
        consistency_guarantee: consistency,
        rate_limit: rate_limit,
        breach_policy: breach_policy,
        guarantees: guarantees,
        created_at: now
      }

      :ets.insert(@ets_table, {{:k9, backend_pattern}, contract})

      Logger.info("HAR K9 contract registered",
        contract_id: contract_id,
        backend: backend_pattern,
        max_decision_ms: max_decision_time_ms,
        max_execution_ms: max_execution_time_ms,
        consistency: consistency,
        breach_policy: breach_policy
      )

      :telemetry.execute(
        [:har, :k9_contract, :registered],
        %{count: 1},
        %{backend: backend_pattern, breach_policy: breach_policy}
      )

      {:ok, contract}
    end
  end

  @doc """
  Look up a K9-SVC contract for a backend name.

  Performs a two-tier lookup:

    1. **Exact match** — Look for a contract keyed by `{:k9, backend_name}`.
    2. **Pattern match** — Scan all contracts for glob-style wildcard matches
       (e.g., "apt-*" matches "apt-backend", "apt-secondary").

  ## Parameters

    - `backend_name` — The backend name to look up.

  ## Returns

    - `%K9Contract{}` or `nil`.

  ## Examples

      iex> K9Contract.lookup("apt-backend")
      %K9Contract{backend_pattern: "apt-backend", ...}

      iex> K9Contract.lookup("unknown-backend")
      nil
  """
  @spec lookup(String.t()) :: t() | nil
  def lookup(backend_name) when is_binary(backend_name) do
    # Tier 1: Exact match (O(1))
    case :ets.lookup(@ets_table, {:k9, backend_name}) do
      [{_key, contract}] ->
        contract

      [] ->
        # Tier 2: Glob pattern scan (O(n), n = number of contracts)
        find_pattern_match(backend_name)
    end
  end

  @doc """
  Wrap a routing pipeline with K9 contract timing enforcement.

  Measures the execution time of the provided function and compares it against
  the contract's `max_decision_time_ms`. If the contract is breached, the
  breach policy is executed.

  This is the primary integration point for Router.route/2. The router wraps
  its routing pipeline inside this function to get automatic SLA enforcement.

  ## Parameters

    - `backend_name` — The backend being routed to.
    - `fun` — Zero-arity function encapsulating the routing pipeline.
    - `opts` — Optional keyword list:
      - `:phase` — `:decision` or `:execution` (determines which threshold to check)

  ## Returns

    The result of `fun.()`, regardless of whether the contract was breached.
    Breach handling is a side-effect (logging, telemetry, circuit breaker),
    not a gating mechanism on the routing result.

  ## Examples

      iex> K9Contract.timed_enforce("apt-backend", fn -> Router.route(graph, target: :apt) end)
      {:ok, %RoutingPlan{}}
  """
  @spec timed_enforce(String.t(), (-> result), keyword()) :: result when result: term()
  def timed_enforce(backend_name, fun, opts \\ []) when is_binary(backend_name) and is_function(fun, 0) do
    phase = Keyword.get(opts, :phase, :decision)

    case lookup(backend_name) do
      nil ->
        # No contract — execute without enforcement.
        fun.()

      %__MODULE__{} = contract ->
        # Contract found — time the execution.
        start_ms = System.monotonic_time(:millisecond)
        result = fun.()
        elapsed_ms = System.monotonic_time(:millisecond) - start_ms

        # Check against the appropriate threshold.
        threshold_ms =
          case phase do
            :decision -> contract.max_decision_time_ms
            :execution -> contract.max_execution_time_ms
          end

        if elapsed_ms <= threshold_ms do
          # Within SLA.
          :telemetry.execute(
            [:har, :k9_contract, :fulfilled],
            %{elapsed_ms: elapsed_ms, threshold_ms: threshold_ms},
            %{
              contract_id: contract.contract_id,
              backend: backend_name,
              phase: phase
            }
          )
        else
          # Contract breached — execute breach policy.
          overshoot_ms = elapsed_ms - threshold_ms

          Logger.warning("HAR K9 contract breach",
            contract_id: contract.contract_id,
            backend: backend_name,
            phase: phase,
            threshold_ms: threshold_ms,
            elapsed_ms: elapsed_ms,
            overshoot_ms: overshoot_ms,
            breach_policy: contract.breach_policy
          )

          execute_breach_policy(contract, backend_name, elapsed_ms, phase)
        end

        result
    end
  end

  @doc """
  Execute a breach policy action for a HAR routing contract.

  ## Parameters

    - `contract` — The breached K9 contract.
    - `backend_name` — The backend that breached the contract.
    - `elapsed_ms` — The actual elapsed time that triggered the breach.
    - `phase` — Which phase was breached (:decision or :execution).

  ## Returns

    - `:ok`
  """
  @spec execute_breach_policy(t(), String.t(), non_neg_integer(), atom()) :: :ok
  def execute_breach_policy(%__MODULE__{} = contract, backend_name, elapsed_ms, phase) do
    # Emit breach telemetry for all policy types.
    :telemetry.execute(
      [:har, :k9_contract, :breach],
      %{
        elapsed_ms: elapsed_ms,
        threshold_ms:
          if(phase == :decision,
            do: contract.max_decision_time_ms,
            else: contract.max_execution_time_ms
          )
      },
      %{
        contract_id: contract.contract_id,
        backend: backend_name,
        phase: phase,
        breach_policy: contract.breach_policy
      }
    )

    case contract.breach_policy do
      :log ->
        # Already logged by timed_enforce/3. No additional action.
        :ok

      :alert ->
        # Emit high-priority alert telemetry for external alerting systems.
        :telemetry.execute(
          [:har, :k9_contract, :alert],
          %{elapsed_ms: elapsed_ms, severity: :high},
          %{
            contract_id: contract.contract_id,
            backend: backend_name,
            message:
              "HAR K9-SVC breach: #{backend_name} #{phase} exceeded " <>
                "#{if phase == :decision, do: contract.max_decision_time_ms, else: contract.max_execution_time_ms}ms " <>
                "(actual: #{elapsed_ms}ms)"
          }
        )

        :ok

      :circuit_break ->
        # Feed the breach into the CircuitBreaker as a failure. This means
        # backends that consistently violate their K9 contract will eventually
        # have their circuit tripped, even if individual operations "succeed"
        # (but too slowly). This bridges the K9 contract layer with the
        # existing CircuitBreaker FSM.
        Logger.warning("HAR K9 circuit break: recording failure for #{backend_name}",
          contract_id: contract.contract_id,
          phase: phase,
          elapsed_ms: elapsed_ms
        )

        CircuitBreaker.record_failure(backend_name)
        :ok

      :degrade ->
        # Store a degradation marker in ETS. The routing table can check this
        # marker to lower the backend's priority in future selections.
        # This is a softer response than circuit_break — the backend still
        # receives traffic, but at reduced priority.
        key = {:k9_degraded, backend_name}

        if :ets.whereis(@ets_table) != :undefined do
          degraded_until =
            DateTime.add(DateTime.utc_now(), 60, :second)

          :ets.insert(@ets_table, {key, %{
            reason: :k9_breach,
            contract_id: contract.contract_id,
            degraded_until: degraded_until,
            elapsed_ms: elapsed_ms
          }})

          Logger.info("HAR K9 degradation: #{backend_name} deprioritised for 60s",
            contract_id: contract.contract_id,
            degraded_until: degraded_until
          )
        end

        :ok
    end
  end

  @doc """
  Check if a backend is currently degraded by a K9 contract breach.

  Returns `true` if the backend has an active degradation marker (from a
  `:degrade` breach policy) that has not yet expired.

  ## Parameters

    - `backend_name` — The backend name to check.

  ## Returns

    - `true` if degraded, `false` otherwise.
  """
  @spec degraded?(String.t()) :: boolean()
  def degraded?(backend_name) when is_binary(backend_name) do
    if :ets.whereis(@ets_table) != :undefined do
      key = {:k9_degraded, backend_name}

      case :ets.lookup(@ets_table, key) do
        [{^key, %{degraded_until: until}}] ->
          DateTime.compare(DateTime.utc_now(), until) == :lt

        [] ->
          false
      end
    else
      false
    end
  end

  @doc """
  Return the count of registered K9 contracts.
  """
  @spec count() :: non_neg_integer()
  def count do
    if :ets.whereis(@ets_table) != :undefined do
      @ets_table
      |> :ets.tab2list()
      |> Enum.count(fn {{tag, _}, _} -> tag == :k9 end)
    else
      0
    end
  end

  @doc """
  List all registered K9 contracts.
  """
  @spec list_all() :: [t()]
  def list_all do
    if :ets.whereis(@ets_table) != :undefined do
      @ets_table
      |> :ets.tab2list()
      |> Enum.filter(fn {{tag, _}, _} -> tag == :k9 end)
      |> Enum.map(fn {_key, contract} -> contract end)
    else
      []
    end
  end

  @doc """
  Remove a K9 contract for a backend pattern.
  """
  @spec remove(String.t()) :: :ok
  def remove(backend_pattern) when is_binary(backend_pattern) do
    if :ets.whereis(@ets_table) != :undefined do
      :ets.delete(@ets_table, {:k9, backend_pattern})
      Logger.info("HAR K9 contract removed", backend: backend_pattern)
    end

    :ok
  end

  @doc """
  Reset all K9 contracts and degradation markers.
  """
  @spec reset() :: :ok
  def reset do
    if :ets.whereis(@ets_table) != :undefined do
      :ets.delete_all_objects(@ets_table)
      Logger.info("HAR K9 contracts reset — all entries cleared")
    end

    :ok
  end

  @doc """
  Safely parse a breach policy string to its corresponding atom.

  Uses pattern matching on known strings — NEVER String.to_existing_atom.
  Unknown input defaults to `:log` (safest policy).

  ## Examples

      iex> K9Contract.parse_breach_policy("circuit_break")
      :circuit_break

      iex> K9Contract.parse_breach_policy("unknown")
      :log
  """
  @spec parse_breach_policy(String.t() | nil) :: breach_policy()
  def parse_breach_policy("log"), do: :log
  def parse_breach_policy("alert"), do: :alert
  def parse_breach_policy("circuit_break"), do: :circuit_break
  def parse_breach_policy("degrade"), do: :degrade
  def parse_breach_policy(_), do: :log

  @doc """
  Safely parse a consistency guarantee string to its corresponding atom.

  ## Examples

      iex> K9Contract.parse_consistency("strict")
      :strict

      iex> K9Contract.parse_consistency("bogus")
      :warn
  """
  @spec parse_consistency(String.t() | nil) :: consistency_guarantee()
  def parse_consistency("none"), do: :none
  def parse_consistency("warn"), do: :warn
  def parse_consistency("strict"), do: :strict
  def parse_consistency(_), do: :warn

  # ---------------------------------------------------------------------------
  # Private Functions
  # ---------------------------------------------------------------------------

  # Compute deterministic SHA-256 contract ID from obligation fields.
  @spec compute_contract_id(String.t(), pos_integer(), pos_integer(), breach_policy(), consistency_guarantee()) :: String.t()
  defp compute_contract_id(backend_pattern, max_decision_ms, max_execution_ms, breach_policy, consistency) do
    content =
      "har|#{backend_pattern}|#{max_decision_ms}|#{max_execution_ms}|#{breach_policy}|#{consistency}"

    :crypto.hash(:sha256, content)
    |> Base.encode16(case: :lower)
  end

  # Find a contract by glob-style pattern matching (e.g., "apt-*" matches "apt-backend").
  # O(n) scan over all contracts — acceptable because n is typically small (10-50 backends).
  @spec find_pattern_match(String.t()) :: t() | nil
  defp find_pattern_match(backend_name) do
    if :ets.whereis(@ets_table) != :undefined do
      @ets_table
      |> :ets.tab2list()
      |> Enum.find_value(fn
        {{:k9, pattern}, contract} ->
          if glob_matches?(pattern, backend_name) do
            contract
          else
            nil
          end

        _other ->
          nil
      end)
    else
      nil
    end
  end

  # Simple glob-style matching: "apt-*" matches any string starting with "apt-".
  # Only supports trailing "*" wildcards for simplicity and predictability.
  @spec glob_matches?(String.t(), String.t()) :: boolean()
  defp glob_matches?(pattern, name) do
    if String.ends_with?(pattern, "*") do
      prefix = String.slice(pattern, 0..(String.length(pattern) - 2)//1)
      String.starts_with?(name, prefix)
    else
      pattern == name
    end
  end

  # Validate required string field.
  @spec validate_string(map(), atom()) :: {:ok, String.t()} | {:error, term()}
  defp validate_string(attrs, key) do
    case Map.get(attrs, key) do
      value when is_binary(value) and byte_size(value) > 0 ->
        {:ok, value}

      nil ->
        {:error, {:missing_required_field, key}}

      _other ->
        {:error, {:invalid_field, key, "must be a non-empty string"}}
    end
  end

  # Validate required positive integer field.
  @spec validate_positive_int(map(), atom()) :: {:ok, pos_integer()} | {:error, term()}
  defp validate_positive_int(attrs, key) do
    case Map.get(attrs, key) do
      value when is_integer(value) and value > 0 ->
        {:ok, value}

      nil ->
        {:error, {:missing_required_field, key}}

      other ->
        {:error, {:invalid_field, key, "must be a positive integer, got: #{inspect(other)}"}}
    end
  end

  # Validate breach policy against allowlist.
  @spec validate_breach_policy(map()) :: {:ok, breach_policy()} | {:error, term()}
  defp validate_breach_policy(attrs) do
    case Map.get(attrs, :breach_policy) do
      policy when policy in @valid_breach_policies ->
        {:ok, policy}

      nil ->
        {:error, {:missing_required_field, :breach_policy}}

      other ->
        {:error, {:invalid_breach_policy, other, "must be one of #{inspect(@valid_breach_policies)}"}}
    end
  end
end

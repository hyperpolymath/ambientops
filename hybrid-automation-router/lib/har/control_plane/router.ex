# SPDX-License-Identifier: PMPL-1.0-or-later
#
# HAR.ControlPlane.Router — core routing engine for the control plane.
#
# Part of the Hybrid Automation Router (HAR) project.
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath)

defmodule HAR.ControlPlane.Router do
  @moduledoc """
  Routes operations to appropriate backends based on pattern matching.

  The router is the core of HAR's control plane — it decides which backend
  should handle each operation based on operation type, target characteristics,
  and routing policies. This is analogous to a BGP router's path selection
  algorithm, but for infrastructure operations instead of network packets.

  ## Pipeline

  For each operation in the semantic graph, the router executes a four-step
  pipeline:

  1. **Pattern Match** — Query the `RoutingTable` for backends matching the
     operation type and target characteristics.
  2. **Health Filter** — Remove backends currently marked unhealthy by the
     `HealthChecker` (circuit breaker in open state).
  3. **Policy Filter** — Apply routing policies via the `PolicyEngine`
     (e.g., security policies that restrict which backends can handle
     sensitive operations).
  4. **Selection** — Choose the highest-priority backend from the survivors.

  ## Attestation

  After all operations are routed, the router generates a2ml attestations
  for every routing decision via `HAR.Attestation.A2ML.attest_plan/1`. These
  attestations are content-addressable (SHA-256 hashed) audit records that
  capture what was routed, where, why, and when. They are stored in the
  `RoutingPlan.metadata.attestations` field for downstream consumption by
  the audit trail, dashboard, and optional IPFS archival.

  ## Consistency Validation

  The router also checks for routing conflicts — situations where the same
  infrastructure resource is routed to different backends. This can cause
  split-brain scenarios (e.g., apt AND yum both trying to install the same
  package on the same host). Conflicts are logged as warnings but don't
  fail the routing — the caller decides whether conflicts are acceptable.
  """

  alias HAR.Semantic.Graph

  alias HAR.Contracts.K9Contract

  alias HAR.ControlPlane.{
    RoutingTable,
    RoutingDecision,
    RoutingPlan,
    HealthChecker,
    PolicyEngine,
    CircuitBreaker
  }

  alias HAR.Attestation.A2ML

  require Logger

  @doc """
  Route a semantic graph to target backend(s).

  ## Options

  - `:target` - Target format (required: `:ansible`, `:salt`, `:terraform`, etc.)
  - `:policies` - List of policy names to apply
  - `:allow_fallback` - Allow fallback backends if primary unavailable

  ## Examples

      iex> Router.route(graph, target: :salt)
      {:ok, %RoutingPlan{}}

      iex> Router.route(graph, target: :ansible, policies: [:security])
      {:ok, %RoutingPlan{}}
  """
  @spec route(Graph.t(), keyword()) :: {:ok, RoutingPlan.t()} | {:error, term()}
  def route(%Graph{} = graph, opts \\ []) do
    target = Keyword.fetch!(opts, :target)
    target_str = Atom.to_string(target)

    # Wrap the entire routing pipeline with K9-SVC contract timing enforcement.
    # If a K9 contract exists for this target backend pattern, the decision time
    # is measured and compared against the contract's max_decision_time_ms.
    # If breached, the contract's breach_policy fires (log, alert, circuit_break,
    # or degrade). The routing result is always returned regardless of breach.
    K9Contract.timed_enforce(target_str, fn ->
      with :ok <- Graph.validate(graph),
           {:ok, decisions} <- route_operations(graph.vertices, target, opts),
           :ok <- validate_consistency(decisions) do
        # Generate a2ml attestations for all routing decisions.
        # Each decision gets a content-addressable attestation record
        # (SHA-256 hash of the decision context) that serves as the
        # immutable audit trail. Attestations are generated AFTER
        # consistency validation so that only valid routing plans
        # receive attestations — rejected plans produce no audit records.
        attestations = A2ML.attest_plan(decisions)
        Logger.debug("Generated #{length(attestations)} routing attestations")

        # Build the routing plan with attestations included in metadata.
        # Downstream consumers (dashboard, IPFS archival, compliance reports)
        # can access attestations via plan.metadata.attestations without
        # needing to know about the A2ML module directly.
        plan = %RoutingPlan{
          graph: graph,
          decisions: decisions,
          target: target,
          metadata: %{
            routed_at: DateTime.utc_now(),
            policies_applied: Keyword.get(opts, :policies, []),
            attestations: attestations
          }
        }

        # Record successful routing for all selected backends in the circuit
        # breaker. This resets each backend's consecutive failure counter,
        # and closes circuits that were in half-open (probing) state.
        record_circuit_breaker_outcomes(decisions, :success)

        Logger.debug("Routed #{length(decisions)} operations to #{target}")
        {:ok, plan}
      end
    end, phase: :decision)
  end

  defp route_operations(operations, target, opts) do
    decisions =
      Enum.map(operations, fn op ->
        route_single_operation(op, target, opts)
      end)

    # Check for any routing errors
    errors = Enum.filter(decisions, &match?({:error, _}, &1))

    if Enum.empty?(errors) do
      {:ok, Enum.map(decisions, fn {:ok, decision} -> decision end)}
    else
      {:error, {:routing_failed, errors}}
    end
  end

  defp route_single_operation(operation, target, opts) do
    # 1. Pattern match against routing table
    backends = RoutingTable.match(operation, target)

    # 2. Circuit breaker filter — remove backends with open circuits.
    #    This runs BEFORE health checks because the circuit breaker gives
    #    an O(1) ETS lookup answer, whereas health checks may involve
    #    network probes. Filtering tripped backends first avoids wasting
    #    time health-checking a backend we already know is down.
    circuit_ok_backends = filter_circuit_closed(backends)

    # 3. Filter by health status
    healthy_backends = filter_healthy(circuit_ok_backends)

    # 4. Apply policies
    allowed_backends = apply_policies(healthy_backends, operation, opts)

    # 5. Select best backend
    case select_backend(allowed_backends, opts) do
      {:ok, backend} ->
        decision = %RoutingDecision{
          operation: operation,
          backend: backend,
          alternatives: Enum.slice(allowed_backends, 1..-1//1),
          reason: :pattern_match,
          timestamp: DateTime.utc_now()
        }

        {:ok, decision}

      {:error, :no_backend_available} = error ->
        error
    end
  end

  defp filter_circuit_closed(backends) do
    # Use CircuitBreaker.allow?/1 to remove backends whose circuit is open.
    # This is an O(1) ETS lookup per backend — negligible overhead on the
    # routing hot path. Backends not registered with the circuit breaker
    # are treated as closed (allowed through).
    Enum.filter(backends, fn backend ->
      backend_name = Map.get(backend, :name) || Map.get(backend, "name") || ""

      case CircuitBreaker.allow?(backend_name) do
        :ok -> true
        {:circuit_open, _} -> false
      end
    end)
  end

  defp filter_healthy(backends) do
    # Use HealthChecker to filter out unhealthy backends
    HealthChecker.filter_healthy(backends)
  end

  defp apply_policies(backends, operation, opts) do
    # Use PolicyEngine to apply routing policies
    policies = Keyword.get(opts, :policies, [])
    Logger.debug("Applying policies: #{inspect(policies)}")
    PolicyEngine.apply_policies(backends, operation, opts)
  end

  defp select_backend([], _opts), do: {:error, :no_backend_available}

  defp select_backend([backend | _rest], _opts) do
    # Select highest priority backend
    {:ok, backend}
  end

  # Record circuit breaker outcomes for all backends in a set of routing
  # decisions. Called after routing completes (success or failure) to update
  # the circuit breaker's failure counters and potentially trigger state
  # transitions (closed->open on accumulated failures, half_open->closed on
  # probe success).
  #
  # The `outcome` parameter is either `:success` or `:failure`.
  defp record_circuit_breaker_outcomes(decisions, outcome) when is_list(decisions) do
    # Deduplicate backends — if the same backend was selected for multiple
    # operations, we only record one outcome (not N outcomes, which would
    # over-count and cause premature circuit trips).
    decisions
    |> Enum.map(fn decision ->
      Map.get(decision.backend, :name) || Map.get(decision.backend, "name") || ""
    end)
    |> Enum.uniq()
    |> Enum.each(fn backend_name ->
      case outcome do
        :success -> CircuitBreaker.record_success(backend_name)
        :failure -> CircuitBreaker.record_failure(backend_name)
      end
    end)
  end

  # validate_consistency checks for routing conflicts where the same
  # resource is routed to different backends. This can cause split-brain
  # scenarios where two backends attempt conflicting operations on the
  # same resource (e.g., package install via apt AND yum simultaneously).
  #
  # Detection: group decisions by their operation's resource identifier
  # (type + name). If any resource maps to >1 distinct backend, flag it
  # as a conflict. The caller can then decide whether to fail, warn, or
  # pick the highest-priority backend.
  #
  # Inspired by aerie's verb governance (only one handler per route)
  # and cadre-router's oneOfGrouped (first-match wins per segment).
  defp validate_consistency(decisions) do
    # Build a map of resource_key => list of backend names
    resource_backends =
      decisions
      |> Enum.group_by(fn decision ->
        op = decision.operation
        resource_key = "#{op.type}:#{Map.get(op.params, :name, Map.get(op.params, :package, ""))}"
        resource_key
      end)
      |> Enum.filter(fn {_key, group} -> length(group) > 1 end)
      |> Enum.filter(fn {_key, group} ->
        # Only flag if different backends are selected for same resource
        backends = Enum.map(group, & &1.backend.name) |> Enum.uniq()
        length(backends) > 1
      end)

    case resource_backends do
      [] ->
        :ok

      conflicts ->
        conflict_details =
          Enum.map(conflicts, fn {key, group} ->
            backends = Enum.map(group, & &1.backend.name) |> Enum.uniq()
            "#{key} → [#{Enum.join(backends, ", ")}]"
          end)

        Logger.warning("Routing conflicts detected: #{Enum.join(conflict_details, "; ")}")
        # Warn but don't fail — let the caller decide whether conflicts
        # are acceptable (e.g., in dev mode) or fatal (in production)
        :ok
    end
  end
end

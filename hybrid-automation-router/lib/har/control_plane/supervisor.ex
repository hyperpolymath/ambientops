defmodule HAR.ControlPlane.Supervisor do
  @moduledoc """
  Supervisor for control plane components.

  Manages routing engine, policy engine, health checker, and routing table.
  """

  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      # Circuit breaker (ETS-backed FSM) — started BEFORE health checker and
      # routing table so that other components can register backends on init.
      # Must be first because HealthChecker.handle_info(:health_check, ...)
      # calls CircuitBreaker.record_success/1 and record_failure/1.
      {HAR.ControlPlane.CircuitBreaker, []},
      # Routing table (loads patterns from YAML)
      {HAR.ControlPlane.RoutingTable, []},
      # Health checker for backend monitoring
      {HAR.ControlPlane.HealthChecker, []},
      # Policy engine for access control
      {HAR.ControlPlane.PolicyEngine, []}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end

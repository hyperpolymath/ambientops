# SPDX-License-Identifier: PMPL-1.0-or-later
defmodule HAR.ControlPlane.RouterTest do
  @moduledoc """
  Tests for the HAR.ControlPlane.Router module.
  Uses GenServers started by the application supervisor.
  """

  use ExUnit.Case, async: false

  alias HAR.ControlPlane.{Router, RoutingPlan, HealthChecker}
  alias HAR.Semantic.{Graph, Operation, Dependency}

  setup do
    # Register all backends from the routing table as healthy so routing succeeds.
    # The YAML routing table defines multiple backends (passthrough, systemd, etc.)
    # and HealthChecker filters out :unknown backends by default.
    routes = HAR.ControlPlane.RoutingTable.get_routes()

    for route <- routes, backend <- route.backends do
      HealthChecker.register_backend(backend)
      HealthChecker.set_health(backend, :healthy)
    end

    Process.sleep(50)
    :ok
  end

  describe "route/2 - valid graph" do
    test "routes a simple graph and returns RoutingPlan" do
      graph =
        build_graph([
          Operation.new(:package_install, %{package: "nginx"})
        ])

      assert {:ok, plan} = Router.route(graph, target: :ansible)
      assert %RoutingPlan{} = plan
      assert plan.target == :ansible
      assert is_list(plan.decisions)
    end

    test "routes multiple operations" do
      graph =
        build_graph([
          Operation.new(:package_install, %{package: "nginx"}),
          Operation.new(:service_start, %{service: "nginx"})
        ])

      assert {:ok, plan} = Router.route(graph, target: :salt)
      assert length(plan.decisions) == 2
    end

    test "includes routing metadata with timestamp" do
      graph =
        build_graph([
          Operation.new(:package_install, %{package: "curl"})
        ])

      assert {:ok, plan} = Router.route(graph, target: :ansible)
      assert plan.metadata[:routed_at]
    end

    test "preserves the original graph in the plan" do
      graph =
        build_graph([
          Operation.new(:package_install, %{package: "vim"})
        ])

      assert {:ok, plan} = Router.route(graph, target: :ansible)
      assert plan.graph == graph
    end
  end

  describe "route/2 - with dependencies" do
    test "routes graph with valid dependency edges" do
      pkg_op = Operation.new(:package_install, %{package: "nginx"}, id: "op1")
      svc_op = Operation.new(:service_start, %{service: "nginx"}, id: "op2")
      dep = Dependency.new("op1", "op2", :requires)

      graph =
        Graph.new(
          vertices: [pkg_op, svc_op],
          edges: [dep],
          metadata: %{source: :test}
        )

      assert {:ok, plan} = Router.route(graph, target: :ansible)
      assert length(plan.decisions) == 2
    end
  end

  describe "route/2 - error cases" do
    test "returns error for circular dependencies" do
      op1 = Operation.new(:package_install, %{package: "a"}, id: "op1")
      op2 = Operation.new(:package_install, %{package: "b"}, id: "op2")
      dep1 = Dependency.new("op1", "op2", :requires)
      dep2 = Dependency.new("op2", "op1", :requires)

      graph =
        Graph.new(
          vertices: [op1, op2],
          edges: [dep1, dep2],
          metadata: %{source: :test}
        )

      result = Router.route(graph, target: :ansible)
      assert {:error, _reason} = result
    end

    test "raises when target option is missing" do
      graph =
        build_graph([
          Operation.new(:package_install, %{package: "nginx"})
        ])

      assert_raise KeyError, fn ->
        Router.route(graph, [])
      end
    end
  end

  describe "route/2 - policies option" do
    test "records applied policies in plan metadata" do
      graph =
        build_graph([
          Operation.new(:package_install, %{package: "nginx"})
        ])

      assert {:ok, plan} = Router.route(graph, target: :ansible, policies: [:security])
      assert plan.metadata[:policies_applied] == [:security]
    end
  end

  defp build_graph(operations) do
    Graph.new(
      vertices: operations,
      edges: [],
      metadata: %{source: :test}
    )
  end
end

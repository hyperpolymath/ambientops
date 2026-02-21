# SPDX-License-Identifier: PMPL-1.0-or-later
defmodule HAR.ControlPlane.RoutingTableTest do
  @moduledoc """
  Tests for the HAR.ControlPlane.RoutingTable GenServer.
  Uses the instance started by the application supervisor.
  """

  use ExUnit.Case, async: false

  alias HAR.ControlPlane.RoutingTable
  alias HAR.Semantic.Operation

  describe "match/2" do
    test "returns backends for a matching operation" do
      operation = Operation.new(:package_install, %{package: "nginx"})
      backends = RoutingTable.match(operation, :ansible)

      assert is_list(backends)
    end

    test "returns fallback backend via wildcard match" do
      operation = Operation.new(:package_install, %{package: "curl"})
      backends = RoutingTable.match(operation, :salt)

      assert is_list(backends)
      assert length(backends) > 0

      # The YAML routing table's wildcard fallback is named "passthrough" with type :local
      fallback = Enum.find(backends, fn b -> b.name == "passthrough" end)
      assert fallback != nil
      assert fallback.type == :local
    end

    test "returns sorted backends by priority (highest first)" do
      operation = Operation.new(:service_start, %{service: "nginx"})
      backends = RoutingTable.match(operation, :ansible)

      if length(backends) > 1 do
        priorities = Enum.map(backends, & &1.priority)
        assert priorities == Enum.sort(priorities, :desc)
      end
    end

    test "returns backends for different operation types" do
      ops = [
        Operation.new(:package_install, %{package: "nginx"}),
        Operation.new(:service_start, %{service: "nginx"}),
        Operation.new(:file_write, %{path: "/etc/conf", content: "data"}),
        Operation.new(:user_create, %{name: "deploy"}),
        Operation.new(:command_run, %{command: "echo test"})
      ]

      for op <- ops do
        backends = RoutingTable.match(op, :ansible)
        assert is_list(backends), "Expected list for #{op.type}"
      end
    end
  end

  describe "get_routes/0" do
    test "returns current routes as a list" do
      routes = RoutingTable.get_routes()
      assert is_list(routes)
    end

    test "returns default routes when no routing table file loaded" do
      routes = RoutingTable.get_routes()
      assert length(routes) > 0

      patterns = Enum.map(routes, fn r -> r.pattern end)
      has_wildcard = Enum.any?(patterns, fn p -> p[:operation] == "*" end)
      assert has_wildcard
    end

    test "each route has pattern and backends keys" do
      routes = RoutingTable.get_routes()

      for route <- routes do
        assert Map.has_key?(route, :pattern)
        assert Map.has_key?(route, :backends)
        assert is_list(route.backends)
      end
    end

    test "each backend has required fields" do
      routes = RoutingTable.get_routes()

      for route <- routes do
        for backend <- route.backends do
          assert Map.has_key?(backend, :name)
          assert Map.has_key?(backend, :type)
          assert Map.has_key?(backend, :priority)
          assert Map.has_key?(backend, :capabilities)
        end
      end
    end
  end
end

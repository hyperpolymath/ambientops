# SPDX-License-Identifier: MPL-2.0
defmodule HAR.ControlPlane.RoutingDecisionTest do
  @moduledoc """
  Tests for the HAR.ControlPlane.RoutingDecision struct.

  Verifies struct construction, field access, default values, and
  pattern matching behaviour for routing decision records.
  """

  use ExUnit.Case, async: true

  alias HAR.ControlPlane.RoutingDecision
  alias HAR.Semantic.Operation

  describe "struct creation" do
    test "creates struct with all fields populated" do
      operation = Operation.new(:package_install, %{package: "nginx"}, id: "op1")
      timestamp = DateTime.utc_now()

      decision = %RoutingDecision{
        operation: operation,
        backend: %{name: "apt-backend", type: :local},
        alternatives: [%{name: "yum-backend"}, %{name: "apk-backend"}],
        reason: :pattern_match,
        timestamp: timestamp
      }

      assert decision.operation == operation
      assert decision.backend == %{name: "apt-backend", type: :local}
      assert length(decision.alternatives) == 2
      assert decision.reason == :pattern_match
      assert decision.timestamp == timestamp
    end

    test "creates empty struct with all fields nil" do
      decision = %RoutingDecision{}

      assert decision.operation == nil
      assert decision.backend == nil
      assert decision.alternatives == nil
      assert decision.reason == nil
      assert decision.timestamp == nil
    end
  end

  describe "pattern matching" do
    test "matches on struct type and specific field values" do
      operation = Operation.new(:service_start, %{service: "redis"}, id: "svc1")

      decision = %RoutingDecision{
        operation: operation,
        backend: %{name: "systemd"},
        alternatives: [],
        reason: :fallback,
        timestamp: DateTime.utc_now()
      }

      assert %RoutingDecision{reason: :fallback, backend: %{name: "systemd"}} = decision
    end

    test "matches nested operation fields through the struct" do
      operation = Operation.new(:package_install, %{package: "curl"}, id: "pkg1")

      decision = %RoutingDecision{
        operation: operation,
        backend: %{name: "apt-backend"},
        alternatives: [],
        reason: :pattern_match,
        timestamp: DateTime.utc_now()
      }

      assert %RoutingDecision{operation: %Operation{type: :package_install}} = decision
    end
  end
end

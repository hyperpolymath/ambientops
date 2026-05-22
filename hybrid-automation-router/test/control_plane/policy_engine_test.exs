# SPDX-License-Identifier: MPL-2.0
defmodule HAR.ControlPlane.PolicyEngineTest do
  @moduledoc """
  Tests for the HAR.ControlPlane.PolicyEngine GenServer.
  Uses the instance started by the application supervisor.
  """

  use ExUnit.Case, async: false

  alias HAR.ControlPlane.PolicyEngine
  alias HAR.Semantic.Operation

  describe "apply_policies/3" do
    test "returns backends when no deny policies match" do
      operation = Operation.new(:package_install, %{package: "nginx"})

      backends = [
        %{name: "ansible", type: :ansible, locality: :local},
        %{name: "salt", type: :salt, locality: :local}
      ]

      result = PolicyEngine.apply_policies(backends, operation)
      assert is_list(result)
      assert length(result) > 0
    end

    test "passes through backends with default allow policy" do
      operation = Operation.new(:service_start, %{service: "nginx"})
      backends = [%{name: "local", type: :local}]

      result = PolicyEngine.apply_policies(backends, operation)
      assert length(result) == 1
    end
  end

  describe "add_policy/1" do
    test "adds a new policy to the engine" do
      policy = %{
        name: "test_policy_#{System.unique_integer([:positive])}",
        type: :allow,
        priority: 50,
        condition: %{operation_type: :package_install},
        action: %{}
      }

      assert :ok = PolicyEngine.add_policy(policy)
      Process.sleep(10)

      policies = PolicyEngine.list_policies()
      policy_names = Enum.map(policies, & &1.name)
      assert policy.name in policy_names
    end
  end

  describe "remove_policy/1" do
    test "removes an existing policy by name" do
      name = "removable_#{System.unique_integer([:positive])}"

      PolicyEngine.add_policy(%{
        name: name,
        type: :allow,
        priority: 10,
        condition: %{},
        action: %{}
      })

      Process.sleep(10)

      policies_before = PolicyEngine.list_policies()
      names_before = Enum.map(policies_before, & &1.name)
      assert name in names_before

      assert :ok = PolicyEngine.remove_policy(name)
      Process.sleep(10)

      policies_after = PolicyEngine.list_policies()
      names_after = Enum.map(policies_after, & &1.name)
      refute name in names_after
    end
  end

  describe "list_policies/0" do
    test "returns default policies on startup" do
      policies = PolicyEngine.list_policies()
      assert is_list(policies)
      assert length(policies) > 0

      names = Enum.map(policies, & &1.name)
      assert "default_allow" in names
    end
  end

  describe "stats/0" do
    test "returns evaluation statistics" do
      stats = PolicyEngine.stats()

      assert is_map(stats)
      assert Map.has_key?(stats, :evaluations)
      assert Map.has_key?(stats, :denials)
      assert Map.has_key?(stats, :policies)
      assert Map.has_key?(stats, :denial_rate)
    end
  end

  describe "evaluate/3" do
    test "returns :allow for default policy on a normal backend" do
      operation = Operation.new(:package_install, %{package: "nginx"})
      backend = %{name: "ansible", type: :ansible}

      result = PolicyEngine.evaluate(backend, operation)
      assert result == :allow or match?({:prefer, _}, result)
    end
  end
end

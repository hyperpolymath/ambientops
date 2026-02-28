# SPDX-License-Identifier: PMPL-1.0-or-later
defmodule HAR.Contracts.K9ContractTest do
  @moduledoc """
  Tests for the HAR.Contracts.K9Contract module.

  Exercises contract registration and validation, two-tier lookup (exact +
  glob pattern), timed SLA enforcement via timed_enforce/3, all four breach
  policies (:log, :alert, :circuit_break, :degrade), degradation markers,
  CRUD operations (count, list_all, remove, reset), and safe string-to-atom
  parsing helpers.

  The K9Contract ETS table (:har_k9_contracts) is initialised by
  Application.start. Each test calls K9Contract.reset/0 in a setup block to
  ensure full isolation.
  """

  use ExUnit.Case, async: false

  alias HAR.Contracts.K9Contract
  alias HAR.ControlPlane.CircuitBreaker

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  # Build a valid contract attrs map with sensible defaults. Individual tests
  # override specific keys to exercise validation and edge cases.
  defp valid_attrs(overrides \\ %{}) do
    base = %{
      backend_pattern: "test-backend-#{System.unique_integer([:positive, :monotonic])}",
      max_decision_time_ms: 50,
      max_execution_time_ms: 5_000,
      breach_policy: :log,
      description: "Test contract",
      consistency_guarantee: :warn,
      rate_limit: 500
    }

    Map.merge(base, overrides)
  end

  # ---------------------------------------------------------------------------
  # Setup
  # ---------------------------------------------------------------------------

  setup do
    # Ensure a clean ETS table for every test. K9Contract.init/0 has already
    # been called by the application supervisor, so the table exists.
    K9Contract.reset()
    :ok
  end

  # ---------------------------------------------------------------------------
  # Registration — success
  # ---------------------------------------------------------------------------

  describe "register/1 (success)" do
    test "registers a contract with all required fields and returns {:ok, %K9Contract{}}" do
      attrs = valid_attrs()
      assert {:ok, contract} = K9Contract.register(attrs)

      assert %K9Contract{} = contract
      assert contract.backend_pattern == attrs.backend_pattern
      assert contract.max_decision_time_ms == attrs.max_decision_time_ms
      assert contract.max_execution_time_ms == attrs.max_execution_time_ms
      assert contract.breach_policy == :log
      assert contract.consistency_guarantee == :warn
      assert contract.rate_limit == 500
      assert %DateTime{} = contract.created_at
    end

    test "contract_id is a 64-character lowercase hex SHA-256 hash" do
      assert {:ok, contract} = K9Contract.register(valid_attrs())

      assert is_binary(contract.contract_id)
      assert byte_size(contract.contract_id) == 64
      assert contract.contract_id =~ ~r/^[0-9a-f]{64}$/
    end

    test "contract_id is deterministic (same inputs produce same hash)" do
      shared = %{
        backend_pattern: "deterministic-backend",
        max_decision_time_ms: 10,
        max_execution_time_ms: 1_000,
        breach_policy: :log
      }

      assert {:ok, c1} = K9Contract.register(shared)
      K9Contract.reset()
      assert {:ok, c2} = K9Contract.register(shared)

      assert c1.contract_id == c2.contract_id
    end

    test "registers with defaults for optional fields" do
      attrs = %{
        backend_pattern: "minimal-backend",
        max_decision_time_ms: 10,
        max_execution_time_ms: 1_000,
        breach_policy: :log
      }

      assert {:ok, contract} = K9Contract.register(attrs)

      # Default consistency is :warn, default rate_limit is 1000.
      assert contract.consistency_guarantee == :warn
      assert contract.rate_limit == 1_000
      assert is_binary(contract.description)
    end

    test "registers contracts with each valid breach policy" do
      for policy <- [:log, :alert, :circuit_break, :degrade] do
        attrs = valid_attrs(%{
          backend_pattern: "policy-#{policy}",
          breach_policy: policy
        })

        assert {:ok, contract} = K9Contract.register(attrs)
        assert contract.breach_policy == policy
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Registration — validation errors
  # ---------------------------------------------------------------------------

  describe "register/1 (validation)" do
    test "returns error when backend_pattern is missing" do
      attrs = valid_attrs() |> Map.delete(:backend_pattern)
      assert {:error, {:missing_required_field, :backend_pattern}} = K9Contract.register(attrs)
    end

    test "returns error when max_decision_time_ms is missing" do
      attrs = valid_attrs() |> Map.delete(:max_decision_time_ms)
      assert {:error, {:missing_required_field, :max_decision_time_ms}} = K9Contract.register(attrs)
    end

    test "returns error when max_execution_time_ms is missing" do
      attrs = valid_attrs() |> Map.delete(:max_execution_time_ms)
      assert {:error, {:missing_required_field, :max_execution_time_ms}} = K9Contract.register(attrs)
    end

    test "returns error when breach_policy is missing" do
      attrs = valid_attrs() |> Map.delete(:breach_policy)
      assert {:error, {:missing_required_field, :breach_policy}} = K9Contract.register(attrs)
    end

    test "returns error for invalid breach_policy" do
      attrs = valid_attrs(%{breach_policy: :explode})
      assert {:error, {:invalid_breach_policy, :explode, _msg}} = K9Contract.register(attrs)
    end

    test "returns error when backend_pattern is empty string" do
      attrs = valid_attrs(%{backend_pattern: ""})
      assert {:error, {:invalid_field, :backend_pattern, _msg}} = K9Contract.register(attrs)
    end

    test "returns error when max_decision_time_ms is zero" do
      attrs = valid_attrs(%{max_decision_time_ms: 0})
      assert {:error, {:invalid_field, :max_decision_time_ms, _msg}} = K9Contract.register(attrs)
    end

    test "returns error when max_decision_time_ms is negative" do
      attrs = valid_attrs(%{max_decision_time_ms: -1})
      assert {:error, {:invalid_field, :max_decision_time_ms, _msg}} = K9Contract.register(attrs)
    end

    test "returns error when max_execution_time_ms is a string" do
      attrs = valid_attrs(%{max_execution_time_ms: "fast"})
      assert {:error, {:invalid_field, :max_execution_time_ms, _msg}} = K9Contract.register(attrs)
    end
  end

  # ---------------------------------------------------------------------------
  # Lookup — exact match
  # ---------------------------------------------------------------------------

  describe "lookup/1 (exact)" do
    test "finds a contract by exact backend name" do
      attrs = valid_attrs(%{backend_pattern: "apt-backend"})
      assert {:ok, _} = K9Contract.register(attrs)

      contract = K9Contract.lookup("apt-backend")
      assert %K9Contract{} = contract
      assert contract.backend_pattern == "apt-backend"
    end

    test "returns nil for an unregistered backend" do
      assert K9Contract.lookup("no-such-backend") == nil
    end
  end

  # ---------------------------------------------------------------------------
  # Lookup — glob pattern match
  # ---------------------------------------------------------------------------

  describe "lookup/1 (glob)" do
    test "matches a trailing wildcard pattern" do
      attrs = valid_attrs(%{backend_pattern: "apt-*"})
      assert {:ok, _} = K9Contract.register(attrs)

      contract = K9Contract.lookup("apt-backend")
      assert %K9Contract{} = contract
      assert contract.backend_pattern == "apt-*"
    end

    test "matches multiple backends against the same wildcard" do
      attrs = valid_attrs(%{backend_pattern: "salt-*"})
      assert {:ok, _} = K9Contract.register(attrs)

      assert %K9Contract{} = K9Contract.lookup("salt-primary")
      assert %K9Contract{} = K9Contract.lookup("salt-secondary")
      assert %K9Contract{} = K9Contract.lookup("salt-edge-01")
    end

    test "exact match takes priority over glob" do
      assert {:ok, _} = K9Contract.register(valid_attrs(%{
        backend_pattern: "yum-*",
        max_decision_time_ms: 100
      }))

      assert {:ok, _} = K9Contract.register(valid_attrs(%{
        backend_pattern: "yum-primary",
        max_decision_time_ms: 10
      }))

      contract = K9Contract.lookup("yum-primary")
      assert contract.backend_pattern == "yum-primary"
      assert contract.max_decision_time_ms == 10
    end

    test "returns nil when no patterns match" do
      attrs = valid_attrs(%{backend_pattern: "apt-*"})
      assert {:ok, _} = K9Contract.register(attrs)

      assert K9Contract.lookup("yum-backend") == nil
    end
  end

  # ---------------------------------------------------------------------------
  # timed_enforce/3 — within SLA (no breach)
  # ---------------------------------------------------------------------------

  describe "timed_enforce/3 (within SLA)" do
    test "executes the function and returns its result when within threshold" do
      attrs = valid_attrs(%{
        backend_pattern: "fast-backend",
        max_decision_time_ms: 500
      })

      assert {:ok, _} = K9Contract.register(attrs)

      result = K9Contract.timed_enforce("fast-backend", fn ->
        {:ok, :routed}
      end)

      assert result == {:ok, :routed}
    end

    test "does not trigger breach for fast operations" do
      attrs = valid_attrs(%{
        backend_pattern: "quick-backend",
        max_decision_time_ms: 500,
        breach_policy: :degrade
      })

      assert {:ok, _} = K9Contract.register(attrs)

      K9Contract.timed_enforce("quick-backend", fn ->
        :fast_result
      end)

      # Degradation marker should NOT be set.
      refute K9Contract.degraded?("quick-backend")
    end
  end

  # ---------------------------------------------------------------------------
  # timed_enforce/3 — breach (exceeds threshold)
  # ---------------------------------------------------------------------------

  describe "timed_enforce/3 (breach)" do
    test "still returns the function result even when breached" do
      attrs = valid_attrs(%{
        backend_pattern: "slow-backend",
        max_decision_time_ms: 1,
        breach_policy: :log
      })

      assert {:ok, _} = K9Contract.register(attrs)

      result = K9Contract.timed_enforce("slow-backend", fn ->
        Process.sleep(20)
        {:ok, :slow_but_done}
      end)

      assert result == {:ok, :slow_but_done}
    end

    test "triggers breach when function exceeds max_decision_time_ms" do
      attrs = valid_attrs(%{
        backend_pattern: "breach-backend",
        max_decision_time_ms: 1,
        breach_policy: :degrade
      })

      assert {:ok, _} = K9Contract.register(attrs)

      K9Contract.timed_enforce("breach-backend", fn ->
        Process.sleep(20)
        :done
      end)

      # Degrade breach policy sets a degradation marker.
      assert K9Contract.degraded?("breach-backend")
    end
  end

  # ---------------------------------------------------------------------------
  # timed_enforce/3 — no contract (unregistered backend)
  # ---------------------------------------------------------------------------

  describe "timed_enforce/3 (no contract)" do
    test "executes the function without enforcement for unregistered backends" do
      result = K9Contract.timed_enforce("no-contract-backend", fn ->
        {:ok, :unenforced}
      end)

      assert result == {:ok, :unenforced}
    end
  end

  # ---------------------------------------------------------------------------
  # Breach policy: :log
  # ---------------------------------------------------------------------------

  describe "execute_breach_policy/4 (:log)" do
    test "returns :ok without crashing" do
      attrs = valid_attrs(%{
        backend_pattern: "log-policy",
        breach_policy: :log
      })

      assert {:ok, contract} = K9Contract.register(attrs)

      assert :ok = K9Contract.execute_breach_policy(contract, "log-policy", 100, :decision)
    end
  end

  # ---------------------------------------------------------------------------
  # Breach policy: :alert
  # ---------------------------------------------------------------------------

  describe "execute_breach_policy/4 (:alert)" do
    test "returns :ok and emits telemetry without crashing" do
      attrs = valid_attrs(%{
        backend_pattern: "alert-policy",
        breach_policy: :alert
      })

      assert {:ok, contract} = K9Contract.register(attrs)

      assert :ok = K9Contract.execute_breach_policy(contract, "alert-policy", 200, :decision)
    end
  end

  # ---------------------------------------------------------------------------
  # Breach policy: :degrade
  # ---------------------------------------------------------------------------

  describe "execute_breach_policy/4 (:degrade)" do
    test "sets a degradation marker so degraded?/1 returns true" do
      attrs = valid_attrs(%{
        backend_pattern: "degrade-policy",
        breach_policy: :degrade
      })

      assert {:ok, contract} = K9Contract.register(attrs)

      refute K9Contract.degraded?("degrade-policy")

      K9Contract.execute_breach_policy(contract, "degrade-policy", 200, :decision)

      assert K9Contract.degraded?("degrade-policy")
    end
  end

  # ---------------------------------------------------------------------------
  # Breach policy: :circuit_break
  # ---------------------------------------------------------------------------

  describe "execute_breach_policy/4 (:circuit_break)" do
    test "calls CircuitBreaker.record_failure for the backend" do
      # Register the backend with the CircuitBreaker so we can observe the
      # failure being recorded.
      cb_name = "cb-breach-#{System.unique_integer([:positive])}"
      CircuitBreaker.register(cb_name, %{failure_threshold: 2, half_open_after_ms: 5_000})

      attrs = valid_attrs(%{
        backend_pattern: cb_name,
        breach_policy: :circuit_break
      })

      assert {:ok, contract} = K9Contract.register(attrs)

      # Execute breach policy twice — should trip the circuit (threshold=2).
      K9Contract.execute_breach_policy(contract, cb_name, 200, :decision)
      K9Contract.execute_breach_policy(contract, cb_name, 300, :decision)
      Process.sleep(50)

      assert {:circuit_open, ^cb_name} = CircuitBreaker.allow?(cb_name)

      CircuitBreaker.reset(cb_name)
    end
  end

  # ---------------------------------------------------------------------------
  # degraded?/1
  # ---------------------------------------------------------------------------

  describe "degraded?/1" do
    test "returns false for a non-degraded backend" do
      refute K9Contract.degraded?("healthy-backend")
    end

    test "returns true after a :degrade breach policy fires" do
      attrs = valid_attrs(%{
        backend_pattern: "deg-check",
        max_decision_time_ms: 1,
        breach_policy: :degrade
      })

      assert {:ok, _} = K9Contract.register(attrs)

      K9Contract.timed_enforce("deg-check", fn ->
        Process.sleep(20)
        :done
      end)

      assert K9Contract.degraded?("deg-check")
    end
  end

  # ---------------------------------------------------------------------------
  # count/0 and list_all/0
  # ---------------------------------------------------------------------------

  describe "count/0" do
    test "returns 0 when no contracts are registered" do
      assert K9Contract.count() == 0
    end

    test "returns the number of registered contracts" do
      for i <- 1..3 do
        K9Contract.register(valid_attrs(%{backend_pattern: "count-#{i}"}))
      end

      assert K9Contract.count() == 3
    end

    test "does not count degradation markers" do
      attrs = valid_attrs(%{
        backend_pattern: "count-degrade",
        breach_policy: :degrade
      })

      assert {:ok, contract} = K9Contract.register(attrs)
      K9Contract.execute_breach_policy(contract, "count-degrade", 200, :decision)

      # The degradation marker is stored in the same ETS table but should
      # not be counted as a contract.
      assert K9Contract.count() == 1
    end
  end

  describe "list_all/0" do
    test "returns empty list when no contracts are registered" do
      assert K9Contract.list_all() == []
    end

    test "returns all registered contracts" do
      for i <- 1..3 do
        K9Contract.register(valid_attrs(%{backend_pattern: "list-#{i}"}))
      end

      contracts = K9Contract.list_all()
      assert length(contracts) == 3

      patterns = Enum.map(contracts, & &1.backend_pattern) |> Enum.sort()
      assert patterns == ["list-1", "list-2", "list-3"]
    end

    test "each element is a %K9Contract{} struct" do
      K9Contract.register(valid_attrs(%{backend_pattern: "list-struct"}))

      [contract] = K9Contract.list_all()
      assert %K9Contract{} = contract
    end
  end

  # ---------------------------------------------------------------------------
  # remove/1
  # ---------------------------------------------------------------------------

  describe "remove/1" do
    test "removes a registered contract so lookup returns nil" do
      attrs = valid_attrs(%{backend_pattern: "remove-me"})
      assert {:ok, _} = K9Contract.register(attrs)

      assert %K9Contract{} = K9Contract.lookup("remove-me")

      assert :ok = K9Contract.remove("remove-me")

      assert K9Contract.lookup("remove-me") == nil
    end

    test "decrements count after removal" do
      K9Contract.register(valid_attrs(%{backend_pattern: "rm-a"}))
      K9Contract.register(valid_attrs(%{backend_pattern: "rm-b"}))
      assert K9Contract.count() == 2

      K9Contract.remove("rm-a")
      assert K9Contract.count() == 1
    end

    test "returns :ok when removing a non-existent contract" do
      assert :ok = K9Contract.remove("never-registered")
    end
  end

  # ---------------------------------------------------------------------------
  # reset/0
  # ---------------------------------------------------------------------------

  describe "reset/0" do
    test "clears all contracts so count returns 0" do
      for i <- 1..5 do
        K9Contract.register(valid_attrs(%{backend_pattern: "reset-#{i}"}))
      end

      assert K9Contract.count() == 5

      assert :ok = K9Contract.reset()

      assert K9Contract.count() == 0
      assert K9Contract.list_all() == []
    end

    test "clears degradation markers as well" do
      attrs = valid_attrs(%{
        backend_pattern: "reset-deg",
        breach_policy: :degrade
      })

      assert {:ok, contract} = K9Contract.register(attrs)
      K9Contract.execute_breach_policy(contract, "reset-deg", 200, :decision)
      assert K9Contract.degraded?("reset-deg")

      K9Contract.reset()

      refute K9Contract.degraded?("reset-deg")
    end
  end

  # ---------------------------------------------------------------------------
  # parse_breach_policy/1
  # ---------------------------------------------------------------------------

  describe "parse_breach_policy/1" do
    test "parses known breach policy strings to atoms" do
      assert K9Contract.parse_breach_policy("log") == :log
      assert K9Contract.parse_breach_policy("alert") == :alert
      assert K9Contract.parse_breach_policy("circuit_break") == :circuit_break
      assert K9Contract.parse_breach_policy("degrade") == :degrade
    end

    test "defaults to :log for unknown strings" do
      assert K9Contract.parse_breach_policy("unknown") == :log
      assert K9Contract.parse_breach_policy("explode") == :log
      assert K9Contract.parse_breach_policy("") == :log
    end

    test "defaults to :log for nil" do
      assert K9Contract.parse_breach_policy(nil) == :log
    end
  end

  # ---------------------------------------------------------------------------
  # parse_consistency/1
  # ---------------------------------------------------------------------------

  describe "parse_consistency/1" do
    test "parses known consistency strings to atoms" do
      assert K9Contract.parse_consistency("none") == :none
      assert K9Contract.parse_consistency("warn") == :warn
      assert K9Contract.parse_consistency("strict") == :strict
    end

    test "defaults to :warn for unknown strings" do
      assert K9Contract.parse_consistency("bogus") == :warn
      assert K9Contract.parse_consistency("eventual") == :warn
      assert K9Contract.parse_consistency("") == :warn
    end

    test "defaults to :warn for nil" do
      assert K9Contract.parse_consistency(nil) == :warn
    end
  end
end

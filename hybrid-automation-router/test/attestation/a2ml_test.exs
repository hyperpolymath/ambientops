# SPDX-License-Identifier: MPL-2.0
defmodule HAR.Attestation.A2MLTest do
  @moduledoc """
  Tests for the HAR.Attestation.A2ML module.

  Verifies that routing decisions are correctly attested in a2ml envelope
  format, including content-addressable hashing, sensitive parameter
  redaction, and tamper-detection via hash verification.
  """

  use ExUnit.Case, async: true

  alias HAR.Attestation.A2ML
  alias HAR.ControlPlane.RoutingDecision
  alias HAR.Semantic.Operation

  describe "attest/1" do
    test "produces valid envelope with a2ml and payload keys" do
      decision = build_decision()

      attestation = A2ML.attest(decision)

      assert %{"a2ml" => _envelope, "payload" => _payload} = attestation
      assert is_map(attestation["a2ml"])
      assert is_map(attestation["payload"])
    end

    test "envelope metadata contains version, type, issuer, and decision_hash" do
      decision = build_decision()

      %{"a2ml" => envelope} = A2ML.attest(decision)

      assert envelope["version"] == "1.0"
      assert envelope["type"] == "routing-attestation"
      assert envelope["issuer"] == "har"
      assert is_binary(envelope["issued_at"])
      assert String.starts_with?(envelope["decision_hash"], "sha256:")
    end

    test "payload contains all expected fields" do
      decision = build_decision()

      %{"payload" => payload} = A2ML.attest(decision)

      assert payload["operation_type"] == "package_install"
      assert payload["operation_params"] == %{package: "nginx"}
      assert payload["backend"] == "apt-backend"
      assert payload["alternatives"] == ["yum-backend"]
      assert payload["reason"] == "pattern_match"
      assert is_binary(payload["timestamp"])
    end

    test "redacts sensitive params: password, token, secret, api_key" do
      decision =
        build_decision(
          params: %{
            package: "nginx",
            password: "s3cret",
            token: "tok_abc123",
            secret: "my-secret",
            api_key: "AKIAIOSFODNN7EXAMPLE"
          }
        )

      %{"payload" => payload} = A2ML.attest(decision)

      refute Map.has_key?(payload["operation_params"], :password)
      refute Map.has_key?(payload["operation_params"], :token)
      refute Map.has_key?(payload["operation_params"], :secret)
      refute Map.has_key?(payload["operation_params"], :api_key)
    end

    test "preserves non-sensitive params: package, service, name" do
      decision =
        build_decision(
          params: %{
            package: "nginx",
            service: "web",
            name: "my-app"
          }
        )

      %{"payload" => payload} = A2ML.attest(decision)

      assert payload["operation_params"][:package] == "nginx"
      assert payload["operation_params"][:service] == "web"
      assert payload["operation_params"][:name] == "my-app"
    end

    test "deterministic hash for identical decision data" do
      timestamp = ~U[2026-02-28 12:00:00Z]
      decision = build_decision(timestamp: timestamp)

      %{"a2ml" => envelope_a} = A2ML.attest(decision)
      %{"a2ml" => envelope_b} = A2ML.attest(decision)

      # The decision_hash is computed from the payload, which is deterministic
      # for the same input. The issued_at differs but is not part of the hash.
      assert envelope_a["decision_hash"] == envelope_b["decision_hash"]
    end

    test "handles non-map params without crashing" do
      decision = build_decision(params: nil)

      attestation = A2ML.attest(decision)

      assert %{"a2ml" => _envelope, "payload" => payload} = attestation
      assert payload["operation_params"] == nil
    end
  end

  describe "verify/1" do
    test "returns true for valid untampered attestation" do
      decision = build_decision()
      attestation = A2ML.attest(decision)

      assert A2ML.verify(attestation) == true
    end

    test "returns false when payload backend is tampered" do
      decision = build_decision()
      attestation = A2ML.attest(decision)

      tampered = put_in(attestation, ["payload", "backend"], "evil-backend")

      assert A2ML.verify(tampered) == false
    end

    test "returns false when decision_hash is tampered" do
      decision = build_decision()
      attestation = A2ML.attest(decision)

      tampered = put_in(attestation, ["a2ml", "decision_hash"], "sha256:0000000000000000")

      assert A2ML.verify(tampered) == false
    end

    test "returns false for nil input" do
      assert A2ML.verify(nil) == false
    end

    test "returns false for empty map" do
      assert A2ML.verify(%{}) == false
    end

    test "returns false for map missing a2ml key" do
      assert A2ML.verify(%{"payload" => %{}}) == false
    end

    test "returns false for map missing payload key" do
      assert A2ML.verify(%{"a2ml" => %{"decision_hash" => "sha256:abc"}}) == false
    end
  end

  describe "attest_plan/1" do
    test "produces one attestation per decision" do
      decisions = [
        build_decision(id: "op1", backend: "backend-a"),
        build_decision(id: "op2", backend: "backend-b"),
        build_decision(id: "op3", backend: "backend-c")
      ]

      attestations = A2ML.attest_plan(decisions)

      assert length(attestations) == 3
    end

    test "each attestation in plan is independently verifiable" do
      decisions = [
        build_decision(id: "op1", backend: "backend-a"),
        build_decision(id: "op2", backend: "backend-b"),
        build_decision(id: "op3", backend: "backend-c")
      ]

      attestations = A2ML.attest_plan(decisions)

      for attestation <- attestations do
        assert A2ML.verify(attestation) == true
      end
    end

    test "attestations preserve decision ordering" do
      decisions = [
        build_decision(id: "first", backend: "alpha"),
        build_decision(id: "second", backend: "beta"),
        build_decision(id: "third", backend: "gamma")
      ]

      attestations = A2ML.attest_plan(decisions)

      backends = Enum.map(attestations, fn a -> a["payload"]["backend"] end)
      assert backends == ["alpha", "beta", "gamma"]
    end
  end

  # ---------------------------------------------------------------------------
  # Test Helpers
  # ---------------------------------------------------------------------------

  # Build a RoutingDecision struct for testing. Accepts keyword overrides
  # for any field to allow concise per-test customisation.
  defp build_decision(opts \\ []) do
    op =
      Operation.new(
        Keyword.get(opts, :type, :package_install),
        Keyword.get(opts, :params, %{package: "nginx"}),
        id: Keyword.get(opts, :id, "op1")
      )

    %RoutingDecision{
      operation: op,
      backend: %{name: Keyword.get(opts, :backend, "apt-backend")},
      alternatives: Keyword.get(opts, :alternatives, [%{name: "yum-backend"}]),
      reason: Keyword.get(opts, :reason, :pattern_match),
      timestamp: Keyword.get(opts, :timestamp, DateTime.utc_now())
    }
  end
end

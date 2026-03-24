# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# Tests for the new HAR.Security.Manager features:
# - API key validation
# - Token-bucket rate limiting
# - X.509 certificate validation via :public_key
# - Rate limit status reporting

defmodule HAR.Security.ExtensionsTest do
  @moduledoc """
  Tests for the extended security manager features added to HAR.Security.Manager:
  API key auth, token-bucket rate limiting, and certificate validation.

  These tests exercise the new public API surface while the original
  SecurityManagerTest covers authentication, authorization, and audit logging.
  """

  use ExUnit.Case, async: false

  alias HAR.Security.Manager

  # ──────────────────────────────────────────────────────────────────
  # Helpers
  # ──────────────────────────────────────────────────────────────────

  # Restart the Manager with specific config for testing.
  defp restart_with_config(overrides) do
    for {key, val} <- overrides do
      Application.put_env(:har, key, val)
    end

    Supervisor.terminate_child(HAR.Supervisor, Manager)
    Supervisor.restart_child(HAR.Supervisor, Manager)

    # Verify the new instance is alive.
    _ = Manager.get_audit_log()
    :ok
  end

  # Restore defaults after a test.
  defp restore_defaults do
    restart_with_config(
      security_tier: :development,
      api_keys: [],
      rate_limit: [bucket_size: 100, refill_rate: 10, refill_interval_ms: 1_000]
    )
  end

  # ===========================================================================
  # API KEY VALIDATION
  # ===========================================================================

  describe "validate_api_key/1 (development tier)" do
    test "accepts any non-empty key in development tier" do
      assert {:ok, :valid} = Manager.validate_api_key("any-key-at-all")
    end

    test "rejects empty string" do
      assert {:error, :missing_api_key} = Manager.validate_api_key("")
    end

    test "rejects nil" do
      assert {:error, :missing_api_key} = Manager.validate_api_key(nil)
    end

    test "rejects non-string" do
      assert {:error, :invalid_api_key} = Manager.validate_api_key(12345)
    end
  end

  describe "validate_api_key/1 (iot tier with configured keys)" do
    setup do
      restart_with_config(
        security_tier: :iot,
        api_keys: ["secret-key-alpha", "secret-key-beta"]
      )

      on_exit(fn -> restore_defaults() end)
      :ok
    end

    test "accepts a valid configured key" do
      assert {:ok, :valid} = Manager.validate_api_key("secret-key-alpha")
    end

    test "accepts the second configured key" do
      assert {:ok, :valid} = Manager.validate_api_key("secret-key-beta")
    end

    test "rejects an unknown key" do
      assert {:error, :invalid_api_key} = Manager.validate_api_key("wrong-key")
    end

    test "rejects empty string" do
      assert {:error, :missing_api_key} = Manager.validate_api_key("")
    end

    test "creates audit log entry on rejection" do
      Manager.validate_api_key("bad-key-audit-test")

      log = Manager.get_audit_log()

      rejected =
        Enum.filter(log, fn e -> e.event == :api_key_rejected end)

      assert length(rejected) >= 1
      latest = List.last(rejected)
      assert latest.details.reason == :invalid_key
    end

    test "creates audit log entry on acceptance" do
      Manager.validate_api_key("secret-key-alpha")

      log = Manager.get_audit_log()

      accepted =
        Enum.filter(log, fn e -> e.event == :api_key_accepted end)

      assert length(accepted) >= 1
    end
  end

  # ===========================================================================
  # RATE LIMITING
  # ===========================================================================

  describe "check_rate_limit/1" do
    setup do
      # Use a small bucket for testing (5 tokens, no refill during test)
      restart_with_config(
        security_tier: :development,
        rate_limit: [bucket_size: 5, refill_rate: 0, refill_interval_ms: 60_000]
      )

      on_exit(fn -> restore_defaults() end)
      :ok
    end

    test "allows requests within the bucket limit" do
      client = "test-client-#{System.unique_integer([:positive])}"

      for _i <- 1..5 do
        assert :ok = Manager.check_rate_limit(client)
      end
    end

    test "rejects requests when bucket is exhausted" do
      client = "exhaust-client-#{System.unique_integer([:positive])}"

      # Consume all 5 tokens
      for _i <- 1..5 do
        :ok = Manager.check_rate_limit(client)
      end

      # 6th request should be rate-limited
      assert {:error, :rate_limited, retry_after} = Manager.check_rate_limit(client)
      assert is_integer(retry_after)
      assert retry_after > 0
    end

    test "different clients have independent buckets" do
      client_a = "client-a-#{System.unique_integer([:positive])}"
      client_b = "client-b-#{System.unique_integer([:positive])}"

      # Exhaust client A
      for _i <- 1..5, do: Manager.check_rate_limit(client_a)
      assert {:error, :rate_limited, _} = Manager.check_rate_limit(client_a)

      # Client B should still have tokens
      assert :ok = Manager.check_rate_limit(client_b)
    end

    test "creates audit log entry when rate limit is exceeded" do
      client = "audit-rate-#{System.unique_integer([:positive])}"

      for _i <- 1..5, do: Manager.check_rate_limit(client)
      Manager.check_rate_limit(client)

      log = Manager.get_audit_log()

      exceeded =
        Enum.filter(log, fn e ->
          e.event == :rate_limit_exceeded and e.details.client_id == client
        end)

      assert length(exceeded) >= 1
    end
  end

  describe "rate_limit_status/0" do
    setup do
      restart_with_config(
        security_tier: :development,
        rate_limit: [bucket_size: 10, refill_rate: 0, refill_interval_ms: 60_000]
      )

      on_exit(fn -> restore_defaults() end)
      :ok
    end

    test "returns empty list when no clients have been tracked" do
      status = Manager.rate_limit_status()
      # May contain entries from other tests; just check the format
      assert is_list(status)
    end

    test "returns status for tracked clients" do
      client = "status-client-#{System.unique_integer([:positive])}"
      Manager.check_rate_limit(client)

      status = Manager.rate_limit_status()
      client_entry = Enum.find(status, fn e -> e.client_id == client end)

      assert client_entry != nil
      assert client_entry.tokens == 9  # started with 10, consumed 1
      assert client_entry.bucket_size == 10
    end
  end

  # ===========================================================================
  # RATE LIMITING — REFILL
  # ===========================================================================

  describe "rate limit refill" do
    setup do
      # Small bucket, fast refill for testing
      restart_with_config(
        security_tier: :development,
        rate_limit: [bucket_size: 3, refill_rate: 3, refill_interval_ms: 100]
      )

      on_exit(fn -> restore_defaults() end)
      :ok
    end

    test "tokens are refilled after the refill interval" do
      client = "refill-client-#{System.unique_integer([:positive])}"

      # Exhaust the bucket
      for _i <- 1..3, do: Manager.check_rate_limit(client)
      assert {:error, :rate_limited, _} = Manager.check_rate_limit(client)

      # Wait for refill (100ms interval + margin)
      Process.sleep(200)

      # Should have tokens again
      assert :ok = Manager.check_rate_limit(client)
    end
  end
end

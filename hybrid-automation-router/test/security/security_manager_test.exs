# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
defmodule HAR.Security.ManagerTest do
  @moduledoc """
  Tests for the HAR.Security.Manager GenServer.

  Exercises the three core security functions:

  1. **Authentication** — Certificate-based device/user authentication across
     all four security tiers (development, iot, industrial, critical). Validates
     that the development tier always succeeds, while higher tiers enforce
     certificate field presence and expiration checking.

  2. **Authorization** — Policy-based operation authorization. Verifies that
     the development tier permits all operations, while restricted tiers
     (iot, industrial, critical) enforce their operation allow-lists and
     deny unlisted operations.

  3. **Audit Logging** — Immutable ETS-backed audit log. Confirms that
     authentication and authorization events are automatically recorded,
     manual audit_log/2 entries are persisted, entries are ordered, and
     the log survives across multiple operations.

  ## Test Strategy

  The Manager is started by the application supervision tree as a named
  singleton. For the default development tier, tests use the running instance
  directly. For non-default tier tests, `Supervisor.terminate_child/2` and
  `Supervisor.restart_child/2` are used to cycle the process with new
  application config, which avoids exhausting the supervisor's restart
  budget.

  Tests are `async: false` because the GenServer is a named singleton backed
  by shared ETS tables (:security_audit_log and :security_policies).
  """

  use ExUnit.Case, async: false

  alias HAR.Security.Manager

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  # Build a valid certificate map with sensible defaults. The certificate is
  # valid from 2025-01-01 to 2027-01-01, which brackets the current date
  # (2026-02-28) comfortably.
  defp valid_cert(overrides \\ %{}) do
    Map.merge(
      %{
        subject: "CN=device-#{System.unique_integer([:positive, :monotonic])}",
        issuer: "CN=HAR-CA",
        not_before: ~U[2025-01-01 00:00:00Z],
        not_after: ~U[2027-01-01 00:00:00Z]
      },
      overrides
    )
  end

  # Build an expired certificate (not_after is in the past).
  defp expired_cert(overrides) do
    valid_cert(
      Map.merge(
        %{
          not_before: ~U[2023-01-01 00:00:00Z],
          not_after: ~U[2024-01-01 00:00:00Z]
        },
        overrides
      )
    )
  end

  # Build a not-yet-valid certificate (not_before is in the future).
  defp future_cert(overrides) do
    valid_cert(
      Map.merge(
        %{
          not_before: ~U[2028-01-01 00:00:00Z],
          not_after: ~U[2029-01-01 00:00:00Z]
        },
        overrides
      )
    )
  end

  # Gracefully cycle the Security.Manager process with a new security tier.
  # Uses Supervisor.terminate_child/restart_child to avoid exhausting the
  # supervisor's max_restarts budget (which Process.exit(:kill) would do).
  defp restart_with_tier(tier) do
    Application.put_env(:har, :security_tier, tier)
    Supervisor.terminate_child(HAR.Supervisor, Manager)
    Supervisor.restart_child(HAR.Supervisor, Manager)

    # Verify the new instance is alive and responsive.
    _ = Manager.get_audit_log()
    :ok
  end

  # ===========================================================================
  # AUTHENTICATION — Development Tier
  # ===========================================================================

  describe "authenticate/1 (development tier)" do
    test "succeeds with a valid certificate" do
      cert = valid_cert(%{subject: "CN=dev-device-01"})
      assert {:ok, identity} = Manager.authenticate(cert)

      assert identity.authenticated == true
      assert identity.device_id == "CN=dev-device-01"
      assert identity.tier == :development
    end

    test "succeeds even with an expired certificate (development tier is permissive)" do
      cert = expired_cert(%{subject: "CN=expired-dev"})
      assert {:ok, identity} = Manager.authenticate(cert)

      assert identity.authenticated == true
      assert identity.device_id == "CN=expired-dev"
      assert identity.tier == :development
    end

    test "succeeds with a not-yet-valid certificate in development" do
      cert = future_cert(%{subject: "CN=future-dev"})
      assert {:ok, identity} = Manager.authenticate(cert)

      assert identity.authenticated == true
      assert identity.device_id == "CN=future-dev"
    end

    test "succeeds with minimal cert fields (only subject)" do
      cert = %{subject: "CN=minimal-device"}
      assert {:ok, identity} = Manager.authenticate(cert)

      assert identity.device_id == "CN=minimal-device"
      assert identity.tier == :development
    end

    test "succeeds with an empty cert map (device_id defaults to unknown_device)" do
      assert {:ok, identity} = Manager.authenticate(%{})

      assert identity.authenticated == true
      assert identity.device_id == "unknown_device"
      assert identity.tier == :development
    end

    test "records an auth_success audit entry on successful authentication" do
      cert = valid_cert(%{subject: "CN=audit-check-dev"})
      {:ok, _identity} = Manager.authenticate(cert)

      log = Manager.get_audit_log()
      auth_events = Enum.filter(log, fn entry -> entry.event == :auth_success end)

      assert length(auth_events) >= 1

      latest = List.last(auth_events)
      assert latest.details.device_id == "CN=audit-check-dev"
      assert latest.details.tier == :development
    end
  end

  # ===========================================================================
  # AUTHENTICATION — IoT Tier
  # ===========================================================================

  describe "authenticate/1 (iot tier)" do
    setup do
      restart_with_tier(:iot)
      on_exit(fn -> restart_with_tier(:development) end)
      :ok
    end

    test "succeeds with a valid certificate" do
      cert = valid_cert(%{subject: "CN=iot-sensor-01"})
      assert {:ok, identity} = Manager.authenticate(cert)

      assert identity.authenticated == true
      assert identity.device_id == "CN=iot-sensor-01"
      assert identity.tier == :iot
    end

    test "fails with an expired certificate" do
      cert = expired_cert(%{subject: "CN=iot-expired"})
      assert {:error, :cert_expired} = Manager.authenticate(cert)
    end

    test "fails with a not-yet-valid certificate" do
      cert = future_cert(%{subject: "CN=iot-future"})
      assert {:error, :cert_not_yet_valid} = Manager.authenticate(cert)
    end

    test "fails when required certificate fields are missing" do
      cert = %{subject: "CN=iot-incomplete"}
      assert {:error, {:missing_cert_fields, missing}} = Manager.authenticate(cert)

      assert :issuer in missing
      assert :not_before in missing
      assert :not_after in missing
    end

    test "fails when subject is missing from certificate" do
      cert = %{issuer: "CN=HAR-CA", not_before: ~U[2025-01-01 00:00:00Z], not_after: ~U[2027-01-01 00:00:00Z]}
      assert {:error, {:missing_cert_fields, missing}} = Manager.authenticate(cert)

      assert :subject in missing
    end

    test "records an auth_failure audit entry when authentication fails" do
      cert = expired_cert(%{subject: "CN=iot-audit-fail"})
      {:error, :cert_expired} = Manager.authenticate(cert)

      log = Manager.get_audit_log()
      failure_events = Enum.filter(log, fn entry -> entry.event == :auth_failure end)

      assert length(failure_events) >= 1

      latest = List.last(failure_events)
      assert latest.details.device_id == "CN=iot-audit-fail"
      assert latest.details.reason == :cert_expired
    end

    test "records auth_success audit entry on valid certificate" do
      cert = valid_cert(%{subject: "CN=iot-audit-success"})
      {:ok, _identity} = Manager.authenticate(cert)

      log = Manager.get_audit_log()
      success_events = Enum.filter(log, fn entry -> entry.event == :auth_success end)

      assert length(success_events) >= 1

      latest = List.last(success_events)
      assert latest.details.device_id == "CN=iot-audit-success"
      assert latest.details.tier == :iot
    end
  end

  # ===========================================================================
  # AUTHENTICATION — Industrial Tier
  # ===========================================================================

  describe "authenticate/1 (industrial tier)" do
    setup do
      restart_with_tier(:industrial)
      on_exit(fn -> restart_with_tier(:development) end)
      :ok
    end

    test "succeeds with a valid certificate" do
      cert = valid_cert(%{subject: "CN=plc-controller-01"})
      assert {:ok, identity} = Manager.authenticate(cert)

      assert identity.authenticated == true
      assert identity.device_id == "CN=plc-controller-01"
      assert identity.tier == :industrial
    end

    test "fails with an expired certificate" do
      cert = expired_cert(%{subject: "CN=industrial-expired"})
      assert {:error, :cert_expired} = Manager.authenticate(cert)
    end

    test "fails with a not-yet-valid certificate" do
      cert = future_cert(%{subject: "CN=industrial-future"})
      assert {:error, :cert_not_yet_valid} = Manager.authenticate(cert)
    end

    test "fails when all certificate fields are missing" do
      assert {:error, {:missing_cert_fields, missing}} = Manager.authenticate(%{})

      assert :subject in missing
      assert :issuer in missing
      assert :not_before in missing
      assert :not_after in missing
      assert length(missing) == 4
    end
  end

  # ===========================================================================
  # AUTHENTICATION — Critical Tier
  # ===========================================================================

  describe "authenticate/1 (critical tier)" do
    setup do
      restart_with_tier(:critical)
      on_exit(fn -> restart_with_tier(:development) end)
      :ok
    end

    test "succeeds with a valid certificate" do
      cert = valid_cert(%{subject: "CN=hsm-device-01"})
      assert {:ok, identity} = Manager.authenticate(cert)

      assert identity.authenticated == true
      assert identity.device_id == "CN=hsm-device-01"
      assert identity.tier == :critical
    end

    test "fails with an expired certificate" do
      cert = expired_cert(%{subject: "CN=critical-expired"})
      assert {:error, :cert_expired} = Manager.authenticate(cert)
    end

    test "fails with a not-yet-valid certificate" do
      cert = future_cert(%{subject: "CN=critical-future"})
      assert {:error, :cert_not_yet_valid} = Manager.authenticate(cert)
    end

    test "fails with missing fields" do
      cert = %{subject: "CN=critical-incomplete", issuer: "CN=HAR-HSM-CA"}
      assert {:error, {:missing_cert_fields, missing}} = Manager.authenticate(cert)

      assert :not_before in missing
      assert :not_after in missing
    end
  end

  # ===========================================================================
  # AUTHORIZATION — Development Tier (all operations allowed)
  # ===========================================================================

  describe "authorize/2 (development tier)" do
    test "allows :package_install" do
      identity = %{device_id: "CN=dev-device", tier: :development}
      assert :ok = Manager.authorize(identity, :package_install)
    end

    test "allows :command_run" do
      identity = %{device_id: "CN=dev-device", tier: :development}
      assert :ok = Manager.authorize(identity, :command_run)
    end

    test "allows any arbitrary operation atom" do
      identity = %{device_id: "CN=dev-device", tier: :development}
      assert :ok = Manager.authorize(identity, :nuclear_launch_codes)
    end

    test "allows operations passed as a map with :type key" do
      identity = %{device_id: "CN=dev-device", tier: :development}
      operation = %{type: :service_restart, target: "nginx"}
      assert :ok = Manager.authorize(identity, operation)
    end

    test "handles operations without :type key (extracts as :unknown)" do
      identity = %{device_id: "CN=dev-device", tier: :development}
      operation = %{name: "some_op"}
      assert :ok = Manager.authorize(identity, operation)
    end

    test "records authz_success audit entry" do
      identity = %{device_id: "CN=dev-authz-audit", tier: :development}
      :ok = Manager.authorize(identity, :file_write)

      log = Manager.get_audit_log()
      authz_events = Enum.filter(log, fn entry -> entry.event == :authz_success end)

      assert length(authz_events) >= 1

      latest = List.last(authz_events)
      assert latest.details.device_id == "CN=dev-authz-audit"
      assert latest.details.operation == :file_write
    end
  end

  # ===========================================================================
  # AUTHORIZATION — IoT Tier (restricted operations)
  # ===========================================================================

  describe "authorize/2 (iot tier)" do
    setup do
      restart_with_tier(:iot)
      on_exit(fn -> restart_with_tier(:development) end)
      :ok
    end

    test "allows :package_install (in IoT allow-list)" do
      identity = %{device_id: "CN=iot-device", tier: :iot}
      assert :ok = Manager.authorize(identity, :package_install)
    end

    test "allows :package_remove (in IoT allow-list)" do
      identity = %{device_id: "CN=iot-device", tier: :iot}
      assert :ok = Manager.authorize(identity, :package_remove)
    end

    test "allows :service_start (in IoT allow-list)" do
      identity = %{device_id: "CN=iot-device", tier: :iot}
      assert :ok = Manager.authorize(identity, :service_start)
    end

    test "allows :service_stop (in IoT allow-list)" do
      identity = %{device_id: "CN=iot-device", tier: :iot}
      assert :ok = Manager.authorize(identity, :service_stop)
    end

    test "allows :service_restart (in IoT allow-list)" do
      identity = %{device_id: "CN=iot-device", tier: :iot}
      assert :ok = Manager.authorize(identity, :service_restart)
    end

    test "allows :file_write (in IoT allow-list)" do
      identity = %{device_id: "CN=iot-device", tier: :iot}
      assert :ok = Manager.authorize(identity, :file_write)
    end

    test "allows :file_copy (in IoT allow-list)" do
      identity = %{device_id: "CN=iot-device", tier: :iot}
      assert :ok = Manager.authorize(identity, :file_copy)
    end

    test "allows :command_run (in IoT allow-list)" do
      identity = %{device_id: "CN=iot-device", tier: :iot}
      assert :ok = Manager.authorize(identity, :command_run)
    end

    test "denies :network_create (not in IoT allow-list)" do
      identity = %{device_id: "CN=iot-device", tier: :iot}
      assert {:error, {:unauthorized, :network_create}} = Manager.authorize(identity, :network_create)
    end

    test "denies :user_create (not in IoT allow-list)" do
      identity = %{device_id: "CN=iot-device", tier: :iot}
      assert {:error, {:unauthorized, :user_create}} = Manager.authorize(identity, :user_create)
    end

    test "denies arbitrary operations (not in IoT allow-list)" do
      identity = %{device_id: "CN=iot-device", tier: :iot}
      assert {:error, {:unauthorized, :nuclear_launch_codes}} = Manager.authorize(identity, :nuclear_launch_codes)
    end

    test "records authz_denied audit entry for unauthorized operations" do
      identity = %{device_id: "CN=iot-denied-audit", tier: :iot}
      {:error, {:unauthorized, :forbidden_op}} = Manager.authorize(identity, :forbidden_op)

      log = Manager.get_audit_log()
      denied_events = Enum.filter(log, fn entry -> entry.event == :authz_denied end)

      assert length(denied_events) >= 1

      latest = List.last(denied_events)
      assert latest.details.device_id == "CN=iot-denied-audit"
      assert latest.details.operation == :forbidden_op
      assert latest.details.reason == :operation_not_allowed
    end

    test "records authz_success audit entry for allowed operations" do
      identity = %{device_id: "CN=iot-success-audit", tier: :iot}
      :ok = Manager.authorize(identity, :package_install)

      log = Manager.get_audit_log()
      success_events = Enum.filter(log, fn entry -> entry.event == :authz_success end)

      assert length(success_events) >= 1

      latest = List.last(success_events)
      assert latest.details.device_id == "CN=iot-success-audit"
      assert latest.details.operation == :package_install
    end

    test "extracts operation type from map with :type key" do
      identity = %{device_id: "CN=iot-map-op", tier: :iot}
      operation = %{type: :service_restart, target: "nginx"}
      assert :ok = Manager.authorize(identity, operation)
    end

    test "denies map operation when :type is not in allow-list" do
      identity = %{device_id: "CN=iot-map-denied", tier: :iot}
      operation = %{type: :network_create, target: "vlan100"}
      assert {:error, {:unauthorized, :network_create}} = Manager.authorize(identity, operation)
    end
  end

  # ===========================================================================
  # AUTHORIZATION — Industrial Tier (more restricted)
  # ===========================================================================

  describe "authorize/2 (industrial tier)" do
    setup do
      restart_with_tier(:industrial)
      on_exit(fn -> restart_with_tier(:development) end)
      :ok
    end

    test "allows :package_install (in industrial allow-list)" do
      identity = %{device_id: "CN=plc-01", tier: :industrial}
      assert :ok = Manager.authorize(identity, :package_install)
    end

    test "allows :service_start (in industrial allow-list)" do
      identity = %{device_id: "CN=plc-01", tier: :industrial}
      assert :ok = Manager.authorize(identity, :service_start)
    end

    test "allows :service_stop (in industrial allow-list)" do
      identity = %{device_id: "CN=plc-01", tier: :industrial}
      assert :ok = Manager.authorize(identity, :service_stop)
    end

    test "allows :service_restart (in industrial allow-list)" do
      identity = %{device_id: "CN=plc-01", tier: :industrial}
      assert :ok = Manager.authorize(identity, :service_restart)
    end

    test "allows :file_write (in industrial allow-list)" do
      identity = %{device_id: "CN=plc-01", tier: :industrial}
      assert :ok = Manager.authorize(identity, :file_write)
    end

    test "denies :command_run (not in industrial allow-list)" do
      identity = %{device_id: "CN=plc-01", tier: :industrial}
      assert {:error, {:unauthorized, :command_run}} = Manager.authorize(identity, :command_run)
    end

    test "denies :file_copy (not in industrial allow-list)" do
      identity = %{device_id: "CN=plc-01", tier: :industrial}
      assert {:error, {:unauthorized, :file_copy}} = Manager.authorize(identity, :file_copy)
    end

    test "denies :package_remove (not in industrial allow-list)" do
      identity = %{device_id: "CN=plc-01", tier: :industrial}
      assert {:error, {:unauthorized, :package_remove}} = Manager.authorize(identity, :package_remove)
    end

    test "denies :network_create (not in industrial allow-list)" do
      identity = %{device_id: "CN=plc-01", tier: :industrial}
      assert {:error, {:unauthorized, :network_create}} = Manager.authorize(identity, :network_create)
    end
  end

  # ===========================================================================
  # AUTHORIZATION — Critical Tier (most restricted)
  # ===========================================================================

  describe "authorize/2 (critical tier)" do
    setup do
      restart_with_tier(:critical)
      on_exit(fn -> restart_with_tier(:development) end)
      :ok
    end

    test "allows :service_start (in critical allow-list)" do
      identity = %{device_id: "CN=hsm-01", tier: :critical}
      assert :ok = Manager.authorize(identity, :service_start)
    end

    test "allows :service_stop (in critical allow-list)" do
      identity = %{device_id: "CN=hsm-01", tier: :critical}
      assert :ok = Manager.authorize(identity, :service_stop)
    end

    test "allows :service_restart (in critical allow-list)" do
      identity = %{device_id: "CN=hsm-01", tier: :critical}
      assert :ok = Manager.authorize(identity, :service_restart)
    end

    test "denies :package_install (not in critical allow-list)" do
      identity = %{device_id: "CN=hsm-01", tier: :critical}
      assert {:error, {:unauthorized, :package_install}} = Manager.authorize(identity, :package_install)
    end

    test "denies :file_write (not in critical allow-list)" do
      identity = %{device_id: "CN=hsm-01", tier: :critical}
      assert {:error, {:unauthorized, :file_write}} = Manager.authorize(identity, :file_write)
    end

    test "denies :command_run (not in critical allow-list)" do
      identity = %{device_id: "CN=hsm-01", tier: :critical}
      assert {:error, {:unauthorized, :command_run}} = Manager.authorize(identity, :command_run)
    end

    test "denies :file_copy (not in critical allow-list)" do
      identity = %{device_id: "CN=hsm-01", tier: :critical}
      assert {:error, {:unauthorized, :file_copy}} = Manager.authorize(identity, :file_copy)
    end

    test "denies :package_remove (not in critical allow-list)" do
      identity = %{device_id: "CN=hsm-01", tier: :critical}
      assert {:error, {:unauthorized, :package_remove}} = Manager.authorize(identity, :package_remove)
    end

    test "only allows the 3 service operations in critical tier" do
      identity = %{device_id: "CN=hsm-exhaustive", tier: :critical}

      # These three MUST succeed.
      assert :ok = Manager.authorize(identity, :service_start)
      assert :ok = Manager.authorize(identity, :service_stop)
      assert :ok = Manager.authorize(identity, :service_restart)

      # Every other common operation MUST fail.
      denied_ops = [
        :package_install,
        :package_remove,
        :file_write,
        :file_copy,
        :command_run,
        :network_create,
        :user_create,
        :firewall_rule
      ]

      for op <- denied_ops do
        assert {:error, {:unauthorized, ^op}} = Manager.authorize(identity, op)
      end
    end
  end

  # ===========================================================================
  # AUDIT LOGGING
  # ===========================================================================

  describe "audit_log/2 and get_audit_log/0" do
    test "stores a manual audit entry" do
      Manager.audit_log(:test_event, %{key: "value"})
      # audit_log is a cast, so give the GenServer a moment to process.
      Process.sleep(50)

      log = Manager.get_audit_log()
      test_events = Enum.filter(log, fn entry -> entry.event == :test_event end)

      assert length(test_events) >= 1
      latest = List.last(test_events)
      assert latest.details == %{key: "value"}
      assert %DateTime{} = latest.timestamp
    end

    test "stores multiple entries in order" do
      Manager.audit_log(:event_a, %{order: 1})
      Manager.audit_log(:event_b, %{order: 2})
      Manager.audit_log(:event_c, %{order: 3})
      Process.sleep(50)

      log = Manager.get_audit_log()

      # Filter to only our test events (using unique atoms to avoid
      # cross-test contamination from the shared ETS table).
      our_events =
        Enum.filter(log, fn entry ->
          entry.event in [:event_a, :event_b, :event_c]
        end)

      assert length(our_events) == 3

      # Verify ordering (oldest first).
      events = Enum.map(our_events, & &1.event)
      assert events == [:event_a, :event_b, :event_c]
    end

    test "defaults details to empty map when omitted" do
      Manager.audit_log(:bare_event)
      Process.sleep(50)

      log = Manager.get_audit_log()
      bare_events = Enum.filter(log, fn entry -> entry.event == :bare_event end)

      assert length(bare_events) >= 1
      assert List.last(bare_events).details == %{}
    end

    test "each entry has :timestamp, :event, and :details fields" do
      Manager.audit_log(:structure_test, %{foo: "bar"})
      Process.sleep(50)

      log = Manager.get_audit_log()

      struct_events = Enum.filter(log, fn e -> e.event == :structure_test end)
      entry = List.last(struct_events)

      assert Map.has_key?(entry, :timestamp)
      assert Map.has_key?(entry, :event)
      assert Map.has_key?(entry, :details)

      assert is_atom(entry.event)
      assert is_map(entry.details)
      assert %DateTime{} = entry.timestamp
    end

    test "timestamps are monotonically non-decreasing" do
      for i <- 1..5 do
        Manager.audit_log(:mono_test, %{index: i})
      end

      Process.sleep(50)

      log = Manager.get_audit_log()

      mono_events =
        Enum.filter(log, fn entry -> entry.event == :mono_test end)

      timestamps = Enum.map(mono_events, & &1.timestamp)

      # Verify monotonic non-decreasing order.
      pairs = Enum.zip(timestamps, tl(timestamps))

      for {earlier, later} <- pairs do
        assert DateTime.compare(earlier, later) in [:lt, :eq]
      end
    end
  end

  # ===========================================================================
  # AUDIT LOGGING — Automatic entries from auth/authz
  # ===========================================================================

  describe "automatic audit entries from auth/authz flow" do
    test "authenticate success creates an audit entry" do
      cert = valid_cert(%{subject: "CN=auto-audit-auth"})
      {:ok, _identity} = Manager.authenticate(cert)

      log = Manager.get_audit_log()

      auth_entries = Enum.filter(log, fn e ->
        e.event == :auth_success and e.details.device_id == "CN=auto-audit-auth"
      end)

      assert length(auth_entries) >= 1
    end

    test "authorize success creates an audit entry" do
      identity = %{device_id: "CN=auto-audit-authz", tier: :development}
      :ok = Manager.authorize(identity, :service_start)

      log = Manager.get_audit_log()

      authz_entries = Enum.filter(log, fn e ->
        e.event == :authz_success and e.details.device_id == "CN=auto-audit-authz"
      end)

      assert length(authz_entries) >= 1

      entry = List.last(authz_entries)
      assert entry.details.operation == :service_start
    end

    test "full auth+authz flow generates correct audit trail" do
      cert = valid_cert(%{subject: "CN=full-flow-device"})
      {:ok, identity} = Manager.authenticate(cert)
      :ok = Manager.authorize(identity, :package_install)

      log = Manager.get_audit_log()

      # Find our specific entries by device_id.
      flow_entries = Enum.filter(log, fn e ->
        Map.get(e.details, :device_id) == "CN=full-flow-device"
      end)

      assert length(flow_entries) >= 2

      events = Enum.map(flow_entries, & &1.event)
      assert :auth_success in events
      assert :authz_success in events

      # Verify ordering: auth before authz.
      auth_idx = Enum.find_index(flow_entries, fn e -> e.event == :auth_success end)
      authz_idx = Enum.find_index(flow_entries, fn e -> e.event == :authz_success end)
      assert auth_idx < authz_idx
    end

    test "failed auth in restricted tier creates auth_failure audit entry" do
      restart_with_tier(:iot)

      cert = expired_cert(%{subject: "CN=fail-audit-device"})
      {:error, :cert_expired} = Manager.authenticate(cert)

      log = Manager.get_audit_log()
      failure_entries = Enum.filter(log, fn e ->
        e.event == :auth_failure and e.details.device_id == "CN=fail-audit-device"
      end)

      assert length(failure_entries) >= 1

      entry = List.last(failure_entries)
      assert entry.details.reason == :cert_expired

      restart_with_tier(:development)
    end

    test "failed authz in restricted tier creates authz_denied audit entry" do
      restart_with_tier(:critical)

      identity = %{device_id: "CN=denied-audit-device", tier: :critical}
      {:error, {:unauthorized, :command_run}} = Manager.authorize(identity, :command_run)

      log = Manager.get_audit_log()
      denied_entries = Enum.filter(log, fn e ->
        e.event == :authz_denied and e.details.device_id == "CN=denied-audit-device"
      end)

      assert length(denied_entries) >= 1

      entry = List.last(denied_entries)
      assert entry.details.operation == :command_run
      assert entry.details.reason == :operation_not_allowed

      restart_with_tier(:development)
    end
  end

  # ===========================================================================
  # EDGE CASES AND ROBUSTNESS
  # ===========================================================================

  describe "edge cases" do
    test "authenticate/1 rejects non-map argument" do
      assert_raise FunctionClauseError, fn ->
        Manager.authenticate("not-a-map")
      end
    end

    test "authenticate/1 rejects nil" do
      assert_raise FunctionClauseError, fn ->
        Manager.authenticate(nil)
      end
    end

    test "authorize/2 with identity lacking device_id defaults to unknown" do
      identity = %{tier: :development}
      assert :ok = Manager.authorize(identity, :service_start)

      log = Manager.get_audit_log()

      authz_entries = Enum.filter(log, fn e ->
        e.event == :authz_success and e.details.device_id == "unknown"
      end)

      assert length(authz_entries) >= 1
    end

    test "audit_log/2 rejects non-atom event type" do
      assert_raise FunctionClauseError, fn ->
        Manager.audit_log("string_event", %{})
      end
    end

    test "audit_log/2 rejects non-map details" do
      assert_raise FunctionClauseError, fn ->
        Manager.audit_log(:valid_event, "not-a-map")
      end
    end

    test "extract_operation_type handles unexpected input as :unknown" do
      identity = %{device_id: "CN=edge-unknown-op", tier: :development}
      assert :ok = Manager.authorize(identity, 42)

      log = Manager.get_audit_log()

      authz_entries = Enum.filter(log, fn e ->
        e.event == :authz_success and e.details.device_id == "CN=edge-unknown-op"
      end)

      latest = List.last(authz_entries)
      assert latest.details.operation == :unknown
    end

    test "authorize with integer operation in restricted tier denies :unknown" do
      restart_with_tier(:critical)

      identity = %{device_id: "CN=edge-int-op", tier: :critical}
      assert {:error, {:unauthorized, :unknown}} = Manager.authorize(identity, 42)

      restart_with_tier(:development)
    end
  end

  # ===========================================================================
  # TIER TRANSITION — Verifying tier changes take effect
  # ===========================================================================

  describe "tier transitions" do
    test "switching from development to critical restricts operations" do
      identity = %{device_id: "CN=tier-switch", tier: :development}
      assert :ok = Manager.authorize(identity, :command_run)

      restart_with_tier(:critical)

      identity_critical = %{device_id: "CN=tier-switch", tier: :critical}
      assert {:error, {:unauthorized, :command_run}} =
               Manager.authorize(identity_critical, :command_run)

      restart_with_tier(:development)
    end

    test "switching from critical to development opens all operations" do
      restart_with_tier(:critical)

      identity = %{device_id: "CN=tier-open", tier: :critical}
      assert {:error, {:unauthorized, :file_write}} =
               Manager.authorize(identity, :file_write)

      restart_with_tier(:development)

      identity_dev = %{device_id: "CN=tier-open", tier: :development}
      assert :ok = Manager.authorize(identity_dev, :file_write)
    end

    test "switching between IoT and industrial changes allowed operations" do
      restart_with_tier(:iot)

      identity = %{device_id: "CN=tier-compare", tier: :iot}
      assert :ok = Manager.authorize(identity, :command_run)

      restart_with_tier(:industrial)

      identity_industrial = %{device_id: "CN=tier-compare", tier: :industrial}
      assert {:error, {:unauthorized, :command_run}} =
               Manager.authorize(identity_industrial, :command_run)

      restart_with_tier(:development)
    end
  end

  # ===========================================================================
  # GenServer LIFECYCLE
  # ===========================================================================

  describe "GenServer lifecycle" do
    test "start_link/1 starts the process" do
      assert GenServer.whereis(Manager) != nil
    end

    test "process is registered under HAR.Security.Manager name" do
      pid = GenServer.whereis(Manager)
      assert is_pid(pid)
      assert Process.alive?(pid)
    end

    test "survives multiple authenticate/authorize calls without crashing" do
      pid_before = GenServer.whereis(Manager)

      for _ <- 1..20 do
        cert = valid_cert()
        {:ok, identity} = Manager.authenticate(cert)
        Manager.authorize(identity, :service_start)
      end

      pid_after = GenServer.whereis(Manager)
      assert pid_before == pid_after
    end
  end
end

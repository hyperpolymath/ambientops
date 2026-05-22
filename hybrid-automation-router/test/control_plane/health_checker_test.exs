# SPDX-License-Identifier: MPL-2.0
defmodule HAR.ControlPlane.HealthCheckerTest do
  @moduledoc """
  Tests for the HAR.ControlPlane.HealthChecker GenServer.
  Uses the instance started by the application supervisor.
  """

  use ExUnit.Case, async: false

  alias HAR.ControlPlane.HealthChecker

  describe "register_backend/1" do
    test "registers a new backend with unknown health status" do
      backend = %{name: "test-reg-#{System.unique_integer([:positive])}", type: :test}
      assert :ok = HealthChecker.register_backend(backend)
      Process.sleep(10)

      status = HealthChecker.get_health(backend)
      assert status == :unknown
    end

    test "does not overwrite existing backend on duplicate register" do
      backend = %{name: "test-dup-#{System.unique_integer([:positive])}", type: :test}
      HealthChecker.register_backend(backend)
      Process.sleep(10)

      HealthChecker.set_health(backend, :healthy)
      Process.sleep(10)

      HealthChecker.register_backend(backend)
      Process.sleep(10)

      status = HealthChecker.get_health(backend)
      assert status == :healthy
    end
  end

  describe "set_health/2" do
    test "manually sets backend health to healthy" do
      backend = %{name: "test-h-#{System.unique_integer([:positive])}", type: :test}
      HealthChecker.register_backend(backend)
      Process.sleep(10)

      HealthChecker.set_health(backend, :healthy)
      Process.sleep(10)

      assert HealthChecker.get_health(backend) == :healthy
    end

    test "manually sets backend health to unhealthy" do
      backend = %{name: "test-uh-#{System.unique_integer([:positive])}", type: :test}
      HealthChecker.register_backend(backend)
      Process.sleep(10)

      HealthChecker.set_health(backend, :unhealthy)
      Process.sleep(10)

      assert HealthChecker.get_health(backend) == :unhealthy
    end

    test "manually sets backend health to degraded" do
      backend = %{name: "test-dg-#{System.unique_integer([:positive])}", type: :test}
      HealthChecker.register_backend(backend)
      Process.sleep(10)

      HealthChecker.set_health(backend, :degraded)
      Process.sleep(10)

      assert HealthChecker.get_health(backend) == :degraded
    end
  end

  describe "get_health/1" do
    test "returns :unknown for unregistered backend" do
      backend = %{name: "nonexistent-#{System.unique_integer([:positive])}", type: :none}
      assert HealthChecker.get_health(backend) == :unknown
    end
  end

  describe "filter_healthy/1" do
    test "returns only healthy backends" do
      healthy = %{name: "good-#{System.unique_integer([:positive])}", type: :ansible}
      unhealthy = %{name: "bad-#{System.unique_integer([:positive])}", type: :salt}

      HealthChecker.register_backend(healthy)
      HealthChecker.register_backend(unhealthy)
      Process.sleep(10)

      HealthChecker.set_health(healthy, :healthy)
      HealthChecker.set_health(unhealthy, :unhealthy)
      Process.sleep(10)

      result = HealthChecker.filter_healthy([healthy, unhealthy])
      assert length(result) == 1
      assert hd(result).name == healthy.name
    end

    test "includes degraded backends as healthy" do
      degraded = %{name: "deg-#{System.unique_integer([:positive])}", type: :test}
      HealthChecker.register_backend(degraded)
      Process.sleep(10)

      HealthChecker.set_health(degraded, :degraded)
      Process.sleep(10)

      result = HealthChecker.filter_healthy([degraded])
      assert length(result) == 1
    end

    test "returns empty list when all backends are unhealthy" do
      backend = %{name: "down-#{System.unique_integer([:positive])}", type: :test}
      HealthChecker.register_backend(backend)
      Process.sleep(10)

      HealthChecker.set_health(backend, :unhealthy)
      Process.sleep(10)

      result = HealthChecker.filter_healthy([backend])
      assert result == []
    end
  end

  describe "all_health/0" do
    test "returns a map of backend health statuses" do
      health = HealthChecker.all_health()
      assert is_map(health)
    end
  end
end

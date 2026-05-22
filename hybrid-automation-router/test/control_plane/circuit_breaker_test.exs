# SPDX-License-Identifier: MPL-2.0
defmodule HAR.ControlPlane.CircuitBreakerTest do
  @moduledoc """
  Tests for the HAR.ControlPlane.CircuitBreaker GenServer.

  Exercises the three-state FSM (closed -> open -> half_open -> closed),
  ETS-backed O(1) reads via allow?/1, async casts (record_success/1,
  record_failure/1), synchronous registration and reset, per-backend
  isolation, and the half-open timer recovery path.

  Uses the CircuitBreaker instance started by the application supervision
  tree (HAR.ControlPlane.Supervisor). Each test registers a uniquely-named
  backend so tests do not interfere with one another and cleans up via
  reset/1 in the on_exit callback.
  """

  use ExUnit.Case, async: false

  alias HAR.ControlPlane.CircuitBreaker

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  # Generate a unique backend name per test invocation to prevent cross-test
  # contamination in the shared ETS table.
  defp unique_backend(prefix \\ "cb-test") do
    "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
  end

  # Convenience: register a backend with a low failure threshold and a short
  # half-open timer so the FSM transitions are fast enough for tests.
  defp register_test_backend(name, opts \\ []) do
    config = %{
      failure_threshold: Keyword.get(opts, :failure_threshold, 3),
      half_open_after_ms: Keyword.get(opts, :half_open_after_ms, 100)
    }

    :ok = CircuitBreaker.register(name, config)
    name
  end

  # Trip a backend's circuit open by recording exactly `threshold` failures.
  # Waits for the GenServer to process all casts before returning.
  defp trip_circuit(name, threshold \\ 3) do
    for _ <- 1..threshold do
      CircuitBreaker.record_failure(name)
    end

    Process.sleep(50)
  end

  # Read the raw ETS tuple for a backend. Useful for asserting internal state
  # that is not exposed through the public API.
  defp ets_state(name) do
    case :ets.lookup(:har_circuit_breaker, name) do
      [{^name, state, failure_count, opened_at}] ->
        %{state: state, failure_count: failure_count, opened_at: opened_at}

      [] ->
        nil
    end
  end

  # ---------------------------------------------------------------------------
  # Setup
  # ---------------------------------------------------------------------------

  setup do
    # Each test registers its own backend(s). The on_exit callback resets them
    # so stale entries do not leak between tests.
    backends = []

    on_exit(fn ->
      # Best-effort cleanup — reset is synchronous so this is safe.
      Enum.each(backends, &CircuitBreaker.reset/1)
    end)

    {:ok, backends: backends}
  end

  # ---------------------------------------------------------------------------
  # Registration
  # ---------------------------------------------------------------------------

  describe "register/2" do
    test "registers a new backend in the closed state with zero failures" do
      name = unique_backend("reg")
      assert :ok = CircuitBreaker.register(name, %{failure_threshold: 5, half_open_after_ms: 200})

      state = ets_state(name)
      assert state != nil
      assert state.state == :closed
      assert state.failure_count == 0
      assert state.opened_at == nil

      CircuitBreaker.reset(name)
    end

    test "registers with default config when health contract is empty" do
      name = unique_backend("reg-default")
      assert :ok = CircuitBreaker.register(name, %{})

      state = ets_state(name)
      assert state.state == :closed
      assert state.failure_count == 0

      CircuitBreaker.reset(name)
    end

    test "registers with custom failure threshold and half-open timer" do
      name = unique_backend("reg-custom")
      config = %{failure_threshold: 10, half_open_after_ms: 5_000}
      assert :ok = CircuitBreaker.register(name, config)

      # Verify the config is retrievable via states/0.
      states = CircuitBreaker.states()
      assert Map.has_key?(states, name)
      assert states[name].config.failure_threshold == 10
      assert states[name].config.half_open_after_ms == 5_000

      CircuitBreaker.reset(name)
    end
  end

  # ---------------------------------------------------------------------------
  # allow?/1 — O(1) ETS reads for each FSM state
  # ---------------------------------------------------------------------------

  describe "allow?/1" do
    test "returns :ok for a backend in the closed state" do
      name = register_test_backend(unique_backend("allow-closed"))
      assert :ok = CircuitBreaker.allow?(name)
      CircuitBreaker.reset(name)
    end

    test "returns {:circuit_open, name} for a backend in the open state" do
      name = register_test_backend(unique_backend("allow-open"), half_open_after_ms: 5_000)
      trip_circuit(name, 3)

      assert {:circuit_open, ^name} = CircuitBreaker.allow?(name)

      CircuitBreaker.reset(name)
    end

    test "returns :ok for a backend in the half_open state" do
      name = register_test_backend(unique_backend("allow-half"), half_open_after_ms: 80)
      trip_circuit(name, 3)

      # Wait for the half-open timer to fire.
      Process.sleep(150)

      assert ets_state(name).state == :half_open
      assert :ok = CircuitBreaker.allow?(name)

      CircuitBreaker.reset(name)
    end

    test "returns :ok for an unregistered backend (opt-in model)" do
      assert :ok = CircuitBreaker.allow?("never-registered-#{System.unique_integer([:positive])}")
    end
  end

  # ---------------------------------------------------------------------------
  # Failure threshold — tripping the circuit
  # ---------------------------------------------------------------------------

  describe "record_failure/1 (failure threshold)" do
    test "increments failure count without tripping when below threshold" do
      name = register_test_backend(unique_backend("fail-below"), failure_threshold: 5)

      CircuitBreaker.record_failure(name)
      CircuitBreaker.record_failure(name)
      Process.sleep(50)

      state = ets_state(name)
      assert state.state == :closed
      assert state.failure_count == 2

      CircuitBreaker.reset(name)
    end

    test "trips the circuit open when failures reach the threshold" do
      name = register_test_backend(unique_backend("fail-trip"), failure_threshold: 3, half_open_after_ms: 5_000)
      trip_circuit(name, 3)

      state = ets_state(name)
      assert state.state == :open
      assert state.failure_count >= 3
      assert state.opened_at != nil

      CircuitBreaker.reset(name)
    end

    test "additional failures while open are ignored (no-op)" do
      name = register_test_backend(unique_backend("fail-open"), failure_threshold: 3, half_open_after_ms: 5_000)
      trip_circuit(name, 3)

      # Record more failures while open — should be ignored.
      CircuitBreaker.record_failure(name)
      CircuitBreaker.record_failure(name)
      Process.sleep(50)

      state = ets_state(name)
      assert state.state == :open
      # Failure count should not increase beyond the threshold set at trip time.
      assert state.failure_count == 3

      CircuitBreaker.reset(name)
    end

    test "no-op for unregistered backend" do
      # Should not crash or create an ETS entry.
      name = "unregistered-#{System.unique_integer([:positive])}"
      CircuitBreaker.record_failure(name)
      Process.sleep(50)

      assert ets_state(name) == nil
    end
  end

  # ---------------------------------------------------------------------------
  # record_success/1 — reset behaviour
  # ---------------------------------------------------------------------------

  describe "record_success/1" do
    test "resets failure count to zero while closed" do
      name = register_test_backend(unique_backend("succ-reset"), failure_threshold: 5)

      # Accumulate some failures (below threshold).
      CircuitBreaker.record_failure(name)
      CircuitBreaker.record_failure(name)
      Process.sleep(50)
      assert ets_state(name).failure_count == 2

      # Record a success — failure count should reset to zero.
      CircuitBreaker.record_success(name)
      Process.sleep(50)

      state = ets_state(name)
      assert state.state == :closed
      assert state.failure_count == 0

      CircuitBreaker.reset(name)
    end

    test "no-op for unregistered backend" do
      name = "unregistered-succ-#{System.unique_integer([:positive])}"
      CircuitBreaker.record_success(name)
      Process.sleep(50)

      assert ets_state(name) == nil
    end

    test "no state change for an open backend (success ignored while open)" do
      name = register_test_backend(unique_backend("succ-open"), failure_threshold: 3, half_open_after_ms: 5_000)
      trip_circuit(name, 3)

      assert ets_state(name).state == :open

      # Success while open should be ignored — no transition.
      CircuitBreaker.record_success(name)
      Process.sleep(50)

      assert ets_state(name).state == :open

      CircuitBreaker.reset(name)
    end
  end

  # ---------------------------------------------------------------------------
  # Half-open recovery — successful probe closes the circuit
  # ---------------------------------------------------------------------------

  describe "half-open recovery" do
    test "circuit transitions to half_open after the timer fires" do
      name = register_test_backend(unique_backend("ho-timer"), half_open_after_ms: 80)
      trip_circuit(name, 3)

      assert ets_state(name).state == :open

      # Wait for the half-open timer.
      Process.sleep(150)

      assert ets_state(name).state == :half_open

      CircuitBreaker.reset(name)
    end

    test "success during half_open closes the circuit" do
      name = register_test_backend(unique_backend("ho-success"), half_open_after_ms: 80)
      trip_circuit(name, 3)

      # Wait for half-open.
      Process.sleep(150)
      assert ets_state(name).state == :half_open

      # Probe success.
      CircuitBreaker.record_success(name)
      Process.sleep(50)

      state = ets_state(name)
      assert state.state == :closed
      assert state.failure_count == 0
      assert state.opened_at == nil

      CircuitBreaker.reset(name)
    end

    test "failure during half_open re-opens the circuit" do
      name = register_test_backend(unique_backend("ho-fail"), half_open_after_ms: 80)
      trip_circuit(name, 3)

      # Wait for half-open.
      Process.sleep(150)
      assert ets_state(name).state == :half_open

      # Probe failure — circuit should re-open.
      CircuitBreaker.record_failure(name)
      Process.sleep(50)

      state = ets_state(name)
      assert state.state == :open
      assert state.opened_at != nil

      CircuitBreaker.reset(name)
    end

    test "re-tripped circuit eventually transitions to half_open again" do
      name = register_test_backend(unique_backend("ho-re-trip"), half_open_after_ms: 80)
      trip_circuit(name, 3)

      # First half-open.
      Process.sleep(150)
      assert ets_state(name).state == :half_open

      # Probe failure — re-opens.
      CircuitBreaker.record_failure(name)
      Process.sleep(50)
      assert ets_state(name).state == :open

      # Second half-open after the timer fires again.
      Process.sleep(150)
      assert ets_state(name).state == :half_open

      CircuitBreaker.reset(name)
    end
  end

  # ---------------------------------------------------------------------------
  # Manual reset
  # ---------------------------------------------------------------------------

  describe "reset/1" do
    test "resets an open circuit back to closed" do
      name = register_test_backend(unique_backend("reset-open"), half_open_after_ms: 5_000)
      trip_circuit(name, 3)

      assert ets_state(name).state == :open

      assert :ok = CircuitBreaker.reset(name)

      state = ets_state(name)
      assert state.state == :closed
      assert state.failure_count == 0
      assert state.opened_at == nil
    end

    test "resets a half_open circuit back to closed" do
      name = register_test_backend(unique_backend("reset-ho"), half_open_after_ms: 80)
      trip_circuit(name, 3)

      Process.sleep(150)
      assert ets_state(name).state == :half_open

      assert :ok = CircuitBreaker.reset(name)

      state = ets_state(name)
      assert state.state == :closed
      assert state.failure_count == 0
    end

    test "reset on a closed circuit is a no-op (still closed)" do
      name = register_test_backend(unique_backend("reset-closed"))
      assert :ok = CircuitBreaker.reset(name)

      state = ets_state(name)
      assert state.state == :closed
      assert state.failure_count == 0
    end

    test "allow? returns :ok immediately after reset" do
      name = register_test_backend(unique_backend("reset-allow"), half_open_after_ms: 5_000)
      trip_circuit(name, 3)

      assert {:circuit_open, ^name} = CircuitBreaker.allow?(name)

      CircuitBreaker.reset(name)

      assert :ok = CircuitBreaker.allow?(name)
    end
  end

  # ---------------------------------------------------------------------------
  # states/0 — snapshot of all registered backends
  # ---------------------------------------------------------------------------

  describe "states/0" do
    test "returns a map containing all registered backends" do
      name_a = register_test_backend(unique_backend("states-a"))
      name_b = register_test_backend(unique_backend("states-b"))

      states = CircuitBreaker.states()
      assert is_map(states)
      assert Map.has_key?(states, name_a)
      assert Map.has_key?(states, name_b)

      CircuitBreaker.reset(name_a)
      CircuitBreaker.reset(name_b)
    end

    test "each entry contains state, failure_count, opened_at, and config" do
      name = register_test_backend(unique_backend("states-fields"))
      states = CircuitBreaker.states()
      entry = states[name]

      assert Map.has_key?(entry, :state)
      assert Map.has_key?(entry, :failure_count)
      assert Map.has_key?(entry, :opened_at)
      assert Map.has_key?(entry, :config)
      assert Map.has_key?(entry.config, :failure_threshold)
      assert Map.has_key?(entry.config, :half_open_after_ms)

      CircuitBreaker.reset(name)
    end

    test "reflects current FSM state for open backends" do
      name = register_test_backend(unique_backend("states-open"), half_open_after_ms: 5_000)
      trip_circuit(name, 3)

      states = CircuitBreaker.states()
      assert states[name].state == :open
      assert states[name].failure_count >= 3

      CircuitBreaker.reset(name)
    end
  end

  # ---------------------------------------------------------------------------
  # Per-backend isolation
  # ---------------------------------------------------------------------------

  describe "per-backend isolation" do
    test "failures on one backend do not affect another" do
      name_a = register_test_backend(unique_backend("iso-a"), failure_threshold: 3, half_open_after_ms: 5_000)
      name_b = register_test_backend(unique_backend("iso-b"), failure_threshold: 3, half_open_after_ms: 5_000)

      # Trip backend A.
      trip_circuit(name_a, 3)

      assert ets_state(name_a).state == :open
      assert ets_state(name_b).state == :closed
      assert ets_state(name_b).failure_count == 0

      assert {:circuit_open, ^name_a} = CircuitBreaker.allow?(name_a)
      assert :ok = CircuitBreaker.allow?(name_b)

      CircuitBreaker.reset(name_a)
      CircuitBreaker.reset(name_b)
    end

    test "resetting one backend does not affect another" do
      name_a = register_test_backend(unique_backend("iso-reset-a"), failure_threshold: 3, half_open_after_ms: 5_000)
      name_b = register_test_backend(unique_backend("iso-reset-b"), failure_threshold: 3, half_open_after_ms: 5_000)

      # Trip both.
      trip_circuit(name_a, 3)
      trip_circuit(name_b, 3)

      assert ets_state(name_a).state == :open
      assert ets_state(name_b).state == :open

      # Reset only A.
      CircuitBreaker.reset(name_a)

      assert ets_state(name_a).state == :closed
      assert ets_state(name_b).state == :open

      CircuitBreaker.reset(name_b)
    end
  end

  # ---------------------------------------------------------------------------
  # Config preservation on re-register
  # ---------------------------------------------------------------------------

  describe "re-registration" do
    test "preserves existing FSM state when re-registering a backend" do
      name = register_test_backend(unique_backend("re-reg"), half_open_after_ms: 5_000)
      trip_circuit(name, 3)

      assert ets_state(name).state == :open

      # Re-register with different config — state should NOT reset.
      CircuitBreaker.register(name, %{failure_threshold: 10, half_open_after_ms: 5_000})

      state = ets_state(name)
      assert state.state == :open
      assert state.failure_count >= 3

      # But config should be updated.
      states = CircuitBreaker.states()
      assert states[name].config.failure_threshold == 10
      assert states[name].config.half_open_after_ms == 5_000

      CircuitBreaker.reset(name)
    end

    test "preserves failure count on re-register while closed" do
      name = register_test_backend(unique_backend("re-reg-fc"), failure_threshold: 5)

      CircuitBreaker.record_failure(name)
      CircuitBreaker.record_failure(name)
      Process.sleep(50)

      assert ets_state(name).failure_count == 2

      # Re-register — failure count should be preserved.
      CircuitBreaker.register(name, %{failure_threshold: 10})

      assert ets_state(name).failure_count == 2
      assert ets_state(name).state == :closed

      CircuitBreaker.reset(name)
    end
  end
end

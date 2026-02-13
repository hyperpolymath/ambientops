# SPDX-License-Identifier: AGPL-3.0-or-later
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <jonathan@hyperpolymath.io>

defmodule TotalUpdate.Scheduler do
  @moduledoc """
  Cron-like scheduler for periodic update checks.

  Schedules:
  - Periodic update checks (default: every 4 hours)
  - Daily summary reports
  - Weekly cleanup tasks

  Uses Quantum for cron-like scheduling when available,
  falls back to simple Process.send_after otherwise.
  """

  use GenServer
  require Logger

  @default_check_interval :timer.hours(4)
  @default_cleanup_interval :timer.hours(24)

  # ═══════════════════════════════════════════════════════════════════════════
  # Client API
  # ═══════════════════════════════════════════════════════════════════════════

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Trigger an immediate update check"
  def check_now do
    GenServer.cast(__MODULE__, :check_now)
  end

  @doc "Get next scheduled check time"
  def next_check do
    GenServer.call(__MODULE__, :next_check)
  end

  @doc "Pause scheduled checks"
  def pause do
    GenServer.call(__MODULE__, :pause)
  end

  @doc "Resume scheduled checks"
  def resume do
    GenServer.call(__MODULE__, :resume)
  end

  @doc "Get scheduler status"
  def status do
    GenServer.call(__MODULE__, :status)
  end

  @doc "Update check interval"
  def set_interval(interval_ms) when is_integer(interval_ms) and interval_ms > 0 do
    GenServer.call(__MODULE__, {:set_interval, interval_ms})
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Server Callbacks
  # ═══════════════════════════════════════════════════════════════════════════

  @impl true
  def init(opts) do
    check_interval = Keyword.get(opts, :check_interval, @default_check_interval)
    cleanup_interval = Keyword.get(opts, :cleanup_interval, @default_cleanup_interval)

    state = %{
      check_interval: check_interval,
      cleanup_interval: cleanup_interval,
      paused: false,
      last_check: nil,
      next_check_ref: nil,
      next_cleanup_ref: nil
    }

    # Schedule first check after a short delay (let system settle)
    state = schedule_check(state, :timer.seconds(30))
    state = schedule_cleanup(state)

    Logger.info("Scheduler started (check interval: #{div(check_interval, 60_000)} min)")
    {:ok, state}
  end

  @impl true
  def handle_call(:next_check, _from, state) do
    next_time =
      if state.last_check do
        DateTime.add(state.last_check, div(state.check_interval, 1000), :second)
      else
        DateTime.utc_now()
      end

    {:reply, {:ok, next_time}, state}
  end

  @impl true
  def handle_call(:pause, _from, state) do
    state = cancel_timers(state)
    Logger.info("Scheduler paused")
    {:reply, :ok, %{state | paused: true}}
  end

  @impl true
  def handle_call(:resume, _from, state) do
    if state.paused do
      state = schedule_check(%{state | paused: false})
      Logger.info("Scheduler resumed")
      {:reply, :ok, state}
    else
      {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call(:status, _from, state) do
    status = %{
      paused: state.paused,
      check_interval: state.check_interval,
      last_check: state.last_check,
      next_check_in:
        if state.next_check_ref do
          Process.read_timer(state.next_check_ref)
        else
          nil
        end
    }

    {:reply, {:ok, status}, state}
  end

  @impl true
  def handle_call({:set_interval, interval}, _from, state) do
    state = cancel_timers(state)
    state = schedule_check(%{state | check_interval: interval})
    Logger.info("Check interval updated to #{div(interval, 60_000)} min")
    {:reply, :ok, state}
  end

  @impl true
  def handle_cast(:check_now, state) do
    do_check()
    {:noreply, %{state | last_check: DateTime.utc_now()}}
  end

  @impl true
  def handle_info(:scheduled_check, state) do
    unless state.paused do
      do_check()
      state = %{state | last_check: DateTime.utc_now()}
      state = schedule_check(state)
      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(:scheduled_cleanup, state) do
    do_cleanup()
    state = schedule_cleanup(state)
    {:noreply, state}
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Private Functions
  # ═══════════════════════════════════════════════════════════════════════════

  defp schedule_check(state, delay \\ nil) do
    delay = delay || state.check_interval
    ref = Process.send_after(self(), :scheduled_check, delay)
    %{state | next_check_ref: ref}
  end

  defp schedule_cleanup(state) do
    ref = Process.send_after(self(), :scheduled_cleanup, state.cleanup_interval)
    %{state | next_cleanup_ref: ref}
  end

  defp cancel_timers(state) do
    if state.next_check_ref, do: Process.cancel_timer(state.next_check_ref)
    if state.next_cleanup_ref, do: Process.cancel_timer(state.next_cleanup_ref)
    %{state | next_check_ref: nil, next_cleanup_ref: nil}
  end

  defp do_check do
    Logger.debug("Running scheduled update check")
    TotalUpdate.Daemon.check_now()
  end

  defp do_cleanup do
    Logger.debug("Running scheduled cleanup")
    # Cleanup old logs, cache, etc.
    DNFinition.SnapshotManager.cleanup()
  end
end

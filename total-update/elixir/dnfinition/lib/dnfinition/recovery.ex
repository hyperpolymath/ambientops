# SPDX-License-Identifier: AGPL-3.0-or-later
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <jonathan@hyperpolymath.io>

defmodule DNFinition.Recovery do
  @moduledoc """
  Anti-fail recovery system.

  Handles:
  - Detection of incomplete transactions
  - Automatic rollback on crash
  - Boot-time recovery checks
  - Manual intervention guidance
  """

  use GenServer
  require Logger

  # ═══════════════════════════════════════════════════════════════════════════
  # Client API
  # ═══════════════════════════════════════════════════════════════════════════

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Check if system needs recovery.
  """
  def needs_recovery? do
    GenServer.call(__MODULE__, :needs_recovery)
  end

  @doc """
  Perform automatic recovery if possible.
  """
  def auto_recover do
    GenServer.call(__MODULE__, :auto_recover, :infinity)
  end

  @doc """
  Get recovery status and recommendations.
  """
  def status do
    GenServer.call(__MODULE__, :status)
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Server Callbacks
  # ═══════════════════════════════════════════════════════════════════════════

  @impl true
  def init(_opts) do
    # Check for incomplete transactions on startup
    Process.send_after(self(), :check_recovery, 1000)

    state = %{
      recovery_needed: false,
      incomplete_transaction: nil,
      recovery_attempted: false,
      last_check: nil
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:needs_recovery, _from, state) do
    {:reply, state.recovery_needed, state}
  end

  @impl true
  def handle_call(:auto_recover, _from, state) do
    if state.recovery_needed and state.incomplete_transaction do
      Logger.info("Attempting automatic recovery...")

      case perform_recovery(state.incomplete_transaction) do
        :ok ->
          Logger.info("Recovery successful")
          {:reply, :ok, %{state | recovery_needed: false, recovery_attempted: true}}

        {:error, reason} ->
          Logger.error("Recovery failed: #{inspect(reason)}")
          {:reply, {:error, reason}, %{state | recovery_attempted: true}}
      end
    else
      {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call(:status, _from, state) do
    status = %{
      needs_recovery: state.recovery_needed,
      incomplete_transaction: state.incomplete_transaction,
      recovery_attempted: state.recovery_attempted,
      last_check: state.last_check,
      recommendations: get_recommendations(state)
    }

    {:reply, {:ok, status}, state}
  end

  @impl true
  def handle_info(:check_recovery, state) do
    Logger.debug("Checking for incomplete transactions...")

    case DNFinition.TransactionLog.last_incomplete() do
      {:ok, nil} ->
        {:noreply, %{state | recovery_needed: false, last_check: DateTime.utc_now()}}

      {:ok, incomplete} ->
        Logger.warning("Found incomplete transaction: #{incomplete.snapshot_id}")
        notify_recovery_needed(incomplete)

        {:noreply, %{state |
          recovery_needed: true,
          incomplete_transaction: incomplete,
          last_check: DateTime.utc_now()
        }}
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Private Functions
  # ═══════════════════════════════════════════════════════════════════════════

  defp perform_recovery(transaction) do
    Logger.info("Rolling back to snapshot #{transaction.snapshot_id}")

    case DNFinition.SnapshotManager.rollback(transaction.snapshot_id) do
      :ok ->
        DNFinition.TransactionLog.mark_rolled_back(transaction.snapshot_id)
        :ok

      {:ok, :requires_reboot} ->
        Logger.info("Recovery staged - reboot required")
        {:ok, :requires_reboot}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp notify_recovery_needed(transaction) do
    # TODO: Send notification via D-Bus or other mechanism
    Logger.warning("""
    ╔═══════════════════════════════════════════════════════════════════════════╗
    ║  DNFinition Recovery Notice                                              ║
    ╠═══════════════════════════════════════════════════════════════════════════╣
    ║  An incomplete transaction was detected from a previous session.         ║
    ║                                                                           ║
    ║  Transaction: #{String.pad_trailing(transaction.operation, 48)}║
    ║  Snapshot ID: #{String.pad_trailing("#{transaction.snapshot_id}", 48)}║
    ║                                                                           ║
    ║  Run 'dnfinition recovery' to resolve this issue.                        ║
    ╚═══════════════════════════════════════════════════════════════════════════╝
    """)
  end

  defp get_recommendations(state) do
    cond do
      not state.recovery_needed ->
        ["System is healthy. No recovery needed."]

      state.recovery_attempted ->
        [
          "Automatic recovery was attempted.",
          "If issues persist, try manual rollback:",
          "  dnfinition rollback #{state.incomplete_transaction.snapshot_id}",
          "Or boot into a previous snapshot from bootloader."
        ]

      true ->
        [
          "An incomplete transaction was detected.",
          "Recommended action: dnfinition recovery",
          "Alternative: dnfinition rollback #{state.incomplete_transaction.snapshot_id}"
        ]
    end
  end
end

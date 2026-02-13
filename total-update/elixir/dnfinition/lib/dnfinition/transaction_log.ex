# SPDX-License-Identifier: AGPL-3.0-or-later
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <jonathan@hyperpolymath.io>

defmodule DNFinition.TransactionLog do
  @moduledoc """
  Transaction logging for audit trail and recovery.

  Logs all package operations with:
  - Pre-operation state
  - Operation details
  - Post-operation state
  - Rollback markers
  """

  use GenServer
  require Logger

  @log_path "/var/lib/dnfinition/transactions.log"

  # ═══════════════════════════════════════════════════════════════════════════
  # Client API
  # ═══════════════════════════════════════════════════════════════════════════

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Begin a new transaction.
  """
  def begin_transaction(snapshot_id, operation, packages) do
    GenServer.call(__MODULE__, {:begin, snapshot_id, operation, packages})
  end

  @doc """
  Complete a transaction.
  """
  def complete_transaction(snapshot_id, success) do
    GenServer.call(__MODULE__, {:complete, snapshot_id, success})
  end

  @doc """
  Mark a transaction as rolled back.
  """
  def mark_rolled_back(snapshot_id) do
    GenServer.call(__MODULE__, {:rollback, snapshot_id})
  end

  @doc """
  Get transaction history.
  """
  def history(limit \\ 50) do
    GenServer.call(__MODULE__, {:history, limit})
  end

  @doc """
  Get the last incomplete transaction (for recovery).
  """
  def last_incomplete do
    GenServer.call(__MODULE__, :last_incomplete)
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Server Callbacks
  # ═══════════════════════════════════════════════════════════════════════════

  @impl true
  def init(_opts) do
    # Ensure log directory exists
    log_dir = Path.dirname(@log_path)
    File.mkdir_p!(log_dir)

    state = %{
      log_path: @log_path,
      transactions: load_transactions()
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:begin, snapshot_id, operation, packages}, _from, state) do
    entry = %{
      snapshot_id: snapshot_id,
      operation: operation,
      packages: packages,
      started_at: DateTime.utc_now(),
      completed: false,
      success: false,
      rolled_back: false
    }

    new_transactions = [entry | state.transactions]
    append_to_log(entry, state.log_path)

    {:reply, :ok, %{state | transactions: new_transactions}}
  end

  @impl true
  def handle_call({:complete, snapshot_id, success}, _from, state) do
    new_transactions =
      Enum.map(state.transactions, fn entry ->
        if entry.snapshot_id == snapshot_id and not entry.completed do
          updated = %{entry | completed: true, success: success}
          update_log_entry(updated, state.log_path)
          updated
        else
          entry
        end
      end)

    {:reply, :ok, %{state | transactions: new_transactions}}
  end

  @impl true
  def handle_call({:rollback, snapshot_id}, _from, state) do
    new_transactions =
      Enum.map(state.transactions, fn entry ->
        if entry.snapshot_id == snapshot_id do
          updated = %{entry | rolled_back: true}
          update_log_entry(updated, state.log_path)
          updated
        else
          entry
        end
      end)

    {:reply, :ok, %{state | transactions: new_transactions}}
  end

  @impl true
  def handle_call({:history, limit}, _from, state) do
    {:reply, {:ok, Enum.take(state.transactions, limit)}, state}
  end

  @impl true
  def handle_call(:last_incomplete, _from, state) do
    incomplete = Enum.find(state.transactions, &(not &1.completed))
    {:reply, {:ok, incomplete}, state}
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Private Functions
  # ═══════════════════════════════════════════════════════════════════════════

  defp load_transactions do
    case File.read(@log_path) do
      {:ok, content} ->
        content
        |> String.split("\n", trim: true)
        |> Enum.map(&parse_log_line/1)
        |> Enum.reject(&is_nil/1)

      {:error, _} ->
        []
    end
  end

  defp parse_log_line(line) do
    # TODO: Implement log parsing
    # For now, return nil
    nil
  end

  defp append_to_log(entry, path) do
    line = format_log_entry(entry)
    File.write!(path, line <> "\n", [:append])
  end

  defp update_log_entry(_entry, _path) do
    # TODO: Implement log updating
    # This is complex because we need to update in-place
    :ok
  end

  defp format_log_entry(entry) do
    # Format: timestamp|snapshot_id|operation|packages|completed|success|rolled_back
    packages_str = Enum.join(entry.packages, ",")

    [
      DateTime.to_iso8601(entry.started_at),
      entry.snapshot_id,
      entry.operation,
      packages_str,
      entry.completed,
      entry.success,
      entry.rolled_back
    ]
    |> Enum.join("|")
  end
end

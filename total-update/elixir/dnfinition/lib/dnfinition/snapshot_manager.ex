# SPDX-License-Identifier: AGPL-3.0-or-later
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <jonathan@hyperpolymath.io>

defmodule DNFinition.SnapshotManager do
  @moduledoc """
  Coordinates snapshot operations between Elixir and Ada.

  This GenServer provides:
  - Snapshot lifecycle management
  - Coordination with Ada snapshot backends
  - Caching of snapshot metadata
  - Cleanup scheduling
  """

  use GenServer
  require Logger

  @default_max_snapshots 10

  # ═══════════════════════════════════════════════════════════════════════════
  # Client API
  # ═══════════════════════════════════════════════════════════════════════════

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Create a new snapshot with the given description.
  Returns {:ok, snapshot_id} or {:error, reason}.
  """
  def create(description, opts \\ []) do
    GenServer.call(__MODULE__, {:create, description, opts})
  end

  @doc """
  Rollback to a specific snapshot.
  """
  def rollback(snapshot_id) do
    GenServer.call(__MODULE__, {:rollback, snapshot_id}, :infinity)
  end

  @doc """
  Rollback to the most recent snapshot.
  """
  def rollback_last do
    GenServer.call(__MODULE__, :rollback_last, :infinity)
  end

  @doc """
  List all available snapshots.
  """
  def list do
    GenServer.call(__MODULE__, :list)
  end

  @doc """
  Get info about a specific snapshot.
  """
  def get_info(snapshot_id) do
    GenServer.call(__MODULE__, {:get_info, snapshot_id})
  end

  @doc """
  Delete a snapshot.
  """
  def delete(snapshot_id) do
    GenServer.call(__MODULE__, {:delete, snapshot_id})
  end

  @doc """
  Clean up old snapshots beyond max_count.
  """
  def cleanup(max_count \\ @default_max_snapshots) do
    GenServer.call(__MODULE__, {:cleanup, max_count})
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Server Callbacks
  # ═══════════════════════════════════════════════════════════════════════════

  @impl true
  def init(_opts) do
    state = %{
      snapshots: [],
      next_id: 1,
      backend: detect_backend(),
      config: load_config()
    }

    # Schedule periodic cleanup
    schedule_cleanup()

    {:ok, state}
  end

  @impl true
  def handle_call({:create, description, opts}, _from, state) do
    kind = Keyword.get(opts, :kind, :pre_transaction)

    snapshot = %{
      id: state.next_id,
      kind: kind,
      description: description,
      created_at: DateTime.utc_now(),
      state: :creating,
      backend: state.backend
    }

    case create_backend_snapshot(snapshot, state.backend) do
      :ok ->
        snapshot = %{snapshot | state: :valid}
        new_state = %{state |
          snapshots: [snapshot | state.snapshots],
          next_id: state.next_id + 1
        }

        Logger.info("Created snapshot #{snapshot.id}: #{description}")
        {:reply, {:ok, snapshot.id}, new_state}

      {:error, reason} ->
        Logger.error("Failed to create snapshot: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:rollback, snapshot_id}, _from, state) do
    case find_snapshot(snapshot_id, state.snapshots) do
      nil ->
        {:reply, {:error, :not_found}, state}

      snapshot ->
        case rollback_backend_snapshot(snapshot, state.backend) do
          :ok ->
            Logger.info("Rolled back to snapshot #{snapshot_id}")

            # Mark transaction as rolled back
            DNFinition.TransactionLog.mark_rolled_back(snapshot_id)

            {:reply, :ok, state}

          {:error, :requires_reboot} ->
            Logger.info("Rollback to #{snapshot_id} requires reboot")
            {:reply, {:ok, :requires_reboot}, state}

          {:error, reason} ->
            Logger.error("Rollback failed: #{inspect(reason)}")
            {:reply, {:error, reason}, state}
        end
    end
  end

  @impl true
  def handle_call(:rollback_last, from, state) do
    case state.snapshots do
      [latest | _] ->
        handle_call({:rollback, latest.id}, from, state)

      [] ->
        {:reply, {:error, :no_snapshots}, state}
    end
  end

  @impl true
  def handle_call(:list, _from, state) do
    {:reply, {:ok, state.snapshots}, state}
  end

  @impl true
  def handle_call({:get_info, snapshot_id}, _from, state) do
    case find_snapshot(snapshot_id, state.snapshots) do
      nil -> {:reply, {:error, :not_found}, state}
      snapshot -> {:reply, {:ok, snapshot}, state}
    end
  end

  @impl true
  def handle_call({:delete, snapshot_id}, _from, state) do
    case find_snapshot(snapshot_id, state.snapshots) do
      nil ->
        {:reply, {:error, :not_found}, state}

      snapshot ->
        case delete_backend_snapshot(snapshot, state.backend) do
          :ok ->
            new_snapshots = Enum.reject(state.snapshots, &(&1.id == snapshot_id))
            {:reply, :ok, %{state | snapshots: new_snapshots}}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
    end
  end

  @impl true
  def handle_call({:cleanup, max_count}, _from, state) do
    {keep, remove} = Enum.split(state.snapshots, max_count)

    deleted =
      Enum.count(remove, fn snapshot ->
        case delete_backend_snapshot(snapshot, state.backend) do
          :ok -> true
          _ -> false
        end
      end)

    {:reply, {:ok, deleted}, %{state | snapshots: keep}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    max = state.config[:max_snapshots] || @default_max_snapshots

    if length(state.snapshots) > max do
      GenServer.call(self(), {:cleanup, max})
    end

    schedule_cleanup()
    {:noreply, state}
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Private Functions
  # ═══════════════════════════════════════════════════════════════════════════

  defp detect_backend do
    # Detection order based on priority
    cond do
      # rpm-ostree has native deployment support
      System.find_executable("rpm-ostree") ->
        :rpm_ostree

      # btrfs is preferred for Linux
      System.find_executable("btrfs") &&
        File.exists?("/proc/filesystems") &&
        String.contains?(File.read!("/proc/filesystems"), "btrfs") ->
        :btrfs

      # ZFS is excellent for snapshots
      System.find_executable("zfs") ->
        :zfs

      # Snapper (openSUSE)
      System.find_executable("snapper") ->
        :snapper

      # LVM as fallback
      System.find_executable("lvm") ->
        :lvm

      # macOS APFS
      System.find_executable("tmutil") ->
        :apfs

      true ->
        :transaction_log
    end
  end

  defp load_config do
    config_paths = [
      Path.expand("~/.config/dnfinition/snapshots.scm"),
      "/etc/dnfinition/snapshots.scm"
    ]

    default_config = %{
      max_snapshots: @default_max_snapshots,
      auto_cleanup: true,
      snapshot_path: "/.snapshots"
    }

    case Enum.find(config_paths, &File.exists?/1) do
      nil ->
        default_config

      path ->
        case parse_scheme_config(path) do
          {:ok, parsed} -> Map.merge(default_config, parsed)
          {:error, _} -> default_config
        end
    end
  end

  defp parse_scheme_config(path) do
    # Simple key-value parser for Scheme config
    # Format: (key . value) or (key value)
    try do
      content = File.read!(path)

      config =
        Regex.scan(~r/\((\w+[-\w]*)\s+[.\s]*([^\)]+)\)/, content)
        |> Enum.reduce(%{}, fn [_, key, value], acc ->
          atom_key = key |> String.replace("-", "_") |> String.to_atom()
          parsed_value = parse_config_value(String.trim(value))
          Map.put(acc, atom_key, parsed_value)
        end)

      {:ok, config}
    rescue
      _ -> {:error, :parse_error}
    end
  end

  defp parse_config_value("#t"), do: true
  defp parse_config_value("#f"), do: false
  defp parse_config_value(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> String.trim(value, "\"")
    end
  end

  defp schedule_cleanup do
    # Run cleanup every hour
    Process.send_after(self(), :cleanup, :timer.hours(1))
  end

  defp find_snapshot(id, snapshots) do
    Enum.find(snapshots, &(&1.id == id))
  end

  defp create_backend_snapshot(snapshot, backend) do
    case backend do
      :rpm_ostree ->
        # rpm-ostree automatically creates deployments
        :ok

      :btrfs ->
        # Create btrfs snapshot
        path = "/.snapshots/#{snapshot.id}"
        case System.cmd("btrfs", ["subvolume", "snapshot", "-r", "/", path]) do
          {_, 0} -> :ok
          {error, _} -> {:error, error}
        end

      :zfs ->
        # Create ZFS snapshot
        pool_name = detect_zfs_root_pool()
        snapshot_name = "#{pool_name}@dnfinition-#{snapshot.id}"

        case System.cmd("zfs", ["snapshot", "-r", snapshot_name]) do
          {_, 0} -> :ok
          {error, _} -> {:error, error}
        end

      :snapper ->
        # Use snapper
        case System.cmd("snapper", ["create", "-d", snapshot.description]) do
          {_, 0} -> :ok
          {error, _} -> {:error, error}
        end

      :transaction_log ->
        # Just log the transaction, no actual snapshot
        :ok

      _ ->
        {:error, :unsupported_backend}
    end
  end

  defp rollback_backend_snapshot(snapshot, backend) do
    case backend do
      :rpm_ostree ->
        # rpm-ostree rollback requires reboot
        case System.cmd("rpm-ostree", ["rollback"]) do
          {_, 0} -> {:error, :requires_reboot}
          {error, _} -> {:error, error}
        end

      :btrfs ->
        # btrfs rollback is complex, may require reboot
        path = "/.snapshots/#{snapshot.id}"
        # This is simplified - real implementation needs more work
        {:error, :requires_reboot}

      :zfs ->
        # ZFS rollback
        pool_name = detect_zfs_root_pool()
        snapshot_name = "#{pool_name}@dnfinition-#{snapshot.id}"

        case System.cmd("zfs", ["rollback", "-r", snapshot_name]) do
          {_, 0} -> :ok
          {error, _} -> {:error, error}
        end

      :snapper ->
        # Snapper undochange
        case System.cmd("snapper", ["undochange", "#{snapshot.id}..0"]) do
          {_, 0} -> :ok
          {error, _} -> {:error, error}
        end

      _ ->
        {:error, :unsupported_backend}
    end
  end

  defp delete_backend_snapshot(snapshot, backend) do
    case backend do
      :btrfs ->
        path = "/.snapshots/#{snapshot.id}"
        case System.cmd("btrfs", ["subvolume", "delete", path]) do
          {_, 0} -> :ok
          {error, _} -> {:error, error}
        end

      :zfs ->
        pool_name = detect_zfs_root_pool()
        snapshot_name = "#{pool_name}@dnfinition-#{snapshot.id}"

        case System.cmd("zfs", ["destroy", snapshot_name]) do
          {_, 0} -> :ok
          {error, _} -> {:error, error}
        end

      :snapper ->
        case System.cmd("snapper", ["delete", "#{snapshot.id}"]) do
          {_, 0} -> :ok
          {error, _} -> {:error, error}
        end

      _ ->
        :ok
    end
  end

  defp detect_zfs_root_pool do
    # Detect the ZFS dataset containing root filesystem
    case System.cmd("zfs", ["list", "-H", "-o", "name", "/"]) do
      {output, 0} ->
        output |> String.trim()

      _ ->
        # Fallback: try to find from mount
        case System.cmd("findmnt", ["-n", "-o", "SOURCE", "/"]) do
          {output, 0} ->
            output |> String.trim() |> String.split("/") |> hd()

          _ ->
            # Default fallback
            "rpool/ROOT"
        end
    end
  end
end

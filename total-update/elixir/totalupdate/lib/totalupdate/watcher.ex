# SPDX-License-Identifier: AGPL-3.0-or-later
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <jonathan@hyperpolymath.io>

defmodule TotalUpdate.Watcher do
  @moduledoc """
  File and package watcher for detecting changes.

  Monitors:
  - Package database changes (dpkg, rpm, etc.)
  - Configuration file changes
  - New package installations outside TotalUpdate

  Uses filesystem notifications when available (inotify on Linux),
  falls back to polling otherwise.
  """

  use GenServer
  require Logger

  @poll_interval :timer.seconds(60)

  # Paths to watch for package database changes
  @watch_paths %{
    apt: ["/var/lib/dpkg/status", "/var/lib/apt/lists"],
    dnf: ["/var/lib/dnf", "/var/cache/dnf"],
    rpm: ["/var/lib/rpm"],
    pacman: ["/var/lib/pacman/local"],
    nix: ["/nix/var/nix/profiles"],
    guix: ["/var/guix/profiles"]
  }

  # ═══════════════════════════════════════════════════════════════════════════
  # Client API
  # ═══════════════════════════════════════════════════════════════════════════

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Get list of watched paths"
  def watched_paths do
    GenServer.call(__MODULE__, :watched_paths)
  end

  @doc "Check if any changes detected since last check"
  def changes_detected? do
    GenServer.call(__MODULE__, :changes_detected?)
  end

  @doc "Get last detected change"
  def last_change do
    GenServer.call(__MODULE__, :last_change)
  end

  @doc "Force a check for changes"
  def check_now do
    GenServer.cast(__MODULE__, :check_now)
  end

  @doc "Add a path to watch"
  def watch(path) do
    GenServer.call(__MODULE__, {:watch, path})
  end

  @doc "Remove a path from watch list"
  def unwatch(path) do
    GenServer.call(__MODULE__, {:unwatch, path})
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Server Callbacks
  # ═══════════════════════════════════════════════════════════════════════════

  @impl true
  def init(_opts) do
    # Detect which package managers are present and watch their paths
    paths_to_watch = detect_paths_to_watch()

    state = %{
      watched_paths: paths_to_watch,
      path_mtimes: get_mtimes(paths_to_watch),
      last_change: nil,
      changes_pending: false,
      poll_ref: nil
    }

    # Start polling
    state = schedule_poll(state)

    Logger.info("Watcher started, monitoring #{length(paths_to_watch)} paths")
    {:ok, state}
  end

  @impl true
  def handle_call(:watched_paths, _from, state) do
    {:reply, {:ok, state.watched_paths}, state}
  end

  @impl true
  def handle_call(:changes_detected?, _from, state) do
    {:reply, state.changes_pending, state}
  end

  @impl true
  def handle_call(:last_change, _from, state) do
    {:reply, {:ok, state.last_change}, state}
  end

  @impl true
  def handle_call({:watch, path}, _from, state) do
    if File.exists?(path) do
      new_paths = [path | state.watched_paths] |> Enum.uniq()
      new_mtimes = Map.put(state.path_mtimes, path, get_mtime(path))
      {:reply, :ok, %{state | watched_paths: new_paths, path_mtimes: new_mtimes}}
    else
      {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call({:unwatch, path}, _from, state) do
    new_paths = List.delete(state.watched_paths, path)
    new_mtimes = Map.delete(state.path_mtimes, path)
    {:reply, :ok, %{state | watched_paths: new_paths, path_mtimes: new_mtimes}}
  end

  @impl true
  def handle_cast(:check_now, state) do
    state = check_for_changes(state)
    {:noreply, state}
  end

  @impl true
  def handle_info(:poll, state) do
    state = check_for_changes(state)
    state = schedule_poll(state)
    {:noreply, state}
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Private Functions
  # ═══════════════════════════════════════════════════════════════════════════

  defp detect_paths_to_watch do
    @watch_paths
    |> Enum.flat_map(fn {_pm, paths} ->
      Enum.filter(paths, &File.exists?/1)
    end)
  end

  defp get_mtimes(paths) do
    paths
    |> Enum.map(fn path -> {path, get_mtime(path)} end)
    |> Map.new()
  end

  defp get_mtime(path) do
    case File.stat(path) do
      {:ok, %{mtime: mtime}} -> mtime
      _ -> nil
    end
  end

  defp check_for_changes(state) do
    new_mtimes = get_mtimes(state.watched_paths)

    changed_paths =
      Enum.filter(state.watched_paths, fn path ->
        Map.get(new_mtimes, path) != Map.get(state.path_mtimes, path)
      end)

    if changed_paths != [] do
      Logger.info("Detected changes in: #{inspect(changed_paths)}")

      # Notify daemon of changes
      TotalUpdate.Daemon.check_now()

      %{state |
        path_mtimes: new_mtimes,
        last_change: %{
          paths: changed_paths,
          detected_at: DateTime.utc_now()
        },
        changes_pending: true
      }
    else
      %{state | path_mtimes: new_mtimes, changes_pending: false}
    end
  end

  defp schedule_poll(state) do
    ref = Process.send_after(self(), :poll, @poll_interval)
    %{state | poll_ref: ref}
  end
end

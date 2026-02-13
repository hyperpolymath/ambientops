# SPDX-License-Identifier: AGPL-3.0-or-later
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <jonathan@hyperpolymath.io>

defmodule TotalUpdate.Daemon do
  @moduledoc """
  Main TotalUpdate daemon process.

  Coordinates:
  - Update checking across all package managers
  - Download scheduling
  - Update application (via DNFinition)
  - Strategy enforcement
  """

  use GenServer
  require Logger

  @default_check_interval :timer.hours(4)

  # ═══════════════════════════════════════════════════════════════════════════
  # Client API
  # ═══════════════════════════════════════════════════════════════════════════

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Trigger manual update check.
  """
  def check_now do
    GenServer.call(__MODULE__, :check_now, :infinity)
  end

  @doc """
  Get current update status.
  """
  def status do
    GenServer.call(__MODULE__, :status)
  end

  @doc """
  Get available updates.
  """
  def available_updates do
    GenServer.call(__MODULE__, :available_updates)
  end

  @doc """
  Apply pending updates.
  """
  def apply_updates(opts \\ []) do
    GenServer.call(__MODULE__, {:apply_updates, opts}, :infinity)
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Server Callbacks
  # ═══════════════════════════════════════════════════════════════════════════

  @impl true
  def init(_opts) do
    config = load_config()

    state = %{
      config: config,
      last_check: nil,
      available_updates: [],
      status: :idle,
      check_in_progress: false
    }

    # Schedule first check
    schedule_check(config.check_interval)

    {:ok, state}
  end

  @impl true
  def handle_call(:check_now, _from, state) do
    if state.check_in_progress do
      {:reply, {:error, :check_in_progress}, state}
    else
      new_state = perform_check(state)
      {:reply, {:ok, new_state.available_updates}, new_state}
    end
  end

  @impl true
  def handle_call(:status, _from, state) do
    status = %{
      status: state.status,
      last_check: state.last_check,
      updates_available: length(state.available_updates),
      check_in_progress: state.check_in_progress
    }

    {:reply, {:ok, status}, state}
  end

  @impl true
  def handle_call(:available_updates, _from, state) do
    {:reply, {:ok, state.available_updates}, state}
  end

  @impl true
  def handle_call({:apply_updates, opts}, _from, state) do
    packages = Keyword.get(opts, :packages, state.available_updates)

    if Enum.empty?(packages) do
      {:reply, {:ok, :nothing_to_do}, state}
    else
      case apply_package_updates(packages, state.config) do
        :ok ->
          # Re-check after applying
          new_state = perform_check(state)
          {:reply, :ok, new_state}

        {:error, reason} ->
          {:reply, {:error, reason}, state}
      end
    end
  end

  @impl true
  def handle_info(:scheduled_check, state) do
    new_state = perform_check(state)
    schedule_check(state.config.check_interval)
    {:noreply, new_state}
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Private Functions
  # ═══════════════════════════════════════════════════════════════════════════

  defp load_config do
    config_paths = [
      Path.expand("~/.config/totalupdate/config.scm"),
      "/etc/totalupdate/config.scm"
    ]

    default_config = %{
      check_interval: @default_check_interval,
      mode: :conservative,  # :aggressive, :conservative, :manual
      auto_apply: false,
      apply_on_idle: true,
      download_in_background: true,
      whitelist: [],
      blacklist: [],
      version_pins: %{}
    }

    case Enum.find(config_paths, &File.exists?/1) do
      nil ->
        default_config

      path ->
        case parse_config_file(path) do
          {:ok, parsed} -> Map.merge(default_config, parsed)
          {:error, _} -> default_config
        end
    end
  end

  defp parse_config_file(path) do
    try do
      content = File.read!(path)

      config =
        Regex.scan(~r/\((\w+[-\w]*)\s+[.\s]*([^\)]+)\)/, content)
        |> Enum.reduce(%{}, fn [_, key, value], acc ->
          atom_key = key |> String.replace("-", "_") |> String.to_atom()
          parsed_value = parse_value(String.trim(value))
          Map.put(acc, atom_key, parsed_value)
        end)

      {:ok, config}
    rescue
      _ -> {:error, :parse_error}
    end
  end

  defp parse_value("#t"), do: true
  defp parse_value("#f"), do: false
  defp parse_value(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> String.trim(value, "\"")
    end
  end

  defp schedule_check(interval) do
    Process.send_after(self(), :scheduled_check, interval)
  end

  defp perform_check(state) do
    Logger.info("Checking for updates...")

    state = %{state | check_in_progress: true, status: :checking}

    # Check all enabled package managers
    updates = collect_updates(state.config)

    # Filter based on strategy
    filtered_updates =
      updates
      |> filter_blacklisted(state.config.blacklist)
      |> filter_pinned(state.config.version_pins)

    Logger.info("Found #{length(filtered_updates)} updates available")

    # Auto-apply if configured
    if state.config.auto_apply and not Enum.empty?(filtered_updates) do
      apply_package_updates(filtered_updates, state.config)
    end

    %{state |
      check_in_progress: false,
      status: :idle,
      last_check: DateTime.utc_now(),
      available_updates: filtered_updates
    }
  end

  defp collect_updates(_config) do
    # Collect updates from all sources
    updates = []

    # System packages (via DNFinition backends)
    updates =
      updates ++ collect_system_updates()

    # Language packages
    updates = updates ++ check_deno_updates()
    updates = updates ++ check_python_updates()
    updates = updates ++ check_rust_updates()

    # Universal packages
    updates = updates ++ check_flatpak_updates()

    updates
  end

  defp collect_system_updates do
    # Query available updates from all registered backends
    case TotalUpdate.PluginManager.available_plugins() do
      {:ok, plugins} ->
        Enum.flat_map(plugins, fn plugin ->
          case get_backend_updates(plugin) do
            {:ok, updates} -> updates
            _ -> []
          end
        end)

      _ ->
        []
    end
  end

  defp get_backend_updates(plugin) do
    try do
      backend = plugin.module.backend_module()

      if function_exported?(backend, :get_upgradable, 0) do
        {:ok, backend.get_upgradable()}
      else
        {:ok, []}
      end
    rescue
      _ -> {:error, :backend_unavailable}
    end
  end

  defp check_deno_updates do
    # Check Deno for updates
    []
  end

  defp check_python_updates do
    # Check pipx for updates
    []
  end

  defp check_rust_updates do
    # Check rustup and cargo
    []
  end

  defp check_flatpak_updates do
    case System.cmd("flatpak", ["remote-ls", "--updates", "--columns=application"],
           stderr_to_stdout: true) do
      {output, 0} ->
        output
        |> String.split("\n", trim: true)
        |> Enum.map(fn app -> %{name: app, source: :flatpak} end)

      _ ->
        []
    end
  rescue
    _ -> []
  end

  defp filter_blacklisted(updates, blacklist) do
    Enum.reject(updates, fn update ->
      update.name in blacklist
    end)
  end

  defp filter_pinned(updates, pins) do
    Enum.reject(updates, fn update ->
      Map.has_key?(pins, update.name)
    end)
  end

  defp apply_package_updates(packages, config) do
    Logger.info("Applying #{length(packages)} updates...")

    # Create snapshot first via DNFinition
    case DNFinition.SnapshotManager.create("TotalUpdate automatic update") do
      {:ok, snapshot_id} ->
        Logger.info("Created snapshot #{snapshot_id}")

        # Log transaction
        DNFinition.TransactionLog.begin_transaction(
          snapshot_id,
          "totalupdate:apply",
          Enum.map(packages, & &1.name)
        )

        # Apply updates
        result = do_apply_updates(packages)

        DNFinition.TransactionLog.complete_transaction(snapshot_id, result == :ok)

        result

      {:error, reason} ->
        Logger.error("Failed to create snapshot: #{inspect(reason)}")
        {:error, :snapshot_failed}
    end
  end

  defp do_apply_updates(packages) do
    # Group by source and apply
    packages
    |> Enum.group_by(& &1.source)
    |> Enum.each(fn {source, pkgs} ->
      apply_updates_for_source(source, pkgs)
    end)

    :ok
  end

  defp apply_updates_for_source(:flatpak, _packages) do
    System.cmd("flatpak", ["update", "-y"], stderr_to_stdout: true)
  end

  defp apply_updates_for_source(_source, _packages) do
    # TODO: Implement for other sources
    :ok
  end
end

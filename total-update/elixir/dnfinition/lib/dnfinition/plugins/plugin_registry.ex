# SPDX-License-Identifier: AGPL-3.0-or-later
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <jonathan@hyperpolymath.io>

defmodule DNFinition.Plugins.PluginRegistry do
  @moduledoc """
  Plugin registry for package manager backends.

  This module provides:
  - Dynamic registration and discovery of package manager backends
  - Plugin metadata and capability tracking
  - Priority-based backend selection
  - Hot-reload support for plugins

  ## Plugin Types

  - `:builtin` - Compiled with DNFinition (Guix, Nix, apt, dnf, etc.)
  - `:external` - Loaded dynamically from shared libraries
  - `:script` - Shell script wrapper
  - `:config` - Configuration-defined custom backends

  ## Usage

      # Register a new plugin
      DNFinition.Plugins.PluginRegistry.register(MyPlugin)

      # Get plugin by ID
      plugin = DNFinition.Plugins.PluginRegistry.get("guix")

      # Find best plugin for capabilities
      plugin = DNFinition.Plugins.PluginRegistry.best_for([:install, :rollback])

      # List all available plugins
      plugins = DNFinition.Plugins.PluginRegistry.list_available()
  """

  use GenServer
  require Logger

  @type capability ::
          :install
          | :remove
          | :upgrade
          | :search
          | :query
          | :transactions
          | :native_rollback
          | :dry_run
          | :pinning
          | :hold
          | :autoremove
          | :cache_clean
          | :parallel_download
          | :verify
          | :dependencies
          | :provides
          | :files
          | :history
          | :offline

  @type plugin_type :: :builtin | :external | :script | :config

  @type plugin_status :: :available | :unavailable | :disabled | :error | :degraded

  @type plugin_metadata :: %{
          id: String.t(),
          name: String.t(),
          version: String.t(),
          description: String.t(),
          pm_type: atom(),
          plugin_type: plugin_type(),
          status: plugin_status(),
          priority: 0..100,
          capabilities: [capability()],
          required_commands: [String.t()],
          config_path: String.t() | nil,
          has_native_recovery: boolean(),
          preferred_snapshot: atom()
        }

  # ═══════════════════════════════════════════════════════════════════════════
  # Client API
  # ═══════════════════════════════════════════════════════════════════════════

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Register a new plugin.
  """
  @spec register(module()) :: :ok | {:error, term()}
  def register(plugin_module) do
    GenServer.call(__MODULE__, {:register, plugin_module})
  end

  @doc """
  Unregister a plugin by ID.
  """
  @spec unregister(String.t()) :: :ok | {:error, :not_found}
  def unregister(id) do
    GenServer.call(__MODULE__, {:unregister, id})
  end

  @doc """
  Get a plugin by ID.
  """
  @spec get(String.t()) :: {:ok, plugin_metadata()} | {:error, :not_found}
  def get(id) do
    GenServer.call(__MODULE__, {:get, id})
  end

  @doc """
  Get a plugin by package manager type.
  """
  @spec get_by_type(atom()) :: {:ok, plugin_metadata()} | {:error, :not_found}
  def get_by_type(pm_type) do
    GenServer.call(__MODULE__, {:get_by_type, pm_type})
  end

  @doc """
  List all registered plugins.
  """
  @spec list() :: [plugin_metadata()]
  def list do
    GenServer.call(__MODULE__, :list)
  end

  @doc """
  List only available plugins.
  """
  @spec list_available() :: [plugin_metadata()]
  def list_available do
    GenServer.call(__MODULE__, :list_available)
  end

  @doc """
  Find the best plugin that has all required capabilities.
  Returns highest-priority matching plugin.
  """
  @spec best_for([capability()]) :: {:ok, plugin_metadata()} | {:error, :no_match}
  def best_for(required_capabilities) do
    GenServer.call(__MODULE__, {:best_for, required_capabilities})
  end

  @doc """
  Count plugins with a specific capability.
  """
  @spec count_with_capability(capability()) :: non_neg_integer()
  def count_with_capability(capability) do
    GenServer.call(__MODULE__, {:count_with_capability, capability})
  end

  @doc """
  Enable a plugin.
  """
  @spec enable(String.t()) :: :ok | {:error, :not_found}
  def enable(id) do
    GenServer.call(__MODULE__, {:enable, id})
  end

  @doc """
  Disable a plugin.
  """
  @spec disable(String.t()) :: :ok | {:error, :not_found}
  def disable(id) do
    GenServer.call(__MODULE__, {:disable, id})
  end

  @doc """
  Refresh status of all plugins (check availability).
  """
  @spec refresh() :: :ok
  def refresh do
    GenServer.call(__MODULE__, :refresh)
  end

  @doc """
  Discover and register all built-in plugins.
  """
  @spec discover_builtin() :: :ok
  def discover_builtin do
    GenServer.call(__MODULE__, :discover_builtin)
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Server Callbacks
  # ═══════════════════════════════════════════════════════════════════════════

  @impl true
  def init(_opts) do
    state = %{
      plugins: %{},
      by_type: %{}
    }

    # Auto-discover built-in plugins on startup
    send(self(), :discover_builtin)

    {:ok, state}
  end

  @impl true
  def handle_call({:register, plugin_module}, _from, state) do
    try do
      metadata = plugin_module.metadata()
      id = metadata.id

      # Check availability
      status =
        if check_commands_available(metadata.required_commands) do
          :available
        else
          :unavailable
        end

      metadata = Map.put(metadata, :status, status)
      metadata = Map.put(metadata, :module, plugin_module)

      new_plugins = Map.put(state.plugins, id, metadata)
      new_by_type = Map.put(state.by_type, metadata.pm_type, id)

      Logger.info("Registered plugin: #{metadata.name} (#{id}) - #{status}")
      {:reply, :ok, %{state | plugins: new_plugins, by_type: new_by_type}}
    rescue
      e ->
        Logger.error("Failed to register plugin: #{inspect(e)}")
        {:reply, {:error, e}, state}
    end
  end

  @impl true
  def handle_call({:unregister, id}, _from, state) do
    case Map.get(state.plugins, id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      metadata ->
        new_plugins = Map.delete(state.plugins, id)
        new_by_type = Map.delete(state.by_type, metadata.pm_type)
        Logger.info("Unregistered plugin: #{id}")
        {:reply, :ok, %{state | plugins: new_plugins, by_type: new_by_type}}
    end
  end

  @impl true
  def handle_call({:get, id}, _from, state) do
    case Map.get(state.plugins, id) do
      nil -> {:reply, {:error, :not_found}, state}
      metadata -> {:reply, {:ok, metadata}, state}
    end
  end

  @impl true
  def handle_call({:get_by_type, pm_type}, _from, state) do
    case Map.get(state.by_type, pm_type) do
      nil ->
        {:reply, {:error, :not_found}, state}

      id ->
        {:reply, {:ok, Map.get(state.plugins, id)}, state}
    end
  end

  @impl true
  def handle_call(:list, _from, state) do
    plugins = Map.values(state.plugins)
    {:reply, plugins, state}
  end

  @impl true
  def handle_call(:list_available, _from, state) do
    plugins =
      state.plugins
      |> Map.values()
      |> Enum.filter(&(&1.status == :available))

    {:reply, plugins, state}
  end

  @impl true
  def handle_call({:best_for, required}, _from, state) do
    best =
      state.plugins
      |> Map.values()
      |> Enum.filter(&(&1.status == :available))
      |> Enum.filter(fn plugin ->
        Enum.all?(required, &(&1 in plugin.capabilities))
      end)
      |> Enum.max_by(& &1.priority, fn -> nil end)

    case best do
      nil -> {:reply, {:error, :no_match}, state}
      plugin -> {:reply, {:ok, plugin}, state}
    end
  end

  @impl true
  def handle_call({:count_with_capability, cap}, _from, state) do
    count =
      state.plugins
      |> Map.values()
      |> Enum.filter(&(&1.status == :available))
      |> Enum.count(&(cap in &1.capabilities))

    {:reply, count, state}
  end

  @impl true
  def handle_call({:enable, id}, _from, state) do
    case Map.get(state.plugins, id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      metadata ->
        new_metadata = %{metadata | status: :available}
        new_plugins = Map.put(state.plugins, id, new_metadata)
        {:reply, :ok, %{state | plugins: new_plugins}}
    end
  end

  @impl true
  def handle_call({:disable, id}, _from, state) do
    case Map.get(state.plugins, id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      metadata ->
        new_metadata = %{metadata | status: :disabled}
        new_plugins = Map.put(state.plugins, id, new_metadata)
        {:reply, :ok, %{state | plugins: new_plugins}}
    end
  end

  @impl true
  def handle_call(:refresh, _from, state) do
    new_plugins =
      state.plugins
      |> Enum.map(fn {id, metadata} ->
        status =
          if metadata.status != :disabled do
            if check_commands_available(metadata.required_commands) do
              :available
            else
              :unavailable
            end
          else
            :disabled
          end

        {id, %{metadata | status: status}}
      end)
      |> Map.new()

    {:reply, :ok, %{state | plugins: new_plugins}}
  end

  @impl true
  def handle_call(:discover_builtin, _from, state) do
    # Register built-in plugins
    builtin_plugins = [
      DNFinition.Plugins.GuixPlugin,
      DNFinition.Plugins.NixPlugin
      # Future: AptPlugin, DnfPlugin, PacmanPlugin, FlatpakPlugin
    ]

    new_state =
      Enum.reduce(builtin_plugins, state, fn plugin_module, acc ->
        try do
          if Code.ensure_loaded?(plugin_module) do
            metadata = plugin_module.metadata()
            id = metadata.id

            status =
              if check_commands_available(metadata.required_commands) do
                :available
              else
                :unavailable
              end

            metadata = Map.put(metadata, :status, status)
            metadata = Map.put(metadata, :module, plugin_module)

            new_plugins = Map.put(acc.plugins, id, metadata)
            new_by_type = Map.put(acc.by_type, metadata.pm_type, id)

            Logger.debug("Discovered built-in plugin: #{metadata.name} (#{status})")
            %{acc | plugins: new_plugins, by_type: new_by_type}
          else
            acc
          end
        rescue
          _ -> acc
        end
      end)

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_info(:discover_builtin, state) do
    {:reply, :ok, new_state} = handle_call(:discover_builtin, nil, state)
    {:noreply, new_state}
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Private Functions
  # ═══════════════════════════════════════════════════════════════════════════

  defp check_commands_available(commands) do
    Enum.all?(commands, fn cmd ->
      System.find_executable(cmd) != nil
    end)
  end
end

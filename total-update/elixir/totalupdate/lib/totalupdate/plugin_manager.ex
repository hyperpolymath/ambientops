# SPDX-License-Identifier: AGPL-3.0-or-later
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <jonathan@hyperpolymath.io>

defmodule TotalUpdate.PluginManager do
  @moduledoc """
  Plugin manager for TotalUpdate package manager backends.

  Responsibilities:
  - Discover and load plugins from configured paths
  - Register/unregister plugins at runtime
  - Route operations to appropriate backends
  - Manage plugin lifecycle (init/shutdown)

  Plugin discovery paths (in priority order):
  1. Built-in plugins (Guix, Nix, apt, dnf, etc.)
  2. ~/.config/totalupdate/plugins/ (user plugins)
  3. /usr/share/totalupdate/plugins/ (system plugins)
  4. /usr/local/share/totalupdate/plugins/ (local plugins)
  """

  use GenServer
  require Logger

  @plugin_paths [
    Path.expand("~/.config/totalupdate/plugins"),
    "/usr/share/totalupdate/plugins",
    "/usr/local/share/totalupdate/plugins"
  ]

  # Built-in plugins (module references)
  @builtin_plugins [
    DNFinition.Plugins.GuixPlugin,
    DNFinition.Plugins.NixPlugin
  ]

  # ═══════════════════════════════════════════════════════════════════════════
  # Client API
  # ═══════════════════════════════════════════════════════════════════════════

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "List all registered plugins"
  def list_plugins do
    GenServer.call(__MODULE__, :list_plugins)
  end

  @doc "Get plugin by ID"
  def get_plugin(plugin_id) do
    GenServer.call(__MODULE__, {:get_plugin, plugin_id})
  end

  @doc "Get all available plugins (those whose executables are present)"
  def available_plugins do
    GenServer.call(__MODULE__, :available_plugins)
  end

  @doc "Register a plugin module"
  def register(plugin_module) do
    GenServer.call(__MODULE__, {:register, plugin_module})
  end

  @doc "Unregister a plugin by ID"
  def unregister(plugin_id) do
    GenServer.call(__MODULE__, {:unregister, plugin_id})
  end

  @doc "Find best plugin for given capabilities"
  def best_for(capabilities) when is_list(capabilities) do
    GenServer.call(__MODULE__, {:best_for, capabilities})
  end

  @doc "Find all plugins supporting given capabilities"
  def plugins_for(capabilities) when is_list(capabilities) do
    GenServer.call(__MODULE__, {:plugins_for, capabilities})
  end

  @doc "Reload plugins from discovery paths"
  def reload do
    GenServer.call(__MODULE__, :reload)
  end

  @doc "Get plugin health/status"
  def health do
    GenServer.call(__MODULE__, :health)
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Server Callbacks
  # ═══════════════════════════════════════════════════════════════════════════

  @impl true
  def init(_opts) do
    state = %{
      plugins: %{},
      load_errors: [],
      last_reload: nil
    }

    # Load built-in plugins
    state = load_builtin_plugins(state)

    # Discover external plugins
    state = discover_plugins(state)

    Logger.info("PluginManager started with #{map_size(state.plugins)} plugins")
    {:ok, state}
  end

  @impl true
  def handle_call(:list_plugins, _from, state) do
    plugins =
      state.plugins
      |> Enum.map(fn {id, plugin} ->
        %{
          id: id,
          name: plugin.metadata.name,
          priority: plugin.metadata.priority,
          available: plugin.available,
          capabilities: plugin.metadata.capabilities
        }
      end)
      |> Enum.sort_by(& &1.priority, :desc)

    {:reply, {:ok, plugins}, state}
  end

  @impl true
  def handle_call({:get_plugin, plugin_id}, _from, state) do
    case Map.get(state.plugins, plugin_id) do
      nil -> {:reply, {:error, :not_found}, state}
      plugin -> {:reply, {:ok, plugin}, state}
    end
  end

  @impl true
  def handle_call(:available_plugins, _from, state) do
    available =
      state.plugins
      |> Enum.filter(fn {_id, plugin} -> plugin.available end)
      |> Enum.map(fn {id, plugin} ->
        %{
          id: id,
          name: plugin.metadata.name,
          priority: plugin.metadata.priority,
          capabilities: plugin.metadata.capabilities
        }
      end)
      |> Enum.sort_by(& &1.priority, :desc)

    {:reply, {:ok, available}, state}
  end

  @impl true
  def handle_call({:register, plugin_module}, _from, state) do
    case register_plugin(state, plugin_module) do
      {:ok, new_state} ->
        metadata = plugin_module.metadata()
        Logger.info("Registered plugin: #{metadata.name} (#{metadata.id})")
        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:unregister, plugin_id}, _from, state) do
    case Map.get(state.plugins, plugin_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      plugin ->
        # Call shutdown if plugin supports it
        if function_exported?(plugin.module, :shutdown, 0) do
          plugin.module.shutdown()
        end

        new_plugins = Map.delete(state.plugins, plugin_id)
        Logger.info("Unregistered plugin: #{plugin_id}")
        {:reply, :ok, %{state | plugins: new_plugins}}
    end
  end

  @impl true
  def handle_call({:best_for, capabilities}, _from, state) do
    result =
      state.plugins
      |> Enum.filter(fn {_id, plugin} ->
        plugin.available and
          Enum.all?(capabilities, &(&1 in plugin.metadata.capabilities))
      end)
      |> Enum.sort_by(fn {_id, plugin} -> plugin.metadata.priority end, :desc)
      |> List.first()

    case result do
      nil -> {:reply, {:error, :no_matching_plugin}, state}
      {_id, plugin} -> {:reply, {:ok, plugin}, state}
    end
  end

  @impl true
  def handle_call({:plugins_for, capabilities}, _from, state) do
    matching =
      state.plugins
      |> Enum.filter(fn {_id, plugin} ->
        plugin.available and
          Enum.all?(capabilities, &(&1 in plugin.metadata.capabilities))
      end)
      |> Enum.map(fn {id, plugin} ->
        %{
          id: id,
          name: plugin.metadata.name,
          priority: plugin.metadata.priority,
          module: plugin.module
        }
      end)
      |> Enum.sort_by(& &1.priority, :desc)

    {:reply, {:ok, matching}, state}
  end

  @impl true
  def handle_call(:reload, _from, state) do
    # Clear existing plugins
    Enum.each(state.plugins, fn {_id, plugin} ->
      if function_exported?(plugin.module, :shutdown, 0) do
        plugin.module.shutdown()
      end
    end)

    new_state = %{
      plugins: %{},
      load_errors: [],
      last_reload: DateTime.utc_now()
    }

    new_state = load_builtin_plugins(new_state)
    new_state = discover_plugins(new_state)

    Logger.info("Reloaded plugins: #{map_size(new_state.plugins)} active")
    {:reply, {:ok, map_size(new_state.plugins)}, new_state}
  end

  @impl true
  def handle_call(:health, _from, state) do
    health = %{
      total_plugins: map_size(state.plugins),
      available_plugins: Enum.count(state.plugins, fn {_, p} -> p.available end),
      load_errors: length(state.load_errors),
      last_reload: state.last_reload,
      plugins:
        Enum.map(state.plugins, fn {id, plugin} ->
          %{
            id: id,
            name: plugin.metadata.name,
            available: plugin.available,
            priority: plugin.metadata.priority
          }
        end)
    }

    {:reply, {:ok, health}, state}
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Private Functions
  # ═══════════════════════════════════════════════════════════════════════════

  defp load_builtin_plugins(state) do
    Enum.reduce(@builtin_plugins, state, fn plugin_module, acc ->
      case register_plugin(acc, plugin_module) do
        {:ok, new_state} -> new_state
        {:error, _reason} -> acc
      end
    end)
  end

  defp discover_plugins(state) do
    # Discover plugins from filesystem paths
    @plugin_paths
    |> Enum.filter(&File.dir?/1)
    |> Enum.flat_map(&discover_plugins_in_path/1)
    |> Enum.reduce(state, fn plugin_module, acc ->
      case register_plugin(acc, plugin_module) do
        {:ok, new_state} -> new_state
        {:error, reason} ->
          %{acc | load_errors: [{plugin_module, reason} | acc.load_errors]}
      end
    end)
  end

  defp discover_plugins_in_path(path) do
    # Look for .ex or .exs files that define plugins
    path
    |> Path.join("*.{ex,exs}")
    |> Path.wildcard()
    |> Enum.flat_map(fn file ->
      case Code.compile_file(file) do
        modules when is_list(modules) ->
          modules
          |> Enum.map(fn {module, _binary} -> module end)
          |> Enum.filter(&implements_plugin_behaviour?/1)

        _ ->
          []
      end
    end)
  rescue
    _ -> []
  end

  defp implements_plugin_behaviour?(module) do
    behaviours = module.module_info(:attributes)[:behaviour] || []
    DNFinition.Plugins.Plugin in behaviours
  rescue
    _ -> false
  end

  defp register_plugin(state, plugin_module) do
    if implements_plugin_behaviour?(plugin_module) do
      metadata = plugin_module.metadata()
      available = plugin_module.available?()

      # Initialize if available
      if available and function_exported?(plugin_module, :initialize, 0) do
        plugin_module.initialize()
      end

      plugin = %{
        module: plugin_module,
        metadata: metadata,
        available: available,
        registered_at: DateTime.utc_now()
      }

      new_plugins = Map.put(state.plugins, metadata.id, plugin)
      {:ok, %{state | plugins: new_plugins}}
    else
      {:error, :not_a_plugin}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end
end

# SPDX-License-Identifier: AGPL-3.0-or-later
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <jonathan@hyperpolymath.io>

defmodule DNFinition.Plugins.Plugin do
  @moduledoc """
  Behaviour defining the interface for package manager plugins.

  All plugins must implement this behaviour to be registered
  with the PluginRegistry.
  """

  @doc "Return plugin metadata"
  @callback metadata() :: DNFinition.Plugins.PluginRegistry.plugin_metadata()

  @doc "Check if this plugin is available on the current system"
  @callback available?() :: boolean()

  @doc "Return the backend module for this plugin"
  @callback backend_module() :: module()

  @doc "Initialize the plugin (called after registration)"
  @callback initialize() :: :ok | {:error, term()}

  @doc "Shutdown the plugin (cleanup resources)"
  @callback shutdown() :: :ok
end

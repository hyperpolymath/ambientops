# SPDX-License-Identifier: AGPL-3.0-or-later
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <jonathan@hyperpolymath.io>

defmodule DNFinition.Plugins.GuixPlugin do
  @moduledoc """
  Built-in plugin for GNU Guix package manager.

  Guix has native generation-based transactions, providing:
  - Atomic package operations
  - Instant rollback via generation switching
  - Full transaction history
  """

  @behaviour DNFinition.Plugins.Plugin

  alias DNFinition.Backends.GuixBackend

  @impl true
  def metadata do
    %{
      id: "guix",
      name: "GNU Guix",
      version: "1.0.0",
      description: "GNU Guix functional package manager with atomic generations",
      pm_type: :guix,
      plugin_type: :builtin,
      status: :unavailable,
      priority: 90,
      capabilities: [
        :install,
        :remove,
        :upgrade,
        :search,
        :query,
        :transactions,
        :native_rollback,
        :dry_run,
        :autoremove,
        :cache_clean,
        :dependencies,
        :history
      ],
      required_commands: ["guix"],
      config_path: nil,
      has_native_recovery: true,
      preferred_snapshot: :native
    }
  end

  @impl true
  def available? do
    System.find_executable("guix") != nil
  end

  @impl true
  def backend_module do
    GuixBackend
  end

  @impl true
  def initialize do
    if available?() do
      {:ok, _} = GuixBackend.start_link()
      :ok
    else
      {:error, :not_available}
    end
  end

  @impl true
  def shutdown do
    :ok
  end
end

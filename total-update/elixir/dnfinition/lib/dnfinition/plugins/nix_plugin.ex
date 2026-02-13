# SPDX-License-Identifier: AGPL-3.0-or-later
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <jonathan@hyperpolymath.io>

defmodule DNFinition.Plugins.NixPlugin do
  @moduledoc """
  Built-in plugin for Nix package manager.

  Nix has native generation-based transactions, providing:
  - Atomic package operations
  - Instant rollback via generation switching
  - Full transaction history
  - Works on NixOS and as standalone on any Linux/macOS
  """

  @behaviour DNFinition.Plugins.Plugin

  alias DNFinition.Backends.NixBackend

  @impl true
  def metadata do
    %{
      id: "nix",
      name: if(nixos?(), do: "NixOS", else: "Nix"),
      version: "1.0.0",
      description: "Nix package manager with atomic generations",
      pm_type: :nix,
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
      required_commands: ["nix-env"],
      config_path: nil,
      has_native_recovery: true,
      preferred_snapshot: :native
    }
  end

  @impl true
  def available? do
    System.find_executable("nix-env") != nil
  end

  @impl true
  def backend_module do
    NixBackend
  end

  @impl true
  def initialize do
    if available?() do
      {:ok, _} = NixBackend.start_link()
      :ok
    else
      {:error, :not_available}
    end
  end

  @impl true
  def shutdown do
    :ok
  end

  defp nixos? do
    File.exists?("/etc/nixos/configuration.nix")
  end
end

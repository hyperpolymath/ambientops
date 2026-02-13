# SPDX-License-Identifier: AGPL-3.0-or-later
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <jonathan@hyperpolymath.io>

defmodule TotalUpdate.Application do
  @moduledoc """
  TotalUpdate OTP Application - Universal Package Update Daemon.

  ## Architecture

  ```
  TotalUpdate.Supervisor
  ├── TotalUpdate.Daemon           # Main daemon process
  ├── TotalUpdate.Scheduler        # Cron-like scheduler
  ├── TotalUpdate.Watcher          # File/package watcher
  ├── TotalUpdate.DownloadManager  # aria2 integration
  ├── TotalUpdate.StrategyEngine   # Update policies
  └── TotalUpdate.PluginManager    # Plugin discovery/loading
  ```
  """

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    Logger.info("Starting TotalUpdate daemon...")

    children = [
      # HTTP client pool for update checks
      {Finch, name: TotalUpdate.Finch},

      # Main daemon
      {TotalUpdate.Daemon, []},

      # Scheduler for periodic checks
      {TotalUpdate.Scheduler, []},

      # File/package watcher
      {TotalUpdate.Watcher, []},

      # Download manager (aria2)
      {TotalUpdate.DownloadManager, []},

      # Strategy engine
      {TotalUpdate.StrategyEngine, []},

      # Plugin manager
      {TotalUpdate.PluginManager, []}
    ]

    opts = [strategy: :one_for_one, name: TotalUpdate.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def stop(_state) do
    Logger.info("TotalUpdate daemon stopping...")
    :ok
  end
end

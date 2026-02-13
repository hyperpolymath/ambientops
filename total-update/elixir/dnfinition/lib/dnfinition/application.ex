# SPDX-License-Identifier: AGPL-3.0-or-later
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <jonathan@hyperpolymath.io>

defmodule DNFinition.Application do
  @moduledoc """
  DNFinition OTP Application.

  This application coordinates the Ada TUI process and provides
  fault-tolerant supervision for the reversibility layer.

  ## Architecture

  ```
  DNFinition.Supervisor
  ├── DNFinition.AdaWrapper         # Port to Ada TUI binary
  ├── DNFinition.SnapshotManager    # Snapshot coordination
  ├── DNFinition.TransactionLog     # Transaction logging
  └── DNFinition.Recovery           # Anti-fail recovery
  ```
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Ada TUI wrapper - managed port to the Ada binary
      {DNFinition.AdaWrapper, []},

      # Snapshot manager coordination
      {DNFinition.SnapshotManager, []},

      # Transaction logging
      {DNFinition.TransactionLog, []},

      # Recovery manager for anti-fail
      {DNFinition.Recovery, []}
    ]

    opts = [strategy: :one_for_one, name: DNFinition.Supervisor]
    Supervisor.start_link(children, opts)
  end
end

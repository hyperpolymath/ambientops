# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule ServiceAutopsy do
  @moduledoc """
  Post-mortem analysis of crashed/restarting systemd services.

  ServiceAutopsy watches for systemd service failures, collects crash
  context (journal entries, coredumps, D-Bus state, dependency graph),
  and produces structured autopsy reports conforming to
  evidence-envelope.schema.json.

  ## Quick Start

      # Get recent failures
      ServiceAutopsy.Watcher.recent_failures()

      # Manual autopsy of a specific unit
      ServiceAutopsy.Watcher.autopsy("sshd.service")

      # Query stored reports
      ServiceAutopsy.ReportStore.for_unit("sshd.service")

  ## Architecture

  - `ServiceAutopsy.Watcher` - Monitors journal for failures, tracks restart counts
  - `ServiceAutopsy.Collector` - Gathers crash context from system tools
  - `ServiceAutopsy.ReportStore` - In-memory bounded store for autopsy reports

  ## Author

  Jonathan D.A. Jewell
  """
end

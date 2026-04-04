# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule SystemObservatory.Application do
  @moduledoc """
  JuSys Application supervisor.

  Starts the observability system supervision tree.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Task supervisor for fire-and-forget VeriSimDB persistence writes.
      # Must start before the metrics store so VeriSimDB tasks have a home
      # as soon as the first metric is recorded.
      {Task.Supervisor, name: SystemObservatory.TaskSupervisor},
      # Start the metrics store (dual-writes to ring buffer + VeriSimDB)
      SystemObservatory.Metrics.Store,
      # Start the event correlator
      SystemObservatory.Correlator
    ]

    opts = [strategy: :one_for_one, name: SystemObservatory.Supervisor]
    Supervisor.start_link(children, opts)
  end
end

# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule SystemObservatory.Application do
  @moduledoc """
  JuSys Application supervisor.

  Starts the observability system supervision tree.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Start the metrics store
      SystemObservatory.Metrics.Store,
      # Start the event correlator
      SystemObservatory.Correlator
    ]

    opts = [strategy: :one_for_one, name: SystemObservatory.Supervisor]
    Supervisor.start_link(children, opts)
  end
end

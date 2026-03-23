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
      # Start the metrics store
      SystemObservatory.Metrics.Store,
      # Start the event correlator
      SystemObservatory.Correlator,
      # Start NVMe health sentinel (polls SMART data, feeds metrics store)
      {SystemObservatory.NvmeSentinel, nvme_sentinel_opts()}
    ]

    opts = [strategy: :one_for_one, name: SystemObservatory.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # NVMe sentinel configuration from application env or defaults.
  # Set `config :system_observatory, :nvme_sentinel, enabled: false` to disable.
  defp nvme_sentinel_opts do
    Application.get_env(:system_observatory, :nvme_sentinel, [])
  end
end

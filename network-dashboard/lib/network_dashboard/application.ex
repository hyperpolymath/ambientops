# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule NetworkDashboard.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      NetworkDashboardWeb.Endpoint,
      {NetworkDashboard.ModulePoller, interval: :timer.seconds(10)}
    ]

    opts = [strategy: :one_for_one, name: NetworkDashboard.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    NetworkDashboardWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end

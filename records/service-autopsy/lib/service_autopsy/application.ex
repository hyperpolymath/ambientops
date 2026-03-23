# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule ServiceAutopsy.Application do
  @moduledoc """
  OTP Application supervisor for ServiceAutopsy.

  Starts the service failure watcher and autopsy report store.

  ## Author

  Jonathan D.A. Jewell
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Stores completed autopsy reports in memory
      ServiceAutopsy.ReportStore,
      # Watches for systemd service failures via journal
      ServiceAutopsy.Watcher
    ]

    opts = [strategy: :one_for_one, name: ServiceAutopsy.Supervisor]
    Supervisor.start_link(children, opts)
  end
end

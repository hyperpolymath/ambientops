# SPDX-License-Identifier: PMPL-1.0-or-later

import Config

config :network_dashboard, NetworkDashboardWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [formats: [html: NetworkDashboardWeb.ErrorHTML], layout: false],
  pubsub_server: NetworkDashboard.PubSub,
  live_view: [signing_salt: "flatracoon"]

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"

# SPDX-License-Identifier: PMPL-1.0-or-later

import Config

config :network_dashboard, NetworkDashboardWeb.Endpoint,
  url: [host: System.get_env("PHX_HOST") || "localhost", port: 443, scheme: "https"],
  http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}, port: String.to_integer(System.get_env("PORT") || "4000")],
  secret_key_base: System.get_env("SECRET_KEY_BASE"),
  server: true

config :logger, level: :info

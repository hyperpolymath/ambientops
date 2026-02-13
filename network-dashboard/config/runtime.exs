# SPDX-License-Identifier: PMPL-1.0-or-later

import Config

if config_env() == :prod do
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise "SECRET_KEY_BASE env var is required in production"

  host = System.get_env("PHX_HOST") || "localhost"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :network_dashboard, NetworkDashboardWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}, port: port],
    secret_key_base: secret_key_base
end

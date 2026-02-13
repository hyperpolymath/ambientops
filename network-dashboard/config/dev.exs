# SPDX-License-Identifier: PMPL-1.0-or-later

import Config

config :network_dashboard, NetworkDashboardWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4001],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "dev-only-secret-key-base-flatracoon-dashboard-do-not-use-in-prod",
  watchers: []

config :logger, :console, format: "[$level] $message\n"
config :phoenix, :stacktrace_depth, 20
config :phoenix, :plug_init_mode, :runtime

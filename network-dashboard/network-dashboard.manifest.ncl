# SPDX-License-Identifier: PMPL-1.0-or-later
# network-dashboard module manifest for FlatRacoon orchestrator

{
  name = "network-dashboard",
  version = "0.1.0",
  layer = 'observability,
  description = "Phoenix LiveView dashboard for FlatRacoon module status and network observability",
  repo = "github.com/hyperpolymath/network-dashboard",
  requires = ["kubernetes", "poly-observability-mcp"],
  provides = ["dashboard", "module-status", "network-visualization"],
  config_schema = "configs/schema.ncl",
  health_endpoint = "/health",
  metrics_endpoint = "/metrics",
  deployment_mode = "kubectl",
  namespace = "flatracoon-dashboard",
}

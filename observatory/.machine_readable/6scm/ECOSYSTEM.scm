; SPDX-License-Identifier: PMPL-1.0-or-later
; ECOSYSTEM.scm - Project relationship mapping

(ecosystem
  (version "1.0")
  (name "system-observatory")
  (type "satellite")
  (purpose "Observability layer - metrics, correlation, and forecasting")

  (position-in-ecosystem
    (role "observability")
    (layer "monitoring")
    (description "Systems Observatory for AmbientOps"))

  (hub
    (name "system-tools-contracts")
    (relationship "consumes")
    (contracts-used
      "system-weather.schema.json"
      "run-bundle.schema.json"
      "evidence-envelope.schema.json"
      "ambient-payload.schema.json"))

  (sibling-satellites
    (satellite "system-operating-theatre"
      (relationship "observes")
      (description "Observes theatre execution for metrics"))

    (satellite "system-emergency-room"
      (relationship "correlates")
      (description "Correlates emergency incidents with system changes"))

    (satellite "feedback-o-tron"
      (relationship "integrates")
      (description "User feedback correlates with system anomalies"))

    (satellite "personal-sysadmin"
      (relationship "ingests")
      (description "Ingests PSA diagnostics and health metrics")))

  (related-projects
    (project "ambientops"
      (relationship "parent-ecosystem")
      (description "Part of AmbientOps system tools"))

    (project "big-up"
      (relationship "ingests")
      (description "Ingests run bundles from big-up diagnostic runs")))

  (what-this-is
    "The observability layer providing:"
    "- Metrics store (time series data)"
    "- Event correlation (change timeline)"
    "- Forecasting (resource exhaustion prediction)"
    "- Dashboard (SolarWinds-like visualization)"
    "Implemented in Elixir for supervision and live updates")

  (what-this-is-not
    "NEVER source of truth - only observes"
    "Not a policy engine - that's system-operating-theatre"
    "Not an executor - only recommends, never applies changes"))

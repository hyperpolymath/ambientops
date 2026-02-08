;; SPDX-License-Identifier: PMPL-1.0-or-later
(ecosystem
  (metadata
    (version "0.1.0")
    (last-updated "2026-02-08"))
  (project
    (name "hardware-crash-team")
    (purpose "Hardware diagnostic and remediation for system stability")
    (role operating-room-crash-team))
  (position-in-ecosystem
    (parent "ambientops")
    (model "hospital")
    (location "Operating Room → Crash Team"))
  (related-projects
    (project "ambientops"
      (relationship parent)
      (description "Hospital model orchestrator - ward, emergency room, operating room, records"))
    (project "panic-attack"
      (relationship sibling-tool)
      (description "Source code static analysis. Complements hardware diagnostics with software analysis."))
    (project "verisimdb"
      (relationship data-store)
      (description "Multi-modal database. Stores hardware findings as hexads for correlation and search."))
    (project "hypatia"
      (relationship intelligence-layer)
      (description "Neurosymbolic CI/CD. Processes hardware findings through rule engine for pattern detection."))
    (project "echidnabot"
      (relationship consumer)
      (description "Proof-aware CI bot. Can verify hardware remediation claims."))
    (project "sustainabot"
      (relationship consumer)
      (description "Ecological/economic analysis. Hardware health affects sustainability metrics."))))

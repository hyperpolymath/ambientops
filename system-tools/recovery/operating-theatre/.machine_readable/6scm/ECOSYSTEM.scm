; SPDX-License-Identifier: PMPL-1.0-or-later
; ECOSYSTEM.scm - Project relationship mapping

(ecosystem
  (version "1.0")
  (name "system-operating-theatre")
  (type "satellite")
  (purpose "D-layer orchestration, policy packs, and validation hooks")

  (position-in-ecosystem
    (role "orchestration")
    (layer "D")
    (description "Drivers/Deployment/Delivery layer for system tools"))

  (hub
    (name "system-tools-contracts")
    (relationship "implements")
    (contracts-used
      "procedure-plan.schema.json"
      "pack-manifest.schema.json"
      "receipt.schema.json"))

  (sibling-satellites
    (satellite "system-emergency-room"
      (relationship "triggers")
      (description "Emergency room triggers theatre procedures"))

    (satellite "system-observatory"
      (relationship "feeds")
      (description "Theatre execution results feed into system-observatory observability")))

  (related-projects
    (project "ambientops"
      (relationship "parent-ecosystem")
      (description "Part of AmbientOps system tools"))

    (project "big-up"
      (relationship "orchestrates")
      (description "Theatre can orchestrate big-up diagnostic runs")))

  (what-this-is
    "The orchestration layer providing:"
    "- Policy pack definitions"
    "- Validation hooks for GitHub workflows"
    "- Anti-fearware documentation and policies"
    "- Claims policy enforcement"
    "- Ambient UI specifications")

  (what-this-is-not
    "Not the execution engine - that's in individual tools"
    "Not the contracts - those are in system-tools-contracts"
    "Not observability - that's system-observatory"))

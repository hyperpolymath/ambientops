; SPDX-License-Identifier: PMPL-1.0-or-later
; ECOSYSTEM.scm - Project relationship mapping

(ecosystem
  (version "1.0")
  (name "system-tools-contracts")
  (type "hub")
  (purpose "Core JSON schemas and contracts for the System Tools ecosystem")

  (position-in-ecosystem
    (role "foundation")
    (layer "contracts")
    (description "Provides shared data contracts for all system tools"))

  (satellites
    ; These repos depend on and implement contracts from this hub
    (satellite "system-operating-theatre"
      (relationship "implements")
      (role "D-layer orchestration")
      (description "Implements contracts for pack execution and policy enforcement"))

    (satellite "system-emergency-room"
      (relationship "implements")
      (role "V-layer emergency trigger")
      (description "Implements incident envelope and receipt contracts"))

    (satellite "system-observatory"
      (relationship "consumes")
      (role "observability layer")
      (description "Consumes run bundles and weather payloads for correlation"))

    (satellite "feedback-o-tron"
      (relationship "consumes")
      (role "feedback ingestion")
      (description "Consumes message intent contracts for user feedback")))

  (related-projects
    (project "ambientops"
      (relationship "parent-ecosystem")
      (description "AmbientOps is the umbrella for all system tools"))

    (project "big-up"
      (relationship "sibling-standard")
      (description "Diagnostic tool that produces evidence envelopes")))

  (what-this-is
    "A collection of JSON schemas defining contracts for:"
    "- Evidence Envelope (diagnostic results)"
    "- Procedure Plan (remediation steps)"
    "- Receipt (execution proof)"
    "- System Weather (health indicator)"
    "- Message Intent (user feedback)"
    "- Run Bundle (execution manifest)"
    "- Pack Manifest (check definitions)"
    "- Ambient Payload (dashboard state)")

  (what-this-is-not
    "Not an implementation - only contracts"
    "Not a runtime dependency - compile-time only"
    "Not a UI or CLI tool"))

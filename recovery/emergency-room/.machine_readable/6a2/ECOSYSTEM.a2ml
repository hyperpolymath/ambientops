; SPDX-License-Identifier: PMPL-1.0-or-later
; ECOSYSTEM.scm - Project relationship mapping

(ecosystem
  (version "1.0")
  (name "system-emergency-room")
  (type "satellite")
  (purpose "V-layer emergency trigger and incident bundling")

  (position-in-ecosystem
    (role "emergency-response")
    (layer "V")
    (description "Verification/Validation layer for emergency diagnostics"))

  (hub
    (name "system-tools-contracts")
    (relationship "implements")
    (contracts-used
      "evidence-envelope.schema.json"
      "receipt.schema.json"))

  (sibling-satellites
    (satellite "system-operating-theatre"
      (relationship "triggers")
      (description "Emergency room can trigger theatre procedures"))

    (satellite "system-observatory"
      (relationship "feeds")
      (description "Incident bundles feed into system-observatory for correlation")))

  (related-projects
    (project "ambientops"
      (relationship "parent-ecosystem")
      (description "Part of AmbientOps system tools"))

    (project "big-up"
      (relationship "hands-off-to")
      (description "Emergency room can hand off to big-up for deeper analysis")))

  (what-this-is
    "A tiny cross-platform emergency launcher providing:"
    "- Incident bundle creation"
    "- Safe diagnostic capture"
    "- Quick backup (opt-in)"
    "- Handoff to specialized tools"
    "Implemented in V language for minimal footprint")

  (what-this-is-not
    "Not a full diagnostic suite - that's big-up"
    "Not destructive - all operations are safe and reversible"
    "Not online-dependent - works fully offline"))

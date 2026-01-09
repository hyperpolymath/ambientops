;; SPDX-License-Identifier: AGPL-3.0-or-later
;; META.scm - Meta-level information for ambientops
;; Media-Type: application/meta+scheme

(meta
  (architecture-decisions
    ("ADR-001" "Hospital mental model"
      "Use hospital metaphor (Ward/ER/OR/Records) for UX to reduce user anxiety and provide clear navigation")
    ("ADR-002" "Umbrella + satellite architecture"
      "Umbrella repo coordinates satellites for separation of concerns; implementations in dedicated repos")
    ("ADR-003" "Evidence-first, no fearware"
      "Show measurements not hype; no inflated counts or fake urgency; trust through transparency")
    ("ADR-004" "Plan-Apply-Undo-Receipt pattern"
      "All mutations require explicit approval, produce receipts, and support undo where possible")
    ("ADR-005" "Local-first by default"
      "Privacy controls visible and simple; local-only mode fully supported without degradation"))

  (development-practices
    (code-style
      ("AsciiDoc for documentation")
      ("Guile Scheme for machine-readable state")
      ("No TypeScript/Python per RSR language policy")
      ("ReScript for any future UI components"))
    (security
      (principle "Defense in depth")
      (principle "No hardcoded secrets")
      (principle "SHA-pinned dependencies")
      (principle "SPDX license headers required"))
    (testing
      ("SCM file validation via Guile")
      ("RSR compliance validation")
      ("Documentation coverage checks"))
    (versioning "SemVer")
    (documentation "AsciiDoc primary, Markdown for GitHub compatibility")
    (branching "main for stable, feature branches for development"))

  (design-rationale
    ("Hospital model reduces anxiety"
      "System tools often scare users; hospital metaphor communicates safety, consent, and expert help")
    ("Profiles over one-size-fits-all"
      "Different users (child/general/dev/tech) need different intrusiveness and detail levels")
    ("HAT roles for guidance"
      "Role-based helpers (Coordinator/Information/Risk/Optimisation) provide focused, non-overlapping advice")
    ("Receipts build trust"
      "Every action produces a receipt; users can review, share, and undo; transparency over magic")
    ("Satellite repos for modularity"
      "Each department (Ward/ER/OR/Records) can evolve independently with clear contracts")))

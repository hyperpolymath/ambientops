;; SPDX-License-Identifier: AGPL-3.0-or-later
;; STATE.scm - Project state for ambientops
;; Media-Type: application/vnd.state+scm

(state
  (metadata
    (version "0.1.0")
    (schema-version "1.0")
    (created "2026-01-03")
    (updated "2026-01-09")
    (project "ambientops")
    (repo "github.com/hyperpolymath/ambientops"))

  (project-context
    (name "AmbientOps")
    (tagline "Cross-platform system tools for everyday users - trustworthy help without fearware")
    (tech-stack
      ("AsciiDoc" "documentation")
      ("Guile Scheme" "machine-readable state files")
      ("Justfile" "task automation")))

  (current-position
    (phase "bootstrap")
    (overall-completion 10)
    (components
      ("umbrella-repo" 90 "Docs, manifest, packaging glue")
      ("hospital-model" 80 "UX model documented")
      ("ecosystem-manifest" 50 "Structure defined, needs satellite repos")
      ("contracts" 0 "Not started - Phase 1"))
    (working-features
      ("Documentation site structure")
      ("Hospital model specification")
      ("Ecosystem manifest format")
      ("RSR compliance structure")))

  (route-to-mvp
    (milestones
      ("Phase 0 - Bootstrap" "in-progress"
        "Umbrella repo, hospital model docs, ecosystem manifest, trust principles")
      ("Phase 1 - Contracts" "planned"
        "System Weather schema, evidence envelope, receipt schema, deep-link format")
      ("Phase 2 - Ward MVP" "planned"
        "Tray app, HAT roles, theme packs, local-only mode")
      ("Phase 3 - Emergency Room MVP" "planned"
        "Incident bundle, safety posture, handoff flows")
      ("Phase 4 - Operating Room MVP" "planned"
        "Scan/Plan/Apply/Undo/Receipt flow, safe pack v0.1")
      ("Phase 5 - Ecosystem polish" "planned"
        "Cross-platform packaging, technician packs, adapters")))

  (blockers-and-issues
    (critical)
    (high
      ("Need to create satellite repos for Ward, ER, OR, Records"))
    (medium
      ("system-tools-contracts repo not yet created"))
    (low))

  (critical-next-actions
    (immediate
      ("Complete umbrella repo documentation")
      ("Define contracts for satellite repos"))
    (this-week
      ("Create system-tools-contracts repo")
      ("Draft System Weather payload schema"))
    (this-month
      ("Begin Ward MVP implementation")
      ("Establish satellite repo structure")))

  (session-history
    ("2026-01-09" "Resolved all TODOs and stubs in umbrella repo")))

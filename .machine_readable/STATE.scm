;; SPDX-License-Identifier: PMPL-1.0-or-later
;; STATE.scm - Project state for ambientops
;; Media-Type: application/vnd.state+scm

(state
  (metadata
    (version "0.2.0")
    (schema-version "1.0")
    (created "2026-01-03")
    (updated "2026-02-12")
    (project "ambientops")
    (repo "github.com/hyperpolymath/ambientops"))

  (project-context
    (name "AmbientOps")
    (tagline "Hospital-model operations framework - trustworthy system help without fearware")
    (tech-stack
      ("Rust" "clinician, hardware-crash-team, contracts-rust")
      ("V" "emergency-room")
      ("Elixir" "observatory, records/referrals")
      ("ReScript" "nafa-app UI")
      ("Deno" "contract validators, scripts")
      ("AsciiDoc" "documentation")
      ("Guile Scheme" "machine-readable state files")
      ("Justfile" "task automation")))

  (current-position
    (phase "consolidation")
    (overall-completion 35)
    (components
      ("umbrella-repo" 90 "Docs, manifest, packaging glue")
      ("hospital-model" 80 "UX model documented")
      ("ecosystem-manifest" 70 "Structure defined, satellites identified")
      ("clinician" 40 "Absorbed from personal-sysadmin, 4.4k LOC Rust")
      ("emergency-room" 35 "Absorbed from emergency-button, 1.8k LOC V")
      ("hardware-crash-team" 25 "Scanner working, analyzer stub, remediation plans")
      ("observatory" 30 "Elixir metrics, bundle ingestion, forecasting stubs")
      ("contracts" 80 "8 JSON schemas, Deno validators, Rust types")
      ("contracts-rust" 30 "Rust serde types matching JSON schemas")
      ("records-referrals" 25 "Absorbed from feedback-o-tron, bug reporting MCP")
      ("nafa-app" 10 "Shell structure only")
      ("composer" 5 "Stubs only"))
    (working-features
      ("Hospital model specification")
      ("PCI zombie device scanning (hardware-crash-team)")
      ("Remediation plan generation with undo receipts")
      ("Observatory metrics collection and bundle ingestion")
      ("Emergency button one-click stabilization")
      ("8 contract schemas with cross-validation")
      ("Clinician incident envelope intake")
      ("RSR compliance structure")))

  (route-to-mvp
    (milestones
      ("Phase 0 - Bootstrap" "mostly-complete"
        "Umbrella repo, hospital model docs, ecosystem manifest, trust principles")
      ("Phase 1 - Consolidation" "in-progress"
        "Absorb satellite repos, wire contract schemas, establish workspace")
      ("Phase 2 - Ward MVP" "planned"
        "System weather generation, ambient monitoring, theme packs")
      ("Phase 3 - Emergency Room MVP" "planned"
        "Incident bundle, safety posture, handoff to clinician")
      ("Phase 4 - Operating Room MVP" "planned"
        "Scan/Plan/Apply/Undo/Receipt flow, safe pack v0.1")
      ("Phase 5 - Ecosystem polish" "planned"
        "Cross-platform packaging, technician packs, adapters")))

  (blockers-and-issues
    (critical)
    (high
      ("Wire end-to-end flow: ER → OR → Records with contract schemas"))
    (medium
      ("Crash analyzer not yet implemented in hardware-crash-team")
      ("System weather generation not yet in observatory"))
    (low
      ("nafa-app UI not started")
      ("Composer orchestration engine is stubs only")))

  (critical-next-actions
    (immediate
      ("Wire hardware-crash-team output to contract schemas")
      ("Create contracts-rust shared crate")
      ("Implement crash analyzer"))
    (this-week
      ("System weather generation in observatory")
      ("Demo flow script: scan → envelope → plan → receipt")
      ("Update ECOSYSTEM.scm with absorbed components"))
    (this-month
      ("Ward MVP - ambient monitoring UI")
      ("Emergency Room handoff integration")))

  (session-history
    ("2026-01-09" "Resolved all TODOs and stubs in umbrella repo")
    ("2026-02-08" "Added hardware-crash-team with PCI scanning and remediation")
    ("2026-02-12" "Consolidated hospital model: absorbed clinician, emergency-room, contracts, referrals")))

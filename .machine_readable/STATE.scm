;; SPDX-License-Identifier: PMPL-1.0-or-later
;; STATE.scm - Project state for ambientops
;; Media-Type: application/vnd.state+scm

(state
  (metadata
    (version "0.3.0")
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
    (phase "leveling")
    (overall-completion 55)
    (components
      ("umbrella-repo" 90 "Docs, manifest, Justfile, unified build")
      ("hospital-model" 80 "UX model documented, data flow wired")
      ("ecosystem-manifest" 75 "Structure defined, satellites identified, schema wiring")
      ("clinician" 30 "Core tools work (process/network/disk/service/security/crisis), heavy deps feature-gated")
      ("emergency-room" 70 "1.8k LOC V, PII redaction, handoff to clinician, tests")
      ("hardware-crash-team" 60 "Scanner + real crash analyzer + remediation, contract output")
      ("observatory" 80 "Metrics, bundle ingestion, weather generation, forecasting, correlator")
      ("contracts" 80 "8 JSON schemas, Deno validators, cross-validation")
      ("contracts-rust" 80 "Serde types matching all 8 schemas, From conversions, 7 tests")
      ("records-referrals" 55 "MCP server works, multi-platform submitter")
      ("nafa-app" 25 "TEA shell, no backend connectivity")
      ("composer" 0 "RSR template only"))
    (working-features
      ("Hospital model specification and data flow")
      ("PCI zombie scanning with Evidence Envelope output (--envelope)")
      ("Crash analyzer: journalctl parsing, PCI/ACPI correlation")
      ("Remediation plans with Procedure Plan output (--procedure)")
      ("Observatory: metrics, weather generation, forecasting, correlator")
      ("Emergency room: one-click stabilization with PII redaction")
      ("8 contract schemas with Deno cross-validation")
      ("contracts-rust: serde types + From conversions for all types")
      ("Clinician: incident/envelope intake, 5 sysadmin tool modules")
      ("Records/referrals: MCP server, multi-platform bug reporting")
      ("Rust workspace: 3 crates, unified build")
      ("Justfile: build-all, test-all, check, clean")))

  (route-to-mvp
    (milestones
      ("Phase 0 - Bootstrap" "complete"
        "Umbrella repo, hospital model docs, ecosystem manifest, trust principles")
      ("Phase 1 - Consolidation" "complete"
        "Absorbed satellite repos, wired contract schemas, established workspace")
      ("Phase 1.5 - Leveling" "in-progress"
        "Balanced component development: tests, contract connectivity, build health")
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
      ("Add test suites to hardware-crash-team and records/referrals (both at 0 tests)")
      ("Wire remaining contract consumers: ER→envelope, referrals→envelope, nafa→weather"))
    (medium
      ("nafa-app needs weather endpoint and basic tests")
      ("ARCHITECTURE.adoc completely stale (describes wrong system)"))
    (low
      ("Composer orchestration engine not yet specified")
      ("4 of 8 schemas unwired (message-intent, pack-manifest, ambient-payload, run-bundle)")))

  (critical-next-actions
    (immediate
      ("Add tests to all untested components (Wave 2)")
      ("Wire contract connectivity across all departments (Wave 3)")
      ("Rewrite stale ARCHITECTURE.adoc (Wave 4)"))
    (this-week
      ("Integration test script for end-to-end validation")
      ("Composer plan documentation")
      ("Update ECOSYSTEM.scm with schema wiring info"))
    (this-month
      ("Remaining remediation strategies in hardware-crash-team")
      ("Ward MVP - nafa-app consuming SystemWeather")))

  (session-history
    ("2026-01-09" "Resolved all TODOs and stubs in umbrella repo")
    ("2026-02-08" "Added hardware-crash-team with PCI scanning and remediation")
    ("2026-02-12" "Consolidated hospital model: absorbed clinician, ER, contracts, referrals")
    ("2026-02-12" "Balanced leveling: Justfile, feature-gated clinician, fixed Python/AGPL/stale state")))

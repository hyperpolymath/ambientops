;; SPDX-License-Identifier: PMPL-1.0-or-later
;; STATE.scm - Project state for ambientops
;; Media-Type: application/vnd.state+scm

(state
  (metadata
    (version "0.3.0")
    (schema-version "1.0")
    (created "2026-01-03")
    (updated "2026-02-13")
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
      ("Deno" "contract validators, scripts, nafa-app server")
      ("AsciiDoc" "documentation")
      ("Guile Scheme" "machine-readable state files")
      ("Justfile" "task automation")))

  (current-position
    (phase "leveling-complete")
    (overall-completion 65)
    (components
      ("umbrella-repo" 90 "Docs, manifest, Justfile, unified build, integration tests")
      ("hospital-model" 85 "UX model documented, data flow wired, architecture synced")
      ("ecosystem-manifest" 80 "Structure defined, satellites identified, schema wiring documented")
      ("clinician" 55 "Core tools work, heavy deps feature-gated, 16 tests, reasoning engine")
      ("emergency-room" 75 "1.8k LOC V, PII redaction, EvidenceEnvelope producer, 9 tests")
      ("hardware-crash-team" 75 "Scanner + crash analyzer (~429 LOC) + remediation, 27 tests")
      ("observatory" 85 "Metrics, ingestion, weather, forecasting, CLI routes for envelope+weather")
      ("contracts" 80 "8 JSON schemas, Deno validators, WIRING.md, 13 test steps")
      ("contracts-rust" 80 "Serde types matching all 8 schemas, From conversions, 7 tests")
      ("records-referrals" 65 "MCP server, multi-platform submitter, envelope consumer, 8 tests")
      ("nafa-app" 50 "TEA shell, weather endpoint, domain tests, 7 tests")
      ("composer" 10 "RSR template + PLAN.md (orchestration architecture documented)"))
    (working-features
      ("Hospital model specification and data flow")
      ("PCI zombie scanning with Evidence Envelope output (--envelope)")
      ("Crash analyzer: journalctl parsing, PCI/ACPI/taint/crash correlation")
      ("Remediation plans with Procedure Plan output (--procedure)")
      ("Observatory: metrics, weather generation, forecasting, correlator")
      ("Observatory CLI: ingest-envelope, weather --output subcommands")
      ("Emergency room: one-click stabilization with PII redaction and --envelope")
      ("8 contract schemas with Deno cross-validation")
      ("contracts-rust: serde types + From conversions for all types")
      ("Clinician: incident/envelope intake, 5 sysadmin tool modules, feature-gated deps")
      ("Records/referrals: MCP server, multi-platform bug reporting, envelope consumer")
      ("Nafa-app: GET /api/weather consuming observatory output")
      ("Rust workspace: 3 crates, unified build, 50 tests")
      ("Justfile: build-all, test-all, check, clean")
      ("Contract wiring: 4 schemas wired across all departments")))

  (route-to-mvp
    (milestones
      ("Phase 0 - Bootstrap" "complete"
        "Umbrella repo, hospital model docs, ecosystem manifest, trust principles")
      ("Phase 1 - Consolidation" "complete"
        "Absorbed satellite repos, wired contract schemas, established workspace")
      ("Phase 1.5 - Leveling" "complete"
        "Balanced component development: tests, contract connectivity, build health, docs sync")
      ("Phase 2 - Ward MVP" "in-progress"
        "System weather generation, ambient monitoring, theme packs")
      ("Phase 3 - Emergency Room MVP" "planned"
        "Incident bundle, safety posture, handoff to clinician")
      ("Phase 4 - Operating Room MVP" "planned"
        "Scan/Plan/Apply/Undo/Receipt flow, safe pack v0.1")
      ("Phase 5 - Ecosystem polish" "planned"
        "Cross-platform packaging, technician packs, adapters")))

  (blockers-and-issues
    (critical)
    (high)
    (medium
      ("Remaining 5 remediation strategies in hardware-crash-team (v0.3.0)")
      ("nafa-app needs full UI build (Phase 2: Ward MVP)")
      ("Observatory pre-existing test failures in forecasting module (8 tests)"))
    (low
      ("Composer orchestration engine not yet specified beyond PLAN.md")
      ("4 of 8 schemas unwired (message-intent, pack-manifest, ambient-payload, run-bundle)")
      ("Contract test fixture: envelope test needs non-empty artifacts array")))

  (critical-next-actions
    (immediate
      ("Fix observatory forecasting test failures (8 tests)")
      ("Fix contract envelope test fixture (empty artifacts)"))
    (this-week
      ("Remaining remediation strategies in hardware-crash-team")
      ("nafa-app: connect UI to weather endpoint"))
    (this-month
      ("Ward MVP: ambient monitoring with theme packs")
      ("Composer: choose language, implement orchestration skeleton")))

  (session-history
    ("2026-01-09" "Resolved all TODOs and stubs in umbrella repo")
    ("2026-02-08" "Added hardware-crash-team with PCI scanning and remediation")
    ("2026-02-12" "Consolidated hospital model: absorbed clinician, ER, contracts, referrals")
    ("2026-02-12" "Wave 1: Justfile, feature-gated clinician, fixed Python/AGPL/stale state")
    ("2026-02-13" "Waves 2-5: 56 new tests, contract wiring (ER→envelope, obs→weather→nafa, referrals→envelope), docs sync, integration test")))

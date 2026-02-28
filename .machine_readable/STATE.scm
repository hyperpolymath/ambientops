;; SPDX-License-Identifier: PMPL-1.0-or-later
;; STATE.scm - Project state for ambientops
;; Media-Type: application/vnd.state+scm

(state
  (metadata
    (version "0.4.0")
    (schema-version "1.0")
    (created "2026-01-03")
    (updated "2026-02-28")
    (project "ambientops")
    (repo "github.com/hyperpolymath/ambientops"))

  (project-context
    (name "AmbientOps")
    (tagline "Hospital-model operations framework - trustworthy system help without fearware")
    (tech-stack
      ("Rust" "clinician, hardware-crash-team, contracts-rust")
      ("V" "emergency-room")
      ("Elixir" "observatory, records/referrals")
      ("Gleam" "composer orchestration engine")
      ("Deno" "contract validators, scripts")
      ("AsciiDoc" "documentation")
      ("Guile Scheme" "machine-readable state files")
      ("Justfile" "task automation")))

  (current-position
    (phase "deep-build")
    (overall-completion 80)
    (components
      ("umbrella-repo" 90 "Docs, manifest, Justfile, unified build, integration tests")
      ("hospital-model" 85 "UX model documented, data flow wired, architecture synced")
      ("ecosystem-manifest" 85 "Structure defined, satellites integrated, all 8 schemas typed")
      ("clinician" 78 "Core tools + satellites + gossipsub mesh + ArangoDB graph traversal behind feature gates")
      ("emergency-room" 85 "1.8k LOC V, PII redaction, diagnostics, backup, handoff, 82 test assertions")
      ("hardware-crash-team" 92 "All 6 strategies, BAR/lspci/interrupts, multi-device, TUI, SARIF output, 60 tests")
      ("observatory" 78 "Metrics, ingestion, weather, forecasting, themes, ambient payload, CLI — ABI/FFI templates not instantiated")
      ("contracts" 85 "8 JSON schemas, Deno validators, WIRING.md, 14/14 test steps")
      ("contracts-rust" 90 "Serde types matching all 8 schemas, From conversions, 15+ tests")
      ("records-referrals" 65 "MCP server, multi-platform submitter, envelope consumer, 8 tests")
      ("composer" 20 "Gleam orchestration engine: types, executor, receipts, 22 tests passing"))
    (working-features
      ("Hospital model specification and data flow")
      ("PCI zombie scanning with Evidence Envelope output (--envelope)")
      ("Crash analyzer: journalctl parsing, PCI/ACPI/taint/crash correlation")
      ("Remediation plans with Procedure Plan output (--procedure)")
      ("Observatory: metrics, weather generation, forecasting, correlator")
      ("Observatory CLI: ingest-envelope, weather --output subcommands")
      ("Emergency room: incident bundle, diagnostic capture, PII redaction, backup, handoff")
      ("Emergency room: cross-platform support (Linux/macOS/Windows conditional compilation)")
      ("8 contract schemas with Deno cross-validation")
      ("contracts-rust: serde types + From conversions for all types")
      ("Clinician: incident/envelope intake, 5 sysadmin tool modules, feature-gated deps")
      ("Records/referrals: MCP server, multi-platform bug reporting, envelope consumer")
      ("Clinician: full gossipsub pub/sub mesh with persistent peer identity")
      ("Clinician: ArangoDB graph traversal with AQL queries, 2-step find+traverse")
      ("Hardware-crash-team: SARIF 2.1.0 output with 9 rule IDs (HCT001-HCT009)")
      ("Composer: plan validation, execution lifecycle, receipt generation, risk calculation")
      ("Composer: dry-run mode, rollback eligibility, receipt summaries")
      ("Rust workspace: 3 crates, unified build, 145+ tests")
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
      ("Phase 2 - Ward MVP" "complete"
        "System weather generation, ambient monitoring, theme packs, observatory fully functional")
      ("Phase 3 - Emergency Room MVP" "complete"
        "Incident bundle, diagnostic capture, PII redaction, backup, handoff, 82 tests")
      ("Phase 4 - Operating Room MVP" "in-progress"
        "Composer orchestration skeleton done (Gleam, 22 tests), needs CLI + integrations")
      ("Phase 5 - Ecosystem polish" "planned"
        "Cross-platform packaging, technician packs, adapters")))

  (blockers-and-issues
    (critical)
    (high
      ("Composer needs CLI and component integrations to complete Phase 4"))
    (medium
      ("Observatory ABI/FFI templates not instantiated ({{PROJECT}} placeholders)"))
    (low
      ("Consider VeriSimDB/Hypatia integration for hardware-crash-team")))

  (critical-next-actions
    (immediate
      ("Composer: add JSON codec for ProcedurePlan and Receipt serialization")
      ("Composer: wire HCT/clinician CLI integration"))
    (this-week
      ("Composer: implement CLI with orchestrate, dry-run, rollback, status commands")
      ("Composer: add OTP supervision tree for parallel step execution"))
    (this-month
      ("Composer: implement run-bundle packaging for Observatory ingestion")
      ("Integration test script end-to-end (./scripts/integration-test.sh)")
      ("Codeberg + Bitbucket mirroring for ambientops")))

  (session-history
    ("2026-01-09" "Resolved all TODOs and stubs in umbrella repo")
    ("2026-02-08" "Added hardware-crash-team with PCI scanning and remediation")
    ("2026-02-12" "Consolidated hospital model: absorbed clinician, ER, contracts, referrals")
    ("2026-02-12" "Wave 1: Justfile, feature-gated clinician, fixed Python/AGPL/stale state")
    ("2026-02-13" "Waves 2-5: 56 new tests, contract wiring, docs sync, integration test")
    ("2026-02-13" "Deep build: 62+ new tests, all 6 strategies, BAR/lspci/interrupts, TUI, themes, ambient")
    ("2026-02-13" "SARIF output, gossipsub mesh, ArangoDB graph traversal")
    ("2026-02-28" "HAR round-trip tests (72 new, 892 total), security manager tests (83 new, 820 total)")
    ("2026-02-28" "Updated observatory STATE.scm (0%→78%), emergency-room STATE.scm (0%→85%)")
    ("2026-02-28" "Scaffolded Composer Gleam orchestration engine (types, executor, receipts, 22 tests)")
    ("2026-02-28" "Fixed emergency-room v.mod license AGPL→PMPL")))

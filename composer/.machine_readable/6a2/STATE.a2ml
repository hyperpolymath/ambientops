;; SPDX-License-Identifier: PMPL-1.0-or-later
;; STATE.scm - Project state for composer
;; Media-Type: application/vnd.state+scm

(state
  (metadata
    (version "0.1.0")
    (schema-version "1.0")
    (created "2026-01-03")
    (updated "2026-02-28")
    (project "composer")
    (repo "github.com/hyperpolymath/ambientops"))

  (project-context
    (name "composer")
    (tagline "Orchestration engine for AmbientOps multi-step procedures")
    (tech-stack (gleam otp beam)))

  (current-position
    (phase "initial-implementation")
    (overall-completion 20)
    (components
      (types 90 "Core types mirroring procedure-plan, receipt, run-bundle contracts")
      (orchestrator 60 "Plan validation, execution lifecycle, step advancement, receipt generation")
      (rollback 30 "Rollback eligibility check — undo execution not yet implemented")
      (cli 0 "CLI interface not yet implemented")
      (http-api 0 "HTTP API not yet implemented")
      (hct-integration 0 "HCT scan/plan consumption not yet wired")
      (clinician-integration 0 "Clinician delegation not yet wired")
      (observatory-integration 0 "Receipt/bundle emission not yet wired")
      (tests 80 "26 tests covering validation, execution, receipts, risk, rollback"))
    (working-features
      ("Gleam type definitions mirroring all 3 contract schemas")
      ("Plan validation (empty plan rejection, sequential ordering check)")
      ("Execution lifecycle (begin, advance, complete, fail)")
      ("Dry-run mode (preview without mutations)")
      ("Step-level result tracking (success, failed, skipped, rolled_back)")
      ("Receipt generation with accurate counts")
      ("Overall risk calculation (safe/guided/expert propagation)")
      ("Rollback eligibility checking")
      ("Human-readable receipt summary formatting")))

  (route-to-mvp
    (milestones
      (v0.1 "Core types + orchestrator skeleton" 90)
      (v0.5 "CLI + HCT/clinician integration" 0)
      (v1.0 "Full orchestration with rollback + run bundles" 0)
      (v1.5 "HTTP API + visual macro builder" 0)))

  (blockers-and-issues
    (critical)
    (high
      ("No CLI or HTTP interface yet — orchestrator is library-only"))
    (medium
      ("Rollback execution not implemented (only eligibility check)")
      ("No JSON codec for contract serialization/deserialization"))
    (low
      ("Visual macro builder is Phase 2+")))

  (critical-next-actions
    (immediate
      ("Add JSON codec module for ProcedurePlan and Receipt encoding/decoding")
      ("Wire HCT integration — spawn v build/run for scans"))
    (this-week
      ("Implement CLI with orchestrate, dry-run, rollback, status commands")
      ("Add OTP supervision tree for parallel step execution"))
    (this-month
      ("Implement run-bundle packaging for Observatory ingestion")
      ("Add Observatory integration via ingest-envelope CLI")))

  (session-history
    (session
      (date "2026-02-28")
      (focus "Initial Gleam project scaffolding and core orchestrator")
      (completed
        ("Created gleam.toml with gleam_stdlib, gleam_json, gleam_erlang, gleam_otp deps")
        ("Created types.gleam — 12 types mirroring 3 contract schemas (procedure-plan, receipt, run-bundle)")
        ("Created composer.gleam — 7 public functions: validate_plan, begin_execution, begin_dry_run, advance, generate_receipt, can_rollback, overall_risk, receipt_summary")
        ("Created composer_test.gleam — 26 tests covering validation, execution lifecycle, receipts, risk calculation, rollback eligibility")
        ("Created .machine_readable/STATE.scm"))
      (notes
        ("Types mirror JSON Schema contracts exactly — all enum values, field names, optionality match")
        ("Execution is immutable — each advance creates new Execution value (functional style)")
        ("Gleam 1.14.0 on BEAM target — ready for OTP supervision trees in next phase")))))

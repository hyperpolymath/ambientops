;; SPDX-License-Identifier: PMPL-1.0-or-later
;; STATE.scm - Project state for system-emergency-room
;; Media-Type: application/vnd.state+scm

(state
  (metadata
    (version "0.1.0")
    (schema-version "1.0")
    (created "2026-01-03")
    (updated "2026-02-28")
    (project "system-emergency-room")
    (repo "github.com/hyperpolymath/system-emergency-room"))

  (project-context
    (name "system-emergency-room")
    (tagline "Panic-safe intake and triage for system emergencies")
    (tech-stack (v-lang)))

  (current-position
    (phase "mvp-ready")
    (overall-completion 85)
    (components
      (incident-bundle 100 "Incident ID generation, correlation IDs, metadata envelope, platform detection, receipt generation")
      (diagnostic-capture 100 "6 capture modules: OS version, uptime, disk, memory, network, process — cross-platform")
      (pii-redaction 100 "Comprehensive PII engine: passwords, AWS/GitHub tokens, SSN, email, private keys")
      (quick-backup 100 "Path validation, directory scanning with depth limit, cross-platform copy, result logging")
      (handoff 100 "Tool detection (psa, big-up), path safety validation, correlation ID passing, tool spawning")
      (cli 100 "Flag parsing, dry-run mode, verbose output, color-coded terminal UI, full workflow orchestration")
      (utilities 100 "Atomic writes (temp+rename), structured logging (key=value), log levels")
      (tests 100 "3 test suites, 82 assertions — all passing")
      (stabilisation 0 "Disk/memory/process/network emergency fixes — not yet implemented")
      (interactive-input 0 "Human description prompts, guided fix dialogs — not yet implemented"))
    (working-features
      ("Incident bundle creation with nanosecond+random collision-resistant IDs")
      ("Correlation ID generation for cross-tool tracing")
      ("Platform detection (OS, arch, kernel version) via conditional compilation")
      ("AsciiDoc receipt generation")
      ("Atomic JSON writing with temp+rename pattern")
      ("Safe diagnostic capture — OS, uptime, disk, memory, network, process")
      ("PII redaction engine — passwords, tokens, SSN, email, private keys")
      ("Quick backup to external storage with path injection prevention (CRIT-002)")
      ("Cross-tool handoff with path safety validation (CRIT-001)")
      ("Tool detection for psa and big-up in PATH")
      ("CLI with --quick-backup, --dry-run, --verbose flags")
      ("Dry-run preview mode for all operations")
      ("Atomic file writes prevent corruption on crash")
      ("Structured key=value logging with log levels")
      ("Cross-platform support (Linux, macOS, Windows via $if conditional compilation)")
      ("Zero external dependencies — standard library only")
      ("All 82 test assertions passing")))

  (route-to-mvp
    (milestones
      (v0.1 "Incident intake + diagnostic capture" 100)
      (v0.5 "PII redaction + backup + handoff" 100)
      (v1.0 "Stabilisation features (disk/memory/process/network)" 0)
      (v1.5 "Interactive human input + guided fixes" 0)))

  (blockers-and-issues
    (critical)
    (high)
    (medium
      ("Stabilisation/fix capabilities not yet implemented — capture-only for now")
      ("justfile has placeholder recipes, no actual build targets"))
    (low
      ("README claims 'Specification Pending' — stale, implementation is substantial")
      ("License mismatch: v.mod says AGPL-3.0, should be PMPL-1.0-or-later")))

  (critical-next-actions
    (immediate
      ("Fix license in v.mod from AGPL-3.0-or-later to PMPL-1.0-or-later")
      ("Update README to reflect actual implementation status"))
    (this-week
      ("Implement disk emergency stabilisation (space consumers, cache clearing)")
      ("Implement memory emergency stabilisation (hog identification, reduction guidance)"))
    (this-month
      ("Implement process emergency calm-down plans (nice/ionice suggestions)")
      ("Add interactive human description prompts")
      ("Populate justfile with actual build recipes")))

  (session-history
    (session
      (date "2026-02-28")
      (focus "STATE.scm audit — update from empty stub to reflect actual implementation")
      (completed
        ("Audited all 9 V-lang source files (1,840 LOC)")
        ("Verified all 3 test suites pass (82 assertions, 0 failures)")
        ("Updated STATE.scm from 0% stub to 85% actual completion")
        ("Documented all 10 components with accurate status")
        ("Identified license mismatch (AGPL vs PMPL) in v.mod"))
      (notes
        ("V 0.5.0 compatible — all tests compile and pass cleanly")
        ("Zero external dependencies — entirely V standard library")
        ("Cross-platform via $if conditional compilation (Linux, macOS, Windows)")
        ("String-based PII matching (V regex lacks PCRE lookaheads)")
        ("Defensive error handling on every fallible operation")))))

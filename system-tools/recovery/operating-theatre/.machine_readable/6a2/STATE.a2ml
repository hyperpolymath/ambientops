;; SPDX-License-Identifier: PMPL-1.0-or-later
;; STATE.scm - Current project state

(define project-state
  `((metadata
      ((version . "1.1.0")
       (schema-version . "1")
       (created . "2026-01-03T04:00:00+00:00")
       (updated . "2026-01-03T04:00:00+00:00")
       (project . "System Operating Theatre")
       (repo . "system-operating-theatre")))
    (current-position
      ((phase . "phase-1")
       (overall-completion . 35)
       (components
         ((infrastructure . ((status . complete) (completion . 100)))
          (validation-hooks . ((status . complete) (completion . 100)))
          (documentation . ((status . complete) (completion . 100)))
          (specifications . ((status . in-progress) (completion . 20)))
          (core-cli . ((status . not-started) (completion . 0)))
          (plan-engine . ((status . not-started) (completion . 0)))
          (pack-system . ((status . not-started) (completion . 0)))))
       (working-features
         ("Multi-forge mirroring (GitHub → GitLab, Codeberg, Bitbucket)"
          "Validation hooks (CodeQL, SHA-pins, SPDX, permissions)"
          "Anti-fearware documentation and policy"
          "Claims policy enforcement docs"
          "Ambient UI specification"
          "Pack and modes documentation"))))
    (route-to-mvp
      ((milestones
        ((phase-0-infrastructure
           ((status . complete)
            (items
              ("Multi-forge mirroring"
               "Instant-sync automation"
               "Governance policy"
               "Initial repo structure"))))
         (phase-1-specifications
           ((status . in-progress)
            (items
              (("Feature specifications" . pending)
               ("CLI interface definitions" . pending)
               ("Security model" . pending)
               ("Evidence formats" . pending)
               ("Pack system spec" . pending)
               ("Ecosystem seam files" . complete)))))
         (phase-2-mvp
           ((status . not-started)
            (items
              ("Core CLI (detect, scan, plan, apply, undo, receipt)"
               "Plan engine with preview and reversibility"
               "Apply runner with logging"
               "Undo system with tokens"
               "Receipt generator"
               "First safe pack"))))))))
    (blockers-and-issues . ())
    (critical-next-actions
      ((immediate
         ("Tag v1.1.0 release"))
       (this-week
         ("Define CLI interface for core verbs"
          "Document security model"))
       (this-month
         ("Define evidence formats"
          "Start core CLI implementation"))))))

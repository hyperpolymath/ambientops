;; SPDX-License-Identifier: MPL-2.0-or-later
;; AGENTIC.scm - Agent interaction patterns for nerdsafe-restart
;; Media-Type: application/vnd.agentic+scm

(agentic
 (version "1.0")
 (project "nerdsafe-restart")

 (agent-capabilities
  (can-invoke
   (nerdsafe-restart-check
    (description "Run validation at specified level")
    (command "nerdsafe-restart.sh check --level LEVEL")
    (levels quick standard thorough paranoid)
    (exit-codes
     (0 "All validations passed")
     (1 "Syntax errors found")
     (2 "Timeout exceeded")
     (3 "ShellCheck warnings")))

   (nerdsafe-restart-simulate
    (description "Full container simulation")
    (command "nerdsafe-restart.sh simulate")
    (requires "nerdctl or podman"))

   (run-constrained
    (description "Run with system-matched resources")
    (command "run-constrained.sh ARGS")
    (auto-detects "memory cpu swap pids"))

   (bootstrap-check
    (description "Analyze critical components")
    (command "bootstrap-check.sh [HOME_DIR]")))

  (cannot-do
   "Actual system reboot"
   "Kernel boot emulation"
   "Hardware driver testing"
   "SELinux policy enforcement"))

 (agent-workflows
  (pre-commit-validation
   (trigger "Before committing shell config changes")
   (steps
    (step 1 "Run nerdsafe-restart check --level quick")
    (step 2 "If warnings, run --level standard")
    (step 3 "If pass, allow commit")
    (step 4 "If fail, report errors"))
   (exit-on-failure true))

  (pre-reboot-check
   (trigger "Before system reboot")
   (steps
    (step 1 "Run bootstrap-check.sh")
    (step 2 "Run nerdsafe-restart check --level thorough")
    (step 3 "If pass, safe to reboot")
    (step 4 "If fail, investigate before reboot"))
   (exit-on-failure true))

  (ci-integration
   (trigger "Pull request to shell config repo")
   (steps
    (step 1 "Build container image")
    (step 2 "Run nerdsafe-restart check --level standard")
    (step 3 "Report results in PR")
    (step 4 "Block merge on failure"))
   (exit-on-failure true)))

 (agent-context
  (when-to-use
   "After modifying .bashrc or .bashrc.d/* files"
   "Before rebooting after config changes"
   "When debugging shell startup issues"
   "In CI pipelines for shell config repos")

  (when-not-to-use
   "For bootloader configuration changes"
   "For kernel parameter changes"
   "For systemd service changes"
   "For network configuration changes"))

 (machine-readable-outputs
  (json-report
   (description "Structured validation results")
   (format "JSON")
   (fields "status" "errors" "warnings" "duration"))

  (exit-codes
   (description "Process exit codes for scripting")
   (values
    (0 success)
    (1 syntax-error)
    (2 timeout)
    (3 shellcheck-warning)
    (4 missing-file)
    (5 permission-error)
    (10 container-error)
    (11 resource-detection-error)))))

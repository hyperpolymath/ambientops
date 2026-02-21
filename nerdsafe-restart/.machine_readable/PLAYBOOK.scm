;; SPDX-License-Identifier: MPL-2.0-or-later
;; PLAYBOOK.scm - Operational playbooks for nerdsafe-restart
;; Media-Type: application/vnd.playbook+scm

(playbook
 (version "1.0")
 (project "nerdsafe-restart")

 (runbooks
  (runbook validate-before-reboot
   (name "Pre-Reboot Validation")
   (description "Validate shell configuration before rebooting")
   (trigger manual)
   (steps
    (step 1
     (action "Run quick syntax check")
     (command "nerdsafe-restart.sh check --level quick")
     (expected-exit 0)
     (on-failure "Fix syntax errors before proceeding"))
    (step 2
     (action "Run thorough validation")
     (command "nerdsafe-restart.sh check --level thorough")
     (expected-exit 0)
     (on-failure "Investigate warnings"))
    (step 3
     (action "Review any warnings")
     (command "Check output for non-fatal issues")
     (decision "Proceed or investigate"))
    (step 4
     (action "Reboot if all checks pass")
     (command "systemctl reboot")
     (requires "All previous steps passed"))))

  (runbook ci-validation
   (name "CI Pipeline Validation")
   (description "Validate shell configs in CI")
   (trigger pull-request)
   (steps
    (step 1
     (action "Checkout repository")
     (command "git checkout $PR_BRANCH"))
    (step 2
     (action "Build validation container")
     (command "nerdctl build -t nerdsafe:ci -f Containerfile.kinoite ."))
    (step 3
     (action "Run validation")
     (command "nerdsafe-restart.sh check --level standard")
     (expected-exit 0)
     (on-failure "Block PR merge"))
    (step 4
     (action "Post results")
     (command "gh pr comment with results"))))

  (runbook recover-broken-shell
   (name "Recovery from Broken Shell Config")
   (description "Steps to recover if shell config breaks")
   (trigger emergency)
   (steps
    (step 1
     (action "Boot to rescue mode or use TTY")
     (command "Ctrl+Alt+F3 for TTY"))
    (step 2
     (action "Login with sh as shell")
     (command "Execute: /bin/sh"))
    (step 3
     (action "Backup broken config")
     (command "cp ~/.bashrc ~/.bashrc.broken"))
    (step 4
     (action "Restore minimal config")
     (command "cp /etc/skel/.bashrc ~/.bashrc"))
    (step 5
     (action "Test shell")
     (command "bash --login"))
    (step 6
     (action "Gradually restore modules")
     (command "Source each module file individually to find culprit"))))

  (runbook debug-startup-issue
   (name "Debug Shell Startup Issue")
   (description "Systematically debug startup problems")
   (trigger manual)
   (steps
    (step 1
     (action "Enable verbose startup")
     (command "bash -x --login 2>&1 | head -100"))
    (step 2
     (action "Check specific file syntax")
     (command "bash -n ~/.bashrc.d/*/FILE"))
    (step 3
     (action "Run ShellCheck")
     (command "shellcheck ~/.bashrc ~/.bashrc.d/*/*"))
    (step 4
     (action "Check file permissions")
     (command "stat -c '%a %n' ~/.bashrc ~/.bashrc.d/*/*"))
    (step 5
     (action "Verify commands exist")
     (command "command -v TOOL")))))

 (troubleshooting
  (issue syntax-error-on-startup
   (symptoms
    "Shell exits immediately"
    "Error: unexpected EOF"
    "Error: syntax error near...")
   (diagnosis
    (step 1 "Run: bash -n ~/.bashrc")
    (step 2 "Check line number in error")
    (step 3 "Look for unmatched quotes, brackets"))
   (resolution
    (step 1 "Edit file to fix syntax")
    (step 2 "Re-run bash -n to verify")
    (step 3 "Run nerdsafe-restart check")))

  (issue command-not-found
   (symptoms
    "starship: command not found"
    "asdf: command not found"
    "Error during tool init")
   (diagnosis
    (step 1 "Check if tool installed: which TOOL")
    (step 2 "Check PATH: echo $PATH")
    (step 3 "Check if asdf plugin installed"))
   (resolution
    (step 1 "Install missing tool")
    (step 2 "Or: Guard init with 'command -v TOOL && ...'")
    (step 3 "Run nerdsafe-restart to verify")))

  (issue slow-startup
   (symptoms
    "Shell takes > 5 seconds to start"
    "Visible delay before prompt")
   (diagnosis
    (step 1 "Time startup: time bash -i -c exit")
    (step 2 "Profile with: bash -x --login 2>&1 | ts")
    (step 3 "Find slow commands"))
   (resolution
    (step 1 "Lazy-load slow tools")
    (step 2 "Cache expensive operations")
    (step 3 "Remove unnecessary modules")))

  (issue permission-denied
   (symptoms
    "Permission denied on source"
    "Cannot read config file")
   (diagnosis
    (step 1 "Check permissions: ls -la ~/.bashrc*")
    (step 2 "Files should be 644")
    (step 3 "Directories should be 755"))
   (resolution
    (step 1 "Fix permissions: chmod 644 ~/.bashrc")
    (step 2 "Fix directory: chmod 755 ~/.bashrc.d")
    (step 3 "Run nerdsafe-restart to verify"))))

 (maintenance
  (task weekly-validation
   (schedule "0 9 * * MON")
   (action "Run thorough validation")
   (command "nerdsafe-restart.sh check --level thorough"))

  (task monthly-container-rebuild
   (schedule "0 9 1 * *")
   (action "Rebuild container with latest packages")
   (command "nerdctl build --no-cache -t nerdsafe-restart:latest -f Containerfile.kinoite ."))

  (task quarterly-fidelity-review
   (schedule "0 9 1 */3 *")
   (action "Review emulation gaps")
   (command "Compare EMULATION-SCOPE.adoc with actual failures"))))

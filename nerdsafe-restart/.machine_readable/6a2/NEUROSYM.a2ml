;; SPDX-License-Identifier: MPL-2.0-or-later
;; NEUROSYM.scm - Neurosymbolic reasoning patterns for nerdsafe-restart
;; Media-Type: application/vnd.neurosym+scm

(neurosym
 (version "1.0")
 (project "nerdsafe-restart")

 (symbolic-reasoning
  (domain-axioms
   (axiom shell-startup-order
    (description "Bash startup files are sourced in specific order")
    (formal "/etc/profile -> ~/.bash_profile -> ~/.bashrc -> modules")
    (implications "Order matters for PATH and variable inheritance"))

   (axiom syntax-before-semantic
    (description "Syntax errors prevent execution")
    (formal "parse_error(file) -> NOT executable(file)")
    (implications "Syntax validation catches fatal errors early"))

   (axiom path-order-precedence
    (description "Earlier PATH entries take precedence")
    (formal "PATH=A:B -> lookup(cmd) in A before B")
    (implications "Duplicate entries waste lookup time"))

   (axiom permission-inheritance
    (description "Source files must be readable")
    (formal "source(file) requires read_permission(file)")
    (implications "Permission errors prevent module loading")))

  (inference-rules
   (rule syntax-propagation
    (if "syntax_error(module)")
    (then "startup_fails")
    (confidence 1.0))

   (rule missing-command
    (if "config_references(cmd) AND NOT command_exists(cmd)")
    (then "potential_error")
    (confidence 0.8))

   (rule path-conflict
    (if "path_contains(A) AND path_contains(B) AND provides_same_command(A, B)")
    (then "shadowing_risk")
    (confidence 0.6))))

 (neural-patterns
  (pattern-recognition
   (common-errors
    (unmatched-quotes
     (description "Missing closing quote in shell config")
     (detection "bash -n reports 'unexpected EOF'")
     (frequency high))
    (missing-fi
     (description "Unclosed if statement")
     (detection "bash -n reports 'syntax error: unexpected end of file'")
     (frequency medium))
    (bad-variable-expansion
     (description "Unquoted variable with spaces")
     (detection "ShellCheck SC2086")
     (frequency high))
    (command-not-found
     (description "Reference to non-existent command")
     (detection "type command fails")
     (frequency medium))))

  (learned-heuristics
   (heuristic tool-init-patterns
    (description "Common tool initialization patterns")
    (examples
     "eval \"$(starship init bash)\""
     "eval \"$(direnv hook bash)\""
     "eval \"$(zoxide init bash)\"")
    (validation "Check tool exists before eval"))

   (heuristic path-patterns
    (description "Common PATH modification patterns")
    (examples
     "PATH=\"$HOME/.local/bin:$PATH\""
     "export PATH=\"$HOME/.cargo/bin:$PATH\"")
    (validation "Check directory exists"))))

 (hybrid-reasoning
  (validation-strategy
   (phase symbolic-first
    (description "Apply formal syntax rules")
    (tools "bash -n" "ShellCheck")
    (catches "Parse errors, style issues, potential bugs"))

   (phase pattern-matching
    (description "Apply learned patterns")
    (tools "Custom analyzers")
    (catches "Common mistakes, anti-patterns"))

   (phase semantic-simulation
    (description "Actually run in container")
    (tools "Container with bash --login")
    (catches "Runtime issues, environment problems")))

  (confidence-aggregation
   (formula "final = (syntax * 1.0) * (patterns * 0.8) * (simulation * 0.95)")
   (threshold 0.93)
   (interpretation "93% confidence means safe to reboot"))))

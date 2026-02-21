# SPDX-License-Identifier: MIT OR AGPL-3.0-or-later
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <hyperpolymath>
#
# Must Configuration for nick-shells
# ===================================
# Type-safe deployment configuration following hyperpolymath/mustfile conventions.
# Integrates with Just via hyperpolymath/must-just-nickel patterns.
#
# Usage:
#   nickel typecheck must.ncl   # Validate configuration
#   nickel export must.ncl      # Export to JSON
#
# Requires Nickel >= 1.5.0

# Version requirements
let NickelVersion = {
  minimum | String | doc "Minimum required Nickel version" = "1.5.0",
  recommended | String | doc "Tested and known-good version" = "1.9.0",
} in

# Physical state contract for shell modules
let ShellModule = {
  name | String | doc "Module filename without extension",
  path | String | doc "Relative path from repository root",
  description | String | doc "Brief description of module purpose",
  dependencies | Array String | default = [] | doc "Other modules this depends on",
  shell_compat | Array String | default = ["bash", "zsh", "sh"] | doc "Compatible shells",
} in

# Task definition contract
let Task = {
  name | String | doc "Task identifier",
  description | String | doc "Human-readable description",
  command | String | doc "Shell command to execute",
  dependencies | Array String | default = [] | doc "Tasks that must run first",
  inputs | Array String | default = [] | doc "Input files (for change detection)",
  outputs | Array String | default = [] | doc "Output files produced",
} in

# Project configuration
let ProjectConfig = {
  name | String,
  version | String,
  nickel | NickelVersion,
  modules | Array ShellModule,
  tasks | Array Task,
} in

# nick-shells configuration
{
  name = "nick-shells",
  version = "0.1.0",

  nickel = {
    minimum = "1.5.0",
    recommended = "1.9.0",
  },

  modules = [
    {
      name = "security",
      path = "shell/modules/security.sh",
      description = "Security hardening: umask, core dumps, safety aliases",
      dependencies = [],
      shell_compat = ["bash", "zsh", "sh"],
    },
    {
      name = "xdg",
      path = "shell/modules/xdg.sh",
      description = "XDG Base Directory environment variables",
      dependencies = [],
      shell_compat = ["bash", "zsh", "sh"],
    },
    {
      name = "locale",
      path = "shell/modules/locale.sh",
      description = "UTF-8 locale defaults",
      dependencies = [],
      shell_compat = ["bash", "zsh", "sh"],
    },
    {
      name = "history",
      path = "shell/modules/history.sh",
      description = "History configuration with timestamps",
      dependencies = [],
      shell_compat = ["bash"],
    },
    {
      name = "behavior",
      path = "shell/modules/behavior.sh",
      description = "Shell behavior options (shopt)",
      dependencies = [],
      shell_compat = ["bash"],
    },
    {
      name = "aliases",
      path = "shell/modules/aliases.sh",
      description = "Common navigation and listing aliases",
      dependencies = [],
      shell_compat = ["bash", "zsh", "sh"],
    },
    {
      name = "path",
      path = "shell/modules/path.sh",
      description = "RSR-compliant PATH configuration",
      dependencies = [],
      shell_compat = ["bash", "zsh", "sh"],
    },
    {
      name = "editor",
      path = "shell/modules/editor.sh",
      description = "Editor and pager configuration",
      dependencies = [],
      shell_compat = ["bash", "zsh", "sh"],
    },
    {
      name = "dev",
      path = "shell/modules/dev.sh",
      description = "Development environment variables",
      dependencies = ["xdg"],
      shell_compat = ["bash", "zsh", "sh"],
    },
    {
      name = "prompt",
      path = "shell/modules/prompt.sh",
      description = "Informative prompt with exit code display",
      dependencies = [],
      shell_compat = ["bash", "zsh"],
    },
  ],

  tasks = [
    {
      name = "test",
      description = "Run shellcheck on all modules",
      command = "shellcheck --shell=bash --severity=warning shell/modules/*.sh shell/examples/*.sh shell/baseline.sh",
      dependencies = [],
      inputs = ["shell/modules/*.sh", "shell/examples/*.sh", "shell/baseline.sh"],
      outputs = [],
    },
    {
      name = "fmt",
      description = "Format shell scripts with shfmt",
      command = "shfmt -w -i 4 -ci -bn shell/modules/*.sh shell/examples/*.sh shell/baseline.sh shell/apply.sh",
      dependencies = [],
      inputs = ["shell/modules/*.sh", "shell/examples/*.sh", "shell/baseline.sh", "shell/apply.sh"],
      outputs = ["shell/modules/*.sh", "shell/examples/*.sh", "shell/baseline.sh", "shell/apply.sh"],
    },
    {
      name = "lint",
      description = "Run all linters",
      command = "just lint",
      dependencies = ["test"],
      inputs = [],
      outputs = [],
    },
    {
      name = "build",
      description = "Export Nickel configs to JSON",
      command = "mkdir -p build && nickel export shell/config.ncl > build/config.json && nickel export must.ncl > build/must.json",
      dependencies = [],
      inputs = ["shell/config.ncl", "must.ncl"],
      outputs = ["build/config.json", "build/must.json"],
    },
    {
      name = "install",
      description = "Install baseline configuration",
      command = "shell/apply.sh --install",
      dependencies = ["test"],
      inputs = ["shell/baseline.sh", "shell/modules/*.sh"],
      outputs = [],
    },
    {
      name = "clean",
      description = "Remove generated files",
      command = "rm -rf build/ config.json must.json",
      dependencies = [],
      inputs = [],
      outputs = [],
    },
  ],
} | ProjectConfig

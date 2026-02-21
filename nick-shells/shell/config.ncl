# SPDX-License-Identifier: MIT OR AGPL-3.0-or-later
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <hyperpolymath>
#
# Shell Configuration Schema (Nickel)
# ====================================
# Type-safe configuration for nick-shells.
# Requires Nickel >= 1.5.0
#
# Usage:
#   nickel export config.ncl > config.json
#   nickel typecheck config.ncl

let Version = {
  minimum | String | doc "Minimum required version",
  recommended | String | doc "Tested and known-good version",
  maximum | String | optional | doc "Upper bound (if any)",
} in

let ModuleConfig = {
  enabled | Bool | default = true | doc "Whether this module is loaded",
  priority | Number | default = 50 | doc "Load order (lower = earlier)",
} in

let ShellConfig = {
  # Version constraints
  nickel_version | Version,

  # Module toggles
  modules | {
    security | ModuleConfig | default = { enabled = true, priority = 10 },
    xdg | ModuleConfig | default = { enabled = true, priority = 15 },
    locale | ModuleConfig | default = { enabled = true, priority = 20 },
    history | ModuleConfig | default = { enabled = true, priority = 30 },
    behavior | ModuleConfig | default = { enabled = true, priority = 35 },
    aliases | ModuleConfig | default = { enabled = true, priority = 40 },
    path | ModuleConfig | default = { enabled = true, priority = 50 },
    editor | ModuleConfig | default = { enabled = true, priority = 55 },
    dev | ModuleConfig | default = { enabled = true, priority = 60 },
    prompt | ModuleConfig | default = { enabled = true, priority = 90 },
  },

  # Custom settings
  history_size | Number | default = 10000,
  editor_preference | Array String | default = ["hx", "nvim", "vim", "vi"],

  # Safety settings
  safety_aliases | Bool | default = true | doc "Enable rm/mv/cp -i aliases",
  core_dumps | Bool | default = false | doc "Allow core dumps",
} in

# Default configuration
{
  nickel_version = {
    minimum = "1.5.0",
    recommended = "1.9.0",
  },
  modules = {},
  history_size = 10000,
  editor_preference = ["hx", "nvim", "vim", "vi"],
  safety_aliases = true,
  core_dumps = false,
} | ShellConfig

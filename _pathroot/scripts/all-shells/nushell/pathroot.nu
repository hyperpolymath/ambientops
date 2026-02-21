# SPDX-License-Identifier: PMPL-1.0-or-later
# _pathroot entry point for nushell

# Detect _pathroot installation
let pathroot_root = if ($env | get -i PATHROOT_HOME | is-not-empty) {
    $env.PATHROOT_HOME
} else if ($"($env.HOME)/.pathroot/env" | path exists) {
    $"($env.HOME)/.pathroot"
} else {
    let xdg = if ($env | get -i XDG_DATA_HOME | is-not-empty) {
        $env.XDG_DATA_HOME
    } else {
        $"($env.HOME)/.local/share"
    }
    $"($xdg)/pathroot"
}

$env.PATHROOT_ROOT = $pathroot_root

# Source environment
if ($"($pathroot_root)/env.nu" | path exists) {
    source $"($pathroot_root)/env.nu"
}

# Run validation
deno run --allow-read --allow-env $"($pathroot_root)/src/Validate.mjs" ...$args

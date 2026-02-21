# SPDX-License-Identifier: PMPL-1.0-or-later
# _pathroot entry point for PowerShell

$ErrorActionPreference = "Stop"

# Detect _pathroot installation
if ($env:PATHROOT_HOME) {
    $PathrootRoot = $env:PATHROOT_HOME
} elseif (Test-Path "$HOME/.pathroot/env") {
    $PathrootRoot = "$HOME/.pathroot"
} else {
    $XdgDataHome = if ($env:XDG_DATA_HOME) { $env:XDG_DATA_HOME } else { "$HOME/.local/share" }
    $PathrootRoot = "$XdgDataHome/pathroot"
}

$env:PATHROOT_ROOT = $PathrootRoot

# Source environment
if (Test-Path "$PathrootRoot/env.ps1") {
    . "$PathrootRoot/env.ps1"
}

# Run validation
& deno run --allow-read --allow-env "$PathrootRoot/src/Validate.mjs" @args

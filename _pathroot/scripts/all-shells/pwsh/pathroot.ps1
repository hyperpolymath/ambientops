#!/usr/bin/env pwsh
# SPDX-License-Identifier: PMPL-1.0-or-later
# _pathroot entry point for pwsh

set -eu

# Detect _pathroot installation
if [ -n "${PATHROOT_HOME:-}" ]; then
  PATHROOT_ROOT="$PATHROOT_HOME"
elif [ -f "$HOME/.pathroot/env" ]; then
  PATHROOT_ROOT="$HOME/.pathroot"
else
  PATHROOT_ROOT="${XDG_DATA_HOME:-$HOME/.local/share}/pathroot"
fi

export PATHROOT_ROOT

# Source environment
if [ -f "$PATHROOT_ROOT/env.sh" ]; then
  . "$PATHROOT_ROOT/env.sh"
fi

# Run validation
exec deno run --allow-read --allow-env "$PATHROOT_ROOT/src/Validate.mjs" "$@"

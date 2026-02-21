#!/usr/bin/env fish
# SPDX-License-Identifier: PMPL-1.0-or-later
# _pathroot entry point for fish

# Detect _pathroot installation
if set -q PATHROOT_HOME
    set -x PATHROOT_ROOT $PATHROOT_HOME
else if test -f $HOME/.pathroot/env
    set -x PATHROOT_ROOT $HOME/.pathroot
else
    set -x PATHROOT_ROOT (test -n "$XDG_DATA_HOME"; and echo $XDG_DATA_HOME; or echo $HOME/.local/share)/pathroot
end

# Source environment
if test -f $PATHROOT_ROOT/env.fish
    source $PATHROOT_ROOT/env.fish
end

# Run validation
exec deno run --allow-read --allow-env $PATHROOT_ROOT/src/Validate.mjs $argv

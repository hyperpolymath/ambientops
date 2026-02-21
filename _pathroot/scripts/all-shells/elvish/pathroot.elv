# SPDX-License-Identifier: PMPL-1.0-or-later
# _pathroot entry point for elvish

# Detect _pathroot installation
var pathroot-root = (if (has-env PATHROOT_HOME) {
    get-env PATHROOT_HOME
} elif (path:is-regular $E:HOME/.pathroot/env) {
    $E:HOME/.pathroot
} else {
    (or (get-env XDG_DATA_HOME) $E:HOME/.local/share)/pathroot
})

set-env PATHROOT_ROOT $pathroot-root

# Source environment
if (path:is-regular $pathroot-root/env.elv) {
    eval (slurp < $pathroot-root/env.elv)
}

# Run validation
deno run --allow-read --allow-env $pathroot-root/src/Validate.mjs $@args

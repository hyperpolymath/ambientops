# SPDX-License-Identifier: MIT OR AGPL-3.0-or-later
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <hyperpolymath>
#
# Known-Good Baseline Shell Configuration
# ========================================
# A minimal, secure, POSIX-compatible shell configuration.
# This is the full baseline - sources all modules.
#
# For lighter configurations, see examples/:
#   - minimal.sh    : Security + XDG only (servers)
#   - interactive.sh: Comfortable interactive use
#   - developer.sh  : Full dev environment (same as this)
#
# Usage: . /path/to/baseline.sh
#        source /path/to/baseline.sh

# Locate modules directory
__NS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
__NS_MODULES="$__NS_DIR/modules"

# Verify modules exist
if [ ! -d "$__NS_MODULES" ]; then
    echo "[nick-shells] Error: modules/ directory not found at $__NS_MODULES" >&2
    unset __NS_DIR __NS_MODULES
    return 1 2>/dev/null || exit 1
fi

# =============================================================================
# CORE MODULES
# =============================================================================

. "$__NS_MODULES/security.sh"
. "$__NS_MODULES/xdg.sh"
. "$__NS_MODULES/locale.sh"

# =============================================================================
# SHELL IMPROVEMENTS
# =============================================================================

. "$__NS_MODULES/history.sh"
. "$__NS_MODULES/behavior.sh"
. "$__NS_MODULES/aliases.sh"

# =============================================================================
# DEVELOPMENT ENVIRONMENT
# =============================================================================

. "$__NS_MODULES/path.sh"
. "$__NS_MODULES/editor.sh"
. "$__NS_MODULES/dev.sh"
. "$__NS_MODULES/prompt.sh"

# =============================================================================
# CLEANUP
# =============================================================================

unset __NS_DIR __NS_MODULES

# Reset -u for compatibility with scripts that don't handle it
set +u 2>/dev/null || true

# vim: ft=sh ts=4 sw=4 et

# SPDX-License-Identifier: MIT OR AGPL-3.0-or-later
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <hyperpolymath>
#
# Developer Shell Configuration Example
# ======================================
# Full baseline plus development tools for RSR workflows.
#
# Usage: . /path/to/examples/developer.sh

__NS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"

# Core
. "$__NS_DIR/modules/security.sh"
. "$__NS_DIR/modules/xdg.sh"
. "$__NS_DIR/modules/locale.sh"

# Shell improvements
. "$__NS_DIR/modules/history.sh"
. "$__NS_DIR/modules/behavior.sh"
. "$__NS_DIR/modules/aliases.sh"

# Development
. "$__NS_DIR/modules/path.sh"
. "$__NS_DIR/modules/editor.sh"
. "$__NS_DIR/modules/dev.sh"
. "$__NS_DIR/modules/prompt.sh"

unset __NS_DIR

# Reset -u for compatibility
set +u 2>/dev/null || true

# vim: ft=sh ts=4 sw=4 et

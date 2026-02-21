# SPDX-License-Identifier: MIT OR AGPL-3.0-or-later
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <hyperpolymath>
#
# Interactive Shell Configuration Example
# ========================================
# Comfortable interactive experience without dev tools.
#
# Usage: . /path/to/examples/interactive.sh

__NS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"

# Core
. "$__NS_DIR/modules/security.sh"
. "$__NS_DIR/modules/xdg.sh"
. "$__NS_DIR/modules/locale.sh"

# Interactive improvements
. "$__NS_DIR/modules/history.sh"
. "$__NS_DIR/modules/behavior.sh"
. "$__NS_DIR/modules/aliases.sh"
. "$__NS_DIR/modules/editor.sh"
. "$__NS_DIR/modules/prompt.sh"

unset __NS_DIR

# Reset -u for compatibility
set +u 2>/dev/null || true

# vim: ft=sh ts=4 sw=4 et

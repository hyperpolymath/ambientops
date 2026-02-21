# SPDX-License-Identifier: MIT OR AGPL-3.0-or-later
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <hyperpolymath>
#
# Minimal Shell Configuration Example
# ====================================
# Just security and XDG - for servers and minimal environments.
#
# Usage: . /path/to/examples/minimal.sh

__NS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"

. "$__NS_DIR/modules/security.sh"
. "$__NS_DIR/modules/xdg.sh"
. "$__NS_DIR/modules/locale.sh"

unset __NS_DIR

# vim: ft=sh ts=4 sw=4 et

# SPDX-License-Identifier: MIT OR AGPL-3.0-or-later
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <hyperpolymath>
#
# Editor Module
# =============
# Editor and pager configuration.

# Prefer modern editors
if command -v hx >/dev/null 2>&1; then
    export EDITOR='hx'
    export VISUAL='hx'
elif command -v nvim >/dev/null 2>&1; then
    export EDITOR='nvim'
    export VISUAL='nvim'
elif command -v vim >/dev/null 2>&1; then
    export EDITOR='vim'
    export VISUAL='vim'
else
    export EDITOR='vi'
    export VISUAL='vi'
fi

# Pager configuration
export PAGER='less'
export LESS='-R -F -X -i -M -S'
export LESSHISTFILE=-

# vim: ft=sh ts=4 sw=4 et

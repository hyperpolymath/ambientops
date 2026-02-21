# SPDX-License-Identifier: MIT OR AGPL-3.0-or-later
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <hyperpolymath>
#
# History Module
# ==============
# Shell history configuration with timestamps and deduplication.

# History size
HISTSIZE=10000
HISTFILESIZE=20000

# Ignore duplicates and commands starting with space
HISTCONTROL=ignoreboth:erasedups

# Append to history, don't overwrite
shopt -s histappend 2>/dev/null || true

# Timestamp history entries
HISTTIMEFORMAT='%F %T  '

# Ignore common commands in history
HISTIGNORE='ls:ll:la:cd:pwd:exit:clear:history'

# vim: ft=sh ts=4 sw=4 et

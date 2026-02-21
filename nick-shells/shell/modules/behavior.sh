# SPDX-License-Identifier: MIT OR AGPL-3.0-or-later
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <hyperpolymath>
#
# Behavior Module
# ===============
# Shell behavior improvements (bash-specific options).

# Check window size after each command
shopt -s checkwinsize 2>/dev/null || true

# Enable ** glob pattern (bash 4+)
shopt -s globstar 2>/dev/null || true

# Case-insensitive globbing
shopt -s nocaseglob 2>/dev/null || true

# Autocorrect minor typos in cd
shopt -s cdspell 2>/dev/null || true

# Enable extended pattern matching
shopt -s extglob 2>/dev/null || true

# vim: ft=sh ts=4 sw=4 et

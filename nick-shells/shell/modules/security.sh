# SPDX-License-Identifier: MIT OR AGPL-3.0-or-later
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <hyperpolymath>
#
# Security Module
# ===============
# Basic security hardening for interactive shells.

# Exit on undefined variables (catch typos)
set -u 2>/dev/null || true

# Secure umask: files 644, directories 755
umask 022

# Disable core dumps (security)
ulimit -c 0 2>/dev/null || true

# Interactive safety aliases (prompt before destructive operations)
alias cp='cp -i'
alias mv='mv -i'
alias rm='rm -i'

# vim: ft=sh ts=4 sw=4 et

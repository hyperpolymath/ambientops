# SPDX-License-Identifier: MIT OR AGPL-3.0-or-later
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <hyperpolymath>
#
# Development Module
# ==================
# RSR-compliant development environment configuration.

# Rust
if command -v rustc >/dev/null 2>&1; then
    export RUST_BACKTRACE=1
fi

# Deno (RSR: preferred JS runtime)
if command -v deno >/dev/null 2>&1; then
    export DENO_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/deno"
fi

# vim: ft=sh ts=4 sw=4 et

# SPDX-License-Identifier: MIT OR AGPL-3.0-or-later
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <hyperpolymath>
#
# PATH Module
# ===========
# RSR-compliant PATH configuration for Rust, Deno, Guix, and Nix.

# Function to safely add to PATH (no duplicates)
__ns_path_prepend() {
    case ":${PATH}:" in
        *:"$1":*) ;;
        *) PATH="$1${PATH:+:$PATH}" ;;
    esac
}

__ns_path_append() {
    case ":${PATH}:" in
        *:"$1":*) ;;
        *) PATH="${PATH:+$PATH:}$1" ;;
    esac
}

# User binaries (high priority)
[ -d "$HOME/.local/bin" ] && __ns_path_prepend "$HOME/.local/bin"
[ -d "$HOME/bin" ] && __ns_path_prepend "$HOME/bin"

# Cargo/Rust (RSR: Rust preferred for CLI tools)
[ -d "$HOME/.cargo/bin" ] && __ns_path_prepend "$HOME/.cargo/bin"

# Deno (RSR: replaces Node/npm/bun)
[ -d "$HOME/.deno/bin" ] && __ns_path_prepend "$HOME/.deno/bin"

# Guix (RSR: primary package manager)
if [ -d "$HOME/.guix-profile" ]; then
    __ns_path_prepend "$HOME/.guix-profile/bin"
    export GUIX_LOCPATH="$HOME/.guix-profile/lib/locale"
fi

# Nix (RSR: fallback package manager)
if [ -e "$HOME/.nix-profile/etc/profile.d/nix.sh" ]; then
    . "$HOME/.nix-profile/etc/profile.d/nix.sh"
fi

export PATH

# Cleanup helper functions
unset -f __ns_path_prepend __ns_path_append 2>/dev/null || true

# vim: ft=sh ts=4 sw=4 et

#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# bootstrap-check.sh - Identify critical bootstrap components
#
# This script analyzes your shell configuration to determine the
# minimal set of components required for successful shell startup.

set -euo pipefail

HOME_DIR="${1:-$HOME}"
BASHRC="${HOME_DIR}/.bashrc"
BASHRC_D="${HOME_DIR}/.bashrc.d"

echo "=== CRITICAL BOOTSTRAP COMPONENT ANALYSIS ==="
echo "Home: $HOME_DIR"
echo ""

# =============================================================================
# 1. SOURCED FILES DEPENDENCY GRAPH
# =============================================================================
echo "1. FILES SOURCED DURING STARTUP"
echo "================================"

sourced_files=()

# Parse .bashrc for source/. commands
if [[ -f "$BASHRC" ]]; then
    echo "From .bashrc:"
    while IFS= read -r line; do
        # Match: source file, . file, [[ -f file ]] && . file
        if [[ "$line" =~ (source|\.)[[:space:]]+[\"\']?([^\"\'[:space:]]+) ]]; then
            file="${BASH_REMATCH[2]}"
            # Expand $HOME
            file="${file/\$HOME/$HOME_DIR}"
            file="${file/\~/$HOME_DIR}"
            echo "  - $file"
            sourced_files+=("$file")
        fi
    done < "$BASHRC"
fi

# List module files
if [[ -d "$BASHRC_D" ]]; then
    echo ""
    echo "From .bashrc.d modules:"
    for dir in "$BASHRC_D"/*/; do
        if [[ -d "$dir" ]]; then
            dirname=$(basename "$dir")
            echo "  [$dirname]"
            for f in "$dir"*; do
                if [[ -f "$f" ]]; then
                    echo "    - $(basename "$f")"
                    sourced_files+=("$f")
                fi
            done
        fi
    done
fi

# =============================================================================
# 2. EXTERNAL COMMANDS INVOKED
# =============================================================================
echo ""
echo "2. EXTERNAL COMMANDS REQUIRED"
echo "=============================="

commands_required=()

# Scan all shell files for command invocations
for f in "$BASHRC" "${sourced_files[@]}"; do
    if [[ -f "$f" ]]; then
        # Look for command -v, which, eval "$(...)", and direct invocations
        while IFS= read -r cmd; do
            # Clean up the command name
            cmd=$(echo "$cmd" | sed 's/[^a-zA-Z0-9_-]//g')
            if [[ -n "$cmd" ]] && [[ ! " ${commands_required[*]} " =~ " ${cmd} " ]]; then
                commands_required+=("$cmd")
            fi
        done < <(grep -oE '(command -v|which|eval "\$\(|`)[[:space:]]*([a-zA-Z0-9_-]+)' "$f" 2>/dev/null | \
                 sed 's/command -v //; s/which //; s/eval "\$(//; s/`//' || true)
    fi
done

# Known critical commands from common shell tools
known_critical=(
    # Core
    "bash" "sh"
    # Path/env management
    "asdf" "direnv"
    # Prompt
    "starship"
    # History
    "atuin"
    # Navigation
    "zoxide"
    # Completions
    "carapace"
    # Version managers
    "opam" "rustup" "ghcup"
)

echo "Detected commands:"
for cmd in "${commands_required[@]}"; do
    if command -v "$cmd" &>/dev/null; then
        echo "  [FOUND] $cmd -> $(command -v "$cmd")"
    else
        echo "  [MISSING] $cmd"
    fi
done

echo ""
echo "Known critical tools:"
for cmd in "${known_critical[@]}"; do
    if command -v "$cmd" &>/dev/null; then
        echo "  [FOUND] $cmd"
    else
        echo "  [---] $cmd (not installed)"
    fi
done

# =============================================================================
# 3. ENVIRONMENT VARIABLES SET
# =============================================================================
echo ""
echo "3. ENVIRONMENT VARIABLES"
echo "========================="

env_vars=()

for f in "$BASHRC" "${sourced_files[@]}"; do
    if [[ -f "$f" ]]; then
        while IFS= read -r var; do
            var=$(echo "$var" | cut -d= -f1)
            if [[ -n "$var" ]] && [[ ! " ${env_vars[*]} " =~ " ${var} " ]]; then
                env_vars+=("$var")
            fi
        done < <(grep -oE 'export[[:space:]]+[A-Z_][A-Z0-9_]*=' "$f" 2>/dev/null | \
                 sed 's/export //; s/=//' || true)
    fi
done

echo "Variables exported:"
for var in "${env_vars[@]}"; do
    echo "  - $var"
done | sort | uniq

# =============================================================================
# 4. PATHS ADDED TO PATH
# =============================================================================
echo ""
echo "4. PATH MODIFICATIONS"
echo "====================="

paths_added=()

for f in "$BASHRC" "${sourced_files[@]}"; do
    if [[ -f "$f" ]]; then
        while IFS= read -r path; do
            # Clean and expand
            path="${path/\$HOME/$HOME_DIR}"
            path="${path/\~/$HOME_DIR}"
            path="${path//\"/}"
            if [[ -n "$path" ]] && [[ ! " ${paths_added[*]} " =~ " ${path} " ]]; then
                paths_added+=("$path")
            fi
        done < <(grep -oE 'PATH="[^"]*"' "$f" 2>/dev/null | \
                 grep -oE '\$HOME[^:]*|\~/[^:]*|/[^:$"]+' || true)
    fi
done

echo "Paths added (existence check):"
for p in "${paths_added[@]}"; do
    if [[ -e "$p" ]]; then
        echo "  [EXISTS] $p"
    else
        echo "  [MISSING] $p"
    fi
done

# =============================================================================
# 5. MINIMAL BOOTSTRAP SET
# =============================================================================
echo ""
echo "5. MINIMAL BOOTSTRAP REQUIREMENTS"
echo "=================================="
echo ""
echo "To successfully start a shell, you need:"
echo ""
echo "FILES:"
echo "  - $BASHRC"
if [[ -d "$BASHRC_D" ]]; then
    echo "  - $BASHRC_D/ (with modules)"
fi
echo ""
echo "PACKAGES (Fedora):"
echo "  bash coreutils findutils grep gawk"
echo "  procps-ng util-linux ShellCheck"
echo ""
echo "OPTIONAL (for full functionality):"
echo "  asdf (version management)"
echo "  starship (prompt)"
echo "  direnv (environment switching)"
echo "  atuin (history)"
echo "  zoxide (navigation)"
echo ""

# =============================================================================
# 6. GUIX MANIFEST GENERATION
# =============================================================================
echo "6. GUIX MANIFEST (for reproducible environment)"
echo "================================================"
echo ""
echo "Save this to guix-manifest.scm:"
echo ""
cat <<'GUIX'
;; SPDX-License-Identifier: AGPL-3.0-or-later
;; nerdsafe-restart environment manifest
;; Install: guix package -m guix-manifest.scm

(specifications->manifest
 '(;; Core shell
   "bash"
   "coreutils"
   "findutils"
   "grep"
   "gawk"
   "sed"

   ;; Validation
   "shellcheck"

   ;; Shell enhancements (optional)
   ;; "starship"
   ;; "zoxide"
   ;; "direnv"
   ;; "atuin"

   ;; Version managers
   ;; Note: asdf not in Guix, use guix shell instead
   ))
GUIX

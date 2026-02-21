#!/bin/sh
# SPDX-License-Identifier: MIT OR AGPL-3.0-or-later
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <hyperpolymath>
#
# Apply baseline shell configuration
# ==================================
# This script adds the baseline.sh source line to your shell RC file.
# It is idempotent - safe to run multiple times.
#
# Usage: ./apply.sh [--uninstall] [--shell bash|zsh|all]

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASELINE_PATH="$SCRIPT_DIR/baseline.sh"
MARKER="# nick-shells baseline"
SOURCE_LINE=". \"$BASELINE_PATH\"  $MARKER"

# Colors (if terminal supports them)
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    NC=''
fi

log_info() { printf "${BLUE}[INFO]${NC} %s\n" "$1"; }
log_ok() { printf "${GREEN}[OK]${NC} %s\n" "$1"; }
log_warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$1"; }
log_error() { printf "${RED}[ERROR]${NC} %s\n" "$1" >&2; }

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Install or remove the baseline shell configuration.

Options:
    --install       Install baseline to shell RC (default)
    --uninstall     Remove baseline from shell RC
    --shell SHELL   Target shell: bash, zsh, or all (default: all)
    --dry-run       Show what would be done without making changes
    --help          Show this help message

Examples:
    $(basename "$0")                   # Install for all shells
    $(basename "$0") --shell bash      # Install for bash only
    $(basename "$0") --uninstall       # Remove from all shells
EOF
    exit 0
}

# Parse arguments
ACTION="install"
TARGET_SHELL="all"
DRY_RUN=""

while [ $# -gt 0 ]; do
    case "$1" in
        --install)
            ACTION="install"
            shift
            ;;
        --uninstall)
            ACTION="uninstall"
            shift
            ;;
        --shell)
            TARGET_SHELL="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN="1"
            shift
            ;;
        --help|-h)
            usage
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            ;;
    esac
done

# Validate baseline exists
if [ ! -f "$BASELINE_PATH" ]; then
    log_error "baseline.sh not found at: $BASELINE_PATH"
    exit 1
fi

# Get RC file for shell
get_rc_file() {
    case "$1" in
        bash) echo "$HOME/.bashrc" ;;
        zsh)  echo "$HOME/.zshrc" ;;
        *)    return 1 ;;
    esac
}

# Check if baseline is already installed
is_installed() {
    rc_file="$1"
    [ -f "$rc_file" ] && grep -qF "$MARKER" "$rc_file"
}

# Create backup of RC file
backup_rc() {
    rc_file="$1"
    if [ -f "$rc_file" ]; then
        backup="${rc_file}.backup.$(date +%Y%m%d_%H%M%S)"
        if [ -z "$DRY_RUN" ]; then
            cp "$rc_file" "$backup"
            log_info "Backed up $rc_file to $backup"
        else
            log_info "[DRY-RUN] Would backup $rc_file to $backup"
        fi
    fi
}

# Install baseline to RC file
install_baseline() {
    shell="$1"
    rc_file="$(get_rc_file "$shell")"

    if is_installed "$rc_file"; then
        log_warn "Already installed in $rc_file (skipping)"
        return 0
    fi

    backup_rc "$rc_file"

    if [ -z "$DRY_RUN" ]; then
        # Create RC file if it doesn't exist
        [ ! -f "$rc_file" ] && touch "$rc_file"

        # Add source line at the end
        printf '\n%s\n' "$SOURCE_LINE" >> "$rc_file"
        log_ok "Installed baseline to $rc_file"
    else
        log_info "[DRY-RUN] Would add to $rc_file:"
        log_info "    $SOURCE_LINE"
    fi
}

# Uninstall baseline from RC file
uninstall_baseline() {
    shell="$1"
    rc_file="$(get_rc_file "$shell")"

    if ! is_installed "$rc_file"; then
        log_warn "Not installed in $rc_file (skipping)"
        return 0
    fi

    backup_rc "$rc_file"

    if [ -z "$DRY_RUN" ]; then
        # Remove lines containing the marker
        tmp_file="$(mktemp)"
        grep -vF "$MARKER" "$rc_file" > "$tmp_file" || true
        mv "$tmp_file" "$rc_file"
        log_ok "Removed baseline from $rc_file"
    else
        log_info "[DRY-RUN] Would remove baseline from $rc_file"
    fi
}

# Main
main() {
    log_info "Baseline configuration: $BASELINE_PATH"
    log_info "Action: $ACTION"
    log_info "Target shells: $TARGET_SHELL"
    [ -n "$DRY_RUN" ] && log_warn "Dry-run mode enabled"
    echo

    case "$TARGET_SHELL" in
        all)
            shells="bash zsh"
            ;;
        bash|zsh)
            shells="$TARGET_SHELL"
            ;;
        *)
            log_error "Invalid shell: $TARGET_SHELL"
            exit 1
            ;;
    esac

    for shell in $shells; do
        rc_file="$(get_rc_file "$shell")"

        # Skip if parent dir doesn't exist (shell not used)
        if [ ! -d "$(dirname "$rc_file")" ]; then
            log_warn "Skipping $shell (home directory not found)"
            continue
        fi

        case "$ACTION" in
            install)
                install_baseline "$shell"
                ;;
            uninstall)
                uninstall_baseline "$shell"
                ;;
        esac
    done

    echo
    if [ "$ACTION" = "install" ] && [ -z "$DRY_RUN" ]; then
        log_ok "Done! Restart your shell or run: source ~/.bashrc (or ~/.zshrc)"
    elif [ "$ACTION" = "uninstall" ] && [ -z "$DRY_RUN" ]; then
        log_ok "Done! Baseline configuration removed."
    fi
}

main

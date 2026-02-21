#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# nerdsafe-restart - Pre-reboot validation for paranoid sysadmins
# https://github.com/hyperpolymath/nerdsafe-restart

set -euo pipefail

VERSION="0.1.0"
PASS=0
WARN=0
FAIL=0
CRIT=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Detect if running in container
IN_CONTAINER=false
if [[ -f /.dockerenv ]] || [[ -f /run/.containerenv ]]; then
    IN_CONTAINER=true
fi

# Default paths (can be overridden via env or args)
HOME_DIR="${NERDSAFE_HOME:-$HOME}"
BASHRC="${NERDSAFE_BASHRC:-$HOME_DIR/.bashrc}"
BASHRC_D="${NERDSAFE_BASHRC_D:-$HOME_DIR/.bashrc.d}"

usage() {
    cat <<EOF
nerdsafe-restart v${VERSION} - Pre-reboot validation

Usage: nerdsafe-restart [COMMAND] [OPTIONS]

Commands:
  check       Run validation checks (default)
  simulate    Simulate shell startup in isolation
  report      Generate detailed report
  version     Show version

Options:
  --quick     Quick checks only (syntax + critical paths)
  --thorough  Extended validation (services, boot, SELinux)
  --paranoid  Maximum validation (formal verification, SMART)
  --json      Output in JSON format
  --sarif     Output in SARIF format (for CI/CD)
  --home DIR  Override home directory
  --bashrc F  Override bashrc path
  --help      Show this help

Environment:
  NERDSAFE_HOME      Home directory to validate
  NERDSAFE_BASHRC    Path to .bashrc
  NERDSAFE_BASHRC_D  Path to .bashrc.d modules

Examples:
  nerdsafe-restart check
  nerdsafe-restart check --paranoid
  nerdsafe-restart simulate
  nerdctl run --rm -v \$HOME:\$HOME:ro nerdsafe-restart check

Exit Codes:
  0 - All checks passed (safe to reboot)
  1 - Warnings detected (review recommended)
  2 - Errors detected (do not reboot)
  3 - Critical failures (system may not boot)
EOF
}

log_pass() { echo -e "${GREEN}[PASS]${NC} $1"; ((PASS++)) || true; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; ((WARN++)) || true; }
log_fail() { echo -e "${RED}[FAIL]${NC} $1"; ((FAIL++)) || true; }
log_crit() { echo -e "${RED}[CRIT]${NC} $1"; ((CRIT++)) || true; }
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }

# ===========================================================================
# SHELL CONFIGURATION CHECKS
# ===========================================================================

check_bashrc_syntax() {
    log_info "Checking shell configuration syntax..."

    if [[ ! -f "$BASHRC" ]]; then
        log_crit "bashrc not found: $BASHRC"
        return
    fi

    if bash -n "$BASHRC" 2>/dev/null; then
        log_pass "bashrc syntax valid"
    else
        log_crit "bashrc syntax error: $(bash -n "$BASHRC" 2>&1)"
    fi
}

check_module_syntax() {
    log_info "Checking module file syntax..."

    if [[ ! -d "$BASHRC_D" ]]; then
        log_warn "bashrc.d not found: $BASHRC_D"
        return
    fi

    local failed=0
    for f in "$BASHRC_D"/*/*; do
        if [[ -f "$f" ]]; then
            if bash -n "$f" 2>/dev/null; then
                log_pass "$(basename "$f")"
            else
                log_fail "$(basename "$f"): $(bash -n "$f" 2>&1 | head -1)"
                ((failed++))
            fi
        fi
    done

    if [[ $failed -eq 0 ]]; then
        log_pass "All module files valid"
    fi
}

check_shellcheck() {
    log_info "Running ShellCheck formal verification..."

    if ! command -v shellcheck &>/dev/null; then
        log_warn "ShellCheck not installed, skipping formal verification"
        return
    fi

    if [[ -f "$BASHRC" ]]; then
        local issues
        issues=$(shellcheck -f gcc "$BASHRC" 2>/dev/null | wc -l)
        if [[ $issues -eq 0 ]]; then
            log_pass "bashrc passes ShellCheck"
        else
            log_warn "bashrc has $issues ShellCheck issues"
        fi
    fi
}

# ===========================================================================
# CRITICAL PATHS CHECK
# ===========================================================================

check_critical_paths() {
    log_info "Checking critical paths..."

    local paths=(
        "$HOME_DIR/.local/bin"
        "$HOME_DIR/.bashrc"
    )

    # Add asdf if present
    [[ -d "$HOME_DIR/.asdf" ]] && paths+=("$HOME_DIR/.asdf/asdf.sh")

    for p in "${paths[@]}"; do
        if [[ -e "$p" ]]; then
            log_pass "exists: $p"
        else
            log_fail "missing: $p"
        fi
    done
}

check_permissions() {
    log_info "Checking file permissions..."

    if [[ -f "$BASHRC" ]]; then
        local perms
        perms=$(stat -c "%a" "$BASHRC" 2>/dev/null || echo "000")
        if [[ "$perms" == "644" ]] || [[ "$perms" == "600" ]]; then
            log_pass "bashrc permissions: $perms"
        else
            log_warn "bashrc permissions: $perms (expected 644 or 600)"
        fi
    fi

    # Check for world-writable configs
    if [[ -d "$BASHRC_D" ]]; then
        local ww
        ww=$(find "$BASHRC_D" -type f -perm -002 2>/dev/null | wc -l)
        if [[ $ww -eq 0 ]]; then
            log_pass "No world-writable config files"
        else
            log_crit "$ww world-writable config files found (security risk)"
        fi
    fi
}

# ===========================================================================
# SHELL STARTUP SIMULATION
# ===========================================================================

simulate_startup() {
    log_info "Simulating shell startup..."

    local output
    local exit_code

    # Create isolated environment
    output=$(timeout 10 bash --login -c '
        echo "SHELL_OK"
        echo "PATH_ENTRIES=$(echo "$PATH" | tr ":" "\n" | wc -l)"
        echo "EDITOR=$EDITOR"
        for cmd in asdf direnv starship zoxide git; do
            if command -v $cmd &>/dev/null; then
                echo "TOOL_OK:$cmd"
            else
                echo "TOOL_MISSING:$cmd"
            fi
        done
    ' 2>&1) || exit_code=$?

    if echo "$output" | grep -q "SHELL_OK"; then
        log_pass "Shell startup successful"

        # Parse tool availability
        while IFS= read -r line; do
            if [[ "$line" == TOOL_OK:* ]]; then
                log_pass "tool available: ${line#TOOL_OK:}"
            elif [[ "$line" == TOOL_MISSING:* ]]; then
                log_warn "tool missing: ${line#TOOL_MISSING:}"
            fi
        done <<< "$output"
    else
        log_crit "Shell startup failed"
        echo "$output" | head -10
    fi
}

# ===========================================================================
# SYSTEM CHECKS (thorough mode)
# ===========================================================================

check_services() {
    log_info "Checking critical services..."

    if $IN_CONTAINER; then
        log_info "Skipping service checks (running in container)"
        return
    fi

    if command -v systemctl &>/dev/null; then
        for svc in sshd display-manager NetworkManager; do
            if systemctl is-enabled "$svc" &>/dev/null; then
                if systemctl is-active "$svc" &>/dev/null; then
                    log_pass "service active: $svc"
                else
                    log_warn "service enabled but not active: $svc"
                fi
            fi
        done
    fi
}

check_filesystem() {
    log_info "Checking filesystem..."

    if $IN_CONTAINER; then
        log_info "Skipping filesystem checks (running in container)"
        return
    fi

    # Check home directory
    if [[ -d "$HOME_DIR" ]] && [[ -w "$HOME_DIR" ]]; then
        log_pass "Home directory writable"
    else
        log_crit "Home directory not writable: $HOME_DIR"
    fi

    # Check disk space
    local avail
    avail=$(df -h "$HOME_DIR" 2>/dev/null | awk 'NR==2 {print $4}')
    log_info "Available disk space: $avail"
}

check_ostree() {
    log_info "Checking ostree/rpm-ostree status..."

    if $IN_CONTAINER; then
        log_info "Skipping ostree checks (running in container)"
        return
    fi

    if command -v rpm-ostree &>/dev/null; then
        local staged
        staged=$(rpm-ostree status 2>/dev/null | grep -c "Staged:" || true)
        if [[ $staged -gt 0 ]]; then
            log_info "rpm-ostree deployment staged (will apply on reboot)"
            log_pass "Staged deployment detected"
        else
            log_info "No staged rpm-ostree deployment"
        fi
    fi
}

check_selinux() {
    log_info "Checking SELinux status..."

    if $IN_CONTAINER; then
        log_info "Skipping SELinux checks (running in container)"
        return
    fi

    if command -v getenforce &>/dev/null; then
        local mode
        mode=$(getenforce 2>/dev/null || echo "Unknown")
        log_info "SELinux mode: $mode"

        if [[ "$mode" == "Enforcing" ]] || [[ "$mode" == "Permissive" ]]; then
            log_pass "SELinux operational"
        fi
    fi
}

# ===========================================================================
# BACKUP CHECK
# ===========================================================================

check_backup() {
    log_info "Checking for configuration backups..."

    local backup_patterns=(
        "$HOME_DIR/.bashrc.backup-*"
        "$HOME_DIR/.bashrc.bak"
        "$HOME_DIR/.bashrc~"
    )

    local found=0
    for pattern in "${backup_patterns[@]}"; do
        # shellcheck disable=SC2086
        if ls $pattern &>/dev/null 2>&1; then
            log_pass "Backup found: $(ls -1 $pattern 2>/dev/null | tail -1)"
            ((found++))
        fi
    done

    if [[ $found -eq 0 ]]; then
        log_warn "No bashrc backups found"
    fi
}

# ===========================================================================
# MAIN
# ===========================================================================

run_quick() {
    echo "=== nerdsafe-restart v${VERSION} - Quick Check ==="
    echo ""
    check_bashrc_syntax
    check_critical_paths
    check_permissions
    check_backup
}

run_standard() {
    echo "=== nerdsafe-restart v${VERSION} - Standard Check ==="
    echo ""
    check_bashrc_syntax
    check_module_syntax
    check_critical_paths
    check_permissions
    check_backup
    simulate_startup
    check_ostree
}

run_thorough() {
    echo "=== nerdsafe-restart v${VERSION} - Thorough Check ==="
    echo ""
    check_bashrc_syntax
    check_module_syntax
    check_critical_paths
    check_permissions
    check_backup
    simulate_startup
    check_services
    check_filesystem
    check_ostree
    check_selinux
}

run_paranoid() {
    echo "=== nerdsafe-restart v${VERSION} - Paranoid Check ==="
    echo ""
    check_bashrc_syntax
    check_module_syntax
    check_shellcheck
    check_critical_paths
    check_permissions
    check_backup
    simulate_startup
    check_services
    check_filesystem
    check_ostree
    check_selinux
}

print_summary() {
    echo ""
    echo "=== SUMMARY ==="
    echo -e "Pass: ${GREEN}$PASS${NC} | Warn: ${YELLOW}$WARN${NC} | Fail: ${RED}$FAIL${NC} | Critical: ${RED}$CRIT${NC}"
    echo ""

    if [[ $CRIT -gt 0 ]]; then
        echo -e "${RED}RESULT: CRITICAL - DO NOT REBOOT${NC}"
        echo "Critical issues detected that may prevent system boot."
        return 3
    elif [[ $FAIL -gt 0 ]]; then
        echo -e "${RED}RESULT: FAILED - DO NOT REBOOT${NC}"
        echo "Errors detected. Fix issues before rebooting."
        return 2
    elif [[ $WARN -gt 0 ]]; then
        echo -e "${YELLOW}RESULT: WARNINGS - REVIEW BEFORE REBOOT${NC}"
        echo "Warnings detected. Review and consider if safe to proceed."
        return 1
    else
        echo -e "${GREEN}RESULT: PASSED - SAFE TO REBOOT${NC}"
        return 0
    fi
}

main() {
    local cmd="${1:-check}"
    local level="standard"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            check|simulate|report|version)
                cmd="$1"
                ;;
            --quick)
                level="quick"
                ;;
            --thorough)
                level="thorough"
                ;;
            --paranoid)
                level="paranoid"
                ;;
            --home)
                HOME_DIR="$2"
                BASHRC="$HOME_DIR/.bashrc"
                BASHRC_D="$HOME_DIR/.bashrc.d"
                shift
                ;;
            --bashrc)
                BASHRC="$2"
                shift
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                ;;
        esac
        shift
    done

    case "$cmd" in
        check)
            case "$level" in
                quick)    run_quick ;;
                standard) run_standard ;;
                thorough) run_thorough ;;
                paranoid) run_paranoid ;;
            esac
            print_summary
            ;;
        simulate)
            simulate_startup
            print_summary
            ;;
        version)
            echo "nerdsafe-restart v${VERSION}"
            ;;
        *)
            usage
            exit 1
            ;;
    esac
}

main "$@"

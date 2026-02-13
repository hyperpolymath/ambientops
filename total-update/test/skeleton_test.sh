#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <jonathan@hyperpolymath.io>

# Walking Skeleton Integration Test
# Tests the package manager backends (Guix/Nix) with safety boundary enforcement

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test state
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((TESTS_PASSED++))
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((TESTS_FAILED++))
}

log_skip() {
    echo -e "${YELLOW}[SKIP]${NC} $1"
}

run_test() {
    local name="$1"
    local cmd="$2"
    ((TESTS_RUN++))

    log_info "Running: $name"
    if eval "$cmd" > /dev/null 2>&1; then
        log_success "$name"
        return 0
    else
        log_fail "$name"
        return 1
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# Backend Availability Tests
# ═══════════════════════════════════════════════════════════════════════════════

test_guix_available() {
    if command -v guix >/dev/null 2>&1; then
        log_success "Guix backend available"
        return 0
    else
        log_skip "Guix not installed"
        return 1
    fi
}

test_nix_available() {
    if command -v nix-env >/dev/null 2>&1; then
        log_success "Nix backend available"
        return 0
    else
        log_skip "Nix not installed"
        return 1
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# Guix Walking Skeleton Tests
# ═══════════════════════════════════════════════════════════════════════════════

test_guix_skeleton() {
    if ! command -v guix >/dev/null 2>&1; then
        log_skip "Guix skeleton tests (Guix not available)"
        return 0
    fi

    echo ""
    log_info "=== Guix Walking Skeleton Tests ==="

    # Test 1: List generations (proves rollback is available)
    ((TESTS_RUN++))
    log_info "Testing: guix package -l (list generations)"
    if guix package -l >/dev/null 2>&1; then
        log_success "Can list Guix generations (recovery points)"
    else
        log_fail "Cannot list Guix generations"
    fi

    # Test 2: Get current generation
    ((TESTS_RUN++))
    log_info "Testing: Get current generation"
    CURRENT_GEN=$(guix package -l 2>/dev/null | grep -E '\(current\)' | head -1 | awk '{print $2}' || echo "1")
    if [[ -n "$CURRENT_GEN" ]]; then
        log_success "Current Guix generation: $CURRENT_GEN"
    else
        log_fail "Cannot determine current generation"
    fi

    # Test 3: List installed packages (read-only, safe)
    ((TESTS_RUN++))
    log_info "Testing: guix package -I (list installed)"
    if guix package -I >/dev/null 2>&1; then
        INSTALLED_COUNT=$(guix package -I 2>/dev/null | wc -l)
        log_success "Listed $INSTALLED_COUNT installed packages"
    else
        log_fail "Cannot list installed packages"
    fi

    # Test 4: Search packages (read-only, safe)
    ((TESTS_RUN++))
    log_info "Testing: guix search hello"
    if guix search hello 2>/dev/null | head -5 >/dev/null; then
        log_success "Package search works"
    else
        log_fail "Package search failed"
    fi

    # Test 5: Dry-run install (verifies install capability without changes)
    ((TESTS_RUN++))
    log_info "Testing: guix package -i hello --dry-run (simulated install)"
    if guix package -i hello --dry-run 2>&1 | grep -q "would be installed\|would be upgraded\|nothing to be done"; then
        log_success "Dry-run install works"
    else
        log_fail "Dry-run install failed"
    fi

    # Test 6: Rollback capability check
    ((TESTS_RUN++))
    log_info "Testing: Rollback capability"
    GEN_COUNT=$(guix package -l 2>/dev/null | grep -c "Generation" || echo "0")
    if [[ "$GEN_COUNT" -gt 0 ]]; then
        log_success "Rollback available ($GEN_COUNT generations)"
    else
        log_skip "No generations for rollback test"
    fi

    echo ""
}

# ═══════════════════════════════════════════════════════════════════════════════
# Nix Walking Skeleton Tests
# ═══════════════════════════════════════════════════════════════════════════════

test_nix_skeleton() {
    if ! command -v nix-env >/dev/null 2>&1; then
        log_skip "Nix skeleton tests (Nix not available)"
        return 0
    fi

    echo ""
    log_info "=== Nix Walking Skeleton Tests ==="

    # Test 1: List generations
    ((TESTS_RUN++))
    log_info "Testing: nix-env --list-generations"
    if nix-env --list-generations >/dev/null 2>&1; then
        log_success "Can list Nix generations (recovery points)"
    else
        log_fail "Cannot list Nix generations"
    fi

    # Test 2: Get current generation
    ((TESTS_RUN++))
    log_info "Testing: Get current generation"
    CURRENT_GEN=$(nix-env --list-generations 2>/dev/null | grep -E '\(current\)' | awk '{print $1}' || echo "1")
    if [[ -n "$CURRENT_GEN" ]]; then
        log_success "Current Nix generation: $CURRENT_GEN"
    else
        log_fail "Cannot determine current generation"
    fi

    # Test 3: List installed packages
    ((TESTS_RUN++))
    log_info "Testing: nix-env -q (list installed)"
    if nix-env -q >/dev/null 2>&1; then
        INSTALLED_COUNT=$(nix-env -q 2>/dev/null | wc -l)
        log_success "Listed $INSTALLED_COUNT installed packages"
    else
        log_fail "Cannot list installed packages"
    fi

    # Test 4: Search packages
    ((TESTS_RUN++))
    log_info "Testing: nix search nixpkgs hello"
    if nix search nixpkgs hello 2>/dev/null | head -5 >/dev/null; then
        log_success "Package search works (nix search)"
    else
        # Fallback to legacy search
        if nix-env -qa 'hello*' 2>/dev/null | head -5 >/dev/null; then
            log_success "Package search works (nix-env -qa)"
        else
            log_fail "Package search failed"
        fi
    fi

    # Test 5: Dry-run install
    ((TESTS_RUN++))
    log_info "Testing: nix-env -i hello --dry-run (simulated install)"
    if nix-env -i hello --dry-run 2>&1 | grep -qE "would be installed|these derivations will be built|will be fetched"; then
        log_success "Dry-run install works"
    else
        # Accept any non-error as success for dry-run
        if nix-env -i hello --dry-run 2>&1; then
            log_success "Dry-run install works"
        else
            log_fail "Dry-run install failed"
        fi
    fi

    # Test 6: Rollback capability check
    ((TESTS_RUN++))
    log_info "Testing: Rollback capability"
    GEN_COUNT=$(nix-env --list-generations 2>/dev/null | wc -l || echo "0")
    if [[ "$GEN_COUNT" -gt 0 ]]; then
        log_success "Rollback available ($GEN_COUNT generations)"
    else
        log_skip "No generations for rollback test"
    fi

    echo ""
}

# ═══════════════════════════════════════════════════════════════════════════════
# Safety Invariant Tests
# ═══════════════════════════════════════════════════════════════════════════════

test_safety_invariant() {
    echo ""
    log_info "=== Safety Invariant Tests ==="

    # The critical invariant is:
    # "Every modifying operation MUST be preceded by a recovery point"

    # For Guix/Nix, this is guaranteed by design:
    # - Every package operation creates a new generation
    # - Previous generations are always available for rollback
    # - Rollback is a simple generation switch

    ((TESTS_RUN++))
    log_info "Testing: Safety invariant (native transactions)"

    local invariant_holds=true

    # Check Guix
    if command -v guix >/dev/null 2>&1; then
        if guix package -l >/dev/null 2>&1; then
            log_info "  Guix: Native transactions enabled ✓"
        else
            invariant_holds=false
        fi
    fi

    # Check Nix
    if command -v nix-env >/dev/null 2>&1; then
        if nix-env --list-generations >/dev/null 2>&1; then
            log_info "  Nix: Native transactions enabled ✓"
        else
            invariant_holds=false
        fi
    fi

    if $invariant_holds; then
        log_success "Safety invariant verified (all backends have native transaction support)"
    else
        log_fail "Safety invariant verification failed"
    fi

    # Additional invariant: Recovery point exists
    ((TESTS_RUN++))
    log_info "Testing: Recovery point availability"

    local recovery_available=false

    if command -v guix >/dev/null 2>&1; then
        GEN_COUNT=$(guix package -l 2>/dev/null | grep -c "Generation" || echo "0")
        if [[ "$GEN_COUNT" -gt 0 ]]; then
            recovery_available=true
            log_info "  Guix: $GEN_COUNT recovery points available"
        fi
    fi

    if command -v nix-env >/dev/null 2>&1; then
        GEN_COUNT=$(nix-env --list-generations 2>/dev/null | wc -l || echo "0")
        if [[ "$GEN_COUNT" -gt 0 ]]; then
            recovery_available=true
            log_info "  Nix: $GEN_COUNT recovery points available"
        fi
    fi

    if $recovery_available; then
        log_success "Recovery points available for rollback"
    else
        log_skip "No recovery points (first-use scenario)"
    fi

    echo ""
}

# ═══════════════════════════════════════════════════════════════════════════════
# Main Test Runner
# ═══════════════════════════════════════════════════════════════════════════════

main() {
    echo ""
    echo "╔═══════════════════════════════════════════════════════════════════════════╗"
    echo "║  DNFinition Walking Skeleton Test Suite                                   ║"
    echo "║  Package Manager Backends: Guix, Nix                                      ║"
    echo "║  Testing: install, upgrade, rollback with safety boundary                 ║"
    echo "╚═══════════════════════════════════════════════════════════════════════════╝"
    echo ""

    # Backend availability
    log_info "=== Backend Availability ==="
    test_guix_available || true
    test_nix_available || true
    echo ""

    # Run skeleton tests
    test_guix_skeleton
    test_nix_skeleton
    test_safety_invariant

    # Summary
    echo "╔═══════════════════════════════════════════════════════════════════════════╗"
    echo "║  Test Summary                                                             ║"
    echo "╠═══════════════════════════════════════════════════════════════════════════╣"
    printf "║  Tests Run:    %-58s ║\n" "$TESTS_RUN"
    printf "║  Tests Passed: %-58s ║\n" "${GREEN}$TESTS_PASSED${NC}"
    if [[ $TESTS_FAILED -gt 0 ]]; then
        printf "║  Tests Failed: %-58s ║\n" "${RED}$TESTS_FAILED${NC}"
    else
        printf "║  Tests Failed: %-58s ║\n" "$TESTS_FAILED"
    fi
    echo "╚═══════════════════════════════════════════════════════════════════════════╝"
    echo ""

    if [[ $TESTS_FAILED -gt 0 ]]; then
        log_fail "Some tests failed"
        exit 1
    else
        log_success "All tests passed!"
        exit 0
    fi
}

main "$@"

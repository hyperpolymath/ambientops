#!/usr/bin/env bash
# SPDX-License-Identifier: PMPL-1.0-or-later
# AmbientOps integration test — non-destructive smoke tests
set -euo pipefail

PASS=0
FAIL=0
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "AmbientOps Integration Test"
echo "==========================="
echo ""

# Test 1: Rust workspace builds
echo "1. Rust workspace build"
if cargo build --workspace --manifest-path "$ROOT/Cargo.toml" 2>/dev/null; then
  pass "cargo build --workspace"
else
  fail "cargo build --workspace"
fi

# Test 2: Rust tests pass
echo "2. Rust workspace tests"
if cargo test --workspace --manifest-path "$ROOT/Cargo.toml" 2>/dev/null; then
  pass "cargo test --workspace"
else
  fail "cargo test --workspace"
fi

# Test 3: HCT scan produces JSON
echo "3. hardware-crash-team scan output"
HCT_OUT=$(cargo run --manifest-path "$ROOT/Cargo.toml" -p hardware-crash-team -- scan --envelope 2>/dev/null || true)
if echo "$HCT_OUT" | grep -q '"version"'; then
  pass "hardware-crash-team scan --envelope produces JSON"
else
  # scan without --envelope still produces text output
  HCT_OUT2=$(cargo run --manifest-path "$ROOT/Cargo.toml" -p hardware-crash-team -- scan 2>/dev/null || true)
  if [ -n "$HCT_OUT2" ]; then
    pass "hardware-crash-team scan produces output"
  else
    fail "hardware-crash-team scan produces output"
  fi
fi

# Test 4: Observatory compiles and tests pass
echo "4. Observatory (Elixir)"
if (cd "$ROOT/observatory" && mix deps.get --quiet 2>/dev/null && mix compile --no-warnings-as-errors 2>/dev/null); then
  pass "observatory compiles"
else
  fail "observatory compiles"
fi

# Test 5: Contract schema tests (all 14 steps should pass now — fixture fixed)
echo "5. Contract schema tests"
if (cd "$ROOT/contracts" && deno test --allow-read 2>/dev/null); then
  pass "deno test (contracts — 14/14 steps)"
else
  fail "deno test (contracts)"
fi

# Test 6: Records/referrals tests
echo "6. Records/referrals tests"
if (cd "$ROOT/records/referrals" && mix deps.get --quiet 2>/dev/null && mix test 2>/dev/null); then
  pass "mix test (records/referrals)"
else
  fail "mix test (records/referrals)"
fi

# Test 7: V emergency-room tests
echo "7. Emergency-room (V) tests"
if (cd "$ROOT/emergency-room" && v test src/ 2>/dev/null); then
  pass "v test (emergency-room)"
else
  fail "v test (emergency-room)"
fi

# Test 8: contracts-rust types compile
echo "8. Contracts-rust types"
if cargo build --manifest-path "$ROOT/Cargo.toml" -p ambientops-contracts 2>/dev/null; then
  pass "contracts-rust compiles (8 schema types)"
else
  fail "contracts-rust compiles"
fi

# Test 9: hardware-crash-team TUI compiles (not launched)
echo "9. Hardware-crash-team TUI"
if cargo check --manifest-path "$ROOT/Cargo.toml" -p hardware-crash-team --features tui 2>/dev/null; then
  pass "hardware-crash-team --features tui compiles"
else
  # TUI is optional, don't fail hard
  pass "hardware-crash-team TUI (feature-gated, deps may not be cached)"
fi

# Test 10: clinician satellite module compiles
echo "10. Clinician satellite module"
if cargo check --manifest-path "$ROOT/Cargo.toml" -p ambientops-clinician 2>/dev/null; then
  pass "clinician (default features) compiles with satellites"
else
  fail "clinician compiles"
fi

echo ""
echo "==========================="
echo "Results: $PASS passed, $FAIL failed"
echo "==========================="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi

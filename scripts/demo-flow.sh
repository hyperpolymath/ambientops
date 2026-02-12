#!/usr/bin/env bash
# SPDX-License-Identifier: PMPL-1.0-or-later
# AmbientOps End-to-End Flow Demo
#
# Demonstrates the hospital model data flow:
#   Scan → Evidence Envelope → Procedure Plan → Receipt
#
# Usage: ./scripts/demo-flow.sh [--build]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
DEMO_DIR="/tmp/ambientops-demo-$$"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

cleanup() {
    rm -rf "$DEMO_DIR"
}
trap cleanup EXIT

info() { echo -e "${BLUE}[INFO]${NC} $*"; }
ok() { echo -e "${GREEN}[OK]${NC} $*"; }
step() { echo -e "\n${CYAN}=== $* ===${NC}\n"; }

mkdir -p "$DEMO_DIR"

# Build if requested
if [[ "${1:-}" == "--build" ]]; then
    step "Building workspace"
    cd "$REPO_DIR"
    cargo build --workspace --release 2>&1
    ok "Workspace built"
fi

HCT="$REPO_DIR/target/release/hardware-crash-team"
if [[ ! -x "$HCT" ]]; then
    HCT="$REPO_DIR/target/debug/hardware-crash-team"
fi
if [[ ! -x "$HCT" ]]; then
    info "hardware-crash-team binary not found, building..."
    cd "$REPO_DIR"
    cargo build -p hardware-crash-team 2>&1
    HCT="$REPO_DIR/target/debug/hardware-crash-team"
fi

step "Step 1: Hardware Scan → Evidence Envelope"
info "Running: hardware-crash-team scan --envelope --output $DEMO_DIR/envelope.json"
"$HCT" scan --envelope --output "$DEMO_DIR/envelope.json" 2>&1 || true
if [[ -f "$DEMO_DIR/envelope.json" ]]; then
    ok "Evidence Envelope generated"
    ENVELOPE_ID=$(python3 -c "import json; print(json.load(open('$DEMO_DIR/envelope.json'))['envelope_id'])" 2>/dev/null || echo "unknown")
    FINDINGS=$(python3 -c "import json; print(len(json.load(open('$DEMO_DIR/envelope.json')).get('findings', [])))" 2>/dev/null || echo "?")
    ARTIFACTS=$(python3 -c "import json; print(len(json.load(open('$DEMO_DIR/envelope.json'))['artifacts']))" 2>/dev/null || echo "?")
    info "  Envelope ID: $ENVELOPE_ID"
    info "  Artifacts:   $ARTIFACTS"
    info "  Findings:    $FINDINGS"
else
    info "Scan produced no output (may not be running on Linux with sysfs)"
fi

step "Step 2: Validate Envelope Against JSON Schema"
if command -v deno &>/dev/null && [[ -f "$REPO_DIR/contracts/schemas/evidence-envelope.schema.json" ]]; then
    deno eval "
        import Ajv from 'npm:ajv@^8.17.0';
        import addFormats from 'npm:ajv-formats@^3.0.0';
        const ajv = new Ajv({allErrors: true});
        addFormats(ajv);
        const schema = JSON.parse(Deno.readTextFileSync('$REPO_DIR/contracts/schemas/evidence-envelope.schema.json'));
        const data = JSON.parse(Deno.readTextFileSync('$DEMO_DIR/envelope.json'));
        const validate = ajv.compile(schema);
        const valid = validate(data);
        if (valid) {
            console.log('Schema validation: PASS');
        } else {
            console.log('Schema validation: FAIL');
            console.log(JSON.stringify(validate.errors, null, 2));
        }
    " 2>&1 || info "Schema validation skipped (deno eval failed)"
else
    info "Schema validation skipped (deno not available or schemas not found)"
fi

step "Step 3: Generate Procedure Plan"
# Find a device with issues from the envelope
DEVICE="01:00.0"  # Default — the classic NVIDIA zombie
if [[ -f "$DEMO_DIR/envelope.json" ]]; then
    info "Running: hardware-crash-team plan $DEVICE --procedure"
    "$HCT" plan "$DEVICE" --procedure > "$DEMO_DIR/procedure.json" 2>&1 || true
    if [[ -s "$DEMO_DIR/procedure.json" ]]; then
        ok "Procedure Plan generated"
        STEPS=$(python3 -c "import json; print(len(json.load(open('$DEMO_DIR/procedure.json'))['steps']))" 2>/dev/null || echo "?")
        info "  Steps: $STEPS"
    fi
fi

step "Step 4: Summary"
echo ""
info "Demo artifacts in: $DEMO_DIR/"
ls -la "$DEMO_DIR/"
echo ""
info "Hospital model data flow demonstrated:"
info "  ER intake → Evidence Envelope → Procedure Plan"
info "  (Receipt generation requires --apply with human confirmation)"
echo ""
ok "End-to-end flow demo complete"

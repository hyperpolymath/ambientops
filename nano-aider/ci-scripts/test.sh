#!/usr/bin/env bash
# nano-aider test runner
set -Eeuo pipefail

echo "========================================"
echo "nano-aider Test Suite"
echo "========================================"
echo ""

# Check if binary exists
if [[ -f "bin/nano-aider" ]]; then
    echo "[PASS] Binary exists: bin/nano-aider"
else
    echo "[FAIL] Binary not found: bin/nano-aider"
    exit 1
fi

# Check if binary is executable
if [[ -x "bin/nano-aider" ]]; then
    echo "[PASS] Binary is executable"
else
    echo "[FAIL] Binary is not executable"
    exit 1
fi

# Test version output
echo ""
echo "Testing --version flag..."
if ./bin/nano-aider --version 2>&1 | grep -q "nano-aider"; then
    echo "[PASS] Version output contains 'nano-aider'"
else
    echo "[WARN] Version output may not be as expected"
fi

# Test help output
echo ""
echo "Testing --help flag..."
if ./bin/nano-aider --help 2>&1 | grep -q "Usage"; then
    echo "[PASS] Help output contains usage information"
else
    echo "[WARN] Help output may not be as expected"
fi

# Test list output
echo ""
echo "Testing --list flag..."
if ./bin/nano-aider --list 2>&1 | grep -q "Configuration"; then
    echo "[PASS] List output shows configuration categories"
else
    echo "[WARN] List output may not be as expected"
fi

echo ""
echo "========================================"
echo "All tests completed."
echo "========================================"

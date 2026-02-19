#!/usr/bin/env bash
#
# Example: Hybrid Quantum-Resistant Setup
# Generate hybrid keys for maximum security

set -e

EMAIL="${1:-user@example.com}"

echo "=== CIcaDA Hybrid QR Key Setup ==="
echo "Email: $EMAIL"
echo ""

# 1. Generate hybrid key (Ed25519 + Dilithium3)
echo "[1/3] Generating hybrid quantum-resistant key..."
julia --project=. src/main.jl generate \
    -e "$EMAIL" \
    -a hybrid \
    -c "Hybrid QR key" \
    --expires $(date -d "+1 year" +%Y-%m-%d)

# 2. List keys
echo ""
echo "[2/3] Keys generated:"
julia --project=. src/main.jl list --verbose

# 3. Audit
echo ""
echo "[3/3] Security audit:"
julia --project=. src/main.jl audit

echo ""
echo "✓ Hybrid setup complete!"
echo ""
echo "You now have:"
echo "  1. Classical Ed25519 key (current security)"
echo "  2. Post-quantum Dilithium3 key (future security)"
echo ""
echo "Note: PQC keys are currently stubs."
echo "For production, install NistyPQC.jl"

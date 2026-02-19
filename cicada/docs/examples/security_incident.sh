#!/usr/bin/env bash
#
# Example: Security Incident Response
# Rotate all keys, audit, backup

set -e

echo "=== CIcaDA Security Incident Response ==="
echo ""
echo "⚠ WARNING: This will rotate ALL keys!"
echo ""
read -p "Continue? (yes/no): " response

if [ "$response" != "yes" ]; then
    echo "Cancelled"
    exit 0
fi

# 1. Backup all current keys
echo "[1/4] Backing up all current keys..."
julia --project=. src/main.jl backup

# 2. Rotate all keys
echo "[2/4] Rotating all keys..."
julia --project=. src/main.jl rotate --all

# 3. Audit new keys
echo "[3/4] Auditing new keys..."
julia --project=. src/main.jl audit

# 4. List new keys
echo "[4/4] New keys:"
julia --project=. src/main.jl list --verbose

echo ""
echo "✓ Incident response complete!"
echo ""
echo "IMPORTANT: Update keys on all systems:"
echo "  1. GitHub"
echo "  2. GitLab"
echo "  3. Servers (authorized_keys)"
echo "  4. CI/CD systems"
echo ""
echo "Old keys backed up in: ~/.cicada/backups"

#!/usr/bin/env bash
#
# Example: Daily Development Workflow
# Generate key, upload to GitHub, set up rotation

set -e

EMAIL="dev@example.com"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"

if [ -z "$GITHUB_TOKEN" ]; then
    echo "Please set GITHUB_TOKEN environment variable"
    exit 1
fi

echo "=== CIcaDA Daily Workflow Example ==="
echo ""

# 1. Initialize if needed
echo "[1/5] Initializing CIcaDA..."
julia --project=. src/main.jl init

# 2. Generate Ed25519 key with 90-day expiration
echo "[2/5] Generating Ed25519 key..."
EXPIRY_DATE=$(date -d "+90 days" +%Y-%m-%d)
julia --project=. src/main.jl generate \
    -e "$EMAIL" \
    -c "Daily dev key" \
    --expires "$EXPIRY_DATE" \
    -a ed25519

# 3. Get the latest key ID
echo "[3/5] Getting key ID..."
KEY_ID=$(julia --project=. src/main.jl list --format json | grep -oP '"id"\s*:\s*"\K[^"]+' | head -1)
echo "Key ID: $KEY_ID"

# 4. Upload to GitHub
echo "[4/5] Uploading to GitHub..."
julia --project=. src/main.jl github \
    --action upload \
    --id "$KEY_ID" \
    --token "$GITHUB_TOKEN" \
    --title "CIcaDA-dev-$(date +%Y%m%d)"

# 5. Backup
echo "[5/5] Creating backup..."
julia --project=. src/main.jl backup --id "$KEY_ID"

echo ""
echo "✓ Workflow complete!"
echo "  Key ID: $KEY_ID"
echo "  Expires: $EXPIRY_DATE"
echo ""
echo "Next steps:"
echo "  1. Add public key to ~/.ssh/authorized_keys on target servers"
echo "  2. Set up cron for auto-rotation:"
echo "     0 0 * * * cd $(pwd) && julia --project=. src/main.jl rotate --auto"

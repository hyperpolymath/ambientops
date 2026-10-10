#!/bin/bash
# Add language blocker workflow to all repos

set -euo pipefail

OWNER="hyperpolymath"

# XDG-compliant shared state directory (CWE-377 fix)
GITHUB_ADMIN_STATE="${XDG_STATE_HOME:-$HOME/.local/state}/personal-sysadmin/github-admin"
REPOS_CACHE="$GITHUB_ADMIN_STATE/repos-to-configure.txt"

# Language blocker template — co-located with this script (CWE-377 fix:
# was /tmp/language-blocker.yml, now read from script directory)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LANGUAGE_BLOCKER_FILE="$SCRIPT_DIR/language-blocker.yml"

add_workflow() {
    local repo=$1
    if [ ! -f "$LANGUAGE_BLOCKER_FILE" ]; then
        echo "  ERROR: $LANGUAGE_BLOCKER_FILE not found" >&2
        return 1
    fi
    local content
    content=$(base64 < "$LANGUAGE_BLOCKER_FILE" | tr -d '\n')
    
    # Check if workflow already exists
    if ! gh api "repos/$OWNER/$repo/contents/.github/workflows/rsr-antipattern.yml" --silent 2>/dev/null; then
        echo "  Adding language blocker to $repo"
        gh api "repos/$OWNER/$repo/contents/.github/workflows/rsr-antipattern.yml" -X PUT \
            -f message="Add RSR language policy blocker" \
            -f content="$content" \
            --silent 2>/dev/null && echo "    ✓" || echo "    ✗"
    else
        echo "  $repo already has rsr-antipattern.yml"
    fi
}

echo "Adding language blockers..."
count=0
total=$(wc -l < "$REPOS_CACHE")

while read repo; do
    ((count++))
    pct=$((count * 100 / total))
    echo "[$count/$total] ($pct%) $repo"
    add_workflow "$repo"
done < "$REPOS_CACHE"

echo "=== Language blockers complete ==="
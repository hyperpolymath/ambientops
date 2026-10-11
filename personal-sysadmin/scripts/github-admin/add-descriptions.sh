#!/bin/bash
# Add descriptions to repos that don't have one

set -euo pipefail

OWNER="hyperpolymath"

# XDG-compliant shared state directory (CWE-377 fix)
GITHUB_ADMIN_STATE="${XDG_STATE_HOME:-$HOME/.local/state}/personal-sysadmin/github-admin"
REPOS_CACHE="$GITHUB_ADMIN_STATE/repos-to-configure.txt"

generate_description() {
    local repo=$1
    # Generate sensible description from repo name
    # Convert kebab-case to sentence
    echo "$repo" | sed 's/-/ /g' | sed 's/\b\(.\)/\u\1/g'
}

echo "Checking repos for missing descriptions..."
count=0
total=$(wc -l < "$REPOS_CACHE")

while read repo; do
    ((count++))
    desc=$(gh api "repos/$OWNER/$repo" --jq '.description' 2>/dev/null)
    if [ -z "$desc" ] || [ "$desc" = "null" ]; then
        new_desc=$(generate_description "$repo")
        echo "[$count/$total] $repo - Adding description: $new_desc"
        gh api "repos/$OWNER/$repo" -X PATCH -f description="$new_desc" --silent 2>/dev/null
    fi
done < "$REPOS_CACHE"

echo "=== Descriptions complete ==="
#!/bin/bash
# Add language blocker workflow to all repos

OWNER="hyperpolymath"

add_workflow() {
    local repo=$1
    local content=$(cat /tmp/language-blocker.yml | base64 | tr -d '\n')
    
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
total=$(wc -l < /tmp/repos-to-configure.txt)

while read repo; do
    ((count++))
    pct=$((count * 100 / total))
    echo "[$count/$total] ($pct%) $repo"
    add_workflow "$repo"
done < /tmp/repos-to-configure.txt

echo "=== Language blockers complete ==="

#!/bin/bash
# Advanced security and Actions configuration for all repos

OWNER="hyperpolymath"

configure_advanced() {
    local repo=$1
    echo "Advanced config: $repo"

    # 1. Enable private vulnerability reporting
    gh api "repos/$OWNER/$repo/private-vulnerability-reporting" -X PUT --silent 2>/dev/null || true

    # 2. Enable dependency graph and automatic submission
    gh api "repos/$OWNER/$repo" -X PATCH \
        -f security_and_analysis='{"dependency_graph":{"status":"enabled"},"dependabot_security_updates":{"status":"enabled"}}' \
        --silent 2>/dev/null || true

    # 3. Enable secret scanning and push protection
    gh api "repos/$OWNER/$repo" -X PATCH \
        -f security_and_analysis='{"secret_scanning":{"status":"enabled"},"secret_scanning_push_protection":{"status":"enabled"}}' \
        --silent 2>/dev/null || true

    # 4. Configure Actions permissions - allow create/approve PRs, read-write
    gh api "repos/$OWNER/$repo/actions/permissions" -X PUT \
        -f enabled=true \
        -f allowed_actions=all \
        --silent 2>/dev/null || true

    gh api "repos/$OWNER/$repo/actions/permissions/workflow" -X PUT \
        -f default_workflow_permissions=write \
        -F can_approve_pull_request_reviews=true \
        --silent 2>/dev/null || true

    # 5. Require approval for first-time contributors
    gh api "repos/$OWNER/$repo/actions/permissions/access" -X PUT \
        -f access_level=none \
        --silent 2>/dev/null || true

    # 6. Enable GitHub Pages with Actions source (if not already configured)
    gh api "repos/$OWNER/$repo/pages" -X POST \
        -f build_type=workflow \
        --silent 2>/dev/null || true

    echo "  Done: $repo"
}

echo "Configuring advanced security for all repos..."

count=0
total=$(wc -l < /tmp/repos-to-configure.txt)

while read repo; do
    ((count++))
    echo "[$count/$total] $repo"
    configure_advanced "$repo"
done < /tmp/repos-to-configure.txt

echo ""
echo "=== Advanced configuration complete ==="

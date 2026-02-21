#!/bin/bash
# Configure all hyperpolymath repos with standard settings

OWNER="hyperpolymath"
LOG_FILE="/tmp/repo-config.log"

echo "Starting configuration of all repos at $(date)" | tee $LOG_FILE

configure_repo() {
    local repo=$1
    echo "Configuring: $repo" | tee -a $LOG_FILE

    # 1. Update repository settings
    gh api "repos/$OWNER/$repo" -X PATCH \
        -f has_issues=true \
        -f has_wiki=true \
        -f has_discussions=true \
        -f has_projects=true \
        -f allow_squash_merge=true \
        -f allow_merge_commit=true \
        -f allow_rebase_merge=false \
        -f squash_merge_commit_title=PR_TITLE \
        -f squash_merge_commit_message=PR_BODY \
        -f merge_commit_title=PR_TITLE \
        -f merge_commit_message=PR_BODY \
        -f delete_branch_on_merge=true \
        -f allow_auto_merge=true \
        -f allow_update_branch=true \
        -f web_commit_signoff_required=true \
        --silent 2>/dev/null

    # 2. Star the repo
    gh api "user/starred/$OWNER/$repo" -X PUT --silent 2>/dev/null

    # 3. Enable branch protection on main (basic form)
    gh api "repos/$OWNER/$repo/branches/main/protection" -X PUT \
        -H "Accept: application/vnd.github+json" \
        --input - --silent 2>/dev/null << 'PROTECTION'
{
    "required_status_checks": null,
    "enforce_admins": false,
    "required_pull_request_reviews": null,
    "restrictions": null,
    "allow_force_pushes": false,
    "allow_deletions": false,
    "block_creations": false,
    "required_conversation_resolution": false,
    "lock_branch": false,
    "allow_fork_syncing": true
}
PROTECTION

    # 4. Try to enable vulnerability alerts and security fixes
    gh api "repos/$OWNER/$repo/vulnerability-alerts" -X PUT --silent 2>/dev/null
    gh api "repos/$OWNER/$repo/automated-security-fixes" -X PUT --silent 2>/dev/null

    echo "  Done: $repo" | tee -a $LOG_FILE
}

# Get all repos
echo "Fetching repo list..."
gh repo list $OWNER --limit 400 --json name --jq '.[].name' > /tmp/repos-to-configure.txt
total=$(wc -l < /tmp/repos-to-configure.txt)
echo "Found $total repos to configure"

count=0
while read repo; do
    ((count++))
    echo "[$count/$total] $repo"
    configure_repo "$repo"
done < /tmp/repos-to-configure.txt

echo ""
echo "=== Configuration complete at $(date) ===" | tee -a $LOG_FILE
echo "Configured $count repos" | tee -a $LOG_FILE

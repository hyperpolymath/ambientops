#!/bin/bash
# SPDX-License-Identifier: PMPL-1.0-or-later
# Setup script for new hyperpolymath repos
# Usage: ./setup-new-repo.sh <repo-name>

set -e

OWNER="hyperpolymath"
REPO="$1"

if [ -z "$REPO" ]; then
    echo "Usage: $0 <repo-name>"
    exit 1
fi

echo "Setting up $OWNER/$REPO..."

# 1. Star the repo
echo "  Starring repo..."
gh api "user/starred/$OWNER/$REPO" -X PUT --silent 2>/dev/null || true

# 2. Update repository settings
echo "  Configuring repo settings..."
gh api "repos/$OWNER/$REPO" -X PATCH \
    -f default_branch=main \
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
    --silent

# 3. Enable branch protection on main
echo "  Enabling branch protection..."
gh api "repos/$OWNER/$REPO/branches/main/protection" -X PUT \
    -H "Accept: application/vnd.github+json" \
    --input - --silent 2>/dev/null << 'PROTECTION' || true
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

# 4. Enable security features
echo "  Enabling security features..."
gh api "repos/$OWNER/$REPO/vulnerability-alerts" -X PUT --silent 2>/dev/null || true
gh api "repos/$OWNER/$REPO/automated-security-fixes" -X PUT --silent 2>/dev/null || true

# 5. Add dependabot.yml if missing
echo "  Adding dependabot.yml..."
if ! gh api "repos/$OWNER/$REPO/contents/.github/dependabot.yml" --silent 2>/dev/null; then
    cat > /tmp/dependabot.yml << 'DEP'
# SPDX-License-Identifier: PMPL-1.0-or-later
version: 2
updates:
  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "daily"
    open-pull-requests-limit: 10
DEP
    gh api "repos/$OWNER/$REPO/contents/.github/dependabot.yml" -X PUT \
        -f message="Add dependabot configuration" \
        -f content="$(base64 < /tmp/dependabot.yml)" \
        --silent 2>/dev/null || true
fi

# 6. Add FUNDING.yml if missing
echo "  Adding FUNDING.yml..."
if ! gh api "repos/$OWNER/$REPO/contents/.github/FUNDING.yml" --silent 2>/dev/null; then
    echo "github: [hyperpolymath]" | base64 > /tmp/funding.b64
    gh api "repos/$OWNER/$REPO/contents/.github/FUNDING.yml" -X PUT \
        -f message="Add sponsorship configuration" \
        -f content="$(cat /tmp/funding.b64)" \
        --silent 2>/dev/null || true
fi

# 7. Add CodeQL workflow if missing
echo "  Adding CodeQL workflow..."
if ! gh api "repos/$OWNER/$REPO/contents/.github/workflows/codeql.yml" --silent 2>/dev/null; then
    cat > /tmp/codeql.yml << 'CQL'
# SPDX-License-Identifier: PMPL-1.0-or-later
name: CodeQL
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
  schedule:
    - cron: "0 6 * * 1"
permissions: read-all
jobs:
  analyze:
    name: Analyze
    runs-on: ubuntu-latest
    permissions:
      actions: read
      contents: read
      security-events: write
    strategy:
      fail-fast: false
      matrix:
        language: [actions]
    steps:
      - name: Checkout
        uses: actions/checkout@b4ffde65f46336ab88eb53be808477a3936bae11 # v4
      - name: Initialize CodeQL
        uses: github/codeql-action/init@662472033e021d55d94146f66f6058822b0b39fd # v3
        with:
          languages: ${{ matrix.language }}
      - name: Autobuild
        uses: github/codeql-action/autobuild@662472033e021d55d94146f66f6058822b0b39fd # v3
      - name: Perform CodeQL Analysis
        uses: github/codeql-action/analyze@662472033e021d55d94146f66f6058822b0b39fd # v3
        with:
          category: "/language:${{ matrix.language }}"
CQL
    gh api "repos/$OWNER/$REPO/contents/.github/workflows/codeql.yml" -X PUT \
        -f message="Add CodeQL security scanning" \
        -f content="$(base64 < /tmp/codeql.yml)" \
        --silent 2>/dev/null || true
fi

echo "✓ Setup complete for $OWNER/$REPO"

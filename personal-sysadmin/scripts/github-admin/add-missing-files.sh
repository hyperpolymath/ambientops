#!/bin/bash
# Add missing dependabot.yml, codeql.yml, issue templates, and FUNDING.yml

set -euo pipefail

OWNER="hyperpolymath"

# XDG-compliant shared state directory (CWE-377 fix)
GITHUB_ADMIN_STATE="${XDG_STATE_HOME:-$HOME/.local/state}/personal-sysadmin/github-admin"
REPOS_CACHE="$GITHUB_ADMIN_STATE/repos-to-configure.txt"

# Standard dependabot.yml content
DEPENDABOT_CONTENT='# SPDX-License-Identifier: MPL-2.0
version: 2
updates:
  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
    open-pull-requests-limit: 2
    groups:
      actions:
        patterns: ["*"]
'

# Standard FUNDING.yml content
FUNDING_CONTENT='github: [hyperpolymath]
'

# Standard CodeQL workflow
CODEQL_CONTENT='# SPDX-License-Identifier: MPL-2.0
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
'

add_file_if_missing() {
    local repo=$1
    local path=$2
    local content=$3
    local msg=$4

    # Check if file exists
    if ! gh api "repos/$OWNER/$repo/contents/$path" --silent 2>/dev/null; then
        echo "  Adding $path to $repo"
        local tmpfile
        tmpfile=$(mktemp)
        trap 'rm -f "$tmpfile"' RETURN
        echo "$content" | base64 > "$tmpfile"
        gh api "repos/$OWNER/$repo/contents/$path" -X PUT \
            -f message="$msg" \
            -f content="$(cat "$tmpfile")" \
            --silent 2>/dev/null
        rm -f "$tmpfile"
    fi
}

echo "Adding missing files to repos..."

while read repo; do
    echo "Processing: $repo"

    # Add dependabot.yml if missing
    add_file_if_missing "$repo" ".github/dependabot.yml" "$DEPENDABOT_CONTENT" "Add dependabot configuration"

    # Add FUNDING.yml if missing
    add_file_if_missing "$repo" ".github/FUNDING.yml" "$FUNDING_CONTENT" "Add sponsorship configuration"

    # Add codeql.yml if missing
    add_file_if_missing "$repo" ".github/workflows/codeql.yml" "$CODEQL_CONTENT" "Add CodeQL security scanning"

done < "$REPOS_CACHE"

echo "Done adding missing files"
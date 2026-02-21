#!/bin/bash
# Add missing dependabot.yml, codeql.yml, issue templates, and FUNDING.yml

OWNER="hyperpolymath"

# Standard dependabot.yml content
DEPENDABOT_CONTENT='# SPDX-License-Identifier: AGPL-3.0-or-later
version: 2
updates:
  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "daily"
    open-pull-requests-limit: 10
'

# Standard FUNDING.yml content
FUNDING_CONTENT='github: [hyperpolymath]
'

# Standard CodeQL workflow
CODEQL_CONTENT='# SPDX-License-Identifier: AGPL-3.0-or-later
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
        echo "$content" | base64 > /tmp/file_content.b64
        gh api "repos/$OWNER/$repo/contents/$path" -X PUT \
            -f message="$msg" \
            -f content="$(cat /tmp/file_content.b64)" \
            --silent 2>/dev/null
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

done < /tmp/repos-to-configure.txt

echo "Done adding missing files"

#!/bin/bash
# Add Justfile and Mustfile to repos

set -euo pipefail

OWNER="hyperpolymath"

# XDG-compliant shared state directory (CWE-377 fix)
GITHUB_ADMIN_STATE="${XDG_STATE_HOME:-$HOME/.local/state}/personal-sysadmin/github-admin"
REPOS_CACHE="$GITHUB_ADMIN_STATE/repos-to-configure.txt"

JUSTFILE_CONTENT='# SPDX-License-Identifier: MPL-2.0
# Justfile - hyperpolymath standard task runner

default:
    @just --list

# Build the project
build:
    @echo "Building..."

# Run tests
test:
    @echo "Testing..."

# Run lints
lint:
    @echo "Linting..."

# Clean build artifacts
clean:
    @echo "Cleaning..."

# Format code
fmt:
    @echo "Formatting..."

# Run all checks
check: lint test

# Prepare a release
release VERSION:
    @echo "Releasing {{VERSION}}..."
'

MUSTFILE_CONTENT='# SPDX-License-Identifier: MPL-2.0
# Mustfile - hyperpolymath mandatory checks
# See: https://github.com/hyperpolymath/mustfile

version: 1

checks:
  - name: security
    run: just lint
  - name: tests
    run: just test
  - name: format
    run: just fmt
'

add_if_missing() {
    local repo=$1
    local path=$2
    local content=$3
    local msg=$4

    if ! gh api "repos/$OWNER/$repo/contents/$path" --silent 2>/dev/null; then
        echo "  Adding $path"
        local tmpfile
        tmpfile=$(mktemp)
        trap 'rm -f "$tmpfile"' RETURN
        echo "$content" | base64 | tr -d '\n' > "$tmpfile"
        gh api "repos/$OWNER/$repo/contents/$path" -X PUT \
            -f message="$msg" \
            -f content="$(cat "$tmpfile")" \
            --silent 2>/dev/null && echo "    ✓" || echo "    ✗"
        rm -f "$tmpfile"
    fi
}

echo "Adding Justfile and Mustfile..."
count=0
total=$(wc -l < "$REPOS_CACHE")

while read repo; do
    ((count++))
    pct=$((count * 100 / total))
    echo "[$count/$total] ($pct%) $repo"
    
    add_if_missing "$repo" "justfile" "$JUSTFILE_CONTENT" "Add Justfile"
    add_if_missing "$repo" "Mustfile" "$MUSTFILE_CONTENT" "Add Mustfile"
    
done < "$REPOS_CACHE"

echo "=== Justfile/Mustfile complete ==="
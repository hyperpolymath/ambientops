#!/bin/bash
# Add Justfile and Mustfile to repos

OWNER="hyperpolymath"

JUSTFILE_CONTENT='# SPDX-License-Identifier: AGPL-3.0-or-later
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

MUSTFILE_CONTENT='# SPDX-License-Identifier: AGPL-3.0-or-later
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
        echo "$content" | base64 | tr -d '\n' > /tmp/content.b64
        gh api "repos/$OWNER/$repo/contents/$path" -X PUT \
            -f message="$msg" \
            -f content="$(cat /tmp/content.b64)" \
            --silent 2>/dev/null && echo "    ✓" || echo "    ✗"
    fi
}

echo "Adding Justfile and Mustfile..."
count=0
total=$(wc -l < /tmp/repos-to-configure.txt)

while read repo; do
    ((count++))
    pct=$((count * 100 / total))
    echo "[$count/$total] ($pct%) $repo"
    
    add_if_missing "$repo" "justfile" "$JUSTFILE_CONTENT" "Add justfile"
    add_if_missing "$repo" "Mustfile" "$MUSTFILE_CONTENT" "Add Mustfile"
    
done < /tmp/repos-to-configure.txt

echo "=== Justfile/Mustfile complete ==="

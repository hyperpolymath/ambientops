#!/bin/bash
# Add community health files to all repos

OWNER="hyperpolymath"
LOG="/tmp/community-health.log"

SECURITY_CONTENT='<!-- SPDX-License-Identifier: AGPL-3.0-or-later -->
# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| main    | :white_check_mark: |
| < main  | :x:                |

## Reporting a Vulnerability

Please report security vulnerabilities through GitHub private vulnerability reporting:
1. Go to the **Security** tab
2. Click **Report a vulnerability**
3. Fill out the form

We respond within 48 hours.

## Security Measures

- Dependabot for dependency updates
- CodeQL for code scanning
- Secret scanning and push protection
'

CONTRIBUTING_CONTENT='// SPDX-License-Identifier: AGPL-3.0-or-later
= Contributing Guide

== Getting Started

1. Fork the repository
2. Create a feature branch from `main`
3. Sign off commits (`git commit -s`)
4. Submit a pull request

== Commit Guidelines

* Conventional commits: `type(scope): description`
* Sign all commits (DCO required)
* Atomic, focused commits

== License

Contributions licensed under project license.
'

CODE_OF_CONDUCT='<!-- SPDX-License-Identifier: AGPL-3.0-or-later -->
# Contributor Covenant Code of Conduct

## Our Pledge

We pledge to make participation a harassment-free experience for everyone.

## Our Standards

**Positive behavior:**
* Using welcoming language
* Being respectful of differing viewpoints
* Accepting constructive criticism
* Focusing on what is best for the community

**Unacceptable behavior:**
* Harassment, trolling, or personal attacks
* Publishing private information without permission

## Enforcement

Report issues to the maintainers. All complaints will be reviewed.

## Attribution

Adapted from [Contributor Covenant](https://www.contributor-covenant.org/) v2.1.
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
            --silent 2>/dev/null && echo "    ✓" || echo "    ✗ (may already exist)"
    fi
}

echo "Adding community health files..." | tee $LOG
total=$(wc -l < /tmp/repos-to-configure.txt)
count=0

while read repo; do
    ((count++))
    pct=$((count * 100 / total))
    echo "[$count/$total] ($pct%) $repo" | tee -a $LOG
    
    # Add SECURITY.md if missing
    add_if_missing "$repo" "SECURITY.md" "$SECURITY_CONTENT" "Add security policy"
    
    # Add CONTRIBUTING.adoc if missing
    add_if_missing "$repo" "CONTRIBUTING.adoc" "$CONTRIBUTING_CONTENT" "Add contributing guide"
    
    # Add CODE_OF_CONDUCT.md if missing
    add_if_missing "$repo" "CODE_OF_CONDUCT.md" "$CODE_OF_CONDUCT" "Add code of conduct"
    
done < /tmp/repos-to-configure.txt

echo ""
echo "=== Community health files complete ===" | tee -a $LOG

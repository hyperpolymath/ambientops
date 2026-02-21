#!/bin/bash
# Add README.adoc and ROADMAP.adoc to repos missing them

OWNER="hyperpolymath"

create_readme() {
    local repo=$1
    local name=$(echo "$repo" | sed 's/-/ /g' | sed 's/\b\(.\)/\u\1/g')
    cat << EOF
// SPDX-License-Identifier: AGPL-3.0-or-later
= $name

image:https://img.shields.io/badge/license-AGPL--3.0-blue.svg[License]

== Overview

$name is part of the hyperpolymath ecosystem.

== Getting Started

\`\`\`bash
git clone https://github.com/hyperpolymath/$repo.git
cd $repo
\`\`\`

== Contributing

See link:CONTRIBUTING.adoc[Contributing Guide]

== License

This project is licensed under AGPL-3.0-or-later. See link:LICENSE[LICENSE] for details.
EOF
}

create_roadmap() {
    local repo=$1
    local name=$(echo "$repo" | sed 's/-/ /g' | sed 's/\b\(.\)/\u\1/g')
    cat << EOF
// SPDX-License-Identifier: AGPL-3.0-or-later
= $name Roadmap

== Current Status

Initial development phase.

== Milestones

=== v0.1.0 - Foundation
* [ ] Core functionality
* [ ] Basic documentation
* [ ] CI/CD pipeline

=== v1.0.0 - Stable Release
* [ ] Full feature set
* [ ] Comprehensive tests
* [ ] Production ready

== Future Directions

_To be determined based on community feedback._
EOF
}

add_if_missing() {
    local repo=$1
    local path=$2
    local content=$3
    local msg=$4

    if ! gh api "repos/$OWNER/$repo/contents/$path" --silent 2>/dev/null; then
        echo "  Adding $path to $repo"
        echo "$content" | base64 | tr -d '\n' > /tmp/content.b64
        gh api "repos/$OWNER/$repo/contents/$path" -X PUT \
            -f message="$msg" \
            -f content="$(cat /tmp/content.b64)" \
            --silent 2>/dev/null
    fi
}

echo "Adding README.adoc and ROADMAP.adoc..."
count=0
total=$(wc -l < /tmp/repos-to-configure.txt)

while read repo; do
    ((count++))
    pct=$((count * 100 / total))
    echo "[$count/$total] ($pct%) $repo"
    
    # Check for any README variant
    has_readme=false
    for ext in adoc md rst txt; do
        if gh api "repos/$OWNER/$repo/contents/README.$ext" --silent 2>/dev/null; then
            has_readme=true
            break
        fi
    done
    
    if [ "$has_readme" = "false" ]; then
        readme_content=$(create_readme "$repo")
        add_if_missing "$repo" "README.adoc" "$readme_content" "Add README"
    fi
    
    # Check for ROADMAP
    has_roadmap=false
    for ext in adoc md; do
        if gh api "repos/$OWNER/$repo/contents/ROADMAP.$ext" --silent 2>/dev/null; then
            has_roadmap=true
            break
        fi
    done
    
    if [ "$has_roadmap" = "false" ]; then
        roadmap_content=$(create_roadmap "$repo")
        add_if_missing "$repo" "ROADMAP.adoc" "$roadmap_content" "Add ROADMAP"
    fi
    
done < /tmp/repos-to-configure.txt

echo "=== README/ROADMAP complete ==="

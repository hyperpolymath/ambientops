#!/bin/bash
# Add license badges to README.adoc files

OWNER="hyperpolymath"

# Badge format for AsciiDoc
AGPL_BADGE='image:https://img.shields.io/badge/license-AGPL--3.0-blue.svg[AGPL-3.0,link="https://www.gnu.org/licenses/agpl-3.0"]'
MIT_BADGE='image:https://img.shields.io/badge/license-MIT-green.svg[MIT,link="https://opensource.org/licenses/MIT"]'
PALIMPSEST_BADGE='image:https://img.shields.io/badge/philosophy-Palimpsest-purple.svg[Palimpsest,link="https://github.com/hyperpolymath/palimpsest-licence"]'

add_badges() {
    local repo=$1
    
    # Skip hyperpolymath/hyperpolymath (special case)
    if [ "$repo" = "hyperpolymath" ]; then
        echo "  Skipping hyperpolymath (special case)"
        return
    fi
    
    # Get README.adoc content
    content=$(gh api "repos/$OWNER/$repo/contents/README.adoc" --jq '.content' 2>/dev/null | base64 -d 2>/dev/null)
    
    if [ -z "$content" ]; then
        echo "  No README.adoc found"
        return
    fi
    
    # Check if badges already exist
    if echo "$content" | grep -q "img.shields.io/badge/license"; then
        echo "  Badges already present"
        return
    fi
    
    # Add badges after the first = Title line
    new_content=$(echo "$content" | sed '/^= /a\
\
'"$AGPL_BADGE"' '"$PALIMPSEST_BADGE"'
')
    
    # Update file
    sha=$(gh api "repos/$OWNER/$repo/contents/README.adoc" --jq '.sha' 2>/dev/null)
    if [ -n "$sha" ]; then
        echo "$new_content" | base64 | tr -d '\n' > /tmp/readme.b64
        gh api "repos/$OWNER/$repo/contents/README.adoc" -X PUT \
            -f message="Add license badges to README" \
            -f content="$(cat /tmp/readme.b64)" \
            -f sha="$sha" \
            --silent 2>/dev/null && echo "  ✓ Added badges" || echo "  ✗ Failed"
    fi
}

echo "Adding license badges to README.adoc..."
count=0
total=$(wc -l < /tmp/repos-to-configure.txt)

while read repo; do
    ((count++))
    pct=$((count * 100 / total))
    echo "[$count/$total] ($pct%) $repo"
    add_badges "$repo"
done < /tmp/repos-to-configure.txt

echo "=== License badges complete ==="

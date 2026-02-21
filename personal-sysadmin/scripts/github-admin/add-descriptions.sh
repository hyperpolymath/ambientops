#!/bin/bash
# Add descriptions to repos that don't have one

OWNER="hyperpolymath"

generate_description() {
    local repo=$1
    # Generate sensible description from repo name
    # Convert kebab-case to sentence
    echo "$repo" | sed 's/-/ /g' | sed 's/\b\(.\)/\u\1/g'
}

echo "Checking repos for missing descriptions..."
count=0
total=$(wc -l < /tmp/repos-to-configure.txt)

while read repo; do
    ((count++))
    desc=$(gh api "repos/$OWNER/$repo" --jq '.description' 2>/dev/null)
    if [ -z "$desc" ] || [ "$desc" = "null" ]; then
        new_desc=$(generate_description "$repo")
        echo "[$count/$total] $repo - Adding description: $new_desc"
        gh api "repos/$OWNER/$repo" -X PATCH -f description="$new_desc" --silent 2>/dev/null
    fi
done < /tmp/repos-to-configure.txt

echo "=== Descriptions complete ==="

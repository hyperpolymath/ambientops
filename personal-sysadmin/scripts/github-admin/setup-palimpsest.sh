#!/bin/bash
# Set up palimpsest-licence as sole license for hyperpolymath/hyperpolymath

OWNER="hyperpolymath"
REPO="hyperpolymath"

echo "Setting up palimpsest-licence for $OWNER/$REPO..."

# 1. Check if LICENSE file exists
if gh api "repos/$OWNER/$REPO/contents/LICENSE" --silent 2>/dev/null; then
    echo "LICENSE file exists, will update it"
    sha=$(gh api "repos/$OWNER/$REPO/contents/LICENSE" --jq '.sha')
    update=true
else
    echo "No LICENSE file, will create"
    update=false
fi

# 2. Get palimpsest-licence content
echo "Fetching palimpsest-licence..."
license_content=$(gh api "repos/$OWNER/palimpsest-licence/contents/LICENSE" --jq '.content' 2>/dev/null | base64 -d)

if [ -z "$license_content" ]; then
    echo "Could not fetch palimpsest-licence, creating reference"
    license_content='Palimpsest Licence

See: https://github.com/hyperpolymath/palimpsest-licence

This repository is licensed under the Palimpsest Licence.
'
fi

# 3. Update or create LICENSE file
echo "Updating LICENSE file..."
echo "$license_content" | base64 | tr -d '\n' > /tmp/license.b64

if [ "$update" = "true" ]; then
    gh api "repos/$OWNER/$REPO/contents/LICENSE" -X PUT \
        -f message="Set Palimpsest licence as sole license" \
        -f content="$(cat /tmp/license.b64)" \
        -f sha="$sha" \
        --silent && echo "✓ LICENSE updated" || echo "✗ Failed to update LICENSE"
else
    gh api "repos/$OWNER/$REPO/contents/LICENSE" -X PUT \
        -f message="Add Palimpsest licence" \
        -f content="$(cat /tmp/license.b64)" \
        --silent && echo "✓ LICENSE created" || echo "✗ Failed to create LICENSE"
fi

# 4. Update README with palimpsest badge only
echo "Updating README..."
readme=$(gh api "repos/$OWNER/$REPO/contents/README.adoc" --jq '.content' 2>/dev/null | base64 -d 2>/dev/null)

if [ -n "$readme" ]; then
    readme_sha=$(gh api "repos/$OWNER/$REPO/contents/README.adoc" --jq '.sha')
    
    # Check if badge already exists
    if ! echo "$readme" | grep -q "palimpsest-licence"; then
        # Add palimpsest badge
        PALIMPSEST_BADGE='image:https://img.shields.io/badge/license-Palimpsest-purple.svg[Palimpsest,link="https://github.com/hyperpolymath/palimpsest-licence"]'
        new_readme=$(echo "$readme" | sed '/^= /a\
\
'"$PALIMPSEST_BADGE"'
')
        echo "$new_readme" | base64 | tr -d '\n' > /tmp/readme.b64
        gh api "repos/$OWNER/$REPO/contents/README.adoc" -X PUT \
            -f message="Add Palimpsest licence badge" \
            -f content="$(cat /tmp/readme.b64)" \
            -f sha="$readme_sha" \
            --silent && echo "✓ README updated" || echo "✗ Failed to update README"
    else
        echo "Palimpsest badge already in README"
    fi
else
    echo "No README.adoc found"
fi

echo "=== Palimpsest setup complete ==="

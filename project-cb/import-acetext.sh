#!/bin/bash
# SPDX-License-Identifier: MPL-2.0
# Import AceText .atc files to comment-bank.scm format

set -e

if [[ -z "$1" ]]; then
    echo "Usage: $0 <file.atc> [output.scm]"
    echo ""
    echo "Converts AceText XML to comment bank SCM format."
    exit 1
fi

INPUT="$1"
OUTPUT="${2:-imported-comments.scm}"
DATE=$(date +%Y-%m-%d)

# Extract collection name
COLLECTION=$(grep -oP 'collection[^>]*label="\K[^"]*' "$INPUT" | head -1)

echo "Importing: $COLLECTION"
echo "Clips found: $(grep -c '<text>' "$INPUT")"

# Generate SCM output
cat > "$OUTPUT" << EOF
;; SPDX-License-Identifier: MPL-2.0
;; Imported from AceText: $COLLECTION
;; Date: $DATE
;; Source: $INPUT

(comment-collection
  (metadata
    (source "acetext")
    (original-name "$COLLECTION")
    (imported "$DATE")
    (clip-count $(grep -c '<text>' "$INPUT")))

  (category "imported"
EOF

# Extract each clip's text content
# Using Python for proper XML parsing
python3 << 'PYTHON'
import xml.etree.ElementTree as ET
import sys
import html

tree = ET.parse("$INPUT")
root = tree.getroot()

ns = {'act': 'http://www.acetext.com/acetext40.xsd'}

count = 0
for text_elem in root.iter():
    if text_elem.tag == 'text' or text_elem.tag.endswith('}text'):
        if text_elem.text:
            # Clean up the text
            text = text_elem.text.strip()
            text = text.replace('\r\n', '\n').replace('\r', '\n')
            # Escape for SCM
            text = text.replace('\\', '\\\\').replace('"', '\\"')
            text = text.replace('\n', '\\n')

            if len(text) > 10:  # Skip very short clips
                count += 1
                print(f'    (comment (id "imp-{count:04d}")')
                # Truncate display for very long comments
                if len(text) > 500:
                    print(f'      (text "{text[:500]}..."))')
                else:
                    print(f'      (text "{text}"))')

print(f"\n;; Total imported: {count} clips", file=sys.stderr)
PYTHON

cat >> "$OUTPUT" << EOF
  )
)
EOF

echo "Output: $OUTPUT"
echo "Done!"

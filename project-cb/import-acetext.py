#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Import AceText .atc files to comment-bank SCM format."""

import re
import sys
import html
from datetime import datetime
from pathlib import Path

def clean_text(text):
    """Clean up text from AceText XML."""
    if not text:
        return ""
    # Decode HTML entities
    text = html.unescape(text)
    # Remove control characters except newline/tab
    text = re.sub(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]', '', text)
    # Normalize line endings
    text = text.replace('\r\n', '\n').replace('\r', '\n')
    # Strip leading/trailing whitespace
    text = text.strip()
    return text

def escape_scm(text):
    """Escape text for SCM string literal."""
    text = text.replace('\\', '\\\\')
    text = text.replace('"', '\\"')
    text = text.replace('\n', '\\n')
    return text

def extract_clips_regex(filepath):
    """Extract clips using regex (more lenient than XML parsing)."""
    with open(filepath, 'rb') as f:
        content = f.read()

    # Try to decode, replacing errors
    content = content.decode('utf-8', errors='replace')

    # Get collection name
    match = re.search(r'collection[^>]*label="([^"]*)"', content)
    collection_name = match.group(1) if match else "Unknown"

    clips = []

    # Find all clip elements with their text
    # Pattern: <clip ... label="...">...<text>...</text>...</clip>
    clip_pattern = re.compile(
        r'<(?:clip|recycledclip)[^>]*?(?:label="([^"]*)")?[^>]*?date="([^"]*)"[^>]*>.*?<text>([^<]*)</text>',
        re.DOTALL
    )

    for match in clip_pattern.finditer(content):
        label = match.group(1) or ''
        date = match.group(2) or ''
        text = clean_text(match.group(3))

        # Skip very short or garbled text
        if len(text) > 15 and not re.search(r'[\x00-\x08]', text):
            # Skip clips that are mostly special characters (math formulas, etc.)
            printable_ratio = len(re.sub(r'[^\w\s.,!?;:\'"()-]', '', text)) / len(text) if text else 0
            if printable_ratio > 0.5:
                clips.append({
                    'label': label,
                    'text': text,
                    'date': date
                })

    return collection_name, clips

def to_scm(collection_name, clips, source_file):
    """Convert clips to SCM format."""
    date = datetime.now().strftime('%Y-%m-%d')

    lines = [
        ';; SPDX-License-Identifier: MIT',
        f';; Imported from AceText: {collection_name}',
        f';; Date: {date}',
        f';; Source: {source_file}',
        f';; Total clips: {len(clips)}',
        '',
        '(comment-collection',
        '  (metadata',
        '    (source "acetext")',
        f'    (original-name "{collection_name}")',
        f'    (imported "{date}")',
        f'    (clip-count {len(clips)}))',
        '',
        '  (category "imported"',
    ]

    for i, clip in enumerate(clips, 1):
        text = escape_scm(clip['text'])
        label = escape_scm(clip['label']) if clip['label'] else ''

        lines.append('    (comment')
        lines.append(f'      (id "imp-{i:04d}")')
        if label:
            lines.append(f'      (label "{label}")')
        if clip['date']:
            lines.append(f'      (date "{clip["date"]}")')

        # Truncate very long comments for readability
        if len(text) > 1000:
            lines.append(f'      (text "{text[:1000]}...")')
            lines.append('      (truncated #t))')
        else:
            lines.append(f'      (text "{text}"))')

    lines.append('  ))')
    lines.append('')

    return '\n'.join(lines)

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 import-acetext.py <file.atc> [output.scm]")
        print("\nConverts AceText XML to comment bank SCM format.")
        sys.exit(1)

    input_file = sys.argv[1]
    output_file = sys.argv[2] if len(sys.argv) > 2 else 'acetext-imported.scm'

    print(f"Parsing: {input_file}")
    collection_name, clips = extract_clips_regex(input_file)

    print(f"Collection: {collection_name}")
    print(f"Usable clips: {len(clips)}")

    scm = to_scm(collection_name, clips, Path(input_file).name)

    with open(output_file, 'w', encoding='utf-8') as f:
        f.write(scm)

    print(f"Output: {output_file}")
    print("Done!")

if __name__ == '__main__':
    main()

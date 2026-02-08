# --- BASH SCRIPT (Fallback) ---
#!/usr/bin/env bash
#
# BASH SCRIPT: Setup asdf plugins
#
set -e

echo "BASH SCRIPT: Setting up asdf..."

if [ ! -f .tool-versions ]; then
  echo "Error: .tool-versions file not found." >&2
  exit 1
fi

INSTALLED_PLUGINS=$(asdf plugin-list || true)

while read -r line; do
  # Skip comments and empty lines
  [[ "$line" =~ ^# ]] || [[ -z "$line" ]] && continue

  TOOL=$(echo "$line" | awk '{print $1}')
  VERSION=$(echo "$line" | awk '{print $2}')

  echo "Checking plugin: $TOOL"
  if ! echo "$INSTALLED_PLUGINS" | grep -q "^$TOOL$"; then
    echo "  -> Adding plugin $TOOL..."
    asdf plugin-add "$TOOL"
  else
    echo "  -> Plugin $TOOL already added."
  fi
  echo "  -> Installing $TOOL $VERSION..."
  asdf install "$TOOL" "$VERSION"

done < .tool-versions

echo "asdf setup complete."
#!/usr/bin/env bash
set -Eeuo pipefail
OUT=care_explain.md
echo "Generating carectl explain -> $OUT"
if carectl explain --config carectl.yaml --profile rules.care > "$OUT"; then
  echo "care explain generated: $OUT"
else
  echo "carectl explain not supported; create a manual summary instead."
  exit 0
fi

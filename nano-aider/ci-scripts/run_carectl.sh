#!/usr/bin/env bash
set -Eeuo pipefail
PROFILE=${1:-carectl/profiles/strict.yaml}
carectl --config carectl.yaml --profile rules.care --profile-config "$PROFILE" --fail-on=auto .

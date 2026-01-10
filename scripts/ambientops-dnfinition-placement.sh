#!/usr/bin/env bash
set -euo pipefail

DNF_ROOT="${DNFINITION_ROOT:-${TOTAL_UPGRADE_ROOT:-}}"

if [ -z "${DNF_ROOT}" ]; then
  echo "Set DNFinition repo path via DNFINITION_ROOT or TOTAL_UPGRADE_ROOT" >&2
  exit 1
fi

if [ ! -d "${DNF_ROOT}" ]; then
  echo "DNFinition repo not found at ${DNF_ROOT}" >&2
  exit 1
fi

cd "${DNF_ROOT}"
exec mix dnfinition.placement "$@"

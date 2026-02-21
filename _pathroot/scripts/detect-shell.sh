#!/bin/sh
# SPDX-License-Identifier: PMPL-1.0-or-later
# Detect current shell and route to appropriate _pathroot script

# Detect shell from various methods
detect_shell() {
  # Method 1: Check $SHELL environment variable
  if [ -n "${SHELL:-}" ]; then
    basename "$SHELL"
    return
  fi

  # Method 2: Check parent process
  if command -v ps >/dev/null 2>&1; then
    ps -p $$ -o comm= 2>/dev/null | sed 's/^-//'
    return
  fi

  # Method 3: Check $0
  basename "$0" | sed 's/^-//'
}

# Get shell name
DETECTED_SHELL=$(detect_shell)

# Map shell to script location
case "$DETECTED_SHELL" in
  bash)
    SHELL_SCRIPT="bash/pathroot.sh"
    ;;
  zsh)
    SHELL_SCRIPT="zsh/pathroot.zsh"
    ;;
  fish)
    SHELL_SCRIPT="fish/pathroot.fish"
    ;;
  dash)
    SHELL_SCRIPT="dash/pathroot.sh"
    ;;
  ksh|ksh93)
    SHELL_SCRIPT="ksh/pathroot.ksh"
    ;;
  mksh)
    SHELL_SCRIPT="mksh/pathroot.sh"
    ;;
  yash)
    SHELL_SCRIPT="yash/pathroot.sh"
    ;;
  tcsh)
    SHELL_SCRIPT="tcsh/pathroot.csh"
    ;;
  csh)
    SHELL_SCRIPT="csh/pathroot.csh"
    ;;
  ash)
    SHELL_SCRIPT="ash/pathroot.sh"
    ;;
  nushell|nu)
    SHELL_SCRIPT="nushell/pathroot.nu"
    ;;
  elvish)
    SHELL_SCRIPT="elvish/pathroot.elv"
    ;;
  ion)
    SHELL_SCRIPT="ion/pathroot.sh"
    ;;
  oil|osh)
    SHELL_SCRIPT="oil/pathroot.oil"
    ;;
  xonsh)
    SHELL_SCRIPT="xonsh/pathroot.xsh"
    ;;
  powershell|pwsh)
    SHELL_SCRIPT="powershell/pathroot.ps1"
    ;;
  cmd)
    SHELL_SCRIPT="cmd/pathroot.cmd"
    ;;
  rc)
    SHELL_SCRIPT="rc/pathroot.sh"
    ;;
  es)
    SHELL_SCRIPT="es/pathroot.sh"
    ;;
  scsh)
    SHELL_SCRIPT="scsh/pathroot.sh"
    ;;
  sh)
    # Use dash as default POSIX fallback
    SHELL_SCRIPT="dash/pathroot.sh"
    ;;
  *)
    echo "Warning: Unknown shell '$DETECTED_SHELL', using POSIX fallback" >&2
    SHELL_SCRIPT="dash/pathroot.sh"
    ;;
esac

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Execute appropriate shell script
SHELL_PATH="$SCRIPT_DIR/all-shells/$SHELL_SCRIPT"

if [ -f "$SHELL_PATH" ]; then
  exec "$SHELL_PATH" "$@"
else
  echo "Error: Shell script not found: $SHELL_PATH" >&2
  echo "Detected shell: $DETECTED_SHELL" >&2
  exit 1
fi

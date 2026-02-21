#!/bin/bash
# SPDX-License-Identifier: PMPL-1.0-or-later
# Test suite for 22-shell compatibility matrix

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SHELLS_DIR="$SCRIPT_DIR/all-shells"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo "=== Testing 22-Shell Compatibility Matrix ==="
echo

total=0
created=0
available=0
syntax_ok=0

# Test each shell
test_shell() {
  local name=$1
  local script=$2
  local binary=$3

  ((total++))

  local script_path="$SHELLS_DIR/$script"

  # Check if script exists
  if [ ! -f "$script_path" ]; then
    echo -e "${RED}✗${NC} $name - Script missing"
    return 1
  fi

  ((created++))

  # Check if executable
  if [ ! -x "$script_path" ]; then
    echo -e "${YELLOW}○${NC} $name - Not executable (fixing...)"
    chmod +x "$script_path"
  fi

  # Check if shell is available
  if command -v "$binary" >/dev/null 2>&1; then
    ((available++))
    echo -e "${GREEN}✓${NC} $name - Available ($binary)"

    # Test syntax if possible
    case "$binary" in
      bash|dash|ksh|mksh|yash|ash)
        if "$binary" -n "$script_path" 2>/dev/null; then
          ((syntax_ok++))
        fi
        ;;
    esac
  else
    echo -e "${YELLOW}○${NC} $name - Not installed"
  fi
}

# Test all shells
test_shell "bash" "bash/pathroot.sh" "bash"
test_shell "zsh" "zsh/pathroot.zsh" "zsh"
test_shell "fish" "fish/pathroot.fish" "fish"
test_shell "dash" "dash/pathroot.sh" "dash"
test_shell "ksh" "ksh/pathroot.ksh" "ksh"
test_shell "mksh" "mksh/pathroot.sh" "mksh"
test_shell "yash" "yash/pathroot.sh" "yash"
test_shell "tcsh" "tcsh/pathroot.csh" "tcsh"
test_shell "csh" "csh/pathroot.csh" "csh"
test_shell "ash" "ash/pathroot.sh" "ash"
test_shell "nushell" "nushell/pathroot.nu" "nu"
test_shell "elvish" "elvish/pathroot.elv" "elvish"
test_shell "ion" "ion/pathroot.sh" "ion"
test_shell "oil" "oil/pathroot.oil" "osh"
test_shell "xonsh" "xonsh/pathroot.xsh" "xonsh"
test_shell "powershell" "powershell/pathroot.ps1" "pwsh"
test_shell "pwsh" "pwsh/pathroot.ps1" "pwsh"
test_shell "cmd" "cmd/pathroot.cmd" "cmd"
test_shell "rc" "rc/pathroot.sh" "rc"
test_shell "es" "es/pathroot.sh" "es"
test_shell "scsh" "scsh/pathroot.sh" "scsh"
test_shell "minix-sh" "minix-sh/pathroot.sh" "sh"

echo
echo "=== Summary ==="
echo "Total shells: $total"
echo "Scripts created: $created/$total"
echo "Shells available on system: $available/$total"

# Test detect-shell.sh
echo
echo "=== Testing Shell Detection Router ==="
if [ -f "$SCRIPT_DIR/detect-shell.sh" ] && [ -x "$SCRIPT_DIR/detect-shell.sh" ]; then
  echo -e "${GREEN}✓${NC} detect-shell.sh exists and is executable"
else
  echo -e "${RED}✗${NC} detect-shell.sh missing or not executable"
fi

echo
if [ "$created" -eq "$total" ]; then
  echo -e "${GREEN}✅ All shell scripts created successfully!${NC}"
else
  echo -e "${RED}❌ Some shell scripts are missing${NC}"
  exit 1
fi

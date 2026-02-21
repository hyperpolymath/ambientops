#!/usr/bin/env bash
# _pathroot Environment Management for POSIX Systems
# Version: 0.1.0

set -euo pipefail

VERSION="0.1.0"
SCRIPT_NAME=$(basename "$0")

# Default locations
PATHROOT_FILE="${PATHROOT_FILE:-/_pathroot}"
DEVTOOLS_ROOT=""

# Colors (if terminal supports them)
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    CYAN='\033[0;36m'
    NC='\033[0m' # No Color
else
    RED='' GREEN='' YELLOW='' CYAN='' NC=''
fi

usage() {
    cat <<EOF
_pathroot Environment Manager v${VERSION}

Usage: ${SCRIPT_NAME} <command> [options]

Commands:
    init [path]     Initialize _pathroot at specified location (default: /opt/devtools)
    info            Display environment information
    validate        Validate _pathroot configuration
    env             Output environment variables (for eval)
    profile [name]  Switch to specified profile

Options:
    -p, --pathroot PATH    Path to _pathroot file (default: /_pathroot)
    -h, --help             Show this help message
    -v, --version          Show version

Examples:
    ${SCRIPT_NAME} init /opt/devtools
    ${SCRIPT_NAME} info
    ${SCRIPT_NAME} profile test
    eval \$(${SCRIPT_NAME} env)

EOF
}

log_info() { echo -e "${CYAN}[INFO]${NC} $*"; }
log_ok() { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Discover _pathroot location
discover_pathroot() {
    local locations=(
        "$PATHROOT_FILE"
        "/_pathroot"
        "/mnt/c/_pathroot"  # WSL
        "$HOME/.pathroot"
    )

    for loc in "${locations[@]}"; do
        if [[ -f "$loc" ]]; then
            PATHROOT_FILE="$loc"
            DEVTOOLS_ROOT=$(cat "$loc" | tr -d '\r\n')
            return 0
        fi
    done

    return 1
}

# Read _envbase JSON (basic parsing without jq dependency)
read_envbase() {
    local envbase_file="$DEVTOOLS_ROOT/_envbase"
    if [[ -f "$envbase_file" ]]; then
        cat "$envbase_file"
    else
        echo "{}"
    fi
}

# Extract value from simple JSON (fallback if jq not available)
json_get() {
    local json="$1"
    local key="$2"

    if command -v jq &>/dev/null; then
        echo "$json" | jq -r ".$key // empty"
    else
        # Basic grep-based extraction for simple JSON
        echo "$json" | grep -o "\"$key\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | \
            sed 's/.*"'"$key"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/'
    fi
}

cmd_init() {
    local target="${1:-/opt/devtools}"

    echo ""
    echo "========================================"
    echo " _pathroot Initializer v${VERSION}"
    echo "========================================"
    echo ""

    log_info "Creating devtools structure at: $target"

    # Create directories
    local dirs=("bin" "scripts" "config" "logs" "temp" "tools")
    for dir in "${dirs[@]}"; do
        mkdir -p "$target/$dir"
        log_ok "Created: $target/$dir"
    done

    # Create _pathroot marker
    log_info "Creating _pathroot marker..."
    echo "$target" | sudo tee "/_pathroot" > /dev/null
    log_ok "Created: /_pathroot"

    # Create _envbase
    log_info "Creating _envbase metadata..."
    cat > "$target/_envbase" <<EOF
{
  "env": "devtools",
  "profile": "default",
  "platform": "$(uname -s | tr '[:upper:]' '[:lower:]')",
  "version": "${VERSION}",
  "created": "$(date -Iseconds)"
}
EOF
    log_ok "Created: $target/_envbase"

    echo ""
    log_ok "Initialization complete!"
    echo ""
    echo "Next steps:"
    echo "  1. Add $target/bin to your PATH"
    echo "  2. Run: $SCRIPT_NAME info"
    echo ""
}

cmd_info() {
    if ! discover_pathroot; then
        log_error "_pathroot not found"
        exit 1
    fi

    echo ""
    echo "========================================"
    echo " _pathroot Environment v${VERSION}"
    echo "========================================"
    echo ""

    log_info "Pathroot File: $PATHROOT_FILE"
    log_info "Devtools Root: $DEVTOOLS_ROOT"
    echo ""

    local envbase
    envbase=$(read_envbase)

    if [[ -n "$envbase" && "$envbase" != "{}" ]]; then
        echo "Environment Metadata:"
        echo "  env:      $(json_get "$envbase" "env")"
        echo "  profile:  $(json_get "$envbase" "profile")"
        echo "  platform: $(json_get "$envbase" "platform")"
        echo "  version:  $(json_get "$envbase" "version")"
    else
        log_warn "_envbase not found or empty"
    fi

    # List tools
    if [[ -d "$DEVTOOLS_ROOT/bin" ]]; then
        echo ""
        echo "Available Tools:"
        find "$DEVTOOLS_ROOT/bin" -maxdepth 1 -type f -executable 2>/dev/null | \
            while read -r tool; do
                echo "  - $(basename "$tool")"
            done
    fi

    echo ""
}

cmd_validate() {
    local errors=0
    local warnings=0

    echo ""
    echo "Validation Results:"
    echo ""

    # Check _pathroot
    if discover_pathroot; then
        log_ok "_pathroot exists: $PATHROOT_FILE"
    else
        log_error "_pathroot not found"
        ((errors++))
    fi

    # Check devtools root
    if [[ -n "$DEVTOOLS_ROOT" && -d "$DEVTOOLS_ROOT" ]]; then
        log_ok "Devtools root exists: $DEVTOOLS_ROOT"
    else
        log_error "Devtools root not found"
        ((errors++))
    fi

    # Check directories
    local dirs=("bin" "scripts" "config" "logs" "temp" "tools")
    for dir in "${dirs[@]}"; do
        if [[ -d "$DEVTOOLS_ROOT/$dir" ]]; then
            log_ok "$dir/ exists"
        else
            log_warn "$dir/ not found"
            ((warnings++))
        fi
    done

    # Check _envbase
    if [[ -f "$DEVTOOLS_ROOT/_envbase" ]]; then
        log_ok "_envbase exists"
    else
        log_warn "_envbase not found"
        ((warnings++))
    fi

    # Check PATH
    if [[ ":$PATH:" == *":$DEVTOOLS_ROOT/bin:"* ]]; then
        log_ok "bin/ in PATH"
    else
        log_warn "bin/ not in PATH"
        ((warnings++))
    fi

    echo ""
    echo "Summary: $errors errors, $warnings warnings"

    [[ $errors -eq 0 ]]
}

cmd_env() {
    if ! discover_pathroot; then
        exit 1
    fi

    local envbase
    envbase=$(read_envbase)

    echo "export DEVTOOLS_ROOT=\"$DEVTOOLS_ROOT\""
    echo "export DEVTOOLS_PROFILE=\"$(json_get "$envbase" "profile")\""
    echo "export DEVTOOLS_PLATFORM=\"$(json_get "$envbase" "platform")\""
    echo "export PATH=\"\$DEVTOOLS_ROOT/bin:\$PATH\""
}

cmd_profile() {
    local profile="${1:-}"

    if [[ -z "$profile" ]]; then
        log_error "Profile name required"
        exit 1
    fi

    if ! discover_pathroot; then
        log_error "_pathroot not found"
        exit 1
    fi

    local envbase_file="$DEVTOOLS_ROOT/_envbase"

    if command -v jq &>/dev/null; then
        local envbase
        envbase=$(cat "$envbase_file")
        echo "$envbase" | jq ".profile = \"$profile\"" > "$envbase_file.tmp"
        mv "$envbase_file.tmp" "$envbase_file"
        log_ok "Profile switched to: $profile"
    else
        log_error "jq required for profile switching"
        exit 1
    fi
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -p|--pathroot)
            PATHROOT_FILE="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -v|--version)
            echo "pathroot v${VERSION}"
            exit 0
            ;;
        init|info|validate|env|profile)
            CMD="$1"
            shift
            break
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Execute command
case "${CMD:-info}" in
    init)     cmd_init "$@" ;;
    info)     cmd_info ;;
    validate) cmd_validate ;;
    env)      cmd_env ;;
    profile)  cmd_profile "$@" ;;
    *)
        log_error "Unknown command: $CMD"
        usage
        exit 1
        ;;
esac

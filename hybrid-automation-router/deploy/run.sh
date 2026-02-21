#!/bin/sh
# SPDX-License-Identifier: MPL-2.0
# HAR Container Runtime Script
#
# Detects and uses available container runtime in priority order:
#   1. nerdctl (containerd)
#   2. podman (rootless preferred)
#   3. docker (last resort)
#
# Fallback package managers:
#   1. guix (primary)
#   2. nix (secondary)
#
# Usage:
#   ./deploy/run.sh build           # Build container image
#   ./deploy/run.sh up              # Start 3-node cluster
#   ./deploy/run.sh down            # Stop cluster
#   ./deploy/run.sh logs            # View logs
#   ./deploy/run.sh shell           # Enter container shell
#   ./deploy/run.sh native          # Install natively via guix/nix

set -eu

# Colors (if terminal supports it)
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    NC=''
fi

# Logging
log_info() { printf "${BLUE}[INFO]${NC} %s\n" "$1"; }
log_ok() { printf "${GREEN}[OK]${NC} %s\n" "$1"; }
log_warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$1"; }
log_error() { printf "${RED}[ERROR]${NC} %s\n" "$1"; }

# Detect container runtime
detect_container_runtime() {
    # Priority: nerdctl > podman > docker
    if command -v nerdctl >/dev/null 2>&1; then
        RUNTIME="nerdctl"
        COMPOSE="nerdctl compose"
        log_ok "Using nerdctl (containerd)"
    elif command -v podman >/dev/null 2>&1; then
        RUNTIME="podman"
        if command -v podman-compose >/dev/null 2>&1; then
            COMPOSE="podman-compose"
        else
            COMPOSE="podman compose"
        fi
        log_ok "Using podman"
    elif command -v docker >/dev/null 2>&1; then
        RUNTIME="docker"
        COMPOSE="docker compose"
        log_warn "Using docker (consider nerdctl or podman for FOSS-first)"
    else
        log_error "No container runtime found!"
        log_info "Install one of: nerdctl, podman, docker"
        log_info "Or use: ./deploy/run.sh native"
        exit 1
    fi
}

# Detect native package manager
detect_package_manager() {
    # Priority: guix > nix
    if command -v guix >/dev/null 2>&1; then
        PKG_MGR="guix"
        log_ok "Using Guix package manager"
    elif command -v nix >/dev/null 2>&1; then
        PKG_MGR="nix"
        log_ok "Using Nix package manager (fallback)"
    else
        log_error "No package manager found!"
        log_info "Install Guix: https://guix.gnu.org/manual/en/html_node/Binary-Installation.html"
        log_info "Or Nix: https://nixos.org/download.html"
        exit 1
    fi
}

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Commands
cmd_build() {
    detect_container_runtime
    log_info "Building HAR container image..."
    cd "$PROJECT_ROOT"
    $RUNTIME build -t har:latest -f deploy/Containerfile .
    log_ok "Built har:latest"
}

cmd_up() {
    detect_container_runtime
    log_info "Starting HAR cluster (3 nodes)..."
    cd "$PROJECT_ROOT"
    $COMPOSE -f deploy/compose.yaml up -d
    log_ok "HAR cluster started"
    log_info "Web interface: http://localhost:4000"
}

cmd_down() {
    detect_container_runtime
    log_info "Stopping HAR cluster..."
    cd "$PROJECT_ROOT"
    $COMPOSE -f deploy/compose.yaml down
    log_ok "HAR cluster stopped"
}

cmd_logs() {
    detect_container_runtime
    cd "$PROJECT_ROOT"
    $COMPOSE -f deploy/compose.yaml logs -f
}

cmd_shell() {
    detect_container_runtime
    log_info "Entering HAR container shell..."
    $RUNTIME exec -it har-node1 /bin/sh
}

cmd_status() {
    detect_container_runtime
    cd "$PROJECT_ROOT"
    $COMPOSE -f deploy/compose.yaml ps
}

cmd_native() {
    detect_package_manager
    log_info "Installing HAR natively..."

    cd "$PROJECT_ROOT"

    case "$PKG_MGR" in
        guix)
            log_info "Building with Guix..."
            guix build -f deploy/guix/har.scm
            log_ok "Built! Install with: guix install -f deploy/guix/har.scm"
            ;;
        nix)
            log_info "Building with Nix..."
            cd deploy/nix
            nix build
            log_ok "Built! Run with: nix run"
            ;;
    esac
}

cmd_dev() {
    detect_package_manager
    log_info "Entering development shell..."

    cd "$PROJECT_ROOT"

    case "$PKG_MGR" in
        guix)
            guix shell -f deploy/guix/har.scm
            ;;
        nix)
            cd deploy/nix
            nix develop
            ;;
    esac
}

cmd_help() {
    cat << EOF
HAR (Hybrid Automation Router) Deployment Script

Usage: $0 <command>

Container Commands:
  build         Build container image
  up            Start 3-node HAR cluster
  down          Stop HAR cluster
  logs          Follow container logs
  shell         Enter container shell
  status        Show cluster status

Native Commands:
  native        Install HAR natively (guix > nix)
  dev           Enter development shell

Runtime Priority:
  Container: nerdctl > podman > docker
  Package:   guix > nix

Examples:
  $0 build && $0 up     # Build and start cluster
  $0 native             # Install without containers
  $0 dev                # Enter dev shell

EOF
}

# Main
case "${1:-help}" in
    build)  cmd_build ;;
    up)     cmd_up ;;
    down)   cmd_down ;;
    logs)   cmd_logs ;;
    shell)  cmd_shell ;;
    status) cmd_status ;;
    native) cmd_native ;;
    dev)    cmd_dev ;;
    help|--help|-h) cmd_help ;;
    *)
        log_error "Unknown command: $1"
        cmd_help
        exit 1
        ;;
esac

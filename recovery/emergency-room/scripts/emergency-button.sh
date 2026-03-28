#!/bin/bash
# SPDX-License-Identifier: PMPL-1.0-or-later
# Emergency system cleanup and diagnostics script
# MED-008 fix: Safe glob handling

set -uo pipefail

# Enable nullglob so non-matching globs expand to nothing
shopt -s nullglob

# Disable globbing in unexpected places
set -o noglob

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

header() { printf "\n${BLUE}=== %s ===${NC}\n" "$1"; }
success() { printf "${GREEN}[OK]${NC} %s\n" "$1"; }
warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$1"; }
info() { printf "${BLUE}[INFO]${NC} %s\n" "$1"; }

header "Emergency System Diagnostics"
echo "Running at: $(date)"

header "Disk Usage"
df -h / /var /home 2>/dev/null | grep -v "^Filesystem" | head -5

header "Memory Status"
free -h | grep -E "^Mem|^Swap"

header "Quick Cleanup"

# Fast cache cleanup - no scanning, just delete known safe paths
declare -a cache_dirs=(
    ~/.cache/pip
    ~/.cache/cargo/registry
    ~/.cache/go-build
    ~/.cache/deno
    ~/.cache/thumbnails
    ~/.cache/mozilla/firefox/*/cache2
    ~/.cache/chromium/*/Cache
    ~/.cache/google-chrome/*/Cache
    ~/.cache/BraveSoftware/*/Cache
    ~/.cache/fontconfig
    ~/.cache/mesa_shader_cache
    ~/.cache/nix
    ~/.npm/_cacache
    ~/.bun/install/cache
)

freed=0
# MED-008: Temporarily enable globbing for cache directory expansion
set +o noglob
for dir in "${cache_dirs[@]}"; do
    # Expand glob patterns safely
    for expanded in $dir; do
        # Validate path is under user's home directory (prevent traversal)
        if [[ "$expanded" != "$HOME"* ]]; then
            warn "Skipping path outside home: $expanded"
            continue
        fi
        if [[ -d "$expanded" && ! -L "$expanded" ]]; then
            size=$(du -sb "$expanded" 2>/dev/null | cut -f1 || echo 0)
            rm -rf "$expanded" 2>/dev/null && {
                freed=$((freed + size))
                success "Cleared $(basename "$expanded")"
            }
        fi
    done
done
set -o noglob

if [[ $freed -gt 1073741824 ]]; then
    info "Freed: $((freed / 1073741824))G"
elif [[ $freed -gt 1048576 ]]; then
    info "Freed: $((freed / 1048576))M"
elif [[ $freed -gt 0 ]]; then
    info "Freed: $((freed / 1024))K"
fi

# Flatpak cleanup (quiet)
if command -v flatpak &>/dev/null; then
    flatpak uninstall --unused -y &>/dev/null && success "Removed unused Flatpak runtimes" || :
fi

# Podman cleanup (with timeout)
if command -v podman &>/dev/null; then
    timeout 10 podman system prune -f &>/dev/null && success "Pruned podman" || :
fi

# Nerdctl/containerd cleanup
if command -v nerdctl &>/dev/null; then
    timeout 10 nerdctl system prune -f &>/dev/null && success "Pruned nerdctl" || :
fi

header "Status"
df -h /var | tail -1 | awk '{print "Disk: " $3 " used / " $4 " free (" $5 ")"}'
free -h | awk '/^Mem:/{print "RAM: " $3 " used / " $4 " free"}'

success "Done"

# Interactive menu
show_menu() {
    echo ""
    printf "${CYAN}─────────────────────────────────────${NC}\n"
    printf "${CYAN}Additional Info Menu${NC}\n"
    printf "${CYAN}─────────────────────────────────────${NC}\n"
    echo "1) Top memory consumers"
    echo "2) Largest directories in home"
    echo "3) Flatpak runtimes (pinned/installed)"
    echo "4) Container images (podman)"
    echo "5) rpm-ostree status"
    echo "6) Journal disk usage"
    echo "q) Quit"
    echo ""
}

while true; do
    show_menu
    read -rp "Select [1-6, q]: " choice
    case $choice in
        1)
            header "Top Memory Consumers"
            ps aux --sort=-%mem 2>/dev/null | head -8 | awk '{printf "%-6s %-5s %s\n", $4"%", $2, $11}'
            ;;
        2)
            header "Largest Directories"
            timeout 15 du -sh ~/Downloads ~/Documents ~/.cache ~/.local ~/repos 2>/dev/null | sort -hr
            ;;
        3)
            header "Flatpak Runtimes"
            flatpak list --runtime 2>/dev/null | head -20
            info "Run 'flatpak list --runtime' for full list"
            ;;
        4)
            header "Container Images"
            podman images 2>/dev/null || info "No podman images"
            ;;
        5)
            header "rpm-ostree Status"
            rpm-ostree status --booted 2>/dev/null || warn "Not an rpm-ostree system"
            ;;
        6)
            header "Journal Disk Usage"
            journalctl --disk-usage 2>/dev/null
            info "Clean with: sudo journalctl --vacuum-time=7d"
            ;;
        q|Q|"")
            echo "Bye!"
            exit 0
            ;;
        *)
            warn "Invalid option"
            ;;
    esac
done

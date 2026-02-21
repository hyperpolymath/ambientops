#!/usr/bin/env bash
# System detection and utility functions

# Detect Linux distribution
detect_distro() {
    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        source /etc/os-release
        echo "${ID}"
    elif [[ -f /etc/lsb-release ]]; then
        # shellcheck source=/dev/null
        source /etc/lsb-release
        echo "${DISTRIB_ID}" | tr '[:upper:]' '[:lower:]'
    elif command -v lsb_release >/dev/null 2>&1; then
        lsb_release -si | tr '[:upper:]' '[:lower:]'
    else
        echo "unknown"
    fi
}

# Detect distribution family
detect_distro_family() {
    local distro
    distro="$(detect_distro)"

    case "${distro}" in
        ubuntu|debian|linuxmint|pop)
            echo "debian"
            ;;
        fedora|rhel|centos|rocky|alma)
            echo "redhat"
            ;;
        arch|manjaro|endeavouros)
            echo "arch"
            ;;
        opensuse*)
            echo "suse"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# Check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check if a package is installed
package_installed() {
    local package="$1"
    local distro_family
    distro_family="$(detect_distro_family)"

    case "${distro_family}" in
        debian)
            dpkg -l "${package}" 2>/dev/null | grep -q "^ii"
            ;;
        redhat)
            rpm -q "${package}" >/dev/null 2>&1
            ;;
        arch)
            pacman -Q "${package}" >/dev/null 2>&1
            ;;
        *)
            command_exists "${package}"
            ;;
    esac
}

# Get network manager type
detect_network_manager() {
    if systemctl is-active --quiet NetworkManager 2>/dev/null; then
        echo "NetworkManager"
    elif systemctl is-active --quiet systemd-networkd 2>/dev/null; then
        echo "systemd-networkd"
    elif [[ -d /etc/netplan ]]; then
        echo "netplan"
    elif [[ -f /etc/network/interfaces ]]; then
        echo "ifupdown"
    else
        echo "unknown"
    fi
}

# Check if systemd is available
has_systemd() {
    command_exists systemctl && systemctl --version >/dev/null 2>&1
}

# Get primary network interface
get_primary_interface() {
    # Try to get default route interface
    ip route show default 2>/dev/null | grep -oP 'dev \K\S+' | head -1
}

# Get all network interfaces (excluding loopback)
get_all_interfaces() {
    ip -o link show | awk -F': ' '{print $2}' | grep -v '^lo$'
}

# Check if interface exists
interface_exists() {
    local interface="$1"
    ip link show "${interface}" >/dev/null 2>&1
}

# Check if interface is up
interface_is_up() {
    local interface="$1"
    [[ "$(cat /sys/class/net/"${interface}"/operstate 2>/dev/null)" == "up" ]]
}

# Get interface IP address
get_interface_ip() {
    local interface="$1"
    ip -4 addr show "${interface}" 2>/dev/null | grep -oP 'inet \K[\d.]+'
}

# Sanitize input (prevent command injection)
sanitize_input() {
    local input="$1"
    # Remove any characters that aren't alphanumeric, dash, underscore, or dot
    echo "${input}" | tr -cd '[:alnum:]._-'
}

# Check internet connectivity
check_internet() {
    local host="${1:-8.8.8.8}"
    local count="${2:-2}"
    ping -c "${count}" -W 2 "${host}" >/dev/null 2>&1
}

# Check DNS resolution
check_dns() {
    local domain="${1:-google.com}"
    if command_exists dig; then
        dig +short "${domain}" >/dev/null 2>&1
    elif command_exists nslookup; then
        nslookup "${domain}" >/dev/null 2>&1
    elif command_exists host; then
        host "${domain}" >/dev/null 2>&1
    else
        # Fallback to getent
        getent hosts "${domain}" >/dev/null 2>&1
    fi
}

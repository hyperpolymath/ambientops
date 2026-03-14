#!/usr/bin/env bash
# Connectivity diagnostics module

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../utils/logging.sh"
source "${SCRIPT_DIR}/../utils/system.sh"

# Test basic connectivity
test_basic_connectivity() {
    log_section "Basic Connectivity Test"

    local issues=0
    local test_hosts=("8.8.8.8" "1.1.1.1" "9.9.9.9")

    for host in "${test_hosts[@]}"; do
        log_step "Pinging ${host}"

        if ping -c 3 -W 3 "${host}" >/dev/null 2>&1; then
            # Get ping statistics
            local stats
            stats=$(ping -c 3 -W 3 "${host}" 2>/dev/null | tail -1)
            log_success "  ${host} is reachable - ${stats}"
        else
            log_error "  ${host} is NOT reachable"
            issues=$((issues + 1))
        fi
    done

    return ${issues}
}

# Test DNS-based connectivity
test_dns_connectivity() {
    log_section "DNS-based Connectivity Test"

    local issues=0
    local test_domains=("google.com" "cloudflare.com" "github.com")

    for domain in "${test_domains[@]}"; do
        log_step "Pinging ${domain}"

        # First try to resolve
        if ! check_dns "${domain}"; then
            log_error "  Cannot resolve ${domain}"
            issues=$((issues + 1))
            continue
        fi

        # Then ping
        if ping -c 2 -W 3 "${domain}" >/dev/null 2>&1; then
            log_success "  ${domain} is reachable"
        else
            log_warn "  ${domain} resolved but not pingable (may be blocked)"
        fi
    done

    return ${issues}
}

# Test HTTP/HTTPS connectivity
test_http_connectivity() {
    log_section "HTTP/HTTPS Connectivity Test"

    local issues=0

    if ! command_exists curl && ! command_exists wget; then
        log_warn "Neither curl nor wget available, skipping HTTP tests"
        return 0
    fi

    local test_urls=(
        "http://www.google.com"
        "https://www.cloudflare.com"
        "https://www.github.com"
    )

    for url in "${test_urls[@]}"; do
        log_step "Testing ${url}"

        if command_exists curl; then
            if timeout 10 curl -s -o /dev/null -w "%{http_code}" "${url}" 2>/dev/null | grep -q "^[23]"; then
                log_success "  ${url} is accessible"
            else
                log_error "  ${url} is NOT accessible"
                issues=$((issues + 1))
            fi
        elif command_exists wget; then
            if timeout 10 wget -q --spider "${url}" 2>/dev/null; then
                log_success "  ${url} is accessible"
            else
                log_error "  ${url} is NOT accessible"
                issues=$((issues + 1))
            fi
        fi
    done

    return ${issues}
}

# Test port connectivity
test_port_connectivity() {
    log_section "Port Connectivity Test"

    local issues=0

    if ! command_exists nc && ! command_exists telnet; then
        log_warn "Neither nc nor telnet available, skipping port tests"
        return 0
    fi

    local test_ports=(
        "8.8.8.8:53:DNS"
        "1.1.1.1:53:DNS"
        "google.com:80:HTTP"
        "google.com:443:HTTPS"
    )

    for test in "${test_ports[@]}"; do
        IFS=: read -r host port service <<< "${test}"
        log_step "Testing ${service} (${host}:${port})"

        if command_exists nc; then
            if timeout 3 nc -z -w 2 "${host}" "${port}" 2>/dev/null; then
                log_success "  ${host}:${port} is reachable"
            else
                log_error "  ${host}:${port} is NOT reachable"
                issues=$((issues + 1))
            fi
        elif command_exists telnet; then
            if timeout 3 bash -c "echo quit | telnet ${host} ${port}" 2>&1 | grep -q "Connected"; then
                log_success "  ${host}:${port} is reachable"
            else
                log_error "  ${host}:${port} is NOT reachable"
                issues=$((issues + 1))
            fi
        fi
    done

    return ${issues}
}

# Test MTU — binary search for path MTU discovery
test_mtu() {
    log_section "MTU Test"

    local primary
    primary=$(get_primary_interface)

    if [[ -z "${primary}" ]]; then
        log_warn "No primary interface found"
        return 0
    fi

    # Get current interface MTU
    local iface_mtu
    iface_mtu=$(cat /sys/class/net/"${primary}"/mtu 2>/dev/null || echo "0")

    log_info "Interface MTU on ${primary}: ${iface_mtu}"

    # Binary search for actual path MTU
    log_step "Discovering path MTU (binary search)"

    local low=68    # IPv4 minimum
    local high=1500 # Standard ethernet
    local path_mtu=0

    while [[ $((high - low)) -gt 1 ]]; do
        local mid=$(( (low + high) / 2 ))
        local payload=$((mid - 28))  # Subtract IP + ICMP headers

        if ping -c 1 -W 2 -M do -s ${payload} 8.8.8.8 >/dev/null 2>&1; then
            low=${mid}
            path_mtu=${mid}
        else
            high=${mid}
        fi
    done

    # Final check on high value
    local payload=$((high - 28))
    if ping -c 1 -W 2 -M do -s ${payload} 8.8.8.8 >/dev/null 2>&1; then
        path_mtu=${high}
    fi

    if [[ ${path_mtu} -eq 0 ]]; then
        log_error "  Could not determine path MTU"
        return 1
    fi

    log_info "  Path MTU: ${path_mtu} bytes"

    if [[ ${path_mtu} -lt ${iface_mtu} ]]; then
        local diff=$((iface_mtu - path_mtu))
        log_warn "  Interface MTU (${iface_mtu}) exceeds path MTU (${path_mtu}) by ${diff} bytes"
        log_warn "  Packets larger than ${path_mtu} bytes will be dropped or fragmented"
        log_info "  Recommended fix:"
        log_info "    Temporary:  sudo ip link set ${primary} mtu ${path_mtu}"

        # Detect connection name for permanent fix advice
        local conn_name
        conn_name=$(nmcli -t -f NAME,DEVICE connection show --active 2>/dev/null | grep ":${primary}$" | cut -d: -f1 || true)
        if [[ -n "${conn_name}" ]]; then
            log_info "    Permanent:  nmcli connection modify \"${conn_name}\" 802-11-wireless.mtu ${path_mtu}"
            log_info "                nmcli connection up \"${conn_name}\""
        fi
        return 1
    else
        log_success "  Interface MTU (${iface_mtu}) matches path MTU (${path_mtu})"
    fi

    return 0
}

# Test latency with jitter and quality classification
test_latency() {
    log_section "Latency Test"

    local test_hosts=(
        "8.8.8.8:Google DNS"
        "1.1.1.1:Cloudflare DNS"
        "9.9.9.9:Quad9 DNS"
    )

    for test in "${test_hosts[@]}"; do
        IFS=: read -r host name <<< "${test}"
        log_step "Testing latency to ${name} (${host})"

        local ping_output
        ping_output=$(ping -c 5 -W 3 "${host}" 2>/dev/null)

        if [[ $? -ne 0 ]] && [[ -z "${ping_output}" ]]; then
            log_error "  Cannot reach ${host}"
            continue
        fi

        # Parse rtt min/avg/max/mdev from the summary line
        local stats_line
        stats_line=$(echo "${ping_output}" | grep "rtt min/avg/max/mdev" || true)

        if [[ -n "${stats_line}" ]]; then
            local min_ms avg_ms max_ms jitter_ms
            min_ms=$(echo "${stats_line}" | cut -d'=' -f2 | cut -d'/' -f1 | tr -d ' ')
            avg_ms=$(echo "${stats_line}" | cut -d'=' -f2 | cut -d'/' -f2)
            max_ms=$(echo "${stats_line}" | cut -d'=' -f2 | cut -d'/' -f3)
            jitter_ms=$(echo "${stats_line}" | cut -d'=' -f2 | cut -d'/' -f4 | cut -d' ' -f1)

            # Parse packet loss
            local loss_line
            loss_line=$(echo "${ping_output}" | grep "packet loss" || true)
            local loss_pct="0"
            if [[ -n "${loss_line}" ]]; then
                loss_pct=$(echo "${loss_line}" | grep -oP '\d+(?=% packet loss)' || echo "0")
            fi

            log_info "  RTT min/avg/max: ${min_ms}/${avg_ms}/${max_ms} ms"
            log_info "  Jitter (mdev): ${jitter_ms} ms"
            if [[ "${loss_pct}" != "0" ]]; then
                log_warn "  Packet loss: ${loss_pct}%"
            fi

            # Quality classification (matches Aerie engine thresholds)
            local avg_int
            avg_int=$(echo "${avg_ms}" | cut -d'.' -f1)
            if [[ ${avg_int} -lt 20 ]]; then
                log_success "  Quality: Excellent"
            elif [[ ${avg_int} -lt 50 ]]; then
                log_success "  Quality: Good"
            elif [[ ${avg_int} -lt 100 ]]; then
                log_info "  Quality: Fair"
            elif [[ ${avg_int} -lt 300 ]]; then
                log_warn "  Quality: Poor"
            else
                log_warn "  Quality: Very poor (mobile/satellite connection?)"
            fi
        fi
    done

    return 0
}

# Main connectivity diagnostic function
diagnose_connectivity() {
    log_section "Connectivity Diagnostics"

    local total_issues=0

    test_basic_connectivity || total_issues=$((total_issues + $?))

    test_dns_connectivity || total_issues=$((total_issues + $?))

    test_http_connectivity || total_issues=$((total_issues + $?))

    test_port_connectivity || total_issues=$((total_issues + $?))

    test_mtu || total_issues=$((total_issues + $?))

    test_latency

    if [[ ${total_issues} -eq 0 ]]; then
        log_success "Connectivity diagnostics completed with no issues"
        return 0
    else
        log_warn "Connectivity diagnostics found ${total_issues} issue(s)"
        return 1
    fi
}

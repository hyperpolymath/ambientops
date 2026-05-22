#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# NVMe health check — runs periodically via systemd timer
# Logs warnings and captures SMART data if issues detected

LOG="/var/log/nvme-health-check.log"
ALERT_FILE="${NVME_ALERT_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/ambientops}/NVME-ALERT.txt"

timestamp() { date '+%Y-%m-%d %H:%M:%S'; }

echo "[$(timestamp)] NVMe health check starting" >> "$LOG"

# Check if Eclipse drive is present on PCIe bus
if ! lsblk /dev/nvme0n1 &>/dev/null; then
    echo "[$(timestamp)] CRITICAL: Eclipse NVMe (nvme0n1) NOT DETECTED on PCIe bus!" >> "$LOG"
    cat > "$ALERT_FILE" <<EOF
!! CRITICAL: ECLIPSE NVMe NOT DETECTED !!
Timestamp: $(timestamp)
The SK hynix Eclipse drive has dropped off the PCIe bus.
This is the boot storm trigger. Reseat the M.2 drive.
EOF
    # Try to send desktop notification
    sudo -u hyper DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u hyper)/bus" \
        notify-send -u critical "NVMe ALERT" "Eclipse drive dropped off PCIe bus!" 2>/dev/null
    exit 1
fi

# Check Eclipse SMART
ECLIPSE_WARN=$(smartctl -H /dev/nvme0n1 2>/dev/null | grep -c "PASSED")
if [ "$ECLIPSE_WARN" -eq 0 ]; then
    echo "[$(timestamp)] WARNING: Eclipse NVMe SMART health check did not PASS" >> "$LOG"
    smartctl -a /dev/nvme0n1 >> "$LOG" 2>&1
fi

# Check Samsung SMART
SAMSUNG_WARN=$(smartctl -H /dev/nvme1n1 2>/dev/null | grep -c "PASSED")
if [ "$SAMSUNG_WARN" -eq 0 ]; then
    echo "[$(timestamp)] WARNING: Samsung NVMe SMART health check did not PASS" >> "$LOG"
    smartctl -a /dev/nvme1n1 >> "$LOG" 2>&1
fi

# Check Samsung percentage used (alert at 70%)
PCT_USED=$(smartctl -a /dev/nvme1n1 2>/dev/null | grep "Percentage Used" | awk '{print $NF}' | tr -d '%')
if [ -n "$PCT_USED" ] && [ "$PCT_USED" -ge 70 ]; then
    echo "[$(timestamp)] WARNING: Samsung 960 EVO at ${PCT_USED}% life used — plan replacement!" >> "$LOG"
fi

# Check temperature (alert at 70C)
for dev in nvme0n1 nvme1n1; do
    TEMP=$(smartctl -a /dev/$dev 2>/dev/null | grep "^Temperature:" | awk '{print $2}')
    if [ -n "$TEMP" ] && [ "$TEMP" -ge 70 ]; then
        echo "[$(timestamp)] WARNING: /dev/$dev temperature ${TEMP}C — thermal throttling risk!" >> "$LOG"
    fi
done

# Check dmesg for recent NVMe errors
NVME_ERRORS=$(dmesg 2>/dev/null | grep -c "nvme.*error\|nvme.*ENODEV\|nvme.*timeout" || true)
if [ "$NVME_ERRORS" -gt 0 ]; then
    echo "[$(timestamp)] WARNING: ${NVME_ERRORS} NVMe error(s) in current dmesg" >> "$LOG"
    dmesg 2>/dev/null | grep -i "nvme.*error\|nvme.*ENODEV\|nvme.*timeout" >> "$LOG"
fi

# Count unsafe shutdowns delta (compare to baseline)
BASELINE_FILE="/var/lib/nvme-health/baseline-unsafe-shutdowns"
CURRENT_ECLIPSE=$(smartctl -a /dev/nvme0n1 2>/dev/null | grep "Unsafe Shutdowns" | awk '{print $NF}' | tr -d ',')
CURRENT_SAMSUNG=$(smartctl -a /dev/nvme1n1 2>/dev/null | grep "Unsafe Shutdowns" | awk '{print $NF}' | tr -d ',')

if [ -f "$BASELINE_FILE" ]; then
    BASELINE=$(cat "$BASELINE_FILE")
    BASELINE_E=$(echo "$BASELINE" | head -1)
    BASELINE_S=$(echo "$BASELINE" | tail -1)
    DELTA_E=$((CURRENT_ECLIPSE - BASELINE_E))
    DELTA_S=$((CURRENT_SAMSUNG - BASELINE_S))
    if [ "$DELTA_E" -gt 5 ] || [ "$DELTA_S" -gt 5 ]; then
        echo "[$(timestamp)] WARNING: ${DELTA_E} new unsafe shutdowns (Eclipse), ${DELTA_S} (Samsung) since baseline" >> "$LOG"
    fi
fi

# Save current as baseline
mkdir -p /var/lib/nvme-health
echo -e "${CURRENT_ECLIPSE}\n${CURRENT_SAMSUNG}" > "$BASELINE_FILE"

# Clear alert file if everything is OK
if [ -f "$ALERT_FILE" ] && lsblk /dev/nvme0n1 &>/dev/null; then
    rm -f "$ALERT_FILE"
fi

echo "[$(timestamp)] NVMe health check complete — Eclipse: ${CURRENT_ECLIPSE} unsafe, Samsung: ${CURRENT_SAMSUNG} unsafe, temps OK" >> "$LOG"

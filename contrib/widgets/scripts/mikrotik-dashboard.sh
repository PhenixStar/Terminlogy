#!/bin/bash

# MikroTik Annex-4 Dashboard Widget for WaveTerm
# Polls router status every 30 seconds via SSH

ROUTER_HOST="10.1.1.1"
ROUTER_PORT="2222"
ROUTER_USER="alaa"
SSH_KEY="$HOME/.ssh/id_ed25519_alaa"
REFRESH_INTERVAL=30

# ANSI color codes
RED='\033[0;31m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# Human-readable byte formatting
format_bytes() {
    local bytes="$1"
    # Strip any non-numeric characters
    bytes="${bytes//[^0-9]/}"
    [ -z "$bytes" ] && bytes=0
    if [ "$bytes" -ge 1073741824 ]; then
        printf "%.1f GB" "$(echo "scale=1; $bytes / 1073741824" | bc)"
    elif [ "$bytes" -ge 1048576 ]; then
        printf "%.1f MB" "$(echo "scale=1; $bytes / 1048576" | bc)"
    elif [ "$bytes" -ge 1024 ]; then
        printf "%.1f KB" "$(echo "scale=1; $bytes / 1024" | bc)"
    else
        printf "%s B" "$bytes"
    fi
}

# Color-coded CPU load
cpu_color() {
    local load="$1"
    load="${load//[^0-9]/}"
    [ -z "$load" ] && load=0
    if [ "$load" -ge 80 ]; then
        echo -e "${RED}${load}%${RESET}"
    elif [ "$load" -ge 50 ]; then
        echo -e "${YELLOW}${load}%${RESET}"
    else
        echo -e "${GREEN}${load}%${RESET}"
    fi
}

# Color-coded memory usage
mem_color() {
    local pct="$1"
    pct="${pct//[^0-9]/}"
    [ -z "$pct" ] && pct=0
    if [ "$pct" -ge 80 ]; then
        echo -e "${RED}${pct}% free${RESET}"
    elif [ "$pct" -le 30 ]; then
        echo -e "${YELLOW}${pct}% free${RESET}"
    else
        echo -e "${GREEN}${pct}% free${RESET}"
    fi
}

# Run all RouterOS commands in a single SSH session
fetch_router_data() {
    ssh \
        -i "$SSH_KEY" \
        -p "$ROUTER_PORT" \
        -o BatchMode=yes \
        -o ConnectTimeout=5 \
        -o StrictHostKeyChecking=no \
        "${ROUTER_USER}@${ROUTER_HOST}" \
        ":put \"---RESOURCE---\";
         /system resource print;
         :put \"---IFSTATS---\";
         /interface print stats where running=yes;
         :put \"---FWCOUNT---\";
         /ip firewall filter print count-only;
         :put \"---WIFICLIENTS---\";
         /interface wireless registration-table print count-only;
         :put \"---CLOCK---\";
         /system clock print;
         :put \"---END---\"" 2>/dev/null
}

# Draw the dashboard from raw SSH output
render_dashboard() {
    local raw="$1"
    local now
    now=$(date '+%Y-%m-%d %H:%M:%S')

    # ── Parse sections ──────────────────────────────────────────────────────────

    local resource_block
    resource_block=$(echo "$raw" | awk '/---RESOURCE---/{found=1; next} /---IFSTATS---/{found=0} found{print}')

    local ifstats_block
    ifstats_block=$(echo "$raw" | awk '/---IFSTATS---/{found=1; next} /---FWCOUNT---/{found=0} found{print}')

    local fw_count
    fw_count=$(echo "$raw" | awk '/---FWCOUNT---/{found=1; next} /---WIFICLIENTS---/{found=0} found{print}' | grep -o '[0-9]*' | head -1)

    local wifi_clients
    wifi_clients=$(echo "$raw" | awk '/---WIFICLIENTS---/{found=1; next} /---CLOCK---/{found=0} found{print}' | grep -o '[0-9]*' | head -1)

    local clock_block
    clock_block=$(echo "$raw" | awk '/---CLOCK---/{found=1; next} /---END---/{found=0} found{print}')

    # ── Extract resource fields ──────────────────────────────────────────────────

    local uptime cpu_load free_mem total_mem
    uptime=$(echo "$resource_block"      | grep -i 'uptime'           | sed 's/.*uptime: *//' | awk '{print $1}')
    cpu_load=$(echo "$resource_block"    | grep -i 'cpu-load'         | grep -o '[0-9]*' | head -1)
    free_mem=$(echo "$resource_block"    | grep -i 'free-memory'      | grep -o '[0-9]*' | head -1)
    total_mem=$(echo "$resource_block"   | grep -i 'total-memory'     | grep -o '[0-9]*' | head -1)

    local mem_pct=0
    if [ -n "$total_mem" ] && [ "$total_mem" -gt 0 ] 2>/dev/null; then
        mem_pct=$(( free_mem * 100 / total_mem ))
    fi

    local router_time
    router_time=$(echo "$clock_block" | grep -i 'time' | sed 's/.*time: *//' | awk '{print $1}')
    local router_date
    router_date=$(echo "$clock_block" | grep -i 'date' | sed 's/.*date: *//' | awk '{print $1}')

    # ── Render ───────────────────────────────────────────────────────────────────

    clear

    echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════╗${RESET}"
    printf "${BOLD}${CYAN}║${RESET}  ${BOLD}%-56s${RESET}${BOLD}${CYAN}║${RESET}\n" "MikroTik Annex-4 (hAP ax3) — ${ROUTER_HOST}"
    echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════╝${RESET}"
    echo ""

    # System section
    echo -e "${BOLD}${BLUE}  SYSTEM${RESET}"
    echo -e "${DIM}  ────────────────────────────────────────────────────────${RESET}"
    printf "  %-20s %s\n"    "Uptime:"      "${uptime:-n/a}"
    printf "  %-20s %b\n"    "CPU Load:"    "$(cpu_color "${cpu_load:-0}")"
    printf "  %-20s %b\n"    "Free Memory:" "$(mem_color "$mem_pct")"
    printf "  %-20s %s  %s\n" "Router Time:" "${router_time:-n/a}" "${router_date:-}"
    echo ""

    # Interfaces section
    echo -e "${BOLD}${BLUE}  INTERFACES  ${DIM}(running)${RESET}"
    echo -e "${DIM}  ────────────────────────────────────────────────────────${RESET}"

    # Parse interface stats table — columns: name, rx-byte, tx-byte (positional)
    # RouterOS format: index  name  rx-byte  tx-byte  ...
    echo "$ifstats_block" | grep -v '^\s*$' | grep -v '^[[:space:]]*#' | while IFS= read -r line; do
        # Skip header lines
        echo "$line" | grep -qiE '^\s*(#|name|rx-byte)' && continue

        local iface rx_bytes tx_bytes
        iface=$(echo "$line"    | awk '{print $2}')
        rx_bytes=$(echo "$line" | awk '{print $3}')
        tx_bytes=$(echo "$line" | awk '{print $4}')

        [ -z "$iface" ] && continue
        echo "$iface" | grep -qE '^[0-9]+$' && continue  # skip index-only rows

        local rx_fmt tx_fmt
        rx_fmt=$(format_bytes "$rx_bytes")
        tx_fmt=$(format_bytes "$tx_bytes")

        printf "  %-18s  ${GREEN}RX${RESET} %-12s  ${MAGENTA}TX${RESET} %s\n" "$iface" "$rx_fmt" "$tx_fmt"
    done
    echo ""

    # Firewall section
    echo -e "${BOLD}${BLUE}  FIREWALL${RESET}"
    echo -e "${DIM}  ────────────────────────────────────────────────────────${RESET}"
    printf "  %-20s %s\n" "Filter rules:" "${fw_count:-n/a}"
    echo ""

    # WiFi section
    echo -e "${BOLD}${BLUE}  WIRELESS${RESET}"
    echo -e "${DIM}  ────────────────────────────────────────────────────────${RESET}"
    if [ -n "$wifi_clients" ]; then
        printf "  %-20s %s\n" "Associated clients:" "$wifi_clients"
    else
        printf "  %-20s %s\n" "Associated clients:" "n/a"
    fi
    echo ""

    # Footer
    echo -e "${DIM}  Last updated: ${now}  —  refresh every ${REFRESH_INTERVAL}s${RESET}"
    echo ""
}

# Show offline banner
render_offline() {
    clear
    echo ""
    echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════╗${RESET}"
    printf "${BOLD}${CYAN}║${RESET}  ${BOLD}%-56s${RESET}${BOLD}${CYAN}║${RESET}\n" "MikroTik Annex-4 (hAP ax3) — ${ROUTER_HOST}"
    echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════╝${RESET}"
    echo ""
    echo -e "  ${YELLOW}${BOLD}Offline — not reachable${RESET}"
    echo -e "  ${DIM}SSH to ${ROUTER_USER}@${ROUTER_HOST}:${ROUTER_PORT} failed.${RESET}"
    echo -e "  ${DIM}You may not be on the local network.${RESET}"
    echo ""
    echo -e "  ${DIM}Last attempt: $(date '+%Y-%m-%d %H:%M:%S')  —  retrying in ${REFRESH_INTERVAL}s${RESET}"
    echo ""
}

# Main loop
main() {
    while true; do
        local raw
        raw=$(fetch_router_data)

        if [ -z "$raw" ] || ! echo "$raw" | grep -q '---END---'; then
            render_offline
        else
            render_dashboard "$raw"
        fi

        sleep "$REFRESH_INTERVAL"
    done
}

main

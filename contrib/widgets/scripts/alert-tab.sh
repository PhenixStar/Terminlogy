#!/bin/bash
#
# alert-tab.sh - Monitor system metrics and send tab alerts to WaveTerm
#
# Usage: alert-tab.sh --gpu-temp 85 --container-down true --tunnel-offline true
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(dirname "$SCRIPT_DIR")/lib"

# Source widget state library if available
if [[ -f "$LIB_DIR/widget-state.sh" ]]; then
    source "$LIB_DIR/widget_state.sh" 2>/dev/null || source "$LIB_DIR/widget-state.sh" 2>/dev/null || true
fi

# Default thresholds
GPU_TEMP_THRESHOLD=80
CONTAINER_DOWN_ALERT=false
TUNNEL_OFFLINE_ALERT=false
POLL_INTERVAL=10
SSH_HOST="phenix@dgx"
SSH_PORT="22"
SSH_KEY="$HOME/.ssh/id_ed25519"
MAX_ALERT_HISTORY=5

# Colors
RED='\033[0;31m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# State files
STATE_DIR="${WIDGET_STATE_DIR:-$HOME/.waveterm/widget-state}"
ALERT_HISTORY_FILE="$STATE_DIR/alert-history.txt"
LAST_CONTAINER_COUNT_FILE="$STATE_DIR/last-container-count.txt"
LAST_TUNNEL_COUNT_FILE="$STATE_DIR/last-tunnel-count.txt"

# Runtime state
declare -a ALERT_HISTORY=()
SELECTED=0

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Monitor system metrics and send alerts to WaveTerm tab bar.

OPTIONS:
    --gpu-temp N           GPU temperature threshold (default: 80)
    --container-down BOOL   Alert when container count decreases (default: false)
    --tunnel-offline BOOL  Alert when tunnel count decreases (default: false)
    --poll-interval N      Poll interval in seconds (default: 10)
    -h, --help            Show this help

EXAMPLES:
    $(basename "$0") --gpu-temp 85 --container-down true
    $(basename "$0") --gpu-temp 90 --container-down true --tunnel-offline true
EOF
    exit 0
}

log_msg() {
    local msg="$1"
    echo -e "${DIM}[$(date '+%H:%M:%S')]${NC} $msg"
}

send_tab_alert() {
    local severity="$1"
    local message="$2"
    # OSC 777 escape sequence to notify WaveTerm tab bar
    printf '\033]777;alert;%s;%s\007' "$severity" "$message"
}

check_gpu_temp() {
    local current_temp
    current_temp=$(ssh -i "$SSH_KEY" -p "$SSH_PORT" "$SSH_HOST" \
        "nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader" 2>/dev/null || echo "0")
    current_temp=$(echo "$current_temp" | tr -d '[:space:]')

    if [[ -n "$current_temp" && "$current_temp" =~ ^[0-9]+$ ]]; then
        if (( current_temp > GPU_TEMP_THRESHOLD )); then
            local severity="warning"
            if (( current_temp > 95 )); then
                severity="critical"
            fi
            local msg="GPU temp ${current_temp}C exceeds threshold ${GPU_TEMP_THRESHOLD}C"
            add_alert "$severity" "$msg"
            log_msg "${RED}ALERT: ${msg}${NC}"
            send_tab_alert "$severity" "$msg"
        else
            log_msg "${GREEN}GPU temp: ${current_temp}C (ok)${NC}"
        fi
    else
        log_msg "${YELLOW}GPU temp check failed (ssh error)${NC}"
    fi
}

check_containers() {
    if [[ "$CONTAINER_DOWN_ALERT" != "true" ]]; then
        return 0
    fi

    local current_count
    current_count=$(ssh -i "$SSH_KEY" -p "$SSH_PORT" "$SSH_HOST" \
        "docker ps --format '{{.ID}}' 2>/dev/null | wc -l" || echo "-1")
    current_count=$(echo "$current_count" | tr -d '[:space:]')

    local last_count=0
    if [[ -f "$LAST_CONTAINER_COUNT_FILE" ]]; then
        last_count=$(cat "$LAST_CONTAINER_COUNT_FILE" 2>/dev/null | tr -d '[:space:]')
        last_count=${last_count:-0}
    fi

    # Save current count for next iteration
    echo "$current_count" > "$LAST_CONTAINER_COUNT_FILE"

    if [[ "$current_count" =~ ^[0-9]+$ ]] && (( last_count > 0 )) && (( current_count < last_count )); then
        local diff=$((last_count - current_count))
        local msg="Container count decreased: ${current_count} (was ${last_count}, ${diff} stopped)"
        add_alert "critical" "$msg"
        log_msg "${RED}ALERT: ${msg}${NC}"
        send_tab_alert "critical" "$msg"
    else
        log_msg "${GREEN}Containers: ${current_count} running${NC}"
    fi
}

check_tunnels() {
    if [[ "$TUNNEL_OFFLINE_ALERT" != "true" ]]; then
        return 0
    fi

    # Count SSH tunnels (adjust grep pattern for your tunnel naming)
    local current_count
    current_count=$(ssh -i "$SSH_KEY" -p "$SSH_PORT" "$SSH_HOST" \
        "ps aux | grep 'ssh.*-L' | grep -v grep | wc -l" 2>/dev/null || echo "-1")
    current_count=$(echo "$current_count" | tr -d '[:space:]')

    local last_count=0
    if [[ -f "$LAST_TUNNEL_COUNT_FILE" ]]; then
        last_count=$(cat "$LAST_TUNNEL_COUNT_FILE" 2>/dev/null | tr -d '[:space:]')
        last_count=${last_count:-0}
    fi

    # Save current count for next iteration
    echo "$current_count" > "$LAST_TUNNEL_COUNT_FILE"

    if [[ "$current_count" =~ ^[0-9]+$ ]] && (( last_count > 0 )) && (( current_count < last_count )); then
        local diff=$((last_count - current_count))
        local msg="Tunnel count decreased: ${current_count} (was ${last_count}, ${diff} offline)"
        add_alert "warning" "$msg"
        log_msg "${YELLOW}ALERT: ${msg}${NC}"
        send_tab_alert "warning" "$msg"
    else
        log_msg "${GREEN}Tunnels: ${current_count} active${NC}"
    fi
}

add_alert() {
    local severity="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    local alert_entry="[$timestamp] ${severity^^}: $message"
    ALERT_HISTORY+=("$alert_entry")

    # Keep only last MAX_ALERT_HISTORY alerts
    if (( ${#ALERT_HISTORY[@]} > MAX_ALERT_HISTORY )); then
        ALERT_HISTORY=("${ALERT_HISTORY[@]: -MAX_ALERT_HISTORY}")
    fi
}

load_alert_history() {
    if [[ -f "$ALERT_HISTORY_FILE" ]]; then
        while IFS= read -r line; do
            [[ -n "$line" ]] && ALERT_HISTORY+=("$line")
        done < "$ALERT_HISTORY_FILE"
        # Keep only last MAX_ALERT_HISTORY
        if (( ${#ALERT_HISTORY[@]} > MAX_ALERT_HISTORY )); then
            ALERT_HISTORY=("${ALERT_HISTORY[@]: -MAX_ALERT_HISTORY}")
        fi
    fi
}

save_alert_history() {
    mkdir -p "$STATE_DIR"
    printf '%s\n' "${ALERT_HISTORY[@]}" > "$ALERT_HISTORY_FILE"
}

render_screen() {
    clear -x
    echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║              WaveTerm Alert Monitor                          ║${NC}"
    echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo

    echo -e "${BOLD}Configuration:${NC}"
    echo -e "  GPU temp threshold:  ${YELLOW}${GPU_TEMP_THRESHOLD}C${NC}"
    echo -e "  Container alerts:   ${CONTAINER_DOWN_ALERT}"
    echo -e "  Tunnel alerts:      ${TUNNEL_OFFLINE_ALERT}"
    echo -e "  Poll interval:      ${POLL_INTERVAL}s"
    echo -e "  SSH target:         ${MAGENTA}${SSH_HOST}:${SSH_PORT}${NC}"
    echo

    echo -e "${BOLD}Monitoring Status:${NC}"
    local gpu_status
    if ssh -i "$SSH_KEY" -p "$SSH_PORT" -o ConnectTimeout=5 "$SSH_HOST" "exit 0" 2>/dev/null; then
        echo -e "  SSH connection:     ${GREEN}connected${NC}"
    else
        echo -e "  SSH connection:     ${RED}failed${NC}"
    fi
    echo

    echo -e "${BOLD}Recent Alerts (last ${MAX_ALERT_HISTORY}):${NC}"
    if (( ${#ALERT_HISTORY[@]} == 0 )); then
        echo -e "  ${DIM}No alerts recorded${NC}"
    else
        for i in "${!ALERT_HISTORY[@]}"; do
            local alert="${ALERT_HISTORY[$i]}"
            local prefix="  "
            if [[ "$alert" == *"CRITICAL"* ]]; then
                echo -e "${prefix}${RED}●${NC} ${alert#*] }"
            elif [[ "$alert" == *"WARNING"* ]]; then
                echo -e "${prefix}${YELLOW}●${NC} ${alert#*] }"
            else
                echo -e "${prefix}${DIM}●${NC} ${alert#*] }"
            fi
        done
    fi
    echo

    echo -e "${DIM}Press Ctrl+C to exit${NC}"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --gpu-temp)
            GPU_TEMP_THRESHOLD="$2"
            shift 2
            ;;
        --container-down)
            CONTAINER_DOWN_ALERT="$2"
            shift 2
            ;;
        --tunnel-offline)
            TUNNEL_OFFLINE_ALERT="$2"
            shift 2
            ;;
        --poll-interval)
            POLL_INTERVAL="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Ensure state directory exists
mkdir -p "$STATE_DIR"

# Load previous alert history
load_alert_history

# Save initial container/tunnel counts if not exist
if [[ ! -f "$LAST_CONTAINER_COUNT_FILE" ]]; then
    ssh -i "$SSH_KEY" -p "$SSH_PORT" "$SSH_HOST" \
        "docker ps --format '{{.ID}}' 2>/dev/null | wc -l" > "$LAST_CONTAINER_COUNT_FILE" 2>/dev/null || echo "0" > "$LAST_CONTAINER_COUNT_FILE"
fi

if [[ ! -f "$LAST_TUNNEL_COUNT_FILE" ]]; then
    ssh -i "$SSH_KEY" -p "$SSH_PORT" "$SSH_HOST" \
        "ps aux | grep 'ssh.*-L' | grep -v grep | wc -l" > "$LAST_TUNNEL_COUNT_FILE" 2>/dev/null || echo "0" > "$LAST_TUNNEL_COUNT_FILE"
fi

# Trap for cleanup
trap 'echo -e "\n${GREEN}Shutting down alert monitor...${NC}"; save_alert_history; exit 0' INT TERM

echo -e "${GREEN}Starting alert monitor...${NC}"
echo -e "${DIM}Press Ctrl+C to exit${NC}"
sleep 2

# Main monitoring loop
while true; do
    check_gpu_temp
    check_containers
    check_tunnels

    render_screen
    save_alert_history

    sleep "$POLL_INTERVAL"
done

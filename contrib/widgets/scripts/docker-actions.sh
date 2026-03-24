#!/bin/bash
#
# docker-actions.sh - Interactive Docker quick-actions widget
#
# SSH to phenix@dgx and manage Docker containers with keyboard shortcuts
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(dirname "$SCRIPT_DIR")/lib"

# Source widget state library if available
if [[ -f "$LIB_DIR/widget-state.sh" ]]; then
    source "$LIB_DIR/widget_state.sh" 2>/dev/null || source "$LIB_DIR/widget-state.sh" 2>/dev/null || true
fi

# Configuration
SSH_HOST="phenix@dgx"
SSH_PORT="2442"
SSH_KEY="$HOME/.ssh/id_ed25519"
STATE_DIR="${WIDGET_STATE_DIR:-$HOME/.waveterm/widget-state}"
LAST_SELECTED_FILE="$STATE_DIR/docker-actions-last-selected.txt"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# State
declare -a CONTAINERS=()
SELECTED=0
ACTION_RESULT=""

docker_ssh() {
    ssh -i "$SSH_KEY" -p "$SSH_PORT" -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$SSH_HOST" "$@"
}

fetch_containers() {
    CONTAINERS=()
    local container_data
    container_data=$(docker_ssh "docker ps -a --format '{{.ID}}|{{.Names}}|{{.Status}}|{{.State}}|{{.Image}}' 2>/dev/null" || echo "")

    if [[ -n "$container_data" ]]; then
        while IFS='|' read -r id name status state image; do
            CONTAINERS+=("$id|$name|$status|$state|$image")
        done <<< "$container_data"
    fi
}

get_container_state_color() {
    local state="$1"
    case "$state" in
        running) echo "$GREEN" ;;
        exited) echo "$RED" ;;
        restarting) echo "$YELLOW" ;;
        paused) echo "$CYAN" ;;
        created) echo "$DIM" ;;
        dead) echo "$MAGENTA" ;;
        *) echo "$NC" ;;
    esac
}

get_container_state_indicator() {
    local state="$1"
    case "$state" in
        running) echo "▶" ;;
        exited) echo "■" ;;
        restarting) echo "⟳" ;;
        paused) echo "⏸" ;;
        created) echo "○" ;;
        dead) echo "✕" ;;
        *) echo "?" ;;
    esac
}

render_container_list() {
    local start=$1
    local page_size=$((LINES - 12))
    local total=${#CONTAINERS[@]}
    local end=$((start + page_size))
    [[ $end -gt $total ]] && end=$total

    clear -x
    echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║           Docker Container Manager @ ${SSH_HOST}              ║${NC}"
    echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo

    if [[ -n "$ACTION_RESULT" ]]; then
        echo -e "${GREEN}✓ ${ACTION_RESULT}${NC}"
        echo
        ACTION_RESULT=""
    fi

    echo -e "${BOLD}Containers (${total} total):${NC}"
    echo -e "${DIM}─${NC}" | tr '─' '─'

    local display_start=$((start + 1))
    for i in $(seq $start $((end - 1))); do
        local data="${CONTAINERS[$i]}"
        IFS='|' read -r id name status state image <<< "$data"

        local color
        color=$(get_container_state_color "$state")
        local indicator
        indicator=$(get_container_state_indicator "$state")

        local line_prefix="  "
        local prefix_color="$NC"

        if (( i == SELECTED )); then
            line_prefix="${GREEN}→${NC} "
            prefix_color="$GREEN"
        fi

        # Truncate name if too long
        local display_name="$name"
        if [[ ${#display_name} -gt 20 ]]; then
            display_name="${display_name:0:17}..."
        fi

        local image_short="${image%%:*}"
        if [[ ${#image_short} -gt 20 ]]; then
            image_short="${image_short:0:17}..."
        fi

        echo -e "${line_prefix}${prefix_color}${color}${indicator}${NC} ${BOLD}${display_name}${NC} | ${image_short} | ${color}${status}${NC}"
    done

    echo -e "${DIM}─${NC}" | tr '─' '─'
    echo

    # Show navigation hint if more containers than fit on screen
    if (( total > page_size )); then
        echo -e "${DIM}Showing ${display_start}-${end} of ${total} | Page up/down to scroll${NC}"
    fi

    echo
    echo -e "${BOLD}Actions:${NC} ${GREEN}[s]${NC} start ${YELLOW}[t]${NC} stop ${RED}[r]${NC} restart ${CYAN}[l]${NC} logs ${MAGENTA}[i]${NC} inspect ${BLUE}[x]${NC} exec"
    echo -e "        ${GREEN}[j]${NC}/${YELLOW}[k]${NC} navigate ${DIM}[p]${NC}/${DIM}[n]${NC} page up/down ${RED}[q]${NC} quit"

    # Show selected container ID
    if (( ${#CONTAINERS[@]} > 0 && SELECTED < ${#CONTAINERS[@]} )); then
        local selected_data="${CONTAINERS[$SELECTED]}"
        IFS='|' read -r id name status state image <<< "$selected_data"
        echo -e "${DIM}Selected: ${id:0:12} (${name})${NC}"
    fi
}

do_start() {
    if (( ${#CONTAINERS[@]} == 0 )); then
        ACTION_RESULT="No containers available"
        return
    fi

    local selected_data="${CONTAINERS[$SELECTED]}"
    IFS='|' read -r id name status state image <<< "$selected_data"

    if [[ "$state" == "running" ]]; then
        ACTION_RESULT="Container '${name}' is already running"
        return
    fi

    docker_ssh "docker start '$name'" 2>/dev/null
    ACTION_RESULT="Started container: ${name}"
}

do_stop() {
    if (( ${#CONTAINERS[@]} == 0 )); then
        ACTION_RESULT="No containers available"
        return
    fi

    local selected_data="${CONTAINERS[$SELECTED]}"
    IFS='|' read -r id name status state image <<< "$selected_data"

    if [[ "$state" != "running" ]]; then
        ACTION_RESULT="Container '${name}' is not running"
        return
    fi

    docker_ssh "docker stop '$name'" 2>/dev/null
    ACTION_RESULT="Stopped container: ${name}"
}

do_restart() {
    if (( ${#CONTAINERS[@]} == 0 )); then
        ACTION_RESULT="No containers available"
        return
    fi

    local selected_data="${CONTAINERS[$SELECTED]}"
    IFS='|' read -r id name status state image <<< "$selected_data"

    docker_ssh "docker restart '$name'" 2>/dev/null
    ACTION_RESULT="Restarted container: ${name}"
}

do_logs() {
    if (( ${#CONTAINERS[@]} == 0 )); then
        ACTION_RESULT="No containers available"
        return
    fi

    local selected_data="${CONTAINERS[$SELECTED]}"
    IFS='|' read -r id name status state image <<< "$selected_data"

    clear -x
    echo -e "${BOLD}${CYAN}Logs for: ${name}${NC}"
    echo -e "${DIM}Press 'q' to return${NC}"
    echo

    docker_ssh "docker logs --tail 50 '$name'" 2>/dev/null | less -R -E -X -K

    # After exiting less, repaint the container list
    ACTION_RESULT="Viewed logs for: ${name}"
}

do_inspect() {
    if (( ${#CONTAINERS[@]} == 0 )); then
        ACTION_RESULT="No containers available"
        return
    fi

    local selected_data="${CONTAINERS[$SELECTED]}"
    IFS='|' read -r id name status state image <<< "$selected_data"

    clear -x
    echo -e "${BOLD}${CYAN}Inspect: ${name}${NC}"
    echo -e "${DIM}Press 'q' to return${NC}"
    echo

    docker_ssh "docker inspect '$name'" 2>/dev/null | less -R -E -X -K

    ACTION_RESULT="Inspected container: ${name}"
}

do_exec() {
    if (( ${#CONTAINERS[@]} == 0 )); then
        ACTION_RESULT="No containers available"
        return
    fi

    local selected_data="${CONTAINERS[$SELECTED]}"
    IFS='|' read -r id name status state image <<< "$selected_data"

    if [[ "$state" != "running" ]]; then
        ACTION_RESULT="Cannot exec into non-running container: ${name}"
        return
    fi

    echo -e "${BOLD}Opening shell in ${name}...${NC}"
    echo -e "${DIM}Type 'exit' to return to container list${NC}"

    docker_ssh "docker exec -it '$name' /bin/bash" 2>/dev/null
    # Re-fetch containers after returning from shell
    fetch_containers
    save_last_selected
    ACTION_RESULT="Exited shell: ${name}"
}

save_last_selected() {
    mkdir -p "$STATE_DIR"
    echo "$SELECTED" > "$LAST_SELECTED_FILE"
}

load_last_selected() {
    if [[ -f "$LAST_SELECTED_FILE" ]]; then
        local saved
        saved=$(cat "$LAST_SELECTED_FILE" 2>/dev/null | tr -d '[:space:]')
        if [[ -n "$saved" && "$saved" =~ ^[0-9]+$ ]]; then
            SELECTED=$saved
        fi
    fi
}

# Check SSH connectivity first
if ! docker_ssh "echo 0" > /dev/null 2>&1; then
    clear -x
    echo -e "${RED}Failed to connect to ${SSH_HOST}:${SSH_PORT}${NC}"
    echo -e "${DIM}Check SSH key and host availability${NC}"
    exit 1
fi

# Setup terminal
stty -echo 2>/dev/null || true
trap 'stty echo 2>/dev/null; exit 0' INT TERM

# Initial fetch and restore last selected
fetch_containers
load_last_selected

# Ensure selected index is valid
if (( SELECTED >= ${#CONTAINERS[@]} )); then
    SELECTED=0
fi

# Main loop
PAGER_OFFSET=0
LINES=$(tput lines 2>/dev/null || echo 24)

while true; do
    render_container_list "$PAGER_OFFSET"

    read -r -n 1 -t 10 key 2>/dev/null || true

    case "$key" in
        j|J)
            if (( SELECTED < ${#CONTAINERS[@]} - 1 )); then
                ((SELECTED++))
                # Auto-scroll if selection goes past visible area
                local page_size=$((LINES - 12))
                if (( SELECTED >= PAGER_OFFSET + page_size )); then
                    ((PAGER_OFFSET++))
                fi
            fi
            ;;
        k|K)
            if (( SELECTED > 0 )); then
                ((SELECTED--))
                if (( SELECTED < PAGER_OFFSET )); then
                    ((PAGER_OFFSET--))
                fi
            fi
            ;;
        n|N)
            # Page down
            ((PAGER_OFFSET += LINES - 12))
            [[ $PAGER_OFFSET -gt $((${#CONTAINERS[@]} - (LINES - 12))) ]] && PAGER_OFFSET=$((${#CONTAINERS[@]} - (LINES - 12)))
            [[ $PAGER_OFFSET -lt 0 ]] && PAGER_OFFSET=0
            ;;
        p|P)
            # Page up
            ((PAGER_OFFSET -= LINES - 12))
            [[ $PAGER_OFFSET -lt 0 ]] && PAGER_OFFSET=0
            ;;
        s|S)
            do_start
            fetch_containers
            save_last_selected
            [[ $SELECTED -ge ${#CONTAINERS[@]} ]] && SELECTED=0
            ;;
        t|T)
            do_stop
            fetch_containers
            save_last_selected
            ;;
        r|R)
            do_restart
            fetch_containers
            save_last_selected
            ;;
        l|L)
            do_logs
            ;;
        i|I)
            do_inspect
            ;;
        x|X)
            do_exec
            ;;
        q|Q)
            stty echo 2>/dev/null
            echo -e "\n${GREEN}Goodbye!${NC}"
            exit 0
            ;;
        '')
            # Timeout - refresh container list
            fetch_containers
            [[ $SELECTED -ge ${#CONTAINERS[@]} ]] && SELECTED=0
            ;;
    esac
done

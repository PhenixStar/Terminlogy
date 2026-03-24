#!/bin/bash
# fan-out-blocks.sh — Open a command across multiple SSH hosts as Wave Terminal blocks
# Usage: fan-out-blocks.sh "command" [host1 host2 ...]
# If no hosts, reads from ~/.config/waveterm/connections.json
# Each host opens as a separate terminal block in the current tab

CMD="${1:?Usage: fan-out-blocks.sh \"command\" [host1 host2 ...]}"
shift
HOSTS=("$@")

# If no hosts given, parse connections.json
if [ ${#HOSTS[@]} -eq 0 ]; then
    CONN_FILE="$HOME/.config/waveterm/connections.json"
    if [ -f "$CONN_FILE" ]; then
        # Extract SSH connection names (skip wsl://, bare IPs)
        HOSTS=($(jq -r 'keys[] | select(contains("@")) | select(startswith("wsl://") | not)' "$CONN_FILE" 2>/dev/null))
    fi
fi

if [ ${#HOSTS[@]} -eq 0 ]; then
    echo "Error: no hosts specified and none found in connections.json" >&2
    exit 1
fi

# Colors
CYAN='\033[36m'; DIM='\033[2m'; RESET='\033[0m'; BOLD='\033[1m'; GREEN='\033[32m'

echo -e "${BOLD}${CYAN}Fan-Out Blocks: ${CMD}${RESET}"
echo -e "${DIM}Opening ${#HOSTS[@]} blocks...${RESET}\n"

for conn in "${HOSTS[@]}"; do
    if command -v jq &>/dev/null; then
        meta=$(jq -nc --arg conn "$conn" --arg cmd "$CMD" \
            '{view:"term",controller:"cmd",connection:$conn,cmd:$cmd,"cmd:runonstart":true,"cmd:interactive":true}')
    else
        # Fallback: escape both values for JSON safety
        esc_conn=$(printf '%s' "$conn" | sed 's/[\\"]/\\&/g')
        esc_cmd=$(printf '%s' "$CMD" | sed 's/[\\"]/\\&/g')
        meta="{\"view\":\"term\",\"controller\":\"cmd\",\"connection\":\"${esc_conn}\",\"cmd\":\"${esc_cmd}\",\"cmd:runonstart\":true,\"cmd:interactive\":true}"
    fi
    wsh createblock --meta "$meta"
    echo -e "${GREEN}+ $conn${RESET}"
done

echo -e "\n${BOLD}Opened ${#HOSTS[@]} block(s)${RESET}"

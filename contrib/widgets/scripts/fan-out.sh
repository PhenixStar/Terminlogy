#!/bin/bash
# fan-out.sh — Run command across multiple SSH hosts in parallel
# Usage: fan-out.sh "command" [host1 host2 ...]
# If no hosts, reads from ~/.config/terminolgy/connections.json

CMD="${1:?Usage: fan-out.sh \"command\" [host1 host2 ...]}"
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

# Connection name to SSH params mapping
ssh_for_conn() {
    local conn="$1"
    local user="${conn%%@*}"
    local cfg="$HOME/.config/waveterm/connections.json"
    local hostname=$(jq -r ".\"$conn\".\"ssh:hostname\" // empty" "$cfg" 2>/dev/null)
    local port=$(jq -r ".\"$conn\".\"ssh:port\" // \"22\"" "$cfg" 2>/dev/null)
    local keyfile=$(jq -r ".\"$conn\".\"ssh:identityfile\"[0] // empty" "$cfg" 2>/dev/null)
    keyfile="${keyfile/#\~/$HOME}"

    # Fallback: if no hostname in config, parse host from connection string
    if [ -z "$hostname" ]; then
        hostname="${conn#*@}"
    fi

    local args="$user@$hostname -p $port"
    if [ -n "$keyfile" ] && [ -f "$keyfile" ]; then
        args="$args -i $keyfile"
    fi
    echo "$args"
}

# Colors
GREEN='\033[32m'; RED='\033[31m'; CYAN='\033[36m'; DIM='\033[2m'; RESET='\033[0m'; BOLD='\033[1m'

echo -e "${BOLD}${CYAN}Fan-Out: ${CMD}${RESET}"
echo -e "${DIM}Hosts: ${HOSTS[*]}${RESET}\n"

TMPDIR=$(mktemp -d)
PIDS=()
SUCCESS=0; FAIL=0

for conn in "${HOSTS[@]}"; do
    (
        read -ra SSH_ARGS <<< "$(ssh_for_conn "$conn")"
        ssh -o ConnectTimeout=10 -o BatchMode=yes "${SSH_ARGS[@]}" "$CMD" > "$TMPDIR/$conn.out" 2>&1
        echo $? > "$TMPDIR/$conn.rc"
    ) &
    PIDS+=($!)
done

for pid in "${PIDS[@]}"; do wait "$pid"; done

for conn in "${HOSTS[@]}"; do
    RC=$(cat "$TMPDIR/$conn.rc" 2>/dev/null || echo 1)
    if [ "$RC" -eq 0 ]; then
        echo -e "${GREEN}━━━ $conn ━━━${RESET}"
        SUCCESS=$((SUCCESS+1))
    else
        echo -e "${RED}━━━ $conn (exit $RC) ━━━${RESET}"
        FAIL=$((FAIL+1))
    fi
    cat "$TMPDIR/$conn.out"
    echo ""
done

rm -rf "$TMPDIR"
echo -e "${BOLD}Summary: ${GREEN}$SUCCESS OK${RESET}, ${RED}$FAIL failed${RESET} (${#HOSTS[@]} total)"

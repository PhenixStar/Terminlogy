#!/bin/bash
# ctx-launch.sh — Context-Aware Tool Launcher for WaveTerm
# Reads the current block's SSH connection + CWD and launches
# a tool (btop, lazygit, etc.) in a new block on that same context.
#
# Usage: ctx-launch.sh <tool> [split-direction]
#   tool: btop | lazygit | htop | tig | k9s | nvtop | dust | ncdu | mc
#   split: right (default) | down | replace
#
# When run from a WaveTerm terminal, it:
#   1. Detects the current connection (local or SSH)
#   2. Detects the current working directory
#   3. Opens a new block running the tool in that context

TOOL="${1:-btop}"
SPLIT="${2:-splitright}"

# Map split shorthand
case "$SPLIT" in
    right|r)   SPLIT="splitright" ;;
    down|d)    SPLIT="splitdown" ;;
    left|l)    SPLIT="splitleft" ;;
    up|u)      SPLIT="splitup" ;;
    replace|x) SPLIT="replace" ;;
esac

# Get current connection from WaveTerm environment
CONN="${TERMINOLGY_CONN:-}"
BLOCK_ID="${TERMINOLGY_BLOCKID:-}"

# Get current working directory
CWD="$(pwd)"

# Tool configurations: command, interactive flag, label
declare -A TOOL_CMD TOOL_LABEL TOOL_ICON
TOOL_CMD[btop]="btop"
TOOL_CMD[lazygit]="lazygit"
TOOL_CMD[htop]="htop"
TOOL_CMD[tig]="tig"
TOOL_CMD[k9s]="k9s"
TOOL_CMD[nvtop]="nvtop"
TOOL_CMD[dust]="dust"
TOOL_CMD[ncdu]="ncdu ."
TOOL_CMD[mc]="mc"
TOOL_CMD[docker]="lazydocker"
TOOL_CMD[gpu]="watch -n1 nvidia-smi"
TOOL_CMD[logs]="tail -f /var/log/syslog 2>/dev/null || journalctl -f"
TOOL_CMD[ports]="ss -tlnp || netstat -tlnp"

TOOL_LABEL[btop]="btop"
TOOL_LABEL[lazygit]="lazygit"
TOOL_LABEL[htop]="htop"
TOOL_LABEL[tig]="tig"
TOOL_LABEL[k9s]="k9s"
TOOL_LABEL[nvtop]="nvtop"
TOOL_LABEL[dust]="dust"
TOOL_LABEL[ncdu]="ncdu"
TOOL_LABEL[mc]="mc"
TOOL_LABEL[docker]="lazydocker"
TOOL_LABEL[gpu]="gpu-watch"
TOOL_LABEL[logs]="logs"
TOOL_LABEL[ports]="ports"

CMD="${TOOL_CMD[$TOOL]}"
LABEL="${TOOL_LABEL[$TOOL]:-$TOOL}"

if [[ -z "$CMD" ]]; then
    echo "Unknown tool: $TOOL"
    echo "Available: btop lazygit htop tig k9s nvtop dust ncdu mc docker gpu logs ports"
    exit 1
fi

# Build the meta JSON
META="{\"view\":\"term\",\"controller\":\"cmd\",\"cmd\":\"$CMD\",\"cmd:interactive\":true,\"cmd:runonstart\":true,\"cmd:clearonstart\":true"

# Add connection if we're on SSH
if [[ -n "$CONN" && "$CONN" != "local" ]]; then
    META="$META,\"connection\":\"$CONN\""
fi

# Add CWD
if [[ -n "$CWD" ]]; then
    # Escape backslashes for JSON (Windows paths)
    ESCAPED_CWD=$(echo "$CWD" | sed 's/\\/\\\\/g')
    META="$META,\"cmd:cwd\":\"$ESCAPED_CWD\""
fi

META="$META}"

# Use wsh to create the block
if command -v wsh &>/dev/null; then
    echo -e "\033[36mLaunching $LABEL on ${CONN:-local} in $CWD\033[0m"
    wsh createblock --magnified --meta "$META"
else
    # Fallback: just run the command directly
    echo -e "\033[33mwsh not available — running $TOOL directly\033[0m"
    eval "$CMD"
fi

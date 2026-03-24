#!/usr/bin/env bash
# load-workspace.sh — Load a Wave Terminal workspace from a JSON template
# Usage: ./load-workspace.sh <workspace.json>

set -euo pipefail

WORKSPACE_FILE="${1:-}"

if [[ -z "$WORKSPACE_FILE" ]]; then
    echo "Usage: $0 <workspace.json>" >&2
    exit 1
fi

if [[ ! -f "$WORKSPACE_FILE" ]]; then
    echo "Error: file not found: $WORKSPACE_FILE" >&2
    exit 1
fi

# Detect JSON parser
if command -v jq &>/dev/null; then
    parse_json() { jq -r "$1" "$WORKSPACE_FILE"; }
    parse_json_arr_len() { jq "$1 | length" "$WORKSPACE_FILE"; }
    parse_json_idx() { jq -r "$1" "$WORKSPACE_FILE"; }
else
    echo "jq not found, falling back to python3" >&2
    parse_json() {
        python3 -c "
import json, sys
data = json.load(open('$WORKSPACE_FILE'))
expr = '$1'
# naive jq-like path: strip leading . and split on .
parts = expr.lstrip('.').split('.')
val = data
for p in parts:
    if not p:
        continue
    val = val[p] if isinstance(val, dict) else val[int(p)]
print(val if val is not None else '')
"
    }
    parse_json_arr_len() {
        python3 -c "
import json
data = json.load(open('$WORKSPACE_FILE'))
parts = '$1'.lstrip('.').split('.')
val = data
for p in parts:
    if not p: continue
    val = val[p] if isinstance(val, dict) else val[int(p)]
print(len(val))
"
    }
    parse_json_idx() { parse_json "$1"; }
fi

WS_NAME=$(parse_json '.name')
WS_DESC=$(parse_json '.description')
echo "Loading workspace: $WS_NAME"
echo "  $WS_DESC"

TAB_COUNT=$(parse_json_arr_len '.tabs')
echo "Creating $TAB_COUNT tab(s)..."

for i in $(seq 0 $((TAB_COUNT - 1))); do
    TAB_TITLE=$(jq -r ".tabs[$i].title" "$WORKSPACE_FILE" 2>/dev/null || \
        python3 -c "import json; d=json.load(open('$WORKSPACE_FILE')); print(d['tabs'][$i].get('title','Tab'))")
    TAB_CONN=$(jq -r ".tabs[$i][\"tab:connection\"] // empty" "$WORKSPACE_FILE" 2>/dev/null || \
        python3 -c "import json; d=json.load(open('$WORKSPACE_FILE')); print(d['tabs'][$i].get('tab:connection',''))" 2>/dev/null || true)

    echo "  Tab $((i+1)): $TAB_TITLE"

    # Create new tab
    TAB_ID=$(wsh tab open --title "$TAB_TITLE" 2>/dev/null || echo "")

    # Set connection if specified
    if [[ -n "$TAB_CONN" && -n "$TAB_ID" ]]; then
        wsh meta set --tab "$TAB_ID" "tab:connection=$TAB_CONN" 2>/dev/null || true
    fi

    # Create blocks
    BLOCK_COUNT=$(jq ".tabs[$i].blocks | length" "$WORKSPACE_FILE" 2>/dev/null || \
        python3 -c "import json; d=json.load(open('$WORKSPACE_FILE')); print(len(d['tabs'][$i].get('blocks',[])))")

    for j in $(seq 0 $((BLOCK_COUNT - 1))); do
        BLOCK_VIEW=$(jq -r ".tabs[$i].blocks[$j].view" "$WORKSPACE_FILE" 2>/dev/null || \
            python3 -c "import json; d=json.load(open('$WORKSPACE_FILE')); print(d['tabs'][$i]['blocks'][$j].get('view',''))")

        echo "    Block $((j+1)): $BLOCK_VIEW"

        if [[ -n "$TAB_ID" ]]; then
            wsh block new --tab "$TAB_ID" --view "$BLOCK_VIEW" 2>/dev/null || true
        fi
    done
done

echo "Workspace '$WS_NAME' loaded."

#!/bin/bash
#
# clipboard-history.sh - Clipboard history ring buffer widget
#
# Monitor clipboard every 2 seconds, store last 50 entries, display with timestamps
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="${WIDGET_STATE_DIR:-$HOME/.waveterm/widget-state}"
HISTORY_FILE="$STATE_DIR/clipboard-history.txt"
MAX_ENTRIES=50
POLL_INTERVAL=2
TRUNCATE_LEN=80
SEARCH_QUERY=""

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
declare -a CLIPBOARD_HISTORY=()
LAST_CONTENT=""
SELECTED=0
MODE="normal"  # normal, search, confirm_clear

get_clipboard() {
    local content=""

    # Windows PowerShell
    if command -v powershell &>/dev/null; then
        content=$(powershell -Command 'Get-Clipboard -Format Text -Raw' 2>/dev/null || echo "")

    # Linux xclip
    elif command -v xclip &>/dev/null; then
        content=$(xclip -selection clipboard -o 2>/dev/null || echo "")

    # Linux xsel
    elif command -v xsel &>/dev/null; then
        content=$(xsel --clipboard --output 2>/dev/null || echo "")

    # macOS
    elif command -v pbpaste &>/dev/null; then
        content=$(pbpaste 2>/dev/null || echo "")

    else
        echo "No clipboard tool found" >&2
        return 1
    fi

    # Normalize line endings and trim whitespace
    content=$(echo "$content" | tr -d '\r' | sed 's/[[:space:]]*$//')

    echo "$content"
}

load_history() {
    CLIPBOARD_HISTORY=()
    if [[ -f "$HISTORY_FILE" ]]; then
        while IFS= read -r line; do
            [[ -n "$line" ]] && CLIPBOARD_HISTORY+=("$line")
        done < "$HISTORY_FILE"

        # Keep only last MAX_ENTRIES
        if (( ${#CLIPBOARD_HISTORY[@]} > MAX_ENTRIES )); then
            CLIPBOARD_HISTORY=("${CLIPBOARD_HISTORY[@]: -MAX_ENTRIES}")
        fi
    fi
}

save_history() {
    mkdir -p "$STATE_DIR"
    printf '%s\n' "${CLIPBOARD_HISTORY[@]}" > "$HISTORY_FILE"
}

add_entry() {
    local content="$1"

    # Skip empty content
    [[ -z "$content" ]] && return

    # Skip duplicates (check last entry only for performance)
    if (( ${#CLIPBOARD_HISTORY[@]} > 0 )); then
        local last_entry="${CLIPBOARD_HISTORY[-1]}"
        # Extract content from stored format (timestamp|content)
        local last_content="${last_entry#*|}"
        if [[ "$last_content" == "$content" ]]; then
            return  # Skip duplicate
        fi
    fi

    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    local entry="${timestamp}|${content}"
    CLIPBOARD_HISTORY+=("$entry")

    # Maintain max entries
    if (( ${#CLIPBOARD_HISTORY[@]} > MAX_ENTRIES )); then
        CLIPBOARD_HISTORY=("${CLIPBOARD_HISTORY[@]: -MAX_ENTRIES}")
    fi

    save_history
}

truncate_content() {
    local content="$1"
    local max_len=$2

    # Remove newlines for display
    content=$(echo "$content" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g')

    if [[ ${#content} -gt $max_len ]]; then
        echo "${content:0:$((max_len - 3))}..."
    else
        echo "$content"
    fi
}

copy_to_clipboard() {
    local content="$1"

    # Windows PowerShell
    if command -v powershell &>/dev/null; then
        echo "$content" | powershell -Command 'Set-Clipboard -Value $input' 2>/dev/null

    # Linux xclip
    elif command -v xclip &>/dev/null; then
        echo "$content" | xclip -selection clipboard

    # Linux xsel
    elif command -v xsel &>/dev/null; then
        echo "$content" | xsel --clipboard --input

    # macOS
    elif command -v pbcopy &>/dev/null; then
        echo "$content" | pbcopy

    else
        echo "No clipboard tool found" >&2
        return 1
    fi
}

render_screen() {
    local start=$1
    local page_size=$((LINES - 10))
    local filtered=("${CLIPBOARD_HISTORY[@]}")

    # Apply search filter
    if [[ -n "$SEARCH_QUERY" ]]; then
        filtered=()
        for entry in "${CLIPBOARD_HISTORY[@]}"; do
            local content="${entry#*|}"
            if [[ "$content" == *"$SEARCH_QUERY"* ]]; then
                filtered+=("$entry")
            fi
        done
    fi

    local total=${#filtered[@]}
    local end=$((start + page_size))
    [[ $end -gt $total ]] && end=$total

    clear -x

    echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║              Clipboard History (${total} entries)                  ║${NC}"
    echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo

    if [[ -n "$SEARCH_QUERY" ]]; then
        echo -e "${BOLD}Search: ${YELLOW}${SEARCH_QUERY}${NC} ${DIM}(Press / to change, Esc to clear)${NC}"
        echo
    fi

    if [[ "$MODE" == "confirm_clear" ]]; then
        echo -e "${RED}${BOLD}⚠ Clear all clipboard history?${NC}"
        echo -e "${GREEN}[y]${NC} Yes, clear all   ${RED}[n]${NC} No, cancel"
        echo
        return
    fi

    if (( total == 0 )); then
        echo -e "${DIM}No clipboard entries${NC}"
        if [[ -n "$SEARCH_QUERY" ]]; then
            echo -e "${DIM}No matches for '${SEARCH_QUERY}'${NC}"
        fi
    else
        echo -e "${BOLD}Recent clipboard entries:${NC}"
        echo -e "${DIM}─${NC}" | tr '─' '─'

        local display_start=$((start + 1))
        for i in $(seq $start $((end - 1))); do
            local entry="${filtered[$i]}"
            local timestamp="${entry%%|*}"
            local content="${entry#*|}"

            local line_prefix="  "
            local prefix_color="$NC"
            local highlight=""

            if (( i == SELECTED )); then
                line_prefix="${GREEN}→${NC} "
                prefix_color="$GREEN"
                highlight="${BOLD}"
            fi

            # Highlight search matches
            if [[ -n "$SEARCH_QUERY" ]]; then
                # Mark the matching portion
                content=$(echo "$content" | sed "s/${SEARCH_QUERY}/${YELLOW}${BOLD}${SEARCH_QUERY}${NC}${highlight}/gI")
            fi

            local truncated
            truncated=$(truncate_content "$content" "$TRUNCATE_LEN")

            echo -e "${line_prefix}${prefix_color}${highlight}[$((i + 1))]${NC} ${DIM}${timestamp}${NC}"
            echo -e "${line_prefix}${highlight}${truncated}${NC}"
        done

        echo -e "${DIM}─${NC}" | tr '─' '─'
    fi

    echo

    # Navigation hint
    if (( total > page_size )); then
        local display_start=$((start + 1))
        echo -e "${DIM}Showing ${display_start}-${end} of ${total}${NC}"
    fi

    echo
    echo -e "${BOLD}Actions:${NC} ${GREEN}[1-9,0]${NC} select & copy ${MAGENTA}[/]${NC} search ${CYAN}[c]${NC} clear ${RED}[q]${NC} quit"
    echo -e "        ${GREEN}[j]${NC}/${YELLOW}[k]${NC} navigate ${DIM}[p]${NC}/${DIM}[n]${NC} page up/down ${DIM}[Enter]${NC} copy selected"

    # Show clipboard status
    echo -e "${DIM}Clipboard monitoring active (every ${POLL_INTERVAL}s)${NC}"
}

handle_search() {
    echo -e "\n${BOLD}Search:${NC} ${YELLOW}${SEARCH_QUERY}${NC}"
    echo -ne "${DIM}Type to search (Esc to cancel): ${NC}"

    local search_input=""
    local key

    while true; do
        read -r -n 1 key 2>/dev/null || true

        case "$key" in
            $'\e')  # Escape
                return
                ;;
            $'\177'|$'\010')  # Backspace/Delete
                if [[ ${#search_input} -gt 0 ]]; then
                    search_input="${search_input:0:-1}"
                    SEARCH_QUERY="$search_input"
                    echo -ne "\r${DIM}Type to search (Esc to cancel): ${NC}${search_input} \b \b"
                fi
                ;;
            $'\r'|$'\n')  # Enter
                return
                ;;
            '')
                return
                ;;
            *)
                if [[ ${#key} -eq 1 && "$key" =~ [[:print:]] ]]; then
                    search_input+="$key"
                    SEARCH_QUERY="$search_input"
                    echo -ne "\r${DIM}Type to search (Esc to cancel): ${NC}${search_input} \b \b"
                fi
                ;;
        esac
    done
}

handle_confirm_clear() {
    local key
    read -r -n 1 key 2>/dev/null || true

    case "$key" in
        y|Y)
            CLIPBOARD_HISTORY=()
            > "$HISTORY_FILE"
            MODE="normal"
            echo -e "\n${GREEN}Clipboard history cleared${NC}"
            sleep 1
            ;;
        *)
            MODE="normal"
            ;;
    esac
}

copy_selected() {
    local filtered=("${CLIPBOARD_HISTORY[@]}")

    # Apply search filter
    if [[ -n "$SEARCH_QUERY" ]]; then
        filtered=()
        for entry in "${CLIPBOARD_HISTORY[@]}"; do
            local content="${entry#*|}"
            if [[ "$content" == *"$SEARCH_QUERY"* ]]; then
                filtered+=("$entry")
            fi
        done
    fi

    if (( ${#filtered[@]} == 0 )); then
        return
    fi

    local entry="${filtered[$SELECTED]}"
    local content="${entry#*|}"

    copy_to_clipboard "$content"
    echo -e "\n${GREEN}✓ Copied to clipboard${NC}"
    sleep 0.5
}

# Main
mkdir -p "$STATE_DIR"
load_history

# Check clipboard tools
if ! get_clipboard &>/dev/null; then
    clear -x
    echo -e "${RED}Error: No clipboard tool available${NC}"
    echo -e "${DIM}Supported: PowerShell (Windows), xclip/xsel (Linux), pbpaste (macOS)${NC}"
    exit 1
fi

# Setup terminal
stty -echo 2>/dev/null || true
trap 'stty echo 2>/dev/null; exit 0' INT TERM

# Initial content
LAST_CONTENT=$(get_clipboard)

LINES=$(tput lines 2>/dev/null || echo 24)
PAGER_OFFSET=0

while true; do
    if [[ "$MODE" == "confirm_clear" ]]; then
        render_screen "$PAGER_OFFSET"
        handle_confirm_clear
        continue
    fi

    # Poll clipboard
    local current_content
    current_content=$(get_clipboard)

    if [[ -n "$current_content" && "$current_content" != "$LAST_CONTENT" ]]; then
        add_entry "$current_content"
        LAST_CONTENT="$current_content"
    fi

    render_screen "$PAGER_OFFSET"

    # Check for keypress with timeout
    local key
    read -r -n 1 -t "$POLL_INTERVAL" key 2>/dev/null || true

    case "$key" in
        # Number keys 1-9 for direct selection
        [1-9])
            local num=$(( $(echo "$key" | tr '1-9' '1-9') - 1 ))
            if (( num < ${#CLIPBOARD_HISTORY[@]} )); then
                SELECTED=$num
                copy_selected
            fi
            ;;
        # 0 = 10th entry
        0)
            SELECTED=9
            if (( SELECTED < ${#CLIPBOARD_HISTORY[@]} )); then
                copy_selected
            fi
            ;;
        /)
            SEARCH_QUERY=""
            handle_search
            if [[ -z "$SEARCH_QUERY" ]]; then
                SEARCH_QUERY=""
            fi
            SELECTED=0
            PAGER_OFFSET=0
            ;;
        c)
            MODE="confirm_clear"
            ;;
        j|J)
            if (( SELECTED < ${#CLIPBOARD_HISTORY[@]} - 1 )); then
                ((SELECTED++))
                local page_size=$((LINES - 10))
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
            ((PAGER_OFFSET += LINES - 10))
            local total=${#CLIPBOARD_HISTORY[@]}
            local page_size=$((LINES - 10))
            [[ $PAGER_OFFSET -gt $((total - page_size)) ]] && PAGER_OFFSET=$((total - page_size))
            [[ $PAGER_OFFSET -lt 0 ]] && PAGER_OFFSET=0
            ;;
        p|P)
            ((PAGER_OFFSET -= LINES - 10))
            [[ $PAGER_OFFSET -lt 0 ]] && PAGER_OFFSET=0
            ;;
        $'\e')  # Escape
            if [[ -n "$SEARCH_QUERY" ]]; then
                SEARCH_QUERY=""
                SELECTED=0
                PAGER_OFFSET=0
            fi
            ;;
        $'\r'|$'\n')  # Enter
            copy_selected
            ;;
        q|Q)
            stty echo 2>/dev/null
            echo -e "\n${GREEN}Goodbye!${NC}"
            exit 0
            ;;
        '')
            # Timeout - refresh, keep position valid
            if (( SELECTED >= ${#CLIPBOARD_HISTORY[@]} )); then
                SELECTED=0
                PAGER_OFFSET=0
            fi
            ;;
    esac
done

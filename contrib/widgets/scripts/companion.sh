#!/bin/bash
# companion.sh — Interactive Context-Aware Companion Tool Picker
# Shows a menu of dev tools; launches the selected one in a new WaveTerm
# block that inherits the current SSH connection and working directory.
#
# Drop this in your shell as an alias:
#   alias cc='bash /path/to/companion.sh'
# Then just type 'cc' in any terminal (local or SSH) to get the picker.

ESC='\033'
BOLD="${ESC}[1m"
DIM="${ESC}[2m"
GREEN="${ESC}[32m"
CYAN="${ESC}[36m"
YELLOW="${ESC}[33m"
MAGENTA="${ESC}[35m"
RED="${ESC}[31m"
RESET="${ESC}[0m"

CONN="${WAVETERM_CONN:-local}"
CWD="$(pwd)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Detect what's available on the current host
check_cmd() { command -v "$1" &>/dev/null; }

show_menu() {
    clear
    echo -e "${BOLD}${CYAN}  Companion Tools${RESET}  ${DIM}(${CONN} : ${CWD})${RESET}"
    echo -e "${DIM}  Press key to launch in split, Shift+key for magnified${RESET}"
    echo ""

    # System monitoring
    echo -e "  ${MAGENTA}System${RESET}"
    printf "  ${GREEN}[b]${RESET} %-14s" "btop"
    check_cmd btop  && echo -e "${DIM}system monitor${RESET}" || echo -e "${RED}not installed${RESET}"
    printf "  ${GREEN}[h]${RESET} %-14s" "htop"
    check_cmd htop  && echo -e "${DIM}process viewer${RESET}" || echo -e "${RED}not installed${RESET}"
    printf "  ${GREEN}[n]${RESET} %-14s" "nvtop"
    check_cmd nvtop && echo -e "${DIM}GPU monitor${RESET}"     || echo -e "${RED}not installed${RESET}"
    printf "  ${GREEN}[g]${RESET} %-14s" "nvidia-smi"
    check_cmd nvidia-smi && echo -e "${DIM}GPU status (watch)${RESET}" || echo -e "${RED}no GPU${RESET}"

    # Git
    echo ""
    echo -e "  ${MAGENTA}Git${RESET}"
    printf "  ${GREEN}[l]${RESET} %-14s" "lazygit"
    check_cmd lazygit && echo -e "${DIM}git TUI${RESET}"   || echo -e "${RED}not installed${RESET}"
    printf "  ${GREEN}[t]${RESET} %-14s" "tig"
    check_cmd tig     && echo -e "${DIM}git history${RESET}" || echo -e "${RED}not installed${RESET}"

    # Docker/K8s
    echo ""
    echo -e "  ${MAGENTA}Containers${RESET}"
    printf "  ${GREEN}[d]${RESET} %-14s" "lazydocker"
    check_cmd lazydocker && echo -e "${DIM}docker TUI${RESET}" || echo -e "${RED}not installed${RESET}"
    printf "  ${GREEN}[k]${RESET} %-14s" "k9s"
    check_cmd k9s        && echo -e "${DIM}kubernetes TUI${RESET}" || echo -e "${RED}not installed${RESET}"

    # Files
    echo ""
    echo -e "  ${MAGENTA}Files${RESET}"
    printf "  ${GREEN}[u]${RESET} %-14s" "ncdu"
    check_cmd ncdu && echo -e "${DIM}disk usage analyzer${RESET}" || echo -e "${RED}not installed${RESET}"
    printf "  ${GREEN}[x]${RESET} %-14s" "dust"
    check_cmd dust && echo -e "${DIM}disk usage (rust)${RESET}"   || echo -e "${RED}not installed${RESET}"
    printf "  ${GREEN}[m]${RESET} %-14s" "mc"
    check_cmd mc   && echo -e "${DIM}midnight commander${RESET}"  || echo -e "${RED}not installed${RESET}"

    echo ""
    echo -e "  ${DIM}[q] quit${RESET}"
}

launch() {
    local tool="$1"
    local magnified="${2:-false}"
    bash "$SCRIPT_DIR/ctx-launch.sh" "$tool" "splitright"
}

show_menu

while true; do
    read -rsn1 key
    case "$key" in
        b) launch btop ;;
        h) launch htop ;;
        n) launch nvtop ;;
        g) launch gpu ;;
        l) launch lazygit ;;
        t) launch tig ;;
        d) launch docker ;;
        k) launch k9s ;;
        u) launch ncdu ;;
        x) launch dust ;;
        m) launch mc ;;
        q|Q) echo -e "\n${DIM}  Done${RESET}"; exit 0 ;;
        *) ;;
    esac
    # Brief pause then redraw
    sleep 0.3
    show_menu
done

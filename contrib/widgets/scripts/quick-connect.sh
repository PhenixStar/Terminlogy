#!/bin/bash
# Quick-Connect Bookmarks — WaveTerm Widget
# Shows bookmarked SSH+command combos as a selection menu

ESC='\033'
BOLD="${ESC}[1m"
DIM="${ESC}[2m"
GREEN="${ESC}[32m"
CYAN="${ESC}[36m"
YELLOW="${ESC}[33m"
WHITE="${ESC}[37m"
RESET="${ESC}[0m"

declare -A BOOKMARKS=(
    ["1"]="DGX Docker|phenix@dgx|docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'"
    ["2"]="DGX GPU Monitor|phenix@dgx|nvidia-smi -l 5"
    ["3"]="DGX Logs (nginx)|phenix@dgx|tail -f /var/log/nginx/access.log"
    ["4"]="DGX Ollama Models|phenix@dgx|ollama list"
    ["5"]="DGX Disk Usage|phenix@dgx|df -h /raid /opt /home"
    ["6"]="Annex4 Status|alaa@annex4|/system resource print; /interface print stats"
    ["7"]="MikroTik HQ Status|alaa@mikrotik-hq|/system resource print; /interface print stats"
    ["8"]="MCE VPS Status|root@mce-new|htop -t || top -bn1 | head -20"
    ["9"]="DGX Tunnel Health|phenix@dgx|docker ps --filter name=-tunnel --format 'table {{.Names}}\t{{.Status}}'"
    ["0"]="DGX VRAM Usage|phenix@dgx|nvidia-smi --query-gpu=index,name,memory.used,memory.total,utilization.gpu --format=csv"
)

BOOKMARK_ORDER=("1" "2" "3" "4" "5" "6" "7" "8" "9" "0")

show_menu() {
    clear
    echo -e "${BOLD}${CYAN}  Quick-Connect Bookmarks${RESET}"
    echo -e "${DIM}  Press number to connect, q to quit${RESET}"
    echo ""

    for key in "${BOOKMARK_ORDER[@]}"; do
        IFS='|' read -r label conn cmd <<< "${BOOKMARKS[$key]}"
        printf "  ${GREEN}[%s]${RESET} ${BOLD}%-22s${RESET} ${DIM}%s${RESET}\n" "$key" "$label" "$conn"
    done

    echo ""
    echo -e "${DIM}  Commands execute via wsh on the target connection${RESET}"
}

show_menu

while true; do
    read -rsn1 key
    if [[ "$key" == "q" || "$key" == "Q" ]]; then
        echo -e "\n${DIM}  Bye${RESET}"
        exit 0
    fi

    if [[ -n "${BOOKMARKS[$key]}" ]]; then
        IFS='|' read -r label conn cmd <<< "${BOOKMARKS[$key]}"
        echo -e "\n${YELLOW}  Connecting to ${conn}...${RESET}"
        echo -e "${DIM}  Running: ${cmd}${RESET}\n"

        # Use wsh if available, fallback to direct SSH
        if command -v wsh &>/dev/null; then
            wsh ssh "$conn" -c "$cmd"
        else
            # Map connection names to SSH params
            case "$conn" in
                "phenix@dgx")
                    ssh -o ConnectTimeout=10 -i ~/.ssh/id_ed25519 -p 2442 phenix@120.28.138.55 "$cmd"
                    ;;
                "alaa@annex4")
                    ssh -o ConnectTimeout=5 -i ~/.ssh/id_ed25519_alaa -p 2222 alaa@10.1.1.1 "$cmd"
                    ;;
                "alaa@mikrotik-hq")
                    ssh -o ConnectTimeout=5 -i ~/.ssh/id_ed25519_alaa -p 2222 alaa@10.10.101.1 "$cmd"
                    ;;
                "root@mce-new")
                    ssh -o ConnectTimeout=10 -i ~/.ssh/id_ed25519_alaa -p 2222 root@152.42.191.40 "$cmd"
                    ;;
                *)
                    echo -e "${YELLOW}  Unknown connection: ${conn}${RESET}"
                    ;;
            esac
        fi

        echo -e "\n${DIM}  Press any key to return to menu...${RESET}"
        read -rsn1
        show_menu
    fi
done

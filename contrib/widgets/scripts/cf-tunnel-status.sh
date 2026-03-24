#!/usr/bin/env bash
# cf-tunnel-status.sh — WaveTerm widget: Cloudflare tunnel health on DGX1
# Polls every 30 seconds via SSH and renders an ANSI-colored table.

# ── SSH config ────────────────────────────────────────────────────────────────
SSH_HOST="120.28.138.55"
SSH_PORT="2442"
SSH_USER="phenix"
SSH_KEY="${HOME}/.ssh/id_ed25519"
POLL_INTERVAL=30

# ── Tunnel → domain mapping ───────────────────────────────────────────────────
declare -A DOMAIN_MAP=(
  [voicebox]="voice.nulled.ai"
  [hive]="hive.nulled.ai"
  [columbus]="columbus.nulled.ai"
  [lobe]="l.mce.ph"
  [telegram]="telegram.nulled.ai"
  [aion]="aion.nulled.ai"
  [nvr]="nvrold.mce.ph"
  [webclaw]="webclaw.nulled.ai"
  [crabwalk]="crabwalk.nulled.ai"
  [archestra]="archestra.nulled.ai"
  [clowdbot]="bot.mce.ph"
  [cloudflared]="ui.mce.ph"
  [zen]="zen.nulled.ai"
  [nulled-ai]="nulled.ai"
  [skillforge]="dev-skillforge.nulled.ai"
  [flameboard]="dev-flameboard.nulled.ai"
  [basira]="dev-basira.nulled.ai"
  [deepagents]="dev-deepagents.nulled.ai"
  [bariq]="dev-tau.nulled.ai"
  [scorch]="dev-bentopdf.nulled.ai"
  [sentinel]="sentinel.nulled.ai"
)

# ── ANSI colors ───────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# ── Helpers ───────────────────────────────────────────────────────────────────
ssh_cmd() {
  ssh \
    -i "${SSH_KEY}" \
    -p "${SSH_PORT}" \
    -o BatchMode=yes \
    -o ConnectTimeout=8 \
    -o StrictHostKeyChecking=no \
    "${SSH_USER}@${SSH_HOST}" \
    "$@"
}

clear_screen() {
  printf '\033[2J\033[H'
}

print_header() {
  local ts
  ts=$(date '+%Y-%m-%d %H:%M:%S')
  printf "${BOLD}${CYAN}Cloudflare Tunnels — dgx-station${RESET}  ${DIM}%s${RESET}\n" "${ts}"
  printf "${DIM}%-22s %-12s %-20s %-30s${RESET}\n" "TUNNEL" "STATUS" "UPTIME" "DOMAIN"
  printf "${DIM}%s${RESET}\n" "$(printf '─%.0s' {1..87})"
}

color_status() {
  local raw="$1"
  case "${raw}" in
    Up*)         printf "${GREEN}%-12s${RESET}" "${raw}" ;;
    Exited*)     printf "${RED}%-12s${RESET}"   "${raw}" ;;
    Restarting*) printf "${YELLOW}%-12s${RESET}" "${raw}" ;;
    *)           printf "%-12s"                 "${raw}" ;;
  esac
}

render() {
  local raw_output="$1"
  local healthy=0 down=0 total=0

  while IFS='|' read -r name status uptime; do
    [[ -z "${name}" ]] && continue

    # Strip leading/trailing whitespace
    name="${name#"${name%%[![:space:]]*}"}"
    name="${name%"${name##*[![:space:]]}"}"
    status="${status#"${status%%[![:space:]]*}"}"
    status="${status%"${status##*[![:space:]]}"}"
    uptime="${uptime#"${uptime%%[![:space:]]*}"}"
    uptime="${uptime%"${uptime##*[![:space:]]}"}"

    # Derive display name: strip -tunnel suffix
    display="${name%-tunnel}"

    # Look up domain
    local domain="${DOMAIN_MAP[${display}]:-—}"

    # Classify
    (( total++ ))
    if [[ "${status}" == Up* ]]; then
      (( healthy++ ))
    else
      (( down++ ))
    fi

    printf "%-22s " "${display}"
    color_status "${status}"
    printf " %-20s %-30s\n" "${uptime}" "${domain}"

  done <<< "${raw_output}"

  printf "${DIM}%s${RESET}\n" "$(printf '─%.0s' {1..87})"
  printf "  ${GREEN}%d healthy${RESET}  ${RED}%d down${RESET}  ${DIM}%d total${RESET}\n" \
    "${healthy}" "${down}" "${total}"
}

# ── Main loop ─────────────────────────────────────────────────────────────────
while true; do
  clear_screen
  print_header

  raw=$(ssh_cmd docker ps -a \
    --filter 'name=-tunnel' \
    --format '{{.Names}}|{{.Status}}|{{.RunningFor}}' 2>&1)

  ssh_exit=$?

  if [[ ${ssh_exit} -ne 0 ]]; then
    printf "\n${RED}SSH error (exit %d): %s${RESET}\n" "${ssh_exit}" "${raw}"
  elif [[ -z "${raw}" ]]; then
    printf "\n${YELLOW}No tunnel containers found.${RESET}\n"
  else
    render "${raw}"
  fi

  printf "\n${DIM}Next refresh in ${POLL_INTERVAL}s — Ctrl-C to exit${RESET}\n"
  sleep "${POLL_INTERVAL}"
done

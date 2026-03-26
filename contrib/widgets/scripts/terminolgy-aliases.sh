#!/bin/bash
# terminolgy-aliases.sh — Source this from .bashrc or .zshrc
# Provides context-aware companion tool shortcuts in Terminolgy
#
# Usage: source /path/to/terminolgy-aliases.sh
# Then use: cc (picker), cbtop, clg, chtop, etc.

_TERMINOLGY_SCRIPTS="${TERMINOLGY_WIDGETS_DIR:-D:/Dev/terminolgy-widgets/scripts}"

# Only define aliases when running inside Terminolgy
if [[ -n "$TERMINOLGY" ]]; then
    # Interactive picker
    alias cc="bash $_TERMINOLGY_SCRIPTS/companion.sh"

    # Direct launchers (context-aware — inherit connection + CWD)
    alias cbtop="bash $_TERMINOLGY_SCRIPTS/ctx-launch.sh btop"
    alias clg="bash $_TERMINOLGY_SCRIPTS/ctx-launch.sh lazygit"
    alias chtop="bash $_TERMINOLGY_SCRIPTS/ctx-launch.sh htop"
    alias ctig="bash $_TERMINOLGY_SCRIPTS/ctx-launch.sh tig"
    alias ck9s="bash $_TERMINOLGY_SCRIPTS/ctx-launch.sh k9s"
    alias cnvtop="bash $_TERMINOLGY_SCRIPTS/ctx-launch.sh nvtop"
    alias cdust="bash $_TERMINOLGY_SCRIPTS/ctx-launch.sh dust"
    alias cncdu="bash $_TERMINOLGY_SCRIPTS/ctx-launch.sh ncdu"
    alias cmc="bash $_TERMINOLGY_SCRIPTS/ctx-launch.sh mc"
    alias cdocker="bash $_TERMINOLGY_SCRIPTS/ctx-launch.sh docker"
    alias cgpu="bash $_TERMINOLGY_SCRIPTS/ctx-launch.sh gpu"

    # Split direction variants
    alias ccr="bash $_TERMINOLGY_SCRIPTS/ctx-launch.sh"        # default: split right
    alias ccd="bash $_TERMINOLGY_SCRIPTS/ctx-launch.sh btop down"  # split down
fi

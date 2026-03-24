#!/bin/bash
# waveterm-aliases.sh — Source this from .bashrc or .zshrc
# Provides context-aware companion tool shortcuts in WaveTerm
#
# Usage: source /path/to/waveterm-aliases.sh
# Then use: cc (picker), cbtop, clg, chtop, etc.

_WAVETERM_SCRIPTS="${WAVETERM_WIDGETS_DIR:-D:/Dev/waveterm-widgets/scripts}"

# Only define aliases when running inside WaveTerm
if [[ -n "$WAVETERM" ]]; then
    # Interactive picker
    alias cc="bash $_WAVETERM_SCRIPTS/companion.sh"

    # Direct launchers (context-aware — inherit connection + CWD)
    alias cbtop="bash $_WAVETERM_SCRIPTS/ctx-launch.sh btop"
    alias clg="bash $_WAVETERM_SCRIPTS/ctx-launch.sh lazygit"
    alias chtop="bash $_WAVETERM_SCRIPTS/ctx-launch.sh htop"
    alias ctig="bash $_WAVETERM_SCRIPTS/ctx-launch.sh tig"
    alias ck9s="bash $_WAVETERM_SCRIPTS/ctx-launch.sh k9s"
    alias cnvtop="bash $_WAVETERM_SCRIPTS/ctx-launch.sh nvtop"
    alias cdust="bash $_WAVETERM_SCRIPTS/ctx-launch.sh dust"
    alias cncdu="bash $_WAVETERM_SCRIPTS/ctx-launch.sh ncdu"
    alias cmc="bash $_WAVETERM_SCRIPTS/ctx-launch.sh mc"
    alias cdocker="bash $_WAVETERM_SCRIPTS/ctx-launch.sh docker"
    alias cgpu="bash $_WAVETERM_SCRIPTS/ctx-launch.sh gpu"

    # Split direction variants
    alias ccr="bash $_WAVETERM_SCRIPTS/ctx-launch.sh"        # default: split right
    alias ccd="bash $_WAVETERM_SCRIPTS/ctx-launch.sh btop down"  # split down
fi

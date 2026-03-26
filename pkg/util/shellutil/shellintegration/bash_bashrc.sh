
# Source /etc/profile if it exists
if [ -f /etc/profile ]; then
    . /etc/profile
fi

# REBRAND: WAVETERM_WSHBINDIR → TERMINOLGY_TSHBINDIR (bin dir env var injected by Go server)
TERMINOLGY_TSHBINDIR={{.WSHBINDIR}}

# after /etc/profile which is likely to clobber the path
export PATH="$TERMINOLGY_TSHBINDIR:$PATH"

# Source the dynamic script from tsh token
# REBRAND: wsh → tsh (shell helper binary name); WAVETERM_SWAPTOKEN → TERMINOLGY_SWAPTOKEN
eval "$(tsh token "$TERMINOLGY_SWAPTOKEN" bash 2> /dev/null)"
unset TERMINOLGY_SWAPTOKEN

# Source the first of ~/.bash_profile, ~/.bash_login, or ~/.profile that exists
if [ -f ~/.bash_profile ]; then
    . ~/.bash_profile
elif [ -f ~/.bash_login ]; then
    . ~/.bash_login
elif [ -f ~/.profile ]; then
    . ~/.profile
fi

if [[ ":$PATH:" != *":$TERMINOLGY_TSHBINDIR:"* ]]; then
    export PATH="$TERMINOLGY_TSHBINDIR:$PATH"
fi
unset TERMINOLGY_TSHBINDIR
if type _init_completion &>/dev/null; then
  source <(tsh completion bash)  # REBRAND: wsh → tsh
fi

# extdebug breaks bash-preexec semantics; bail out cleanly
if shopt -q extdebug; then
  # printf 'wave si: disabled (bash extdebug enabled)\n' >&2
  printf '\033]16162;M;{"integration":false}\007'
  return 0
fi

# Source bash-preexec for proper preexec/precmd hook support
if [ -z "${bash_preexec_imported:-}" ]; then
    _TERMINOLGY_SI_BASHRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ -f "$_TERMINOLGY_SI_BASHRC_DIR/bash_preexec.sh" ]; then
        source "$_TERMINOLGY_SI_BASHRC_DIR/bash_preexec.sh"
    fi
    unset _TERMINOLGY_SI_BASHRC_DIR
fi

# Check if bash-preexec was successfully imported
if [ -z "${bash_preexec_imported:-}" ]; then
    # bash-preexec failed to import, disable shell integration
    printf '\033]16162;M;{"integration":false}\007'
    return 0
fi

_TERMINOLGY_SI_FIRSTPROMPT=1  # REBRAND: was _TERMINOLGY_SI_FIRSTPROMPT

# Terminolgy Shell Integration
_terminolgy_si_blocked() {  # REBRAND: was _terminolgy_si_blocked
    [[ -n "$TMUX" || -n "$STY" || "$TERM" == tmux* || "$TERM" == screen* ]]
}

_terminolgy_si_urlencode() {
    local s="$1"
    s="${s//%/%25}"
    s="${s// /%20}"
    s="${s//#/%23}"
    s="${s//\?/%3F}"
    s="${s//&/%26}"
    s="${s//;/%3B}"
    s="${s//+/%2B}"
    printf '%s' "$s"
}

_terminolgy_si_osc7() {
    _terminolgy_si_blocked && return
    local encoded_pwd=$(_terminolgy_si_urlencode "$PWD")
    printf '\033]7;file://localhost%s\007' "$encoded_pwd"
}

_terminolgy_si_precmd() {
    local _waveterm_si_status=$?
    _terminolgy_si_blocked && return
    
    if [ "$_TERMINOLGY_SI_FIRSTPROMPT" -eq 1 ]; then
        local uname_info
        uname_info=$(uname -smr 2>/dev/null)
        printf '\033]16162;M;{"shell":"bash","shellversion":"%s","uname":"%s","integration":true}\007' "$BASH_VERSION" "$uname_info"
    else
        printf '\033]16162;D;{"exitcode":%d}\007' "$_waveterm_si_status"
    fi
    # OSC 7 sent on every prompt - bash has no chpwd hook for directory changes
    _terminolgy_si_osc7
    printf '\033]16162;A\007'
    _TERMINOLGY_SI_FIRSTPROMPT=0
}

_terminolgy_si_preexec() {
    _terminolgy_si_blocked && return
    
    local cmd="$1"
    local cmd_length=${#cmd}
    if [ "$cmd_length" -gt 8192 ]; then
        cmd=$(printf '# command too large (%d bytes)' "$cmd_length")
    fi
    local cmd64
    cmd64=$(printf '%s' "$cmd" | base64 2>/dev/null | tr -d '\n\r')
    if [ -n "$cmd64" ]; then
        printf '\033]16162;C;{"cmd64":"%s"}\007' "$cmd64"
    else
        printf '\033]16162;C\007'
    fi
}

# Add our functions to the bash-preexec arrays
precmd_functions+=(_terminolgy_si_precmd)
preexec_functions+=(_terminolgy_si_preexec)
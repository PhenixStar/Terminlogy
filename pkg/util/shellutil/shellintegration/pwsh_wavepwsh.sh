# We source this file with -NoExit -File
$env:PATH = {{.WSHBINDIR_PWSH}} + "{{.PATHSEP}}" + $env:PATH

# Source dynamic script from wsh token
$terminolgy_swaptoken_output = tsh token $env:TERMINOLGY_SWAPTOKEN pwsh 2>$null | Out-String  # REBRAND: wsh → tsh; waveterm_swaptoken_output → terminolgy_swaptoken_output
if ($terminolgy_swaptoken_output -and $terminolgy_swaptoken_output -ne "") {
    Invoke-Expression $terminolgy_swaptoken_output
}
Remove-Variable -Name terminolgy_swaptoken_output
Remove-Item Env:TERMINOLGY_SWAPTOKEN

# Load Wave completions
tsh completion powershell | Out-String | Invoke-Expression  # REBRAND: wsh → tsh

if ($PSVersionTable.PSVersion.Major -lt 7) {
    return  # skip OSC setup entirely
}

if ($PSStyle.FileInfo.Directory -eq "`e[44;1m") {
    $PSStyle.FileInfo.Directory = "`e[34;1m"
}

$Global:_TERMINOLGY_SI_FIRSTPROMPT = $true

# shell integration
function Global:_terminolgy_si_blocked {
    # Check if we're in tmux or screen
    return ($env:TMUX -or $env:STY -or $env:TERM -like "tmux*" -or $env:TERM -like "screen*")
}

function Global:_terminolgy_si_osc7 {
    if (_terminolgy_si_blocked) { return }
    
    # Percent-encode the raw path as-is (handles UNC, drive letters, etc.)
    $encoded_pwd = [System.Uri]::EscapeDataString($PWD.Path)
    
    # OSC 7 - current directory
    Write-Host -NoNewline "`e]7;file://localhost/$encoded_pwd`a"
}

function Global:_terminolgy_si_prompt {
    if (_terminolgy_si_blocked) { return }
    
    if ($Global:_TERMINOLGY_SI_FIRSTPROMPT) {
		# not sending uname
		       $shellversion = $PSVersionTable.PSVersion.ToString()
		       Write-Host -NoNewline "`e]16162;M;{`"shell`":`"pwsh`",`"shellversion`":`"$shellversion`",`"integration`":false}`a"
        $Global:_TERMINOLGY_SI_FIRSTPROMPT = $false
    }
    
    _terminolgy_si_osc7
}

# Add the OSC 7 call to the prompt function
if (Test-Path Function:\prompt) {
    $global:_terminolgy_original_prompt = $function:prompt
    function Global:prompt {
        _terminolgy_si_prompt
        & $global:_terminolgy_original_prompt
    }
} else {
    function Global:prompt {
        _terminolgy_si_prompt
        "PS $($executionContext.SessionState.Path.CurrentLocation)$('>' * ($nestedPromptLevel + 1)) "
    }
}
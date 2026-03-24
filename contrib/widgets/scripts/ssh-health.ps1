#Requires -Version 5.1
<#
.SYNOPSIS
    WaveTerm SSH Health Monitor - polls SSH connections and displays live status.
.DESCRIPTION
    Reads connections from WaveTerm connections.json, tests each SSH host every
    30 seconds, and renders a color-coded status table in the terminal.
#>

$ConnectionsFile = "$env:USERPROFILE\.config\waveterm\connections.json"
$PollInterval    = 30   # seconds
$SSHTimeout      = 5    # seconds

# ANSI color codes
$ESC   = [char]27
$Reset = "$ESC[0m"
$Bold  = "$ESC[1m"
$Dim   = "$ESC[2m"

$ColorGreen  = "$ESC[32m"
$ColorRed    = "$ESC[31m"
$ColorYellow = "$ESC[33m"
$ColorCyan   = "$ESC[36m"
$ColorWhite  = "$ESC[97m"
$ColorGray   = "$ESC[90m"

$CircleGreen  = "${ColorGreen}●${Reset}"
$CircleRed    = "${ColorRed}●${Reset}"
$CircleYellow = "${ColorYellow}●${Reset}"
$CircleGray   = "${ColorGray}○${Reset}"

function Read-Connections {
    if (-not (Test-Path $ConnectionsFile)) {
        return $null
    }

    try {
        $raw = Get-Content $ConnectionsFile -Raw -ErrorAction Stop
        return $raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        return $null
    }
}

function Get-SortedConnections {
    param($JsonObject)

    $entries = @()

    foreach ($name in $JsonObject.PSObject.Properties.Name) {
        # Skip WSL connections
        if ($name -like 'wsl://*') { continue }

        # Skip entries without @ (bare IPs or malformed names)
        if ($name -notmatch '@') { continue }

        $conn = $JsonObject.$name

        # Skip entries without a hostname
        if (-not $conn.'ssh:hostname') { continue }

        $order = if ($conn.'display:order') { [int]$conn.'display:order' } else { 999 }

        $entries += [PSCustomObject]@{
            Name     = $name
            Hostname = $conn.'ssh:hostname'
            Port     = if ($conn.'ssh:port') { $conn.'ssh:port' } else { '22' }
            KeyFile  = if ($conn.'ssh:identityfile') { $conn.'ssh:identityfile'[0] } else { $null }
            Order    = $order
            Status   = 'PENDING'
            Latency  = $null
        }
    }

    return $entries | Sort-Object Order
}

function Test-SSHConnection {
    param(
        [string]$User,
        [string]$Hostname,
        [string]$Port,
        [string]$KeyFile
    )

    $args = @(
        '-o', "ConnectTimeout=$SSHTimeout"
        '-o', 'BatchMode=yes'
        '-o', 'StrictHostKeyChecking=no'
        '-o', 'UserKnownHostsFile=/dev/null'
        '-o', 'LogLevel=ERROR'
        '-p', $Port
    )

    # Expand ~ in key path
    if ($KeyFile) {
        $expandedKey = $KeyFile -replace '^~', $env:USERPROFILE
        $args += @('-i', $expandedKey)
    }

    $target = "${User}@${Hostname}"
    $args  += @($target, 'echo OK')

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $proc = Start-Process -FilePath 'ssh' `
                              -ArgumentList $args `
                              -NoNewWindow `
                              -PassThru `
                              -RedirectStandardOutput 'NUL' `
                              -RedirectStandardError  'NUL' `
                              -ErrorAction Stop

        $timedOut = -not $proc.WaitForExit(($SSHTimeout + 1) * 1000)
        $stopwatch.Stop()

        if ($timedOut) {
            try { $proc.Kill() } catch {}
            return @{ Status = 'TIMEOUT'; Latency = $null }
        }

        if ($proc.ExitCode -eq 0) {
            return @{ Status = 'OK'; Latency = [int]$stopwatch.ElapsedMilliseconds }
        } else {
            return @{ Status = 'FAIL'; Latency = [int]$stopwatch.ElapsedMilliseconds }
        }
    } catch {
        $stopwatch.Stop()
        return @{ Status = 'FAIL'; Latency = $null }
    }
}

function Format-Latency {
    param($Ms)
    if ($null -eq $Ms) { return '  --  ' }
    return "$Ms ms".PadLeft(6)
}

function Get-StatusIcon {
    param([string]$Status)
    switch ($Status) {
        'OK'      { return $CircleGreen }
        'FAIL'    { return $CircleRed }
        'TIMEOUT' { return $CircleYellow }
        default   { return $CircleGray }
    }
}

function Get-StatusColor {
    param([string]$Status)
    switch ($Status) {
        'OK'      { return $ColorGreen }
        'FAIL'    { return $ColorRed }
        'TIMEOUT' { return $ColorYellow }
        default   { return $ColorGray }
    }
}

function Render-Table {
    param($Connections, [datetime]$CheckedAt, [bool]$Checking = $false)

    # Column widths derived from data
    $maxName = ($Connections | ForEach-Object { $_.Name.Length } | Measure-Object -Maximum).Maximum
    $maxName = [Math]::Max($maxName, 16)
    $maxHost = ($Connections | ForEach-Object { $_.Hostname.Length } | Measure-Object -Maximum).Maximum
    $maxHost = [Math]::Max($maxHost, 12)

    $w1 = $maxName   # Connection
    $w2 = $maxHost   # Hostname
    $w3 = 6          # Port
    $w4 = 8          # Latency
    $w5 = 9          # Status

    $sep = "${ColorGray}$('─' * ($w1 + $w2 + $w3 + $w4 + $w5 + 16))${Reset}"

    [System.Console]::Clear()

    # Header bar
    $timestamp = $CheckedAt.ToString('yyyy-MM-dd HH:mm:ss')
    $checkingTag = if ($Checking) { " ${ColorYellow}(checking...)${Reset}" } else { '' }
    Write-Host "${Bold}${ColorCyan}  SSH Health Monitor${Reset}${checkingTag}"
    Write-Host "${ColorGray}  Last check: ${ColorWhite}${timestamp}${Reset}"
    Write-Host $sep

    # Column headers
    $h1 = 'CONNECTION'.PadRight($w1)
    $h2 = 'HOSTNAME'.PadRight($w2)
    $h3 = 'PORT'.PadRight($w3)
    $h4 = 'LATENCY'.PadRight($w4)
    $h5 = 'STATUS'
    Write-Host "  ${Bold}${ColorGray}${h1}  ${h2}  ${h3}  ${h4}  ${h5}${Reset}"
    Write-Host $sep

    # Rows
    foreach ($conn in $Connections) {
        $icon    = Get-StatusIcon  $conn.Status
        $sColor  = Get-StatusColor $conn.Status

        $namePad = $conn.Name.PadRight($w1)
        $hostPad = $conn.Hostname.PadRight($w2)
        $portPad = $conn.Port.PadRight($w3)
        $latStr  = Format-Latency $conn.Latency
        $statStr = "${sColor}$($conn.Status)${Reset}"

        Write-Host "  ${ColorWhite}${namePad}${Reset}  ${ColorGray}${hostPad}${Reset}  ${ColorGray}${portPad}${Reset}  ${ColorCyan}${latStr}${Reset}  ${icon} ${statStr}"
    }

    Write-Host $sep

    # Summary line
    $total   = $Connections.Count
    $ok      = ($Connections | Where-Object Status -eq 'OK').Count
    $fail    = ($Connections | Where-Object Status -eq 'FAIL').Count
    $timeout = ($Connections | Where-Object Status -eq 'TIMEOUT').Count
    $pending = ($Connections | Where-Object Status -eq 'PENDING').Count

    $summaryParts = @()
    if ($ok      -gt 0) { $summaryParts += "${CircleGreen} ${ok} ok" }
    if ($fail    -gt 0) { $summaryParts += "${CircleRed} ${fail} fail" }
    if ($timeout -gt 0) { $summaryParts += "${CircleYellow} ${timeout} timeout" }
    if ($pending -gt 0) { $summaryParts += "${CircleGray} ${pending} pending" }

    $summary = $summaryParts -join "   "
    Write-Host "  ${Dim}${total} connections${Reset}   ${summary}"
    Write-Host "  ${ColorGray}${Dim}Refreshes every ${PollInterval}s  •  Ctrl+C to exit${Reset}"
}

# ── Main loop ────────────────────────────────────────────────────────────────

[System.Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[System.Console]::Title = 'SSH Health Monitor'

# Hide cursor for cleaner rendering
Write-Host -NoNewline "$ESC[?25l"

try {
    while ($true) {
        $jsonObj = Read-Connections

        if ($null -eq $jsonObj) {
            [System.Console]::Clear()
            Write-Host "${ColorRed}  [ERROR]${Reset} Cannot read connections file:"
            Write-Host "  ${ColorGray}${ConnectionsFile}${Reset}"
            Write-Host ""
            Write-Host "  Retrying in ${PollInterval}s..."
            Start-Sleep -Seconds $PollInterval
            continue
        }

        $connections = Get-SortedConnections $jsonObj

        if ($connections.Count -eq 0) {
            [System.Console]::Clear()
            Write-Host "${ColorYellow}  [WARN]${Reset} No testable SSH connections found."
            Write-Host "  ${ColorGray}(WSL and entries without @ are skipped)${Reset}"
            Start-Sleep -Seconds $PollInterval
            continue
        }

        $checkedAt = Get-Date
        Render-Table -Connections $connections -CheckedAt $checkedAt -Checking $true

        # Test each connection sequentially (avoids SSH agent contention)
        foreach ($conn in $connections) {
            $userPart = ($conn.Name -split '@')[0]
            $result   = Test-SSHConnection `
                            -User     $userPart `
                            -Hostname $conn.Hostname `
                            -Port     $conn.Port `
                            -KeyFile  $conn.KeyFile

            $conn.Status  = $result.Status
            $conn.Latency = $result.Latency

            # Re-render after each result so the table updates live
            $checkedAt = Get-Date
            Render-Table -Connections $connections -CheckedAt $checkedAt -Checking $true
        }

        # Final render — all done, no "checking" tag
        Render-Table -Connections $connections -CheckedAt (Get-Date) -Checking $false

        Start-Sleep -Seconds $PollInterval
    }
} finally {
    # Restore cursor on exit
    Write-Host -NoNewline "$ESC[?25h"
}

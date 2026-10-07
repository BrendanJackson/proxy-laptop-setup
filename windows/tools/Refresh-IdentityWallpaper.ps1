# Refresh-IdentityWallpaper.ps1 -- redraw the identity wallpaper with the
# machine's CURRENT addresses, using the best renderer available right now.
#
# setup.ps1 sets the wallpaper once. The addresses on it go stale the moment
# the machine docks, joins a different site network, or finally signs into
# Tailscale -- which is the one number someone reads off the screen when they
# need to reach the box. This re-renders it.
#
#   .\Refresh-IdentityWallpaper.ps1 -Label FXWB-1 -Tag "FX Workbench field laptop" -Install
#
# -Install registers a scheduled task (at logon, then hourly). -Uninstall
# removes it. Without either, it just redraws once.
#
# Renderer order matches base.ps1, so a refresh never downgrades the look that
# setup produced:
#   1. the shared theme in homelab-bootstrap   (identical to the Linux boxes)
#   2. the same theme vendored in this repo    (same Chrome pipeline)
#   3. Set-InfoWallpaper.ps1                   (native, no Chrome, no 2nd repo)

[CmdletBinding()]
param(
    [string]$Label,
    [string]$HostName,
    [string]$Tag,
    [string]$Theme = "fx",
    [switch]$Install,
    [switch]$Uninstall
)

$ErrorActionPreference = "Continue"
$TaskName = "Identity Wallpaper"
$RepoRaw = "https://raw.githubusercontent.com/BrendanJackson/proxy-laptop-setup/master"

if ($Uninstall) {
    try {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction Stop
        Write-Host "Removed scheduled task '$TaskName'." -ForegroundColor Green
    }
    catch { Write-Host "No scheduled task '$TaskName' to remove." -ForegroundColor DarkGray }
    return
}

if (-not $HostName) { $HostName = $env:COMPUTERNAME }
if (-not $Label) { $Label = $HostName }

# This script may run from a clone or straight from the repo, so resolve the
# library the same way setup.ps1 does rather than assuming files on disk.
$repoRoot = if ($PSScriptRoot) { Split-Path (Split-Path $PSScriptRoot -Parent) -Parent } else { $null }
function Get-Piece([string]$Rel) {
    if ($repoRoot) {
        $p = Join-Path $repoRoot $Rel
        if (Test-Path $p) { return Get-Content -Raw $p }
    }
    return (Invoke-RestMethod "$RepoRaw/$($Rel -replace '\\','/')")
}

# common.ps1 wants $ManualSteps to exist; it is only collected for the final
# summary, which a refresh run has no use for.
$ManualSteps = New-Object System.Collections.Generic.List[string]
. ([scriptblock]::Create((Get-Piece "windows/lib/common.ps1")))

$done = $false

# ---- tier 1: the shared theme ------------------------------------------------
$homelabTheme = Join-Path $env:USERPROFILE "homelab-bootstrap\dotfiles\wallpapers\$Theme.html"
if (Test-Path $homelabTheme) {
    $done = Set-IdentityWallpaper -ThemeFile $homelabTheme -Label $Label -HostName $HostName -Tag $Tag
}

# ---- tier 2: the vendored copy of the same theme -----------------------------
if (-not $done) {
    try {
        $html = Get-Piece "dotfiles/wallpapers/$Theme.html"
        if ($html) {
            $tmp = Join-Path $env:TEMP "wallpaper-$Theme.html"
            Set-Content -Path $tmp -Value $html -Encoding utf8
            $done = Set-IdentityWallpaper -ThemeFile $tmp -Label $Label -HostName $HostName -Tag $Tag
        }
    }
    catch { }
}

# ---- tier 3: native ----------------------------------------------------------
if (-not $done) {
    try {
        $native = [scriptblock]::Create((Get-Piece "windows/tools/Set-InfoWallpaper.ps1"))
        # No -Install: this script owns the scheduled task, not that one.
        & $native -Label $Label -HostName $HostName -Tag $Tag
    }
    catch {
        Write-Host "Could not refresh the wallpaper: $($_.Exception.Message)" -ForegroundColor DarkYellow
    }
}

if ($Install) {
    if (-not $PSCommandPath) {
        Write-Host "Run this from a clone to use -Install (it needs a file path to schedule)." -ForegroundColor DarkYellow
        return
    }
    # Set-InfoWallpaper registers a task under the same name when called with
    # -Install, so remove whatever is there before claiming the name -- two
    # tasks would fight over the wallpaper every hour.
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue

    $argLine = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}"' -f $PSCommandPath
    foreach ($p in 'Label', 'HostName', 'Tag', 'Theme') {
        $v = (Get-Variable $p -ValueOnly -ErrorAction SilentlyContinue)
        if ($v) { $argLine += ' -{0} "{1}"' -f $p, $v }
    }

    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $argLine
    $triggers = @(
        (New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME")
        (New-ScheduledTaskTrigger -Once -At (Get-Date).Date `
            -RepetitionInterval (New-TimeSpan -Hours 1) -RepetitionDuration (New-TimeSpan -Days 3650))
    )
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $triggers -Settings $settings `
        -Description 'Redraws the identity wallpaper with current addresses.' -Force | Out-Null
    Write-Host "Registered scheduled task '$TaskName' (at logon, then hourly)." -ForegroundColor Green
}

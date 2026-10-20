# Set-InfoWallpaper.ps1 -- identity wallpaper WITHOUT homelab-bootstrap or Chrome.
#
# The preferred renderer is Set-IdentityWallpaper in windows/lib/common.ps1: it
# screenshots dotfiles/wallpapers/<theme>.html from homelab-bootstrap through
# headless Chrome, so the Windows boxes and the Linux boxes look identical.
#
# That path needs two things a fresh machine may not have: a clone of the
# PRIVATE homelab-bootstrap repo, and Chrome. Until both are there it silently
# skips and the machine keeps the Windows Spotlight default -- which is how
# FXWB-1 sat for a week with no identity wallpaper at all.
#
# This draws the same information natively with System.Drawing. Same
# label/host/tag/ip contract as the HTML theme, so swapping back later changes
# only the look.
#
#   .\Set-InfoWallpaper.ps1 -Label FXWB-1 -Tag "FX Workbench field laptop" -Install
#
# -Install also registers a scheduled task so the addresses stay true after a
# dock or a VPN connect. -Uninstall removes it.

[CmdletBinding()]
param(
    [string]$Label,
    [string]$HostName,
    [string]$Tag,
    [switch]$Install,
    [switch]$Uninstall,
    [string]$Accent = '#4EA1F7'
)

$ErrorActionPreference = 'Stop'

$TaskName = 'Identity Wallpaper'
$OutDir = Join-Path $env:LOCALAPPDATA 'IdentityWallpaper'
$OutFile = Join-Path $OutDir 'wallpaper.png'

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

# ---- gather ------------------------------------------------------------------
# Tailscale gets its own row, so it is excluded from the adapter list below to
# avoid printing the same 100.x address twice.
$addresses = @(
    Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object {
            $_.IPAddress -notlike '127.*' -and
            $_.IPAddress -notlike '169.254.*' -and
            $_.InterfaceAlias -notlike '*Tailscale*'
        } |
        Sort-Object InterfaceAlias |
        ForEach-Object { [PSCustomObject]@{ Alias = $_.InterfaceAlias; IP = $_.IPAddress } }
)

$tsIp = $null
$tsState = 'not installed'
$tsExe = "$env:ProgramFiles\Tailscale\tailscale.exe"
if (Test-Path $tsExe) {
    $tsState = 'unknown'
    try {
        $json = & $tsExe status --json 2>$null | Out-String
        if ($json.Trim()) {
            $st = $json | ConvertFrom-Json
            if ($st.BackendState) { $tsState = $st.BackendState }
            if ($st.Self -and $st.Self.TailscaleIPs) {
                $tsIp = @($st.Self.TailscaleIPs | Where-Object { $_ -notmatch ':' })[0]
            }
            # A health warning matters more than "Running" does: a machine can
            # report Running while its netmap is hours stale.
            if ($st.Health -and @($st.Health).Count -gt 0) { $tsState = "$tsState, health warning" }
        }
    }
    catch { $tsState = 'error reading status' }
}

$os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue

$lines = New-Object System.Collections.Generic.List[object]
function Add-Line([string]$L, [string]$V, [string]$K = 'normal') {
    $lines.Add([PSCustomObject]@{ Label = $L; Value = $V; Kind = $K })
}

if ($Tag) { Add-Line 'Role' $Tag 'dim' }
Add-Line 'User' $env:USERNAME
Add-Line 'Tailscale' $(if ($tsIp) { "$tsIp  ($tsState)" } else { $tsState }) `
    $(if ($tsState -like 'Running*' -and $tsState -notlike '*health*') { 'good' }
      elseif ($tsState -eq 'not installed') { 'dim' } else { 'warn' })
if ($addresses.Count) { foreach ($a in $addresses) { Add-Line $a.Alias $a.IP } }
else { Add-Line 'Network' 'no active IPv4 address' 'warn' }
if ($os) { Add-Line 'OS' "$($os.Caption) $($os.Version)" 'dim' }
Add-Line 'Updated' (Get-Date -Format 'yyyy-MM-dd HH:mm') 'dim'

# ---- render ------------------------------------------------------------------
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

# Win32_VideoController reports true pixels; Screen.Bounds can come back scaled
# by the DPI setting, which would render the wallpaper soft on a HiDPI panel.
$width = $null; $height = $null
$vc = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue |
      Where-Object { $_.CurrentHorizontalResolution -gt 0 } |
      Sort-Object CurrentHorizontalResolution -Descending | Select-Object -First 1
if ($vc) { $width = [int]$vc.CurrentHorizontalResolution; $height = [int]$vc.CurrentVerticalResolution }
if (-not $width -or -not $height) {
    $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $width = $b.Width; $height = $b.Height
}

$scale = [Math]::Max(1.0, $height / 1080.0)
function New-Color([string]$Hex) {
    $Hex = $Hex.TrimStart('#')
    [System.Drawing.Color]::FromArgb(
        [Convert]::ToInt32($Hex.Substring(0, 2), 16),
        [Convert]::ToInt32($Hex.Substring(2, 2), 16),
        [Convert]::ToInt32($Hex.Substring(4, 2), 16))
}

$cAccent = New-Color $Accent
$cText = New-Color 'E8ECF2'
$cLabel = New-Color '93A1B5'
$cDim = New-Color '6B7A8F'
$cGood = New-Color '4ADE80'
$cWarn = New-Color 'FBBF24'

$bmp = New-Object System.Drawing.Bitmap($width, $height)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit

try {
    $rect = New-Object System.Drawing.Rectangle(0, 0, $width, $height)
    $grad = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        $rect, (New-Color '0D1117'), (New-Color '1B2533'),
        [System.Drawing.Drawing2D.LinearGradientMode]::ForwardDiagonal)
    $g.FillRectangle($grad, $rect)
    $grad.Dispose()

    $fTitle = New-Object System.Drawing.Font('Segoe UI Semibold', (22 * $scale), [System.Drawing.FontStyle]::Bold)
    $fLabel = New-Object System.Drawing.Font('Segoe UI', (11 * $scale))
    $fValue = New-Object System.Drawing.Font('Consolas', (13 * $scale))

    $labelW = 0; $valueW = 0
    foreach ($l in $lines) {
        $labelW = [Math]::Max($labelW, $g.MeasureString($l.Label, $fLabel).Width)
        $valueW = [Math]::Max($valueW, $g.MeasureString($l.Value, $fValue).Width)
    }

    $pad = [int](28 * $scale); $gap = [int](18 * $scale); $rowH = [int](26 * $scale)
    $titleH = [int](46 * $scale)
    $panelW = [int]($labelW + $gap + $valueW + ($pad * 2))
    $panelH = [int]($titleH + ($lines.Count * $rowH) + ($pad * 2))
    $margin = [int](56 * $scale)
    # Top right, so it never sits under the desktop icons.
    $panelX = $width - $panelW - $margin
    $panelY = $margin

    $panelBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(170, 8, 12, 18))
    $g.FillRectangle($panelBrush, (New-Object System.Drawing.Rectangle($panelX, $panelY, $panelW, $panelH)))
    $panelBrush.Dispose()

    $barBrush = New-Object System.Drawing.SolidBrush($cAccent)
    $g.FillRectangle($barBrush, $panelX, $panelY, [int](4 * $scale), $panelH)
    $barBrush.Dispose()

    $bTitle = New-Object System.Drawing.SolidBrush($cAccent)
    $g.DrawString($Label, $fTitle, $bTitle, ($panelX + $pad), ($panelY + $pad - (6 * $scale)))
    $bTitle.Dispose()

    $bLabel = New-Object System.Drawing.SolidBrush($cLabel)
    $y = $panelY + $pad + $titleH
    foreach ($l in $lines) {
        $colour = switch ($l.Kind) {
            'good' { $cGood } 'warn' { $cWarn } 'dim' { $cDim } 'strong' { $cAccent } default { $cText }
        }
        $bValue = New-Object System.Drawing.SolidBrush($colour)
        $g.DrawString($l.Label, $fLabel, $bLabel, ($panelX + $pad), ($y + (2 * $scale)))
        $g.DrawString($l.Value, $fValue, $bValue, ($panelX + $pad + $labelW + $gap), $y)
        $bValue.Dispose()
        $y += $rowH
    }
    $bLabel.Dispose()

    if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }
    $bmp.Save($OutFile, [System.Drawing.Imaging.ImageFormat]::Png)
    $fTitle.Dispose(); $fLabel.Dispose(); $fValue.Dispose()
}
finally {
    $g.Dispose(); $bmp.Dispose()
}

# ---- apply -------------------------------------------------------------------
Set-ItemProperty 'HKCU:\Control Panel\Desktop' -Name WallpaperStyle -Value '10'   # fill
Set-ItemProperty 'HKCU:\Control Panel\Desktop' -Name TileWallpaper -Value '0'

# Take the desktop off Windows Spotlight, which otherwise rotates its own
# picture back in and silently undoes this.
$wp = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Wallpapers'
if (-not (Test-Path $wp)) { New-Item -Path $wp -Force | Out-Null }
Set-ItemProperty -Path $wp -Name 'BackgroundType' -Value 0 -Type DWord -Force

if (-not ('NativeWallpaper' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class NativeWallpaper {
    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool SystemParametersInfo(uint uiAction, uint uiParam, string pvParam, uint fWinIni);
}
'@
}
# SPI_SETDESKWALLPAPER=20, SPIF_UPDATEINIFILE|SPIF_SENDWININICHANGE=3
if ([NativeWallpaper]::SystemParametersInfo(20, 0, $OutFile, 3)) {
    Write-Host "Identity wallpaper set: $OutFile" -ForegroundColor Green
}
else {
    Write-Host "SystemParametersInfo reported failure -- wallpaper not applied." -ForegroundColor Yellow
}

if ($Install) {
    $argLine = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}"' -f $PSCommandPath
    foreach ($p in 'Label', 'HostName', 'Tag') {
        $v = (Get-Variable $p -ValueOnly)
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
        -Description 'Regenerates the identity desktop wallpaper.' -Force | Out-Null
    Write-Host "Registered scheduled task '$TaskName' (at logon, then hourly)." -ForegroundColor Green
}

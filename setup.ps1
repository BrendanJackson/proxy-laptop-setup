# Proxy Laptop Setup -- one command install
# Run in PowerShell as Administrator: .\setup.ps1
#
# Companion repo/runbook:
#   Notion: "Proxy Laptop Setup -- Remote Access Runbook"
#   GitHub: https://github.com/BrendanJackson/proxy-laptop-setup
#
# What this does:
#   1. Installs every winget-available app in one pass (general remote-access
#      stack + controls field tools' runtime dependencies).
#   2. Clones/updates controls-field-tools and homelab-bootstrap (both
#      private repos; needs GitHub auth).
#   3. Sets dark mode and this machine's identity wallpaper -- see
#      $IdentityTag below to customize for a second property/site.
#   4. Prints the manual steps that can't be scripted (sign-ins, vendor-gated
#      software, per-machine config).
#
# Vendor-gated tools this script deliberately does NOT install:
#   Niagara Workbench / Metasys SCT -- licensed installers, not winget packages.
#   See "Controls-specific tools" in the README for how those get added.

$ErrorActionPreference = "Continue"

# ---- Windows edition check ----
# This script installs apps only; it never touches OS licensing. If the
# Windows Setup key prompt was skipped or "I don't have a key" was chosen,
# the machine is silently still on Home and nothing else will ever flag it.
$editionId = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name EditionID -ErrorAction SilentlyContinue).EditionID
if ($editionId -and $editionId -notmatch 'Professional|Enterprise|Education') {
    Write-Host "`n=== WINDOWS EDITION WARNING ===" -ForegroundColor Red
    Write-Host "This machine is running '$editionId', not Pro/Enterprise/Education." -ForegroundColor Red
    Write-Host "setup.ps1 only installs apps -- it does not install or activate Windows." -ForegroundColor Red
    Write-Host "If you have a Windows 11 Pro key and meant to be on Pro:" -ForegroundColor Yellow
    Write-Host "  Settings > System > Activation > Change Product Key -- enter it there." -ForegroundColor Yellow
    Write-Host "  This is a same-media edition change; you do NOT need to reimage again for this alone." -ForegroundColor Yellow
    Write-Host "Continuing with app installs regardless. Re-run this script after upgrading to confirm this check clears.`n" -ForegroundColor Yellow
}
else {
    Write-Host "Windows edition: $editionId -- OK.`n" -ForegroundColor Green
}

$apps = @(
    "Tailscale.Tailscale",
    "mRemoteNG.mRemoteNG",
    "Notion.Notion",
    "Microsoft.VisualStudioCode",
    "Git.Git",
    "Bitwarden.Bitwarden",
    "Google.Chrome",
    "WiresharkFoundation.Wireshark",
    "PuTTY.PuTTY",
    "GitHub.cli",              # gh: auths git against the private controls-field-tools repo
    "Python.Python.3.12",      # controls-field-tools/site-audit needs a Python 3 interpreter (stdlib only, no pip)
    "Anthropic.Claude",        # Claude desktop app -- was missing from the original list, added 2026-09-25
    "Anthropic.ClaudeCode",    # Claude Code CLI -- Brendan flagged this was missing too, added 2026-09-25
    "Microsoft.WindowsTerminal" # multi-tab terminal for the PowerShell/Git Bash/Python CLI work this laptop now does
)

Write-Host "Installing $($apps.Count) apps via winget..." -ForegroundColor Cyan

foreach ($app in $apps) {
    Write-Host "`n--- $app ---" -ForegroundColor Yellow
    winget install --id $app --silent --accept-package-agreements --accept-source-agreements
}

# ---- clone/pull a private repo, skipping cleanly if gh isn't ready yet ----
function Sync-PrivateRepo {
    param([string]$Repo, [string]$Dir)
    $name = $Repo.Split('/')[-1]
    Write-Host "`n--- $name ---" -ForegroundColor Yellow
    $ghOk = Get-Command gh -ErrorAction SilentlyContinue
    if (-not $ghOk) {
        Write-Host "gh isn't on PATH yet (fresh install needs a new shell). Re-run setup.ps1 in a new PowerShell window to pick up the clone step." -ForegroundColor DarkYellow
        return $false
    }
    if (Test-Path $Dir) {
        Write-Host "$name already present at $Dir -- pulling latest." -ForegroundColor Cyan
        git -C $Dir pull
        return $true
    }
    gh auth status 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Not signed into GitHub yet. Run 'gh auth login' (opens a browser for SSO), then re-run setup.ps1 to clone $name." -ForegroundColor DarkYellow
        return $false
    }
    gh repo clone $Repo $Dir
    return $?
}

$toolsDir = Join-Path $env:USERPROFILE "controls-field-tools"
Sync-PrivateRepo -Repo "BrendanJackson/controls-field-tools" -Dir $toolsDir | Out-Null

$hbDir = Join-Path $env:USERPROFILE "homelab-bootstrap"
$hbReady = Sync-PrivateRepo -Repo "BrendanJackson/homelab-bootstrap" -Dir $hbDir

# ---- dark mode ----
# Preference, applies system + app theme. Doesn't need a restart.
Write-Host "`n--- dark mode ---" -ForegroundColor Yellow
$personalizeKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
New-Item -Path $personalizeKey -Force | Out-Null
Set-ItemProperty -Path $personalizeKey -Name AppsUseLightTheme -Value 0 -Type DWord
Set-ItemProperty -Path $personalizeKey -Name SystemUsesLightTheme -Value 0 -Type DWord
Write-Host "Dark mode set (apps + system)." -ForegroundColor Green

# ---- identity wallpaper ----
# Reuses the exact template + headless-Chrome render pipeline homelab-bootstrap
# uses for the Linux boxes (dotfiles/wallpapers/<theme>.html, same
# label/host/tag/ip query-string contract) -- one shared source of truth, two
# OS-native apply steps. See homelab-bootstrap/docs/DIVERGENCE.md #16.
#
# $IdentityTag: edit this for a second property/site, e.g. "remote workstation - Ivy House".
# Mirrors the IDENTITY_TAG override in homelab-bootstrap's lib/xfce.sh.
$IdentityTag = "remote workstation"
Write-Host "`n--- identity wallpaper ---" -ForegroundColor Yellow
if (-not $hbReady) {
    Write-Host "Skipped -- homelab-bootstrap isn't cloned yet (see above). Re-run setup.ps1 once it is." -ForegroundColor DarkYellow
}
else {
    $theme = Join-Path $hbDir "dotfiles\wallpapers\workstation.html"
    $chrome = "$env:ProgramFiles\Google\Chrome\Application\chrome.exe"
    if (-not (Test-Path $chrome)) { $chrome = "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe" }
    if (-not (Test-Path $theme)) {
        Write-Host "Skipped -- $theme not found (homelab-bootstrap clone may be stale; try 'git -C $hbDir pull')." -ForegroundColor DarkYellow
    }
    elseif (-not (Test-Path $chrome)) {
        Write-Host "Skipped -- Chrome not found at the expected winget install path yet. Re-run setup.ps1 in a new PowerShell window." -ForegroundColor DarkYellow
    }
    else {
        $wallDir = Join-Path $env:USERPROFILE "Pictures\wallpapers"
        New-Item -ItemType Directory -Path $wallDir -Force | Out-Null
        $out = Join-Path $wallDir "$env:COMPUTERNAME.png"
        $tsIp = ""
        $ts = Get-Command tailscale -ErrorAction SilentlyContinue
        if ($ts) { $tsIp = (& tailscale ip -4 2>$null | Select-Object -First 1) }
        $url = "file:///$($theme -replace '\\','/')?label=PROXY&host=$env:COMPUTERNAME&tag=$([uri]::EscapeDataString($IdentityTag))&ip=$tsIp"
        & $chrome --headless=new --no-sandbox --disable-gpu --hide-scrollbars --force-device-scale-factor=1 `
            --window-size=1920,1080 --virtual-time-budget=8000 --screenshot="$out" "$url" 2>$null
        if (Test-Path $out) {
            Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name Wallpaper -Value $out
            Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name WallpaperStyle -Value 10   # fill
            Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name TileWallpaper -Value 0
            RUNDLL32.EXE user32.dll,UpdatePerUserSystemParameters
            Write-Host "Identity wallpaper set: $out" -ForegroundColor Green
            if (-not $tsIp) { Write-Host "(Tailscale IP blank -- sign in and re-run setup.ps1 to fill it in.)" -ForegroundColor DarkYellow }
        }
        else {
            Write-Host "WARNING: Chrome produced no image -- wallpaper not set. Cosmetic only, rest of setup is unaffected." -ForegroundColor DarkYellow
        }
    }
}

# ---- elevated shortcut for IP Speed Dial ----
# IP Speed Dial needs admin to change the adapter IP. The README's "Run JCI
# Elevated" context-menu item is provisioned by JCI's own MDM and won't exist
# on this laptop, so the manual fallback is right-click -> Run as
# Administrator every time. This creates a desktop shortcut with the "Run as
# administrator" flag already set on it, so a plain double-click elevates --
# the personal-laptop equivalent of "Run JCI Elevated". Windows still shows
# the UAC consent prompt each launch; that's by design and this doesn't try
# to suppress it -- it only removes the right-click step.
Write-Host "`n--- elevated shortcut (IP Speed Dial) ---" -ForegroundColor Yellow
$speedDialBat = Join-Path $toolsDir "speed-dial\Run-IP-SpeedDial.bat"
if (-not (Test-Path $speedDialBat)) {
    Write-Host "Skipped -- $speedDialBat not found (controls-field-tools not cloned yet)." -ForegroundColor DarkYellow
}
else {
    $lnkPath = Join-Path ([Environment]::GetFolderPath("Desktop")) "IP Speed Dial (Admin).lnk"
    $wsh = New-Object -ComObject WScript.Shell
    $shortcut = $wsh.CreateShortcut($lnkPath)
    $shortcut.TargetPath = $speedDialBat
    $shortcut.WorkingDirectory = Split-Path $speedDialBat -Parent
    $shortcut.Description = "IP Speed Dial, pre-elevated (double-click, no right-click needed)"
    $shortcut.Save()
    # .lnk byte 0x15 bit 0x20 is the "run as administrator" flag -- not exposed
    # by the WScript.Shell COM object, so it's set directly on the saved file.
    # Standard, widely-used technique; does not touch UAC or any system policy.
    $bytes = [System.IO.File]::ReadAllBytes($lnkPath)
    $bytes[0x15] = $bytes[0x15] -bor 0x20
    [System.IO.File]::WriteAllBytes($lnkPath, $bytes)
    Write-Host "Desktop shortcut created: 'IP Speed Dial (Admin)' -- double-click elevates (UAC prompt still appears once per launch)." -ForegroundColor Green
}

Write-Host "`nDone with winget batch. Manual steps still required:" -ForegroundColor Green
Write-Host "1. Sign into Tailscale (opens browser SSO)."
Write-Host "2. Sign into Bitwarden, unlock vault."
Write-Host "3. Run 'gh auth login' if the controls-field-tools/homelab-bootstrap clones above were skipped, then re-run this script."
Write-Host "4. Confirm controls-specific tools below (Niagara Workbench / Metasys SCT are vendor-gated, not winget-installable)."
Write-Host "5. Set Power Plan to 'never sleep' if this machine will also host RDP inbound."
Write-Host "6. Use the 'IP Speed Dial (Admin)' desktop shortcut (or right-click Run-IP-SpeedDial.bat -> Run as Administrator)."

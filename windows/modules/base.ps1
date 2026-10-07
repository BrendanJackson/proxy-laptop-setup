# windows/modules/base.ps1 -- what EVERY Windows machine gets.
#
# Brendan, 2026-10-06: "Every machine I use will have these; you can structure
# the git repo around this." Add an app here only if it belongs on every box;
# role-specific apps go in their own module (controls.ps1, remote-hub.ps1, ...).
#
# Needs from setup.ps1: $MachineConfig (machine file), common.ps1 helpers.

Write-Section "base: every machine"

# ---- Windows edition check ----
# This script installs apps only; it never touches OS licensing. If the
# Windows Setup key prompt was skipped or "I don't have a key" was chosen,
# the machine is silently still on Home and nothing else will ever flag it.
# Pro matters: Remote Desktop *into* a machine (rdp-host.ps1) needs it.
$editionId = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name EditionID -ErrorAction SilentlyContinue).EditionID
if ($editionId -and $editionId -notmatch 'Professional|Enterprise|Education') {
    Write-Host "`n=== WINDOWS EDITION WARNING ===" -ForegroundColor Red
    Write-Host "This machine is running '$editionId', not Pro/Enterprise/Education." -ForegroundColor Red
    Write-Host "Setup only installs apps -- it does not install or activate Windows." -ForegroundColor Red
    Write-Host "If you have a Windows 11 Pro key: Settings > System > Activation > Change Product Key." -ForegroundColor Yellow
    Write-Host "This is a same-media edition change; you do NOT need to reimage for this alone." -ForegroundColor Yellow
    Add-ManualStep "Upgrade Windows to Pro (Settings > System > Activation > Change Product Key), then re-run setup."
}
else {
    Write-Host "Windows edition: $editionId -- OK." -ForegroundColor Green
}

$BaseApps = @(
    "Tailscale.Tailscale",          # every machine is on the tailnet
    "Bitwarden.Bitwarden",          # client for the self-hosted Vaultwarden server
    "Microsoft.VisualStudioCode",
    "Notepad++.Notepad++",
    "Brave.Brave",
    "Google.Chrome",                # also renders the identity wallpaper (headless)
    "Git.Git",
    "GitHub.cli",                   # gh: auths git against the private repos
    "Microsoft.WindowsTerminal",
    "Notion.Notion",
    "Anthropic.Claude",             # Claude desktop app
    "Anthropic.ClaudeCode"          # Claude Code CLI
)
Install-WingetApps -Ids $BaseApps
Update-SessionPath

# ---- computer name ----
# Only when the machine file sets one. The proxy laptop's file leaves it unset
# so a re-run there never renames it.
if ($MachineConfig.ComputerName -and $env:COMPUTERNAME -ne $MachineConfig.ComputerName) {
    Write-Host "`n--- computer name ---" -ForegroundColor Yellow
    Rename-Computer -NewName $MachineConfig.ComputerName -Force
    Write-Host "Renamed $env:COMPUTERNAME -> $($MachineConfig.ComputerName). Takes effect after a restart." -ForegroundColor Green
    Add-ManualStep "Restart (computer was renamed to $($MachineConfig.ComputerName)), then sign into Tailscale so its tailnet name is $($MachineConfig.ComputerName.ToLower())."
}

# Dark mode, power and the other behaviour defaults live in preferences.ps1
# (no installs there, so it can run alone on an old machine).

# ---- identity wallpaper ----
# Templates live once, in homelab-bootstrap, shared with the Linux boxes.
$HomelabDir = Join-Path $env:USERPROFILE "homelab-bootstrap"
$hbReady = Sync-PrivateRepo -Repo "BrendanJackson/homelab-bootstrap" -Dir $HomelabDir
Write-Host "`n--- identity wallpaper ---" -ForegroundColor Yellow
$hostName = if ($MachineConfig.ComputerName) { $MachineConfig.ComputerName } else { $env:COMPUTERNAME }
if ($hbReady) {
    Set-IdentityWallpaper -HomelabDir $HomelabDir -Theme $MachineConfig.WallpaperTheme `
        -Label $MachineConfig.WallpaperLabel -HostName $hostName -Tag $MachineConfig.IdentityTag
}
else {
    # No homelab-bootstrap (it is private, so this also happens when gh has no
    # access to it) means no shared HTML theme and no Chrome render. Draw the
    # same information natively instead of leaving the machine on the Windows
    # Spotlight default -- FXWB-1 sat unlabelled for a week that way.
    # Swapping back later changes only the look, not the contract.
    Write-Host "homelab-bootstrap not available -- drawing the wallpaper natively instead." -ForegroundColor DarkYellow
    try {
        $wallBlock = [scriptblock]::Create((Get-RepoScript "windows/tools/Set-InfoWallpaper.ps1"))
        & $wallBlock -Label $MachineConfig.WallpaperLabel -HostName $hostName `
            -Tag $MachineConfig.IdentityTag -Install
    }
    catch {
        Write-Host "Native wallpaper failed too ($($_.Exception.Message)). Cosmetic only." -ForegroundColor DarkYellow
    }
}

Add-ManualStep "Sign into Tailscale (opens browser SSO)."
Add-ManualStep "Bitwarden: on the login screen choose 'Self-hosted', enter the Vaultwarden server URL, then sign in."

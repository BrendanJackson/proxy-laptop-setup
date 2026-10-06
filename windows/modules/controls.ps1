# windows/modules/controls.ps1 -- the controls field tech add-on.
# Every field laptop (proxy laptop, FXWB-1, the next one) gets this.
#
# What it adds on top of base:
#   - runtimes/tools the field work needs: Python (site-audit), Wireshark,
#     PuTTY
#   - the controls-field-tools repo, with the IP Speed Dial pre-elevated
#     shortcut and a shortcut to the capture recipes
#   - checks for the pieces winget cannot install silently (Npcap, YABE,
#     GlobalProtect) and says exactly how to finish each
#
# Licensed vendor tools (FX Workbench, Metasys) are NOT here -- each gets its
# own module (fx-workbench.ps1), because not every field laptop has them.

Write-Section "controls: field tech tools"

$ControlsApps = @(
    "Python.Python.3.12",            # controls-field-tools/site-audit (stdlib only, no pip)
    "WiresharkFoundation.Wireshark",
    "PuTTY.PuTTY"
)
Install-WingetApps -Ids $ControlsApps
Update-SessionPath

$ToolsDir = Join-Path $env:USERPROFILE "controls-field-tools"
Sync-PrivateRepo -Repo "BrendanJackson/controls-field-tools" -Dir $ToolsDir | Out-Null

# ---- IP Speed Dial, pre-elevated ----
# It needs admin to change the adapter IP. "Run JCI Elevated" only exists on
# the JCI-managed laptop, so this shortcut is the equivalent here.
Write-Host "`n--- IP Speed Dial shortcut ---" -ForegroundColor Yellow
$speedDialBat = Join-Path $ToolsDir "speed-dial\Run-IP-SpeedDial.bat"
if (Test-Path $speedDialBat) {
    New-ElevatedShortcut -Name "IP Speed Dial (Admin)" -Target $speedDialBat `
        -Description "IP Speed Dial, pre-elevated (double-click, no right-click needed)" | Out-Null
    Write-Host "Desktop shortcut created: 'IP Speed Dial (Admin)'." -ForegroundColor Green
}
else {
    Write-Host "Skipped -- $speedDialBat not found (controls-field-tools not cloned yet)." -ForegroundColor DarkYellow
}

# ---- capture recipes (Wireshark / BACnet scripts + when-to-use README) ----
$recipes = Join-Path $ToolsDir "capture-recipes\Run-Recipes.bat"
if (Test-Path $recipes) {
    New-DesktopShortcut -Name "Capture Recipes" -Target $recipes `
        -Description "Menu of Wireshark and BACnet checks for the common field problems. README.md says when to use each." | Out-Null
    Write-Host "Desktop shortcut created: 'Capture Recipes'." -ForegroundColor Green
}

# ---- Npcap (Wireshark's capture driver) ----
# Npcap's free license does not allow a silent install, so winget's Wireshark
# arrives without it and Wireshark can open files but cannot capture.
Write-Host "`n--- Npcap ---" -ForegroundColor Yellow
if (Get-Service npcap -ErrorAction SilentlyContinue) {
    Write-Host "Npcap present -- Wireshark can capture." -ForegroundColor Green
}
else {
    Write-Host "Npcap missing -- Wireshark cannot capture until it is installed." -ForegroundColor DarkYellow
    Add-ManualStep "Install Npcap from https://npcap.com/#download (defaults are fine; leave 'Restrict to Administrators' UNCHECKED so the capture scripts run without admin)."
}

# ---- YABE (BACnet explorer) ----
# Not on winget. Same app the Metasys laptop has (Yabe 1.3.2, seen 09/25).
Write-Host "`n--- YABE ---" -ForegroundColor Yellow
$yabe = Test-AppInstalled 'Yabe'
if ($yabe) { Write-Host "YABE present: $($yabe.DisplayName)" -ForegroundColor Green }
else {
    Add-ManualStep "Install YABE (BACnet explorer) from https://sourceforge.net/projects/yetanotherbacnetexplorer/ -- the Metasys laptop runs 1.3.2. How to use it: capture-recipes\README.md."
}

# ---- GlobalProtect (customer VPN) ----
# Migrated from the old laptop: Export-GlobalProtect.ps1 there writes
# globalprotect-export.json; put that file on this machine's Desktop or in
# Downloads and this step imports the portal address.
Write-Host "`n--- GlobalProtect ---" -ForegroundColor Yellow
$gpExport = @("$env:USERPROFILE\Desktop\globalprotect-export.json",
              "$env:USERPROFILE\Downloads\globalprotect-export.json") |
            Where-Object { Test-Path $_ } | Select-Object -First 1
if ($gpExport) {
    $gpBlock = [scriptblock]::Create((Get-RepoScript "windows/tools/Import-GlobalProtect.ps1"))
    & $gpBlock -ExportFile $gpExport
}
elseif (Test-AppInstalled '^GlobalProtect') {
    Write-Host "GlobalProtect present." -ForegroundColor Green
}
else {
    Add-ManualStep "GlobalProtect: on the OLD laptop run windows\tools\Export-GlobalProtect.ps1, copy globalprotect-export.json to this Desktop, re-run setup. Full steps: README 'Moving GlobalProtect'."
}

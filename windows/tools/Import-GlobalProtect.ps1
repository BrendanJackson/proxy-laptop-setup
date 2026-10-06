# Import-GlobalProtect.ps1 -- run on the NEW laptop (as Administrator), or let
# setup's controls module run it: it does so automatically when it finds
# globalprotect-export.json on the Desktop or in Downloads.
#
#   .\Import-GlobalProtect.ps1 -ExportFile "$env:USERPROFILE\Desktop\globalprotect-export.json"
#
# GlobalProtect's installer comes from the VPN portal itself (it is matched to
# the portal's version), so this does not download it. It:
#   - not installed yet: prints the portal address to open in a browser to
#     download the agent
#   - installed: pre-fills the portal address so the app opens ready to sign in

[CmdletBinding()]
param([Parameter(Mandatory)][string]$ExportFile)

$data = Get-Content -Raw $ExportFile | ConvertFrom-Json
$portal = @($data.portals) | Select-Object -First 1
if (-not $portal) {
    Write-Host "The export has no portal address. Check GlobalProtect > Settings > General on the old laptop." -ForegroundColor Yellow
    return
}
$installed = $null
foreach ($r in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
               'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*') {
    $installed = Get-ItemProperty $r -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match '^GlobalProtect' } | Select-Object -First 1
    if ($installed) { break }
}

if (-not $installed) {
    $msg = "GlobalProtect: open https://$portal in Brave, sign in, download the Windows 64-bit agent, install it, then re-run setup to pre-fill the portal."
    Write-Host $msg -ForegroundColor Yellow
    if (Get-Command Add-ManualStep -ErrorAction SilentlyContinue) { Add-ManualStep $msg }
    return
}

$key = 'HKLM:\SOFTWARE\Palo Alto Networks\GlobalProtect\PanSetup'
New-Item -Path $key -Force | Out-Null
Set-ItemProperty -Path $key -Name Portal -Value $portal
Write-Host "GlobalProtect $($installed.DisplayVersion) installed; portal set to $portal (old laptop ran $($data.version))." -ForegroundColor Green
if (@($data.portals).Count -gt 1) {
    Write-Host "Other portals the old laptop used (add in GlobalProtect > Settings if needed): $((@($data.portals) | Select-Object -Skip 1) -join ', ')" -ForegroundColor Yellow
}
$msg = "GlobalProtect: open it from the system tray, sign in (password in Vaultwarden), connect once to prove it works."
if (Get-Command Add-ManualStep -ErrorAction SilentlyContinue) { Add-ManualStep $msg } else { Write-Host $msg }

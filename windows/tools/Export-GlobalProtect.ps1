# Export-GlobalProtect.ps1 -- run on the OLD laptop. Writes the GlobalProtect
# portal address(es) and version to globalprotect-export.json on the Desktop,
# for Import-GlobalProtect.ps1 (or setup's controls module) on the new one.
#
#   Set-ExecutionPolicy Bypass -Scope Process -Force; iex (irm https://raw.githubusercontent.com/BrendanJackson/proxy-laptop-setup/master/windows/tools/Export-GlobalProtect.ps1)
#
# Read only: it changes nothing on the old laptop. It copies NO password and
# NO private key -- you sign in again on the new laptop (credentials are in
# Vaultwarden). If the VPN uses a client certificate, this lists candidate
# certificates so you know to move one; moving it is a deliberate manual step.
#
# Brendan, 2026-10-06: GlobalProtect "is the main VPN I use", and it is not
# JCI's network -- so the new laptop can join it the same way the old one did.

$portals = New-Object System.Collections.Generic.List[string]
function Add-Portal($v) { if ($v -and -not $portals.Contains($v)) { $portals.Add($v) } }

$panSetup = Get-ItemProperty 'HKLM:\SOFTWARE\Palo Alto Networks\GlobalProtect\PanSetup' -ErrorAction SilentlyContinue
Add-Portal $panSetup.Portal
foreach ($root in 'HKCU:\Software\Palo Alto Networks\GlobalProtect\Settings',
                  'HKLM:\SOFTWARE\Palo Alto Networks\GlobalProtect\Settings') {
    $s = Get-ItemProperty $root -ErrorAction SilentlyContinue
    Add-Portal $s.LastUrl
    # each portal the user has connected to is a subkey named after it
    Get-ChildItem $root -ErrorAction SilentlyContinue | ForEach-Object { Add-Portal $_.PSChildName }
}

$app = $null
foreach ($r in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
               'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*') {
    $app = Get-ItemProperty $r -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match '^GlobalProtect' } | Select-Object -First 1
    if ($app) { break }
}

# Certificates with a private key that are not Microsoft/Windows-issued are
# the ones a VPN might use for sign-in. Names only -- nothing is exported.
$certs = Get-ChildItem Cert:\CurrentUser\My, Cert:\LocalMachine\My -ErrorAction SilentlyContinue |
         Where-Object { $_.HasPrivateKey -and $_.Issuer -notmatch 'Microsoft|Windows' } |
         ForEach-Object { [ordered]@{ Store = $_.PSParentPath -replace '^.*::', ''; Subject = $_.Subject; Issuer = $_.Issuer; Expires = $_.NotAfter.ToString('yyyy-MM-dd'); Thumbprint = $_.Thumbprint } }

$out = [ordered]@{
    exportedFrom = $env:COMPUTERNAME
    exportedAt   = (Get-Date).ToString('s')
    version      = if ($app) { $app.DisplayVersion } else { $null }
    portals      = @($portals)
    certificates = @($certs)
}
$path = Join-Path ([Environment]::GetFolderPath("Desktop")) "globalprotect-export.json"
$out | ConvertTo-Json -Depth 4 | Set-Content -Path $path -Encoding UTF8

if ($portals.Count -eq 0) {
    Write-Host "No GlobalProtect portal found on this machine. Open GlobalProtect > Settings > General: the portal address is listed there; write it down." -ForegroundColor Yellow
}
else {
    Write-Host "Portal(s): $($portals -join ', ')" -ForegroundColor Green
}
if ($certs) {
    Write-Host "Certificates that MAY be used by the VPN (not exported):" -ForegroundColor Yellow
    $certs | ForEach-Object { Write-Host "  $($_.Subject)  issued by $($_.Issuer), expires $($_.Expires)" }
    Write-Host "If GlobalProtect sign-in fails on the new laptop with a certificate error, move the matching one (README 'Moving GlobalProtect')." -ForegroundColor Yellow
}
Write-Host "Wrote $path -- copy it to the new laptop's Desktop." -ForegroundColor Green

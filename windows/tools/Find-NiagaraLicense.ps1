# Find-NiagaraLicense.ps1 -- where is the FX Workbench license, and which
# machine is it tied to? Read only; changes nothing.
#
#   Set-ExecutionPolicy Bypass -Scope Process -Force; iex (irm https://raw.githubusercontent.com/BrendanJackson/proxy-laptop-setup/master/windows/tools/Find-NiagaraLicense.ps1)
#
# Brendan, 2026-10-06: "I don't know where to find the license information."
#
# FX Workbench is built on Tridium Niagara 4. Niagara licenses are small XML
# files (*.license), sometimes bundled in a *.lar archive, each tied to one
# machine by its Host ID. This finds every one on this computer and prints
# where it is, which Host ID it is for, who issued it and when it expires.
#
# Run it on the machine where Workbench already works (to find the existing
# license) and on the new one (to get the Host ID a new license must name).

$roots = @('C:\Niagara', "$env:ProgramFiles\Niagara", "${env:ProgramFiles(x86)}\Niagara",
           "$env:ProgramFiles\Johnson Controls", 'C:\JCI', $env:ProgramData, $env:USERPROFILE) |
         Where-Object { $_ -and (Test-Path $_) }

Write-Host "Searching for Niagara license files (this can take a minute)..." -ForegroundColor Cyan
$files = foreach ($r in $roots) {
    $depth = if ($r -in @($env:ProgramData, $env:USERPROFILE)) { 4 } else { 8 }
    Get-ChildItem -Path $r -Recurse -Depth $depth -Include *.license, *.lar, *.certificate -File -ErrorAction SilentlyContinue
}
$files = $files | Sort-Object FullName -Unique

if (-not $files) {
    Write-Host "No license files found on $env:COMPUTERNAME." -ForegroundColor Yellow
    Write-Host "If Workbench is not installed here yet, that is expected: a new install has no license until one is issued for this machine's Host ID."
}
foreach ($f in $files) {
    Write-Host "`n$($f.FullName)" -ForegroundColor Green
    if ($f.Extension -ne '.license') { Write-Host "  ($($f.Extension) file -- archive/certificate; the .license files are what to read)"; continue }
    $text = Get-Content -Raw $f.FullName -ErrorAction SilentlyContinue
    foreach ($attr in 'hostId', 'vendor', 'brandId', 'expiration', 'generated', 'version') {
        if ($text -match "$attr\s*=\s*""([^""]*)""") { Write-Host ("  {0,-11} {1}" -f $attr, $Matches[1]) }
    }
    $features = [regex]::Matches($text, '<feature[^>]*name\s*=\s*"([^"]+)"') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique
    if ($features) { Write-Host "  features    $(($features | Select-Object -First 12) -join ', ')$(if ($features.Count -gt 12) { ' ...' })" }
}

Write-Host "`nThis machine is $env:COMPUTERNAME." -ForegroundColor Cyan
Write-Host "Its Host ID is shown inside Workbench (Tools > License Manager, or Help > About). A license only works on the machine whose Host ID it names."

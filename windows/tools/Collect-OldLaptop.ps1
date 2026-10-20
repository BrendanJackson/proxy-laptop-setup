# Collect-OldLaptop.ps1 -- run on the OLD laptop. One command that runs every
# read-only tool in this folder and leaves the answers in ONE place.
#
#   Set-ExecutionPolicy Bypass -Scope Process -Force; iex (irm https://raw.githubusercontent.com/BrendanJackson/proxy-laptop-setup/master/windows/tools/Collect-OldLaptop.ps1)
#
# Brendan, 2026-10-07: "I don't know where the files meant to run on the other
# laptop live but I need that all organized so I can fetch the info, preferably
# with one click."
#
# Read only, like the tools it calls: it changes nothing on the old laptop and
# copies no password and no private key. Needs no administrator rights.
#
# Everything lands in Desktop\old-laptop-info\ :
#   globalprotect-export.json   the VPN portal(s), written by Export-GlobalProtect
#   niagara-licenses.txt        Host ID and license files, from Find-NiagaraLicense
#   installed-software.txt      every installed app and version
#   transcript.txt              the whole run, in case something needs reading back
#
# Then copy that folder to the new laptop. Nothing else on the old machine is
# needed.

$ErrorActionPreference = "Continue"
$RepoRaw = "https://raw.githubusercontent.com/BrendanJackson/proxy-laptop-setup/master"

$outDir = Join-Path ([Environment]::GetFolderPath("Desktop")) "old-laptop-info"
New-Item -ItemType Directory -Path $outDir -Force | Out-Null

Start-Transcript -Path (Join-Path $outDir "transcript.txt") -Force | Out-Null

Write-Host ""
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "  Collecting from $env:COMPUTERNAME" -ForegroundColor Cyan
Write-Host "  Everything lands in: $outDir" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan

# Each tool runs in its own scope so a failure in one cannot stop the others --
# a half-collected folder is still worth carrying over.
function Invoke-Tool {
    param([string]$Name, [string]$Rel)
    Write-Host ""
    Write-Host "=== $Name ===" -ForegroundColor Magenta
    try {
        $src = Invoke-RestMethod "$RepoRaw/$Rel"
        & ([scriptblock]::Create($src))
    }
    catch {
        Write-Host "$Name failed: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "(The other steps still ran; see below.)" -ForegroundColor DarkGray
    }
}

# ---- GlobalProtect -----------------------------------------------------------
# Writes globalprotect-export.json to the Desktop itself; move it in afterwards
# so the whole answer is one folder.
Invoke-Tool "GlobalProtect portal" "windows/tools/Export-GlobalProtect.ps1"
$gpOnDesktop = Join-Path ([Environment]::GetFolderPath("Desktop")) "globalprotect-export.json"
if (Test-Path $gpOnDesktop) {
    Move-Item $gpOnDesktop (Join-Path $outDir "globalprotect-export.json") -Force
    Write-Host "Moved globalprotect-export.json into $outDir" -ForegroundColor Green
}

# ---- Niagara / FX Workbench --------------------------------------------------
# This one prints rather than writing a file, so capture what it prints.
Write-Host ""
Write-Host "=== FX Workbench license ===" -ForegroundColor Magenta
try {
    $src = Invoke-RestMethod "$RepoRaw/windows/tools/Find-NiagaraLicense.ps1"
    $niagara = & ([scriptblock]::Create($src)) 6>&1 | Out-String
    $niagara | Set-Content (Join-Path $outDir "niagara-licenses.txt") -Encoding utf8
    Write-Host $niagara
}
catch {
    Write-Host "FX Workbench license scan failed: $($_.Exception.Message)" -ForegroundColor Red
}

# ---- what is installed here --------------------------------------------------
# Cheap, and it answers "which version of YABE / Workbench was on the old one?"
Write-Host ""
Write-Host "=== installed software ===" -ForegroundColor Magenta
try {
    $roots = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
             'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
             'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    $apps = Get-ItemProperty $roots -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName } |
            Select-Object DisplayName, DisplayVersion, Publisher |
            Sort-Object DisplayName -Unique
    $apps | Format-Table -AutoSize | Out-String -Width 200 |
        Set-Content (Join-Path $outDir "installed-software.txt") -Encoding utf8
    Write-Host "$($apps.Count) programs written to installed-software.txt" -ForegroundColor Green

    # The ones this migration actually turns on. Match on how the vendor really
    # registers itself, not on the product's full name: YABE appears as
    # "Yabe version 1.3.2", with no "BACnet" anywhere in it, so searching for
    # "BACnet" reported it missing on MA-5P23ZB4 when it was installed.
    foreach ($w in 'GlobalProtect', 'Workbench', 'Niagara', 'Tridium', 'mRemoteNG',
                   'Npcap', 'Wireshark', 'Yabe', 'Metasys') {
        $hit = $apps | Where-Object { $_.DisplayName -like "*$w*" } | Select-Object -First 1
        if ($hit) { Write-Host ("  [x] {0,-14} {1} {2}" -f $w, $hit.DisplayName, $hit.DisplayVersion) -ForegroundColor Green }
        else      { Write-Host ("  [ ] {0,-14} not installed here" -f $w) -ForegroundColor DarkGray }
    }
}
catch {
    Write-Host "Software inventory failed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "  Done. Copy this folder to the new laptop:" -ForegroundColor Cyan
Write-Host "  $outDir" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan

Stop-Transcript | Out-Null
Start-Process explorer.exe $outDir

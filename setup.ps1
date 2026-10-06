# setup.ps1 -- one command to set up any of our Windows machines.
# Run in PowerShell as Administrator.
#
# Proxy laptop (the original one-liner, unchanged):
#   Set-ExecutionPolicy Bypass -Scope Process -Force; iex (irm https://raw.githubusercontent.com/BrendanJackson/proxy-laptop-setup/master/setup.ps1)
#
# Any other machine (name = a file in windows/machines/):
#   Set-ExecutionPolicy Bypass -Scope Process -Force; & ([scriptblock]::Create((irm https://raw.githubusercontent.com/BrendanJackson/proxy-laptop-setup/master/setup.ps1))) -Machine fxwb-1
#
# How it is put together (TSK-203, 2026-10-06):
#   windows/lib/common.ps1     helpers every module uses
#   windows/modules/<name>.ps1 one piece of a machine: base (every machine),
#                              controls (field tech), remote-hub, rdp-host,
#                              fx-workbench
#   windows/machines/<m>.ps1   one short file per machine: its name, wallpaper,
#                              and which modules it gets
# A new machine is a new file in windows/machines/. New code is only needed
# for a genuinely new kind of piece -- same rule as homelab-bootstrap's roles.
#
# Works from a clone (reads the files next to it) or from the one-liner (no
# files on disk; fetches each piece from this repo's master branch).

[CmdletBinding()]
param([string]$Machine = "proxy")

$ErrorActionPreference = "Continue"
$RepoRaw = "https://raw.githubusercontent.com/BrendanJackson/proxy-laptop-setup/master"
$LocalRoot = $PSScriptRoot

function Get-RepoScript([string]$Rel) {
    if ($LocalRoot) {
        $p = Join-Path $LocalRoot $Rel
        if (Test-Path $p) { return Get-Content -Raw $p }
    }
    return (Invoke-RestMethod "$RepoRaw/$($Rel -replace '\\','/')")
}

$Machine = $Machine.ToLower()
. ([scriptblock]::Create((Get-RepoScript "windows/lib/common.ps1")))
try {
    . ([scriptblock]::Create((Get-RepoScript "windows/machines/$Machine.ps1")))
}
catch {
    Write-Host "No machine file 'windows/machines/$Machine.ps1' ($($_.Exception.Message))." -ForegroundColor Red
    Write-Host "Machines in this repo: see the windows/machines folder on GitHub." -ForegroundColor Red
    return
}

Write-Host "Setting up '$Machine' -- modules: $($MachineConfig.Modules -join ', ')" -ForegroundColor Cyan
foreach ($m in $MachineConfig.Modules) {
    . ([scriptblock]::Create((Get-RepoScript "windows/modules/$m.ps1")))
}

Write-Host "`nDone. Manual steps still required:" -ForegroundColor Green
$i = 1
foreach ($s in $ManualSteps) { Write-Host "$i. $s"; $i++ }
Write-Host "`nRe-running setup is safe: installed apps are skipped." -ForegroundColor DarkGray

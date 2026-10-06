# windows/modules/fx-workbench.ps1 -- Johnson Controls FX Workbench (Niagara 4).
#
# Brendan, 2026-10-06: "I have workbench and workbench pro version 14.15.1,
# I don't know where to find the license information."
#
# FX Workbench is a licensed JCI installer, not a winget package, so this
# module never downloads or installs it. It checks what is installed, says
# exactly what is left, and points at Find-NiagaraLicense.ps1 for the license.
# Niagara licenses are tied to the machine (its Host ID), so a license file
# copied from another computer will not unlock this one; see the README.

Write-Section "fx-workbench: FX Workbench $($MachineConfig.FxWorkbenchVersion)"

$want = $MachineConfig.FxWorkbenchVersion
$found = @()
foreach ($r in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
               'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*') {
    $found += Get-ItemProperty $r -ErrorAction SilentlyContinue |
              Where-Object { $_.DisplayName -match 'Workbench|Niagara' -or $_.Publisher -match 'Tridium' }
}
# Niagara installers often only lay down a folder, no Uninstall entry, so
# look on disk too.
$dirs = @(Get-ChildItem 'C:\Niagara', "$env:ProgramFiles\Niagara", "$env:ProgramFiles\Johnson Controls", 'C:\JCI' `
            -Directory -ErrorAction SilentlyContinue |
          Where-Object { $_.Name -match 'Niagara|Workbench|FX|^4\.' })

if ($found -or $dirs) {
    $found | ForEach-Object { Write-Host "Installed: $($_.DisplayName) $($_.DisplayVersion)" -ForegroundColor Green }
    $dirs  | ForEach-Object { Write-Host "Folder:    $($_.FullName)" -ForegroundColor Green }
    $all = ($found | ForEach-Object { "$($_.DisplayName) $($_.DisplayVersion)" }) + ($dirs | ForEach-Object Name)
    if (-not ($all -match [regex]::Escape($want))) {
        Write-Host "None of these mention $want -- check the version in Workbench: Help > About." -ForegroundColor DarkYellow
    }
}
else {
    Write-Host "FX Workbench not found on this machine." -ForegroundColor DarkYellow
    Add-ManualStep "Install FX Workbench $want, then FX Workbench Pro $want, from your installer copies (run each installer as Administrator). Re-run setup to confirm it is detected."
}

Add-ManualStep "FX Workbench license: run windows\tools\Find-NiagaraLicense.ps1 on the machine where Workbench already works, AND on this one. It lists the license files and the Host ID each is tied to. README 'FX Workbench license' says what to do with the result."

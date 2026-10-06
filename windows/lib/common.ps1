# windows/lib/common.ps1 -- helpers every module uses. Dot-sourced by setup.ps1
# before any module runs; never run on its own.
#
# The pieces here were all in the original single-file setup.ps1 (proxy
# laptop, 2026-09-24..10-01). They moved here unchanged in behavior when the
# repo was split into shared base + add-on modules + one file per machine
# (TSK-203, 2026-10-06), so a second Windows machine reuses them instead of
# copying them.

# Manual steps collected from every module, printed once at the very end so
# they are not lost in the install scroll.
$ManualSteps = New-Object System.Collections.Generic.List[string]
function Add-ManualStep([string]$Text) { if (-not $ManualSteps.Contains($Text)) { $ManualSteps.Add($Text) } }

function Write-Section([string]$Title) { Write-Host "`n=== $Title ===" -ForegroundColor Cyan }

# Direct-download fallbacks for apps whose vendor deletes old installers, so a
# stale winget catalog points at a file that no longer exists. Notion does
# this; a fresh Windows install failed on it every time (FXWB-1, 2026-10-06).
# The URL must always redirect to the CURRENT installer.
$WingetFallbacks = @{
    "Notion.Notion" = @{ Url = "https://www.notion.so/desktop/windows/download"; Args = "/S"; Name = "Notion" }
}

$script:WingetSourceUpdated = $false
function Install-WingetApps {
    param([string[]]$Ids)
    # A fresh Windows install ships an old copy of winget's catalog; refresh it
    # once per run so installs use current download links.
    if (-not $script:WingetSourceUpdated) {
        Write-Host "Refreshing the winget catalog..." -ForegroundColor DarkGray
        winget source update --disable-interactivity | Out-Null
        $script:WingetSourceUpdated = $true
    }
    foreach ($app in $Ids) {
        Write-Host "`n--- $app ---" -ForegroundColor Yellow
        winget install --id $app --exact --silent --accept-package-agreements --accept-source-agreements --disable-interactivity
        # Exit codes vary (already installed, no upgrade available...), so ask
        # winget whether the app is there rather than trusting the code.
        winget list --id $app --exact --disable-interactivity *> $null
        if ($LASTEXITCODE -eq 0) { continue }
        $fb = $WingetFallbacks[$app]
        if ($fb) {
            Write-Host "winget could not install $app -- downloading $($fb.Name) directly from the vendor." -ForegroundColor DarkYellow
            $tmp = Join-Path $env:TEMP "$($fb.Name)-setup.exe"
            try {
                Invoke-WebRequest -Uri $fb.Url -OutFile $tmp -UseBasicParsing
                Start-Process -FilePath $tmp -ArgumentList $fb.Args -Wait
                Write-Host "$($fb.Name) installed from the vendor download." -ForegroundColor Green
            }
            catch {
                Write-Host "Direct download of $($fb.Name) failed too: $($_.Exception.Message)" -ForegroundColor Red
                Add-ManualStep "Install $($fb.Name) by hand from $($fb.Url)"
            }
        }
        else {
            Add-ManualStep "$app did not install (see its winget error above). Re-run setup; if it fails again, install it by hand."
        }
    }
}

# winget installs land on PATH only for new shells; pull the updated machine +
# user PATH into this process so a just-installed gh/git/tailscale is usable now.
function Update-SessionPath {
    $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                [Environment]::GetEnvironmentVariable("Path", "User")
}

# True if an app with a matching DisplayName is in any Uninstall registry hive.
function Test-AppInstalled([string]$NamePattern) {
    $roots = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
             'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
             'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    foreach ($r in $roots) {
        $hit = Get-ItemProperty $r -ErrorAction SilentlyContinue |
               Where-Object { $_.DisplayName -match $NamePattern } | Select-Object -First 1
        if ($hit) { return $hit }
    }
    return $null
}

# Clone/pull a private repo, skipping cleanly if gh isn't ready yet.
function Sync-PrivateRepo {
    param([string]$Repo, [string]$Dir)
    $name = $Repo.Split('/')[-1]
    Write-Host "`n--- $name ---" -ForegroundColor Yellow
    $ghOk = Get-Command gh -ErrorAction SilentlyContinue
    if (-not $ghOk) {
        Write-Host "gh isn't on PATH yet (fresh install needs a new shell). Re-run setup in a new PowerShell window to pick up the clone step." -ForegroundColor DarkYellow
        return $false
    }
    if (Test-Path $Dir) {
        Write-Host "$name already present at $Dir -- pulling latest." -ForegroundColor Cyan
        git -C $Dir pull
        return $true
    }
    gh auth status 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Not signed into GitHub yet. Run 'gh auth login' (opens a browser for SSO), then re-run setup to clone $name." -ForegroundColor DarkYellow
        Add-ManualStep "Run 'gh auth login', then re-run setup so $name gets cloned."
        return $false
    }
    gh repo clone $Repo $Dir
    return $?
}

# Desktop shortcut with the "Run as administrator" flag set, so a plain
# double-click elevates. Windows still shows the UAC prompt each launch; this
# only removes the right-click step.
function New-ElevatedShortcut {
    param([string]$Name, [string]$Target, [string]$Description)
    $lnkPath = Join-Path ([Environment]::GetFolderPath("Desktop")) "$Name.lnk"
    $wsh = New-Object -ComObject WScript.Shell
    $shortcut = $wsh.CreateShortcut($lnkPath)
    $shortcut.TargetPath = $Target
    $shortcut.WorkingDirectory = Split-Path $Target -Parent
    $shortcut.Description = $Description
    $shortcut.Save()
    # .lnk byte 0x15 bit 0x20 is the "run as administrator" flag -- not exposed
    # by the WScript.Shell COM object, so it's set directly on the saved file.
    $bytes = [System.IO.File]::ReadAllBytes($lnkPath)
    $bytes[0x15] = $bytes[0x15] -bor 0x20
    [System.IO.File]::WriteAllBytes($lnkPath, $bytes)
    return $lnkPath
}

# Plain (non-elevated) desktop shortcut, e.g. to open a folder.
function New-DesktopShortcut {
    param([string]$Name, [string]$Target, [string]$Description)
    $lnkPath = Join-Path ([Environment]::GetFolderPath("Desktop")) "$Name.lnk"
    $wsh = New-Object -ComObject WScript.Shell
    $shortcut = $wsh.CreateShortcut($lnkPath)
    $shortcut.TargetPath = $Target
    $shortcut.Description = $Description
    $shortcut.Save()
    return $lnkPath
}

# Identity wallpaper. Reuses the template + headless-Chrome render pipeline
# homelab-bootstrap uses for the Linux boxes (dotfiles/wallpapers/<theme>.html,
# same label/host/tag/ip query-string contract) -- one shared source of truth,
# two OS-native apply steps. See homelab-bootstrap/docs/DIVERGENCE.md #16.
function Set-IdentityWallpaper {
    param([string]$HomelabDir, [string]$Theme, [string]$Label, [string]$HostName, [string]$Tag)
    $themeFile = Join-Path $HomelabDir "dotfiles\wallpapers\$Theme.html"
    $chrome = "$env:ProgramFiles\Google\Chrome\Application\chrome.exe"
    if (-not (Test-Path $chrome)) { $chrome = "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe" }
    if (-not (Test-Path $themeFile)) {
        Write-Host "Skipped -- $themeFile not found (homelab-bootstrap clone may be stale; try 'git -C $HomelabDir pull')." -ForegroundColor DarkYellow
        return
    }
    if (-not (Test-Path $chrome)) {
        Write-Host "Skipped -- Chrome not found at the expected winget install path yet. Re-run setup in a new PowerShell window." -ForegroundColor DarkYellow
        return
    }
    $wallDir = Join-Path $env:USERPROFILE "Pictures\wallpapers"
    New-Item -ItemType Directory -Path $wallDir -Force | Out-Null
    $out = Join-Path $wallDir "$HostName.png"
    $tsIp = ""
    if (Get-Command tailscale -ErrorAction SilentlyContinue) { $tsIp = (& tailscale ip -4 2>$null | Select-Object -First 1) }
    $url = "file:///$($themeFile -replace '\\','/')?label=$([uri]::EscapeDataString($Label))&host=$HostName&tag=$([uri]::EscapeDataString($Tag))&ip=$tsIp"
    & $chrome --headless=new --no-sandbox --disable-gpu --hide-scrollbars --force-device-scale-factor=1 `
        --window-size=1920,1080 --virtual-time-budget=8000 --screenshot="$out" "$url" 2>$null
    if (Test-Path $out) {
        Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name Wallpaper -Value $out
        Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name WallpaperStyle -Value 10   # fill
        Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name TileWallpaper -Value 0
        RUNDLL32.EXE user32.dll,UpdatePerUserSystemParameters
        Write-Host "Identity wallpaper set: $out" -ForegroundColor Green
        if (-not $tsIp) { Write-Host "(Tailscale IP blank -- sign in and re-run setup to fill it in.)" -ForegroundColor DarkYellow }
    }
    else {
        Write-Host "WARNING: Chrome produced no image -- wallpaper not set. Cosmetic only, rest of setup is unaffected." -ForegroundColor DarkYellow
    }
}

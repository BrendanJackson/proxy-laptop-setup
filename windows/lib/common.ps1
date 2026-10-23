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
    if ($LASTEXITCODE -eq 0) { return $true }
    # gh can be signed in with a fine-grained token that only covers some
    # repos (FXWB-1, 2026-10-23: "Could not resolve to a Repository") while
    # Git Credential Manager holds a login that does see them. Try plain git.
    Write-Host "gh could not clone $Repo -- trying git with the saved Git credentials." -ForegroundColor DarkYellow
    if (Test-Path $Dir) { Remove-Item $Dir -Recurse -Force }
    git clone "https://github.com/$Repo.git" $Dir
    if ($LASTEXITCODE -eq 0) { return $true }
    Add-ManualStep "Could not clone $Repo with gh or git. Run 'gh auth login' (choose a login that can see private repos), then re-run setup."
    return $false
}

# Desktop shortcut with the "Run as administrator" flag set, so a plain
# double-click elevates. Windows still shows the UAC prompt each launch; this
# only removes the right-click step.
function New-ElevatedShortcut {
    param([string]$Name, [string]$Target, [string]$Description,
          # Where the .lnk goes; the Desktop unless told otherwise (e.g. a
          # Start menu Programs folder).
          [string]$Folder = [Environment]::GetFolderPath("Desktop"),
          [string]$Arguments, [string]$WorkingDirectory, [string]$Icon)
    New-Item -ItemType Directory -Path $Folder -Force | Out-Null
    $lnkPath = Join-Path $Folder "$Name.lnk"
    $wsh = New-Object -ComObject WScript.Shell
    $shortcut = $wsh.CreateShortcut($lnkPath)
    $shortcut.TargetPath = $Target
    if ($Arguments) { $shortcut.Arguments = $Arguments }
    $shortcut.WorkingDirectory = if ($WorkingDirectory) { $WorkingDirectory } else { Split-Path $Target -Parent }
    if ($Icon) { $shortcut.IconLocation = $Icon }
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

# Pin Start menu shortcuts to the taskbar. Windows 11 has no API or verb for
# this any more; the supported route is a taskbar layout XML named by the
# StartLayoutFile policy. PinListPlacement="Append" adds to whatever is already
# pinned instead of replacing it, and Windows applies a given layout once, so
# anything the person unpins later stays unpinned. Per user (HKCU), takes
# effect when Explorer restarts or at the next sign-in. Every pin this repo
# wants goes in one call: the file is rewritten each time.
function Set-TaskbarPins {
    param([string[]]$LinkPaths)
    $layoutDir = Join-Path $env:LOCALAPPDATA "proxy-laptop-setup"
    New-Item -ItemType Directory -Path $layoutDir -Force | Out-Null
    $layout = Join-Path $layoutDir "TaskbarLayout.xml"
    $pins = ($LinkPaths | ForEach-Object {
        "        <taskbar:DesktopApp DesktopApplicationLinkPath=`"$([Security.SecurityElement]::Escape($_))`" />"
    }) -join "`r`n"
    @"
<?xml version="1.0" encoding="utf-8"?>
<LayoutModificationTemplate
    xmlns="http://schemas.microsoft.com/Start/2014/LayoutModification"
    xmlns:defaultlayout="http://schemas.microsoft.com/Start/2014/FullDefaultLayout"
    xmlns:start="http://schemas.microsoft.com/Start/2014/StartLayout"
    xmlns:taskbar="http://schemas.microsoft.com/Start/2014/TaskbarLayout"
    Version="1">
  <CustomTaskbarLayoutCollection PinListPlacement="Append">
    <defaultlayout:TaskbarLayout>
      <taskbar:TaskbarPinList>
$pins
      </taskbar:TaskbarPinList>
    </defaultlayout:TaskbarLayout>
  </CustomTaskbarLayoutCollection>
</LayoutModificationTemplate>
"@ | Set-Content -Path $layout -Encoding utf8
    # HKCU\Software\Policies is writable only from an elevated shell, which
    # is how setup normally runs; say so instead of failing quietly.
    $key = "HKCU:\Software\Policies\Microsoft\Windows\Explorer"
    try {
        if (-not (Test-Path $key)) { New-Item -Path $key -Force -ErrorAction Stop | Out-Null }
        Set-ItemProperty -Path $key -Name StartLayoutFile -Value $layout -ErrorAction Stop
        # 0 = the person can still pin, unpin and rearrange as they like.
        Set-ItemProperty -Path $key -Name LockedStartLayout -Value 0 -Type DWord -ErrorAction Stop
        return $layout
    }
    catch {
        Write-Host "Could not set the taskbar layout policy ($($_.Exception.Message)). Run setup as Administrator." -ForegroundColor DarkYellow
        return $null
    }
}

# Pin a folder to File Explorer's Quick Access ("Home"). Same as right-click >
# Pin to Quick access; re-running is harmless.
function Add-QuickAccessPin([string]$Folder) {
    $shell = New-Object -ComObject Shell.Application
    $self = $shell.Namespace($Folder).Self
    # Explorer only offers "pintohome" on a folder that is not pinned yet
    # (a pinned one offers "unpinfromhome"), so its presence is the check.
    if (-not ($self.Verbs() | Where-Object { ($_.Name -replace '&', '') -match '^Pin to (Quick access|Home)' })) { return $false }
    $self.InvokeVerb("pintohome")
    return $true
}

# Identity wallpaper. Reuses the template + headless-Chrome render pipeline
# homelab-bootstrap uses for the Linux boxes (dotfiles/wallpapers/<theme>.html,
# same label/host/tag/ip query-string contract) -- one shared source of truth,
# two OS-native apply steps. See homelab-bootstrap/docs/DIVERGENCE.md #16.
function Set-IdentityWallpaper {
    # -ThemeFile renders a theme from anywhere and takes precedence over
    # -HomelabDir/-Theme. It exists so the same Chrome pipeline can render a
    # theme that is not in homelab-bootstrap -- that repo is private, so a
    # machine whose gh token cannot see it would otherwise lose the artistic
    # render entirely and fall back to the plain native drawing.
    param([string]$HomelabDir, [string]$Theme, [string]$Label, [string]$HostName, [string]$Tag,
          [string]$ThemeFile)
    if (-not $ThemeFile) { $ThemeFile = Join-Path $HomelabDir "dotfiles\wallpapers\$Theme.html" }
    $themeFile = $ThemeFile
    $chrome = "$env:ProgramFiles\Google\Chrome\Application\chrome.exe"
    if (-not (Test-Path $chrome)) { $chrome = "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe" }
    if (-not (Test-Path $themeFile)) {
        Write-Host "Skipped -- $themeFile not found (homelab-bootstrap clone may be stale; try 'git -C $HomelabDir pull')." -ForegroundColor DarkYellow
        return $false
    }
    if (-not (Test-Path $chrome)) {
        Write-Host "Skipped -- Chrome not found at the expected winget install path yet. Re-run setup in a new PowerShell window." -ForegroundColor DarkYellow
        return $false
    }
    $wallDir = Join-Path $env:USERPROFILE "Pictures\wallpapers"
    New-Item -ItemType Directory -Path $wallDir -Force | Out-Null
    $out = Join-Path $wallDir "$HostName.png"
    $tsIp = ""
    if (Get-Command tailscale -ErrorAction SilentlyContinue) { $tsIp = (& tailscale ip -4 2>$null | Select-Object -First 1) }
    $url = "file:///$($themeFile -replace '\\','/')?label=$([uri]::EscapeDataString($Label))&host=$HostName&tag=$([uri]::EscapeDataString($Tag))&ip=$tsIp"
    # --user-data-dir is NOT optional. Without it, a headless Chrome launched
    # while the user already has Chrome open just hands the URL to the running
    # instance and exits 0 having written nothing, so the render silently
    # produces no file. That is why this step "worked" in testing on a clean
    # machine and never once produced a wallpaper on a machine in daily use.
    $chromeProfile = Join-Path $env:TEMP "wallpaper-chrome-profile"
    & $chrome --headless --no-sandbox --disable-gpu --hide-scrollbars --force-device-scale-factor=1 `
        --user-data-dir="$chromeProfile" --no-first-run --window-size=1920,1080 `
        --virtual-time-budget=8000 --screenshot="$out" "$url" 2>$null
    if (Test-Path $out) {
        Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name Wallpaper -Value $out
        Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name WallpaperStyle -Value 10   # fill
        Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name TileWallpaper -Value 0
        # Windows 11 Spotlight owns the desktop until it is switched back to a
        # picture, and it rotates its own image in on a timer -- so without this
        # the render above silently disappears within the hour. Found on FXWB-1,
        # which was still on the Spotlight default after setup had "set" a
        # wallpaper. BackgroundType 0 = picture.
        $wpKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Wallpapers'
        if (-not (Test-Path $wpKey)) { New-Item -Path $wpKey -Force | Out-Null }
        Set-ItemProperty -Path $wpKey -Name 'BackgroundType' -Value 0 -Type DWord -Force
        RUNDLL32.EXE user32.dll,UpdatePerUserSystemParameters
        Write-Host "Identity wallpaper set: $out" -ForegroundColor Green
        if (-not $tsIp) { Write-Host "(Tailscale IP blank -- sign in and re-run setup to fill it in.)" -ForegroundColor DarkYellow }
        return $true
    }
    Write-Host "WARNING: Chrome produced no image -- wallpaper not set. Cosmetic only, rest of setup is unaffected." -ForegroundColor DarkYellow
    return $false
}

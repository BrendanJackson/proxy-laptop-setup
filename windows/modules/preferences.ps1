# windows/modules/preferences.ps1 -- how every machine behaves: power, dark
# mode, and the small conveniences. No apps are installed here, so this piece
# is safe to run on an OLD machine on its own:
#   ... setup.ps1 ... -Machine existing           (preferences + claude)
#   ... setup.ps1 ... -Machine existing -Only preferences
#
# Brendan, 2026-10-06: "off charging cable we default to low power mode, on
# power we stay live for 5 hours, dark mode at a system level, and any other
# conveniences ... Make these defaults not just for the new laptop but for all
# new machines, we also may update old machines with some of this code."
#
# Every setting is a plain Windows setting you can change back in Settings;
# nothing here is locked by policy. Re-running just sets the same values again.

Write-Section "preferences: power, dark mode, conveniences"

# One failed setting must not hide the rest: report it by name and carry on.
function Set-Reg([string]$Path, [string]$Name, $Value, [string]$Type = "DWord") {
    try {
        if (-not (Test-Path $Path)) { New-Item -Path $Path -Force -ErrorAction Stop | Out-Null }
        Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -ErrorAction Stop
    }
    catch {
        Write-Host "Could not set $Name ($Path): $($_.Exception.Message)" -ForegroundColor Red
        Add-ManualStep "Setting '$Name' was refused by Windows; tell Claude the red line it printed."
    }
}

# ---- power -------------------------------------------------------------------
Write-Host "`n--- power ---" -ForegroundColor Yellow
$acSleep = if ($null -ne $MachineConfig.AcSleepMinutes) { [int]$MachineConfig.AcSleepMinutes } else { 300 }

# Plugged in: awake for 5 hours idle (0 = never), screen off after 30 min.
powercfg /change standby-timeout-ac $acSleep
powercfg /change hibernate-timeout-ac 0
powercfg /change monitor-timeout-ac 30
# On battery: screen off after 5 min, sleep after 15.
powercfg /change monitor-timeout-dc 5
powercfg /change standby-timeout-dc 15
# On battery: Energy Saver (Battery Saver) on at ANY charge level, i.e.
# always on when unplugged. This is the "low power mode": it lowers
# performance and background activity whenever the cable is out.
powercfg /setdcvalueindex SCHEME_CURRENT SUB_ENERGYSAVER ESBATTTHRESHOLD 100
powercfg /setactive SCHEME_CURRENT
# NOT set here: the Settings "Power mode" slider. Its registry key
# (...\Control\Power\User\PowerSchemes) is locked to the SYSTEM account, so
# an admin script gets "Requested registry access is not allowed" (FXWB-1,
# 2026-10-06). Energy Saver above already gives low power on battery.
$acText = if ($acSleep -eq 0) { "never sleeps" } else { "sleeps after $([math]::Round($acSleep / 60, 1)) h idle" }
Write-Host "Plugged in: $acText, screen off 30 min. On battery: Energy Saver always on, screen 5 min, sleep 15 min." -ForegroundColor Green

# Fast startup off: "Shut down" really shuts down, so network adapters, drivers
# and a static IP set by IP Speed Dial come back clean, and updates finish.
Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' HiberbootEnabled 0

# ---- dark mode (system + apps) ----------------------------------------------
Write-Host "`n--- dark mode ---" -ForegroundColor Yellow
$personalize = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
Set-Reg $personalize AppsUseLightTheme 0
Set-Reg $personalize SystemUsesLightTheme 0
Write-Host "Dark mode: system and apps." -ForegroundColor Green

# ---- conveniences -----------------------------------------------------------
Write-Host "`n--- conveniences ---" -ForegroundColor Yellow
$adv = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
Set-Reg $adv HideFileExt 0          # show file extensions: tells setup.bat from setup.txt
Set-Reg $adv Hidden 1               # show hidden files (AppData, .git, .claude)
Set-Reg $adv LaunchTo 1             # File Explorer opens on "This PC", not Recent
Set-Reg "$adv\TaskbarDeveloperSettings" TaskbarEndTask 1      # right-click a taskbar app > End task
Set-Reg 'HKCU:\Software\Microsoft\Clipboard' EnableClipboardHistory 1   # Win+V clipboard history
# Start-menu search shows this computer's results only, no Bing web results.
Set-Reg 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' DisableSearchBoxSuggestions 1
# Classic right-click menu (no "Show more options" step). Delete this key to undo.
$classic = 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32'
if (-not (Test-Path $classic)) { New-Item -Path $classic -Force | Out-Null }
Set-ItemProperty -Path $classic -Name '(default)' -Value ''
# Long file paths: deep project/site folders and git checkouts stop failing at 260 chars.
Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' LongPathsEnabled 1
# Time zone: Kentucky, Eastern (same as dev-1).
Set-TimeZone -Id "Eastern Standard Time"
Write-Host "File extensions + hidden files shown, Explorer opens on This PC, taskbar End task, clipboard history, no Bing in Start, classic right-click menu, long paths, Eastern time." -ForegroundColor Green

# Explorer re-reads most of the above only when it restarts. The taskbar
# blinks for a second; open windows are unaffected.
Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue

Add-ManualStep "Sign out and back in once so every preference (classic right-click menu, Start search) is fully applied."

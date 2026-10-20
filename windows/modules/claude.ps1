# windows/modules/claude.ps1 -- how Claude Code behaves on this machine.
#
# base.ps1 installs Anthropic.ClaudeCode; this piece configures it. No apps are
# installed here, so like preferences.ps1 it is safe to run alone on an OLD
# machine:
#   ... setup.ps1 ... -Machine existing -Only claude
#
# Brendan, 2026-10-06: "Claude Code default --dangerously-skip-permissions on
# new machines + sessions set up for remote access."
#
# Four things, in order:
#
#   1. permissions.defaultMode = "bypassPermissions" (plus
#      skipDangerousModePermissionPrompt, so the one-time "are you sure" banner
#      never stalls an unattended start) when the machine file sets
#      ClaudeSkipPermissions. This is the settings.json equivalent of starting
#      Claude Code with --dangerously-skip-permissions, and it is what makes
#      unattended runs possible: without it a session driven over RDP or from
#      the phone stops at the first permission prompt with nobody there to
#      answer it.
#
#      It is a real reduction in safety -- Claude Code stops asking before it
#      runs commands or edits files. It is opt-in per machine for that reason:
#      right for a single-user field laptop, wrong for anything shared.
#
#   2. The same look and housekeeping as dev-1: dark theme inside Claude Code
#      (the OS dark mode is preferences.ps1's job) and 365 days of session
#      history instead of the 30-day default, so a conversation from a site
#      visit last quarter can still be resumed.
#
#   3. Push notifications, so a session here can be followed from claude.ai/code
#      or the phone app.
#
#   4. Remote Control at sign-in, unless the machine file sets
#      ClaudeRemoteControl = $false. A per-user Scheduled Task
#      "Claude Remote Control (<host>)" runs `claude remote-control` at logon
#      and retries every 15 minutes, in %USERPROFILE%\claude-remote. The
#      machine then shows up in claude.ai/code and the phone app as
#      "<HOST>: <role>" whenever someone is signed in, with nothing to click.
#      This is how dev-1 does it (cron @reboot -> tmux -> claude remote-control)
#      and how the Windows desktop was set up by hand; this piece makes it
#      part of setup so a reimage does not lose it.
#
#      Claude Code refuses to serve the home folder itself ("home-directory
#      trust is never saved"), hence the dedicated folder, and it asks to trust
#      a new folder on first use -- with no terminal to answer on, that prompt
#      would hang the task forever. So the folder is pre-trusted here through
#      the same key Claude Code writes when you answer "yes" by hand:
#      projects["<folder>"].hasTrustDialogAccepted in ~\.claude.json.
#
# Needs from setup.ps1: $MachineConfig (machine file), common.ps1 helpers.
# Machine-file keys read here (all optional):
#   ClaudeSkipPermissions  $true = no permission prompts        (default $false)
#   ClaudeRemoteControl    $false = no Remote Control task       (default $true)
#   RemoteControlName      session name shown in claude.ai/code (default "<HOST>: <IdentityTag>")

Write-Section "claude: Claude Code configuration"

$claudeDir = Join-Path $env:USERPROFILE ".claude"
$settingsPath = Join-Path $claudeDir "settings.json"
$globalConfigPath = Join-Path $env:USERPROFILE ".claude.json"
$skip = [bool]$MachineConfig.ClaudeSkipPermissions
$remote = if ($null -ne $MachineConfig.ClaudeRemoteControl) { [bool]$MachineConfig.ClaudeRemoteControl } else { $true }
$hostName = if ($MachineConfig.ComputerName) { $MachineConfig.ComputerName } else { $env:COMPUTERNAME }
$remoteName = if ($MachineConfig.RemoteControlName) { [string]$MachineConfig.RemoteControlName }
              elseif ($MachineConfig.IdentityTag) { "{0}: {1}" -f $hostName, $MachineConfig.IdentityTag }
              else { "{0}: Remote Control" -f $hostName }
$remoteDir = Join-Path $env:USERPROFILE "claude-remote"
$launcherPath = Join-Path $remoteDir "Start-ClaudeRemoteControl.ps1"
$taskName = "Claude Remote Control ($hostName)"

# Read a JSON object file into an ordered hashtable, after backing it up.
# Returns $null when the file exists but cannot be parsed -- a file we cannot
# read is not ours to silently replace. Merge rather than overwrite: these
# files also hold anything the person (or Claude itself) has set from inside
# the app, and a re-run must not drop it.
function Read-ClaudeJsonFile([string]$Path) {
    $table = [ordered]@{}
    if (-not (Test-Path $Path)) { return $table }
    $backup = "$Path.$(Get-Date -Format 'yyyyMMdd-HHmmss').bak"
    try {
        Copy-Item $Path $backup -Force
        $raw = Get-Content $Path -Raw
        if ($raw.Trim()) {
            ($raw | ConvertFrom-Json).PSObject.Properties |
                ForEach-Object { $table[$_.Name] = $_.Value }
        }
        Write-Host "Existing $(Split-Path $Path -Leaf) backed up to $(Split-Path $backup -Leaf)." -ForegroundColor DarkGray
        return $table
    }
    catch {
        Write-Host "Could not read $Path ($($_.Exception.Message))." -ForegroundColor Red
        return $null
    }
}

# ---- settings.json -----------------------------------------------------------
$settings = Read-ClaudeJsonFile $settingsPath
if ($null -eq $settings) {
    Add-ManualStep "~\.claude\settings.json could not be parsed, so Claude Code was left alone. Fix or delete that file, then re-run setup -Only claude."
    return
}
if (-not (Test-Path $claudeDir)) { New-Item -ItemType Directory -Path $claudeDir -Force | Out-Null }

# ---- permission mode ---------------------------------------------------------
Write-Host "`n--- permission mode ---" -ForegroundColor Yellow
if ($skip) {
    # permissions may already carry allow/deny rules; only defaultMode is ours.
    $perms = if ($settings.Contains("permissions") -and $settings["permissions"]) {
        $settings["permissions"]
    }
    else {
        [PSCustomObject]@{}
    }
    $perms | Add-Member -NotePropertyName "defaultMode" -NotePropertyValue "bypassPermissions" -Force
    $settings["permissions"] = $perms
    # Without this, the first start in bypass mode shows a "yes, I accept the
    # risks" banner that needs a keypress -- fatal for a session nobody is
    # watching. dev-1 runs with the same key.
    $settings["skipDangerousModePermissionPrompt"] = $true

    Write-Host "permissions.defaultMode = bypassPermissions (and no confirmation banner)" -ForegroundColor Green
    Write-Host "Claude Code will NOT ask before running commands or editing files here." -ForegroundColor DarkYellow
}
else {
    Write-Host "Left at the Claude Code default (asks before acting)." -ForegroundColor Green
    Write-Host "Set ClaudeSkipPermissions = `$true in this machine's file to change that." -ForegroundColor DarkGray
}

# ---- look and housekeeping ---------------------------------------------------
# Re-running sets the same values again, like every preference in this repo.
Write-Host "`n--- theme and history ---" -ForegroundColor Yellow
$settings["theme"] = "dark"
$settings["cleanupPeriodDays"] = 365
Write-Host "Dark theme; session history kept 365 days." -ForegroundColor Green

# ---- following a session remotely --------------------------------------------
Write-Host "`n--- remote follow ---" -ForegroundColor Yellow
$settings["agentPushNotifEnabled"] = $true
$settings["inputNeededNotifEnabled"] = $true
if ($remote) {
    # Every interactive `claude` here also announces itself to claude.ai/code,
    # so a session someone started at the keyboard can be picked up from the
    # phone. Same key as dev-1. The always-on host is the Scheduled Task below.
    $settings["remoteControlAtStartup"] = $true
}
elseif ($settings.Contains("remoteControlAtStartup")) {
    $settings.Remove("remoteControlAtStartup")
}
Write-Host "Push notifications on (needed to follow a session from the phone)." -ForegroundColor Green

# ---- save --------------------------------------------------------------------
try {
    [PSCustomObject]$settings | ConvertTo-Json -Depth 20 |
        Set-Content -Path $settingsPath -Encoding utf8 -ErrorAction Stop
    Write-Host "`nWrote $settingsPath" -ForegroundColor Green
}
catch {
    Write-Host "Could not write $settingsPath : $($_.Exception.Message)" -ForegroundColor Red
    Add-ManualStep "Claude Code settings could not be written; tell Claude the red line it printed."
    return
}

# ---- Remote Control at sign-in -----------------------------------------------
Write-Host "`n--- remote control ---" -ForegroundColor Yellow
if (-not $remote) {
    if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
        Write-Host "Removed scheduled task '$taskName' (ClaudeRemoteControl is off for this machine)." -ForegroundColor Green
    }
    else {
        Write-Host "Off for this machine (ClaudeRemoteControl = `$false); no task registered." -ForegroundColor Green
    }
}
else {
    # 1. The folder the host serves. Not a git repo and never will be: it is
    #    a landing spot, not a project. Sessions started from claude.ai/code
    #    open here, then cd or clone wherever the work is.
    New-Item -ItemType Directory -Path $remoteDir -Force | Out-Null
    @"
This folder is served by the "$taskName" scheduled task, which keeps
'claude remote-control' running so this machine appears in claude.ai/code and
the Claude phone app as "$remoteName".

Set up by proxy-laptop-setup (windows/modules/claude.ps1). Nothing in here is
precious. Start-ClaudeRemoteControl.ps1 is the launcher the task runs;
remote-control.log is its most recent output. To turn this off: set
ClaudeRemoteControl = `$false in this machine's file and re-run setup -Only claude.
"@ | Set-Content -Path (Join-Path $remoteDir "README.txt") -Encoding utf8

    # 2. Pre-trust the folder in ~\.claude.json. Only touched when the entry is
    #    missing: this file is large and Claude Code rewrites it constantly, so
    #    the less we rewrite it, the better.
    $trusted = $false
    $cfg = Read-ClaudeJsonFile $globalConfigPath
    if ($null -eq $cfg) {
        Add-ManualStep "~\.claude.json could not be parsed, so $remoteDir was not pre-trusted. Open PowerShell in $remoteDir, run 'claude' once and answer yes to the trust question; the Remote Control task starts working within 15 minutes."
    }
    else {
        $projects = if ($cfg.Contains("projects") -and $cfg["projects"]) { $cfg["projects"] } else { [PSCustomObject]@{} }
        $entry = $projects.PSObject.Properties[$remoteDir]
        if ($entry -and $entry.Value.PSObject.Properties["hasTrustDialogAccepted"] -and [bool]$entry.Value.hasTrustDialogAccepted) {
            $trusted = $true
            Write-Host "$remoteDir is already trusted by Claude Code." -ForegroundColor Green
        }
        else {
            $project = if ($entry) { $entry.Value } else { [PSCustomObject]@{ allowedTools = @() } }
            $project | Add-Member -NotePropertyName "hasTrustDialogAccepted" -NotePropertyValue $true -Force
            $projects | Add-Member -NotePropertyName $remoteDir -NotePropertyValue $project -Force
            $cfg["projects"] = $projects
            try {
                [PSCustomObject]$cfg | ConvertTo-Json -Depth 100 |
                    Set-Content -Path $globalConfigPath -Encoding utf8 -ErrorAction Stop
                $trusted = $true
                Write-Host "Pre-trusted $remoteDir in ~\.claude.json (so the task never waits on the trust question)." -ForegroundColor Green
            }
            catch {
                Write-Host "Could not write ${globalConfigPath}: $($_.Exception.Message)" -ForegroundColor Red
                Add-ManualStep "Open PowerShell in $remoteDir, run 'claude' once and answer yes to the trust question; the Remote Control task starts working within 15 minutes."
            }
        }
    }

    # 3. The launcher. A separate file rather than a long task command line so
    #    it can find claude.exe at RUN time (winget's link folder is not on the
    #    PATH a scheduled task sees) and leave a log behind when it fails.
    $rcExtra = if ($skip) { ", '--permission-mode', 'bypassPermissions'" } else { "" }
    $launcher = @'
# Start-ClaudeRemoteControl.ps1 -- written by proxy-laptop-setup (claude.ps1).
# Run by the scheduled task "__TASK__" at logon and every 15 minutes; the
# task ignores a new start while this one is still running.
$ErrorActionPreference = "Continue"
Set-Location $PSScriptRoot
$log = Join-Path $PSScriptRoot "remote-control.log"
$env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
            [Environment]::GetEnvironmentVariable("Path", "User") + ";" + $env:Path
$claude = $null
$cmd = Get-Command claude.exe, claude -ErrorAction SilentlyContinue | Select-Object -First 1
if ($cmd) { $claude = $cmd.Source }
foreach ($candidate in @(
        (Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links\claude.exe"),
        (Join-Path $env:USERPROFILE ".local\bin\claude.exe"),
        (Join-Path $env:LOCALAPPDATA "Programs\claude-code\claude.exe"))) {
    if (-not $claude -and (Test-Path $candidate)) { $claude = $candidate }
}
$rcArgs = @('remote-control', '--spawn', 'same-dir', '--name', '__NAME__'__EXTRA__)
"$(Get-Date -Format s) starting: $claude $($rcArgs -join ' ')" | Set-Content -Path $log -Encoding utf8
if (-not $claude) {
    "claude.exe not found. Install Claude Code (winget install Anthropic.ClaudeCode) or re-run setup." | Add-Content -Path $log
    exit 1
}
& $claude @rcArgs *>> $log
"$(Get-Date -Format s) exited with code $LASTEXITCODE" | Add-Content -Path $log
exit $LASTEXITCODE
'@
    $launcher.Replace('__TASK__', $taskName).Replace('__NAME__', $remoteName.Replace("'", "''")).Replace('__EXTRA__', $rcExtra) |
        Set-Content -Path $launcherPath -Encoding utf8

    # 4. The task. Per user, interactive logon type: Remote Control serves
    #    THIS person's Claude account, so it runs as them, in their session,
    #    and only while they are signed in. IgnoreNew + no time limit keep one
    #    long-lived host; the 15-minute repeat is only a retry for after a
    #    crash, a sign-out or a network drop.
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' `
        -Argument ('-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}"' -f $launcherPath)
    $triggers = @(
        (New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME")
        (New-ScheduledTaskTrigger -Once -At (Get-Date).Date `
            -RepetitionInterval (New-TimeSpan -Minutes 15) -RepetitionDuration (New-TimeSpan -Days 3650))
    )
    $taskSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero)
    $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
    try {
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $triggers -Settings $taskSettings `
            -Principal $principal -Description "Keeps 'claude remote-control' running so this machine shows in claude.ai/code as '$remoteName'. From proxy-laptop-setup." `
            -Force -ErrorAction Stop | Out-Null
        Write-Host "Registered scheduled task '$taskName' (at logon, retried every 15 min) as $env:USERNAME." -ForegroundColor Green
        Write-Host "Session name in claude.ai/code: $remoteName" -ForegroundColor Green
        if ($skip) { Write-Host "Sessions it spawns run in bypassPermissions mode." -ForegroundColor DarkYellow }
        # Start it now so the acceptance check does not wait for the next sign-in.
        Start-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    }
    catch {
        Write-Host "Could not register '$taskName': $($_.Exception.Message)" -ForegroundColor Red
        Add-ManualStep "The Remote Control scheduled task could not be registered; tell Claude the red line it printed."
    }

    Add-ManualStep "Claude Code: within a minute this machine should appear in claude.ai/code (and the phone app) as '$remoteName'. If it does not: open PowerShell in $remoteDir, run 'claude' once and sign in (the task cannot sign in for you), then wait for the next 15-minute retry or run the task from Task Scheduler. Last output: $remoteDir\remote-control.log"
    if (-not $trusted) {
        Add-ManualStep "The Remote Control task will wait on Claude Code's trust question until $remoteDir has been opened with 'claude' once by hand (see the step above)."
    }
}

if ($skip) {
    $machineFile = if ($MachineConfig.ComputerName) { "windows\machines\$($MachineConfig.ComputerName.ToLower()).ps1" } else { "this machine's file in windows\machines\" }
    Add-ManualStep "Claude Code here no longer asks before running commands or editing files (bypassPermissions). To undo: set ClaudeSkipPermissions = `$false in $machineFile and re-run setup -Only claude, or just delete permissions.defaultMode from ~\.claude\settings.json."
}

# windows/modules/claude.ps1 -- how Claude Code behaves on this machine.
#
# base.ps1 installs Anthropic.ClaudeCode; this piece configures it. No apps are
# installed here, so like preferences.ps1 it is safe to run alone on an OLD
# machine:
#   ... setup.ps1 ... -Machine existing -Only claude
#
# Two things:
#
#   1. permissions.defaultMode = "bypassPermissions" when the machine file sets
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
#   2. Push notifications, so a session here can be followed from claude.ai/code
#      or the phone app.
#
# Remote Control itself is PER-SESSION and deliberately has no settings.json
# key -- linking a session to the account is a decision a person makes each
# time, not a machine default. It is the toolbar switch in the Claude desktop
# app, so it lands in the manual steps below.
#
# Needs from setup.ps1: $MachineConfig (machine file), common.ps1 helpers.

Write-Section "claude: Claude Code configuration"

$claudeDir = Join-Path $env:USERPROFILE ".claude"
$settingsPath = Join-Path $claudeDir "settings.json"
$skip = [bool]$MachineConfig.ClaudeSkipPermissions

# ---- read what is already there ----------------------------------------------
# Merge rather than overwrite: this file also holds anything the person (or
# Claude itself) has set from inside the app, and a re-run must not drop it.
$settings = [ordered]@{}
if (Test-Path $settingsPath) {
    $backup = "$settingsPath.$(Get-Date -Format 'yyyyMMdd-HHmmss').bak"
    try {
        Copy-Item $settingsPath $backup -Force
        $raw = Get-Content $settingsPath -Raw
        if ($raw.Trim()) {
            ($raw | ConvertFrom-Json).PSObject.Properties |
                ForEach-Object { $settings[$_.Name] = $_.Value }
        }
        Write-Host "Existing settings.json backed up to $(Split-Path $backup -Leaf)." -ForegroundColor DarkGray
    }
    catch {
        # A settings.json we cannot parse is not ours to silently replace.
        Write-Host "Could not read $settingsPath ($($_.Exception.Message))." -ForegroundColor Red
        Add-ManualStep "~\.claude\settings.json could not be parsed, so Claude Code was left alone. Fix or delete that file, then re-run setup -Only claude."
        return
    }
}
else {
    New-Item -ItemType Directory -Path $claudeDir -Force | Out-Null
}

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

    Write-Host "permissions.defaultMode = bypassPermissions" -ForegroundColor Green
    Write-Host "Claude Code will NOT ask before running commands or editing files here." -ForegroundColor DarkYellow
}
else {
    Write-Host "Left at the Claude Code default (asks before acting)." -ForegroundColor Green
    Write-Host "Set ClaudeSkipPermissions = `$true in this machine's file to change that." -ForegroundColor DarkGray
}

# ---- following a session remotely --------------------------------------------
Write-Host "`n--- remote follow ---" -ForegroundColor Yellow
$settings["agentPushNotifEnabled"] = $true
$settings["inputNeededNotifEnabled"] = $true
Write-Host "Push notifications on (needed to follow a session from the phone)." -ForegroundColor Green

# ---- save --------------------------------------------------------------------
try {
    [PSCustomObject]$settings | ConvertTo-Json -Depth 10 |
        Set-Content -Path $settingsPath -Encoding utf8 -ErrorAction Stop
    Write-Host "`nWrote $settingsPath" -ForegroundColor Green
}
catch {
    Write-Host "Could not write $settingsPath : $($_.Exception.Message)" -ForegroundColor Red
    Add-ManualStep "Claude Code settings could not be written; tell Claude the red line it printed."
    return
}

Add-ManualStep "Claude Code: turn on Remote Control for a session with the toolbar switch in the Claude desktop app (it is per-session, not a machine setting), then follow it from claude.ai/code or the phone."
if ($skip) {
    $machineFile = if ($MachineConfig.ComputerName) { "windows\machines\$($MachineConfig.ComputerName.ToLower()).ps1" } else { "this machine's file in windows\machines\" }
    Add-ManualStep "Claude Code here no longer asks before running commands or editing files (bypassPermissions). To undo: set ClaudeSkipPermissions = `$false in $machineFile and re-run setup -Only claude, or just delete permissions.defaultMode from ~\.claude\settings.json."
}

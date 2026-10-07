# windows/machines/proxy.ps1 -- the proxy laptop: remote-control hub for every
# other machine, plus the controls field tools.
#
# This is the default when setup.ps1 is run with no -Machine, so the original
# one-liner keeps doing what it always did.
#
# IdentityTag: edit for a second property/site, e.g. "remote workstation - Ivy House".
# ComputerName unset on purpose: a re-run here never renames the laptop.
$MachineConfig = @{
    ComputerName   = $null
    IdentityTag    = "remote workstation"
    WallpaperTheme = "workstation"
    WallpaperLabel = "PROXY"
    # Left off on purpose: this is the machine you drive the others FROM, so a
    # person is normally sitting at it and can answer a prompt. Set $true if you
    # start running unattended sessions here too.
    ClaudeSkipPermissions = $false
    Modules        = @("base", "preferences", "claude", "controls", "remote-hub")
}

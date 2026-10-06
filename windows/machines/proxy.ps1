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
    Modules        = @("base", "preferences", "controls", "remote-hub")
}

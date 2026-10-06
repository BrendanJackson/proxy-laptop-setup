# windows/machines/fxwb-1.ps1 -- FX Workbench field laptop (Ithaca Solutions).
# Shared by Brendan and Allen. Windows 11. Set up 2026-10 (TSK-203).
#
# Driven remotely from the proxy laptop (mRemoteNG over Tailscale), so it is
# an rdp-host, not a remote-hub.
$MachineConfig = @{
    ComputerName       = "FXWB-1"
    IdentityTag        = "FX Workbench field laptop"
    WallpaperTheme     = "fx"
    WallpaperLabel     = "FXWB-1"
    FxWorkbenchVersion = "14.15.1"
    # AcSleepMinutes unset = the 5 h default. Set 0 if it must always be reachable.
    Modules            = @("base", "preferences", "controls", "rdp-host", "fx-workbench")
}

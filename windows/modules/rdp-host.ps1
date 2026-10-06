# windows/modules/rdp-host.ps1 -- a machine OTHER machines drive (by Remote
# Desktop over Tailscale). Brendan, 2026-10-06: "mRemoteNG the full set up so
# that the proxy laptop can drive this one."
#
# Turns on Remote Desktop, opens it in the Windows firewall, and stops the
# machine sleeping while plugged in -- a sleeping laptop is an unreachable one.
# Network Level Authentication stays on (Windows default).

Write-Section "rdp-host: reachable by Remote Desktop"

if ($editionId -and $editionId -notmatch 'Professional|Enterprise|Education') {
    Write-Host "Skipped -- Windows $editionId cannot accept Remote Desktop connections. Upgrade to Pro (see the edition warning above), then re-run setup." -ForegroundColor DarkYellow
}
else {
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections -Value 0
    # "@FirewallAPI.dll,-28752" is the Remote Desktop rule group by its
    # language-independent name (the display name is localized).
    Enable-NetFirewallRule -Group "@FirewallAPI.dll,-28752"
    Write-Host "Remote Desktop on, firewall rule enabled." -ForegroundColor Green
}

# Plugged in: never sleep, never hibernate, closing the lid does nothing.
# On battery the Windows defaults are left alone, so it still sleeps in a bag.
powercfg /change standby-timeout-ac 0
powercfg /change hibernate-timeout-ac 0
powercfg /setacvalueindex SCHEME_CURRENT SUB_BUTTONS LIDACTION 0
powercfg /setactive SCHEME_CURRENT
Write-Host "On AC power: no sleep, no hibernate, lid close does nothing." -ForegroundColor Green

Add-ManualStep "Remote Desktop sign-in uses the Windows ACCOUNT PASSWORD, not the PIN. If you sign in with a Microsoft account, use that account's password in mRemoteNG."
Add-ManualStep "On the proxy laptop, re-run Install-MRemoteNG.ps1 (it lists $($MachineConfig.ComputerName) now) and connect once to confirm."

# windows/modules/rdp-host.ps1 -- a machine OTHER machines drive (by Remote
# Desktop over Tailscale). Brendan, 2026-10-06: "mRemoteNG the full set up so
# that the proxy laptop can drive this one."
#
# Turns on Remote Desktop, opens it in the Windows firewall, and makes closing
# the lid do nothing while plugged in.
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

# Sleep timing comes from preferences.ps1 (5 h idle on AC by default, per
# Brendan 2026-10-06). A sleeping machine can't be reached, so a machine that
# must always answer sets AcSleepMinutes = 0 in its machine file.
# Plugged in, closing the lid does nothing, so it can sit closed on a desk and
# still be driven remotely. On battery the lid still sleeps it.
powercfg /setacvalueindex SCHEME_CURRENT SUB_BUTTONS LIDACTION 0
powercfg /setactive SCHEME_CURRENT
Write-Host "Plugged in: closing the lid does nothing." -ForegroundColor Green

Add-ManualStep "Remote Desktop sign-in uses the Windows ACCOUNT PASSWORD, not the PIN. If you sign in with a Microsoft account, use that account's password in mRemoteNG."
Add-ManualStep "On the proxy laptop, re-run Install-MRemoteNG.ps1 (it lists $($MachineConfig.ComputerName) now) and connect once to confirm."

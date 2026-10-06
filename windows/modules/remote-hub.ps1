# windows/modules/remote-hub.ps1 -- the machine you drive the others FROM.
# mRemoteNG plus the ready-made "Homelab" connection list (TSK-173). Today only
# the proxy laptop has this role.
#
# The logic lives in the root Install-MRemoteNG.ps1 so it can also run alone
# on any box by its own one-liner; this module just calls it. Local file when
# run from a clone; fetched from the repo when run via irm | iex.

Write-Section "remote-hub: mRemoteNG + connection list"

Install-WingetApps -Ids @("mRemoteNG.mRemoteNG")

try {
    $mrngBlock = [scriptblock]::Create((Get-RepoScript "Install-MRemoteNG.ps1"))
    & $mrngBlock -SkipInstall
}
catch {
    Write-Host "Could not run Install-MRemoteNG.ps1 ($($_.Exception.Message)). Run it on its own later; see README 'mRemoteNG connection list'." -ForegroundColor DarkYellow
}

Add-ManualStep "Open mRemoteNG: if it already had a connections file, File > Import > From File > %APPDATA%\mRemoteNG\homelab-connections.xml. Set a master password before saving any credential."

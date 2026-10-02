# Find-JCILaptop.ps1 -- resolve the JCI laptop's current IP on whatever local
# network this machine is on right now, by ARP, since it deliberately has no
# Tailscale (MDM-managed, kept off it -- see Install-MRemoteNG.ps1's
# Tailnet = $false row) and its IP changes per site/DHCP. Run in PowerShell,
# no admin needed:
#
#   Set-ExecutionPolicy Bypass -Scope Process -Force; iex (irm https://raw.githubusercontent.com/BrendanJackson/proxy-laptop-setup/tsk-173/mremoteng-connections/Find-JCILaptop.ps1)
#
# What it does (TSK-173, 2026-10-01):
#   1. Finds this machine's local (non-Tailscale, non-APIPA) IPv4 subnets.
#   2. Async-pings every host address on each subnet -- not for a reply, just
#      to make this machine ARP for it -- then reads back the ARP table
#      (Get-NetNeighbor).
#   3. Matches $JciMacAddress against the ARP table. If found, prints the
#      current IP and updates the "JCI laptop (RDP)" connection's Hostname in
#      whichever mRemoteNG connections file has it (confCons.xml or the
#      homelab-connections.xml side file -- see Install-MRemoteNG.ps1), so the
#      existing saved connection just works without retyping anything in the
#      mRemoteNG UI.
#
# Same trick controls-field-tools' IP Speed Dial already uses for JCI engine
# discovery (ping+ARP), aimed at the laptop itself instead of a BAS engine.
#
# RUN WITH mRemoteNG CLOSED. It writes its own copy of confCons.xml on exit
# and would overwrite the Hostname update made here.

[CmdletBinding()]
param()

$ErrorActionPreference = "Continue"

# ---- the one thing to edit if this laptop's active NIC ever changes --------
$JciMacAddress = "80-E4-BA-DD-6B-20"   # JCI laptop Wi-Fi adapter, recorded 2026-10-01

function Get-HostAddressesInSubnet {
    param([string]$IPAddress, [int]$PrefixLength)
    if ($PrefixLength -ge 31) { return @() }   # no usable host range (point-to-point/host route)
    $ip = [System.Net.IPAddress]::Parse($IPAddress)
    $ipBytes = $ip.GetAddressBytes()
    [Array]::Reverse($ipBytes)
    $ipInt = [System.BitConverter]::ToUInt32($ipBytes, 0)
    $maskInt = [uint32]([uint32]::MaxValue -shl (32 - $PrefixLength))
    $networkInt = $ipInt -band $maskInt
    $hostCount = [int][math]::Pow(2, 32 - $PrefixLength) - 2   # drop network + broadcast
    if ($hostCount -gt 1022) { $hostCount = 1022 }               # safety cap
    1..$hostCount | ForEach-Object {
        $hostInt = $networkInt + $_
        $bytes = [System.BitConverter]::GetBytes([uint32]$hostInt)
        [Array]::Reverse($bytes)
        ([System.Net.IPAddress]$bytes).ToString()
    }
}

Write-Host "--- local subnets on this machine ---" -ForegroundColor Yellow
$subnets = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.IPAddress -notlike "169.254.*" -and $_.IPAddress -ne "127.0.0.1" -and $_.InterfaceAlias -notlike "Tailscale*" }
$subnets | ForEach-Object { Write-Host "  $($_.InterfaceAlias): $($_.IPAddress)/$($_.PrefixLength)" }

if (-not $subnets) {
    Write-Host "No local subnets found (Tailscale/loopback/APIPA excluded). Nothing to scan." -ForegroundColor Red
    return
}

Write-Host "`n--- ARP sweep (async ping, no admin needed) ---" -ForegroundColor Yellow
foreach ($s in $subnets) {
    $targets = Get-HostAddressesInSubnet -IPAddress $s.IPAddress -PrefixLength $s.PrefixLength
    if (-not $targets) { continue }
    Write-Host "Sweeping $($s.IPAddress)/$($s.PrefixLength) ($($targets.Count) addresses)..." -ForegroundColor Cyan
    $pings = foreach ($t in $targets) {
        $p = New-Object System.Net.NetworkInformation.Ping
        [pscustomobject]@{ Ping = $p; Task = $p.SendPingAsync($t, 300) }
    }
    [System.Threading.Tasks.Task]::WaitAll(($pings | ForEach-Object { $_.Task }), 20000) | Out-Null
    $pings | ForEach-Object { $_.Ping.Dispose() }
}

Write-Host "`n--- checking ARP table for $JciMacAddress ---" -ForegroundColor Yellow
$normalizedMac = ($JciMacAddress -replace '[:-]', '').ToUpper()
$match = Get-NetNeighbor -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { ($_.LinkLayerAddress -replace '[:-]', '').ToUpper() -eq $normalizedMac -and $_.State -ne "Unreachable" } |
    Select-Object -First 1

if (-not $match) {
    Write-Host "JCI laptop (MAC $JciMacAddress) not found on any scanned subnet. Confirm it's on Wi-Fi, on the same network as this machine, then re-run." -ForegroundColor Red
    return
}

$jciIp = $match.IPAddress
Write-Host "Found: $jciIp" -ForegroundColor Green

Write-Host "`n--- updating mRemoteNG connections file ---" -ForegroundColor Yellow
$confDir = Join-Path $env:APPDATA "mRemoteNG"
$candidates = @((Join-Path $confDir "confCons.xml"), (Join-Path $confDir "homelab-connections.xml"))
$updated = $false
foreach ($file in $candidates) {
    if (-not (Test-Path $file)) { continue }
    [xml]$doc = Get-Content $file -Raw
    $node = $doc.SelectSingleNode("//Node[@Name='JCI laptop (RDP)']")
    if ($node) {
        $old = $node.Hostname
        $node.Hostname = $jciIp
        $doc.Save($file)
        Write-Host "$file : JCI laptop (RDP) Hostname $old -> $jciIp" -ForegroundColor Green
        $updated = $true
    }
}
if (-not $updated) {
    Write-Host "No 'JCI laptop (RDP)' entry found in confCons.xml or homelab-connections.xml. Run Install-MRemoteNG.ps1 (or import homelab-connections.xml) first, then re-run this." -ForegroundColor DarkYellow
}
else {
    Write-Host "`nDone. Open mRemoteNG (if it was open, restart it first -- it overwrites confCons.xml on exit) and connect to 'JCI laptop (RDP)'." -ForegroundColor Cyan
}

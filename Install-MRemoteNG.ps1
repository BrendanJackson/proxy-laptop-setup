# Install-MRemoteNG.ps1 -- mRemoteNG plus a ready-made connection list for
# every machine on the tailnet, on any Windows box (proxy laptop, the Windows
# desktop, a future one). Run in PowerShell as Administrator:
#
#   Set-ExecutionPolicy Bypass -Scope Process -Force; iex (irm https://raw.githubusercontent.com/BrendanJackson/proxy-laptop-setup/master/Install-MRemoteNG.ps1)
#
# setup.ps1 runs this too, so the proxy laptop gets it on a normal setup.
#
# What it does (TSK-173, 2026-10-01):
#   1. winget-installs mRemoteNG (no-op if already present).
#   2. Writes a connections file holding a "Homelab" folder with an RDP and/or
#      SSH entry for every machine in $Machines below, addressed by Tailscale
#      MagicDNS name. No passwords are written -- mRemoteNG prompts the first
#      time and can save them once a master password is set on the file.
#   3. Never overwrites an existing confCons.xml. If one is there (it is, on
#      the proxy laptop: mRemoteNG has been used by hand since 09/25), the list
#      is written beside it as homelab-connections.xml and the import step is
#      printed. -Replace overwrites after taking a dated backup.
#   4. Probes every host:port in the list and prints open/closed, so "ready to
#      connect" is observed, not assumed.
#
# To add a machine or a second property: add a row to $Machines. Nothing else
# changes. $TailnetSuffix is the one per-tailnet value (mirrors $IdentityTag in
# setup.ps1 as the single "which site is this" knob).
#
# File format: mRemoteNG 1.76.20 confCons.xml, ConfVersion 2.6. The root
# "Protected" attribute is the string "ThisIsNotProtected" AES-GCM-encrypted
# under mRemoteNG's default file password (mR3m), the state a fresh unprotected
# file is in. Precomputed on dev-1 with the same KDF/cipher the app uses
# (PBKDF2-SHA1 x1000, 256-bit key, 16-byte salt + 16-byte nonce + ciphertext +
# tag, base64) because Windows PowerShell 5.1 has no AES-GCM. The salt/nonce are
# random, so any such value is valid; this one is fixed so the file is
# reproducible.
#
# RUN WITH mRemoteNG CLOSED. It writes its own copy of confCons.xml on exit and
# would overwrite a file written underneath it.

[CmdletBinding()]
param(
    [switch]$Replace,      # overwrite an existing confCons.xml (backup taken first)
    [switch]$SkipInstall,  # only write the connections file + probe
    [switch]$SkipProbe     # skip the host:port reachability table
)

$ErrorActionPreference = "Continue"

# ---- the one per-site knob --------------------------------------------------
$TailnetSuffix = "tail018f42.ts.net"

# ---- every machine, one row each --------------------------------------------
# Host is the Tailscale machine name; the FQDN is Host + $TailnetSuffix so it
# resolves whether or not the MagicDNS search domain is set on this box.
# Protocols: RDP (3389) and/or SSH (22). User is pre-filled where it is known
# and fixed (the Linux boxes); blank means mRemoteNG asks.
$Machines = @(
    @{ Name = "dev-1";           Host = "dev-1";           Descr = "Ubuntu automation box (XFCE over xrdp; Claude Code sessions live here)"; Protocols = @("RDP", "SSH"); User = "master" },
    @{ Name = "homeassistant-1"; Host = "homeassistant-1"; Descr = "Ubuntu Home Assistant box (OptiPlex #1, xrdp)";                           Protocols = @("RDP", "SSH"); User = "master" },
    @{ Name = "Windows desktop"; Host = "desktop-4539ppg"; Descr = "Windows desktop, 8TB backup target. Enable Remote Desktop on it first (runbook section 5)."; Protocols = @("RDP", "SSH"); User = "" },
    @{ Name = "JCI laptop";      Host = "ma-5p23zb4";      Descr = "Corporate Metasys laptop, MDM-managed. Ask IT before relying on this; Tailscale may not be allowed."; Protocols = @("RDP"); User = "" },
    @{ Name = "Proxy laptop";    Host = "proxy";           Descr = "This proxy laptop itself, for use from the desktop";                       Protocols = @("RDP"); User = "" }
)
# Deliberately not listed: greystar-m16-bench. It is a customer's Metasys
# server (Greystar, cut over 2026-09-30), not a workstation.

# ---- 1. install ----------------------------------------------------------------
if (-not $SkipInstall) {
    Write-Host "`n--- mRemoteNG.mRemoteNG ---" -ForegroundColor Yellow
    winget install --id mRemoteNG.mRemoteNG --silent --accept-package-agreements --accept-source-agreements
}

# ---- 2. build the connections file ---------------------------------------------
# Precomputed on dev-1 2026-10-01: AES-GCM("ThisIsNotProtected", key=PBKDF2-SHA1("mR3m", salt, 1000, 32))
$ProtectedValue = "9Nu5PEq1e/EjoHWpJpwM94GtWlrTUdB7LNB49PUnWcDCdEtnqU5gqo9b/A4VnmV0ClQsXwKMdieeEkGOm3JCTIAA"

function Esc([string]$s) { [System.Security.SecurityElement]::Escape($s) }

function New-NodeAttributes {
    param([string]$Name, [string]$Type, [string]$Descr, [string]$Hostname, [string]$Protocol, [int]$Port, [string]$Username)
    # EVERY attribute mRemoteNG 1.76.20 writes is set here, with the app's own
    # defaults. The importer reads each one as xmlnode.Attributes["X"].Value with
    # no null check, so a missing attribute is a NullReferenceException and the
    # dialog "An error occurred while importing the file" -- observed on the
    # proxy laptop 2026-10-01 with a file that carried only the useful ones.
    $a = [ordered]@{
        Name = $Name; Type = $Type; Expanded = ($Type -eq "Container").ToString().ToLowerInvariant()
        Descr = $Descr; Icon = "mRemoteNG"; Panel = "General"; Id = [guid]::NewGuid().ToString()
        Username = $Username; Domain = ""; Password = ""
        Hostname = $Hostname; Protocol = $Protocol; PuttySession = "Default Settings"; Port = $Port
        ConnectToConsole = "false"; UseCredSsp = "true"; RenderingEngine = "IE"
        ICAEncryptionStrength = "EncrBasic"; RDPAuthenticationLevel = "NoAuth"
        RDPMinutesToIdleTimeout = "0"; RDPAlertIdleTimeout = "false"; LoadBalanceInfo = ""
        Colors = "Colors16Bit"; Resolution = "FitToWindow"; AutomaticResize = "true"
        DisplayWallpaper = "false"; DisplayThemes = "false"; EnableFontSmoothing = "false"
        EnableDesktopComposition = "false"; CacheBitmaps = "false"
        RedirectDiskDrives = "false"; RedirectPorts = "false"; RedirectPrinters = "false"
        RedirectSmartCards = "false"; RedirectSound = "DoNotPlay"; SoundQuality = "Dynamic"; RedirectKeys = "false"
        Connected = "false"; PreExtApp = ""; PostExtApp = ""; MacAddress = ""; UserField = ""; ExtApp = ""
        VNCCompression = "CompNone"; VNCEncoding = "EncHextile"; VNCAuthMode = "AuthVNC"
        VNCProxyType = "ProxyNone"; VNCProxyIP = ""; VNCProxyPort = "0"; VNCProxyUsername = ""; VNCProxyPassword = ""
        VNCColors = "ColNormal"; VNCSmartSizeMode = "SmartSAspect"; VNCViewOnly = "false"
        RDGatewayUsageMethod = "Never"; RDGatewayHostname = ""; RDGatewayUseConnectionCredentials = "Yes"
        RDGatewayUsername = ""; RDGatewayPassword = ""; RDGatewayDomain = ""
    }
    foreach ($k in @("CacheBitmaps","Colors","Description","DisplayThemes","DisplayWallpaper","EnableFontSmoothing",
        "EnableDesktopComposition","Domain","Icon","Panel","Password","Port","Protocol","PuttySession",
        "RedirectDiskDrives","RedirectKeys","RedirectPorts","RedirectPrinters","RedirectSmartCards","RedirectSound",
        "SoundQuality","Resolution","AutomaticResize","UseConsoleSession","UseCredSsp","RenderingEngine","Username",
        "ICAEncryptionStrength","RDPAuthenticationLevel","RDPMinutesToIdleTimeout","RDPAlertIdleTimeout","LoadBalanceInfo",
        "PreExtApp","PostExtApp","MacAddress","UserField","ExtApp","VNCCompression","VNCEncoding","VNCAuthMode",
        "VNCProxyType","VNCProxyIP","VNCProxyPort","VNCProxyUsername","VNCProxyPassword","VNCColors","VNCSmartSizeMode",
        "VNCViewOnly","RDGatewayUsageMethod","RDGatewayHostname","RDGatewayUseConnectionCredentials","RDGatewayUsername",
        "RDGatewayPassword","RDGatewayDomain")) {
        $a["Inherit$k"] = "false"
    }
    ($a.GetEnumerator() | ForEach-Object { '{0}="{1}"' -f $_.Key, (Esc ([string]$_.Value)) }) -join " "
}

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('<?xml version="1.0" encoding="utf-8"?>')
[void]$sb.AppendLine(('<mrng:Connections xmlns:mrng="http://mremoteng.org" Name="Connections" Export="false" EncryptionEngine="AES" BlockCipherMode="GCM" KdfIterations="1000" FullFileEncryption="false" Protected="{0}" ConfVersion="2.6">' -f $ProtectedValue))
[void]$sb.AppendLine('  <Node ' + (New-NodeAttributes -Name "Homelab" -Type "Container" -Descr ("Every machine on " + $TailnetSuffix + ", written by proxy-laptop-setup/Install-MRemoteNG.ps1") -Hostname "" -Protocol "RDP" -Port 3389 -Username "") + '>')
$probeList = @()
foreach ($m in $Machines) {
    $fqdn = "$($m.Host).$TailnetSuffix"
    foreach ($proto in $m.Protocols) {
        if ($proto -eq "RDP") { $p = "RDP";  $port = 3389 } else { $p = "SSH2"; $port = 22 }
        $name = "{0} ({1})" -f $m.Name, $proto
        [void]$sb.AppendLine('    <Node ' + (New-NodeAttributes -Name $name -Type "Connection" -Descr $m.Descr -Hostname $fqdn -Protocol $p -Port $port -Username $m.User) + ' />')
        $probeList += [pscustomobject]@{ Connection = $name; Host = $fqdn; Port = $port }
    }
}
[void]$sb.AppendLine('  </Node>')
[void]$sb.AppendLine('</mrng:Connections>')
$xml = $sb.ToString()

$confDir  = Join-Path $env:APPDATA "mRemoteNG"
$confCons = Join-Path $confDir "confCons.xml"
$sideFile = Join-Path $confDir "homelab-connections.xml"
New-Item -ItemType Directory -Path $confDir -Force | Out-Null
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

Write-Host "`n--- connections file ---" -ForegroundColor Yellow
if ((Test-Path $confCons) -and -not $Replace) {
    [System.IO.File]::WriteAllText($sideFile, $xml, $utf8NoBom)
    Write-Host "An existing confCons.xml was left alone (your saved connections are in it)." -ForegroundColor Cyan
    Write-Host "The Homelab list was written to: $sideFile" -ForegroundColor Green
    Write-Host "In mRemoteNG: File > Import > From File... > pick that file. The Homelab folder appears in your tree." -ForegroundColor Green
    Write-Host "Or re-run with -Replace to make it the main file (a dated backup of the old one is taken)." -ForegroundColor DarkYellow
}
else {
    if (Test-Path $confCons) {
        $bak = "$confCons.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
        Copy-Item $confCons $bak
        Write-Host "Backed up the old file to $bak" -ForegroundColor DarkYellow
    }
    [System.IO.File]::WriteAllText($confCons, $xml, $utf8NoBom)
    Write-Host "Wrote $confCons (Homelab folder, $($probeList.Count) connections)." -ForegroundColor Green
}
Write-Host "Passwords are not stored. First connection asks; to save them, set a master password on the file in mRemoteNG first (Tools > Options > Security)." -ForegroundColor Cyan

# ---- 3. probe -------------------------------------------------------------------
if (-not $SkipProbe) {
    Write-Host "`n--- reachability from this machine (read-only TCP probe) ---" -ForegroundColor Yellow
    if (-not (Get-Command tailscale -ErrorAction SilentlyContinue)) {
        Write-Host "tailscale is not on PATH; names below only resolve once Tailscale is installed and signed in." -ForegroundColor DarkYellow
    }
    $rows = foreach ($t in $probeList) {
        $client = New-Object System.Net.Sockets.TcpClient
        try {
            $ar = $client.BeginConnect($t.Host, $t.Port, $null, $null)
            $ok = $ar.AsyncWaitHandle.WaitOne(3000) -and $client.Connected
        } catch { $ok = $false }
        finally { $client.Close() }
        [pscustomobject]@{ Connection = $t.Connection; Target = "$($t.Host):$($t.Port)"; State = $(if ($ok) { "open" } else { "closed / offline" }) }
    }
    $rows | Format-Table -AutoSize | Out-String | Write-Host
    Write-Host "closed on a Windows target usually means Remote Desktop is off or its firewall rule is scoped to the local subnet; fix it on that machine (runbook section 5)." -ForegroundColor DarkYellow
}

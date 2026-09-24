# Proxy Laptop Setup -- one command install
# Run in PowerShell as Administrator: .\setup.ps1
#
# Companion repo/runbook:
#   Notion: "Proxy Laptop Setup -- Remote Access Runbook"
#   GitHub: https://github.com/BrendanJackson/proxy-laptop-setup
#
# What this does:
#   1. Installs every winget-available app in one pass (general remote-access
#      stack + controls field tools' runtime dependencies).
#   2. Clones/updates the controls-field-tools repo (private; needs GitHub auth).
#   3. Prints the manual steps that can't be scripted (sign-ins, vendor-gated
#      software, per-machine config).
#
# Vendor-gated tools this script deliberately does NOT install:
#   Niagara Workbench / Metasys SCT -- licensed installers, not winget packages.
#   See "Controls-specific tools" in the README for how those get added.

$ErrorActionPreference = "Continue"

$apps = @(
    "Tailscale.Tailscale",
    "mRemoteNG.mRemoteNG",
    "Notion.Notion",
    "Microsoft.VisualStudioCode",
    "Git.Git",
    "Bitwarden.Bitwarden",
    "Google.Chrome",
    "WiresharkFoundation.Wireshark",
    "PuTTY.PuTTY",
    "GitHub.cli",             # gh: auths git against the private controls-field-tools repo
    "Python.Python.3.12"      # controls-field-tools/site-audit needs a Python 3 interpreter (stdlib only, no pip)
)

Write-Host "Installing $($apps.Count) apps via winget..." -ForegroundColor Cyan

foreach ($app in $apps) {
    Write-Host "`n--- $app ---" -ForegroundColor Yellow
    winget install --id $app --silent --accept-package-agreements --accept-source-agreements
}

Write-Host "`n--- controls-field-tools ---" -ForegroundColor Yellow
$toolsDir = Join-Path $env:USERPROFILE "controls-field-tools"
$ghOk = Get-Command gh -ErrorAction SilentlyContinue
if (-not $ghOk) {
    Write-Host "gh isn't on PATH yet (fresh install needs a new shell). Re-run setup.ps1 in a new PowerShell window to pick up the clone step." -ForegroundColor DarkYellow
}
elseif (Test-Path $toolsDir) {
    Write-Host "controls-field-tools already present at $toolsDir -- pulling latest." -ForegroundColor Cyan
    git -C $toolsDir pull
}
else {
    $authed = gh auth status 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Not signed into GitHub yet. Run 'gh auth login' (opens a browser for SSO), then re-run setup.ps1 to clone controls-field-tools." -ForegroundColor DarkYellow
    }
    else {
        gh repo clone BrendanJackson/controls-field-tools $toolsDir
    }
}

Write-Host "`nDone with winget batch. Manual steps still required:" -ForegroundColor Green
Write-Host "1. Sign into Tailscale (opens browser SSO)."
Write-Host "2. Sign into Bitwarden, unlock vault."
Write-Host "3. Run 'gh auth login' if the controls-field-tools clone above was skipped, then re-run this script."
Write-Host "4. Confirm controls-specific tools below (Niagara Workbench / Metasys SCT are vendor-gated, not winget-installable)."
Write-Host "5. Set Power Plan to 'never sleep' if this machine will also host RDP inbound."
Write-Host "6. In controls-field-tools\speed-dial: right-click Run-IP-SpeedDial.bat -> Run JCI Elevated (or Run as Administrator if that menu item isn't present on this laptop)."

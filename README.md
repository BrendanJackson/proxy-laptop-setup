# Proxy Laptop Setup

One-command bootstrap for the Windows 11 Pro proxy laptop: single-auth remote
access to the two Windows machines + two Ubuntu/GNOME servers, corporate-laptop
app access without a second license, and the Ithaca Solutions controls field
tools (Metasys/Niagara BAS work).

Full narrative version, with the Wireshark/YABE field-use walkthrough and the
per-machine (Windows/Ubuntu/corporate-laptop) setup steps, lives in Notion:
**"Proxy Laptop Setup — Remote Access Runbook."** This repo exists because that
page's install script had nowhere to be cloned from — that was the one open
item blocking a real one-click install, and this repo closes it.

**This repo is public** (made public 2026-09-25, so the one-liner below works
with zero GitHub auth on a bare machine). It contains only the app list and
setup instructions — no secrets, no customer data. `controls-field-tools`
(the actual field tools this installs) is a separate, private repo and is
unaffected.

## Before you touch the laptop: Windows 11 Pro

This is a **reimage of a used laptop**, not an upgrade — there's no existing
activated OS to upgrade from, so the cheaper Home→Pro $99 key path doesn't
apply. Do it in this order:

1. **Confirm compatibility first.** Run [Microsoft's PC Health Check
   app](https://www.microsoft.com/en-us/windows/windows-11-specifications) on
   the laptop *before* wiping anything, to confirm it actually has TPM 2.0 and
   Secure Boot capability. This is where used/older laptops most often fail —
   five minutes now saves a reimage you can't finish.
2. **Buy the Pro key before you start the reimage** — you said you already
   have one, so this is done. (For reference: [StackSocial](https://www.stacksocial.com/)
   or the [PCWorld Software Store](https://www.pcworld.com/softwarestore) run
   Microsoft-partner flash sales with verified keys; cheaper third-party
   resellers like Kinguin/G2A carry real revocation risk.)
3. **Download the official ISO** from
   [microsoft.com/software-download/windows11](https://www.microsoft.com/software-download/windows11) —
   not a third-party mirror.
4. **Boot the installer, choose "erase everything," full clean install.**
   Don't upgrade in place over the previous owner's account. When the
   installer asks for a product key, **enter the Pro key at that prompt** —
   this makes it install Pro directly instead of Home.
5. If the installer skips key entry and lands on Home anyway: **Settings →
   System → Activation → Change Product Key**, enter the same key. This is
   the fallback path, not the main one.

**The installer skipping the key prompt is common, not a sign something went
wrong.** Depending on the ISO and which options you click through, Windows
Setup often defaults straight to Home without ever asking for a key — it
doesn't reliably prompt just because you have one. There's no dependable way
to know from the installer alone which edition you landed on. Check with
**Settings → System → About → Windows specification → Edition**, or just run
`setup.ps1` — as of 2026-09-25 it checks this automatically at the top of the
run and warns loudly (with the exact remediation steps) if you're still on
Home, so you don't have to catch it by eye.

Once you're at a signed-in Windows desktop (Pro or not — the script will
tell you which), come back here.

## One-click install

Open PowerShell **as Administrator** (right-click the Start button →
"Terminal (Admin)" or "Windows PowerShell (Admin)") and paste this one line:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; iex (irm https://raw.githubusercontent.com/BrendanJackson/proxy-laptop-setup/master/setup.ps1)
```

This is the one-click install — nothing to download, unzip, unblock, or sign
into GitHub first. It works on a completely bare machine, before `git` even
exists, because `iex` runs the script directly from memory rather than as a
file on disk, so none of the local-file restrictions below ever come into
play (and because the repo is public, so `irm` needs no auth token to fetch it).

<details>
<summary>Why not just `git clone` + `.\setup.ps1`? (click to expand)</summary>

That was the original instruction here, and it fails on a fresh Windows
install for two compounding reasons:

1. **Chicken-and-egg.** `git clone` needs `git`, which is one of the things
   `setup.ps1` itself installs — so a bare machine can't run that command yet.
2. **Downloaded files get blocked.** The natural workaround — clicking
   GitHub's green **Code → Download ZIP** button instead — marks the
   extracted `setup.ps1` with a "downloaded from the internet" flag (Windows
   calls this Mark of the Web). Windows' default execution policy refuses to
   run it, and even `Set-ExecutionPolicy RemoteSigned` still refuses it
   because RemoteSigned requires downloaded scripts to be digitally signed.
   You'll see exactly this:
   ```
   File ...\setup.ps1 cannot be loaded because running scripts is disabled on this system.
   ```
   or, after loosening the policy:
   ```
   File ...\setup.ps1 is not digitally signed. You cannot run this script on this system.
   ```

If you do want a local, editable copy (e.g. to change the app list before
running it), that path still works — see "Local copy" below — it just needs
one extra step to clear the download flag.

</details>

### Local copy (optional — if you want to edit the script first)

```powershell
git clone https://github.com/BrendanJackson/proxy-laptop-setup.git
cd proxy-laptop-setup
Unblock-File .\setup.ps1          # clears the "downloaded from the internet" flag
.\setup.ps1                       # run in PowerShell as Administrator
```

If you used GitHub's **Download ZIP** button instead of `git clone`, run
`Unblock-File .\setup.ps1` (or `Get-ChildItem -Recurse | Unblock-File` to
unblock the whole extracted folder) before the last line — a ZIP downloaded
through a browser carries the same Mark-of-the-Web flag as a lone `.ps1`
file.

---

`setup.ps1` installs everything winget can install in one pass, checks
whether Windows is actually on Pro/Enterprise/Education (see below), then
clones `controls-field-tools` (see below). A handful of steps can't be
scripted — they're printed at the end of the run, and repeated here:

1. Sign into Tailscale (browser SSO).
2. Sign into Bitwarden, unlock the vault.
3. Run `gh auth login` if the controls-field-tools clone was skipped (happens
   on the very first run, before `gh` is on PATH — just re-run the script in a
   new PowerShell window).
4. Niagara Workbench / Metasys SCT — vendor-licensed installers, not
   winget-installable. Being handled separately (client-quote route per the
   Notion page); install manually once that's sorted.
5. If this laptop will also accept **inbound** RDP (not just originate
   outbound sessions to the other 4 machines), set its Power Plan to never
   sleep.
6. In `controls-field-tools\speed-dial`, right-click `Run-IP-SpeedDial.bat` →
   **Run JCI Elevated** (or plain "Run as Administrator" — see below, this
   laptop likely won't have the JCI-specific menu item).

## What gets installed, and why

| App | Why |
|---|---|
| Tailscale | The single-auth tailnet — same login reaches all 4 target machines by name (MagicDNS). |
| mRemoteNG | One app, one set of saved credentials, for every RDP/SSH session — the actual "proxy" in proxy laptop. Windows-native, best multi-session tool for this. |
| Notion | Matches this runbook and the rest of the Ithaca Solutions workspace. |
| VS Code | Editing scripts/configs on the laptop itself. |
| Git | Version control for this repo and controls-field-tools. Git for Windows bundles Git Credential Manager, so `gh auth login` is enough — no separate token wrangling. |
| Bitwarden | Shared vault, same account signed in everywhere that needs it. |
| Google Chrome | Browser SSO flows (Tailscale, GitHub) and general use. |
| Wireshark | Field diagnosis when a BACnet/IP device won't talk — `bacnet` filter, Who-Is/I-Am pairs, duplicate device IDs. See the Notion runbook for the 5-step loop. |
| PuTTY | SSH fallback for anything mRemoteNG doesn't cover cleanly. |
| **GitHub CLI (`gh`)** | *Added for controls-field-tools.* It's a **private** repo — `gh auth login` is the one clean way to authenticate `git clone`/`pull` against it without hand-rolling a PAT. |
| **Python 3.12** | *Added for controls-field-tools.* `site-audit/bas_diff.py` and `site_tool.py` are stdlib-only Python — no interpreter was in the original app list, so the tool would clone fine and then not run. |
| **Claude (desktop app)** | *Added 2026-09-25.* Was missing from the original list — no functional dependency on it, just an oversight worth fixing since it's part of how this whole workflow is run day to day. |
| **Windows Terminal** | *Added 2026-09-25.* This laptop now runs PowerShell, Git Bash, and Python CLI tools regularly (setup.ps1 itself, controls-field-tools, general dev use) — a real multi-tab terminal beats juggling separate console windows for that. |

**Deliberately left out:** a general IP/subnet scanner. Wireshark's ARP
traffic plus IP Speed Dial's own ping+ARP scan and JCI engine discovery
already cover the practical need — a third overlapping tool isn't worth the
extra footprint unless a specific gap shows up in the field.

## Controls field tools (`controls-field-tools`)

Cloned by `setup.ps1` to `%USERPROFILE%\controls-field-tools` — private repo,
`gh auth login` required once. Two tools:

- **IP Speed Dial** (`speed-dial/`) — one-click static-IP switching between
  sites, ping+ARP subnet scan, JCI engine discovery. PowerShell, no extra
  runtime needed (Windows 10/11 ships PowerShell 5.1+). Right-click
  `Run-IP-SpeedDial.bat` → **Run JCI Elevated** if that context-menu item is
  present (it's provisioned on JCI-managed corporate laptops); otherwise a
  plain double-click + **Yes** at the UAC prompt works identically as long as
  the account has local admin, which this laptop's account does.
- **bas-diff** (`site-audit/`) — compares a before/after BAS capture and
  writes the visit closeout email. Pure Python stdlib, no network client at
  all, read-only, no install step beyond having Python on the machine.

Both tools are read-only and keep everything local — no cloud, no upload, no
telemetry (see `controls-field-tools/README.md`, "Design rules both tools
follow"). That's why they're safe to install here even though the proxy
laptop's main job is remote access, not field work: installing them costs
nothing and puts the tools one `git pull` away whenever they *are* needed in
the field, without waiting on a second setup pass.

**Before using either tool against a real site:** read
`controls-field-tools/CUSTOMER-DATA-EXPOSURE.md` and `SECURITY-INCIDENT.md`.
Both document a real, since-resolved incident where the field collector leaked
other customers' names into committed bundles, and where a live Metasys
credential landed in a notes file. Both are fixed and the credential was
rotated, but the fixes matter operationally: **credentials go in
`site-audit/.env`** (gitignored, never in a notes file or a Notion page), and
any capture bundle should be checked with the `grep`/`git ls-files` commands
in that doc before it's shared anywhere, since redaction covers content but
filenames can still carry a site name.

## Why git, not a flash drive

Recommendation: **git, not a USB flash drive**, for both this repo and
controls-field-tools. Reasons, specific to this setup:

1. **controls-field-tools already updates weekly**, not once. There's a
   standing maintenance job that opens a PR against it most weeks (new site
   subnets, fixes). A flash drive is a snapshot from install day; git is a
   30-second `git pull` to stay current. A flash drive would need to be
   re-imaged and re-carried every time the tools change.
2. **It's already how the tool is distributed and licensed for change control.**
   controls-field-tools is a private GitHub repo with PR-based maintenance
   already in place. Copying it to a flash drive creates a second, untracked
   copy with no relationship to that process — the exact kind of drift the PR
   workflow exists to prevent.
3. **A flash drive is a physical object that can be lost, and it would be
   carrying a copy of a private repo** whose history includes a
   since-resolved but real customer-data incident (see above). Git access is
   revocable (rotate the GitHub token, remove the collaborator) in a way a
   physical drive in a bag is not.
4. **This laptop already needs `git` and now `gh`** for the rest of the setup
   (this repo, Tailscale config, general dev use per the Notion page's app
   list) — there's no meaningful setup cost to using the same mechanism for
   controls-field-tools instead of a second, different method.

A flash drive would make sense for a one-time offline transfer to a machine
with genuinely no internet access. This laptop has internet (it's pulling
apps via winget and signing into Tailscale/GitHub SSO), so that case doesn't
apply here.

## Preferences (dark mode, identity wallpaper)

`setup.ps1` also sets two things that aren't strictly "install an app":

- **Dark mode** — app + system theme, via the standard `Personalize` registry
  keys. No restart needed.
- **Identity wallpaper** — same visual-identity system homelab-bootstrap uses
  on the Linux boxes (dev-1 shows "DEV", homeassistant-1 shows "HA"), so this
  laptop shows **"PROXY"** with hostname/role/Tailscale-IP underneath. It's
  not a separate image: `setup.ps1` clones `homelab-bootstrap` (private,
  same `gh auth login` as controls-field-tools) and renders
  `dotfiles/wallpapers/workstation.html` with headless Chrome — the *exact*
  template and query-string contract (`?label=&host=&tag=&ip=`) the Linux
  side uses, just applied with a Windows-native step (registry + `RUNDLL32`)
  instead of XFCE's `xfconf-query`. One template, two OS-specific appliers —
  see `homelab-bootstrap/docs/DIVERGENCE.md` #16 for why they're split that
  way instead of unified into one script.

**For a second property, site, or client setup:** edit `$IdentityTag` near
the top of `setup.ps1` (defaults to `"remote workstation"`) before running —
e.g. `"remote workstation - Ivy House"`. That's the whole change; nothing
else in the pipeline is specific to this one laptop or property. The Linux
side has the equivalent override (`IDENTITY_TAG` in homelab-bootstrap's
`lib/xfce.sh`), added the same day for the same reason: this is meant to
scale to more properties, and eventually other people's setups, without
rewriting the pipeline each time.

## Definition of done

- [ ] Windows 11 Pro licensed and activated on proxy laptop (`setup.ps1`'s edition check prints "OK" at the top of its run)
- [ ] `setup.ps1` run successfully — winget apps installed, controls-field-tools + homelab-bootstrap cloned
- [ ] Tailscale signed in on proxy laptop + all 4 targets, MagicDNS on
- [ ] mRemoteNG has 4 working saved connections, tested end to end
- [ ] Bitwarden vault accessible from proxy laptop
- [ ] `gh auth login` done, both private-repo clones succeed
- [ ] Dark mode applied; identity wallpaper shows PROXY + hostname/IP
- [ ] IP Speed Dial launches elevated and can apply a site IP
- [ ] Ubuntu lock-screen extension installed on both servers, verified session survives a lock
- [ ] IT/security check done on corporate laptop before installing anything there
- [ ] Niagara Workbench / Metasys SCT confirmed and installed manually (separate licensing track)

## Changelog

### 2026-09-25 (4)
- Added dark mode (system + app theme via registry) and an identity
  wallpaper ("PROXY" + hostname/tag/IP), both Brendan preferences flagged
  after the app-list fix. The wallpaper reuses homelab-bootstrap's existing
  template/render pipeline (`dotfiles/wallpapers/workstation.html`, new in
  homelab-bootstrap PR #8) rather than a separate Windows-only image, so the
  visual-identity system stays one source of truth across Linux and Windows
  boxes. `setup.ps1` now also clones `homelab-bootstrap` alongside
  `controls-field-tools`.
- Added `$IdentityTag` as an explicit, documented override point — Brendan's
  ask to keep this modular for future properties/sites (and eventually other
  people's setups) rather than hardcoding "remote workstation" for this one
  laptop.

### 2026-09-25 (3)
- Added Claude desktop (`Anthropic.Claude`) — missing from the original app
  list, flagged by Brendan after the first real run.
- Added Windows Terminal (`Microsoft.WindowsTerminal`) — proactive addition,
  not requested, easy to drop if unwanted: this laptop runs enough
  PowerShell/Git Bash/Python CLI work now that a real multi-tab terminal is
  worth the one extra winget line.

### 2026-09-25 (2)
- Made this repo **public**. The `irm | iex` one-liner below 404'd on the
  first real attempt to use it — `raw.githubusercontent.com` refuses
  unauthenticated requests for private-repo content regardless of path, and
  the whole point of the one-liner is zero prerequisites, so embedding a
  token wasn't the right fix. Audited contents first: no secrets, no
  customer data, just the app list and setup instructions.

### 2026-09-25
- Fixed a real install failure on the first machine this ran on: the
  `git clone` + `.\setup.ps1` instructions don't work on a bare machine
  (chicken-and-egg on `git`) and fail even worse if you instead use GitHub's
  Download ZIP button (Mark-of-the-Web blocks the unsigned script, and
  `Set-ExecutionPolicy RemoteSigned` doesn't fix that). Primary install
  method is now a one-line `irm | iex` bootstrap that needs nothing
  preinstalled; the clone path is now documented as the "local copy" option
  with the required `Unblock-File` step.
- Added a Windows edition check to `setup.ps1` — it was silently possible to
  run the whole install on a machine that landed on Home (the installer
  doesn't reliably prompt for the Pro key), with nothing ever flagging it.

### 2026-09-24
- Repo created — closes the "repo push to GitHub still pending" item from the
  Notion runbook. `setup.ps1` moved here from the Notion page's embedded copy.
- Added controls-field-tools integration: clone/pull step in `setup.ps1`,
  `gh` and Python 3.12 added to the winget app list (both were missing
  dependencies for tools the original list didn't anticipate).

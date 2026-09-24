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

Once you're at a signed-in Windows 11 Pro desktop, come back here.

## One-click install

```powershell
git clone https://github.com/BrendanJackson/proxy-laptop-setup.git
cd proxy-laptop-setup
.\setup.ps1        # run in PowerShell as Administrator
```

`setup.ps1` installs everything winget can install in one pass, then clones
`controls-field-tools` (see below). A handful of steps can't be scripted —
they're printed at the end of the run, and repeated here:

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

## Definition of done

- [ ] Windows 11 Pro licensed and activated on proxy laptop
- [ ] `setup.ps1` run successfully — winget apps installed, controls-field-tools cloned
- [ ] Tailscale signed in on proxy laptop + all 4 targets, MagicDNS on
- [ ] mRemoteNG has 4 working saved connections, tested end to end
- [ ] Bitwarden vault accessible from proxy laptop
- [ ] `gh auth login` done, controls-field-tools clone succeeds
- [ ] IP Speed Dial launches elevated and can apply a site IP
- [ ] Ubuntu lock-screen extension installed on both servers, verified session survives a lock
- [ ] IT/security check done on corporate laptop before installing anything there
- [ ] Niagara Workbench / Metasys SCT confirmed and installed manually (separate licensing track)

## Changelog

### 2026-09-24
- Repo created — closes the "repo push to GitHub still pending" item from the
  Notion runbook. `setup.ps1` moved here from the Notion page's embedded copy.
- Added controls-field-tools integration: clone/pull step in `setup.ps1`,
  `gh` and Python 3.12 added to the winget app list (both were missing
  dependencies for tools the original list didn't anticipate).

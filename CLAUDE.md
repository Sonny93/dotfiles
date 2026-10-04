# dotfiles

Personal setup for zsh, git, mise, Starship and Tabby, across three kinds of machines:

- **Windows 11 host**: Tabby + Bitwarden + `~/.ssh/config` only. No git, no clone of this repo. Files reach it by `scp` from the XPS or from the GitHub raw URL.
- **XPS** (Debian 13 PC): everything, through `just xps`. This machine is the XPS, and it is also an SSH target from the Windows host.
- **Server / VPS**: shell only, through `just server`.

## Setting up a machine

Claude Code runs on this machine; the user drives the other machines and pastes back output.

1. Identify the machine kind, then follow its section of `README.md` (Windows 11 host → Windows 11, XPS → XPS (Debian 13), server → Serveur / VPS) step by step. The README is the procedure; follow it as written.
2. For Windows steps and anything on a remote machine, give the user ready-to-paste commands (PowerShell 7 on Windows) and read the output they send back.
3. Done when `just doctor` (XPS, run last by `just xps`) or `just doctor-server` (server, run last by `just server`) prints only `OK`/`INFO` lines on that machine.

`just` lists the recipes; the doctors report what is missing.

## Public repo boundary

The repo is public. It holds only what grants no access and reveals nothing about the user's network. Everything else lives outside:

| Material | Lives in |
|---|---|
| SSH private key | Bitwarden, served by its SSH agent on PCs only |
| Hosts, IPs, `~/.ssh/config` | Bitwarden secure note + `~/.ssh/config` on each PC |
| Tabby profiles, knownHosts | Local Tabby config on each machine |
| Git identity | Each repo's `.git/config`; `~/.gitconfig.local` optional |
| GitHub token | `gh` on the XPS only |

Servers receive only the public key. Git over HTTPS through `gh` on the XPS; servers pull anonymously over HTTPS and stay without `gh` or agent forwarding.

## Invariants

- **Tabby**: `tabby/config.yaml` holds only overrides of Tabby's defaults, with comments explaining each. Settings change in the repo, then reach each machine through `tabby/install.ps1` (Windows one-liner) or `tabby/install.sh` (`just tabby`): back up, replace with the repo config, carry over `ssh.knownHosts` and an `openssh-config:` default profile. Both scripts implement the same behavior; a change to one lands in the other in the same change. Tabby must be closed while they run.
- **mise**: one `mise/config.toml` for every machine. Servers install the subset in the Justfile's `shell_tools` variable; the XPS installs everything with `just mise` (part of `just xps`).
- **Docs in sync**: any Justfile change updates `README.md` in the same change (Commandes table + the affected install steps).

## Conventions

- README in French; Justfile descriptions and messages in English.
- Each recipe has a one-line `# description` comment above it (shown by `just`), a `#!/usr/bin/env bash` body, and doctors print `OK:` / `WARN:` / `INFO:` lines that name the recipe to run.

# dotfiles

Personal setup for zsh, git, mise, Starship and Tabby, split into three roles. A machine can hold several (the Debian laptop is both client and dev).

- **Client**: Tabby + Bitwarden SSH agent + `~/.ssh/config`; the user connects to other machines from here. Windows 11 (no git, no clone: files come from the GitHub raw URL) and a Debian laptop. Set up by `tabby/install.ps1` / `tabby/install.sh`, never by `just`.
- **Dev machine**: shell + every mise tool + git hooks + `gh`. This machine is one: reached over SSH from the clients, with no key and no Tabby of its own. To reach servers it borrows the client's Bitwarden agent through `ForwardAgent`, enabled on its own `Host` in the client's `~/.ssh/config`, and lists the servers in a local `~/.ssh/config`.
- **Server / VPS**: shell only (`just shell`).

## Setting up a machine

Claude Code runs on this machine; the user drives the other machines and pastes back output.

1. Identify the machine's roles, then follow each matching section of `README.md` (Poste client → Windows 11 or Debian, Machine de dev, Serveur / VPS) step by step. The README is the procedure; follow it as written.
2. For Windows steps and anything on a remote machine, give the user ready-to-paste commands (PowerShell 7 on Windows) and read the output they send back.
3. Done when `just doctor-dev` (dev machine) or `just doctor-server` (server) prints only `OK`/`INFO` lines on that machine, and, on a client, Tabby opens its default profile with the key from `ssh-add -L`.

`just` lists the recipes; the doctors report what is missing.

## Public repo boundary

The repo is public. It holds only what grants no access and reveals nothing about the user's network. Everything else lives outside:

| Material | Lives in |
|---|---|
| SSH private key | Bitwarden, served by its SSH agent on clients only |
| Hosts, IPs, `~/.ssh/config` | Bitwarden secure note + `~/.ssh/config` on each client |
| Tabby profiles, knownHosts | Local Tabby config on each machine |
| Git identity | Each repo's `.git/config`; `~/.gitconfig.local` optional |
| GitHub token | `gh` on dev machines only |

Servers and dev machines receive only the public key. Git over HTTPS through `gh` on dev machines; servers pull anonymously over HTTPS and stay without `gh`. Agent forwarding targets dev machines only, never servers.

## Invariants

- **Tabby**: `tabby/config.yaml` holds only overrides of Tabby's defaults, with comments explaining each. Settings change in the repo, then reach each machine through `tabby/install.ps1` (Windows one-liner) or `tabby/install.sh` (`bash ~/dotfiles/tabby/install.sh`): back up, replace with the repo config, carry over `ssh.knownHosts` and an `openssh-config:` default profile. Both scripts implement the same behavior; a change to one lands in the other in the same change. Tabby must be closed while they run.
- **mise**: one `mise/config.toml` for every machine. Servers install the subset in the Justfile's `shell_tools` variable; dev machines install everything with `just mise`.
- **Docs in sync**: any Justfile change updates `README.md` in the same change (Commandes table + the affected install steps).

## Conventions

- README in French; Justfile descriptions and messages in English.
- Each recipe has a one-line `# description` comment above it (shown by `just`), a `#!/usr/bin/env bash` body, and doctors print `OK:` / `WARN:` / `INFO:` lines that name the recipe to run.

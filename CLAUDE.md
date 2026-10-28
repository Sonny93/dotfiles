# dotfiles

Personal setup for zsh, git, mise, Starship and Tabby, split into four machine roles:

- **Windows 11**: client only (Tabby + Bitwarden SSH agent). No git, no clone: files come from the GitHub raw URL, set up by `tabby/install.ps1`, never by `just`.
- **XPS** (Debian laptop): client and dev, everything a dev machine has (`just xps`) plus Bitwarden and Tabby.
- **Dev machine**: shell, every mise tool, git hooks, `gh`, Claude Code config (`just dev`). Reached over SSH from Windows 11 and the XPS, with no key of its own: it borrows the client's Bitwarden agent through `ForwardAgent`.
- **Server / VPS**: shell only (`just server`).

## Setting up a machine

Claude Code runs on the dev machine; the user drives the other machines and pastes back output.

1. Identify the machine's role, then follow its section of `README.md` step by step, as written.
2. For Windows steps and anything on a remote machine, give the user ready-to-paste commands (PowerShell 7 on Windows) and read the output they send back.
3. Done when `just doctor-dev` or `just doctor-server` prints only `OK`/`INFO` lines on that machine, and, on Windows 11 and the XPS, Tabby opens its default profile with the key from `ssh-add -L`.

## Public repo boundary

The repo is public: it holds nothing that grants access or reveals the user's network (keys, hosts, IPs, `~/.ssh/config`, git identity, tokens). Where each of those lives instead: `README.md`, sections « Où vit quoi » and « Sécurité ». Agent forwarding targets dev machines only, never servers; servers stay without `gh` and pull anonymously over HTTPS.

## Invariants

- **Tabby**: `tabby/config.yaml` holds only overrides of Tabby's defaults, each with a comment. `tabby/install.ps1` and `tabby/install.sh` implement the same behavior: a change to one lands in the other in the same change. Tabby must be closed while they run.
- **mise**: one `mise/config.toml` for every machine; servers install only the Justfile's `shell_tools` subset.
- **Claude Code**: only machine-independent, non-sensitive settings go in `claude/settings.json`. `just claude` merges it with jq `*`, which replaces arrays instead of merging them: an array in the base (`hooks.PreToolUse`, `autoMode.allow`…) overwrites the machine's copy whole, so it lists every entry.
- **Docs in sync**: any Justfile change updates `README.md` in the same change (Commandes table + the affected install steps).

## Conventions

- README in French; Justfile descriptions and messages in English.
- Each recipe has a one-line `# description` comment above it (shown by `just`), a `#!/usr/bin/env bash` body, and doctors print `OK` / `WARN` / `INFO` lines through `ok` / `warn` / `info` from `scripts/status.sh`, naming the recipe to run.

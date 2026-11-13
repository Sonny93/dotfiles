# dotfiles

Personal setup for zsh, git, mise and Starship, split into two machine roles:

- **Dev machine** (Debian or Arch family, e.g. CachyOS): shell, every mise tool, git hooks, `gh`, Claude Code config (`just dev`). The machines the user sits at hold the key through the Bitwarden SSH agent; their desktop setup (Bitwarden, Tabby, GUI apps, `/etc`) comes from a separate private repo, never from dotfiles. A remote dev machine reached over SSH has no key of its own: it borrows the client's Bitwarden agent through `ForwardAgent`.
- **Server / VPS**: shell only (`just server`).

## Setting up a machine

Claude Code runs on the dev machine; the user drives the other machines and pastes back output.

1. Identify the machine's role, then follow its section of `README.md` step by step, as written.
2. For anything on a remote machine, give the user ready-to-paste commands and read the output they send back.
3. Done when `just doctor-dev` or `just doctor-server` prints only `OK`/`INFO` lines on that machine.

## Public repo boundary

The repo is public: it holds nothing that grants access or reveals the user's network (keys, hosts, IPs, `~/.ssh/config`, git identity, tokens). Where each of those lives instead: `README.md`, sections "Where things live" and "Security". Agent forwarding targets dev machines only, never servers; servers stay without `gh` and pull anonymously over HTTPS.

## Invariants

- **mise**: one `mise/config.toml` for every machine; servers install only the Justfile's `shell_tools` subset.
- **Claude Code**: only machine-independent, non-sensitive settings go in `claude/settings.json`. `just claude` merges it with jq `*`, which replaces arrays instead of merging them: an array in the base (`hooks.PreToolUse`, `autoMode.allow`…) overwrites the machine's copy whole, so it lists every entry.
- **System packages**: every apt call has a pacman twin, picked through `scripts/distro-family.sh` (Debian and Arch families only, anything else is an error).
- **Docs in sync**: any Justfile change updates `README.md` and its French copy `docs/fr/README.md` in the same change (Commands table + the affected install steps).

## Conventions

- Each recipe has a one-line `# description` comment above it (shown by `just`), a `#!/usr/bin/env bash` body, and doctors print `OK` / `WARN` / `INFO` lines through `ok` / `warn` / `info` from `scripts/status.sh`, naming the recipe to run.

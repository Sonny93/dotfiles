# dotfiles

Français : [docs/fr/README.md](docs/fr/README.md)

zsh, git, mise, tmux, Starship and Tabby, split by machine: Windows 11, XPS, dev machine and server.

| Machine | Contents | Check with |
|---|---|---|
| **Windows 11** | Tabby + Bitwarden (SSH agent) + `~/.ssh/config`: you connect to the other machines from here | Tabby opens the default connection |
| **XPS** (Debian) | Everything the dev machine has + Tabby + Bitwarden (SSH agent) + `~/.ssh/config` | `just doctor-dev` + Tabby opens the default connection |
| **Dev machine** (Debian) | Shell + every mise tool + git + `gh` + Claude Code config | `just doctor-dev` |
| **Server / VPS** (Debian) | Shell only. No private key, no GitHub account, nothing to steal | `just doctor-server` |

## Contents

- [Where things live](#where-things-live)
- [Once only: the SSH key](#once-only-the-ssh-key)
- [Windows 11](#windows-11)
- [Dev machine](#dev-machine)
  - [Managing servers from the dev machine](#managing-servers-from-the-dev-machine)
- [XPS](#xps)
- [Server / VPS](#server--vps)
- [Add a connection](#add-a-connection)
- [Commands](#commands)
- [Shell](#shell)
- [Tabby](#tabby)
- [tmux](#tmux)
- [Claude Code](#claude-code)
- [Security](#security)
- [MOTD](#motd)

## Where things live

| What | Where | In the repo |
|---|---|---|
| Private SSH key | Bitwarden, served by its SSH agent on Windows 11 and the XPS | Never |
| SSH connections | `~/.ssh/config` on Windows 11 and the XPS, copy in a Bitwarden note | Never |
| Tabby settings (theme, font, shortcuts) | `tabby/config.yaml` | Yes |
| Git identity | Each repo (`.git/config`), or `~/.gitconfig.local` as an option | Never |
| GitHub access | `gh` token on each dev machine (the XPS included) | Never |
| Claude Code config (CLAUDE.md, RTK.md, agents, skills, base settings) | `claude/` | Yes |
| Claude Code credentials, MCP tokens, memory, history | `~/.claude/` and `~/.claude.json` on each dev machine | Never |

The repo is public: it is cloned over HTTPS, with no key or account.

## Once only: the SSH key

1. In Bitwarden, create an **SSH key** item (Ed25519). The private key never leaves the vault.
2. Create a secure note named **ssh config** with the list of connections, in `~/.ssh/config` format:

   ```
   Host mon-serveur
       HostName 203.0.113.10

   Host *
       User sonny
       ServerAliveInterval 5
       ServerAliveCountMax 10
   ```

   No `IdentityFile`: `ssh` and Tabby ask the Bitwarden agent for the key.

## Windows 11

1. Install **Bitwarden Desktop**, sign in, then enable the **SSH agent** in the settings.
2. Turn off the Windows SSH agent, which conflicts with Bitwarden's (PowerShell **admin**):

   ```powershell
   Stop-Service ssh-agent
   Set-Service ssh-agent -StartupType Disabled
   ```

3. Create `C:\Users\<user>\.ssh\config` (no extension) with the content of the **ssh config** note.
4. Tabby looks for this file through the `HOME` variable, which is not set by default on Windows:

   ```powershell
   [Environment]::SetEnvironmentVariable("HOME", $env:USERPROFILE, "User")
   ```

5. Install **Tabby**, launch it once, close it completely (taskbar icon included), then, from Windows Terminal (not from Tabby):

   ```powershell
   irm https://raw.githubusercontent.com/Sonny93/dotfiles/main/tabby/install.ps1 | iex
   ```

6. Verify: `ssh-add -L` shows the Bitwarden key, and Tabby opens the chosen connection at launch.

To update: see [Tabby](#tabby).

## Dev machine

### Install

1. Base packages:

   ```sh
   sudo apt install git curl zsh
   ```

2. Clone the repo (the `~/dotfiles` path is hard-coded) and install [mise](https://mise.jdx.dev):

   ```sh
   git clone https://github.com/Sonny93/dotfiles ~/dotfiles
   curl https://mise.run | sh
   export PATH="$HOME/.local/bin:$PATH"
   ```

3. Shell:

   ```sh
   cd ~/dotfiles
   mise exec just -- just shell
   chsh -s "$(command -v zsh)"
   exec zsh
   ```

4. Everything else:

   ```sh
   just dev
   ```

   `just dev` runs `apt`, `build-deps` (packages to build tmux), `shell`, `mise` (all the tools), `tmux` (links for the tmux config and the micro theme), `git` (config + gitleaks hook), `gh-auth`, `notes` (git repo for the notes), `claude` (Claude Code config), then `doctor-dev`, which must print only `OK` / `INFO` lines.

   No default git identity: set it in each repo (`git config user.name` / `user.email`). For a default identity on the machine, put it in `~/.gitconfig.local` (`[user]` section).

### Managing servers from the dev machine

To chain Windows 11 or XPS → dev machine → server (for example Claude Code on the dev machine working on a VPS), the dev machine borrows the client's Bitwarden agent instead of having its own key:

1. In the **ssh config** note and in `~/.ssh/config` on Windows 11 and the XPS, enable agent forwarding on the dev machine's `Host`, and on that one only:

   ```
   Host ma-machine-de-dev
       HostName 203.0.113.20
       ForwardAgent yes
   ```

2. On the dev machine, create `~/.ssh/config` with the servers to manage (the same note, without the dev machine itself).

Each connection started from the dev machine asks for approval in Bitwarden, on the client. It only works while an SSH session from the client is open.

### Update

```sh
cd ~/dotfiles && git pull && just dev
exec zsh
```

## XPS

The XPS is both a dev machine and a client.

1. Install as a [Dev machine](#dev-machine), running `just xps` (alias of `just dev`) at step 4.
2. Install **Bitwarden Desktop** as a `.deb` (not Flatpak or Snap: the SSH agent does not create its socket there), sign in, enable the **SSH agent**. Then announce it to the whole graphical session (Tabby included), and log out / log back in:

   ```sh
   mkdir -p ~/.config/environment.d
   echo 'SSH_AUTH_SOCK=${HOME}/.bitwarden-ssh-agent.sock' > ~/.config/environment.d/bitwarden-ssh-agent.conf
   ```

3. Create `~/.ssh/config` with the content of the **ssh config** note.
4. Install **Tabby**, launch it once, close it completely, then from another terminal:

   ```sh
   bash ~/dotfiles/tabby/install.sh
   ```

5. On KDE Plasma Wayland, Tabby's global shortcut (`Ctrl+Shift+Space`, show / hide) goes through the global shortcuts portal, which Electron only uses with a flag. Add that flag to Tabby's launcher:

   ```sh
   sed 's|^Exec=/opt/Tabby/tabby|& --enable-features=GlobalShortcutsPortal|' /usr/share/applications/tabby.desktop > ~/.local/share/applications/tabby.desktop
   ```

   Relaunch Tabby from the launcher, then in **System Settings → Keyboard → Shortcuts → org.chromium.Chromium**, assign `Ctrl+Shift+Space` to "Electron shortcut Ctrl+Shift+Space" (once only, KDE remembers it). The `hacks.globalHotkey: false` in `tabby/config.yaml` forces Tabby to declare this shortcut, which it otherwise ignores on Plasma Wayland before 6.6.

6. Verify: `ssh-add -L` shows the Bitwarden key, Tabby opens the chosen connection at launch, and `Ctrl+Shift+Space` shows / hides Tabby.

### Update

```sh
cd ~/dotfiles && git pull && just xps
exec zsh
```

Tabby: see [Tabby](#tabby).

## Server / VPS

### Install

1. **Give the public key to the server.** It is the lock, not the key: it can be read safely.
   - New VPS: paste the public key (copied from Bitwarden) into the host's form.
   - Existing server, from Windows 11 (PowerShell) or the XPS, with a password connection:

     ```sh
     ssh-add -L | ssh user@host "umask 077; mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys"
     ```

2. Add the connection (see [Add a connection](#add-a-connection)).
3. On the server:

   ```sh
   sudo apt install git curl zsh
   git clone https://github.com/Sonny93/dotfiles ~/dotfiles
   curl https://mise.run | sh
   export PATH="$HOME/.local/bin:$PATH"
   cd ~/dotfiles
   mise exec just -- just shell
   chsh -s "$(command -v zsh)"
   exec zsh
   ```

4. Everything else:

   ```sh
   just server
   ```

   `just server` runs `apt`, `shell` and `doctor-server`. `just shell` only installs the tools the shell needs (starship, fzf, just, fastfetch), not the whole mise config.

Never do on a server: put the private key on it, sign in to GitHub from it, or enable `ForwardAgent` to it (root on the server could use your key while you are connected). Agent forwarding is reserved for your own dev machines.

### Update a server

```sh
cd ~/dotfiles && git pull && just server
exec zsh
```

## Add a connection

1. Give the public key to the server (see [Server / VPS](#server--vps)).
2. Add the `Host` to the Bitwarden **ssh config** note, then to `~/.ssh/config` on Windows 11 and the XPS (and on the dev machine if it must reach this server). Tabby shows it at next launch.

## Commands

`just` or `just help` lists the commands. Windows 11 uses none: Tabby goes through its script (see [Tabby](#tabby)).

| Command | Purpose | Dev / XPS | Server |
|---|---|---|---|
| `just dev` (alias `just xps`) | Install / update a dev machine: `apt`, `build-deps`, `shell`, `mise`, `tmux`, `git`, `gh-auth`, `notes`, `claude`, `doctor-dev` | ✓ | |
| `just server` | Install / update a server: `apt`, `shell`, `doctor-server` | | ✓ |
| `just apt` | Update the system packages | ✓ | ✓ |
| `just build-deps` | Install the system packages to build tmux (`build-essential`, `libncurses-dev`, `bison`) | ✓ | |
| `just shell` | zsh, Starship and the shell's mise tools | ✓ | ✓ |
| `just mise` | Install / update every tool in `mise/config.toml` | ✓ | |
| `just tmux` | Link the tmux config (`~/.config/tmux/tmux.conf`) and the micro Cobalt2 theme (`~/.config/micro/colorschemes/cobalt2.micro`) | ✓ | |
| `just git` | The repo's git config + gitleaks hook | ✓ | |
| `just notes` | Turn `~/notes` into a git repo linked to the private GitHub repo `notes` (created on the first machine, cloned elsewhere) | ✓ | |
| `just gh-auth` | GitHub sign-in through `gh`, used by git over HTTPS | ✓ | |
| `just claude` | Link the Claude Code config (CLAUDE.md, RTK.md, agents, skills) and merge the base settings | ✓ | |
| `just doctor-server` | Check the shell | ✓ | ✓ |
| `just doctor-dev` | Check the whole dev machine (also runs `doctor-server`) | ✓ | |
| `just uninstall-omz` | Remove an old Oh My Zsh / Powerlevel10k install | | |

## Shell

zsh + [zinit](https://github.com/zdharma-continuum/zinit) (autosuggestions, syntax-highlighting) + [Starship](https://starship.rs) (prompt) + fzf (`Ctrl+R` / `Ctrl+T` / `Alt+C`) + fastfetch (alias `ff`). The `update` command updates the system (`apt`), then the tools (`mise upgrade`), then restarts idle Claude Code instances in tmux (`tmux/restart-claude.sh`). Keyboard shortcuts (Ctrl+arrows, Home/End, Delete…) come from Oh My Zsh's `key-bindings.zsh` file, loaded on its own through zinit: it also handles the sequences Tabby sends on Windows. Every tool comes from mise, with a single config for all machines.

Each machine gets a colored badge (emoji) computed from its hostname, shown in the tab title and in the prompt: no configuration. If two machines collide, rename one of them or add `export MACHINE_BADGE=🟢` to `~/.zshenv` on that machine.

## Tabby

`tabby/config.yaml` only contains what differs from Tabby's defaults. It is the reference: a setting is changed in the repo (commit + push), then reinstalled on Windows 11 and the XPS. A setting changed in Tabby's interface is lost at the next install.

Install or update, with Tabby **closed**, from another terminal:

- **Windows**: `irm https://raw.githubusercontent.com/Sonny93/dotfiles/main/tabby/install.ps1 | iex` (`tabby/install.ps1`)
- **XPS**: `cd ~/dotfiles && git pull && bash tabby/install.sh` (`tabby/install.sh`)

The script:

1. backs up the local config (`config.backup-<date>.yaml`, next to it);
2. replaces it with the repo's;
3. keeps the already known hosts (no new fingerprint validation);
4. keeps the default profile if it points to a `Host` of `~/.ssh/config`, otherwise asks which one to open at launch (a `Host` or the local shell).

Connections do not go through the Tabby config: it reads them from `~/.ssh/config` and shows them as `mon-serveur (.ssh/config)`. Their shared settings come from `profileDefaults.ssh` in `tabby/config.yaml`: tab title sent by the remote shell (colored badge and machine name, then the current folder or command) and new tab / SFTP opened in the current folder. The `.zshrc` sends both at every prompt, no profile to edit by hand.

## tmux

On dev machines, tmux keeps sessions alive when the SSH connection drops. mise builds tmux from source (`mise-tmux` plugin, with `build-essential`, `libncurses-dev` and `bison` installed by `just build-deps`): the prebuilt binaries from `tmux/tmux-builds` lag weeks behind tmux releases. `tmux/tmux.conf` (linked by `just tmux`) only contains what differs from tmux's defaults. The prefix is **Ctrl+A** (Ctrl+B is used by Claude Code to send a command to the background).

`t` opens or attaches a tmux session. `t .` (or any path, for example `t ~/dev/app`), run from a project (any subfolder of a git repo), opens or attaches the project's session, named after the git root folder, with the "Claude + shells" layout in the first tab: Claude Code on the left, two stacked shells on the right (`tmux/workspace.sh`). Claude resumes the folder's last conversation there (`claude --continue`), for example after a tmux restart; a "Claude + shells" tab added to an existing session starts a fresh conversation, so two tabs never share the same one. `t <name>` attaches the session of that name, or creates it if `<name>` is a known project (`~/dev/<name>` or `~/dotfiles`); `Tab` completes sessions and projects. `t` alone attaches the last session, or opens the session picker when already inside tmux; with no session at all, it opens the picker directly in the terminal, limited to projects: `Enter` creates the chosen project's session and attaches to it, `Esc` creates nothing. When Claude exits, its pane stays open on a shell. Inside tmux, `t` switches to the session without nesting another one.

tmux boils down to two notions: the session (usually a project) and the tab. `Alt+n` or `Ctrl+A` then `c` opens the "New tab" menu: Claude + shells (`w`), Claude alone (`c`) or shell alone (`s`), in the current pane's folder (`tmux/new-tab-menu.conf`, defined once and reused by the palette).

`Ctrl+A` then `s` opens a single picker (fzf in a popup): the open sessions as a tree (the current one is marked), each followed by its tabs with the same label as the top bar, then the folders of `~/dev` and `~/dotfiles` without a session. The current tab is preselected, the preview shows the targeted tab's pane, and the session name stays filterable from each tab. `Enter` switches to the session or tab, creating the session with "Claude + shells" for a project, `Esc` closes without doing anything (`tmux/session-picker.sh`). The native tree of sessions and tabs remains in the palette.

`Ctrl+A` then `n` opens the project's free-form notes in a popup (micro with the Cobalt2 theme, `micro/colorschemes/cobalt2.micro`, linked by `just tmux`; VS Code-style shortcuts: `Ctrl+S` saves, `Ctrl+Q` closes, `Ctrl+C` copies the selection to the workstation's clipboard (OSC 52), autosave, `Ctrl+Z` history kept after closing). The file is `~/notes/<project>.md`, outside the repos; the project is the git root folder of the current pane, created with a title on first use (`tmux/notes.sh`). `~/notes` is a git repo: opening does a pull, each close commits then pushes to the private GitHub repo `notes` created by `just notes`. Commits are signed `notes <notes@localhost>`, an address unknown to GitHub: they do not inflate the profile's contribution graph. On conflict or failure, a tmux message flags it: ask Claude to sync `~/notes`. This key replaces tmux's native `next-window`: `Alt+1` … `Alt+9` switch tabs.

The status bar spans two lines, in Cobalt2 colors like Tabby: the first lists the sessions (the current one in yellow), the second the tabs, each named after the title of its Claude pane. A bell in any pane of the tab turns its tab pink; `claude/settings.json` sets `preferredNotifChannel` to `terminal_bell` so Claude rings when it has finished or is waiting for an answer. `Alt+1` … `Alt+9` switch tabs without the prefix, and so do `Alt+&` … `Alt+ç` (the AZERTY number row).

`Ctrl+A` then `Ctrl+K` opens a command palette (fzf in a popup): the actions of `tmux/palette.tsv` (label, shortcut, tmux command; one action = one line), `Enter` runs the command on the pane the palette was opened from, `Esc` closes (`tmux/command-palette.sh`).

After `update`, Claude Code instances that are already open keep the old binary: the "Restart idle Claude Code" palette action restarts the idle ones with `claude --resume`, skipping those that are working and those already up to date (`tmux/restart-claude.sh`).

The shortcuts live in `tmux/cheatsheet.md`; `Ctrl+A` then `h` opens it in tmux.

`tmux ls` lists the sessions. The mouse is enabled: dragging selects text within a single pane without copying it, `Ctrl+C` or `Enter` copies it to the workstation's clipboard, a click or `Esc` cancels.

## Claude Code

`claude/` holds the Claude Code user config, applied by `just claude` (run by `just dev`):

- **Linked**: the top-level `.md` files of `claude/` (`CLAUDE.md`, `RTK.md`), each file of `claude/agents/` and each folder of `claude/skills/` are linked one by one into `~/.claude/` (`~/.claude/CLAUDE.md`, `~/.claude/RTK.md`, `~/.claude/agents/<name>.md`, `~/.claude/skills/<name>`). The rest of `~/.claude/skills/` (`synced/`, skills installed by `npx skills`, plugins) is left untouched.
- **Merged**: `claude/settings.json` is a base merged (jq) into `~/.claude/settings.json`, never linked: Claude Code rewrites that file itself. The repo's keys win, the machine's own keys (`model`, `theme`…) stay.
- **rtk**: `rtk` (installed by `just mise`) compresses command output before it reaches Claude. The base settings declare its `PreToolUse` hook (`rtk hook claude`) and `CLAUDE.md` imports `RTK.md`: no `rtk init` to run. Do not rerun `rtk init -g` (it would modify `settings.json` and write through the `RTK.md` link); if a new rtk version changes `RTK.md`, regenerate it elsewhere and copy it to `claude/RTK.md`.
- `claude/statusline.sh` is referenced directly by the base settings: nothing to install.
- **Doc skill guard**: `claude/hooks/require-skill.sh`, referenced by the base settings (`PreToolUse` hook on `Edit|Write`), refuses any change to a `CLAUDE.md`, `CLAUDE.local.md`, `AGENTS.md` or `.claude/rules/*.md` until the `claude-md` skill has been loaded in the session, and to a `README.md`, `docs/**/*.md`, `CONTRIBUTING.md`, `DEPLOY.md`, `PUBLISHING.md` or `SECURITY.md` until the `project-docs` skill has been. `CHANGELOG.md` and `docs/adr/` stay free.

Before replacing anything, `just claude` moves what exists to `~/.claude/backups/dotfiles-<date>/` (same relative path) and prints each backup. Nothing is deleted, except links to the repo that became orphaned (skill or agent removed from the repo).

- **Removing a setting**: the merge only adds and overwrites. A key removed from `claude/settings.json` is removed by hand from `~/.claude/settings.json`.
- **Adding a skill or an agent**: create it in `claude/skills/<name>/SKILL.md` or `claude/agents/<name>.md`, then `just claude`.
- **Outside the repo**: skills installed by `npx skills` or by plugins stay outside the repo.
- Only machine-independent, non-sensitive settings go in `claude/settings.json`.

## Security

The repo is public and **never** contains a secret, an identity or server info:

- **SSH key**: only in Bitwarden, on Windows 11 and the XPS. Locked vault = no connection possible. A lost machine = sign out of Bitwarden on it.
- **Connections**: in Bitwarden and in `~/.ssh/config` on Windows 11 and the XPS, never in the repo.
- **Git identity**: set in each repo. `.gitconfig` also includes `~/.gitconfig.local`, optional and specific to each machine, for a default identity.
- **GitHub**: `gh` token on dev machines only (the XPS included). It goes into the system keyring if there is one, otherwise in plain text in `~/.config/gh/hosts.yml`. No SSH key for GitHub: `.gitconfig` rewrites `git@github.com:` remotes to HTTPS, so repos cloned over SSH also go through `gh`, without changing their remote.
- **gitleaks** runs as a pre-commit hook (`githooks/pre-commit`, enabled by `just git`) and blocks any secret trying to get in.

## MOTD

> sudo nano /etc/update-motd.d/99-custom

```
#!/bin/bash

LAST_IP=$(last -n 2 $USER | awk 'NR==2{print $3}')
LAST_DATE=$(last -n 2 $USER | awk 'NR==2{print $4, $5, $6, $7}')

echo "$(figlet $(logname | sed 's/./\u&/'))"
echo -e "\e[44m\e[97m  🔐 Dernière connexion : $LAST_DATE depuis $LAST_IP  \e[0m"
echo ""
echo "📅 $(date)"
echo "🖥️  $(hostname | sed 's/./\u&/') — Linux $(uname -r)"
echo "💾 RAM : $(free -h | awk '/Mem/{print $3"/"$2}') ($(free | awk '/Mem/{printf "%.0f%%", $3/$2*100}'))"
echo "💿 Disque : $(df -h / | awk 'NR==2{print $3"/"$2" ("$5")"}')"
echo "🌡️  Uptime : $(uptime -p)"
echo ""
```

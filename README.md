# dotfiles

Français : [docs/fr/README.md](docs/fr/README.md)

zsh, git, mise, tmux and Starship, split by machine: dev machine and server.

| Machine | Contents | Check with |
|---|---|---|
| **Dev machine** (Debian or Arch based, for example CachyOS) | Shell + every mise tool + git + `gh` + Claude Code config. A desktop machine gets Bitwarden (SSH agent), Tabby and the desktop apps from a separate private repo | `just doctor-dev` |
| **Server / VPS** (Debian) | Shell only. No private key, no GitHub account, nothing to steal | `just doctor-server` |

## Why

- **Purpose**: one command keeps the user's dev machines and servers set up and up to date.
- **Users**: one person, a few personal machines and servers.
- **Stakes**: it runs root package upgrades. A broken update can leave a machine unbootable; the btrfs snapshots on the CachyOS PCs are the safety net.
- **Non-goals**: no multi-user support, no unattended root updates, no `NOPASSWD` sudo.
- **Hard constraints**: dotfiles never depends on the machines repo (the dependency goes one way, from machines to dotfiles); Arch and Debian are both supported.

## Contents

- [Why](#why)
- [Where things live](#where-things-live)
- [Once only: the SSH key](#once-only-the-ssh-key)
- [Dev machine](#dev-machine)
  - [Managing servers from the dev machine](#managing-servers-from-the-dev-machine)
- [Server / VPS](#server--vps)
- [Add a connection](#add-a-connection)
- [Commands](#commands)
- [The update command](#the-update-command)
- [Shell](#shell)
- [tmux](#tmux)
- [Claude Code](#claude-code)
- [Security](#security)
- [MOTD](#motd)

## Where things live

| What | Where | In the repo |
|---|---|---|
| Private SSH key | Bitwarden, served by its SSH agent on your local machines (the ones running Bitwarden) | Never |
| SSH connections | `~/.ssh/config` on your local machines, copy in a Bitwarden note | Never |
| Git identity | Each repo (`.git/config`), or `~/.gitconfig.local` as an option | Never |
| GitHub access | `gh` token on each dev machine (local machines included) | Never |
| Claude Code config (CLAUDE.md, RTK.md, agents, skills, base settings) | `claude/` | Yes |
| Claude Code credentials, MCP tokens, memory, history | `~/.claude/` and `~/.claude.json` on each dev machine | Never |
| Machine role (`dev` or `server`), written by `just dev` / `just server` and read by `update` | `~/.config/dotfiles/role` | Never |
| Run log of `update` (quiet mode) and its report, the 14 newest of each are kept | `~/.local/state/dotfiles/update/<timestamp>.log` and `<timestamp>.report` | Never |
| Log of the root pacman upgrade started by `update` (root-owned) | `/var/log/dotfiles/pacman-<timestamp>.log` | Never |
| Optional `update` hand-off: an executable that a private repo can install, it replaces the role recipe and must run it itself | `~/.config/dotfiles/update-hook` | Never |

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

   No `IdentityFile`: `ssh` asks the Bitwarden agent for the key.

## Dev machine

### Install

1. Base packages. On Debian:

   ```sh
   sudo apt install git curl zsh
   ```

   On Arch (CachyOS for example):

   ```sh
   sudo pacman -S --needed git curl zsh
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

   `just dev` runs `system`, `build-deps` (packages to build tmux), `shell`, `mise` (all the tools), `tmux` (links for the tmux config and the micro theme), `git` (config + gitleaks and shellcheck hook), `gh-auth`, `notes` (git repo for the notes), `claude` (Claude Code config), then `doctor-dev`, which must print only `OK` / `INFO` lines.

   No default git identity: set it in each repo (`git config user.name` / `user.email`). For a default identity on the machine, put it in `~/.gitconfig.local` (`[user]` section).

### Managing servers from the dev machine

To chain local machine → remote dev machine → server (for example Claude Code on the dev machine working on a VPS), the remote dev machine borrows the client's Bitwarden agent instead of having its own key:

1. In the **ssh config** note and in `~/.ssh/config` on your local machines, enable agent forwarding on the dev machine's `Host`, and on that one only:

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

## Server / VPS

### Install

1. **Give the public key to the server.** It is the lock, not the key: it can be read safely.
   - New VPS: paste the public key (copied from Bitwarden) into the host's form.
   - Existing server, from a local machine, with a password connection:

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

   `just server` runs `system`, `shell` and `doctor-server`. `just shell` only installs the tools the shell needs (starship, fzf, just, fastfetch), not the whole mise config.

Never do on a server: put the private key on it, sign in to GitHub from it, or enable `ForwardAgent` to it (root on the server could use your key while you are connected). Agent forwarding is reserved for your own dev machines.

### Update a server

```sh
cd ~/dotfiles && git pull && just server
exec zsh
```

## Add a connection

1. Give the public key to the server (see [Server / VPS](#server--vps)).
2. Add the `Host` to the Bitwarden **ssh config** note, then to `~/.ssh/config` on your local machines (and on the dev machine if it must reach this server).

## Commands

`just` or `just help` lists the commands.

| Command | Purpose | Dev | Server |
|---|---|---|---|
| `just dev` | Install / update a dev machine, and record the role `dev` in `~/.config/dotfiles/role`: `system`, `build-deps`, `shell`, `mise`, `tmux`, `git`, `gh-auth`, `notes`, `claude`, `doctor-dev` | ✓ | |
| `just server` | Install / update a server, and record the role `server` in `~/.config/dotfiles/role`: `system`, `shell`, `doctor-server` | | ✓ |
| `just system` | Update the system packages (apt or pacman) | ✓ | ✓ |
| `just build-deps` | Install the system packages to build tmux (Debian: `build-essential`, `libncurses-dev`, `bison`; Arch: `base-devel`, `ncurses`, `bison`) | ✓ | |
| `just shell` | zsh, Starship and the shell's mise tools | ✓ | ✓ |
| `just mise` | Install / update every tool in `mise/config.toml` | ✓ | |
| `just tmux` | Link the tmux config (`~/.config/tmux/tmux.conf`) and the micro Cobalt2 theme (`~/.config/micro/colorschemes/cobalt2.micro`) | ✓ | |
| `just git` | The repo's git config + gitleaks and shellcheck hook | ✓ | |
| `just notes` | Turn `~/notes` into a git repo linked to the private GitHub repo `notes` (created on the first machine, cloned elsewhere) | ✓ | |
| `just gh-auth` | GitHub sign-in through `gh`, used by git over HTTPS | ✓ | |
| `just claude` | Link the Claude Code config (CLAUDE.md, RTK.md, agents, skills, rtk config) and merge the base settings, uninstall the plugins and marketplaces dropped from them | ✓ | |
| `just doctor-server` | Check the shell | ✓ | ✓ |
| `just doctor-dev` | Check the whole dev machine (also runs `doctor-server`), including the tools of the Code menu and delta, which git needs as its pager | ✓ | |
| `just test` | Run the tmux script tests (`tmux/*.test.sh`) on an isolated tmux server, the Claude status line tests (`claude/*.test.sh`), the Claude hook tests (`claude/hooks/*.test.sh`) and the shared script tests (`scripts/*.test.sh`) | ✓ | |
| `just uninstall-omz` | Remove an old Oh My Zsh / Powerlevel10k install | | |

## The update command

`update` (`scripts/update.sh [--verbose]`) is quiet by default: one banner per phase, one `✓` / `✗` line per step, the list of pulled commits, a compact list of package upgrades with their versions, conflicts and errors with their reason, and a final summary. Everything else goes to a run log; its path is shown whenever a step fails or the summary is not clean. `update --verbose` prints the full output of every step instead and writes no log. Any other argument is rejected.

Phases:

1. **Pull**: fast-forward only. It skips the pull with a warning when the repo is not on `main`, has uncommitted tracked changes, has no upstream or has diverged, and continues without pulling when offline. The incoming commits are always listed, even in quiet mode: that list is the only review of code that will run as root. When commits were merged, `update` restarts itself so the new version runs.
2. **Apply**: runs `~/.config/dotfiles/update-hook` when an executable one exists (it replaces the role recipe and must run it itself), otherwise `scripts/dev-update.sh` for the recorded role (`just dev` or `just server`, one step per recipe). Without a recorded role or hook, run `just dev` or `just server` once.
3. **Claude Code**: restarts idle instances in tmux (`tmux/restart-claude.sh`).

Files, in `${XDG_STATE_HOME:-~/.local/state}/dotfiles/update` (mode 700):

- `<timestamp>.log`: output of every step (quiet mode only, exported as `UPDATE_LOG`).
- `<timestamp>.report`: one `WARN <text>`, `ERROR <text>` or `REBOOT <text>` line per finding (exported as `UPDATE_REPORT`, always written; an empty report after exit 0 means a clean run). A caller can preset `UPDATE_REPORT` to read it afterwards: `update` then uses that path, truncated at the start.
- The 14 newest logs and the 14 newest reports are kept.

`update` exits non-zero when a step failed or the report holds an `ERROR`.

Safety:

- A sudo keep-alive refreshes the credentials every 60 seconds during the run, and `sudo -k` runs on exit.
- Quiet steps run with stdin closed, `GIT_TERMINAL_PROMPT=0`, `LC_ALL=C` and a timeout (`UPDATE_STEP_TIMEOUT`, 1800 seconds by default), so nothing waits on a hidden prompt. Steps that may ask something run attached to the terminal: `system` (the upgrade confirmation) and the update hook. `gh-auth` is skipped with a `WARN` when `gh` is not logged in (run `just gh-auth`).
- `scripts/dev-update.sh [dev|server]` reads the steps from the `dev` (or `server`) recipe dependencies in the Justfile (`just --dump`), so the list is declared once.

### Arch system upgrade (quiet mode)

On Arch, `just system` under a quiet `update` does this (`scripts/arch-upgrade.sh`):

1. Previews without root: `checkupdates` refreshes a temporary sync database, then the exact transaction is listed with the installed versions as an aligned `name  old -> new` table and a count (a new dependency shows as `(new) -> version`). Nothing to upgrade prints one line and skips every root step.
2. Shows the unread Arch news (`paru -Pw`) when paru is installed.
3. Asks one question, `Appliquer ? [O/n]` (default yes). Answering no, or having no terminal, skips the upgrade with a `WARN`.
4. Refuses with an `ERROR` when `/var/lib/pacman/db.lck` exists.
5. Runs `pacman -Syu --noconfirm` as a transient systemd unit (`dotfiles-pacman-<timestamp>`) under `systemd-inhibit` (shutdown, sleep and lid switch blocked). The unit survives Ctrl+C, a closed terminal and a logout: the terminal only follows the root-owned log `/var/log/dotfiles/pacman-<timestamp>.log`, and Ctrl+C there stops the following, never the upgrade (the message gives the log to follow).
6. Prints `✓` or `✗`. On failure it shows the conflict and error lines and the root log path. `warning:` lines (notably `.pacnew` and `.pacsave`) become `WARN` lines, and a `REBOOT` line is added when the CachyOS hook says `Reboot is recommended` or the running kernel's modules are gone.
7. Lists the orphan packages on one line, asks once (`Supprimer les orphelins ? [O/n]`) and removes them, output in the run log.

Verbose mode and Debian keep the previous behavior (`apt` or `pacman` with their own prompts, in the foreground). Parity with the apt/pacman rule: every apt call still has its pacman twin; the preview, the uninterruptible unit and the root log exist on Arch only, so a Debian server upgrade is not protected against a closed terminal.

## Shell

zsh + [zinit](https://github.com/zdharma-continuum/zinit) (autosuggestions, syntax-highlighting) + [Starship](https://starship.rs) (prompt) + fzf (`Ctrl+R` / `Ctrl+T` / `Alt+C`) + fastfetch (alias `ff`). The `update` command is described in [The update command](#the-update-command). Keyboard shortcuts (Ctrl+arrows, Home/End, Delete…) come from Oh My Zsh's `key-bindings.zsh` file, loaded on its own through zinit. Every tool comes from mise, with a single config for all machines.

Each machine gets a colored badge (emoji) computed from its hostname, shown in the tab title and in the prompt: no configuration. If two machines collide, rename one of them or add `export MACHINE_BADGE=🟢` to `~/.zshenv` on that machine.

## tmux

On dev machines, tmux keeps sessions alive when the SSH connection drops. mise builds tmux from source (`mise-tmux` plugin, with `build-essential`, `libncurses-dev` and `bison` (Debian) or `base-devel`, `ncurses` and `bison` (Arch) installed by `just build-deps`): the prebuilt binaries from `tmux/tmux-builds` lag weeks behind tmux releases. `tmux/tmux.conf` (linked by `just tmux`) only contains what differs from tmux's defaults. The prefix is **Ctrl+A** (Ctrl+B is used by Claude Code to send a command to the background).

`t` opens or attaches a tmux session. `t .` (or any path, for example `t ~/dev/app`), run from a project (any subfolder of a git repo), opens or attaches the project's session, named after the git root folder, in the first tab. A session about to be created first asks for its layout (fzf, `tmux/layouts.sh`): "Claude + shells" (`Enter` or `w`: Claude Code on the left, two stacked shells on the right), "Claude seul" (`c`) or "Shell seul" (`s`); `Esc` creates nothing. `tmux/workspace.sh <layout> <directory> <session>` builds it. In a new session Claude resumes the folder's last conversation (`claude --continue`), for example after a tmux restart, but only when the folder has one (`~/.claude/projects`), since `--continue` fails otherwise; a tab added to an existing session starts a fresh conversation, so two tabs never share the same one. `t <name>` attaches the session of that name, or creates it if `<name>` is a known project (`~/dev/<name>` or `~/dotfiles`); if there is neither, and `gh` is installed, it clones the GitHub repository of that name into `~/dev/<name>` when the repository is in the cache (name matched case-insensitively, the folder takes the repository's spelling; the layout question comes first, then the clone shows its progress, and a failed clone is an error, never an empty folder); otherwise it creates the project folder `~/dev/<name>` (letters, digits, `_`, `.` and `-`, not starting with `.` or `-`; no `git init`) after the layout question. `Tab` completes sessions, projects and the names of the GitHub repositories not cloned yet. The cache (`~/.cache/dotfiles/github-repositories`) lists your own repositories and your organizations' ones, without archived repositories and forks, through `gh`; it is refreshed in the background when older than 10 minutes, so only the very first use on a machine can wait a few seconds. Decisions come from the cache alone, never from the network. Repositories that already have a session or a folder, `~/dotfiles` and `~/notes` are never offered. Without `gh` (servers), there is no GitHub behavior at all. `t` alone attaches the last session, or opens the session picker when already inside tmux; with no session at all, it opens the picker directly in the terminal, limited to projects: `Enter` creates the chosen project's session (after the layout question) and attaches to it, `Esc` creates nothing. When Claude exits, its pane stays open on a shell. Inside tmux, `t` switches to the session without nesting another one.

tmux boils down to two notions: the session (usually a project) and the tab. `Alt+n` or `Ctrl+A` then `c` opens the "New tab" menu: Claude + shells (`w`), Claude alone (`c`) or shell alone (`s`), in the current pane's folder (`tmux/new-tab-menu.conf`, defined once and reused by the palette; each entry calls `tmux/workspace.sh` with its layout).

`Ctrl+A` then `s` opens a single picker (fzf in a popup): the open sessions as a tree (the current one is marked), each followed by its tabs with the same label as the top bar, then the folders of `~/dev` and `~/dotfiles` without a session, then the GitHub repositories not cloned yet (`<owner>/<name>  (GitHub, à cloner)`, only with `gh`): `Enter` asks the layout, clones into `~/dev/<name>`, then opens the session. The current tab is preselected, the preview shows the targeted tab's pane, and the session name stays filterable from each tab. `Enter` switches to the session or tab, creating the session for a project after the layout question, `Esc` closes without doing anything (`tmux/session-picker.sh`; `just test` checks the session flow on an isolated tmux server, `tmux/session-flow.test.sh`). A name typed in the picker can become a new project: `Enter` on a query that matches nothing, or `Alt+Enter` whatever the matches (the header shows `créer ~/dev/<typed text>`), creates the folder `~/dev/<name>` after the layout question (or clones the repository when the typed name is in the GitHub cache) (same name rule as `t <name>`, no `git init`; an invalid name shows an error; `Esc` at the layout question creates nothing). The native tree of sessions and tabs remains in the palette.

`Ctrl+A` then `n` opens the project's free-form notes in a popup (micro with the Cobalt2 theme, `micro/colorschemes/cobalt2.micro`, linked by `just tmux`; VS Code-style shortcuts: `Ctrl+S` saves, `Ctrl+Q` closes, `Ctrl+C` copies the selection to the workstation's clipboard (OSC 52), autosave, `Ctrl+Z` history kept after closing). The file is `~/notes/<project>.md`, outside the repos; the project is the git root folder of the current pane, created with a title on first use (`tmux/notes.sh`). `~/notes` is a git repo: opening does a pull, each close commits then pushes to the private GitHub repo `notes` created by `just notes`. Commits are signed `notes <notes@localhost>`, an address unknown to GitHub: they do not inflate the profile's contribution graph. On conflict or failure, a tmux message flags it: ask Claude to sync `~/notes`. This key replaces tmux's native `next-window`: `Alt+1` … `Alt+9` switch tabs.

The status bar spans two lines, in Cobalt2 colors: the first lists the sessions (the current one in yellow), the second the tabs, each named after the title of its Claude pane, with a single hint on the right: `Alt+h` (no prefix) opens the cheatsheet of every key. A bell in any pane of the tab turns its tab pink; Claude rings through `claude/hooks/ring-bell.sh` the moment it finishes a turn (not while background tasks or scheduled wakeups are still pending: it rings when it really finishes), when a turn fails, and when it waits for an answer (permission, question); `preferredNotifChannel` is `notifications_disabled` in `claude/settings.json`, so the built-in idle bell, 60s late and blind to background shells, never rings. `Alt+1` … `Alt+9` switch tabs without the prefix, and so do `Alt+&` … `Alt+ç` (the AZERTY number row).

`Alt+g` (no prefix) opens the read-only "Code" menu (`tmux/code-menu.conf`, also in the palette): `d` shows the diff of the work in progress in diffnav (`tmux/code-diff.sh`), which refreshes itself every 2 seconds and includes the new untracked files, ignored files excluded (`tmux/working-tree-diff.sh` prints it); `f` browses the files of the repository with fzf and a bat preview (`tmux/code-files.sh`, `Enter` opens a file full screen, `q` goes back, `Esc` closes); `r` searches the content of the files with ripgrep and fzf (`tmux/code-search.sh`: type to search, a regex is accepted, case-insensitive unless the query has a capital, `Enter` opens the file full screen at the matched line, `q` goes back to the results, `Esc` closes); `c` browses the commits of the current branch with fzf and a delta preview (`tmux/code-log.sh`: type to filter, merge commits are shown against their first parent, `Enter` opens the commit in diffnav, `q` goes back to the list, `Esc` closes). When the repository has several worktrees (those of Claude agents, for instance), each view first asks which one (`tmux/pick-worktree.sh`), the most recently edited first, `Esc` closes. Nothing in these views can modify the repository. In a shell, `git diff`, `git show` and `git log -p` go through delta (`.gitconfig`; `n` / `N` jump to the next / previous file). `diffnav`, `bat`, `ripgrep` and `delta` are installed by mise on dev machines, not on servers.

`Ctrl+A` then `Ctrl+K` opens a command palette (fzf in a popup): the actions of `tmux/palette.tsv` (label, shortcut, tmux command; one action = one line), `Enter` runs the command on the pane the palette was opened from, `Esc` closes (`tmux/command-palette.sh`).

After `update`, Claude Code instances that are already open keep the old binary: the "Restart idle Claude Code" palette action restarts the idle ones with `claude --resume`, skipping those that are working and those already up to date (`tmux/restart-claude.sh`).

The shortcuts live in `tmux/cheatsheet.md`; `Alt+h` (no prefix) opens it in tmux.

`tmux ls` lists the sessions. The mouse is enabled: dragging selects text within a single pane without copying it, `Ctrl+C` or `Enter` copies it to the workstation's clipboard, a click or `Esc` cancels.

## Claude Code

`claude/` holds the Claude Code user config, applied by `just claude` (run by `just dev`):

- **Linked**: the top-level `.md` files of `claude/` (`CLAUDE.md`, `RTK.md`), each file of `claude/agents/` and each folder of `claude/skills/` are linked one by one into `~/.claude/` (`~/.claude/CLAUDE.md`, `~/.claude/RTK.md`, `~/.claude/agents/<name>.md`, `~/.claude/skills/<name>`). The rest of `~/.claude/skills/` (`synced/`, skills installed by `npx skills`, plugins) is left untouched.
- **Merged**: `claude/settings.json` is a base merged (jq) into `~/.claude/settings.json`, never linked: Claude Code rewrites that file itself. The repo's keys win, the machine's own keys (`model`, `theme`…) stay.
- **Plugins and marketplaces**: those declared in `claude/settings.json` (`enabledPlugins`, `extraKnownMarketplaces`) are recorded in `~/.claude/dotfiles-managed.json`. When one is removed from the repo, `just claude` (through `claude/prune-plugins.sh`) runs `claude plugin uninstall` or `claude plugin marketplace remove` and drops its key from `~/.claude/settings.json`. Plugins installed by hand, never declared in the repo, are never touched. If a removal fails (or `claude` is not on the `PATH`), the record is kept and the next `just claude` retries.
- **rtk**: `rtk` (installed by `just mise`) compresses command output before it reaches Claude. The base settings declare its `PreToolUse` hook (`rtk hook claude`) and `CLAUDE.md` imports `RTK.md`: no `rtk init` to run. Do not rerun `rtk init -g` (it would modify `settings.json` and write through the `RTK.md` link); if a new rtk version changes `RTK.md`, regenerate it elsewhere and copy it to `claude/RTK.md`. `rtk/config.toml` is linked to `~/.config/rtk/config.toml` and holds only overrides of rtk's defaults: it excludes `pnpm run lint`, `pnpm lint` and `npm run lint` from the rewrite, because rtk would turn them into `rtk lint`, an ESLint-only run that fails on projects linted with oxlint.
- `claude/statusline.sh` is referenced directly by the base settings: nothing to install. It colors the 5h and 7d usages by pace (usage against the elapsed share of the window, with `+N` points when ahead of it and `-N` when behind it, beyond the tolerance on 5h, always on 7d) and shows the freshest quota values known across sessions instead of each session's own stale ones. A session whose own values just changed is trusted even when they are lower, so a mid-window quota reset shows up. It logs each change of the quota values to `~/.local/state/claude/quota-usage.tsv` (`$XDG_STATE_HOME/claude/` when set), to calibrate the thresholds.
- **Doc and code skill guard**: `claude/hooks/require-skill.sh`, referenced by the base settings (`PreToolUse` hook on `Edit|Write`), refuses any change to a `CLAUDE.md`, `CLAUDE.local.md`, `AGENTS.md` or `.claude/rules/*.md` until the `claude-md` skill has been loaded, to a `README.md`, `docs/**/*.md`, `CONTRIBUTING.md`, `DEPLOY.md`, `PUBLISHING.md` or `SECURITY.md` until the `project-docs` skill has been, and to TypeScript files until `typescript-conventions` has been (plus `react-conventions` for `.tsx`, `adonis-conventions` for `.ts` inside an AdonisJS project, found by its `adonisrc.ts`). Declaration files, `dist/`, `build/`, `.adonisjs/` and `node_modules/` are skipped, and so are `CHANGELOG.md` and `docs/adr/`. A skill counts as loaded when it was invoked in the editing agent's session or preloaded by that agent's definition (`skills:` in `agents/<name>.md`).
- **Context7 guard**: `claude/hooks/require-context7.sh`, referenced by the base settings (`SessionStart` hook, asynchronous, and `UserPromptSubmit` hook), checks with `claude mcp get plugin:context7:context7` that the Context7 server is connected. When its status is not `Connected` (typically a pending OAuth login), the first prompt of the session is blocked with a message asking the user to run `/mcp`; sending the message again goes through. It blocks once per session, so a Context7 outage never locks the user out, and does nothing when the status cannot be determined (no `claude` on the `PATH`, error, 10 s timeout).

Before replacing anything, `just claude` moves what exists to `~/.claude/backups/dotfiles-<date>/` (same relative path) and prints each backup. Nothing is deleted, except links to the repo that became orphaned (skill or agent removed from the repo).

- **Removing a setting**: the merge only adds and overwrites. A key removed from `claude/settings.json` (other than plugins and marketplaces) is removed by hand from `~/.claude/settings.json`.
- **Adding a skill or an agent**: create it in `claude/skills/<name>/SKILL.md` or `claude/agents/<name>.md`, then `just claude`.
- **Outside the repo**: skills installed by `npx skills` or by plugins stay outside the repo.
- Only machine-independent, non-sensitive settings go in `claude/settings.json`.

`c` opens agent view (`claude agents`, background sessions) from `~/dev`, so typing `@` in a prompt lists the projects to dispatch the session to; the shell's current folder does not change. Its arguments go to `claude agents` (for example `c --cwd ~/dev/app`). `Enter` on a row opens the session and `←` goes back to the list, so there is no separate `attach` shortcut. The base settings keep transcripts for 10 years (`cleanupPeriodDays: 3650`, since `0` is refused): a session deleted from the list stays readable and resumable with `claude --resume`.

## Security

The repo is public and **never** contains a secret, an identity or server info:

- **SSH key**: only in Bitwarden, on your local machines. Locked vault = no connection possible. A lost machine = sign out of Bitwarden on it.
- **Connections**: in Bitwarden and in `~/.ssh/config` on your local machines, never in the repo.
- **Git identity**: set in each repo. `.gitconfig` also includes `~/.gitconfig.local`, optional and specific to each machine, for a default identity.
- **GitHub**: `gh` token on dev machines only (local machines included). It goes into the system keyring if there is one, otherwise in plain text in `~/.config/gh/hosts.yml`. No SSH key for GitHub: `.gitconfig` rewrites `git@github.com:` remotes to HTTPS, so repos cloned over SSH also go through `gh`, without changing their remote.
- **gitleaks** runs as a pre-commit hook (`githooks/pre-commit`, enabled by `just git`) and blocks any secret trying to get in. The same hook lints staged shell scripts with shellcheck.

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

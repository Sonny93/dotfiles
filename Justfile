home := env_var('HOME')
dotfiles := home + '/dotfiles'
shell_tools := 'starship fzf just fastfetch'

[private]
default: help

# List available targets
help:
    @just --list --unsorted

# Set up or update a dev machine (the XPS included)
dev: apt shell mise git gh-auth claude doctor-dev
    #!/usr/bin/env bash
    echo "Dev setup done. Reload the shell with 'exec zsh'."

alias xps := dev

# Set up or update a server
server: apt shell doctor-server
    #!/usr/bin/env bash
    echo "Server setup done. Reload the shell with 'exec zsh'."

# Upgrade system packages
apt:
    #!/usr/bin/env bash
    set -e
    sudo apt update
    sudo apt full-upgrade
    sudo apt autoremove

# Set up zsh, Starship and the mise tools the shell needs
shell:
    #!/usr/bin/env bash
    set -e
    if ! command -v zsh >/dev/null 2>&1; then
        echo "ERROR: zsh is not installed. Run 'sudo apt install zsh' first."
        exit 1
    fi
    mkdir -p {{home}}/.config/mise
    ln -sf {{dotfiles}}/.zshrc {{home}}/.zshrc
    ln -sf {{dotfiles}}/starship.toml {{home}}/.config/starship.toml
    ln -sf {{dotfiles}}/mise/config.toml {{home}}/.config/mise/config.toml
    mise trust {{dotfiles}}/mise/config.toml
    mise install {{shell_tools}}
    mise upgrade {{shell_tools}}
    login_shell="$(getent passwd "$USER" | cut -d: -f7)"
    if [ "$(basename "$login_shell")" != "zsh" ]; then
        echo "Login shell is $login_shell. Make zsh the default with:"
        echo "    chsh -s \"\$(command -v zsh)\""
    fi
    echo "Shell setup done."

# Install or upgrade every tool from mise/config.toml
mise:
    #!/usr/bin/env bash
    set -e
    mise self-update -y
    mise install
    mise upgrade
    echo "Tools installed/updated via mise."

# Wire the repo git config and gitleaks hook
git:
    #!/usr/bin/env bash
    if [ ! -f "{{home}}/.gitconfig" ]; then
        echo "# Main Git configuration" > {{home}}/.gitconfig
    fi
    if ! grep -q "path = {{dotfiles}}/.gitconfig" {{home}}/.gitconfig; then
        printf "\n# Include custom .gitconfig\n[include]\n    path = {{dotfiles}}/.gitconfig\n" >> {{home}}/.gitconfig
        echo "Custom .gitconfig include added."
    else
        echo "Custom .gitconfig include already present."
    fi
    git -C {{dotfiles}} config core.hooksPath {{dotfiles}}/githooks
    chmod +x {{dotfiles}}/githooks/pre-commit
    echo "Git hooksPath set to {{dotfiles}}/githooks"
    if [ ! -f "{{home}}/.gitconfig.local" ]; then
        echo "INFO: no ~/.gitconfig.local, set the git identity per repo (or add a [user] section there for a machine default)."
    fi

# Log in to GitHub with gh and use it for git over HTTPS
gh-auth:
    #!/usr/bin/env bash
    if [ -n "${GITHUB_TOKEN:-}" ]; then
        echo "GITHUB_TOKEN still exported this shell — unset it, reload .zshrc, retry."
        exit 1
    fi
    if ! gh auth status >/dev/null 2>&1; then
        echo "No gh auth found, launching 'gh auth login'..."
        gh auth login
    else
        echo "gh already authenticated:"
        gh auth status
    fi
    gh config set git_protocol https
    for host in github.com gist.github.com; do
        git config --global --replace-all "credential.https://$host.helper" ''
        git config --global --add "credential.https://$host.helper" '!gh auth git-credential'
    done
    echo "git uses gh for GitHub over HTTPS."

# Link the Claude Code config (CLAUDE.md, agents, skills) and merge the base settings
claude:
    #!/usr/bin/env bash
    set -euo pipefail
    repo_config="{{dotfiles}}/claude"
    claude_home="{{home}}/.claude"
    base_settings="$repo_config/settings.json"
    local_settings="$claude_home/settings.json"
    backup_dir="$claude_home/backups/dotfiles-$(date +%Y%m%d-%H%M%S)"

    require_jq() {
        if ! command -v jq >/dev/null 2>&1; then
            echo "ERROR: jq is not installed. Run 'just mise' first."
            exit 1
        fi
    }

    backup_path() {
        local path="$1"
        local backup_path_target="$backup_dir/${path#"$claude_home"/}"
        mkdir -p "$(dirname "$backup_path_target")"
        mv "$path" "$backup_path_target"
        echo "Backed up $path -> $backup_path_target"
    }

    link_into() {
        local target="$1" link="$2"
        if [ "$(readlink "$link")" = "$target" ]; then
            return 0
        fi
        if [ -e "$link" ] || [ -L "$link" ]; then
            backup_path "$link"
        fi
        ln -s "$target" "$link"
        echo "Linked $link -> $target"
    }

    link_repo_entries() {
        local agent skill
        link_into "$repo_config/CLAUDE.md" "$claude_home/CLAUDE.md"
        for agent in "$repo_config"/agents/*.md; do
            link_into "$agent" "$claude_home/agents/$(basename "$agent")"
        done
        for skill in "$repo_config"/skills/*/; do
            skill="${skill%/}"
            link_into "$skill" "$claude_home/skills/$(basename "$skill")"
        done
    }

    prune_dangling_links() {
        local directory="$1" link
        for link in "$directory"/*; do
            [ -L "$link" ] || continue
            [ -e "$link" ] && continue
            case "$(readlink "$link")" in
                "$repo_config"/*) ;;
                *) continue ;;
            esac
            rm "$link"
            echo "Removed dangling link $link"
        done
    }

    compute_merged_settings() {
        if [ ! -f "$local_settings" ]; then
            jq . "$base_settings"
            return 0
        fi
        jq -s '.[0] * .[1]' "$local_settings" "$base_settings"
    }

    merge_settings() {
        local merged temporary_file
        merged="$(compute_merged_settings)"
        if [ -f "$local_settings" ] && [ "$(jq -S . "$local_settings")" = "$(jq -S . <<<"$merged")" ]; then
            echo "settings.json already up to date."
            return 0
        fi
        if [ -f "$local_settings" ]; then
            mkdir -p "$backup_dir"
            cp -p "$local_settings" "$backup_dir/settings.json"
            echo "Backed up $local_settings -> $backup_dir/settings.json"
        fi
        temporary_file="$(mktemp "$claude_home/settings.json.XXXXXX")"
        chmod 600 "$temporary_file"
        printf '%s\n' "$merged" >"$temporary_file"
        mv "$temporary_file" "$local_settings"
        echo "Merged base settings into $local_settings"
    }

    eval "$(mise env -s bash)"
    require_jq
    jq empty "$base_settings"
    mkdir -p "$claude_home/agents" "$claude_home/skills"
    link_repo_entries
    prune_dangling_links "$claude_home/agents"
    prune_dangling_links "$claude_home/skills"
    merge_settings
    echo "Claude Code config linked."

# Check the shell setup (servers and dev machines)
doctor-server:
    #!/usr/bin/env bash
    source {{dotfiles}}/scripts/status.sh
    if command -v zsh >/dev/null 2>&1; then
        ok "zsh installed"
    else
        warn "zsh missing, run 'sudo apt install zsh' then 'just shell'"
    fi
    login_shell="$(getent passwd "$USER" | cut -d: -f7)"
    if [ "$(basename "$login_shell")" = "zsh" ]; then
        ok "login shell is zsh"
    else
        warn "login shell is $login_shell, run 'chsh -s \"\$(command -v zsh)\"'"
    fi
    check_link "{{home}}/.zshrc" "{{dotfiles}}/.zshrc" shell
    check_link "{{home}}/.config/starship.toml" "{{dotfiles}}/starship.toml" shell
    check_link "{{home}}/.config/mise/config.toml" "{{dotfiles}}/mise/config.toml" shell
    if command -v mise >/dev/null 2>&1; then
        ok "mise on PATH"
    else
        warn "mise not on PATH, install mise then run 'just shell'"
    fi
    for tool in {{shell_tools}}; do
        if mise which "$tool" >/dev/null 2>&1; then
            ok "$tool installed via mise"
        else
            warn "$tool missing, run 'just shell'"
        fi
    done

# Check the full dev machine setup
doctor-dev: doctor-server
    #!/usr/bin/env bash
    source {{dotfiles}}/scripts/status.sh
    if [ -n "${GITHUB_TOKEN:-}" ]; then
        warn "GITHUB_TOKEN still exported, unset it and reload .zshrc"
    else
        ok "no GITHUB_TOKEN"
    fi
    if gh auth status >/dev/null 2>&1; then
        ok "gh authenticated"
    else
        warn "gh not authenticated, run 'just gh-auth'"
    fi
    if [ "$(git config --global --get-all credential.https://github.com.helper | tail -n 1)" = '!gh auth git-credential' ] && [ "$(gh config get git_protocol)" = "https" ]; then
        ok "git and gh use HTTPS through gh"
    else
        warn "git credential helper or gh protocol not set, run 'just gh-auth'"
    fi
    if [ "$(git ls-remote --get-url git@github.com:Sonny93/dotfiles)" = "https://github.com/Sonny93/dotfiles" ]; then
        ok "GitHub SSH remotes rewritten to HTTPS"
    else
        warn "GitHub SSH remotes not rewritten to HTTPS, run 'just git'"
    fi
    if grep -q "path = {{dotfiles}}/.gitconfig" {{home}}/.gitconfig 2>/dev/null; then
        ok "~/.gitconfig includes the repo config"
    else
        warn "~/.gitconfig does not include the repo config, run 'just git'"
    fi
    if [ -f {{home}}/.gitconfig.local ]; then
        ok "~/.gitconfig.local present"
    else
        info "no ~/.gitconfig.local, git identity is set per repo"
    fi
    if [ "$(git -C {{dotfiles}} config core.hooksPath)" = "{{dotfiles}}/githooks" ]; then
        ok "git hooks wired"
    else
        warn "git hooks not wired, run 'just git'"
    fi
    eval "$(mise env -s bash)"
    claude_home="{{home}}/.claude"
    repo_config="{{dotfiles}}/claude"
    check_link "$claude_home/CLAUDE.md" "$repo_config/CLAUDE.md" claude
    for agent in "$repo_config"/agents/*.md; do
        check_link "$claude_home/agents/$(basename "$agent")" "$agent" claude
    done
    for skill in "$repo_config"/skills/*/; do
        skill="${skill%/}"
        check_link "$claude_home/skills/$(basename "$skill")" "$skill" claude
    done
    for link in "$claude_home"/agents/* "$claude_home"/skills/*; do
        [ -L "$link" ] && [ ! -e "$link" ] || continue
        case "$(readlink "$link")" in
            "$repo_config"/*) warn "$link is a dangling link into the repo, run 'just claude'" ;;
        esac
    done
    if [ ! -f "$claude_home/settings.json" ]; then
        warn "$claude_home/settings.json missing, run 'just claude'"
    elif ! command -v jq >/dev/null 2>&1; then
        warn "jq missing, run 'just mise'"
    elif [ "$(jq -S --slurpfile base "$repo_config/settings.json" '. * $base[0]' "$claude_home/settings.json")" = "$(jq -S . "$claude_home/settings.json")" ]; then
        ok "Claude Code settings contain the base settings"
    else
        warn "Claude Code settings differ from the base settings, run 'just claude'"
    fi
    missing_tools="$(mise ls --global --missing)"
    if [ -z "$missing_tools" ]; then
        ok "every mise tool installed"
    else
        warn "mise tools missing, run 'just mise':"
        echo "$missing_tools"
    fi

# Remove a leftover Oh My Zsh / Powerlevel10k install
uninstall-omz:
    #!/usr/bin/env bash
    echo "Will remove:"
    echo "  {{home}}/.oh-my-zsh          (full OMZ install, incl. P10k theme + dead starship-plugin stub)"
    echo "  {{home}}/.p10k.zsh"
    echo "  {{home}}/.cache/p10k-*       (instant-prompt cache + dumps)"
    read -p "Confirm? [y/N] " confirm
    if [ "$confirm" = "y" ]; then
        rm -rf {{home}}/.oh-my-zsh
        rm -f {{home}}/.p10k.zsh
        rm -rf {{home}}/.cache/p10k-*
        echo "Removed."
    else
        echo "Aborted."
    fi

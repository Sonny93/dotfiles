home := env_var('HOME')
dotfiles := home + '/dotfiles'
shell_tools := 'starship fzf just fastfetch'

[private]
default: help

# List available targets
help:
    @just --list --unsorted

# Set up or update a dev machine (the XPS included)
dev: apt shell mise git gh-auth doctor-dev
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
    gh auth setup-git

# Check the shell setup (servers and dev machines)
doctor-server:
    #!/usr/bin/env bash
    check_link() {
        local link="$1" target="$2"
        if [ "$(readlink "$link")" = "$target" ]; then
            echo "OK: $link -> $target"
        else
            echo "WARN: $link is not a symlink to $target, run 'just shell'"
        fi
    }
    if command -v zsh >/dev/null 2>&1; then
        echo "OK: zsh installed"
    else
        echo "WARN: zsh missing, run 'sudo apt install zsh' then 'just shell'"
    fi
    login_shell="$(getent passwd "$USER" | cut -d: -f7)"
    if [ "$(basename "$login_shell")" = "zsh" ]; then
        echo "OK: login shell is zsh"
    else
        echo "WARN: login shell is $login_shell, run 'chsh -s \"\$(command -v zsh)\"'"
    fi
    check_link "{{home}}/.zshrc" "{{dotfiles}}/.zshrc"
    check_link "{{home}}/.config/starship.toml" "{{dotfiles}}/starship.toml"
    check_link "{{home}}/.config/mise/config.toml" "{{dotfiles}}/mise/config.toml"
    if command -v mise >/dev/null 2>&1; then
        echo "OK: mise on PATH"
    else
        echo "WARN: mise not on PATH, install mise then run 'just shell'"
    fi
    for tool in {{shell_tools}}; do
        if mise which "$tool" >/dev/null 2>&1; then
            echo "OK: $tool installed via mise"
        else
            echo "WARN: $tool missing, run 'just shell'"
        fi
    done

# Check the full dev machine setup
doctor-dev: doctor-server
    #!/usr/bin/env bash
    if [ -n "${GITHUB_TOKEN:-}" ]; then
        echo "WARN: GITHUB_TOKEN still exported, unset it and reload .zshrc"
    else
        echo "OK: no GITHUB_TOKEN"
    fi
    if gh auth status >/dev/null 2>&1; then
        echo "OK: gh authenticated"
    else
        echo "WARN: gh not authenticated, run 'just gh-auth'"
    fi
    if grep -q "path = {{dotfiles}}/.gitconfig" {{home}}/.gitconfig 2>/dev/null; then
        echo "OK: ~/.gitconfig includes the repo config"
    else
        echo "WARN: ~/.gitconfig does not include the repo config, run 'just git'"
    fi
    if [ -f {{home}}/.gitconfig.local ]; then
        echo "OK: ~/.gitconfig.local present"
    else
        echo "INFO: no ~/.gitconfig.local, git identity is set per repo"
    fi
    if [ "$(git -C {{dotfiles}} config core.hooksPath)" = "{{dotfiles}}/githooks" ]; then
        echo "OK: git hooks wired"
    else
        echo "WARN: git hooks not wired, run 'just git'"
    fi
    missing_tools="$(mise ls --global --missing)"
    if [ -z "$missing_tools" ]; then
        echo "OK: every mise tool installed"
    else
        echo "WARN: mise tools missing, run 'just mise':"
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

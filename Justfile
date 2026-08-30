home := env_var('HOME')
dotfiles := home + '/dotfiles'

apply: gitconfig bash-aliases zshrc mise-config tools starship

gitconfig:
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

bash-aliases:
    #!/usr/bin/env bash
    if ! grep -q "source {{dotfiles}}/.bash_aliases" {{home}}/.zshrc 2>/dev/null; then
        printf "\n[ -f {{dotfiles}}/.bash_aliases ] && source {{dotfiles}}/.bash_aliases\n" >> {{home}}/.zshrc
        echo "bash_aliases import added."
    else
        echo "bash_aliases import already present."
    fi

zshrc:
    #!/usr/bin/env bash
    ln -sf {{dotfiles}}/.zshrc {{home}}/.zshrc
    echo "Symlink created for .zshrc"

mise-config:
    #!/usr/bin/env bash
    mkdir -p {{home}}/.config/mise
    ln -sf {{dotfiles}}/mise/config.toml {{home}}/.config/mise/config.toml
    mise trust {{dotfiles}}/mise/config.toml
    echo "Symlink created for mise config.toml"

tools:
    #!/usr/bin/env bash
    mise self-update -y
    mise install
    mise upgrade
    echo "Tools installed/updated via mise."

starship:
    #!/usr/bin/env bash
    mkdir -p {{home}}/.config
    ln -sf {{dotfiles}}/starship.toml {{home}}/.config/starship.toml
    echo "Symlink created for starship.toml"

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

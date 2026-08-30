home := env_var('HOME')
dotfiles := home + '/dotfiles'

apply: gitconfig zshrc mise-config tools starship tabby githooks

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

tabby:
    #!/usr/bin/env bash
    mkdir -p {{home}}/.config/tabby
    if [ ! -f {{home}}/.config/tabby/config.yaml ]; then
        cp {{dotfiles}}/tabby/config.yaml {{home}}/.config/tabby/config.yaml
        echo "Tabby config seeded. Add SSH profiles locally in-app — never committed."
    else
        echo "Local Tabby config.yaml already exists, left untouched."
    fi

tabby-export:
    #!/usr/bin/env bash
    python3 {{dotfiles}}/scripts/tabby_export.py {{home}}/.config/tabby/config.yaml {{dotfiles}}/tabby/config.yaml
    echo "Shared Tabby settings exported to repo, profiles/hosts stripped."

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

githooks:
    #!/usr/bin/env bash
    git config core.hooksPath {{dotfiles}}/githooks
    chmod +x {{dotfiles}}/githooks/pre-commit
    echo "Git hooksPath set to {{dotfiles}}/githooks"

doctor:
    #!/usr/bin/env bash
    [ -n "${GITHUB_TOKEN:-}" ] && echo "WARN: GITHUB_TOKEN still exported" || echo "OK: no GITHUB_TOKEN"
    gh auth status >/dev/null 2>&1 && echo "OK: gh authenticated" || echo "WARN: gh not authenticated, run 'just gh-auth'"
    [ -f {{home}}/.gitconfig.local ] && echo "OK: ~/.gitconfig.local present" || echo "WARN: no ~/.gitconfig.local, git commits will fail until set"
    command -v starship >/dev/null 2>&1 && echo "OK: starship" || echo "WARN: starship missing, run 'just tools'"
    command -v fzf >/dev/null 2>&1 && echo "OK: fzf" || echo "WARN: fzf missing, run 'just tools'"
    command -v gitleaks >/dev/null 2>&1 && echo "OK: gitleaks" || echo "WARN: gitleaks missing, run 'just tools'"
    [ "$(git config core.hooksPath)" = "{{dotfiles}}/githooks" ] && echo "OK: git hooks wired" || echo "WARN: run 'just githooks'"

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

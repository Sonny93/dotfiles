home := env_var('HOME')
dotfiles := home + '/dotfiles'

apply: gitconfig npmrc bash-aliases

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

npmrc:
    ln -sf {{dotfiles}}/.npmrc {{home}}/.npmrc
    echo "Symlink created for .npmrc"

bash-aliases:
    #!/usr/bin/env bash
    if ! grep -q "source {{dotfiles}}/.bash_aliases" {{home}}/.zshrc; then
        printf "\n[ -f {{dotfiles}}/.bash_aliases ] && source {{dotfiles}}/.bash_aliases\n" >> {{home}}/.zshrc
        echo "bash_aliases import added."
    else
        echo "bash_aliases import already present."
    fi

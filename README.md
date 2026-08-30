### Setup

Il faut clone ce repo dans $HOME

```sh
git clone git@github.com:Sonny93/dotfiles
```

Puis appliquer les fichiers et outils :

```sh
just apply
```

/!\ On laisse tout dans le dossier original

### Détail des targets

- `just apply` — symlinks (`.zshrc`, `.gitconfig`, `mise/config.toml`, `starship.toml`) + install/update des outils via mise
- `just tools` — installe/upgrade les outils listés dans `mise/config.toml` (idempotent, safe à relancer)
- `just uninstall-omz` — désinstalle proprement Oh My Zsh / Powerlevel10k (liste ce qui sera supprimé avant confirmation)

### Shell

zsh + [zinit](https://github.com/zdharma-continuum/zinit) (autosuggestions, syntax-highlighting) + [Starship](https://starship.rs) (prompt) + fzf (`ctrl+r`/`ctrl+t`/`alt+c` via `fzf --zsh`). Tous les binaires (starship, fzf, node, gh, rust, ...) sont gérés par [mise](https://mise.jdx.dev), config dans `mise/config.toml`.

### MOTD

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

### Pour tabby

> precmd () { echo -n "\x1b]1337;CurrentDir=$(pwd)\x07" }

Déjà inclus dans `.zshrc`. Source https://github.com/Eugeny/tabby/wiki/Shell-working-directory-reporting

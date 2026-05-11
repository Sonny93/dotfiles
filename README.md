### Setup

Il faut clone ce repo dans $HOME

```sh
git clone git@github.com:Sonny93/dotfiles
```

Suivre le guide d'installation zsh/Oh My Zsh/Powerlevel10k : [docs/ohmyzsh-p10k-debian13.md](docs/ohmyzsh-p10k-debian13.md)

Puis appliquer les nouveaux fichiers

```sh
make apply
```

/!\ On laisse tout dans le dossier original

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

### Pour changer comportement par défaut de CD

Faut modifier dans ~/.zshrc, à la toute fin

```
cd() {
  if [ $# -eq 0 ]; then
    builtin cd ~/dev
  else
    builtin cd "$@"
  fi
}

if [[ $SHLVL -eq 1 ]]; then
  cd ~/dev
fi
```

### Pour tabby

> precmd () { echo -n "\x1b]1337;CurrentDir=$(pwd)\x07" }

Source https://github.com/Eugeny/tabby/wiki/Shell-working-directory-reporting
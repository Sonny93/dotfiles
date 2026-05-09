# Oh My Zsh + Powerlevel10k sur Debian 13

## 1. Prérequis — installer zsh

```zsh
sudo apt update && sudo apt upgrade -y
sudo apt install -y zsh git curl wget fontconfig
```

Définir zsh comme shell par défaut :

```zsh
chsh -s $(which zsh)
```

> Déconnectez-vous puis reconnectez-vous pour que le changement prenne effet.

Vérifier :

```zsh
zsh --version
```

---

## 2. Installer Oh My Zsh

```zsh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
```

> Répondre **Y** quand le script demande si vous voulez changer de shell.  
> L'ancien `~/.zshrc` est sauvegardé en `~/.zshrc.pre-oh-my-zsh`.

---

## 3. Installer la police MesloLGS NF

Créer le dossier et télécharger les 4 variantes :

```zsh
mkdir -p ~/.local/share/fonts/MesloLGS
cd ~/.local/share/fonts/MesloLGS

wget "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Regular.ttf"
wget "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Bold.ttf"
wget "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Italic.ttf"
wget "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Bold%20Italic.ttf"

fc-cache -fv
```

### Configurer la police dans le terminal

| Terminal | Chemin |
|----------|--------|
| GNOME Terminal | Profil → Texte → Police personnalisée → `MesloLGS NF` |
| **Tabby** | Settings → Appearance → Font → `MesloLGS NF` |
| Kitty | `font_family MesloLGS NF` dans `~/.config/kitty/kitty.conf` |
| Alacritty | `family: "MesloLGS NF"` dans `~/.config/alacritty/alacritty.yml` |

Si la police n'apparaît pas dans Tabby, forcer dans `~/.config/tabby/config.yaml` :

```yaml
terminal:
  font: MesloLGS NF
  fontSize: 14
```

---

## 4. Installer Powerlevel10k

```zsh
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git \
  ~/.oh-my-zsh/custom/themes/powerlevel10k
```

Activer le thème dans `~/.zshrc` :

```zsh
sed -i 's/ZSH_THEME=.*/ZSH_THEME="powerlevel10k\/powerlevel10k"/' ~/.zshrc
source ~/.zshrc
```

Vérifier que la ligne est bien présente :

```zsh
grep ZSH_THEME ~/.zshrc
# ZSH_THEME="powerlevel10k/powerlevel10k"
```

> L'assistant de configuration se lance automatiquement au premier démarrage.  
> Pour le relancer manuellement : `p10k configure`

---

## 5. Installer les plugins

### zsh-autosuggestions et zsh-syntax-highlighting

```zsh
git clone https://github.com/zsh-users/zsh-autosuggestions \
  ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions

git clone https://github.com/zsh-users/zsh-syntax-highlighting.git \
  ~/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting
```

Activer les plugins dans `~/.zshrc` :

```zsh
sed -i 's/^plugins=(.*/plugins=(git sudo debian zsh-autosuggestions zsh-syntax-highlighting)/' ~/.zshrc
source ~/.zshrc
```

---

## 6. Désactiver l'underline de zsh-syntax-highlighting

Ajouter ce bloc **tout à la fin** de `~/.zshrc` (après `source $ZSH/oh-my-zsh.sh`) :

```zsh
# Supprimer underline zsh-syntax-highlighting
for style in ${(k)ZSH_HIGHLIGHT_STYLES}; do
  ZSH_HIGHLIGHT_STYLES[$style]=${ZSH_HIGHLIGHT_STYLES[$style]//,underline/}
  ZSH_HIGHLIGHT_STYLES[$style]=${ZSH_HIGHLIGHT_STYLES[$style]//underline,/}
  ZSH_HIGHLIGHT_STYLES[$style]=${ZSH_HIGHLIGHT_STYLES[$style]//underline/}
done
```

```zsh
source ~/.zshrc
```

> Le bloc doit être à la fin du fichier — s'il est placé avant le chargement
> des plugins, il n'a aucun effet au démarrage d'une nouvelle session.

---

## 7. Vérification finale

```zsh
echo $SHELL        # /usr/bin/zsh
p10k version       # v1.x.x
```

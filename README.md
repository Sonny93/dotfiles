# dotfiles

zsh, git, mise, Starship et Tabby, pour deux types de machines :

- **PC** : Windows 11 (seulement Tabby + Bitwarden) et le XPS sous Debian 13 (tout).
- **Serveurs / VPS** : Debian, shell seulement. Pas de clé privée, pas de compte GitHub, rien à voler.

## Sommaire

- [Où vit quoi](#où-vit-quoi)
- [PC](#pc)
  - [Une seule fois : la clé SSH](#une-seule-fois--la-clé-ssh)
  - [Windows 11](#windows-11)
  - [XPS (Debian 13)](#xps-debian-13)
  - [Ajouter une connexion](#ajouter-une-connexion)
  - [Mettre à jour le XPS](#mettre-à-jour-le-xps)
- [Serveur / VPS](#serveur--vps)
  - [Installer](#installer)
  - [Mettre à jour un serveur](#mettre-à-jour-un-serveur)
- [Commandes](#commandes)
- [Shell](#shell)
- [Tabby](#tabby)
- [Sécurité](#sécurité)
- [MOTD](#motd)

## Où vit quoi

| Quoi | Où | Dans le repo |
|---|---|---|
| Clé SSH privée | Bitwarden, servie par son agent SSH | Jamais |
| Connexions SSH | `~/.ssh/config` sur chaque PC, copie dans une note Bitwarden | Jamais |
| Réglages Tabby (thème, police, raccourcis) | `tabby/config.yaml` | Oui |
| Identité git | Chaque repo (`.git/config`), ou `~/.gitconfig.local` en option | Jamais |
| Accès GitHub | Jeton `gh` sur le XPS | Jamais |

Le repo est public : on le clone en HTTPS, sans clé ni compte.

## PC

### Une seule fois : la clé SSH

1. Dans Bitwarden, créer un élément **Clé SSH** (Ed25519). La clé privée ne quittera jamais le coffre.
2. Créer une note sécurisée **ssh config** avec la liste des connexions, au format `~/.ssh/config` :

   ```
   Host mon-serveur
       HostName 203.0.113.10

   Host *
       User sonny
       ServerAliveInterval 5
       ServerAliveCountMax 10
   ```

   Pas de `IdentityFile` : `ssh` et Tabby demandent la clé à l'agent Bitwarden.

### Windows 11

1. Installer **Bitwarden Desktop**, se connecter, puis dans les réglages activer **l'agent SSH**.
2. Couper l'agent SSH de Windows, qui entre en conflit avec celui de Bitwarden (PowerShell **admin**) :

   ```powershell
   Stop-Service ssh-agent
   Set-Service ssh-agent -StartupType Disabled
   ```

3. Créer `C:\Users\<user>\.ssh\config` (sans extension) avec le contenu de la note **ssh config**.
4. Tabby cherche ce fichier via la variable `HOME`, absente par défaut sous Windows :

   ```powershell
   [Environment]::SetEnvironmentVariable("HOME", $env:USERPROFILE, "User")
   ```

5. Installer **Tabby**, le lancer une fois, le fermer complètement (icône de la barre des tâches comprise), puis, depuis Windows Terminal (pas depuis Tabby) :

   ```powershell
   irm https://raw.githubusercontent.com/Sonny93/dotfiles/main/tabby/install.ps1 | iex
   ```

   Voir [Tabby](#tabby) pour ce que fait le script.

6. Vérifier : `ssh-add -L` affiche la clé Bitwarden, et Tabby liste les connexions sous la forme `mon-serveur (.ssh/config)`.

### XPS (Debian 13)

1. Paquets de base :

   ```sh
   sudo apt install git curl zsh
   ```

2. Installer **Bitwarden Desktop** en `.deb` (pas en Flatpak ni Snap : l'agent SSH n'y crée pas son socket), se connecter, activer **l'agent SSH**. Puis l'annoncer à toute la session graphique (Tabby compris), et se déconnecter / reconnecter :

   ```sh
   mkdir -p ~/.config/environment.d
   echo 'SSH_AUTH_SOCK=${HOME}/.bitwarden-ssh-agent.sock' > ~/.config/environment.d/bitwarden-ssh-agent.conf
   ```

3. Cloner le repo et installer [mise](https://mise.jdx.dev). Le chemin `~/dotfiles` est codé en dur :

   ```sh
   git clone https://github.com/Sonny93/dotfiles ~/dotfiles
   curl https://mise.run | sh
   export PATH="$HOME/.local/bin:$PATH"
   ```

4. Shell :

   ```sh
   cd ~/dotfiles
   mise exec just -- just shell
   chsh -s "$(command -v zsh)"
   exec zsh
   ```

5. Connexions : créer `~/.ssh/config` avec le contenu de la note **ssh config**.
6. Tabby : installer Tabby, le lancer une fois, le fermer complètement, puis `just tabby` depuis un autre terminal que Tabby.
7. Tout le reste, vérification comprise :

   ```sh
   just xps
   ```

   `just xps` enchaîne `apt`, `shell`, `mise` (tous les outils), `git` (config du repo + hook gitleaks), `gh-auth` (accès GitHub) puis `doctor`, qui ne doit afficher que des lignes `OK` / `INFO`.

   Pas d'identité git par défaut : on la définit dans chaque repo (`git config user.name` / `user.email`). Pour une identité par défaut sur la machine, la mettre dans `~/.gitconfig.local` (section `[user]`).

### Ajouter une connexion

1. Donner la clé publique au serveur (voir [Serveur / VPS](#installer)).
2. Ajouter le `Host` dans la note **ssh config** de Bitwarden, puis dans `~/.ssh/config` de chaque PC. Tabby l'affiche au prochain lancement.

### Mettre à jour le XPS

```sh
cd ~/dotfiles && git pull
just xps
exec zsh
```

Si `tabby/config.yaml` a changé : réinstaller Tabby (voir [Tabby](#tabby)).

## Serveur / VPS

### Installer

1. **Donner la clé publique au serveur.** C'est la serrure, pas la clé : elle peut être lue sans risque.
   - VPS neuf : coller la clé publique (copiée depuis Bitwarden) dans le formulaire de l'hébergeur.
   - Serveur existant, depuis un PC (PowerShell ou XPS), avec une connexion par mot de passe :

     ```sh
     ssh-add -L | ssh user@host "umask 077; mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys"
     ```

2. Ajouter la connexion sur les PC (voir [Ajouter une connexion](#ajouter-une-connexion)).
3. Sur le serveur :

   ```sh
   sudo apt install git curl zsh
   git clone https://github.com/Sonny93/dotfiles ~/dotfiles
   curl https://mise.run | sh
   export PATH="$HOME/.local/bin:$PATH"
   cd ~/dotfiles
   mise exec just -- just shell
   chsh -s "$(command -v zsh)"
   exec zsh
   just server
   ```

   `just server` enchaîne `apt`, `shell` puis `doctor-server`. `just shell` n'installe que les outils dont le shell a besoin (starship, fzf, just, fastfetch), pas toute la config mise.

À ne jamais faire sur un serveur : y mettre la clé privée, s'y connecter à GitHub, ou activer `ForwardAgent` vers lui (root sur le serveur pourrait utiliser ta clé tant que tu es connecté).

### Mettre à jour un serveur

```sh
cd ~/dotfiles && git pull
just server
exec zsh
```

## Commandes

`just` ou `just help` liste les commandes.

| Commande | Rôle | XPS | Serveur |
|---|---|---|---|
| `just xps` | Installer / mettre à jour le XPS (PC Debian) : `apt`, `shell`, `mise`, `git`, `gh-auth`, `doctor` (sans Tabby) | ✓ | |
| `just server` | Installer / mettre à jour un serveur : `apt`, `shell`, `doctor-server` | | ✓ |
| `just apt` | Mettre à jour les paquets système | ✓ | ✓ |
| `just shell` | zsh, Starship et les outils mise du shell | ✓ | ✓ |
| `just mise` | Installer / mettre à jour tous les outils de `mise/config.toml` | ✓ | |
| `just git` | Config git du repo + hook gitleaks | ✓ | |
| `just gh-auth` | Connexion GitHub via `gh`, utilisée par git en HTTPS | ✓ | |
| `just tabby` | Installer la config Tabby du repo (Tabby fermé), en gardant profil par défaut et hosts connus | ✓ | |
| `just doctor-server` | Vérifier le shell | ✓ | ✓ |
| `just doctor` | Vérifier tout le XPS (lance aussi `doctor-server`) | ✓ | |
| `just uninstall-omz` | Supprimer une ancienne install Oh My Zsh / Powerlevel10k | | |

## Shell

zsh + [zinit](https://github.com/zdharma-continuum/zinit) (autosuggestions, syntax-highlighting) + [Starship](https://starship.rs) (prompt) + fzf (`Ctrl+R` / `Ctrl+T` / `Alt+C`) + fastfetch (alias `ff`). Les raccourcis clavier (Ctrl+flèches, Home/End, Suppr…) viennent du fichier `key-bindings.zsh` d'Oh My Zsh, chargé seul via zinit : il gère aussi les séquences envoyées par Tabby sous Windows. Tous les outils viennent de mise, avec une seule config pour le XPS et les serveurs.

## Tabby

`tabby/config.yaml` ne contient que ce qui diffère des valeurs par défaut de Tabby. C'est la référence : un réglage se change dans le repo (commit + push), puis on réinstalle sur chaque PC. Un réglage changé dans l'interface de Tabby est perdu à la prochaine installation.

Installer ou mettre à jour, Tabby **fermé**, depuis un autre terminal :

- **Windows** : `irm https://raw.githubusercontent.com/Sonny93/dotfiles/main/tabby/install.ps1 | iex` (`tabby/install.ps1`)
- **XPS** : `cd ~/dotfiles && git pull && just tabby` (`tabby/install.sh`)

Le script :

1. sauvegarde la config locale (`config.backup-<date>.yaml`, à côté) ;
2. la remplace par celle du repo ;
3. garde les hosts déjà connus (pas de nouvelle validation des empreintes) ;
4. garde le profil par défaut s'il pointe vers un `Host` de `~/.ssh/config`, sinon demande lequel ouvrir au lancement (un `Host` ou le shell local).

Les connexions ne passent pas par la config Tabby : il les lit dans `~/.ssh/config` et les affiche sous la forme `mon-serveur (.ssh/config)`.

## Sécurité

Le repo est public et ne contient **jamais** de secret, d'identité ni d'infos sur les serveurs :

- **Clé SSH** : seulement dans Bitwarden. Coffre verrouillé = aucune connexion possible. Une machine perdue = se déconnecter de Bitwarden dessus.
- **Connexions** : dans Bitwarden et `~/.ssh/config` des PC, jamais dans le repo.
- **Identité git** : définie dans chaque repo. `.gitconfig` inclut aussi `~/.gitconfig.local`, optionnel et propre au XPS, pour une identité par défaut.
- **GitHub** : jeton `gh` sur le XPS uniquement. Il va dans le trousseau système s'il y en a un, sinon en clair dans `~/.config/gh/hosts.yml`.
- **gitleaks** tourne en pre-commit (`githooks/pre-commit`, activé par `just git`) et bloque tout secret qui tenterait d'entrer.

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

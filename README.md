# dotfiles

zsh, git, mise, tmux, Starship et Tabby, répartis par machine : Windows 11, XPS, machine de dev et serveur.

| Machine | Contenu | Vérifier avec |
|---|---|---|
| **Windows 11** | Tabby + Bitwarden (agent SSH) + `~/.ssh/config` : on se connecte aux autres machines depuis là | Tabby ouvre la connexion par défaut |
| **XPS** (Debian) | Tout ce qu'a la machine de dev + Tabby + Bitwarden (agent SSH) + `~/.ssh/config` | `just doctor-dev` + Tabby ouvre la connexion par défaut |
| **Machine de dev** (Debian) | Shell + tous les outils mise + git + `gh` + config Claude Code | `just doctor-dev` |
| **Serveur / VPS** (Debian) | Shell seulement. Pas de clé privée, pas de compte GitHub, rien à voler | `just doctor-server` |

## Sommaire

- [Où vit quoi](#où-vit-quoi)
- [Une seule fois : la clé SSH](#une-seule-fois--la-clé-ssh)
- [Windows 11](#windows-11)
- [Machine de dev](#machine-de-dev)
  - [Gérer des serveurs depuis la machine de dev](#gérer-des-serveurs-depuis-la-machine-de-dev)
- [XPS](#xps)
- [Serveur / VPS](#serveur--vps)
- [Ajouter une connexion](#ajouter-une-connexion)
- [Commandes](#commandes)
- [Shell](#shell)
- [Tabby](#tabby)
- [tmux](#tmux)
- [Claude Code](#claude-code)
- [Sécurité](#sécurité)
- [MOTD](#motd)

## Où vit quoi

| Quoi | Où | Dans le repo |
|---|---|---|
| Clé SSH privée | Bitwarden, servie par son agent SSH sur Windows 11 et le XPS | Jamais |
| Connexions SSH | `~/.ssh/config` sur Windows 11 et le XPS, copie dans une note Bitwarden | Jamais |
| Réglages Tabby (thème, police, raccourcis) | `tabby/config.yaml` | Oui |
| Identité git | Chaque repo (`.git/config`), ou `~/.gitconfig.local` en option | Jamais |
| Accès GitHub | Jeton `gh` sur chaque machine de dev (le XPS compris) | Jamais |
| Config Claude Code (CLAUDE.md, RTK.md, agents, skills, réglages de base) | `claude/` | Oui |
| Identifiants Claude Code, jetons MCP, mémoire, historique | `~/.claude/` et `~/.claude.json` sur chaque machine de dev | Jamais |

Le repo est public : on le clone en HTTPS, sans clé ni compte.

## Une seule fois : la clé SSH

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

## Windows 11

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

6. Vérifier : `ssh-add -L` affiche la clé Bitwarden, et Tabby ouvre la connexion choisie au lancement.

Mise à jour : voir [Tabby](#tabby).

## Machine de dev

### Installer

1. Paquets de base :

   ```sh
   sudo apt install git curl zsh
   ```

2. Cloner le repo (le chemin `~/dotfiles` est codé en dur) et installer [mise](https://mise.jdx.dev) :

   ```sh
   git clone https://github.com/Sonny93/dotfiles ~/dotfiles
   curl https://mise.run | sh
   export PATH="$HOME/.local/bin:$PATH"
   ```

3. Shell :

   ```sh
   cd ~/dotfiles
   mise exec just -- just shell
   chsh -s "$(command -v zsh)"
   exec zsh
   ```

4. Tout le reste :

   ```sh
   just dev
   ```

   `just dev` enchaîne `apt`, `shell`, `mise` (tous les outils), `tmux` (lien de la config), `git` (config + hook gitleaks), `gh-auth`, `claude` (config Claude Code), puis `doctor-dev`, qui ne doit afficher que des lignes `OK` / `INFO`.

   Pas d'identité git par défaut : on la définit dans chaque repo (`git config user.name` / `user.email`). Pour une identité par défaut sur la machine, la mettre dans `~/.gitconfig.local` (section `[user]`).

### Gérer des serveurs depuis la machine de dev

Pour enchaîner Windows 11 ou XPS → machine de dev → serveur (par exemple Claude Code sur la machine de dev qui intervient sur un VPS), la machine de dev emprunte l'agent Bitwarden du client au lieu d'avoir sa propre clé :

1. Dans la note **ssh config** et `~/.ssh/config` de Windows 11 et du XPS, activer le transfert d'agent sur le `Host` de la machine de dev, et seulement lui :

   ```
   Host ma-machine-de-dev
       HostName 203.0.113.20
       ForwardAgent yes
   ```

2. Sur la machine de dev, créer `~/.ssh/config` avec les serveurs à gérer (la même note, sans la machine de dev elle-même).

Chaque connexion lancée depuis la machine de dev demande une validation dans Bitwarden, sur le client. Ça ne marche que tant qu'une session SSH depuis le client est ouverte.

### Mettre à jour

```sh
cd ~/dotfiles && git pull && just dev
exec zsh
```

## XPS

Le XPS est à la fois machine de dev et client.

1. Installer comme [Machine de dev](#machine-de-dev), en lançant `just xps` (alias de `just dev`) à l'étape 4.
2. Installer **Bitwarden Desktop** en `.deb` (pas en Flatpak ni Snap : l'agent SSH n'y crée pas son socket), se connecter, activer **l'agent SSH**. Puis l'annoncer à toute la session graphique (Tabby compris), et se déconnecter / reconnecter :

   ```sh
   mkdir -p ~/.config/environment.d
   echo 'SSH_AUTH_SOCK=${HOME}/.bitwarden-ssh-agent.sock' > ~/.config/environment.d/bitwarden-ssh-agent.conf
   ```

3. Créer `~/.ssh/config` avec le contenu de la note **ssh config**.
4. Installer **Tabby**, le lancer une fois, le fermer complètement, puis depuis un autre terminal :

   ```sh
   bash ~/dotfiles/tabby/install.sh
   ```

5. Vérifier : `ssh-add -L` affiche la clé Bitwarden, et Tabby ouvre la connexion choisie au lancement.

### Mettre à jour

```sh
cd ~/dotfiles && git pull && just xps
exec zsh
```

Tabby : voir [Tabby](#tabby).

## Serveur / VPS

### Installer

1. **Donner la clé publique au serveur.** C'est la serrure, pas la clé : elle peut être lue sans risque.
   - VPS neuf : coller la clé publique (copiée depuis Bitwarden) dans le formulaire de l'hébergeur.
   - Serveur existant, depuis Windows 11 (PowerShell) ou le XPS, avec une connexion par mot de passe :

     ```sh
     ssh-add -L | ssh user@host "umask 077; mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys"
     ```

2. Ajouter la connexion (voir [Ajouter une connexion](#ajouter-une-connexion)).
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
   ```

4. Tout le reste :

   ```sh
   just server
   ```

   `just server` enchaîne `apt`, `shell` et `doctor-server`. `just shell` n'installe que les outils dont le shell a besoin (starship, fzf, just, fastfetch), pas toute la config mise.

À ne jamais faire sur un serveur : y mettre la clé privée, s'y connecter à GitHub, ou activer `ForwardAgent` vers lui (root sur le serveur pourrait utiliser ta clé tant que tu es connecté). Le transfert d'agent est réservé aux machines de dev à toi.

### Mettre à jour un serveur

```sh
cd ~/dotfiles && git pull && just server
exec zsh
```

## Ajouter une connexion

1. Donner la clé publique au serveur (voir [Serveur / VPS](#serveur--vps)).
2. Ajouter le `Host` dans la note **ssh config** de Bitwarden, puis dans `~/.ssh/config` de Windows 11 et du XPS (et de la machine de dev si elle doit joindre ce serveur). Tabby l'affiche au prochain lancement.

## Commandes

`just` ou `just help` liste les commandes. Windows 11 n'en utilise aucune : Tabby passe par son script (voir [Tabby](#tabby)).

| Commande | Rôle | Dev / XPS | Serveur |
|---|---|---|---|
| `just dev` (alias `just xps`) | Installer / mettre à jour une machine de dev : `apt`, `shell`, `mise`, `tmux`, `git`, `gh-auth`, `claude`, `doctor-dev` | ✓ | |
| `just server` | Installer / mettre à jour un serveur : `apt`, `shell`, `doctor-server` | | ✓ |
| `just apt` | Mettre à jour les paquets système | ✓ | ✓ |
| `just shell` | zsh, Starship et les outils mise du shell | ✓ | ✓ |
| `just mise` | Installer / mettre à jour tous les outils de `mise/config.toml` | ✓ | |
| `just tmux` | Lier la config tmux (`~/.config/tmux/tmux.conf`) | ✓ | |
| `just git` | Config git du repo + hook gitleaks | ✓ | |
| `just gh-auth` | Connexion GitHub via `gh`, utilisée par git en HTTPS | ✓ | |
| `just claude` | Lier la config Claude Code (CLAUDE.md, RTK.md, agents, skills) et fusionner les réglages de base | ✓ | |
| `just doctor-server` | Vérifier le shell | ✓ | ✓ |
| `just doctor-dev` | Vérifier toute la machine de dev (lance aussi `doctor-server`) | ✓ | |
| `just uninstall-omz` | Supprimer une ancienne install Oh My Zsh / Powerlevel10k | | |

## Shell

zsh + [zinit](https://github.com/zdharma-continuum/zinit) (autosuggestions, syntax-highlighting) + [Starship](https://starship.rs) (prompt) + fzf (`Ctrl+R` / `Ctrl+T` / `Alt+C`) + fastfetch (alias `ff`). La commande `update` met à jour le système (`apt`), puis les outils (`mise upgrade`), puis relance les Claude Code inactifs dans tmux (`tmux/restart-claude.sh`). Les raccourcis clavier (Ctrl+flèches, Home/End, Suppr…) viennent du fichier `key-bindings.zsh` d'Oh My Zsh, chargé seul via zinit : il gère aussi les séquences envoyées par Tabby sous Windows. Tous les outils viennent de mise, avec une seule config pour toutes les machines.

Chaque machine reçoit une pastille colorée (emoji) calculée à partir de son nom d'hôte, affichée dans le titre d'onglet et dans le prompt : aucune configuration. En cas de collision entre deux machines, renommer l'une d'elles ou ajouter `export MACHINE_BADGE=🟢` dans `~/.zshenv` sur cette machine.

## Tabby

`tabby/config.yaml` ne contient que ce qui diffère des valeurs par défaut de Tabby. C'est la référence : un réglage se change dans le repo (commit + push), puis on réinstalle sur Windows 11 et le XPS. Un réglage changé dans l'interface de Tabby est perdu à la prochaine installation.

Installer ou mettre à jour, Tabby **fermé**, depuis un autre terminal :

- **Windows** : `irm https://raw.githubusercontent.com/Sonny93/dotfiles/main/tabby/install.ps1 | iex` (`tabby/install.ps1`)
- **XPS** : `cd ~/dotfiles && git pull && bash tabby/install.sh` (`tabby/install.sh`)

Le script :

1. sauvegarde la config locale (`config.backup-<date>.yaml`, à côté) ;
2. la remplace par celle du repo ;
3. garde les hosts déjà connus (pas de nouvelle validation des empreintes) ;
4. garde le profil par défaut s'il pointe vers un `Host` de `~/.ssh/config`, sinon demande lequel ouvrir au lancement (un `Host` ou le shell local).

Les connexions ne passent pas par la config Tabby : il les lit dans `~/.ssh/config` et les affiche sous la forme `mon-serveur (.ssh/config)`. Leurs réglages communs viennent de `profileDefaults.ssh` dans `tabby/config.yaml` : titre d'onglet envoyé par le shell distant (pastille colorée et nom de la machine, puis dossier ou commande en cours) et nouvel onglet / SFTP ouvert dans le dossier courant. Le `.zshrc` envoie les deux à chaque prompt, aucun profil à modifier à la main.

## tmux

Sur les machines de dev, tmux garde les sessions en vie quand la connexion SSH tombe. `tmux/tmux.conf` (lié par `just tmux`) ne contient que ce qui diffère des valeurs par défaut de tmux. Le préfixe est **Ctrl+A** (Ctrl+B sert à Claude Code pour passer une commande en arrière-plan).

`t` ouvre ou rattache une session tmux. `t .` (ou tout chemin, par exemple `t ~/dev/app`), lancé depuis un projet (n'importe quel sous-dossier d'un repo git), ouvre ou rattache la session du projet, nommée d'après le dossier de la racine git, avec la disposition « Claude + shells » dans le premier onglet : Claude Code à gauche, deux shells empilés à droite (`tmux/workspace.sh`). `t <nom>` rattache la session de ce nom, ou la crée si `<nom>` est un projet connu (`~/dev/<nom>` ou `~/dotfiles`) ; `Tab` complète les sessions et les projets. `t` seul rattache la dernière session, ou ouvre le sélecteur de sessions quand on est déjà dans tmux. Quand Claude se termine, son pane reste ouvert sur un shell. Dans tmux, `t` bascule vers la session sans en imbriquer une autre.

tmux se résume à deux notions : la session (en général un projet) et l'onglet. `Alt+n` ou `Ctrl+A` puis `c` ouvre le menu « Nouvel onglet » : Claude + shells (`w`), Claude seul (`c`) ou shell seul (`s`), dans le dossier du pane courant (`tmux/new-tab-menu.conf`, défini une seule fois et réutilisé par la palette).

`Ctrl+A` puis `s` ouvre un sélecteur de sessions et de projets (fzf dans un popup) : d'abord les sessions ouvertes (la courante est marquée), puis les dossiers de `~/dev` et `~/dotfiles` sans session. `Entrée` bascule vers la session, en la créant avec « Claude + shells » pour un projet, `Échap` ferme sans rien faire (`tmux/session-picker.sh`). `Ctrl+A` puis `w` garde l'arborescence native des sessions et des onglets.

La barre d'état tient sur deux lignes, en couleurs Cobalt2 comme Tabby : la première liste les sessions (la courante en jaune), la seconde les onglets, chacun nommé d'après le titre de son pane Claude. Une cloche dans n'importe quel pane de l'onglet colore son onglet en rose ; `claude/settings.json` règle `preferredNotifChannel` sur `terminal_bell` pour que Claude sonne quand il a fini ou attend une réponse. `Alt+1` … `Alt+9` changent d'onglet sans préfixe.

`Ctrl+A` puis `Ctrl+K` ouvre une palette de commandes (fzf dans un popup) : les actions de `tmux/palette.tsv` (libellé, raccourci, commande tmux ; une action = une ligne), `Entrée` lance la commande sur le pane d'où la palette a été ouverte, `Échap` ferme (`tmux/command-palette.sh`).

Après `update`, les instances Claude Code déjà ouvertes gardent l'ancien binaire : l'action « Relancer les Claude Code inactifs » de la palette relance celles qui sont inactives avec `claude --resume`, passe celles qui travaillent et celles déjà à jour (`tmux/restart-claude.sh`).

Les raccourcis vivent dans `tmux/cheatsheet.md` ; `Ctrl+A` puis `h` l'ouvre dans tmux.

`tmux ls` liste les sessions. La souris est activée : pour sélectionner du texte avec Tabby, maintenir Shift pendant le glisser.

## Claude Code

`claude/` contient la config utilisateur de Claude Code, appliquée par `just claude` (lancé par `just dev`) :

- **Liés** : les fichiers `.md` de premier niveau de `claude/` (`CLAUDE.md`, `RTK.md`), chaque fichier de `claude/agents/` et chaque dossier de `claude/skills/` sont liés un par un dans `~/.claude/` (`~/.claude/CLAUDE.md`, `~/.claude/RTK.md`, `~/.claude/agents/<nom>.md`, `~/.claude/skills/<nom>`). Le reste de `~/.claude/skills/` (`synced/`, skills installés par `npx skills`, plugins) n'est pas touché.
- **Fusionné** : `claude/settings.json` est une base fusionnée (jq) dans `~/.claude/settings.json`, jamais liée : Claude Code réécrit ce fichier lui-même. Les clés du repo l'emportent, les clés propres à la machine (`model`, `theme`…) restent.
- **rtk** : `rtk` (installé par `just mise`) compresse la sortie des commandes avant qu'elle n'atteigne Claude. Les réglages de base déclarent son hook `PreToolUse` (`rtk hook claude`) et `CLAUDE.md` importe `RTK.md` : aucun `rtk init` à lancer. Ne pas relancer `rtk init -g` (il modifierait `settings.json` et écrirait à travers le lien `RTK.md`) ; si une nouvelle version de rtk change `RTK.md`, le régénérer ailleurs et le copier dans `claude/RTK.md`.
- `claude/statusline.sh` est référencé directement par les réglages de base : rien à installer.

Avant de remplacer quoi que ce soit, `just claude` déplace l'existant dans `~/.claude/backups/dotfiles-<date>/` (même chemin relatif) et affiche chaque sauvegarde. Rien n'est supprimé, sauf les liens vers le repo devenus orphelins (skill ou agent retiré du repo).

- **Retirer un réglage** : la fusion ajoute et écrase seulement. Une clé retirée de `claude/settings.json` se retire à la main de `~/.claude/settings.json`.
- **Ajouter un skill ou un agent** : le créer dans `claude/skills/<nom>/SKILL.md` ou `claude/agents/<nom>.md`, puis `just claude`.
- **Hors repo** : les skills installés par `npx skills` ou par des plugins restent hors du repo.
- Seuls les réglages indépendants de la machine et non sensibles vont dans `claude/settings.json`.

## Sécurité

Le repo est public et ne contient **jamais** de secret, d'identité ni d'infos sur les serveurs :

- **Clé SSH** : seulement dans Bitwarden, sur Windows 11 et le XPS. Coffre verrouillé = aucune connexion possible. Une machine perdue = se déconnecter de Bitwarden dessus.
- **Connexions** : dans Bitwarden et `~/.ssh/config` de Windows 11 et du XPS, jamais dans le repo.
- **Identité git** : définie dans chaque repo. `.gitconfig` inclut aussi `~/.gitconfig.local`, optionnel et propre à chaque machine, pour une identité par défaut.
- **GitHub** : jeton `gh` sur les machines de dev uniquement (le XPS compris). Il va dans le trousseau système s'il y en a un, sinon en clair dans `~/.config/gh/hosts.yml`. Aucune clé SSH pour GitHub : `.gitconfig` réécrit les remotes `git@github.com:` en HTTPS, donc les repos clonés en SSH passent aussi par `gh`, sans changer leur remote.
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

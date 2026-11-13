# dotfiles

[English](../../README.md)

zsh, git, mise, tmux et Starship, répartis par machine : machine de dev et serveur.

| Machine | Contenu | Vérifier avec |
|---|---|---|
| **Machine de dev** (Debian ou base Arch, par exemple CachyOS) | Shell + tous les outils mise + git + `gh` + config Claude Code. Une machine de bureau reçoit Bitwarden (agent SSH), Tabby et les applications de bureau d'un dépôt privé séparé | `just doctor-dev` |
| **Serveur / VPS** (Debian) | Shell seulement. Pas de clé privée, pas de compte GitHub, rien à voler | `just doctor-server` |

## Sommaire

- [Où vit quoi](#où-vit-quoi)
- [Une seule fois : la clé SSH](#une-seule-fois--la-clé-ssh)
- [Machine de dev](#machine-de-dev)
  - [Gérer des serveurs depuis la machine de dev](#gérer-des-serveurs-depuis-la-machine-de-dev)
- [Serveur / VPS](#serveur--vps)
- [Ajouter une connexion](#ajouter-une-connexion)
- [Commandes](#commandes)
- [Shell](#shell)
- [tmux](#tmux)
- [Claude Code](#claude-code)
- [Sécurité](#sécurité)
- [MOTD](#motd)

## Où vit quoi

| Quoi | Où | Dans le repo |
|---|---|---|
| Clé SSH privée | Bitwarden, servie par son agent SSH sur tes machines locales (celles qui font tourner Bitwarden) | Jamais |
| Connexions SSH | `~/.ssh/config` sur tes machines locales, copie dans une note Bitwarden | Jamais |
| Identité git | Chaque repo (`.git/config`), ou `~/.gitconfig.local` en option | Jamais |
| Accès GitHub | Jeton `gh` sur chaque machine de dev (machines locales comprises) | Jamais |
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

   Pas de `IdentityFile` : `ssh` demande la clé à l'agent Bitwarden.

## Machine de dev

### Installer

1. Paquets de base. Sur Debian :

   ```sh
   sudo apt install git curl zsh
   ```

   Sur Arch (CachyOS par exemple) :

   ```sh
   sudo pacman -S --needed git curl zsh
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

   `just dev` enchaîne `system`, `build-deps` (paquets pour compiler tmux), `shell`, `mise` (tous les outils), `tmux` (liens de la config tmux et du thème micro), `git` (config + hook gitleaks et shellcheck), `gh-auth`, `notes` (dépôt git des notes), `claude` (config Claude Code), puis `doctor-dev`, qui ne doit afficher que des lignes `OK` / `INFO`.

   Pas d'identité git par défaut : on la définit dans chaque repo (`git config user.name` / `user.email`). Pour une identité par défaut sur la machine, la mettre dans `~/.gitconfig.local` (section `[user]`).

### Gérer des serveurs depuis la machine de dev

Pour enchaîner machine locale → machine de dev distante → serveur (par exemple Claude Code sur la machine de dev qui intervient sur un VPS), la machine de dev distante emprunte l'agent Bitwarden du client au lieu d'avoir sa propre clé :

1. Dans la note **ssh config** et `~/.ssh/config` de tes machines locales, activer le transfert d'agent sur le `Host` de la machine de dev, et seulement lui :

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

## Serveur / VPS

### Installer

1. **Donner la clé publique au serveur.** C'est la serrure, pas la clé : elle peut être lue sans risque.
   - VPS neuf : coller la clé publique (copiée depuis Bitwarden) dans le formulaire de l'hébergeur.
   - Serveur existant, depuis une machine locale, avec une connexion par mot de passe :

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

   `just server` enchaîne `system`, `shell` et `doctor-server`. `just shell` n'installe que les outils dont le shell a besoin (starship, fzf, just, fastfetch), pas toute la config mise.

À ne jamais faire sur un serveur : y mettre la clé privée, s'y connecter à GitHub, ou activer `ForwardAgent` vers lui (root sur le serveur pourrait utiliser ta clé tant que tu es connecté). Le transfert d'agent est réservé aux machines de dev à toi.

### Mettre à jour un serveur

```sh
cd ~/dotfiles && git pull && just server
exec zsh
```

## Ajouter une connexion

1. Donner la clé publique au serveur (voir [Serveur / VPS](#serveur--vps)).
2. Ajouter le `Host` dans la note **ssh config** de Bitwarden, puis dans `~/.ssh/config` de tes machines locales (et de la machine de dev si elle doit joindre ce serveur).

## Commandes

`just` ou `just help` liste les commandes.

| Commande | Rôle | Dev | Serveur |
|---|---|---|---|
| `just dev` | Installer / mettre à jour une machine de dev : `system`, `build-deps`, `shell`, `mise`, `tmux`, `git`, `gh-auth`, `notes`, `claude`, `doctor-dev` | ✓ | |
| `just server` | Installer / mettre à jour un serveur : `system`, `shell`, `doctor-server` | | ✓ |
| `just system` | Mettre à jour les paquets système (apt ou pacman) | ✓ | ✓ |
| `just build-deps` | Installer les paquets système pour compiler tmux (Debian : `build-essential`, `libncurses-dev`, `bison` ; Arch : `base-devel`, `ncurses`, `bison`) | ✓ | |
| `just shell` | zsh, Starship et les outils mise du shell | ✓ | ✓ |
| `just mise` | Installer / mettre à jour tous les outils de `mise/config.toml` | ✓ | |
| `just tmux` | Lier la config tmux (`~/.config/tmux/tmux.conf`) et le thème micro Cobalt2 (`~/.config/micro/colorschemes/cobalt2.micro`) | ✓ | |
| `just git` | Config git du repo + hook gitleaks et shellcheck | ✓ | |
| `just notes` | Mettre `~/notes` en dépôt git relié au dépôt GitHub privé `notes` (créé sur la première machine, cloné ailleurs) | ✓ | |
| `just gh-auth` | Connexion GitHub via `gh`, utilisée par git en HTTPS | ✓ | |
| `just claude` | Lier la config Claude Code (CLAUDE.md, RTK.md, agents, skills, config rtk) et fusionner les réglages de base | ✓ | |
| `just doctor-server` | Vérifier le shell | ✓ | ✓ |
| `just doctor-dev` | Vérifier toute la machine de dev (lance aussi `doctor-server`) | ✓ | |
| `just test` | Lancer les tests des scripts (`tmux/*.test.sh` sur un serveur tmux isolé, `scripts/*.test.sh`) | ✓ | |
| `just uninstall-omz` | Supprimer une ancienne install Oh My Zsh / Powerlevel10k | | |

## Shell

zsh + [zinit](https://github.com/zdharma-continuum/zinit) (autosuggestions, syntax-highlighting) + [Starship](https://starship.rs) (prompt) + fzf (`Ctrl+R` / `Ctrl+T` / `Alt+C`) + fastfetch (alias `ff`). La commande `update` met à jour le système (`apt` ou `pacman`), puis les outils (`mise upgrade`), puis relance les Claude Code inactifs dans tmux (`tmux/restart-claude.sh`). Les raccourcis clavier (Ctrl+flèches, Home/End, Suppr…) viennent du fichier `key-bindings.zsh` d'Oh My Zsh, chargé seul via zinit. Tous les outils viennent de mise, avec une seule config pour toutes les machines.

Chaque machine reçoit une pastille colorée (emoji) calculée à partir de son nom d'hôte, affichée dans le titre d'onglet et dans le prompt : aucune configuration. En cas de collision entre deux machines, renommer l'une d'elles ou ajouter `export MACHINE_BADGE=🟢` dans `~/.zshenv` sur cette machine.

## tmux

Sur les machines de dev, tmux garde les sessions en vie quand la connexion SSH tombe. mise compile tmux depuis ses sources (plugin `mise-tmux`, avec `build-essential`, `libncurses-dev` et `bison` (Debian) ou `base-devel`, `ncurses` et `bison` (Arch) installés par `just build-deps`) : les binaires précompilés de `tmux/tmux-builds` ont des semaines de retard sur les versions de tmux. `tmux/tmux.conf` (lié par `just tmux`) ne contient que ce qui diffère des valeurs par défaut de tmux. Le préfixe est **Ctrl+A** (Ctrl+B sert à Claude Code pour passer une commande en arrière-plan).

`t` ouvre ou rattache une session tmux. `t .` (ou tout chemin, par exemple `t ~/dev/app`), lancé depuis un projet (n'importe quel sous-dossier d'un repo git), ouvre ou rattache la session du projet, nommée d'après le dossier de la racine git, dans le premier onglet. Une session sur le point d'être créée demande d'abord sa disposition (fzf, `tmux/layouts.sh`) : « Claude + shells » (`Entrée` ou `w` : Claude Code à gauche, deux shells empilés à droite), « Claude seul » (`c`) ou « Shell seul » (`s`) ; `Échap` ne crée rien. `tmux/workspace.sh <disposition> <dossier> <session>` la construit. Dans une nouvelle session, Claude reprend la dernière conversation du dossier (`claude --continue`), par exemple après un redémarrage de tmux, mais seulement si le dossier en a une (`~/.claude/projects`), car `--continue` échoue sinon ; un onglet ajouté à une session existante démarre une conversation neuve, pour que deux onglets ne partagent jamais la même. `t <nom>` rattache la session de ce nom, ou la crée si `<nom>` est un projet connu (`~/dev/<nom>` ou `~/dotfiles`) ; sinon, si `gh` est installé, il clone dans `~/dev/<nom>` le dépôt GitHub de ce nom quand il figure dans le cache (nom comparé sans tenir compte de la casse, le dossier prend l'orthographe du dépôt ; la question de la disposition vient d'abord, puis le clone affiche sa progression, et un clone en échec est une erreur, jamais un dossier vide) ; sinon il crée le dossier de projet `~/dev/<nom>` (lettres, chiffres, `_`, `.` et `-`, sans commencer par `.` ni `-` ; pas de `git init`) après la question de la disposition. `Tab` complète les sessions, les projets et les noms des dépôts GitHub pas encore clonés. Le cache (`~/.cache/dotfiles/github-repositories`) liste vos dépôts et ceux de vos organisations, sans les dépôts archivés ni les forks, via `gh` ; il est rafraîchi en arrière-plan quand il a plus de 10 minutes, donc seule la toute première utilisation sur une machine peut attendre quelques secondes. Les décisions viennent du seul cache, jamais du réseau. Les dépôts qui ont déjà une session ou un dossier, `~/dotfiles` et `~/notes` ne sont jamais proposés. Sans `gh` (serveurs), aucun comportement GitHub. `t` seul rattache la dernière session, ou ouvre le sélecteur de sessions quand on est déjà dans tmux ; sans aucune session, il ouvre le sélecteur directement dans le terminal, limité aux projets : `Entrée` crée la session du projet choisi (après la question de la disposition) et s'y rattache, `Échap` ne crée rien. Quand Claude se termine, son pane reste ouvert sur un shell. Dans tmux, `t` bascule vers la session sans en imbriquer une autre.

tmux se résume à deux notions : la session (en général un projet) et l'onglet. `Alt+n` ou `Ctrl+A` puis `c` ouvre le menu « Nouvel onglet » : Claude + shells (`w`), Claude seul (`c`) ou shell seul (`s`), dans le dossier du pane courant (`tmux/new-tab-menu.conf`, défini une seule fois et réutilisé par la palette ; chaque entrée appelle `tmux/workspace.sh` avec sa disposition).

`Ctrl+A` puis `s` ouvre un sélecteur unique (fzf dans un popup) : les sessions ouvertes en arbre (la courante est marquée), chacune suivie de ses onglets avec le même libellé que la barre du haut, puis les dossiers de `~/dev` et `~/dotfiles` sans session, puis les dépôts GitHub pas encore clonés (`<owner>/<nom>  (GitHub, à cloner)`, seulement avec `gh`) : `Entrée` demande la disposition, clone dans `~/dev/<nom>`, puis ouvre la session. L'onglet courant est présélectionné, l'aperçu montre le pane de l'onglet visé, et le nom de la session reste filtrable depuis chaque onglet. `Entrée` bascule vers la session ou l'onglet, en créant la session d'un projet après la question de la disposition, `Échap` ferme sans rien faire (`tmux/session-picker.sh` ; `just test` vérifie le parcours des sessions sur un serveur tmux isolé, `tmux/session-flow.test.sh`). Un nom tapé dans le sélecteur peut devenir un nouveau projet : `Entrée` sur une saisie qui ne correspond à rien, ou `Alt+Entrée` quelles que soient les correspondances (l'en-tête affiche `créer ~/dev/<saisie>`), crée le dossier `~/dev/<nom>` après la question de la disposition (ou clone le dépôt quand le nom saisi est dans le cache GitHub) (même règle de nom que `t <nom>`, pas de `git init` ; un nom invalide affiche une erreur ; `Échap` à la question de la disposition ne crée rien). L'arborescence native des sessions et des onglets reste dans la palette.

`Ctrl+A` puis `n` ouvre les notes libres du projet dans un popup (micro en thème Cobalt2, `micro/colorschemes/cobalt2.micro`, lié par `just tmux` ; raccourcis à la VS Code : `Ctrl+S` sauve, `Ctrl+Q` ferme, `Ctrl+C` copie la sélection dans le presse-papiers du poste (OSC 52), sauvegarde automatique, historique `Ctrl+Z` conservé après fermeture). Le fichier est `~/notes/<projet>.md`, hors des repos ; le projet est le dossier de la racine git du pane courant, créé avec un titre au premier usage (`tmux/notes.sh`). `~/notes` est un dépôt git : l'ouverture fait un pull, chaque fermeture commite puis pousse vers le dépôt GitHub privé `notes` créé par `just notes`. Les commits sont signés `notes <notes@localhost>`, une adresse inconnue de GitHub : ils ne gonflent pas le graphe de contributions du profil. En cas de conflit ou d'échec, un message tmux le signale : demander à Claude de synchroniser `~/notes`. Cette touche remplace le `next-window` natif de tmux : `Alt+1` … `Alt+9` changent d'onglet.

La barre d'état tient sur deux lignes, en couleurs Cobalt2 : la première liste les sessions (la courante en jaune), la seconde les onglets, chacun nommé d'après le titre de son pane Claude. Une cloche dans n'importe quel pane de l'onglet colore son onglet en rose ; `claude/settings.json` règle `preferredNotifChannel` sur `terminal_bell` pour que Claude sonne quand il a fini ou attend une réponse. `Alt+1` … `Alt+9` changent d'onglet sans préfixe, et `Alt+&` … `Alt+ç` (la rangée de chiffres AZERTY) font de même.

`Ctrl+A` puis `Ctrl+K` ouvre une palette de commandes (fzf dans un popup) : les actions de `tmux/palette.tsv` (libellé, raccourci, commande tmux ; une action = une ligne), `Entrée` lance la commande sur le pane d'où la palette a été ouverte, `Échap` ferme (`tmux/command-palette.sh`).

Après `update`, les instances Claude Code déjà ouvertes gardent l'ancien binaire : l'action « Relancer les Claude Code inactifs » de la palette relance celles qui sont inactives avec `claude --resume`, passe celles qui travaillent et celles déjà à jour (`tmux/restart-claude.sh`).

Les raccourcis vivent dans `tmux/cheatsheet.md` ; `Ctrl+A` puis `h` l'ouvre dans tmux.

`tmux ls` liste les sessions. La souris est activée : glisser sélectionne du texte dans un seul pane sans le copier, `Ctrl+C` ou `Entrée` le copie dans le presse-papiers du poste, un clic ou `Échap` annule.

## Claude Code

`claude/` contient la config utilisateur de Claude Code, appliquée par `just claude` (lancé par `just dev`) :

- **Liés** : les fichiers `.md` de premier niveau de `claude/` (`CLAUDE.md`, `RTK.md`), chaque fichier de `claude/agents/` et chaque dossier de `claude/skills/` sont liés un par un dans `~/.claude/` (`~/.claude/CLAUDE.md`, `~/.claude/RTK.md`, `~/.claude/agents/<nom>.md`, `~/.claude/skills/<nom>`). Le reste de `~/.claude/skills/` (`synced/`, skills installés par `npx skills`, plugins) n'est pas touché.
- **Fusionné** : `claude/settings.json` est une base fusionnée (jq) dans `~/.claude/settings.json`, jamais liée : Claude Code réécrit ce fichier lui-même. Les clés du repo l'emportent, les clés propres à la machine (`model`, `theme`…) restent.
- **rtk** : `rtk` (installé par `just mise`) compresse la sortie des commandes avant qu'elle n'atteigne Claude. Les réglages de base déclarent son hook `PreToolUse` (`rtk hook claude`) et `CLAUDE.md` importe `RTK.md` : aucun `rtk init` à lancer. Ne pas relancer `rtk init -g` (il modifierait `settings.json` et écrirait à travers le lien `RTK.md`) ; si une nouvelle version de rtk change `RTK.md`, le régénérer ailleurs et le copier dans `claude/RTK.md`. `rtk/config.toml` est lié vers `~/.config/rtk/config.toml` et ne contient que des surcharges des valeurs par défaut de rtk : il exclut `pnpm run lint`, `pnpm lint` et `npm run lint` de la réécriture, car rtk les transformerait en `rtk lint`, un run ESLint uniquement qui échoue sur les projets lintés avec oxlint.
- `claude/statusline.sh` est référencé directement par les réglages de base : rien à installer.
- **Garde des skills de doc et de code** : `claude/hooks/require-skill.sh`, référencé par les réglages de base (hook `PreToolUse` sur `Edit|Write`), refuse toute modification d'un `CLAUDE.md`, `CLAUDE.local.md`, `AGENTS.md` ou `.claude/rules/*.md` tant que le skill `claude-md` n'a pas été chargé, d'un `README.md`, `docs/**/*.md`, `CONTRIBUTING.md`, `DEPLOY.md`, `PUBLISHING.md` ou `SECURITY.md` tant que le skill `project-docs` ne l'a pas été, et des fichiers TypeScript tant que `typescript-conventions` ne l'a pas été (plus `react-conventions` pour les `.tsx`, `adonis-conventions` pour les `.ts` d'un projet AdonisJS, repéré par son `adonisrc.ts`). Les fichiers de déclaration, `dist/`, `build/`, `.adonisjs/` et `node_modules/` sont ignorés, ainsi que `CHANGELOG.md` et `docs/adr/`. Un skill compte comme chargé quand il a été invoqué dans la session de l'agent qui édite, ou préchargé par la définition de cet agent (`skills:` dans `agents/<nom>.md`).
- **Garde de Context7** : `claude/hooks/require-context7.sh`, référencé par les réglages de base (hook `SessionStart`, asynchrone, et hook `UserPromptSubmit`), vérifie avec `claude mcp get plugin:context7:context7` que le serveur Context7 est connecté. Quand son statut n'est pas `Connected` (typiquement une authentification OAuth en attente), le premier prompt de la session est bloqué avec un message qui demande de lancer `/mcp` ; renvoyer le message le laisse passer. Elle ne bloque qu'une fois par session, donc une panne de Context7 n'enferme jamais l'utilisateur, et ne fait rien quand le statut est indéterminé (pas de `claude` dans le `PATH`, erreur, timeout de 10 s).

Avant de remplacer quoi que ce soit, `just claude` déplace l'existant dans `~/.claude/backups/dotfiles-<date>/` (même chemin relatif) et affiche chaque sauvegarde. Rien n'est supprimé, sauf les liens vers le repo devenus orphelins (skill ou agent retiré du repo).

- **Retirer un réglage** : la fusion ajoute et écrase seulement. Une clé retirée de `claude/settings.json` se retire à la main de `~/.claude/settings.json`.
- **Ajouter un skill ou un agent** : le créer dans `claude/skills/<nom>/SKILL.md` ou `claude/agents/<nom>.md`, puis `just claude`.
- **Hors repo** : les skills installés par `npx skills` ou par des plugins restent hors du repo.
- Seuls les réglages indépendants de la machine et non sensibles vont dans `claude/settings.json`.

## Sécurité

Le repo est public et ne contient **jamais** de secret, d'identité ni d'infos sur les serveurs :

- **Clé SSH** : seulement dans Bitwarden, sur tes machines locales. Coffre verrouillé = aucune connexion possible. Une machine perdue = se déconnecter de Bitwarden dessus.
- **Connexions** : dans Bitwarden et `~/.ssh/config` de tes machines locales, jamais dans le repo.
- **Identité git** : définie dans chaque repo. `.gitconfig` inclut aussi `~/.gitconfig.local`, optionnel et propre à chaque machine, pour une identité par défaut.
- **GitHub** : jeton `gh` sur les machines de dev uniquement (machines locales comprises). Il va dans le trousseau système s'il y en a un, sinon en clair dans `~/.config/gh/hosts.yml`. Aucune clé SSH pour GitHub : `.gitconfig` réécrit les remotes `git@github.com:` en HTTPS, donc les repos clonés en SSH passent aussi par `gh`, sans changer leur remote.
- **gitleaks** tourne en pre-commit (`githooks/pre-commit`, activé par `just git`) et bloque tout secret qui tenterait d'entrer. Le même hook analyse les scripts shell indexés avec shellcheck.

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

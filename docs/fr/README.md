# dotfiles

[English](../../README.md)

zsh, git, mise, tmux et Starship, répartis par machine : machine de dev et serveur.

| Machine | Contenu | Vérifier avec |
|---|---|---|
| **Machine de dev** (Debian ou base Arch, par exemple CachyOS) | Shell + tous les outils mise + git + `gh` + config Claude Code. Une machine de bureau reçoit Bitwarden (agent SSH), Tabby et les applications de bureau d'un dépôt privé séparé | `just doctor-dev` |
| **Serveur / VPS** (Debian) | Shell seulement. Pas de clé privée, pas de compte GitHub, rien à voler | `just doctor-server` |

## Pourquoi

- **Objectif** : une commande garde les machines de dev et les serveurs de l'utilisateur installés et à jour.
- **Utilisateurs** : une personne, quelques machines et serveurs personnels.
- **Enjeux** : elle lance des mises à jour de paquets en root. Une mise à jour ratée peut laisser une machine qui ne démarre plus ; les snapshots btrfs des PC CachyOS sont le filet de sécurité.
- **Hors périmètre** : pas de multi-utilisateur, pas de mise à jour root sans surveillance, pas de sudo `NOPASSWD`.
- **Contraintes fermes** : dotfiles ne dépend jamais du dépôt machines (la dépendance va dans un seul sens, de machines vers dotfiles) ; Arch et Debian sont tous deux pris en charge.

## Sommaire

- [Pourquoi](#pourquoi)
- [Où vit quoi](#où-vit-quoi)
- [Une seule fois : la clé SSH](#une-seule-fois--la-clé-ssh)
- [Machine de dev](#machine-de-dev)
  - [Gérer des serveurs depuis la machine de dev](#gérer-des-serveurs-depuis-la-machine-de-dev)
- [Serveur / VPS](#serveur--vps)
- [Ajouter une connexion](#ajouter-une-connexion)
- [Commandes](#commandes)
- [La commande update](#la-commande-update)
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
| Rôle de la machine (`dev` ou `server`), écrit par `just dev` / `just server` et lu par `update` | `~/.config/dotfiles/role` | Jamais |
| Journal d'exécution de `update` (mode silencieux) et son rapport, les 14 plus récents de chaque sont gardés | `~/.local/state/dotfiles/update/<horodatage>.log` et `<horodatage>.report` | Jamais |
| Journal de la mise à jour pacman en root lancée par `update` (propriété de root) | `/var/log/dotfiles/pacman-<horodatage>.log` | Jamais |
| Délégation optionnelle de `update` : un exécutable qu'un dépôt privé peut installer, il remplace la recette du rôle et doit la lancer lui-même | `~/.config/dotfiles/update-hook` | Jamais |

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
| `just dev` | Installer / mettre à jour une machine de dev, et enregistrer le rôle `dev` dans `~/.config/dotfiles/role` : `system`, `build-deps`, `shell`, `mise`, `tmux`, `git`, `gh-auth`, `notes`, `claude`, `doctor-dev` | ✓ | |
| `just server` | Installer / mettre à jour un serveur, et enregistrer le rôle `server` dans `~/.config/dotfiles/role` : `system`, `shell`, `doctor-server` | | ✓ |
| `just system` | Mettre à jour les paquets système (apt ou pacman) | ✓ | ✓ |
| `just build-deps` | Installer les paquets système pour compiler tmux (Debian : `build-essential`, `libncurses-dev`, `bison` ; Arch : `base-devel`, `ncurses`, `bison`) | ✓ | |
| `just shell` | zsh, Starship et les outils mise du shell | ✓ | ✓ |
| `just mise` | Installer / mettre à jour tous les outils de `mise/config.toml` | ✓ | |
| `just tmux` | Lier la config tmux (`~/.config/tmux/tmux.conf`) et le thème micro Cobalt2 (`~/.config/micro/colorschemes/cobalt2.micro`) | ✓ | |
| `just git` | Config git du repo + hook gitleaks et shellcheck | ✓ | |
| `just notes` | Mettre `~/notes` en dépôt git relié au dépôt GitHub privé `notes` (créé sur la première machine, cloné ailleurs) | ✓ | |
| `just gh-auth` | Connexion GitHub via `gh`, utilisée par git en HTTPS | ✓ | |
| `just claude` | Lier la config Claude Code (CLAUDE.md, RTK.md, agents, skills, config rtk) et fusionner les réglages de base, désinstaller les plugins et marketplaces retirés de ceux-ci | ✓ | |
| `just doctor-server` | Vérifier le shell | ✓ | ✓ |
| `just doctor-dev` | Vérifier toute la machine de dev (lance aussi `doctor-server`), y compris les outils du menu Code et delta, dont git a besoin comme pager | ✓ | |
| `just test` | Lancer les tests des scripts tmux (`tmux/*.test.sh`) sur un serveur tmux isolé, les tests de la barre d'état Claude (`claude/*.test.sh`), les tests des hooks Claude (`claude/hooks/*.test.sh`) et les tests des scripts partagés (`scripts/*.test.sh`) | ✓ | |
| `just uninstall-omz` | Supprimer une ancienne install Oh My Zsh / Powerlevel10k | | |

## La commande update

`update` (`scripts/update.sh [--verbose]`) est silencieuse par défaut : un bandeau par phase, une ligne `✓` / `✗` par étape, la liste des commits tirés, une liste compacte des mises à jour de paquets avec leurs versions, les conflits et erreurs avec leur raison, puis un résumé final. Tout le reste va dans un journal d'exécution, dont le chemin est affiché dès qu'une étape échoue ou que le résumé n'est pas propre. `update --verbose` affiche à la place toute la sortie de chaque étape et n'écrit pas de journal. Tout autre argument est refusé.

Phases :

1. **Pull** : fast-forward uniquement. Il est sauté avec un avertissement quand le repo n'est pas sur `main`, a des modifications suivies non commitées, n'a pas d'upstream ou a divergé, et continue sans pull hors ligne. Les commits entrants sont toujours listés, même en mode silencieux : cette liste est la seule relecture d'un code qui tournera en root. Quand des commits ont été fusionnés, `update` se relance pour exécuter la nouvelle version.
2. **Application** : lance `~/.config/dotfiles/update-hook` quand un exécutable existe (il remplace la recette du rôle et doit la lancer lui-même), sinon `scripts/dev-update.sh` pour le rôle enregistré (`just dev` ou `just server`, une étape par recette). Sans rôle enregistré ni hook, lancer `just dev` ou `just server` une fois.
3. **Claude Code** : relance les instances inactives dans tmux (`tmux/restart-claude.sh`).

Fichiers, dans `${XDG_STATE_HOME:-~/.local/state}/dotfiles/update` (mode 700) :

- `<horodatage>.log` : sortie de chaque étape (mode silencieux seulement, exporté en `UPDATE_LOG`).
- `<horodatage>.report` : une ligne `WARN <texte>`, `ERROR <texte>` ou `REBOOT <texte>` par constat (exporté en `UPDATE_REPORT`, toujours écrit ; un rapport vide après une sortie 0 signifie une exécution propre). Un appelant peut fixer `UPDATE_REPORT` à l'avance pour le lire ensuite : `update` utilise alors ce chemin, vidé au départ.
- Les 14 journaux et les 14 rapports les plus récents sont gardés.

`update` sort avec un code non nul quand une étape a échoué ou que le rapport contient un `ERROR`.

Sécurité :

- Un maintien de sudo rafraîchit les droits toutes les 60 secondes pendant l'exécution, et `sudo -k` tourne à la sortie.
- Les étapes silencieuses tournent avec stdin fermé, `GIT_TERMINAL_PROMPT=0`, `LC_ALL=C`, dans une nouvelle session sans terminal de contrôle (`setsid`) et sous `timeout` (600 secondes par défaut, 1800 pour `mise` ; `UPDATE_STEP_TIMEOUT` remplace les deux, et un délai dépassé tue tout le groupe de processus). Sans terminal, sudo ne peut pas utiliser le ticket lié au terminal que le maintien garde valide (`timestamp_type`, voir `man sudoers` : sans terminal l'enregistrement dépend du PID parent, donc un script d'installation tiers qui appelle `sudo -n` échoue). Une ligne `… <étape>` s'affiche en direct sur un terminal et est remplacée par la ligne de résultat.
- Les étapes qui appellent sudo (`build-deps`, la suppression des orphelins) gardent le terminal. Sans ticket sudo en cache, `dev-update.sh` le demande une fois (`sudo -v`, 120 secondes) avant la première, et saute les étapes root avec un `WARN` qui nomme la recette si cela échoue.
- Les étapes qui peuvent poser une question restent attachées au terminal : `system` (la confirmation de la mise à jour) et le hook. `gh-auth` est sautée avec un `WARN` quand `gh` n'est pas connecté (lancer `just gh-auth`).
- Les appels réseau hors étapes ont leur propre délai : `git fetch` 30 secondes (et abandon sous 1000 octets/s pendant 20 secondes), `checkupdates` et `paru -Pw` 60 secondes, `gh auth status` 30 secondes.
- Le doctor (`just doctor-<rôle>`) tourne une fois à la fin du chemin sans hook ; `dev-update.sh` saute les recettes `doctor-*`.
- `scripts/dev-update.sh [dev|server]` lit les étapes dans les dépendances de la recette `dev` (ou `server`) du Justfile (`just --dump`) : la liste n'est déclarée qu'une fois.

### Mise à jour système Arch (mode silencieux)

Sur Arch, `just system` sous un `update` silencieux fait ceci (`scripts/arch-upgrade.sh`) :

1. Aperçu sans root : `checkupdates` rafraîchit une base de synchronisation temporaire, puis la transaction exacte est listée avec les versions installées en tableau aligné `nom  ancienne -> nouvelle` et un total (une nouvelle dépendance s'affiche `(new) -> version`). Rien à mettre à jour : une ligne, et aucune étape root.
2. Affiche les nouvelles Arch non lues (`paru -Pw`) quand paru est installé.
3. Pose une seule question, `Appliquer ? [O/n]` (oui par défaut). Répondre non, ou ne pas avoir de terminal, saute la mise à jour avec un `WARN`.
4. Refuse avec un `ERROR` quand `/var/lib/pacman/db.lck` existe.
5. Lance `pacman -Syu --noconfirm` comme unité systemd transitoire (`dotfiles-pacman-<horodatage>`) sous `systemd-inhibit` (arrêt, veille et capot bloqués), avec `Nice=10` et une priorité d'E/S best-effort 7. Les journaux root `/var/log/dotfiles/pacman-*.log` sont réduits aux 14 plus récents. L'unité survit à Ctrl+C, à un terminal fermé et à une déconnexion : le terminal ne fait que suivre le journal root `/var/log/dotfiles/pacman-<horodatage>.log`, et Ctrl+C arrête le suivi, jamais la mise à jour (le message donne le journal à suivre).
6. Affiche `✓` ou `✗`. En cas d'échec : les lignes de conflit et d'erreur et le chemin du journal root. Les lignes `warning:` (notamment `.pacnew` et `.pacsave`) deviennent des `WARN`, et une ligne `REBOOT` est ajoutée quand le hook CachyOS dit `Reboot is recommended` ou que les modules du noyau en cours ont disparu.
7. Liste les paquets orphelins sur une ligne, demande une fois (`Supprimer les orphelins ? [O/n]`) et les supprime, sortie dans le journal d'exécution.

Le mode verbeux et Debian gardent le comportement précédent (`apt` ou `pacman` avec leurs propres invites, au premier plan). Parité apt/pacman : chaque appel apt garde son jumeau pacman ; l'aperçu, l'unité ininterruptible et le journal root n'existent que sur Arch, donc la mise à jour d'un serveur Debian n'est pas protégée contre un terminal fermé.

## Shell

zsh + [zinit](https://github.com/zdharma-continuum/zinit) (autosuggestions, syntax-highlighting) + [Starship](https://starship.rs) (prompt) + fzf (`Ctrl+R` / `Ctrl+T` / `Alt+C`) + fastfetch (alias `ff`). La commande `update` est décrite dans [La commande update](#la-commande-update). Les raccourcis clavier (Ctrl+flèches, Home/End, Suppr…) viennent du fichier `key-bindings.zsh` d'Oh My Zsh, chargé seul via zinit. Tous les outils viennent de mise, avec une seule config pour toutes les machines.

Chaque machine reçoit une pastille colorée (emoji) calculée à partir de son nom d'hôte, affichée dans le titre d'onglet et dans le prompt : aucune configuration. En cas de collision entre deux machines, renommer l'une d'elles ou ajouter `export MACHINE_BADGE=🟢` dans `~/.zshenv` sur cette machine.

## tmux

Sur les machines de dev, tmux garde les sessions en vie quand la connexion SSH tombe. mise compile tmux depuis ses sources (plugin `mise-tmux`, avec `build-essential`, `libncurses-dev` et `bison` (Debian) ou `base-devel`, `ncurses` et `bison` (Arch) installés par `just build-deps`) : les binaires précompilés de `tmux/tmux-builds` ont des semaines de retard sur les versions de tmux. `tmux/tmux.conf` (lié par `just tmux`) ne contient que ce qui diffère des valeurs par défaut de tmux. Le préfixe est **Ctrl+A** (Ctrl+B sert à Claude Code pour passer une commande en arrière-plan).

`t` ouvre ou rattache une session tmux. `t .` (ou tout chemin, par exemple `t ~/dev/app`), lancé depuis un projet (n'importe quel sous-dossier d'un repo git), ouvre ou rattache la session du projet, nommée d'après le dossier de la racine git, dans le premier onglet. Une session sur le point d'être créée demande d'abord sa disposition (fzf, `tmux/layouts.sh`) : « Claude + shells » (`Entrée` ou `w` : Claude Code à gauche, deux shells empilés à droite), « Claude seul » (`c`) ou « Shell seul » (`s`) ; `Échap` ne crée rien. `tmux/workspace.sh <disposition> <dossier> <session>` la construit. Dans une nouvelle session, Claude reprend la dernière conversation du dossier (`claude --continue`), par exemple après un redémarrage de tmux, mais seulement si le dossier en a une (`~/.claude/projects`), car `--continue` échoue sinon ; un onglet ajouté à une session existante démarre une conversation neuve, pour que deux onglets ne partagent jamais la même. `t <nom>` rattache la session de ce nom, ou la crée si `<nom>` est un projet connu (`~/dev/<nom>` ou `~/dotfiles`) ; sinon, si `gh` est installé, il clone dans `~/dev/<nom>` le dépôt GitHub de ce nom quand il figure dans le cache (nom comparé sans tenir compte de la casse, le dossier prend l'orthographe du dépôt ; la question de la disposition vient d'abord, puis le clone affiche sa progression, et un clone en échec est une erreur, jamais un dossier vide) ; sinon il crée le dossier de projet `~/dev/<nom>` (lettres, chiffres, `_`, `.` et `-`, sans commencer par `.` ni `-` ; pas de `git init`) après la question de la disposition. `Tab` complète les sessions, les projets et les noms des dépôts GitHub pas encore clonés. Le cache (`~/.cache/dotfiles/github-repositories`) liste vos dépôts et ceux de vos organisations, sans les dépôts archivés ni les forks, via `gh` ; il est rafraîchi en arrière-plan quand il a plus de 10 minutes, donc seule la toute première utilisation sur une machine peut attendre quelques secondes. Les décisions viennent du seul cache, jamais du réseau. Les dépôts qui ont déjà une session ou un dossier, `~/dotfiles` et `~/notes` ne sont jamais proposés. Sans `gh` (serveurs), aucun comportement GitHub. `t` seul rattache la dernière session, ou ouvre le sélecteur de sessions quand on est déjà dans tmux ; sans aucune session, il ouvre le sélecteur directement dans le terminal, limité aux projets : `Entrée` crée la session du projet choisi (après la question de la disposition) et s'y rattache, `Échap` ne crée rien. Quand Claude se termine, son pane reste ouvert sur un shell. Dans tmux, `t` bascule vers la session sans en imbriquer une autre.

tmux se résume à deux notions : la session (en général un projet) et l'onglet. `Alt+n` ou `Ctrl+A` puis `c` ouvre le menu « Nouvel onglet » : Claude + shells (`w`), Claude seul (`c`) ou shell seul (`s`), dans le dossier du pane courant (`tmux/new-tab-menu.conf`, défini une seule fois et réutilisé par la palette ; chaque entrée appelle `tmux/workspace.sh` avec sa disposition).

`Ctrl+A` puis `s` ouvre un sélecteur unique (fzf dans un popup) : les sessions ouvertes en arbre (la courante est marquée), chacune suivie de ses onglets avec le même libellé que la barre du haut, puis les dossiers de `~/dev` et `~/dotfiles` sans session, puis les dépôts GitHub pas encore clonés (`<owner>/<nom>  (GitHub, à cloner)`, seulement avec `gh`) : `Entrée` demande la disposition, clone dans `~/dev/<nom>`, puis ouvre la session. L'onglet courant est présélectionné, l'aperçu montre le pane de l'onglet visé, et le nom de la session reste filtrable depuis chaque onglet. `Entrée` bascule vers la session ou l'onglet, en créant la session d'un projet après la question de la disposition, `Échap` ferme sans rien faire (`tmux/session-picker.sh` ; `just test` vérifie le parcours des sessions sur un serveur tmux isolé, `tmux/session-flow.test.sh`). Un nom tapé dans le sélecteur peut devenir un nouveau projet : `Entrée` sur une saisie qui ne correspond à rien, ou `Alt+Entrée` quelles que soient les correspondances (l'en-tête affiche `créer ~/dev/<saisie>`), crée le dossier `~/dev/<nom>` après la question de la disposition (ou clone le dépôt quand le nom saisi est dans le cache GitHub) (même règle de nom que `t <nom>`, pas de `git init` ; un nom invalide affiche une erreur ; `Échap` à la question de la disposition ne crée rien). L'arborescence native des sessions et des onglets reste dans la palette.

`Ctrl+A` puis `n` ouvre les notes libres du projet dans un popup (micro en thème Cobalt2, `micro/colorschemes/cobalt2.micro`, lié par `just tmux` ; raccourcis à la VS Code : `Ctrl+S` sauve, `Ctrl+Q` ferme, `Ctrl+C` copie la sélection dans le presse-papiers du poste (OSC 52), sauvegarde automatique, historique `Ctrl+Z` conservé après fermeture). Le fichier est `~/notes/<projet>.md`, hors des repos ; le projet est le dossier de la racine git du pane courant, créé avec un titre au premier usage (`tmux/notes.sh`). `~/notes` est un dépôt git : l'ouverture fait un pull, chaque fermeture commite puis pousse vers le dépôt GitHub privé `notes` créé par `just notes`. Les commits sont signés `notes <notes@localhost>`, une adresse inconnue de GitHub : ils ne gonflent pas le graphe de contributions du profil. En cas de conflit ou d'échec, un message tmux le signale : demander à Claude de synchroniser `~/notes`. Cette touche remplace le `next-window` natif de tmux : `Alt+1` … `Alt+9` changent d'onglet.

La barre d'état tient sur deux lignes, en couleurs Cobalt2 : la première liste les sessions (la courante en jaune), la seconde les onglets, chacun nommé d'après le titre de son pane Claude, avec un seul rappel à droite : `Alt+h` (sans préfixe) ouvre la fiche de tous les raccourcis. Une cloche dans n'importe quel pane de l'onglet colore son onglet en rose ; Claude sonne via `claude/hooks/ring-bell.sh` dès qu'il termine un tour (pas tant que des tâches en arrière-plan ou des réveils programmés sont en attente : il sonne quand il a vraiment fini), quand un tour échoue, et quand il attend une réponse (permission, question) ; `preferredNotifChannel` vaut `notifications_disabled` dans `claude/settings.json`, donc la cloche intégrée d'inactivité, en retard de 60 s et aveugle aux shells en arrière-plan, ne sonne jamais. `Alt+1` … `Alt+9` changent d'onglet sans préfixe, et `Alt+&` … `Alt+ç` (la rangée de chiffres AZERTY) font de même.

`Alt+g` (sans préfixe) ouvre le menu « Code », en lecture seule (`tmux/code-menu.conf`, aussi dans la palette) : `d` affiche le diff du travail en cours dans diffnav (`tmux/code-diff.sh`), qui se rafraîchit toutes les 2 secondes et inclut les nouveaux fichiers non suivis, fichiers ignorés exclus (`tmux/working-tree-diff.sh` l'imprime) ; `f` parcourt les fichiers du dépôt avec fzf et un aperçu bat (`tmux/code-files.sh`, `Entrée` ouvre un fichier en plein écran, `q` revient, `Échap` ferme) ; `r` cherche dans le contenu des fichiers avec ripgrep et fzf (`tmux/code-search.sh` : on tape pour chercher, une regex est acceptée, insensible à la casse sauf si la saisie contient une majuscule, `Entrée` ouvre le fichier en plein écran à la ligne trouvée, `q` revient aux résultats, `Échap` ferme) ; `c` parcourt les commits de la branche courante avec fzf et un aperçu delta (`tmux/code-log.sh` : on tape pour filtrer, un merge est montré face à son premier parent, `Entrée` ouvre le commit dans diffnav, `q` revient à la liste, `Échap` ferme). Quand le dépôt a plusieurs worktrees (ceux des agents Claude, par exemple), chaque vue demande d'abord lequel (`tmux/pick-worktree.sh`), le plus récemment modifié en premier, `Échap` ferme. Rien dans ces vues ne peut modifier le dépôt. Dans un shell, `git diff`, `git show` et `git log -p` passent par delta (`.gitconfig` ; `n` / `N` sautent au fichier suivant / précédent). `diffnav`, `bat`, `ripgrep` et `delta` sont installés par mise sur les machines de dev, pas sur les serveurs.

`Ctrl+A` puis `Ctrl+K` ouvre une palette de commandes (fzf dans un popup) : les actions de `tmux/palette.tsv` (libellé, raccourci, commande tmux ; une action = une ligne), `Entrée` lance la commande sur le pane d'où la palette a été ouverte, `Échap` ferme (`tmux/command-palette.sh`).

Après `update`, les instances Claude Code déjà ouvertes gardent l'ancien binaire : l'action « Relancer les Claude Code inactifs » de la palette relance celles qui sont inactives avec `claude --resume`, passe celles qui travaillent et celles déjà à jour (`tmux/restart-claude.sh`).

Les raccourcis vivent dans `tmux/cheatsheet.md` ; `Alt+h` (sans préfixe) l'ouvre dans tmux.

`tmux ls` liste les sessions. La souris est activée : glisser sélectionne du texte dans un seul pane sans le copier, `Ctrl+C` ou `Entrée` le copie dans le presse-papiers du poste, un clic ou `Échap` annule.

## Claude Code

`claude/` contient la config utilisateur de Claude Code, appliquée par `just claude` (lancé par `just dev`) :

- **Liés** : les fichiers `.md` de premier niveau de `claude/` (`CLAUDE.md`, `RTK.md`), chaque fichier de `claude/agents/` et chaque dossier de `claude/skills/` sont liés un par un dans `~/.claude/` (`~/.claude/CLAUDE.md`, `~/.claude/RTK.md`, `~/.claude/agents/<nom>.md`, `~/.claude/skills/<nom>`). Le reste de `~/.claude/skills/` (`synced/`, skills installés par `npx skills`, plugins) n'est pas touché.
- **Fusionné** : `claude/settings.json` est une base fusionnée (jq) dans `~/.claude/settings.json`, jamais liée : Claude Code réécrit ce fichier lui-même. Les clés du repo l'emportent, les clés propres à la machine (`model`, `theme`…) restent.
- **Plugins et marketplaces** : ceux déclarés dans `claude/settings.json` (`enabledPlugins`, `extraKnownMarketplaces`) sont enregistrés dans `~/.claude/dotfiles-managed.json`. Quand l'un est retiré du repo, `just claude` (via `claude/prune-plugins.sh`) lance `claude plugin uninstall` ou `claude plugin marketplace remove` et retire sa clé de `~/.claude/settings.json`. Les plugins installés à la main, jamais déclarés dans le repo, ne sont jamais touchés. Si un retrait échoue (ou si `claude` n'est pas dans le `PATH`), l'enregistrement est conservé et le `just claude` suivant réessaie.
- **rtk** : `rtk` (installé par `just mise`) compresse la sortie des commandes avant qu'elle n'atteigne Claude. Les réglages de base déclarent son hook `PreToolUse` (`rtk hook claude`) et `CLAUDE.md` importe `RTK.md` : aucun `rtk init` à lancer. Ne pas relancer `rtk init -g` (il modifierait `settings.json` et écrirait à travers le lien `RTK.md`) ; si une nouvelle version de rtk change `RTK.md`, le régénérer ailleurs et le copier dans `claude/RTK.md`. `rtk/config.toml` est lié vers `~/.config/rtk/config.toml` et ne contient que des surcharges des valeurs par défaut de rtk : il exclut `pnpm run lint`, `pnpm lint` et `npm run lint` de la réécriture, car rtk les transformerait en `rtk lint`, un run ESLint uniquement qui échoue sur les projets lintés avec oxlint.
- `claude/statusline.sh` est référencé directement par les réglages de base : rien à installer. Il colore les usages 5h et 7d selon le rythme (usage comparé à la part écoulée de la fenêtre, avec `+N` points quand il est en avance et `-N` quand il est en retard, au-delà de la tolérance sur le 5h, toujours sur le 7d) et affiche les quotas les plus récents connus toutes sessions confondues plutôt que ceux, périmés, de chaque session. Une session dont les valeurs viennent de changer est crue même quand elles sont plus basses, pour qu'une réinitialisation de quota en cours de fenêtre apparaisse. Il journalise chaque changement des quotas dans `~/.local/state/claude/quota-usage.tsv` (`$XDG_STATE_HOME/claude/` si défini), pour calibrer les seuils.
- **Garde des skills de doc et de code** : `claude/hooks/require-skill.sh`, référencé par les réglages de base (hook `PreToolUse` sur `Edit|Write`), refuse toute modification d'un `CLAUDE.md`, `CLAUDE.local.md`, `AGENTS.md` ou `.claude/rules/*.md` tant que le skill `claude-md` n'a pas été chargé, d'un `README.md`, `docs/**/*.md`, `CONTRIBUTING.md`, `DEPLOY.md`, `PUBLISHING.md` ou `SECURITY.md` tant que le skill `project-docs` ne l'a pas été, et des fichiers TypeScript tant que `typescript-conventions` ne l'a pas été (plus `react-conventions` pour les `.tsx`, `adonis-conventions` pour les `.ts` d'un projet AdonisJS, repéré par son `adonisrc.ts`). Les fichiers de déclaration, `dist/`, `build/`, `.adonisjs/` et `node_modules/` sont ignorés, ainsi que `CHANGELOG.md` et `docs/adr/`. Un skill compte comme chargé quand il a été invoqué dans la session de l'agent qui édite, ou préchargé par la définition de cet agent (`skills:` dans `agents/<nom>.md`).
- **Garde de Context7** : `claude/hooks/require-context7.sh`, référencé par les réglages de base (hook `SessionStart`, asynchrone, et hook `UserPromptSubmit`), vérifie avec `claude mcp get plugin:context7:context7` que le serveur Context7 est connecté. Quand son statut n'est pas `Connected` (typiquement une authentification OAuth en attente), le premier prompt de la session est bloqué avec un message qui demande de lancer `/mcp` ; renvoyer le message le laisse passer. Elle ne bloque qu'une fois par session, donc une panne de Context7 n'enferme jamais l'utilisateur, et ne fait rien quand le statut est indéterminé (pas de `claude` dans le `PATH`, erreur, timeout de 10 s).

Avant de remplacer quoi que ce soit, `just claude` déplace l'existant dans `~/.claude/backups/dotfiles-<date>/` (même chemin relatif) et affiche chaque sauvegarde. Rien n'est supprimé, sauf les liens vers le repo devenus orphelins (skill ou agent retiré du repo).

- **Retirer un réglage** : la fusion ajoute et écrase seulement. Une clé retirée de `claude/settings.json` (hors plugins et marketplaces) se retire à la main de `~/.claude/settings.json`.
- **Ajouter un skill ou un agent** : le créer dans `claude/skills/<nom>/SKILL.md` ou `claude/agents/<nom>.md`, puis `just claude`.
- **Hors repo** : les skills installés par `npx skills` ou par des plugins restent hors du repo.
- Seuls les réglages indépendants de la machine et non sensibles vont dans `claude/settings.json`.

`c` ouvre la vue des agents (`claude agents`, sessions en arrière-plan) depuis `~/dev`, pour que `@` tapé dans un prompt liste les projets où lancer la session ; le dossier courant du shell ne change pas. Ses arguments vont à `claude agents` (par exemple `c --cwd ~/dev/app`). `Entrée` sur une ligne ouvre la session et `←` revient à la liste, d'où l'absence de raccourci `attach` séparé. Les réglages de base gardent les transcripts 10 ans (`cleanupPeriodDays: 3650`, car `0` est refusé) : une session supprimée de la liste reste lisible et reprenable avec `claude --resume`.

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

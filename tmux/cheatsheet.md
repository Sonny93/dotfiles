# Fiche tmux

- **Session** : survit à la déconnexion SSH, en général née d'un projet.
- **Window** = un onglet.
- **Pane** = une window découpée en plusieurs zones.

**Préfixe** : appuyer sur `Ctrl+A`, relâcher, puis appuyer sur la touche.

**Palette de commandes** : préfixe puis `Ctrl+K` liste toutes les actions avec leur raccourci. On tape pour filtrer, `Entrée` lance, `Échap` ferme.

`t` : rattache la dernière session (aucune session : ouvre le sélecteur des projets ; dans tmux, ouvre le sélecteur). `t .` : ouvre ou rattache la session du projet courant. `t <nom>` : session ou projet de ce nom (`Tab` complète), ou, s'il n'existe pas, dépôt GitHub à cloner dans `~/dev/<nom>` quand `gh` le connaît (cache rafraîchi en arrière-plan, le premier usage peut attendre quelques secondes ; dépôts archivés et forks masqués, organisations incluses, `~/notes` et `~/dotfiles` jamais proposés ; sans `gh`, aucun dépôt GitHub), sinon nouveau projet `~/dev/<nom>`. Une nouvelle session demande d'abord sa disposition : `Entrée` (Claude + shells), `w`, `c` ou `s`, `Échap` annule.

**Claude + shells** (menu Nouvel onglet, `Alt+n`) : une window de 3 panes, Claude à gauche, deux shells empilés à droite.

```
┌──────────┬────────┐
│          │ shell  │
│  claude  ├────────┤
│          │ shell  │
└──────────┴────────┘
```

**Barre du haut** : ligne 1 = les sessions (la courante en jaune), ligne 2 = les onglets. Chaque onglet affiche le titre du pane Claude, plus le dossier s'il diffère de celui de la session. Un onglet rose = une cloche (Claude a fini ou attend).

## Windows

| Touche | Effet |
|---|---|
| `Alt+n` / `c` | Nouvel onglet (menu : Claude + shells, Claude, shell) ; `Alt+n` sans préfixe |
| `Alt+1` … `Alt+9` | Aller à la window n (sans préfixe) ; en AZERTY aussi `Alt+&` … `Alt+ç` |
| `p` | Précédente |
| `1` … `9` | Aller à la window n |
| `,` | Renommer |
| `&` | Fermer |

## Panes

| Touche | Effet |
|---|---|
| `%` | Couper en deux, côte à côte |
| `"` | Couper en deux, l'un sur l'autre |
| flèches | Se déplacer |
| `z` | Plein écran on/off |
| `x` | Fermer |

## Sessions

| Touche | Effet |
|---|---|
| `s` | Sessions, leurs onglets, projets sans session et dépôts GitHub à cloner (popup, on tape pour filtrer ; `Alt+Entrée` crée le projet `~/dev/<saisie>` ; une nouvelle session demande sa disposition) |
| `$` | Renommer (sans `.` ni `:`, sinon `t <nom>` et `s` ne la trouvent plus) |
| `d` | Se détacher : tout continue de tourner |

Fermer le dernier onglet d'une session bascule sur la session utilisée juste avant, au lieu de quitter tmux.

Depuis l'extérieur : `t` rattache la dernière session (ou ouvre le sélecteur des projets), `t .` rouvre celle du projet, `tmux ls` les liste.

## Notes

| Touche | Effet |
|---|---|
| `n` | Notes du projet (popup micro, `Ctrl+S` sauver, `Ctrl+Q` fermer, `Ctrl+C` copier la sélection, fichier `~/notes/<projet>.md`, sauvegardé et versionné automatiquement) |

## Défilement et copie

| Action | Effet |
|---|---|
| molette | Remonter dans l'historique |
| glisser, double-clic (mot), triple-clic (ligne) | Sélectionner dans un seul pane, sans copier ; `Ctrl+C` ou `Entrée` copie, un clic ou `Échap` annule |
| `[` | Mode copie (`q` pour sortir) |

## Aide

| Touche | Effet |
|---|---|
| `h` | Cette fiche (`q` pour fermer) |
| `?` | Tous les raccourcis |

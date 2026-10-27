# Fiche tmux

- **Session** : survit à la déconnexion SSH, en général née d'un projet.
- **Window** = un onglet.
- **Pane** = une window découpée en plusieurs zones.

**Préfixe** : appuyer sur `Ctrl+A`, relâcher, puis appuyer sur la touche.

**Palette de commandes** : préfixe puis `Ctrl+K` liste toutes les actions avec leur raccourci. On tape pour filtrer, `Entrée` lance, `Échap` ferme.

`t` : rattache la dernière session (aucune session : ouvre le sélecteur des projets ; dans tmux, ouvre le sélecteur). `t .` : ouvre ou rattache la session du projet courant, avec la disposition Claude + shells. `t <nom>` : session ou projet de ce nom (`Tab` complète).

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
| `s` | Sessions, leurs onglets et projets sans session (popup, on tape pour filtrer) |
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

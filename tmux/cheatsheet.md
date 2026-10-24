# Fiche tmux

- **Session** = un projet. Elle survit à la déconnexion SSH.
- **Window** = un onglet (un workspace par window).
- **Pane** = une window découpée en plusieurs zones.

**Préfixe** : appuyer sur `Ctrl+A`, relâcher, puis appuyer sur la touche.

`cc` depuis un projet : ouvre ou rattache la session du projet, avec le workspace.

**Workspace** (`Alt+n`, sans préfixe) : une window de 3 panes, Claude à gauche, deux shells empilés à droite.

```
┌──────────┬────────┐
│          │ shell  │
│  claude  ├────────┤
│          │ shell  │
└──────────┴────────┘
```

**Barre du haut** : ligne 1 = les sessions (la courante en jaune), ligne 2 = les windows. Chaque onglet affiche le titre du pane Claude, plus le dossier s'il diffère de celui de la session. Un onglet rose = une cloche (Claude a fini ou attend).

## Windows

| Touche | Effet |
|---|---|
| `Alt+n` | Nouveau workspace (sans préfixe) |
| `Alt+1` … `Alt+9` | Aller à la window n (sans préfixe) |
| `C` | Nouveau Claude seul |
| `c` | Nouveau shell seul |
| `n` / `p` | Suivante / précédente |
| `1` … `9` | Aller à la window n |
| `w` | Liste des windows |
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
| `s` | Liste des sessions (= les projets) |
| `$` | Renommer |
| `d` | Se détacher : tout continue de tourner |

Depuis l'extérieur : `tmux ls` liste les sessions, `cc` rouvre celle du projet.

## Défilement et copie

| Action | Effet |
|---|---|
| molette | Remonter dans l'historique |
| `Shift` + glisser | Sélectionner avec Tabby |
| `[` | Mode copie (`q` pour sortir) |

## Aide

| Touche | Effet |
|---|---|
| `h` | Cette fiche (`q` pour fermer) |
| `?` | Tous les raccourcis |

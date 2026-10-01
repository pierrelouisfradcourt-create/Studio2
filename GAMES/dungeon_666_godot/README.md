# Dungeon 666 — version Godot

`statut_artefact : PROPOSED` · `claim_verdict : NO_CLAIM_ALLOWED`. Demande de Pierre du
2026-10-01 : « une version plus propre sur Godot ».

Le prototype web (`GAMES/dungeon_666/`) reste la **référence des règles**. Cette version en est
le portage : même simulation, vérifiée par une machine ; nouvelle couche visible en nœuds et
scènes Godot.

| Dossier | Rôle |
|---|---|
| `sim/` | La simulation, portée module par module de `src/sim/*.mjs` (règles : `PORTAGE.md`). Ne connaît pas Godot. |
| `data/` | Tous les nombres et tables du jeu, exportés de la version web (jamais édités ici). |
| `jeu/` | Ce qui se voit, s'entend, se touche (contrat : `jeu/ARCHITECTURE.md`). |
| `parite/` | Rejeu des parties notées côté web, comparaison au bit près. |
| `tests/` | Oracle headless des fonctions pures. |
| `outils/` | `verifier.sh` (l'oracle complet), `capture.gd` (une scène → des PNG). |
| `addons/studio_kit/` | Le socle du studio (sauvegarde, thème, réglages). |

## Vérifier

```
bash outils/verifier.sh
```

1. la version web exporte données, vecteurs et parties notées (`node tools/export_godot.mjs`) ;
2. Godot enregistre ses classes ; 3. chaque fonction pure est comparée à ses vecteurs ;
4. 44 parties jouées par des bots côté web (les 6 armes, les 4 Gardiens et leurs 3 phases,
   sections entières de 7 minutes, entrées au hasard, labo du feel, arène, entraînement) sont
   rejouées par Godot : 7 373 empreintes d'état, égalité **exacte**.

Ce que cet oracle prouve : la simulation Godot calcule ce que calcule la simulation web. Ce qu'il
ne prouve pas : le rendu, les commandes, le son, le plaisir de jeu — à juger à l'écran et en main.
L'oracle sait rougir : trois erreurs introduites exprès (durée d'un tick de brûlure, plafond
d'armure, fenêtre de dash enchaîné) sont détectées.

## Changer une règle

Jamais ici d'abord. On change la règle dans `GAMES/dungeon_666/src/sim/`, on fait passer ses
tests (`node run-oracle.mjs`), puis on porte le changement dans `sim/` et on relance
`bash outils/verifier.sh` jusqu'au vert.

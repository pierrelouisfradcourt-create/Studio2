# parite/ — héritage

**Héritage : dernière parité exacte avec la version web prouvée le 2026-10-01 — 70 parties,
10 729 points de contrôle ; ces outils ne sont plus lancés.**

Jusqu'au 2026-10-01, la version web (`GAMES/dungeon_666/`) était la spécification et Godot devait
la rejouer au bit près. Décision de Pierre ce jour-là : « ne t'embête plus avec la version web,
continue le dev en local ». Godot est depuis seul maître de ses règles et de ses données ; l'oracle
est `bash outils/verifier.sh`, sans Node.

## Ce qui reste ici

| Fichier | Ce que c'était | État |
|---|---|---|
| `comparer.gd` (`D6Comparer`) | comparaison de deux valeurs, chemin du premier écart | **VIVANT** : `tests/harnais.gd` et `references/verifier.gd` s'en servent. Ne pas le déplacer. |
| `rejeu.gd`, `rejouer.gd` | rejeu des parties notées par le web (`parite/traces/`) | plus lancé |
| `verifier_bots.gd` | les bots Godot jouent-ils comme les bots web, image par image | plus lancé |
| `vecteurs.gd`, `adaptateurs/` | fonctions pures contre leurs vecteurs web (`parite/vecteurs/`) | plus lancé |
| `tests/run_tests.gd` (hors de ce dossier) | point d'entrée des vecteurs | plus lancé |
| `traces/`, `traces_denses/`, `vecteurs/`, `essai/` | fichiers générés par `node tools/export_godot.mjs` (27 Mo, hors dépôt) | restes sur disque, jamais régénérés |

`rejouer.gd` et `verifier_bots.gd` passeraient encore tant que les traces web sont sur le disque et
que ni règle ni nombre n'a changé. `tests/run_tests.gd` ne passe plus : il lit `data/tuning.json`
et `data/tables.json`, remplacés par les fichiers par domaine de `data/`. Aucun n'est une garde :
au premier changement voulu d'une règle ils rougiront, et c'est normal.

## Ce qui les remplace

| Avant | Maintenant |
|---|---|
| parties notées par le web, rejouées par Godot | `references/` : parties enregistrées PAR Godot (mêmes 70 parties, mêmes bots, mêmes graines), rejouées par `references/verifier.gd` |
| vecteurs de fonctions pures | `tests/regles/` : 333 tests de règles |
| `data/tuning.json`, `data/tables.json` exportés du web (`~` + 16 chiffres hexadécimaux) | `data/*.json` par domaine, JSON ordinaire, réglés à la main ; `data/validation.json` et `tests/regles/donnees.gd` |

## Les preuves du passage (2026-10-01)

- **Données.** Les 2 499 nombres des deux exports web (957 non entiers) sont relus par Godot,
  depuis le JSON ordinaire, **au bit près** : 0 écart, ordre des clés compris
  (`outils/donnees.gd -- comparer <dossier de l'ancien export>`). Trois d'entre eux (`DEG`, deux
  fois `DT`), que le JSON de Godot ne relit pas exactement, n'étaient lus par personne : ils sont
  recomposés depuis les constantes du code (`D6Data.DEG`, `D6Data.DT`), aux mêmes bits.
- **Références.** L'enregistreur Godot (`references/partie.gd`) a noté les 70 parties du catalogue :
  312 000 images d'entrées, chaque commande de menu et les 10 729 empreintes d'état sont
  **identiques** à celles des traces web. Les références partent donc de l'état prouvé égal au web.
- **Seul nombre changé** : `outils/classes.gd` plaçait les ennemis de l'essai « attaque maintenue »
  avec une table de cosinus de V8 (`V8_RING`) ; il passe par `D6Trig` comme toute la simulation.
  9 des 20 valeurs changent au dernier bit (au plus 4 × 10⁻¹⁴ unité de position). Effet mesuré
  (6 et 3 graines) : verdicts et lignes `FORGE_ORACLE` identiques ; trois mesures non bloquantes
  bougent de 0,2 coup (Dagues : diablotins 13,5 → 13,7, mêlée 14,9 → 15,1 ; Arbalète : mêlée
  9,3 → 9,1).

Pour retrouver l'état d'avant : le commit qui précède celui de la coupe, et
`node tools/export_godot.mjs` dans `GAMES/dungeon_666/`.

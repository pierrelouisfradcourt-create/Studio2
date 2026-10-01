# Playtest automatique — Dungeon 666

Généré par `node tools/playtest.mjs` le 2026-10-01T19:21:02.019Z. Graines 1 à 20, objectif : étage 19 (section 1 battue, boss au 18e), limite 30 min de temps simulé par run, arrêt à la première mort. Durée d'exécution : 11.5 s.

Labo du feel : D5 · Frappe de dash = **Fin du dash** (référence) · D8 · Gel d'impact = **Global** (référence) · D9 · Mobilité du combo = **Mobile** (référence).

Politiques : **skilled** (lit les télégraphes, dashe au dernier moment), **noDash** (même jeu sans dash ni gadget), **masher** (fonce et tape, dash aléatoire, ne lit rien).

## Synthèse

| Politique | Section battue | Section (hors blocages) | Morts | Blocages | Étage moyen | Dégâts / salle | Dégâts / min de combat | Coups reçus / min de combat | Esquives / min | Dash / min | Actions / min |
|---|---|---|---|---|---|---|---|---|---|---|---|
| skilled | 95 % | 95 % | 5 % | 0 | 18.95 | 3.3 | 11.8 | 0.59 | 0.91 | 30.2 | 104.6 |
| noDash | 15 % | 15 % | 85 % | 0 | 16.15 | 20.1 | 95.9 | 4.31 | 0.00 | 0.0 | 85.7 |
| masher | 0 % | 0 % | 100 % | 0 | 8.45 | 28.0 | 206.5 | 11.04 | 0.15 | 9.0 | 136.6 |

Valeurs agrégées sur toutes les salles de combat jouées (étage <= 18) : total des dégâts / nombre de salles, et / minutes de combat (de l'entrée au nettoyage, ou à la mort ; gel d'impact exclu). « Esquives » = coups absorbés par les i-frames d'un dash (télémétrie de la sim).

**Valeur du dash** = dégâts subis par salle (noDash) / (skilled) = **6.05** ; par minute de combat = **8.14**. noDash n'a ni dash ni gadget : le ratio mesure le couple dash + gadget, pas le dash seul. Par salle, les morts de noDash plafonnent ses dégâts (PV max) : le ratio par minute est le plus robuste.

## Audit des dash (contrefactuel)

Chaque dash du bot skilled est rejoué 1 s depuis un clone de la partie : avec le dash, puis sans lui (meilleure esquive à pied, bot noDash).

| Dash audités | Décisifs (seul le futur sans dash est touché) | Nuisibles (le dash fait prendre un coup) | Coup inévitable (touché dans les deux cas) | Sans effet (aucun coup dans les deux cas) | Décisifs / min de combat |
|---|---|---|---|---|---|
| 3713 | 705 (19 %) | 40 | 31 | 2937 | 7.95 |

Lecture : « Dash / min » compte aussi les dash de confort ; seuls les dash décisifs prouvent que le dash sauve des coups.

## Causes de mort

| Politique | Causes de mort |
|---|---|
| skilled | bossOrb ×1 |
| noDash | bossSlam ×4, brute ×4, bossCharge ×4, charger ×3, bossOrb ×1, imp ×1 |
| masher | brute ×5, charger ×4, pyre ×4, pavois ×3, arrow ×2, stalker ×1, imp ×1 |

## Blocages (salle nettoyée, aucune sortie possible pendant 30 s)

Aucun blocage.

## Temps pour tuer par type d'ennemi (s, de l'apparition à la mort)

| Ennemi | skilled (moy / méd / p90, n) | noDash (moy / méd / p90, n) | masher (moy / méd / p90, n) |
|---|---|---|---|
| archer | 4.50 / 4.23 / 8.41 (675) | 3.87 / 3.88 / 7.02 (551) | 2.86 / 2.72 / 4.91 (274) |
| banner | 5.29 / 4.93 / 9.26 (54) | 3.66 / 3.12 / 6.63 (39) | — |
| brute | 7.41 / 6.83 / 12.83 (297) | 6.08 / 5.82 / 9.91 (249) | 3.79 / 3.50 / 6.22 (100) |
| charger | 5.14 / 4.73 / 8.60 (360) | 3.97 / 3.83 / 6.87 (328) | 2.97 / 2.75 / 5.09 (137) |
| exploder | 1.94 / 1.62 / 3.90 (360) | 2.05 / 1.77 / 3.97 (310) | 1.70 / 1.64 / 3.04 (188) |
| gardien | 47.76 / 44.70 / 73.41 (19) | 28.15 / 20.98 / 40.30 (3) | — |
| imp | 2.82 / 2.52 / 5.42 (1552) | 2.60 / 2.33 / 4.75 (1291) | 2.24 / 2.03 / 4.03 (531) |
| necromancer | 4.41 / 3.57 / 8.60 (139) | 4.38 / 4.54 / 7.90 (134) | 4.29 / 4.65 / 8.02 (23) |
| pavois | 6.41 / 6.40 / 10.53 (135) | 5.91 / 5.78 / 8.78 (120) | 8.17 / 7.99 / 10.87 (10) |
| pyromancer | 5.06 / 4.32 / 9.52 (281) | 4.33 / 3.90 / 7.98 (233) | 3.33 / 2.53 / 6.05 (71) |
| stalker | 4.06 / 3.70 / 6.95 (106) | 3.45 / 3.17 / 6.06 (75) | 3.57 / 3.32 / 4.86 (7) |

## Distribution — skilled

| Mesure | Moyenne | Médiane | p10 | p90 |
|---|---|---|---|---|
| Étage atteint | 18.95 | 19.00 | 19.00 | 19.00 |
| Dégâts subis / salle de combat (par run) | 3.32 | 2.91 | 0.86 | 5.76 |
| Coups reçus / min | 0.41 | 0.43 | 0.17 | 0.70 |
| Esquives (dash) / min | 0.91 | 0.66 | 0.33 | 1.50 |
| Dash / min | 30.18 | 30.04 | 27.86 | 32.20 |
| Actions / min | 104.64 | 103.84 | 97.28 | 111.68 |
| Coups pour tuer (mêlée / kills) | 1.91 | 1.93 | 1.57 | 2.37 |
| Durée du boss (s) | 47.76 | 44.70 | 29.51 | 73.41 |
| Durée du run (s) | 368.28 | 364.84 | 319.42 | 418.08 |
| Compétences (Lance) | 71.90 | 72.00 | 60.90 | 81.30 |
| Gadgets | 10.60 | 11.00 | 9.00 | 12.00 |
| Supers | 10.55 | 10.00 | 8.90 | 13.00 |
| Wall slams | 13.75 | 13.50 | 8.90 | 18.10 |
| Déviations | 33.80 | 31.00 | 14.00 | 61.20 |
| Événements de sim / min | 709.26 | 693.49 | 643.67 | 792.47 |
| Durée d'une salle de combat (s, toutes salles) | 14.69 | 14.07 | 5.81 | 23.36 |

## Distribution — noDash

| Mesure | Moyenne | Médiane | p10 | p90 |
|---|---|---|---|---|
| Étage atteint | 16.15 | 18.00 | 12.70 | 19.00 |
| Dégâts subis / salle de combat (par run) | 19.76 | 17.84 | 12.90 | 29.21 |
| Coups reçus / min | 2.97 | 2.72 | 2.04 | 4.27 |
| Esquives (dash) / min | 0.00 | 0.00 | 0.00 | 0.00 |
| Dash / min | 0.00 | 0.00 | 0.00 | 0.00 |
| Actions / min | 85.68 | 86.27 | 78.92 | 92.02 |
| Coups pour tuer (mêlée / kills) | 2.22 | 2.19 | 1.77 | 2.60 |
| Durée du boss (s) | 28.15 | 20.98 | 18.86 | 40.30 |
| Durée du run (s) | 266.03 | 282.13 | 187.19 | 316.77 |
| Compétences (Lance) | 47.80 | 50.00 | 32.90 | 59.70 |
| Gadgets | 0.00 | 0.00 | 0.00 | 0.00 |
| Supers | 7.65 | 7.00 | 3.90 | 10.10 |
| Wall slams | 7.00 | 7.00 | 3.00 | 11.20 |
| Déviations | 29.25 | 16.00 | 3.00 | 66.90 |
| Événements de sim / min | 634.11 | 640.12 | 561.32 | 678.29 |
| Durée d'une salle de combat (s, toutes salles) | 12.42 | 12.01 | 5.40 | 19.11 |

## Distribution — masher

| Mesure | Moyenne | Médiane | p10 | p90 |
|---|---|---|---|---|
| Étage atteint | 8.45 | 8.00 | 4.90 | 12.10 |
| Dégâts subis / salle de combat (par run) | 26.27 | 21.91 | 17.68 | 42.42 |
| Coups reçus / min | 6.08 | 6.02 | 4.34 | 8.06 |
| Esquives (dash) / min | 0.15 | 0.00 | 0.00 | 0.45 |
| Dash / min | 8.96 | 9.19 | 5.75 | 11.39 |
| Actions / min | 136.62 | 137.26 | 122.64 | 150.47 |
| Coups pour tuer (mêlée / kills) | 2.68 | 2.65 | 2.32 | 3.04 |
| Durée du boss (s) | — | — | — | — |
| Durée du run (s) | 113.37 | 101.53 | 52.31 | 179.45 |
| Compétences (Lance) | 0.00 | 0.00 | 0.00 | 0.00 |
| Gadgets | 0.00 | 0.00 | 0.00 | 0.00 |
| Supers | 0.00 | 0.00 | 0.00 | 0.00 |
| Wall slams | 1.25 | 0.50 | 0.00 | 4.00 |
| Déviations | 6.65 | 6.00 | 2.00 | 12.10 |
| Événements de sim / min | 647.81 | 635.31 | 606.48 | 692.86 |
| Durée d'une salle de combat (s, toutes salles) | 8.21 | 8.12 | 4.20 | 13.42 |

## Détail des runs

| Politique | Graine | Issue | Étage | Durée (s) | Dégâts / salle | Esquives | Boss (s) |
|---|---|---|---|---|---|---|---|
| skilled | 1 | section | 19 | 352 | 1.5 | 8 | 35.9 |
| skilled | 2 | section | 19 | 354 | 2.8 | 2 | 40.3 |
| skilled | 3 | section | 19 | 382 | 3.9 | 7 | 67.5 |
| skilled | 4 | section | 19 | 413 | 5.1 | 3 | 62.1 |
| skilled | 5 | dead | 18 | 431 | 7.7 | 3 | — |
| skilled | 6 | section | 19 | 334 | 1.7 | 5 | 24.1 |
| skilled | 7 | section | 19 | 366 | 7.5 | 6 | 48.8 |
| skilled | 8 | section | 19 | 369 | 4.9 | 2 | 30.9 |
| skilled | 9 | section | 19 | 434 | 5.6 | 2 | 76.8 |
| skilled | 10 | section | 19 | 417 | 0.9 | 5 | 72.5 |
| skilled | 11 | section | 19 | 363 | 1.7 | 3 | 33.5 |
| skilled | 12 | section | 19 | 370 | 5.2 | 4 | 55.9 |
| skilled | 13 | section | 19 | 357 | 0.0 | 4 | 48.1 |
| skilled | 14 | section | 19 | 397 | 4.5 | 3 | 79.1 |
| skilled | 15 | section | 19 | 345 | 3.7 | 17 | 47.4 |
| skilled | 16 | section | 19 | 292 | 3.1 | 13 | 41.5 |
| skilled | 17 | section | 19 | 314 | 2.3 | 6 | 28.0 |
| skilled | 18 | section | 19 | 395 | 2.3 | 9 | 40.5 |
| skilled | 19 | section | 19 | 363 | 0.8 | 2 | 44.7 |
| skilled | 20 | section | 19 | 320 | 1.5 | 3 | 29.9 |
| noDash | 1 | dead | 15 | 269 | 12.9 | 0 | — |
| noDash | 2 | dead | 18 | 326 | 21.8 | 0 | — |
| noDash | 3 | dead | 18 | 279 | 26.9 | 0 | — |
| noDash | 4 | dead | 13 | 195 | 16.3 | 0 | — |
| noDash | 5 | dead | 18 | 316 | 39.1 | 0 | — |
| noDash | 6 | section | 19 | 298 | 19.8 | 0 | 21.0 |
| noDash | 7 | dead | 13 | 211 | 22.0 | 0 | — |
| noDash | 8 | dead | 18 | 291 | 17.8 | 0 | — |
| noDash | 9 | dead | 14 | 235 | 12.7 | 0 | — |
| noDash | 10 | section | 19 | 380 | 33.3 | 0 | 45.1 |
| noDash | 11 | dead | 10 | 120 | 14.9 | 0 | — |
| noDash | 12 | dead | 16 | 295 | 14.3 | 0 | — |
| noDash | 13 | dead | 16 | 251 | 8.4 | 0 | — |
| noDash | 14 | dead | 7 | 97 | 18.6 | 0 | — |
| noDash | 15 | section | 19 | 312 | 15.7 | 0 | 18.3 |
| noDash | 16 | dead | 18 | 283 | 17.4 | 0 | — |
| noDash | 17 | dead | 18 | 278 | 20.0 | 0 | — |
| noDash | 18 | dead | 18 | 290 | 16.9 | 0 | — |
| noDash | 19 | dead | 18 | 281 | 17.9 | 0 | — |
| noDash | 20 | dead | 18 | 312 | 28.8 | 0 | — |
| masher | 1 | dead | 7 | 82 | 19.7 | 0 | — |
| masher | 2 | dead | 12 | 162 | 20.8 | 1 | — |
| masher | 3 | dead | 6 | 63 | 18.8 | 0 | — |
| masher | 4 | dead | 4 | 52 | 29.3 | 0 | — |
| masher | 5 | dead | 12 | 176 | 47.1 | 0 | — |
| masher | 6 | dead | 12 | 170 | 29.8 | 1 | — |
| masher | 7 | dead | 8 | 108 | 17.4 | 1 | — |
| masher | 8 | dead | 6 | 64 | 19.5 | 0 | — |
| masher | 9 | dead | 8 | 107 | 22.4 | 0 | — |
| masher | 10 | dead | 11 | 154 | 20.3 | 0 | — |
| masher | 11 | dead | 12 | 177 | 35.8 | 0 | — |
| masher | 12 | dead | 14 | 219 | 42.0 | 0 | — |
| masher | 13 | dead | 4 | 47 | 27.5 | 1 | — |
| masher | 14 | dead | 13 | 206 | 46.2 | 0 | — |
| masher | 15 | dead | 5 | 52 | 22.6 | 0 | — |
| masher | 16 | dead | 6 | 63 | 16.8 | 0 | — |
| masher | 17 | dead | 5 | 59 | 21.4 | 0 | — |
| masher | 18 | dead | 6 | 75 | 30.0 | 0 | — |
| masher | 19 | dead | 8 | 96 | 17.7 | 0 | — |
| masher | 20 | dead | 10 | 135 | 20.2 | 1 | — |

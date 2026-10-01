# Playtest automatique — Dungeon 666

Généré par `node tools/playtest.mjs` le 2026-10-01T13:29:59.332Z. Graines 1 à 20, objectif : étage 19 (section 1 battue, boss au 18e), limite 30 min de temps simulé par run, arrêt à la première mort. Durée d'exécution : 11.9 s.

Labo du feel : D5 · Frappe de dash = **Fin du dash** (référence) · D8 · Gel d'impact = **Global** (référence) · D9 · Mobilité du combo = **Mobile** (référence).

Politiques : **skilled** (lit les télégraphes, dashe au dernier moment), **noDash** (même jeu sans dash ni gadget), **masher** (fonce et tape, dash aléatoire, ne lit rien).

## Synthèse

| Politique | Section battue | Section (hors blocages) | Morts | Blocages | Étage moyen | Dégâts / salle | Dégâts / min de combat | Coups reçus / min de combat | Esquives / min | Dash / min | Actions / min |
|---|---|---|---|---|---|---|---|---|---|---|---|
| skilled | 100 % | 100 % | 0 % | 0 | 19.00 | 2.3 | 7.9 | 0.40 | 0.92 | 30.2 | 102.5 |
| noDash | 5 % | 5 % | 95 % | 0 | 16.30 | 20.3 | 94.4 | 4.19 | 0.00 | 0.0 | 86.2 |
| masher | 5 % | 5 % | 95 % | 0 | 10.40 | 39.1 | 248.0 | 11.36 | 0.16 | 9.0 | 141.5 |

Valeurs agrégées sur toutes les salles de combat jouées (étage <= 18) : total des dégâts / nombre de salles, et / minutes de combat (de l'entrée au nettoyage, ou à la mort ; gel d'impact exclu). « Esquives » = coups absorbés par les i-frames d'un dash (télémétrie de la sim).

**Valeur du dash** = dégâts subis par salle (noDash) / (skilled) = **8.91** ; par minute de combat = **11.92**. noDash n'a ni dash ni gadget : le ratio mesure le couple dash + gadget, pas le dash seul. Par salle, les morts de noDash plafonnent ses dégâts (PV max) : le ratio par minute est le plus robuste.

## Audit des dash (contrefactuel)

Chaque dash du bot skilled est rejoué 1 s depuis un clone de la partie : avec le dash, puis sans lui (meilleure esquive à pied, bot noDash).

| Dash audités | Décisifs (seul le futur sans dash est touché) | Nuisibles (le dash fait prendre un coup) | Coup inévitable (touché dans les deux cas) | Sans effet (aucun coup dans les deux cas) | Décisifs / min de combat |
|---|---|---|---|---|---|
| 3849 | 785 (20 %) | 29 | 18 | 3017 | 8.64 |

Lecture : « Dash / min » compte aussi les dash de confort ; seuls les dash décisifs prouvent que le dash sauve des coups.

## Causes de mort

| Politique | Causes de mort |
|---|---|
| skilled | aucune |
| noDash | bossSlam ×10, charger ×3, bossCharge ×2, brute ×1, arrow ×1, imp ×1, bossOrb ×1 |
| masher | brute ×7, charger ×5, imp ×2, bossSlam ×2, bossOrb ×2, bossCharge ×1 |

## Blocages (salle nettoyée, aucune sortie possible pendant 30 s)

Aucun blocage.

## Temps pour tuer par type d'ennemi (s, de l'apparition à la mort)

| Ennemi | skilled (moy / méd / p90, n) | noDash (moy / méd / p90, n) | masher (moy / méd / p90, n) |
|---|---|---|---|
| archer | 4.56 / 3.98 / 8.70 (741) | 4.09 / 4.00 / 7.61 (595) | 3.00 / 2.92 / 5.30 (354) |
| brute | 7.55 / 6.97 / 12.73 (351) | 6.77 / 6.37 / 10.87 (290) | 3.88 / 3.65 / 6.10 (156) |
| charger | 5.61 / 4.75 / 9.92 (387) | 4.40 / 4.01 / 7.36 (338) | 3.17 / 2.81 / 5.44 (206) |
| exploder | 2.04 / 1.82 / 3.99 (440) | 2.00 / 1.82 / 3.93 (335) | 1.90 / 1.82 / 3.43 (264) |
| gardien | 52.99 / 51.17 / 72.52 (20) | 45.38 / 45.38 / 45.38 (1) | 28.87 / 28.87 / 28.87 (1) |
| imp | 3.03 / 2.78 / 5.71 (1705) | 2.71 / 2.52 / 4.97 (1440) | 2.25 / 2.03 / 4.03 (830) |
| necromancer | 4.40 / 3.83 / 8.15 (169) | 4.29 / 3.45 / 8.54 (167) | 4.83 / 5.16 / 7.77 (84) |
| pyromancer | 5.69 / 5.45 / 9.82 (343) | 4.75 / 4.23 / 8.93 (286) | 3.93 / 3.64 / 7.29 (134) |

## Distribution — skilled

| Mesure | Moyenne | Médiane | p10 | p90 |
|---|---|---|---|---|
| Étage atteint | 19.00 | 19.00 | 19.00 | 19.00 |
| Dégâts subis / salle de combat (par run) | 2.26 | 2.06 | 0.00 | 4.44 |
| Coups reçus / min | 0.28 | 0.31 | 0.00 | 0.51 |
| Esquives (dash) / min | 0.92 | 0.73 | 0.41 | 1.67 |
| Dash / min | 30.21 | 30.44 | 25.73 | 33.86 |
| Actions / min | 102.52 | 101.08 | 94.78 | 111.56 |
| Coups pour tuer (mêlée / kills) | 1.80 | 1.64 | 1.46 | 2.25 |
| Durée du boss (s) | 52.99 | 51.17 | 36.39 | 72.52 |
| Durée du run (s) | 378.82 | 373.35 | 342.37 | 429.72 |
| Compétences (Lance) | 76.10 | 75.00 | 63.80 | 85.70 |
| Gadgets | 10.75 | 11.00 | 8.90 | 13.00 |
| Supers | 10.80 | 11.00 | 8.00 | 13.10 |
| Wall slams | 12.75 | 12.50 | 7.90 | 18.20 |
| Déviations | 31.20 | 27.00 | 18.80 | 50.00 |
| Événements de sim / min | 734.03 | 731.70 | 669.15 | 784.47 |
| Durée d'une salle de combat (s, toutes salles) | 14.84 | 13.72 | 5.84 | 24.26 |

## Distribution — noDash

| Mesure | Moyenne | Médiane | p10 | p90 |
|---|---|---|---|---|
| Étage atteint | 16.30 | 18.00 | 11.90 | 18.00 |
| Dégâts subis / salle de combat (par run) | 19.67 | 17.14 | 13.39 | 28.60 |
| Coups reçus / min | 2.83 | 2.62 | 1.99 | 3.77 |
| Esquives (dash) / min | 0.00 | 0.00 | 0.00 | 0.00 |
| Dash / min | 0.00 | 0.00 | 0.00 | 0.00 |
| Actions / min | 86.24 | 86.07 | 77.14 | 92.61 |
| Coups pour tuer (mêlée / kills) | 2.23 | 2.18 | 1.86 | 2.67 |
| Durée du boss (s) | 45.38 | 45.38 | 45.38 | 45.38 |
| Durée du run (s) | 275.53 | 300.78 | 178.39 | 338.30 |
| Compétences (Lance) | 53.05 | 56.50 | 33.70 | 69.20 |
| Gadgets | 0.00 | 0.00 | 0.00 | 0.00 |
| Supers | 8.00 | 8.00 | 4.00 | 13.00 |
| Wall slams | 8.30 | 8.00 | 3.90 | 13.10 |
| Déviations | 29.15 | 28.00 | 3.90 | 53.20 |
| Événements de sim / min | 605.64 | 621.86 | 544.62 | 662.25 |
| Durée d'une salle de combat (s, toutes salles) | 12.78 | 11.80 | 5.40 | 21.48 |

## Distribution — masher

| Mesure | Moyenne | Médiane | p10 | p90 |
|---|---|---|---|---|
| Étage atteint | 10.40 | 8.00 | 5.80 | 18.00 |
| Dégâts subis / salle de combat (par run) | 32.45 | 24.06 | 17.20 | 57.86 |
| Coups reçus / min | 6.12 | 6.11 | 4.34 | 8.12 |
| Esquives (dash) / min | 0.16 | 0.00 | 0.00 | 0.59 |
| Dash / min | 9.04 | 9.48 | 6.51 | 11.49 |
| Actions / min | 141.53 | 143.20 | 127.74 | 150.93 |
| Coups pour tuer (mêlée / kills) | 2.81 | 2.81 | 2.30 | 3.22 |
| Durée du boss (s) | 28.87 | 28.87 | 28.87 | 28.87 |
| Durée du run (s) | 159.07 | 101.78 | 61.68 | 308.63 |
| Compétences (Lance) | 0.00 | 0.00 | 0.00 | 0.00 |
| Gadgets | 0.00 | 0.00 | 0.00 | 0.00 |
| Supers | 0.00 | 0.00 | 0.00 | 0.00 |
| Wall slams | 3.30 | 2.00 | 0.00 | 7.10 |
| Déviations | 24.65 | 7.00 | 1.90 | 62.50 |
| Événements de sim / min | 667.15 | 653.56 | 597.63 | 747.12 |
| Durée d'une salle de combat (s, toutes salles) | 9.23 | 8.53 | 4.28 | 16.13 |

## Détail des runs

| Politique | Graine | Issue | Étage | Durée (s) | Dégâts / salle | Esquives | Boss (s) |
|---|---|---|---|---|---|---|---|
| skilled | 1 | section | 19 | 428 | 2.7 | 10 | 62.9 |
| skilled | 2 | section | 19 | 398 | 1.4 | 10 | 63.3 |
| skilled | 3 | section | 19 | 369 | 0.0 | 3 | 46.9 |
| skilled | 4 | section | 19 | 387 | 1.9 | 12 | 46.9 |
| skilled | 5 | section | 19 | 383 | 3.6 | 4 | 50.3 |
| skilled | 6 | section | 19 | 347 | 0.5 | 2 | 37.2 |
| skilled | 7 | section | 19 | 348 | 0.4 | 8 | 37.2 |
| skilled | 8 | section | 19 | 350 | 4.5 | 3 | 34.4 |
| skilled | 9 | section | 19 | 419 | 6.3 | 4 | 60.9 |
| skilled | 10 | section | 19 | 429 | 1.0 | 3 | 71.6 |
| skilled | 11 | section | 19 | 383 | 2.1 | 3 | 46.2 |
| skilled | 12 | section | 19 | 359 | 2.1 | 6 | 56.6 |
| skilled | 13 | section | 19 | 449 | 4.4 | 6 | 86.1 |
| skilled | 14 | section | 19 | 438 | 3.9 | 12 | 81.1 |
| skilled | 15 | section | 19 | 361 | 0.0 | 3 | 42.5 |
| skilled | 16 | section | 19 | 340 | 1.4 | 1 | 36.3 |
| skilled | 17 | section | 19 | 378 | 0.0 | 13 | 57.6 |
| skilled | 18 | section | 19 | 343 | 3.3 | 4 | 52.0 |
| skilled | 19 | section | 19 | 312 | 2.1 | 4 | 36.4 |
| skilled | 20 | section | 19 | 355 | 3.9 | 7 | 53.6 |
| noDash | 1 | dead | 12 | 178 | 12.8 | 0 | — |
| noDash | 2 | dead | 18 | 329 | 27.6 | 0 | — |
| noDash | 3 | dead | 13 | 185 | 15.3 | 0 | — |
| noDash | 4 | section | 19 | 344 | 49.1 | 0 | 45.4 |
| noDash | 5 | dead | 11 | 139 | 10.6 | 0 | — |
| noDash | 6 | dead | 18 | 338 | 20.2 | 0 | — |
| noDash | 7 | dead | 18 | 288 | 14.0 | 0 | — |
| noDash | 8 | dead | 18 | 300 | 19.2 | 0 | — |
| noDash | 9 | dead | 18 | 322 | 21.0 | 0 | — |
| noDash | 10 | dead | 18 | 351 | 18.9 | 0 | — |
| noDash | 11 | dead | 18 | 323 | 18.9 | 0 | — |
| noDash | 12 | dead | 11 | 178 | 14.3 | 0 | — |
| noDash | 13 | dead | 18 | 291 | 15.7 | 0 | — |
| noDash | 14 | dead | 18 | 319 | 15.3 | 0 | — |
| noDash | 15 | dead | 13 | 179 | 13.5 | 0 | — |
| noDash | 16 | dead | 13 | 209 | 17.6 | 0 | — |
| noDash | 17 | dead | 18 | 302 | 20.4 | 0 | — |
| noDash | 18 | dead | 18 | 318 | 16.7 | 0 | — |
| noDash | 19 | dead | 18 | 293 | 14.9 | 0 | — |
| noDash | 20 | dead | 18 | 327 | 37.4 | 0 | — |
| masher | 1 | dead | 8 | 112 | 23.8 | 0 | — |
| masher | 2 | dead | 6 | 63 | 17.3 | 0 | — |
| masher | 3 | dead | 7 | 83 | 17.3 | 0 | — |
| masher | 4 | section | 19 | 308 | 57.8 | 3 | 28.9 |
| masher | 5 | dead | 18 | 300 | 51.7 | 1 | — |
| masher | 6 | dead | 18 | 319 | 55.6 | 3 | — |
| masher | 7 | dead | 7 | 91 | 16.4 | 1 | — |
| masher | 8 | dead | 8 | 122 | 19.0 | 0 | — |
| masher | 9 | dead | 4 | 47 | 29.3 | 0 | — |
| masher | 10 | dead | 14 | 260 | 52.2 | 0 | — |
| masher | 11 | dead | 18 | 318 | 58.4 | 3 | — |
| masher | 12 | dead | 4 | 49 | 26.8 | 0 | — |
| masher | 13 | dead | 6 | 73 | 18.8 | 0 | — |
| masher | 14 | dead | 6 | 65 | 22.7 | 0 | — |
| masher | 15 | dead | 6 | 76 | 19.2 | 0 | — |
| masher | 16 | dead | 8 | 103 | 24.4 | 0 | — |
| masher | 17 | dead | 7 | 89 | 18.9 | 1 | — |
| masher | 18 | dead | 18 | 300 | 43.1 | 0 | — |
| masher | 19 | dead | 8 | 101 | 15.5 | 0 | — |
| masher | 20 | dead | 18 | 303 | 61.1 | 0 | — |

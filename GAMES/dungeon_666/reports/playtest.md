# Playtest automatique — Dungeon 666

Généré par `node tools/playtest.mjs` le 2026-10-01T11:03:04.560Z. Graines 1 à 20, objectif : étage 19 (section 1 battue, boss au 18e), limite 30 min de temps simulé par run, arrêt à la première mort. Durée d'exécution : 29.3 s.

Labo du feel : D5 · Frappe de dash = **Fin du dash** (référence) · D8 · Gel d'impact = **Global** (référence) · D9 · Mobilité du combo = **Mobile** (référence).

Politiques : **skilled** (lit les télégraphes, dashe au dernier moment), **noDash** (même jeu sans dash ni gadget), **masher** (fonce et tape, dash aléatoire, ne lit rien).

## Synthèse

| Politique | Section battue | Section (hors blocages) | Morts | Blocages | Étage moyen | Dégâts / salle | Dégâts / min de combat | Coups reçus / min de combat | Esquives / min | Dash / min | Actions / min |
|---|---|---|---|---|---|---|---|---|---|---|---|
| skilled | 100 % | 100 % | 0 % | 0 | 19.00 | 2.7 | 9.3 | 0.41 | 0.86 | 31.4 | 97.5 |
| noDash | 60 % | 60 % | 40 % | 0 | 18.10 | 16.0 | 61.8 | 2.61 | 0.00 | 0.0 | 81.9 |
| masher | 0 % | 0 % | 100 % | 0 | 7.80 | 34.8 | 243.5 | 11.32 | 0.08 | 8.7 | 136.8 |

Valeurs agrégées sur toutes les salles de combat jouées (étage <= 18) : total des dégâts / nombre de salles, et / minutes de combat (de l'entrée au nettoyage, ou à la mort ; gel d'impact exclu). « Esquives » = coups absorbés par les i-frames d'un dash (télémétrie de la sim).

**Valeur du dash** = dégâts subis par salle (noDash) / (skilled) = **6.03** ; par minute de combat = **6.68**. noDash n'a ni dash ni gadget : le ratio mesure le couple dash + gadget, pas le dash seul. Par salle, les morts de noDash plafonnent ses dégâts (PV max) : le ratio par minute est le plus robuste.

## Audit des dash (contrefactuel)

Chaque dash du bot skilled est rejoué 1 s depuis un clone de la partie : avec le dash, puis sans lui (meilleure esquive à pied, bot noDash).

| Dash audités | Décisifs (seul le futur sans dash est touché) | Nuisibles (le dash fait prendre un coup) | Coup inévitable (touché dans les deux cas) | Sans effet (aucun coup dans les deux cas) | Décisifs / min de combat |
|---|---|---|---|---|---|
| 4049 | 695 (17 %) | 22 | 20 | 3312 | 7.57 |

Lecture : « Dash / min » compte aussi les dash de confort ; seuls les dash décisifs prouvent que le dash sauve des coups.

## Causes de mort

| Politique | Causes de mort |
|---|---|
| skilled | aucune |
| noDash | bossOrb ×3, bossCharge ×2, bossSlam ×1, brute ×1, imp ×1 |
| masher | brute ×11, charger ×5, bossSlam ×2, bossOrb ×1, arrow ×1 |

## Blocages (salle nettoyée, aucune sortie possible pendant 30 s)

Aucun blocage.

## Temps pour tuer par type d'ennemi (s, de l'apparition à la mort)

| Ennemi | skilled (moy / méd / p90, n) | noDash (moy / méd / p90, n) | masher (moy / méd / p90, n) |
|---|---|---|---|
| archer | 4.69 / 4.47 / 8.65 (994) | 4.71 / 4.58 / 8.73 (918) | 3.04 / 3.10 / 5.49 (299) |
| brute | 7.31 / 6.87 / 11.97 (472) | 6.87 / 6.63 / 10.97 (471) | 3.75 / 3.67 / 5.49 (126) |
| charger | 5.32 / 4.72 / 9.38 (551) | 4.83 / 4.38 / 8.48 (578) | 3.11 / 2.90 / 5.37 (201) |
| exploder | 2.06 / 1.93 / 3.88 (558) | 2.01 / 1.78 / 3.82 (460) | 1.82 / 1.75 / 3.40 (219) |
| gardien | 46.74 / 43.02 / 64.57 (20) | 35.67 / 32.39 / 49.32 (12) | — |
| imp | 2.97 / 2.82 / 5.47 (1998) | 3.01 / 2.92 / 5.33 (1775) | 2.37 / 2.12 / 4.31 (626) |

## Distribution — skilled

| Mesure | Moyenne | Médiane | p10 | p90 |
|---|---|---|---|---|
| Étage atteint | 19.00 | 19.00 | 19.00 | 19.00 |
| Dégâts subis / salle de combat (par run) | 2.66 | 2.31 | 0.00 | 5.36 |
| Coups reçus / min | 0.29 | 0.31 | 0.00 | 0.56 |
| Esquives (dash) / min | 0.86 | 0.69 | 0.37 | 1.77 |
| Dash / min | 31.39 | 31.49 | 27.07 | 34.64 |
| Actions / min | 97.53 | 97.74 | 87.53 | 103.29 |
| Coups pour tuer (mêlée / kills) | 1.59 | 1.54 | 1.25 | 2.00 |
| Durée du boss (s) | 46.74 | 43.02 | 29.01 | 64.57 |
| Durée du run (s) | 382.98 | 382.09 | 327.78 | 436.24 |
| Compétences (Lance) | 75.40 | 74.50 | 58.90 | 90.20 |
| Gadgets | 10.50 | 10.00 | 8.00 | 12.30 |
| Supers | 13.10 | 13.00 | 11.00 | 15.10 |
| Wall slams | 18.35 | 19.00 | 8.80 | 28.40 |
| Déviations | 32.55 | 34.50 | 7.90 | 48.90 |
| Événements de sim / min | 746.12 | 756.32 | 686.92 | 796.45 |
| Durée d'une salle de combat (s, toutes salles) | 15.25 | 14.02 | 6.43 | 24.21 |

## Distribution — noDash

| Mesure | Moyenne | Médiane | p10 | p90 |
|---|---|---|---|---|
| Étage atteint | 18.10 | 19.00 | 17.60 | 19.00 |
| Dégâts subis / salle de combat (par run) | 15.85 | 16.03 | 9.89 | 19.83 |
| Coups reçus / min | 1.82 | 1.84 | 1.29 | 2.30 |
| Esquives (dash) / min | 0.00 | 0.00 | 0.00 | 0.00 |
| Dash / min | 0.00 | 0.00 | 0.00 | 0.00 |
| Actions / min | 81.92 | 82.60 | 74.38 | 88.90 |
| Coups pour tuer (mêlée / kills) | 2.14 | 2.21 | 1.69 | 2.53 |
| Durée du boss (s) | 35.67 | 32.39 | 25.29 | 49.32 |
| Durée du run (s) | 346.31 | 359.85 | 307.12 | 377.30 |
| Compétences (Lance) | 66.00 | 67.50 | 55.40 | 75.40 |
| Gadgets | 0.00 | 0.00 | 0.00 | 0.00 |
| Supers | 13.40 | 13.00 | 10.60 | 17.10 |
| Wall slams | 15.10 | 15.00 | 11.00 | 19.20 |
| Déviations | 48.60 | 47.50 | 23.40 | 74.60 |
| Événements de sim / min | 633.74 | 630.29 | 587.52 | 685.97 |
| Durée d'une salle de combat (s, toutes salles) | 14.48 | 13.55 | 6.13 | 23.06 |

## Distribution — masher

| Mesure | Moyenne | Médiane | p10 | p90 |
|---|---|---|---|---|
| Étage atteint | 7.80 | 6.00 | 4.00 | 18.00 |
| Dégâts subis / salle de combat (par run) | 29.25 | 25.23 | 18.64 | 49.91 |
| Coups reçus / min | 6.30 | 6.77 | 4.55 | 7.75 |
| Esquives (dash) / min | 0.08 | 0.00 | 0.00 | 0.25 |
| Dash / min | 8.66 | 7.96 | 4.99 | 12.52 |
| Actions / min | 136.80 | 135.92 | 127.88 | 150.03 |
| Coups pour tuer (mêlée / kills) | 2.81 | 2.86 | 2.35 | 3.21 |
| Durée du boss (s) | — | — | — | — |
| Durée du run (s) | 113.90 | 83.41 | 47.57 | 282.32 |
| Compétences (Lance) | 0.00 | 0.00 | 0.00 | 0.00 |
| Gadgets | 0.00 | 0.00 | 0.00 | 0.00 |
| Supers | 0.00 | 0.00 | 0.00 | 0.00 |
| Wall slams | 1.60 | 1.00 | 0.00 | 3.30 |
| Déviations | 9.15 | 5.00 | 0.90 | 23.00 |
| Événements de sim / min | 631.31 | 605.31 | 559.58 | 769.94 |
| Durée d'une salle de combat (s, toutes salles) | 8.68 | 8.72 | 4.10 | 13.70 |

## Détail des runs

| Politique | Graine | Issue | Étage | Durée (s) | Dégâts / salle | Esquives | Boss (s) |
|---|---|---|---|---|---|---|---|
| skilled | 1 | section | 19 | 434 | 4.6 | 3 | 39.7 |
| skilled | 2 | section | 19 | 328 | 0.0 | 3 | 17.0 |
| skilled | 3 | section | 19 | 383 | 4.5 | 6 | 48.1 |
| skilled | 4 | section | 19 | 460 | 7.5 | 15 | 85.3 |
| skilled | 5 | section | 19 | 501 | 5.1 | 9 | 107.8 |
| skilled | 6 | section | 19 | 404 | 1.5 | 6 | 43.5 |
| skilled | 7 | section | 19 | 327 | 2.4 | 2 | 30.2 |
| skilled | 8 | section | 19 | 337 | 3.0 | 11 | 36.5 |
| skilled | 9 | section | 19 | 381 | 3.3 | 4 | 32.9 |
| skilled | 10 | section | 19 | 396 | 3.9 | 5 | 57.1 |
| skilled | 11 | section | 19 | 381 | 7.6 | 5 | 52.5 |
| skilled | 12 | section | 19 | 327 | 0.0 | 2 | 18.3 |
| skilled | 13 | section | 19 | 391 | 2.2 | 4 | 42.3 |
| skilled | 14 | section | 19 | 383 | 0.0 | 7 | 58.4 |
| skilled | 15 | section | 19 | 392 | 2.1 | 4 | 46.6 |
| skilled | 16 | section | 19 | 364 | 0.0 | 2 | 30.4 |
| skilled | 17 | section | 19 | 359 | 2.5 | 3 | 42.5 |
| skilled | 18 | section | 19 | 340 | 1.4 | 6 | 30.3 |
| skilled | 19 | section | 19 | 360 | 1.5 | 3 | 53.0 |
| skilled | 20 | section | 19 | 412 | 0.0 | 12 | 62.3 |
| noDash | 1 | section | 19 | 314 | 13.9 | 0 | 25.3 |
| noDash | 2 | section | 19 | 406 | 27.9 | 0 | 59.9 |
| noDash | 3 | dead | 18 | 360 | 19.1 | 0 | — |
| noDash | 4 | dead | 18 | 345 | 14.4 | 0 | — |
| noDash | 5 | section | 19 | 375 | 19.4 | 0 | 32.0 |
| noDash | 6 | dead | 18 | 331 | 15.6 | 0 | — |
| noDash | 7 | section | 19 | 340 | 19.3 | 0 | 32.8 |
| noDash | 8 | section | 19 | 377 | 11.5 | 0 | 49.8 |
| noDash | 9 | dead | 18 | 362 | 16.4 | 0 | — |
| noDash | 10 | dead | 12 | 208 | 7.2 | 0 | — |
| noDash | 11 | section | 19 | 360 | 16.2 | 0 | 26.1 |
| noDash | 12 | section | 19 | 380 | 15.9 | 0 | 41.9 |
| noDash | 13 | section | 19 | 370 | 18.6 | 0 | 38.7 |
| noDash | 14 | section | 19 | 343 | 6.3 | 0 | 26.6 |
| noDash | 15 | dead | 18 | 356 | 14.6 | 0 | — |
| noDash | 16 | section | 19 | 366 | 10.2 | 0 | 25.4 |
| noDash | 17 | dead | 14 | 246 | 11.6 | 0 | — |
| noDash | 18 | section | 19 | 377 | 17.3 | 0 | 44.9 |
| noDash | 19 | dead | 18 | 373 | 23.9 | 0 | — |
| noDash | 20 | section | 19 | 337 | 17.8 | 0 | 24.6 |
| masher | 1 | dead | 5 | 62 | 25.2 | 0 | — |
| masher | 2 | dead | 7 | 91 | 18.9 | 0 | — |
| masher | 3 | dead | 7 | 99 | 34.1 | 0 | — |
| masher | 4 | dead | 8 | 128 | 27.3 | 0 | — |
| masher | 5 | dead | 18 | 279 | 35.9 | 1 | — |
| masher | 6 | dead | 18 | 314 | 61.3 | 0 | — |
| masher | 7 | dead | 7 | 101 | 15.3 | 0 | — |
| masher | 8 | dead | 5 | 61 | 21.0 | 0 | — |
| masher | 9 | dead | 4 | 48 | 27.0 | 0 | — |
| masher | 10 | dead | 6 | 92 | 22.7 | 0 | — |
| masher | 11 | dead | 13 | 208 | 48.8 | 2 | — |
| masher | 12 | dead | 4 | 47 | 25.3 | 0 | — |
| masher | 13 | dead | 6 | 81 | 16.7 | 1 | — |
| masher | 14 | dead | 5 | 53 | 23.2 | 0 | — |
| masher | 15 | dead | 5 | 66 | 24.2 | 0 | — |
| masher | 16 | dead | 5 | 58 | 23.0 | 0 | — |
| masher | 17 | dead | 4 | 49 | 26.5 | 0 | — |
| masher | 18 | dead | 18 | 311 | 59.6 | 0 | — |
| masher | 19 | dead | 4 | 43 | 28.8 | 0 | — |
| masher | 20 | dead | 7 | 86 | 20.3 | 0 | — |

# Playtest automatique — Dungeon 666

Généré par `node tools/playtest.mjs` le 2026-10-01T08:34:50.960Z. Graines 1 à 20, objectif : étage 7 (section 1 battue, boss au 6e), limite 12 min de temps simulé par run, arrêt à la première mort. Durée d'exécution : 10.9 s.

Politiques : **skilled** (lit les télégraphes, dashe au dernier moment), **noDash** (même jeu sans dash ni gadget), **masher** (fonce et tape, dash aléatoire, ne lit rien).

## Synthèse

| Politique | Section battue | Section (hors blocages) | Morts | Blocages | Étage moyen | Dégâts / salle | Dégâts / min de combat | Coups reçus / min de combat | Esquives / min | Dash / min | Actions / min |
|---|---|---|---|---|---|---|---|---|---|---|---|
| skilled | 95 % | 95 % | 5 % | 0 | 6.95 | 9.1 | 23.0 | 1.56 | 0.96 | 30.4 | 122.4 |
| noDash | 5 % | 5 % | 95 % | 0 | 5.95 | 30.6 | 106.7 | 6.77 | 0.00 | 0.0 | 95.2 |
| masher | 0 % | 0 % | 100 % | 0 | 5.20 | 34.4 | 188.1 | 10.04 | 0.14 | 9.2 | 195.6 |

Valeurs agrégées sur toutes les salles de combat jouées (étage <= 6) : total des dégâts / nombre de salles, et / minutes de combat (de l'entrée au nettoyage, ou à la mort ; gel d'impact exclu). « Esquives » = coups absorbés par les i-frames d'un dash (télémétrie de la sim).

**Valeur du dash** = dégâts subis par salle (noDash) / (skilled) = **3.36** ; par minute de combat = **4.64**. noDash n'a ni dash ni gadget : le ratio mesure le couple dash + gadget, pas le dash seul. Par salle, les morts de noDash plafonnent ses dégâts (PV max) : le ratio par minute est le plus robuste.

## Audit des dash (contrefactuel)

Chaque dash du bot skilled est rejoué 1 s depuis un clone de la partie : avec le dash, puis sans lui (meilleure esquive à pied, bot noDash).

| Dash audités | Décisifs (seul le futur sans dash est touché) | Nuisibles (le dash fait prendre un coup) | Coup inévitable (touché dans les deux cas) | Sans effet (aucun coup dans les deux cas) | Décisifs / min de combat |
|---|---|---|---|---|---|
| 1630 | 456 (28 %) | 18 | 25 | 1131 | 11.50 |

Lecture : « Dash / min » compte aussi les dash de confort ; seuls les dash décisifs prouvent que le dash sauve des coups.

## Causes de mort

| Politique | Causes de mort |
|---|---|
| skilled | bossOrb ×1 |
| noDash | bossSlam ×10, bossCharge ×8, arrow ×1 |
| masher | bossSlam ×9, brute ×5, charger ×2, bossCharge ×2, bossOrb ×2 |

## Blocages (salle nettoyée, aucune sortie possible pendant 30 s)

Aucun blocage.

## Temps pour tuer par type d'ennemi (s, de l'apparition à la mort)

| Ennemi | skilled (moy / méd / p90, n) | noDash (moy / méd / p90, n) | masher (moy / méd / p90, n) |
|---|---|---|---|
| archer | 4.40 / 4.10 / 8.22 (364) | 4.64 / 4.60 / 8.07 (361) | 2.46 / 2.33 / 4.40 (313) |
| brute | 9.05 / 8.68 / 13.32 (103) | 7.46 / 7.34 / 12.36 (102) | 3.21 / 3.23 / 5.05 (91) |
| charger | 5.22 / 4.72 / 8.44 (150) | 4.31 / 3.97 / 7.62 (137) | 2.47 / 2.33 / 4.28 (137) |
| exploder | 1.94 / 1.78 / 3.43 (170) | 2.16 / 2.12 / 3.95 (140) | 1.63 / 1.53 / 2.87 (230) |
| gardien | 42.29 / 40.68 / 58.38 (19) | 35.33 / 35.33 / 35.33 (1) | — |
| imp | 3.21 / 3.02 / 5.75 (703) | 3.02 / 2.94 / 5.20 (650) | 2.07 / 1.98 / 3.60 (636) |

## Distribution — skilled

| Mesure | Moyenne | Médiane | p10 | p90 |
|---|---|---|---|---|
| Étage atteint | 6.95 | 7.00 | 7.00 | 7.00 |
| Dégâts subis / salle de combat (par run) | 9.11 | 8.40 | 4.78 | 13.04 |
| Coups reçus / min | 1.17 | 1.12 | 0.69 | 1.76 |
| Esquives (dash) / min | 0.96 | 0.93 | 0.40 | 1.45 |
| Dash / min | 30.44 | 30.26 | 27.24 | 34.33 |
| Actions / min | 122.45 | 122.64 | 117.11 | 126.18 |
| Coups pour tuer (mêlée / kills) | 2.93 | 2.99 | 2.55 | 3.16 |
| Durée du boss (s) | 42.29 | 40.68 | 29.01 | 58.38 |
| Durée du run (s) | 159.61 | 160.30 | 137.31 | 175.18 |
| Compétences (Lance) | 30.70 | 31.00 | 24.90 | 35.30 |
| Gadgets | 3.55 | 4.00 | 3.00 | 4.00 |
| Supers | 4.45 | 4.00 | 4.00 | 5.00 |
| Wall slams | 8.50 | 8.00 | 4.90 | 12.20 |
| Déviations | 52.40 | 53.50 | 28.50 | 79.10 |
| Événements de sim / min | 758.37 | 760.22 | 688.72 | 817.17 |
| Durée d'une salle de combat (s, toutes salles) | 19.10 | 20.27 | 9.52 | 26.87 |

## Distribution — noDash

| Mesure | Moyenne | Médiane | p10 | p90 |
|---|---|---|---|---|
| Étage atteint | 5.95 | 6.00 | 6.00 | 6.00 |
| Dégâts subis / salle de combat (par run) | 30.53 | 29.50 | 21.04 | 36.90 |
| Coups reçus / min | 4.91 | 4.43 | 3.51 | 6.76 |
| Esquives (dash) / min | 0.00 | 0.00 | 0.00 | 0.00 |
| Dash / min | 0.00 | 0.00 | 0.00 | 0.00 |
| Actions / min | 95.19 | 96.19 | 83.04 | 106.08 |
| Coups pour tuer (mêlée / kills) | 2.60 | 2.60 | 2.08 | 3.06 |
| Durée du boss (s) | 35.33 | 35.33 | 35.33 | 35.33 |
| Durée du run (s) | 117.60 | 118.06 | 101.52 | 133.03 |
| Compétences (Lance) | 21.15 | 21.00 | 18.70 | 24.10 |
| Gadgets | 0.00 | 0.00 | 0.00 | 0.00 |
| Supers | 3.10 | 3.00 | 2.00 | 5.00 |
| Wall slams | 4.05 | 4.00 | 1.90 | 7.00 |
| Déviations | 31.40 | 27.00 | 6.00 | 57.10 |
| Événements de sim / min | 659.59 | 660.46 | 586.01 | 731.93 |
| Durée d'une salle de combat (s, toutes salles) | 17.41 | 18.13 | 9.22 | 23.84 |

## Distribution — masher

| Mesure | Moyenne | Médiane | p10 | p90 |
|---|---|---|---|---|
| Étage atteint | 5.20 | 6.00 | 3.90 | 6.00 |
| Dégâts subis / salle de combat (par run) | 34.19 | 35.03 | 26.15 | 40.64 |
| Coups reçus / min | 5.73 | 5.48 | 4.68 | 6.65 |
| Esquives (dash) / min | 0.14 | 0.00 | 0.00 | 0.65 |
| Dash / min | 9.22 | 9.41 | 4.96 | 12.82 |
| Actions / min | 195.61 | 196.76 | 188.89 | 203.20 |
| Coups pour tuer (mêlée / kills) | 3.00 | 2.96 | 2.55 | 3.47 |
| Durée du boss (s) | — | — | — | — |
| Durée du run (s) | 88.78 | 94.88 | 72.41 | 103.23 |
| Compétences (Lance) | 0.00 | 0.00 | 0.00 | 0.00 |
| Gadgets | 0.00 | 0.00 | 0.00 | 0.00 |
| Supers | 0.00 | 0.00 | 0.00 | 0.00 |
| Wall slams | 0.80 | 0.50 | 0.00 | 2.10 |
| Déviations | 19.25 | 10.50 | 6.00 | 35.30 |
| Événements de sim / min | 831.08 | 831.61 | 788.37 | 873.88 |
| Durée d'une salle de combat (s, toutes salles) | 11.07 | 12.13 | 6.45 | 14.37 |

## Détail des runs

| Politique | Graine | Issue | Étage | Durée (s) | Dégâts / salle | Esquives | Boss (s) |
|---|---|---|---|---|---|---|---|
| skilled | 1 | section | 7 | 157 | 17.0 | 4 | 37.2 |
| skilled | 2 | section | 7 | 174 | 12.0 | 3 | 58.3 |
| skilled | 3 | section | 7 | 175 | 5.6 | 2 | 45.1 |
| skilled | 4 | section | 7 | 137 | 9.0 | 3 | 28.7 |
| skilled | 5 | dead | 6 | 158 | 22.0 | 3 | — |
| skilled | 6 | section | 7 | 148 | 6.0 | 1 | 25.2 |
| skilled | 7 | section | 7 | 167 | 5.6 | 4 | 55.8 |
| skilled | 8 | section | 7 | 146 | 6.0 | 2 | 30.5 |
| skilled | 9 | section | 7 | 136 | 9.0 | 3 | 29.1 |
| skilled | 10 | section | 7 | 164 | 8.4 | 1 | 40.7 |
| skilled | 11 | section | 7 | 171 | 2.8 | 4 | 58.9 |
| skilled | 12 | section | 7 | 180 | 4.6 | 2 | 62.1 |
| skilled | 13 | section | 7 | 167 | 12.0 | 3 | 47.5 |
| skilled | 14 | section | 7 | 155 | 7.8 | 2 | 38.9 |
| skilled | 15 | section | 7 | 159 | 8.4 | 1 | 41.8 |
| skilled | 16 | section | 7 | 186 | 12.6 | 5 | 57.8 |
| skilled | 17 | section | 7 | 137 | 12.0 | 1 | 31.5 |
| skilled | 18 | section | 7 | 162 | 7.6 | 2 | 44.4 |
| skilled | 19 | section | 7 | 173 | 9.0 | 2 | 40.1 |
| skilled | 20 | section | 7 | 142 | 4.8 | 3 | 30.3 |
| noDash | 1 | dead | 6 | 124 | 31.6 | 0 | — |
| noDash | 2 | dead | 6 | 107 | 45.0 | 0 | — |
| noDash | 3 | dead | 6 | 130 | 32.4 | 0 | — |
| noDash | 4 | dead | 6 | 109 | 36.0 | 0 | — |
| noDash | 5 | dead | 6 | 130 | 35.6 | 0 | — |
| noDash | 6 | dead | 6 | 120 | 35.4 | 0 | — |
| noDash | 7 | dead | 6 | 109 | 16.0 | 0 | — |
| noDash | 8 | dead | 6 | 102 | 28.2 | 0 | — |
| noDash | 9 | dead | 6 | 133 | 28.6 | 0 | — |
| noDash | 10 | section | 7 | 141 | 57.6 | 0 | 35.3 |
| noDash | 11 | dead | 6 | 115 | 29.4 | 0 | — |
| noDash | 12 | dead | 6 | 111 | 21.6 | 0 | — |
| noDash | 13 | dead | 4 | 85 | 26.8 | 0 | — |
| noDash | 14 | dead | 6 | 113 | 34.6 | 0 | — |
| noDash | 15 | dead | 6 | 134 | 32.2 | 0 | — |
| noDash | 16 | dead | 6 | 130 | 26.6 | 0 | — |
| noDash | 17 | dead | 6 | 95 | 15.6 | 0 | — |
| noDash | 18 | dead | 6 | 130 | 29.6 | 0 | — |
| noDash | 19 | dead | 6 | 118 | 23.6 | 0 | — |
| noDash | 20 | dead | 6 | 118 | 24.2 | 0 | — |
| masher | 1 | dead | 4 | 77 | 26.3 | 1 | — |
| masher | 2 | dead | 6 | 95 | 33.4 | 0 | — |
| masher | 3 | dead | 3 | 47 | 38.7 | 0 | — |
| masher | 4 | dead | 4 | 78 | 27.5 | 1 | — |
| masher | 5 | dead | 6 | 103 | 42.8 | 0 | — |
| masher | 6 | dead | 6 | 94 | 39.4 | 0 | — |
| masher | 7 | dead | 4 | 84 | 33.0 | 0 | — |
| masher | 8 | dead | 6 | 103 | 38.0 | 0 | — |
| masher | 9 | dead | 4 | 79 | 28.0 | 0 | — |
| masher | 10 | dead | 6 | 99 | 47.0 | 0 | — |
| masher | 11 | dead | 6 | 97 | 30.6 | 0 | — |
| masher | 12 | dead | 6 | 89 | 18.4 | 0 | — |
| masher | 13 | dead | 6 | 94 | 39.2 | 1 | — |
| masher | 14 | dead | 3 | 55 | 36.7 | 0 | — |
| masher | 15 | dead | 6 | 106 | 39.2 | 1 | — |
| masher | 16 | dead | 6 | 101 | 29.6 | 0 | — |
| masher | 17 | dead | 6 | 97 | 40.4 | 0 | — |
| masher | 18 | dead | 6 | 100 | 37.6 | 0 | — |
| masher | 19 | dead | 6 | 102 | 32.8 | 0 | — |
| masher | 20 | dead | 4 | 74 | 25.3 | 0 | — |

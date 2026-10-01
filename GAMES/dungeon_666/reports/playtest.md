# Playtest automatique — Dungeon 666

Généré par `node tools/playtest.mjs` le 2026-10-01T09:20:41.612Z. Graines 1 à 20, objectif : étage 7 (section 1 battue, boss au 6e), limite 12 min de temps simulé par run, arrêt à la première mort. Durée d'exécution : 11.7 s.

Politiques : **skilled** (lit les télégraphes, dashe au dernier moment), **noDash** (même jeu sans dash ni gadget), **masher** (fonce et tape, dash aléatoire, ne lit rien).

## Synthèse

| Politique | Section battue | Section (hors blocages) | Morts | Blocages | Étage moyen | Dégâts / salle | Dégâts / min de combat | Coups reçus / min de combat | Esquives / min | Dash / min | Actions / min |
|---|---|---|---|---|---|---|---|---|---|---|---|
| skilled | 100 % | 100 % | 0 % | 0 | 7.00 | 6.4 | 15.7 | 0.94 | 1.75 | 34.2 | 112.5 |
| noDash | 20 % | 20 % | 80 % | 0 | 6.20 | 28.5 | 88.4 | 4.87 | 0.00 | 0.0 | 89.6 |
| masher | 0 % | 0 % | 100 % | 0 | 3.90 | 30.8 | 161.4 | 9.71 | 0.16 | 9.0 | 156.0 |

Valeurs agrégées sur toutes les salles de combat jouées (étage <= 6) : total des dégâts / nombre de salles, et / minutes de combat (de l'entrée au nettoyage, ou à la mort ; gel d'impact exclu). « Esquives » = coups absorbés par les i-frames d'un dash (télémétrie de la sim).

**Valeur du dash** = dégâts subis par salle (noDash) / (skilled) = **4.48** ; par minute de combat = **5.63**. noDash n'a ni dash ni gadget : le ratio mesure le couple dash + gadget, pas le dash seul. Par salle, les morts de noDash plafonnent ses dégâts (PV max) : le ratio par minute est le plus robuste.

## Audit des dash (contrefactuel)

Chaque dash du bot skilled est rejoué 1 s depuis un clone de la partie : avec le dash, puis sans lui (meilleure esquive à pied, bot noDash).

| Dash audités | Décisifs (seul le futur sans dash est touché) | Nuisibles (le dash fait prendre un coup) | Coup inévitable (touché dans les deux cas) | Sans effet (aucun coup dans les deux cas) | Décisifs / min de combat |
|---|---|---|---|---|---|
| 1814 | 404 (22 %) | 19 | 19 | 1372 | 9.96 |

Lecture : « Dash / min » compte aussi les dash de confort ; seuls les dash décisifs prouvent que le dash sauve des coups.

## Causes de mort

| Politique | Causes de mort |
|---|---|
| skilled | aucune |
| noDash | bossSlam ×7, bossOrb ×5, bossCharge ×4 |
| masher | brute ×9, charger ×8, bossSlam ×2, arrow ×1 |

## Blocages (salle nettoyée, aucune sortie possible pendant 30 s)

Aucun blocage.

## Temps pour tuer par type d'ennemi (s, de l'apparition à la mort)

| Ennemi | skilled (moy / méd / p90, n) | noDash (moy / méd / p90, n) | masher (moy / méd / p90, n) |
|---|---|---|---|
| archer | 4.34 / 4.10 / 7.56 (359) | 4.36 / 4.31 / 7.92 (326) | 2.85 / 2.72 / 4.71 (247) |
| brute | 7.43 / 7.12 / 11.36 (92) | 7.01 / 6.83 / 10.53 (88) | 3.53 / 3.65 / 5.45 (46) |
| charger | 4.84 / 4.63 / 8.53 (186) | 4.72 / 4.39 / 7.77 (188) | 3.11 / 2.98 / 4.99 (136) |
| exploder | 1.93 / 1.57 / 3.85 (219) | 1.91 / 1.78 / 3.52 (176) | 1.89 / 1.82 / 3.40 (191) |
| gardien | 51.67 / 50.62 / 63.55 (20) | 47.03 / 46.37 / 57.81 (4) | — |
| imp | 2.84 / 2.60 / 5.04 (795) | 2.89 / 2.77 / 4.99 (718) | 2.24 / 2.03 / 4.03 (520) |

## Distribution — skilled

| Mesure | Moyenne | Médiane | p10 | p90 |
|---|---|---|---|---|
| Étage atteint | 7.00 | 7.00 | 7.00 | 7.00 |
| Dégâts subis / salle de combat (par run) | 6.37 | 6.00 | 3.00 | 12.06 |
| Coups reçus / min | 0.72 | 0.75 | 0.36 | 1.20 |
| Esquives (dash) / min | 1.75 | 1.35 | 0.37 | 3.85 |
| Dash / min | 34.25 | 33.93 | 31.10 | 37.71 |
| Actions / min | 112.49 | 113.21 | 108.13 | 116.76 |
| Coups pour tuer (mêlée / kills) | 2.14 | 2.17 | 1.88 | 2.38 |
| Durée du boss (s) | 51.67 | 50.62 | 40.33 | 63.55 |
| Durée du run (s) | 158.73 | 160.42 | 140.28 | 170.18 |
| Compétences (Lance) | 31.50 | 32.00 | 27.90 | 35.00 |
| Gadgets | 3.80 | 4.00 | 3.00 | 5.00 |
| Supers | 4.60 | 4.50 | 4.00 | 5.10 |
| Wall slams | 6.20 | 5.00 | 3.90 | 9.10 |
| Déviations | 35.25 | 33.50 | 19.00 | 54.20 |
| Événements de sim / min | 779.29 | 771.07 | 717.67 | 860.10 |
| Durée d'une salle de combat (s, toutes salles) | 17.50 | 17.91 | 9.50 | 22.83 |

## Distribution — noDash

| Mesure | Moyenne | Médiane | p10 | p90 |
|---|---|---|---|---|
| Étage atteint | 6.20 | 6.00 | 6.00 | 7.00 |
| Dégâts subis / salle de combat (par run) | 28.51 | 29.40 | 21.42 | 35.06 |
| Coups reçus / min | 3.59 | 3.47 | 2.55 | 4.52 |
| Esquives (dash) / min | 0.00 | 0.00 | 0.00 | 0.00 |
| Dash / min | 0.00 | 0.00 | 0.00 | 0.00 |
| Actions / min | 89.56 | 90.02 | 81.19 | 98.99 |
| Coups pour tuer (mêlée / kills) | 2.50 | 2.51 | 2.20 | 2.86 |
| Durée du boss (s) | 47.03 | 46.37 | 36.80 | 57.81 |
| Durée du run (s) | 131.79 | 127.83 | 117.44 | 152.02 |
| Compétences (Lance) | 24.60 | 24.00 | 21.90 | 30.10 |
| Gadgets | 0.00 | 0.00 | 0.00 | 0.00 |
| Supers | 3.55 | 3.00 | 3.00 | 5.00 |
| Wall slams | 5.00 | 5.00 | 2.00 | 8.10 |
| Déviations | 36.30 | 32.50 | 19.20 | 56.00 |
| Événements de sim / min | 657.84 | 640.56 | 596.44 | 728.60 |
| Durée d'une salle de combat (s, toutes salles) | 16.62 | 17.57 | 9.23 | 22.53 |

## Distribution — masher

| Mesure | Moyenne | Médiane | p10 | p90 |
|---|---|---|---|---|
| Étage atteint | 3.90 | 4.00 | 3.00 | 4.20 |
| Dégâts subis / salle de combat (par run) | 31.21 | 31.13 | 26.50 | 36.70 |
| Coups reçus / min | 6.14 | 6.01 | 5.00 | 7.59 |
| Esquives (dash) / min | 0.16 | 0.00 | 0.00 | 0.74 |
| Dash / min | 8.95 | 9.12 | 5.09 | 12.27 |
| Actions / min | 156.05 | 155.64 | 142.72 | 171.91 |
| Coups pour tuer (mêlée / kills) | 2.24 | 2.24 | 1.93 | 2.45 |
| Durée du boss (s) | — | — | — | — |
| Durée du run (s) | 70.17 | 70.24 | 55.09 | 83.89 |
| Compétences (Lance) | 0.00 | 0.00 | 0.00 | 0.00 |
| Gadgets | 0.00 | 0.00 | 0.00 | 0.00 |
| Supers | 0.00 | 0.00 | 0.00 | 0.00 |
| Wall slams | 1.30 | 1.00 | 0.00 | 3.00 |
| Déviations | 7.20 | 4.50 | 3.00 | 10.70 |
| Événements de sim / min | 717.63 | 719.17 | 663.69 | 762.94 |
| Durée d'une salle de combat (s, toutes salles) | 11.69 | 12.42 | 7.12 | 15.96 |

## Détail des runs

| Politique | Graine | Issue | Étage | Durée (s) | Dégâts / salle | Esquives | Boss (s) |
|---|---|---|---|---|---|---|---|
| skilled | 1 | section | 7 | 152 | 12.0 | 4 | 43.8 |
| skilled | 2 | section | 7 | 150 | 6.0 | 9 | 49.4 |
| skilled | 3 | section | 7 | 161 | 6.0 | 4 | 51.8 |
| skilled | 4 | section | 7 | 161 | 0.0 | 1 | 54.4 |
| skilled | 5 | section | 7 | 136 | 3.0 | 13 | 34.0 |
| skilled | 6 | section | 7 | 159 | 6.0 | 5 | 52.7 |
| skilled | 7 | section | 7 | 160 | 6.0 | 10 | 47.8 |
| skilled | 8 | section | 7 | 174 | 6.0 | 14 | 71.9 |
| skilled | 9 | section | 7 | 158 | 3.8 | 2 | 45.9 |
| skilled | 10 | section | 7 | 202 | 12.6 | 4 | 78.0 |
| skilled | 11 | section | 7 | 150 | 6.0 | 4 | 44.7 |
| skilled | 12 | section | 7 | 164 | 8.0 | 0 | 58.3 |
| skilled | 13 | section | 7 | 170 | 3.0 | 3 | 60.5 |
| skilled | 14 | section | 7 | 139 | 13.2 | 1 | 41.2 |
| skilled | 15 | section | 7 | 140 | 8.6 | 1 | 41.0 |
| skilled | 16 | section | 7 | 162 | 7.6 | 3 | 62.6 |
| skilled | 17 | section | 7 | 166 | 3.0 | 4 | 57.2 |
| skilled | 18 | section | 7 | 161 | 5.0 | 1 | 49.4 |
| skilled | 19 | section | 7 | 142 | 8.6 | 3 | 32.9 |
| skilled | 20 | section | 7 | 167 | 3.0 | 6 | 55.9 |
| noDash | 1 | dead | 6 | 126 | 26.0 | 0 | — |
| noDash | 2 | dead | 6 | 126 | 23.0 | 0 | — |
| noDash | 3 | dead | 6 | 142 | 32.4 | 0 | — |
| noDash | 4 | dead | 6 | 118 | 29.6 | 0 | — |
| noDash | 5 | dead | 6 | 151 | 35.0 | 0 | — |
| noDash | 6 | dead | 6 | 124 | 31.2 | 0 | — |
| noDash | 7 | dead | 6 | 146 | 28.6 | 0 | — |
| noDash | 8 | dead | 6 | 136 | 26.4 | 0 | — |
| noDash | 9 | dead | 6 | 129 | 32.2 | 0 | — |
| noDash | 10 | dead | 6 | 120 | 21.8 | 0 | — |
| noDash | 11 | section | 7 | 168 | 35.6 | 0 | 61.0 |
| noDash | 12 | dead | 6 | 119 | 29.2 | 0 | — |
| noDash | 13 | section | 7 | 150 | 23.2 | 0 | 34.4 |
| noDash | 14 | dead | 6 | 94 | 16.2 | 0 | — |
| noDash | 15 | dead | 6 | 130 | 32.6 | 0 | — |
| noDash | 16 | section | 7 | 158 | 37.8 | 0 | 50.4 |
| noDash | 17 | section | 7 | 144 | 18.0 | 0 | 42.4 |
| noDash | 18 | dead | 6 | 112 | 34.6 | 0 | — |
| noDash | 19 | dead | 6 | 120 | 31.0 | 0 | — |
| noDash | 20 | dead | 6 | 122 | 25.8 | 0 | — |
| masher | 1 | dead | 3 | 57 | 36.7 | 0 | — |
| masher | 2 | dead | 4 | 69 | 26.8 | 0 | — |
| masher | 3 | dead | 4 | 67 | 33.3 | 0 | — |
| masher | 4 | dead | 4 | 83 | 33.5 | 1 | — |
| masher | 5 | dead | 6 | 96 | 28.8 | 0 | — |
| masher | 6 | dead | 4 | 77 | 33.5 | 1 | — |
| masher | 7 | dead | 4 | 75 | 28.3 | 0 | — |
| masher | 8 | dead | 4 | 70 | 27.0 | 1 | — |
| masher | 9 | dead | 6 | 94 | 34.6 | 0 | — |
| masher | 10 | dead | 4 | 76 | 25.3 | 0 | — |
| masher | 11 | dead | 3 | 56 | 34.7 | 0 | — |
| masher | 12 | dead | 3 | 52 | 38.0 | 0 | — |
| masher | 13 | dead | 3 | 56 | 35.7 | 0 | — |
| masher | 14 | dead | 3 | 55 | 37.0 | 0 | — |
| masher | 15 | dead | 4 | 71 | 29.0 | 0 | — |
| masher | 16 | dead | 4 | 68 | 26.5 | 0 | — |
| masher | 17 | dead | 3 | 52 | 34.0 | 0 | — |
| masher | 18 | dead | 4 | 72 | 26.8 | 0 | — |
| masher | 19 | dead | 4 | 77 | 26.5 | 0 | — |
| masher | 20 | dead | 4 | 81 | 28.5 | 1 | — |

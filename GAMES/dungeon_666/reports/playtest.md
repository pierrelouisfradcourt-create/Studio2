# Playtest automatique — Dungeon 666

Généré par `node tools/playtest.mjs` le 2026-10-01T08:54:51.264Z. Graines 1 à 20, objectif : étage 7 (section 1 battue, boss au 6e), limite 12 min de temps simulé par run, arrêt à la première mort. Durée d'exécution : 10.8 s.

Politiques : **skilled** (lit les télégraphes, dashe au dernier moment), **noDash** (même jeu sans dash ni gadget), **masher** (fonce et tape, dash aléatoire, ne lit rien).

## Synthèse

| Politique | Section battue | Section (hors blocages) | Morts | Blocages | Étage moyen | Dégâts / salle | Dégâts / min de combat | Coups reçus / min de combat | Esquives / min | Dash / min | Actions / min |
|---|---|---|---|---|---|---|---|---|---|---|---|
| skilled | 100 % | 100 % | 0 % | 0 | 7.00 | 12.3 | 30.2 | 2.01 | 1.04 | 33.3 | 114.6 |
| noDash | 30 % | 30 % | 70 % | 0 | 6.30 | 29.2 | 92.0 | 5.42 | 0.00 | 0.0 | 93.9 |
| masher | 0 % | 0 % | 100 % | 0 | 3.85 | 30.9 | 161.6 | 9.70 | 0.16 | 9.4 | 160.3 |

Valeurs agrégées sur toutes les salles de combat jouées (étage <= 6) : total des dégâts / nombre de salles, et / minutes de combat (de l'entrée au nettoyage, ou à la mort ; gel d'impact exclu). « Esquives » = coups absorbés par les i-frames d'un dash (télémétrie de la sim).

**Valeur du dash** = dégâts subis par salle (noDash) / (skilled) = **2.36** ; par minute de combat = **3.05**. noDash n'a ni dash ni gadget : le ratio mesure le couple dash + gadget, pas le dash seul. Par salle, les morts de noDash plafonnent ses dégâts (PV max) : le ratio par minute est le plus robuste.

## Audit des dash (contrefactuel)

Chaque dash du bot skilled est rejoué 1 s depuis un clone de la partie : avec le dash, puis sans lui (meilleure esquive à pied, bot noDash).

| Dash audités | Décisifs (seul le futur sans dash est touché) | Nuisibles (le dash fait prendre un coup) | Coup inévitable (touché dans les deux cas) | Sans effet (aucun coup dans les deux cas) | Décisifs / min de combat |
|---|---|---|---|---|---|
| 1781 | 420 (24 %) | 17 | 18 | 1326 | 10.28 |

Lecture : « Dash / min » compte aussi les dash de confort ; seuls les dash décisifs prouvent que le dash sauve des coups.

## Causes de mort

| Politique | Causes de mort |
|---|---|
| skilled | aucune |
| noDash | bossOrb ×8, bossSlam ×4, bossCharge ×2 |
| masher | brute ×13, charger ×4, bossSlam ×2, arrow ×1 |

## Blocages (salle nettoyée, aucune sortie possible pendant 30 s)

Aucun blocage.

## Temps pour tuer par type d'ennemi (s, de l'apparition à la mort)

| Ennemi | skilled (moy / méd / p90, n) | noDash (moy / méd / p90, n) | masher (moy / méd / p90, n) |
|---|---|---|---|
| archer | 4.77 / 4.59 / 8.85 (368) | 4.17 / 4.12 / 7.47 (328) | 2.95 / 2.93 / 4.82 (241) |
| brute | 8.65 / 8.42 / 13.40 (84) | 7.17 / 6.95 / 11.47 (91) | 3.87 / 3.95 / 5.67 (43) |
| charger | 5.32 / 4.72 / 9.14 (176) | 4.80 / 4.50 / 7.83 (191) | 3.02 / 2.92 / 4.94 (132) |
| exploder | 2.06 / 1.80 / 3.84 (230) | 1.98 / 1.95 / 3.58 (183) | 1.77 / 1.82 / 3.16 (199) |
| gardien | 47.42 / 44.58 / 64.76 (20) | 34.13 / 32.40 / 43.48 (6) | — |
| imp | 2.90 / 2.72 / 5.36 (785) | 2.83 / 2.72 / 4.92 (704) | 2.23 / 2.05 / 3.85 (491) |

## Distribution — skilled

| Mesure | Moyenne | Médiane | p10 | p90 |
|---|---|---|---|---|
| Étage atteint | 7.00 | 7.00 | 7.00 | 7.00 |
| Dégâts subis / salle de combat (par run) | 12.34 | 12.80 | 4.44 | 18.42 |
| Coups reçus / min | 1.54 | 1.56 | 0.70 | 2.29 |
| Esquives (dash) / min | 1.04 | 1.08 | 0.41 | 1.64 |
| Dash / min | 33.32 | 33.64 | 29.56 | 36.44 |
| Actions / min | 114.61 | 115.14 | 110.18 | 120.38 |
| Coups pour tuer (mêlée / kills) | 2.26 | 2.25 | 1.93 | 2.65 |
| Durée du boss (s) | 47.42 | 44.58 | 36.12 | 64.76 |
| Durée du run (s) | 159.37 | 159.82 | 142.00 | 185.95 |
| Compétences (Lance) | 31.35 | 31.00 | 26.90 | 36.10 |
| Gadgets | 3.65 | 3.00 | 3.00 | 5.00 |
| Supers | 4.60 | 5.00 | 4.00 | 5.10 |
| Wall slams | 7.25 | 7.00 | 4.00 | 10.10 |
| Déviations | 65.30 | 62.00 | 34.60 | 100.60 |
| Événements de sim / min | 768.11 | 747.62 | 691.81 | 844.48 |
| Durée d'une salle de combat (s, toutes salles) | 18.77 | 18.57 | 10.59 | 27.29 |

## Distribution — noDash

| Mesure | Moyenne | Médiane | p10 | p90 |
|---|---|---|---|---|
| Étage atteint | 6.30 | 6.00 | 6.00 | 7.00 |
| Dégâts subis / salle de combat (par run) | 29.18 | 29.80 | 19.34 | 37.82 |
| Coups reçus / min | 3.93 | 3.65 | 3.10 | 5.07 |
| Esquives (dash) / min | 0.00 | 0.00 | 0.00 | 0.00 |
| Dash / min | 0.00 | 0.00 | 0.00 | 0.00 |
| Actions / min | 93.91 | 95.64 | 84.80 | 102.77 |
| Coups pour tuer (mêlée / kills) | 2.58 | 2.68 | 2.17 | 2.94 |
| Durée du boss (s) | 34.13 | 32.40 | 26.52 | 43.48 |
| Durée du run (s) | 131.30 | 132.68 | 116.20 | 146.86 |
| Compétences (Lance) | 24.25 | 24.00 | 20.00 | 27.30 |
| Gadgets | 0.00 | 0.00 | 0.00 | 0.00 |
| Supers | 3.75 | 4.00 | 3.00 | 5.00 |
| Wall slams | 5.45 | 5.50 | 3.00 | 8.00 |
| Déviations | 62.20 | 64.00 | 42.30 | 81.30 |
| Événements de sim / min | 667.91 | 667.71 | 596.63 | 737.25 |
| Durée d'une salle de combat (s, toutes salles) | 16.87 | 18.45 | 8.82 | 22.25 |

## Distribution — masher

| Mesure | Moyenne | Médiane | p10 | p90 |
|---|---|---|---|---|
| Étage atteint | 3.85 | 4.00 | 3.00 | 4.20 |
| Dégâts subis / salle de combat (par run) | 31.34 | 30.20 | 26.85 | 37.67 |
| Coups reçus / min | 6.36 | 5.98 | 4.97 | 8.03 |
| Esquives (dash) / min | 0.16 | 0.00 | 0.00 | 0.68 |
| Dash / min | 9.44 | 9.32 | 4.99 | 13.49 |
| Actions / min | 160.26 | 160.10 | 149.20 | 172.17 |
| Coups pour tuer (mêlée / kills) | 2.28 | 2.30 | 1.98 | 2.59 |
| Durée du boss (s) | — | — | — | — |
| Durée du run (s) | 67.22 | 67.14 | 52.67 | 80.73 |
| Compétences (Lance) | 0.00 | 0.00 | 0.00 | 0.00 |
| Gadgets | 0.00 | 0.00 | 0.00 | 0.00 |
| Supers | 0.00 | 0.00 | 0.00 | 0.00 |
| Wall slams | 1.20 | 1.00 | 0.00 | 3.00 |
| Déviations | 6.85 | 6.00 | 1.00 | 15.10 |
| Événements de sim / min | 737.37 | 732.99 | 684.32 | 797.21 |
| Durée d'une salle de combat (s, toutes salles) | 11.73 | 12.75 | 7.34 | 15.73 |

## Détail des runs

| Politique | Graine | Issue | Étage | Durée (s) | Dégâts / salle | Esquives | Boss (s) |
|---|---|---|---|---|---|---|---|
| skilled | 1 | section | 7 | 165 | 11.2 | 3 | 44.4 |
| skilled | 2 | section | 7 | 149 | 15.0 | 4 | 46.0 |
| skilled | 3 | section | 7 | 191 | 12.0 | 7 | 78.5 |
| skilled | 4 | section | 7 | 145 | 14.0 | 1 | 36.6 |
| skilled | 5 | section | 7 | 157 | 3.0 | 4 | 46.4 |
| skilled | 6 | section | 7 | 137 | 15.0 | 2 | 31.3 |
| skilled | 7 | section | 7 | 160 | 22.2 | 2 | 44.2 |
| skilled | 8 | section | 7 | 160 | 13.6 | 3 | 44.3 |
| skilled | 9 | section | 7 | 126 | 6.0 | 0 | 22.3 |
| skilled | 10 | section | 7 | 162 | 8.0 | 3 | 54.1 |
| skilled | 11 | section | 7 | 160 | 18.0 | 5 | 43.5 |
| skilled | 12 | section | 7 | 167 | 16.0 | 2 | 54.3 |
| skilled | 13 | section | 7 | 164 | 9.0 | 4 | 44.8 |
| skilled | 14 | section | 7 | 147 | 9.0 | 2 | 48.6 |
| skilled | 15 | section | 7 | 164 | 3.0 | 1 | 39.1 |
| skilled | 16 | section | 7 | 143 | 15.0 | 1 | 41.9 |
| skilled | 17 | section | 7 | 188 | 16.2 | 4 | 64.7 |
| skilled | 18 | section | 7 | 186 | 24.0 | 3 | 65.3 |
| skilled | 19 | section | 7 | 167 | 12.0 | 3 | 59.7 |
| skilled | 20 | section | 7 | 153 | 4.6 | 3 | 38.5 |
| noDash | 1 | dead | 6 | 132 | 34.4 | 0 | — |
| noDash | 2 | dead | 6 | 124 | 23.0 | 0 | — |
| noDash | 3 | section | 7 | 134 | 19.6 | 0 | 26.3 |
| noDash | 4 | dead | 6 | 125 | 37.8 | 0 | — |
| noDash | 5 | dead | 6 | 138 | 36.6 | 0 | — |
| noDash | 6 | dead | 6 | 115 | 21.8 | 0 | — |
| noDash | 7 | section | 7 | 146 | 34.8 | 0 | 37.8 |
| noDash | 8 | section | 7 | 139 | 28.8 | 0 | 35.4 |
| noDash | 9 | section | 7 | 135 | 26.0 | 0 | 29.4 |
| noDash | 10 | dead | 6 | 116 | 23.6 | 0 | — |
| noDash | 11 | dead | 6 | 152 | 37.2 | 0 | — |
| noDash | 12 | dead | 6 | 132 | 38.0 | 0 | — |
| noDash | 13 | dead | 6 | 133 | 25.0 | 0 | — |
| noDash | 14 | dead | 6 | 122 | 30.8 | 0 | — |
| noDash | 15 | dead | 6 | 127 | 32.8 | 0 | — |
| noDash | 16 | dead | 6 | 109 | 17.0 | 0 | — |
| noDash | 17 | dead | 6 | 121 | 35.8 | 0 | — |
| noDash | 18 | dead | 6 | 143 | 42.2 | 0 | — |
| noDash | 19 | section | 7 | 133 | 24.4 | 0 | 26.7 |
| noDash | 20 | section | 7 | 151 | 14.0 | 0 | 49.2 |
| masher | 1 | dead | 3 | 59 | 34.0 | 0 | — |
| masher | 2 | dead | 4 | 63 | 25.0 | 0 | — |
| masher | 3 | dead | 3 | 53 | 37.7 | 0 | — |
| masher | 4 | dead | 3 | 53 | 37.7 | 0 | — |
| masher | 5 | dead | 4 | 71 | 29.8 | 1 | — |
| masher | 6 | dead | 4 | 75 | 29.0 | 0 | — |
| masher | 7 | dead | 4 | 71 | 30.0 | 0 | — |
| masher | 8 | dead | 4 | 74 | 27.0 | 2 | — |
| masher | 9 | dead | 4 | 62 | 27.8 | 0 | — |
| masher | 10 | dead | 4 | 70 | 28.3 | 0 | — |
| masher | 11 | dead | 3 | 53 | 34.7 | 0 | — |
| masher | 12 | dead | 3 | 58 | 39.7 | 0 | — |
| masher | 13 | dead | 4 | 80 | 28.0 | 0 | — |
| masher | 14 | dead | 3 | 50 | 37.0 | 0 | — |
| masher | 15 | dead | 4 | 72 | 30.5 | 0 | — |
| masher | 16 | dead | 4 | 64 | 28.0 | 0 | — |
| masher | 17 | dead | 6 | 91 | 33.4 | 1 | — |
| masher | 18 | dead | 3 | 54 | 33.7 | 0 | — |
| masher | 19 | dead | 4 | 77 | 25.5 | 0 | — |
| masher | 20 | dead | 6 | 96 | 30.4 | 0 | — |

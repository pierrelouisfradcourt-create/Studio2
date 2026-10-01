# Dungeon 666 — mesure des classes (bots)

Généré par `node tools/classes.mjs 20` : 20 graines par kit et par bot, section 1 (18 étages).
Les bots mesurent des conséquences (dégâts reçus, survie). Ils ne mesurent ni le plaisir ni
l'équilibrage ressenti : **D11 se juge en main**.

## Section 1 jouée par les bots

| Kit | Habile : section battue | Habile : dégâts/salle | Sans dash : dégâts/salle | Valeur du dash | Sans dash vs étalon | Sans dash : section battue | Martèle : meurt | Martèle : étage atteint | Durée (habile) |
|---|---|---|---|---|---|---|---|---|---|
| Revenant · Lame du Revenant | 100 % | 2.3 | 17.5 | ×7.5 | 100 % | 15 % | 100 % | 10.1 | 6.2 min |
| Revenant · Dagues jumelles | 100 % | 2.7 | 19.1 | ×7.0 | 109 % | 25 % | 100 % | 8.8 | 6.4 min |
| Bourreau · Hache du bourreau | 100 % | 3.9 | 25.8 | ×6.7 | 147 % | 25 % | 100 % | 15.6 | 5.8 min |
| Bourreau · Maillet des damnés | 100 % | 2.0 | 25.9 | ×13.2 | 148 % | 30 % | 100 % | 15.6 | 5.7 min |
| Chasseresse · Arc d'os | 100 % | 0.6 | 20.5 | ×31.7 | 117 % | 15 % | 100 % | 5.8 | 5.7 min |
| Chasseresse · Arbalète des limbes | 100 % | 0.7 | 21.2 | ×28.8 | 121 % | 30 % | 95 % | 9.2 | 5.3 min |

Seuils bloquants : section battue ≥ 90 % ; valeur du dash ≥ ×2 ; sans dash, au moins 70 % des dégâts/salle de l'étalon (revenant/lame).

## Attaque maintenue sur place (ennemis increvables)

Le héros ne bouge pas et maintient l'attaque 30 s. Coups reçus, moyenne de 10 graines.

| Kit | brutes (2) | diablotins (3) | mêlée (5) |
|---|---|---|---|
| Revenant · Lame du Revenant | 15.0 | 10.5 | 11.4 |
| Revenant · Dagues jumelles | 14.5 | 13.5 | 14.9 |
| Bourreau · Hache du bourreau | 13.9 | 8.9 | 15.1 |
| Bourreau · Maillet des damnés | 8.0 | 2.1 | 9.0 |
| Chasseresse · Arc d'os (à distance) | 10.4 | 12.9 | 20.5 |
| Chasseresse · Arbalète des limbes (à distance) | 5.4 | 1.3 | 9.3 |

Seuil bloquant (armes de mêlée) : au moins 3 coups de brutes en 30 s. Les diablotins restent une mesure :
une arme lourde les tient à distance par son recul, pas par l'étourdissement.

## Verdict : VERT

Tous les seuils bloquants passent.

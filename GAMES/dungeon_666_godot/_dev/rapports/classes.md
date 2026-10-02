# Dungeon 666 — mesure des classes (bots)

Généré par `outils/classes.gd 20` (version Godot) : 20 graines par kit et par bot, section 1 (18 étages).
Les bots mesurent des conséquences (dégâts reçus, survie). Ils ne mesurent ni le plaisir ni
l'équilibrage ressenti : **D11 se juge en main**.

## Section 1 jouée par les bots

| Kit | Habile : section battue | Habile : dégâts/salle | Sans dash : dégâts/salle | Valeur du dash | Sans dash vs étalon | Sans dash : section battue | Martèle : meurt | Martèle : étage atteint | Durée (habile) |
|---|---|---|---|---|---|---|---|---|---|
| Revenant · Lame du Revenant | 100 % | 2.8 | 20.8 | ×7.5 | 100 % | 30 % | 100 % | 7.7 | 6.4 min |
| Revenant · Dagues jumelles | 100 % | 4.8 | 21.0 | ×4.4 | 101 % | 25 % | 100 % | 7.7 | 6.7 min |
| Bourreau · Hache du bourreau | 100 % | 2.0 | 26.8 | ×13.2 | 129 % | 10 % | 100 % | 14.6 | 5.6 min |
| Bourreau · Maillet des damnés | 100 % | 3.3 | 23.2 | ×7.0 | 111 % | 0 % | 100 % | 14.3 | 5.6 min |
| Chasseresse · Arc d'os | 95 % | 0.5 | 21.0 | ×42.7 | 101 % | 20 % | 100 % | 5.8 | 6.6 min |
| Chasseresse · Arbalète des limbes | 100 % | 1.0 | 18.9 | ×19.6 | 91 % | 10 % | 100 % | 8.7 | 5.2 min |

Seuils bloquants : section battue ≥ 90 % ; valeur du dash ≥ ×2 ; sans dash, au moins 70 % des dégâts/salle de l'étalon (revenant/lame).

## Attaque maintenue sur place (ennemis increvables)

Le héros ne bouge pas et maintient l'attaque 30 s. Coups reçus, moyenne de 10 graines.

| Kit | brutes (2) | diablotins (3) | mêlée (5) |
|---|---|---|---|
| Revenant · Lame du Revenant | 15.0 | 10.0 | 11.3 |
| Revenant · Dagues jumelles | 14.5 | 13.3 | 14.9 |
| Bourreau · Hache du bourreau | 12.1 | 9.3 | 11.1 |
| Bourreau · Maillet des damnés | 8.0 | 1.9 | 9.6 |
| Chasseresse · Arc d'os (à distance) | 10.4 | 12.8 | 20.5 |
| Chasseresse · Arbalète des limbes (à distance) | 5.4 | 1.3 | 9.1 |

Seuil bloquant (armes de mêlée) : au moins 3 coups de brutes en 30 s. Les diablotins restent une mesure :
une arme lourde les tient à distance par son recul, pas par l'étourdissement.

## Verdict : VERT

Tous les seuils bloquants passent.

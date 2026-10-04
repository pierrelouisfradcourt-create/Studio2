# Dungeon 666 — mesure des classes (bots)

Généré par `outils/classes.gd 20` (version Godot) : 20 graines par kit et par bot, section 1 (18 étages).
Les bots mesurent des conséquences (dégâts reçus, survie). Ils ne mesurent ni le plaisir ni
l'équilibrage ressenti : **D11 se juge en main**.

## Section 1 jouée par les bots

| Kit | Habile : section battue | Habile : dégâts/salle | Sans dash : dégâts/salle | Valeur du dash | Sans dash vs étalon | Sans dash : section battue | Martèle : meurt | Martèle : étage atteint | Durée (habile) |
|---|---|---|---|---|---|---|---|---|---|
| Revenant · Lame du Revenant | 100 % | 4.6 | 19.5 | ×4.2 | 100 % | 15 % | 100 % | 7.3 | 6.5 min |
| Revenant · Dagues jumelles | 100 % | 4.8 | 21.6 | ×4.5 | 111 % | 15 % | 100 % | 7.2 | 6.9 min |
| Bourreau · Hache du bourreau | 95 % | 11.4 | 24.1 | ×2.1 | 124 % | 10 % | 100 % | 13.2 | 5.7 min |
| Bourreau · Maillet des damnés | 90 % | 10.9 | 24.0 | ×2.2 | 124 % | 10 % | 95 % | 13.8 | 5.8 min |
| Chasseresse · Arc d'os | 100 % | 0.5 | 16.8 | ×33.0 | 86 % | 5 % | 100 % | 6.3 | 5.4 min |
| Chasseresse · Arbalète des limbes | 100 % | 0.6 | 23.1 | ×36.0 | 119 % | 30 % | 100 % | 8.4 | 5.3 min |

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

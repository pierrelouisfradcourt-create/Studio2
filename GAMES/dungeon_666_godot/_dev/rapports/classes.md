# Dungeon 666 — mesure des classes (bots)

Généré par `outils/classes.gd 20` (version Godot) : 20 graines par kit et par bot, section 1 (18 étages).
Les bots mesurent des conséquences (dégâts reçus, survie). Ils ne mesurent ni le plaisir ni
l'équilibrage ressenti : **D11 se juge en main**.

## Section 1 jouée par les bots

| Kit | Habile : section battue | Habile : dégâts/salle | Sans dash : dégâts/salle | Valeur du dash | Sans dash vs étalon | Sans dash : section battue | Martèle : meurt | Martèle : étage atteint | Durée (habile) |
|---|---|---|---|---|---|---|---|---|---|
| Revenant · Lame du Revenant | 100 % | 3.0 | 16.4 | ×5.4 | 100 % | 15 % | 100 % | 8.0 | 6.3 min |
| Revenant · Dagues jumelles | 100 % | 3.9 | 17.5 | ×4.5 | 106 % | 35 % | 100 % | 7.0 | 6.4 min |
| Bourreau · Hache du bourreau | 100 % | 2.9 | 25.9 | ×9.0 | 158 % | 20 % | 95 % | 13.7 | 5.6 min |
| Bourreau · Maillet des damnés | 100 % | 2.5 | 24.4 | ×9.9 | 148 % | 10 % | 95 % | 13.8 | 5.6 min |
| Chasseresse · Arc d'os | 100 % | 0.9 | 19.1 | ×22.1 | 116 % | 15 % | 100 % | 6.3 | 5.5 min |
| Chasseresse · Arbalète des limbes | 100 % | 1.3 | 18.0 | ×13.8 | 110 % | 15 % | 100 % | 7.8 | 5.3 min |

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

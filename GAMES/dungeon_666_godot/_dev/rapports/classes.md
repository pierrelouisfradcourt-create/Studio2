# Dungeon 666 — mesure des classes (bots)

Généré par `outils/classes.gd 20` (version Godot) : 20 graines par kit et par bot, section 1 (18 étages).
Les bots mesurent des conséquences (dégâts reçus, survie). Ils ne mesurent ni le plaisir ni
l'équilibrage ressenti : **D11 se juge en main**.

## Section 1 jouée par les bots

| Kit | Habile : section battue | Habile : dégâts/salle | Sans dash : dégâts/salle | Valeur du dash | Sans dash vs étalon | Sans dash : section battue | Martèle : meurt | Martèle : étage atteint | Durée (habile) |
|---|---|---|---|---|---|---|---|---|---|
| Revenant · Lame du Revenant | 100 % | 2.6 | 20.3 | ×7.8 | 100 % | 25 % | 100 % | 7.8 | 6.1 min |
| Revenant · Dagues jumelles | 95 % | 4.8 | 22.1 | ×4.6 | 108 % | 30 % | 100 % | 7.0 | 6.6 min |
| Bourreau · Hache du bourreau | 100 % | 2.2 | 27.9 | ×12.6 | 137 % | 5 % | 90 % | 13.9 | 5.8 min |
| Bourreau · Maillet des damnés | 95 % | 2.9 | 24.4 | ×8.4 | 120 % | 20 % | 100 % | 13.5 | 5.6 min |
| Chasseresse · Arc d'os | 100 % | 0.4 | 19.7 | ×50.6 | 97 % | 20 % | 100 % | 5.8 | 5.4 min |
| Chasseresse · Arbalète des limbes | 100 % | 1.0 | 18.9 | ×19.0 | 93 % | 20 % | 100 % | 8.4 | 5.1 min |

Seuils bloquants : section battue ≥ 90 % ; valeur du dash ≥ ×2 ; sans dash, au moins 70 % des dégâts/salle de l'étalon (revenant/lame).

## Attaque maintenue sur place (ennemis increvables)

Le héros ne bouge pas et maintient l'attaque 30 s. Coups reçus, moyenne de 10 graines.

| Kit | brutes (2) | diablotins (3) | mêlée (5) |
|---|---|---|---|
| Revenant · Lame du Revenant | 15.0 | 10.5 | 11.4 |
| Revenant · Dagues jumelles | 14.5 | 13.7 | 15.1 |
| Bourreau · Hache du bourreau | 13.9 | 8.9 | 15.1 |
| Bourreau · Maillet des damnés | 8.0 | 2.1 | 9.0 |
| Chasseresse · Arc d'os (à distance) | 10.4 | 12.9 | 20.5 |
| Chasseresse · Arbalète des limbes (à distance) | 5.4 | 1.3 | 9.1 |

Seuil bloquant (armes de mêlée) : au moins 3 coups de brutes en 30 s. Les diablotins restent une mesure :
une arme lourde les tient à distance par son recul, pas par l'étourdissement.

## Verdict : VERT

Tous les seuils bloquants passent.

# Dungeon 666 — mesure des classes (bots)

Généré par `outils/classes.gd 20` (version Godot) : 20 graines par kit et par bot, section 1 (18 étages).
Les bots mesurent des conséquences (dégâts reçus, survie). Ils ne mesurent ni le plaisir ni
l'équilibrage ressenti : **D11 se juge en main**.

## Section 1 jouée par les bots

| Kit | Habile : section battue | Habile : dégâts/salle | Sans dash : dégâts/salle | Valeur du dash | Sans dash vs étalon | Sans dash : section battue | Martèle : meurt | Martèle : étage atteint | Durée (habile) |
|---|---|---|---|---|---|---|---|---|---|
| Revenant · Lame du Revenant | 100 % | 4.0 | 22.5 | ×5.6 | 100 % | 20 % | 100 % | 8.7 | 6.5 min |
| Revenant · Dagues jumelles | 100 % | 3.4 | 18.3 | ×5.4 | 81 % | 15 % | 100 % | 7.3 | 6.6 min |
| Bourreau · Hache du bourreau | 100 % | 2.6 | 26.3 | ×10.2 | 117 % | 10 % | 95 % | 15.2 | 5.7 min |
| Bourreau · Maillet des damnés | 100 % | 2.1 | 25.9 | ×12.1 | 115 % | 20 % | 95 % | 13.2 | 5.6 min |
| Chasseresse · Arc d'os | 100 % | 0.7 | 17.5 | ×26.5 | 77 % | 25 % | 100 % | 5.8 | 5.5 min |
| Chasseresse · Arbalète des limbes | 95 % | 1.2 | 18.3 | ×15.8 | 81 % | 15 % | 95 % | 9.7 | 5.3 min |

Seuils bloquants : section battue ≥ 90 % ; valeur du dash ≥ ×2 ; sans dash, au moins 70 % des dégâts/salle de l'étalon (revenant/lame).

## Attaque maintenue sur place (ennemis increvables)

Le héros ne bouge pas et maintient l'attaque 30 s. Coups reçus, moyenne de 10 graines.

| Kit | brutes (2) | diablotins (3) | mêlée (5) |
|---|---|---|---|
| Revenant · Lame du Revenant | 14.4 | 8.5 | 11.0 |
| Revenant · Dagues jumelles | 15.0 | 13.0 | 13.8 |
| Bourreau · Hache du bourreau | 10.2 | 5.2 | 7.0 |
| Bourreau · Maillet des damnés | 7.0 | 1.1 | 5.3 |
| Chasseresse · Arc d'os (à distance) | 9.3 | 13.7 | 20.3 |
| Chasseresse · Arbalète des limbes (à distance) | 5.1 | 2.7 | 11.1 |

Seuil bloquant (armes de mêlée) : au moins 3 coups de brutes en 30 s. Les diablotins restent une mesure :
une arme lourde les tient à distance par son recul, pas par l'étourdissement.

## Verdict : VERT

Tous les seuils bloquants passent.

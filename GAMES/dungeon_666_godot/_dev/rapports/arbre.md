# Dungeon 666 — puissance de l'arbre de compétences (bots)

Généré par `outils/arbre.gd 10` : 10 graines par classe, bot habile, section 1 (18 étages), arme de départ,
trois emplacements (compétence de départ, compétence à charges de départ, seconde compétence).
**Arbre vide** : tout au rang 1, aucun passif. **Arbre plein** : tous les points d'un héros au niveau
maximum qui a vaincu tous les Gardiens, première amélioration exclusive de chaque compétence.
Ce sont des conséquences mesurées par un bot, pas un jugement d'équilibrage : **cela se juge en main**.

| Classe | Arbre | Points dépensés | Section battue | Dégâts reçus / salle | Temps par salle | Combat du Gardien | Durée |
|---|---|---|---|---|---|---|---|
| Revenant | vide | 0 | 100 % | 4.5 | 14.1 s | 45.5 s | 6.1 min |
| Revenant | plein | 33 | 100 % | 1.9 | 11.5 s | 33.2 s | 5.3 min |
| Bourreau | vide | 0 | 100 % | 8.7 | 11.9 s | 46.5 s | 5.6 min |
| Bourreau | plein | 33 | 100 % | 3.9 | 10.6 s | 31.6 s | 5.0 min |
| Chasseresse | vide | 0 | 100 % | 0.8 | 10.8 s | 27.2 s | 5.2 min |
| Chasseresse | plein | 33 | 100 % | 0.1 | 9.4 s | 15.8 s | 4.6 min |

## Arbre plein rapporté à l'arbre vide

| Classe | Dégâts reçus / salle | Temps par salle | Combat du Gardien |
|---|---|---|---|
| Revenant | ×0.42 | ×0.81 | ×0.73 |
| Bourreau | ×0.45 | ×0.89 | ×0.68 |
| Chasseresse | ×0.10 | ×0.86 | ×0.58 |

Lecture : ×0,50 en temps par salle = les salles tombent deux fois plus vite avec l'arbre plein.

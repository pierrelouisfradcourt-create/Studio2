# Dungeon 666 — puissance de l'arbre de compétences (bots)

Généré par `outils/arbre.gd 10` : 10 graines par mesure, bot habile, section 1 (18 étages), arme de départ.
Ce sont des conséquences mesurées par un bot, pas un jugement d'équilibrage : **cela se juge en main**.

## 1. Arbre vide contre arbre plein

Trois emplacements (compétence de départ, compétence à charges de départ, seconde compétence).
**Arbre vide** : tout au rang 1, aucun passif. **Arbre plein** : tous les points d'un héros au niveau
maximum qui a vaincu tous les Gardiens, première amélioration exclusive de chaque compétence.

| Classe | Arbre | Points dépensés | Section battue | Dégâts reçus / salle | Temps par salle | Combat du Gardien | Durée |
|---|---|---|---|---|---|---|---|
| Revenant | vide | 0 | 100 % | 4.5 | 14.1 s | 45.5 s | 6.1 min |
| Revenant | plein | 33 | 100 % | 1.9 | 12.0 s | 37.8 s | 5.5 min |
| Bourreau | vide | 0 | 100 % | 8.7 | 11.9 s | 46.5 s | 5.6 min |
| Bourreau | plein | 33 | 100 % | 4.1 | 10.3 s | 29.4 s | 5.0 min |
| Chasseresse | vide | 0 | 100 % | 0.8 | 10.8 s | 27.2 s | 5.2 min |
| Chasseresse | plein | 33 | 100 % | 0.3 | 9.4 s | 16.9 s | 4.6 min |

Arbre plein rapporté à l'arbre vide :

| Classe | Dégâts reçus / salle | Temps par salle | Combat du Gardien |
|---|---|---|---|
| Revenant | ×0.43 | ×0.85 | ×0.83 |
| Bourreau | ×0.47 | ×0.86 | ×0.63 |
| Chasseresse | ×0.33 | ×0.86 | ×0.62 |

Lecture : ×0,50 en temps par salle = les salles tombent deux fois plus vite avec l'arbre plein.

## 2. Valeur de chaque compétence neuve

Kit de départ (deux emplacements, le troisième vide) contre le même kit avec la compétence neuve dans le
troisième emplacement, au rang 1 puis au rang 5, sans amélioration ni autre point. « Lancers » : compétences
lancées et charges dépensées par section, tous emplacements confondus (le kit de départ sert de repère).
Entre parenthèses : rapporté au kit de départ (×1,00 = ne change rien ; ×0,50 = moitié moins).

| Classe | Compétence | Rang | Section battue | Dégâts reçus / salle | Temps par salle | Combat du Gardien | Lancers |
|---|---|---|---|---|---|---|---|
| Revenant | (kit de départ) | — | 100 % | 4.2 | 15.6 s | 49.0 s | 110 |
| Revenant | Sillage de braise | 1 | 100 % | 3.3 (×0.78) | 14.7 s (×0.94) | 46.3 s (×0.95) | 120 |
| Revenant | Sillage de braise | 5 | 100 % | 4.0 (×0.96) | 13.8 s (×0.88) | 55.2 s (×1.13) | 120 |
| Revenant | Stigmate | 1 | 100 % | 3.7 (×0.88) | 14.9 s (×0.96) | 44.6 s (×0.91) | 133 |
| Revenant | Stigmate | 5 | 100 % | 4.8 (×1.15) | 13.6 s (×0.87) | 44.9 s (×0.92) | 136 |
| Revenant | Contre-taille | 1 | 100 % | 4.1 (×0.97) | 14.8 s (×0.95) | 46.7 s (×0.95) | 130 |
| Revenant | Contre-taille | 5 | 100 % | 4.5 (×1.08) | 14.3 s (×0.91) | 52.3 s (×1.07) | 142 |
| Bourreau | (kit de départ) | — | 100 % | 9.6 | 13.0 s | 42.0 s | 57 |
| Bourreau | Faille | 1 | 100 % | 9.7 (×1.00) | 12.0 s (×0.92) | 39.1 s (×0.93) | 89 |
| Bourreau | Faille | 5 | 90 % | 12.7 (×1.32) | 11.6 s (×0.90) | 37.8 s (×0.90) | 91 |
| Bourreau | Hache du supplice | 1 | 90 % | 9.8 (×1.02) | 11.7 s (×0.90) | 33.9 s (×0.81) | 93 |
| Bourreau | Hache du supplice | 5 | 100 % | 6.3 (×0.66) | 11.2 s (×0.86) | 33.0 s (×0.79) | 100 |
| Bourreau | Garde de fer | 1 | 100 % | 6.4 (×0.66) | 12.7 s (×0.98) | 40.8 s (×0.97) | 65 |
| Bourreau | Garde de fer | 5 | 80 % | 9.3 (×0.97) | 12.7 s (×0.98) | 34.2 s (×0.82) | 67 |
| Chasseresse | (kit de départ) | — | 100 % | 0.6 | 12.2 s | 30.0 s | 76 |
| Chasseresse | Marque de la proie | 1 | 100 % | 0.4 (×0.71) | 11.7 s (×0.96) | 28.3 s (×0.94) | 99 |
| Chasseresse | Marque de la proie | 5 | 100 % | 0.9 (×1.61) | 11.8 s (×0.97) | 23.0 s (×0.77) | 102 |
| Chasseresse | Leurre d'os | 1 | 100 % | 0.3 (×0.51) | 12.0 s (×0.98) | 27.5 s (×0.92) | 79 |
| Chasseresse | Leurre d'os | 5 | 100 % | 0.7 (×1.30) | 12.9 s (×1.06) | 38.0 s (×1.27) | 90 |
| Chasseresse | Trait de Nemrod | 1 | 100 % | 0.8 (×1.51) | 12.2 s (×1.00) | 27.9 s (×0.93) | 109 |
| Chasseresse | Trait de Nemrod | 5 | 100 % | 1.0 (×1.82) | 12.2 s (×1.00) | 28.2 s (×0.94) | 115 |

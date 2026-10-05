# Dungeon 666 — puissance de l'arbre de compétences (bots)

Généré par `outils/arbre.gd 6` : 6 graines par mesure, bot habile, section 1 (18 étages), arme de départ.
Ce sont des conséquences mesurées par un bot, pas un jugement d'équilibrage : **cela se juge en main**.

## 1. Arbre vide contre arbre plein

Trois emplacements (compétence de départ, compétence à charges de départ, seconde compétence).
**Arbre vide** : tout au rang 1, aucun passif. **Arbre plein** : tous les points d'un héros au niveau
maximum qui a vaincu tous les Gardiens, première amélioration exclusive de chaque compétence.

| Classe | Arbre | Points dépensés | Section battue | Dégâts reçus / salle | Temps par salle | Combat du Gardien | Durée |
|---|---|---|---|---|---|---|---|
| Revenant | vide | 0 | 100 % | 2.8 | 14.0 s | 44.2 s | 6.0 min |
| Revenant | plein | 33 | 100 % | 1.8 | 11.8 s | 35.0 s | 5.5 min |
| Bourreau | vide | 0 | 100 % | 8.6 | 12.3 s | 53.3 s | 5.8 min |
| Bourreau | plein | 33 | 100 % | 3.3 | 9.9 s | 27.7 s | 4.9 min |
| Chasseresse | vide | 0 | 100 % | 0.9 | 11.0 s | 29.8 s | 5.4 min |
| Chasseresse | plein | 33 | 100 % | 0.4 | 9.2 s | 15.9 s | 4.6 min |

Arbre plein rapporté à l'arbre vide :

| Classe | Dégâts reçus / salle | Temps par salle | Combat du Gardien |
|---|---|---|---|
| Revenant | ×0.65 | ×0.84 | ×0.79 |
| Bourreau | ×0.38 | ×0.81 | ×0.52 |
| Chasseresse | ×0.48 | ×0.83 | ×0.53 |

Lecture : ×0,50 en temps par salle = les salles tombent deux fois plus vite avec l'arbre plein.

## 2. Valeur de chaque compétence neuve

Kit de départ (deux emplacements, le troisième vide) contre le même kit avec la compétence neuve dans le
troisième emplacement, au rang 1 puis au rang 5, sans amélioration ni autre point. « Lancers » : compétences
lancées et charges dépensées par section, tous emplacements confondus (le kit de départ sert de repère).
Entre parenthèses : rapporté au kit de départ (×1,00 = ne change rien ; ×0,50 = moitié moins).

| Classe | Compétence | Rang | Section battue | Dégâts reçus / salle | Temps par salle | Combat du Gardien | Lancers |
|---|---|---|---|---|---|---|---|
| Revenant | (kit de départ) | — | 100 % | 4.4 | 14.8 s | 50.7 s | 106 |
| Revenant | Sillage de braise | 1 | 100 % | 3.7 (×0.83) | 14.7 s (×0.99) | 44.4 s (×0.87) | 122 |
| Revenant | Sillage de braise | 5 | 100 % | 3.9 (×0.88) | 13.5 s (×0.91) | 59.3 s (×1.17) | 116 |
| Revenant | Stigmate | 1 | 100 % | 4.9 (×1.11) | 15.0 s (×1.01) | 45.3 s (×0.89) | 132 |
| Revenant | Stigmate | 5 | 100 % | 4.2 (×0.95) | 13.0 s (×0.88) | 45.9 s (×0.90) | 130 |
| Revenant | Contre-taille | 1 | 100 % | 4.3 (×0.97) | 15.4 s (×1.04) | 51.0 s (×1.01) | 135 |
| Revenant | Contre-taille | 5 | 100 % | 4.6 (×1.04) | 14.7 s (×0.99) | 58.3 s (×1.15) | 145 |
| Bourreau | (kit de départ) | — | 100 % | 7.3 | 12.9 s | 40.6 s | 55 |
| Bourreau | Faille | 1 | 100 % | 9.8 (×1.35) | 12.3 s (×0.95) | 37.9 s (×0.93) | 87 |
| Bourreau | Faille | 5 | 100 % | 13.1 (×1.81) | 11.8 s (×0.91) | 40.3 s (×0.99) | 91 |
| Bourreau | Hache du supplice | 1 | 100 % | 8.5 (×1.17) | 11.6 s (×0.90) | 32.1 s (×0.79) | 89 |
| Bourreau | Hache du supplice | 5 | 100 % | 6.5 (×0.89) | 11.0 s (×0.85) | 30.2 s (×0.74) | 97 |
| Bourreau | Garde de fer | 1 | 100 % | 10.3 (×1.42) | 12.6 s (×0.98) | 48.4 s (×1.19) | 64 |
| Bourreau | Garde de fer | 5 | 100 % | 11.9 (×1.64) | 12.6 s (×0.98) | 40.0 s (×0.99) | 65 |
| Chasseresse | (kit de départ) | — | 100 % | 0.6 | 12.2 s | 26.2 s | 77 |
| Chasseresse | Marque de la proie | 1 | 100 % | 0.5 (×0.77) | 11.7 s (×0.96) | 28.9 s (×1.10) | 97 |
| Chasseresse | Marque de la proie | 5 | 100 % | 1.0 (×1.67) | 12.0 s (×0.99) | 25.7 s (×0.98) | 105 |
| Chasseresse | Leurre d'os | 1 | 100 % | 0.2 (×0.36) | 12.5 s (×1.03) | 29.1 s (×1.11) | 80 |
| Chasseresse | Leurre d'os | 5 | 100 % | 0.5 (×0.90) | 13.2 s (×1.08) | 41.5 s (×1.59) | 90 |
| Chasseresse | Trait de Nemrod | 1 | 100 % | 0.6 (×1.04) | 12.9 s (×1.06) | 34.0 s (×1.30) | 113 |
| Chasseresse | Trait de Nemrod | 5 | 100 % | 1.4 (×2.38) | 12.0 s (×0.98) | 25.1 s (×0.96) | 110 |

# Dungeon 666 — mesure en profondeur du combat V3 (bots)

Généré par `outils/profondeur.gd 20` : 20 graines par case, bot habile, une section entière (18 étages, Gardien compris)
depuis son premier étage. Sections 1, 7, 19 : étages 1, 109, 325. Héros : voir l'en-tête de `outils/profondeur.gd`
(section 1 : héros neuf ; plus bas : Ville achetée, trois objets « rare » du niveau de l'étage précédent ; aucune bénédiction au départ).
Chaque nombre est une MOYENNE ± l'ÉCART-TYPE entre graines (le bruit d'une partie à l'autre) ; l'incertitude sur la
moyenne est cet écart divisé par √20 ≈ 4.5. Ce sont des conséquences mesurées par un bot : **l'équilibrage se juge en main**.

## 1. Arbre vide contre arbre plein, à trois profondeurs

« Dégâts reçus » : en % des PV max du héros, par salle de combat. « Étages faits » : sur 18. « Morts » : parties finies par la mort
du héros (une partie s'arrête à la première mort) ; « bloquées » : ni mort ni section battue (salle sans issue, temps écoulé).

| Classe | Départ | Arbre | Points | PV max | Section battue | Morts | Bloquées | Étages faits | Dégâts reçus / salle | Temps par salle | Combat du Gardien |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Revenant | étage 1 | vide | 0 | 100 | 100 % (20 / 20) | 0 | 0 | 18.0 ± 0.0 | 3.8 ± 3.0 % | 13.4 ± 1.3 s | 40.6 ± 14.1 s |
| Revenant | étage 1 | plein | 33 | 124 | 100 % (20 / 20) | 0 | 0 | 18.0 ± 0.0 | 1.5 ± 1.6 % | 11.2 ± 0.9 s | 31.7 ± 10.7 s |
| Revenant | étage 109 | vide | 0 | 533 | 100 % (20 / 20) | 0 | 0 | 18.0 ± 0.0 | 0.6 ± 0.8 % | 12.4 ± 1.0 s | 29.5 ± 7.4 s |
| Revenant | étage 109 | plein | 33 | 557 | 100 % (20 / 20) | 0 | 0 | 18.0 ± 0.0 | 0.4 ± 0.6 % | 10.3 ± 0.7 s | 20.5 ± 3.4 s |
| Revenant | étage 325 | vide | 0 | 1260 | 100 % (20 / 20) | 0 | 0 | 18.0 ± 0.0 | 1.5 ± 1.2 % | 14.6 ± 0.6 s | 30.5 ± 6.4 s |
| Revenant | étage 325 | plein | 33 | 1284 | 95 % (19 / 20) | 0 | 1 | 17.1 ± 4.0 | 0.4 ± 0.5 % | 11.3 ± 2.0 s | 22.1 ± 4.5 s |
| Bourreau | étage 1 | vide | 0 | 140 | 100 % (20 / 20) | 0 | 0 | 18.0 ± 0.0 | 5.9 ± 2.6 % | 11.9 ± 1.0 s | 42.9 ± 13.8 s |
| Bourreau | étage 1 | plein | 33 | 176 | 100 % (20 / 20) | 0 | 0 | 18.0 ± 0.0 | 2.6 ± 2.1 % | 9.9 ± 0.7 s | 28.4 ± 10.1 s |
| Bourreau | étage 109 | vide | 0 | 573 | 100 % (20 / 20) | 0 | 0 | 18.0 ± 0.0 | 2.5 ± 1.8 % | 11.4 ± 0.9 s | 22.9 ± 4.7 s |
| Bourreau | étage 109 | plein | 33 | 609 | 100 % (20 / 20) | 0 | 0 | 18.0 ± 0.0 | 0.6 ± 0.8 % | 9.6 ± 0.8 s | 17.8 ± 4.1 s |
| Bourreau | étage 325 | vide | 0 | 1300 | 100 % (20 / 20) | 0 | 0 | 18.0 ± 0.0 | 4.3 ± 2.5 % | 12.2 ± 1.4 s | 23.6 ± 4.3 s |
| Bourreau | étage 325 | plein | 33 | 1336 | 85 % (17 / 20) | 0 | 3 | 16.8 ± 3.9 | 1.1 ± 0.8 % | 9.8 ± 1.3 s | 20.3 ± 5.1 s |
| Chasseresse | étage 1 | vide | 0 | 80 | 95 % (19 / 20) | 0 | 1 | 17.9 ± 0.7 | 0.7 ± 1.1 % | 11.0 ± 0.9 s | 26.0 ± 7.4 s |
| Chasseresse | étage 1 | plein | 33 | 80 | 100 % (20 / 20) | 0 | 0 | 18.0 ± 0.0 | 0.1 ± 0.2 % | 9.2 ± 0.6 s | 14.9 ± 4.6 s |
| Chasseresse | étage 109 | vide | 0 | 513 | 100 % (20 / 20) | 0 | 0 | 18.0 ± 0.0 | 0.1 ± 0.3 % | 11.1 ± 1.0 s | 21.0 ± 5.7 s |
| Chasseresse | étage 109 | plein | 33 | 513 | 100 % (20 / 20) | 0 | 0 | 18.0 ± 0.0 | 0.3 ± 0.7 % | 9.2 ± 0.7 s | 11.2 ± 2.2 s |
| Chasseresse | étage 325 | vide | 0 | 1240 | 100 % (20 / 20) | 0 | 0 | 18.0 ± 0.0 | 0.1 ± 0.2 % | 12.9 ± 1.0 s | 22.6 ± 4.9 s |
| Chasseresse | étage 325 | plein | 33 | 1240 | 95 % (19 / 20) | 0 | 1 | 17.6 ± 2.0 | 0.1 ± 0.3 % | 10.3 ± 0.6 s | 11.0 ± 2.2 s |

## 2. Part des dégâts infligés : attaque de base, compétences, ultime

« Base » : coups d'arme et frappes de déplacement. « Compétences » : à recharge et à charges. « Ultime » : ses
dégâts propres, les morsures des limiers et, pendant la Forme du Damné, les griffes. « Autres » : brûlure,
éclairs et explosions des bénédictions, chocs de mur. Les coups comptent à leur montant affiché (le dernier coup d'un ennemi compris).

| Classe | Départ | Arbre | Base | Compétences | Ultime | Autres | Ultimes lancés / section | Compétences lancées / section |
|---|---|---|---|---|---|---|---|---|
| Revenant | étage 1 | vide | 31.5 ± 4.8 % | 25.6 ± 3.2 % | 27.4 ± 5.8 % | 15.5 ± 9.0 % | 7.8 ± 1.1 | 138 ± 22 |
| Revenant | étage 1 | plein | 17.6 ± 2.5 % | 42.7 ± 5.7 % | 33.0 ± 7.4 % | 6.7 ± 7.1 % | 8.3 ± 1.7 | 151 ± 21 |
| Revenant | étage 109 | vide | 26.3 ± 3.8 % | 31.7 ± 3.8 % | 30.6 ± 7.1 % | 11.4 ± 7.2 % | 8.8 ± 1.6 | 145 ± 15 |
| Revenant | étage 109 | plein | 12.4 ± 2.4 % | 52.3 ± 4.4 % | 29.3 ± 4.7 % | 6.0 ± 3.9 % | 8.6 ± 1.4 | 170 ± 16 |
| Revenant | étage 325 | vide | 22.9 ± 2.9 % | 31.1 ± 4.3 % | 34.9 ± 5.2 % | 11.1 ± 6.5 % | 12.1 ± 1.2 | 193 ± 10 |
| Revenant | étage 325 | plein | 10.6 ± 2.1 % | 53.0 ± 11.3 % | 30.2 ± 8.6 % | 6.2 ± 4.8 % | 10.8 ± 2.7 | 198 ± 47 |
| Bourreau | étage 1 | vide | 53.6 ± 5.1 % | 19.2 ± 2.8 % | 19.4 ± 5.0 % | 7.8 ± 5.4 % | 9.6 ± 1.9 | 102 ± 12 |
| Bourreau | étage 1 | plein | 29.4 ± 3.9 % | 46.9 ± 5.2 % | 19.8 ± 4.2 % | 3.8 ± 3.3 % | 11.3 ± 1.7 | 121 ± 11 |
| Bourreau | étage 109 | vide | 42.0 ± 5.8 % | 26.3 ± 2.4 % | 26.5 ± 6.2 % | 5.2 ± 3.9 % | 11.7 ± 1.1 | 106 ± 9 |
| Bourreau | étage 109 | plein | 18.7 ± 3.0 % | 56.1 ± 3.7 % | 22.0 ± 5.9 % | 3.3 ± 4.3 % | 13.6 ± 3.7 | 129 ± 11 |
| Bourreau | étage 325 | vide | 33.8 ± 8.9 % | 28.1 ± 5.8 % | 34.1 ± 13.1 % | 4.0 ± 3.8 % | 17.8 ± 5.4 | 131 ± 25 |
| Bourreau | étage 325 | plein | 16.1 ± 4.4 % | 55.3 ± 5.5 % | 26.7 ± 6.7 % | 1.9 ± 2.5 % | 16.5 ± 4.6 | 135 ± 34 |
| Chasseresse | étage 1 | vide | 61.3 ± 5.8 % | 17.7 ± 2.6 % | 8.5 ± 2.4 % | 12.6 ± 6.3 % | 7.1 ± 1.2 | 94 ± 9 |
| Chasseresse | étage 1 | plein | 42.9 ± 7.0 % | 37.9 ± 5.3 % | 9.3 ± 2.2 % | 9.9 ± 5.9 % | 6.9 ± 1.0 | 91 ± 11 |
| Chasseresse | étage 109 | vide | 52.4 ± 4.5 % | 25.6 ± 3.3 % | 9.8 ± 2.9 % | 12.2 ± 6.5 % | 8.3 ± 0.6 | 112 ± 12 |
| Chasseresse | étage 109 | plein | 34.6 ± 5.4 % | 45.2 ± 5.2 % | 10.7 ± 3.5 % | 9.5 ± 5.2 % | 8.4 ± 1.5 | 103 ± 8 |
| Chasseresse | étage 325 | vide | 49.5 ± 7.6 % | 27.3 ± 5.0 % | 9.6 ± 1.9 % | 13.6 ± 7.8 % | 11.6 ± 1.8 | 143 ± 20 |
| Chasseresse | étage 325 | plein | 29.9 ± 4.8 % | 52.6 ± 6.1 % | 9.9 ± 2.5 % | 7.5 ± 2.4 % | 10.7 ± 1.9 | 129 ± 25 |

## 3. La Forme du Damné (Revenant)

« En forme » : part du temps de combat passée transformé. Dégâts par seconde de combat, en forme et hors forme.
Coups reçus : en % des PV max par MINUTE de combat, en forme et hors forme. Soins : tout ce qui a été soigné dans la section, en % des PV max.

| Départ | Arbre | En forme | Dégâts / s en forme | Dégâts / s hors forme | Rapport | Reçus / min en forme | Reçus / min hors forme | Soins sur la section |
|---|---|---|---|---|---|---|---|---|
| étage 1 | vide | 19.0 ± 3.4 % | 111 ± 19 | 62 ± 10 | ×1.79 | 16.6 ± 22.2 % | 12.0 ± 9.5 % | 32 ± 43 % |
| étage 1 | plein | 29.0 ± 7.2 % | 118 ± 28 | 88 ± 13 | ×1.35 | 5.0 ± 12.0 % | 6.7 ± 7.8 % | 13 ± 20 % |
| étage 109 | vide | 25.3 ± 5.8 % | 730 ± 148 | 516 ± 75 | ×1.42 | 5.6 ± 12.3 % | 1.5 ± 2.2 % | 3 ± 3 % |
| étage 109 | plein | 33.7 ± 4.6 % | 789 ± 101 | 847 ± 107 | ×0.93 | 2.1 ± 4.7 % | 2.2 ± 4.7 % | 2 ± 2 % |
| étage 325 | vide | 31.0 ± 3.8 % | 2055 ± 313 | 1575 ± 125 | ×1.30 | 6.6 ± 8.8 % | 3.9 ± 4.5 % | 5 ± 8 % |
| étage 325 | plein | 37.2 ± 9.5 % | 2315 ± 384 | 2706 ± 373 | ×0.86 | 2.3 ± 4.0 % | 1.3 ± 2.4 % | 1 ± 2 % |

## 4. Le déplacement de classe compte-t-il encore en profondeur ?

Arbre vide, le même bot avec son déplacement (dash, saut, roulade) puis sans (il esquive à pied). « Valeur » : dégâts reçus
par salle sans le geste ÷ avec (l'oracle de jouabilité exige ×2.0 en section 1, sur les kits et les graines de `outils/classes.gd`).

| Classe | Départ | Section battue avec | … sans | Dégâts reçus / salle avec | … sans | Valeur du geste |
|---|---|---|---|---|---|---|
| Revenant (dash) | étage 1 | 100 % | 55 % | 3.8 ± 3.0 % | 21.0 ± 5.2 % | ×5.6 |
| Revenant (dash) | étage 109 | 100 % | 90 % | 0.6 ± 0.8 % | 16.9 ± 5.2 % | ×27.3 |
| Revenant (dash) | étage 325 | 100 % | 85 % | 1.5 ± 1.2 % | 19.4 ± 6.8 % | ×13.2 |
| Bourreau (saut) | étage 1 | 100 % | 25 % | 5.9 ± 2.6 % | 14.9 ± 5.0 % | ×2.5 |
| Bourreau (saut) | étage 109 | 100 % | 50 % | 2.5 ± 1.8 % | 17.7 ± 4.2 % | ×7.2 |
| Bourreau (saut) | étage 325 | 100 % | 65 % | 4.3 ± 2.5 % | 17.0 ± 6.4 % | ×4.0 |
| Chasseresse (roulade) | étage 1 | 95 % | 20 % | 0.7 ± 1.1 % | 22.6 ± 9.7 % | ×31.0 |
| Chasseresse (roulade) | étage 109 | 100 % | 55 % | 0.1 ± 0.3 % | 16.8 ± 4.9 % | plus de ×84 |
| Chasseresse (roulade) | étage 325 | 100 % | 80 % | 0.1 ± 0.2 % | 23.2 ± 7.3 % | plus de ×116 |

## 5. Les échelles, lues dans les règles

Tout coup du héros — arme, compétence à n'importe quel rang, ultime, morsure d'un limier, brûlure — est multiplié par
`dégâts de l'arme portée ÷ weaponBase` (D6Combat._scaled_amount) : un nombre de dégâts « fixe » des données suit donc l'arme.
Les PV des ennemis montent plus vite que l'arme (c'est voulu : les bénédictions de la descente comblent l'écart).

| Départ | PV des ennemis | Dégâts des ennemis | Arme du héros | PV max du héros | Un coup de 30 (Lance, rang 1) | … en % d'un diablotin | Un soin de 6 PV, en % des PV max |
|---|---|---|---|---|---|---|---|
| étage 1 | ×1.0 | ×1.0 | ×1.0 | 100 | 30 | 136 % | 6.0 % |
| étage 109 | ×8.2 | ×7.2 | ×8.8 | 533 | 265 | 147 % | 1.1 % |
| étage 325 | ×28.0 | ×18.3 | ×23.9 | 1260 | 716 | 116 % | 0.5 % |

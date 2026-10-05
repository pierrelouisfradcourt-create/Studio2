# Dungeon 666 — le combat V3 en profondeur : lecture de la mesure

2026-10-05 · tableaux complets : `_dev/rapports/profondeur_mesures.md` (généré par `bash outils/profondeur.sh 20`).
Mesure : le bot habile, chaque classe (Lame, Hache, Arc), une section entière depuis les étages **1, 109 et 325**,
arbre VIDE puis arbre PLEIN (33 points), et une fois sans déplacement de classe. **20 graines par case** : 540 parties.
Chaque nombre est une moyenne ± l'écart-type ENTRE GRAINES ; l'incertitude sur une moyenne est cet écart ÷ 4,5.

Comment la profondeur est atteinte : une reprise depuis un point — premier étage de la section, aucune bénédiction.
Étage 1 : héros neuf. Étages 109 et 325 : toute la Ville achetée, trois objets RARES du niveau de l'étage précédent.
Arbre plein : les trois compétences jouées au rang 5 avec leur première amélioration, puis les passifs, puis le
déplacement et l'ultime, le reste dans les autres compétences (politique écrite en tête de `outils/profondeur.gd`).

**Limite à garder en tête.** Le bot esquive presque tout et ne construit pas son héros : il mesure des écarts, pas
le danger ressenti. Le danger « pour quelqu'un qui n'esquive pas » se lit dans la ligne « sans déplacement ».

## (a) L'arbre plein rend-il la profondeur triviale ?

Pour ce bot, la profondeur n'est PAS dangereuse, avec ou sans arbre : **0 mort sur 360 parties** (vide et plein, trois
profondeurs). L'arbre plein la rend encore plus facile, sans changer sa nature :

| À l'étage 325 | Dégâts reçus / salle (% des PV max) | Temps par salle | Combat du Gardien |
|---|---|---|---|
| Revenant, vide → plein | 1,5 ± 1,2 → 0,4 ± 0,5 (×0,27) | 14,6 → 11,3 s (×0,77) | 30,5 → 22,1 s (×0,72) |
| Bourreau, vide → plein | 4,3 ± 2,5 → 1,1 ± 0,8 (×0,26) | 12,2 → 9,8 s (×0,80) | 23,6 → 20,3 s (×0,86) |
| Chasseresse, vide → plein | 0,1 ± 0,2 → 0,1 ± 0,3 (égal) | 12,9 → 10,3 s (×0,80) | 22,6 → 11,0 s (×0,49) |

- La profondeur ne coûte pas plus cher que la section 1 : arbre vide, le Revenant perd 3,8 % de ses PV par salle à
  l'étage 1, 0,6 % au 109, 1,5 % au 325 (Bourreau : 5,9 / 2,5 / 4,3). Le héros équipé « rare » et la Ville achetée
  compensent l'échelle des ennemis.
- Ce qui reste dangereux se voit sans le déplacement : 15 à 23 % des PV perdus PAR SALLE à toute profondeur, et la
  section n'est battue que 20 à 90 % du temps (Bourreau : 25 % / 50 % / 65 %).
- 6 parties sur 540 ne sont pas allées au bout SANS que le héros meure (5 à l'arbre plein au 325, 1 Chasseresse à
  l'étage 1) : le BOT reste coincé, salle nettoyée, sans rejoindre la récompense (disposition « chicane », au coin
  d'un mur). C'est un défaut de navigation du bot, pas une règle : vu, non corrigé (voir plus bas). Les « 85 % » et
  « 95 % » de sections battues du tableau 1 sont ces blocages.

## (b) Une classe est-elle nettement au-dessus ou au-dessous ?

Oui, et l'écart est le même qu'en section 1 : **la Chasseresse est au-dessus, le Bourreau au-dessous**.

| Arbre vide | Dégâts reçus / salle, étages 1 / 109 / 325 | Gardien, arbre plein, étages 1 / 109 / 325 |
|---|---|---|
| Revenant | 3,8 / 0,6 / 1,5 % | 31,7 / 20,5 / 22,1 s |
| Bourreau | 5,9 / 2,5 / 4,3 % | 28,4 / 17,8 / 20,3 s |
| Chasseresse | 0,7 / 0,1 / 0,1 % | 14,9 / 11,2 / 11,0 s |

- La Chasseresse ne prend presque rien (le bot tient la distance) et, arbre plein, tue le Gardien deux fois plus vite
  que les deux autres. Son ultime pèse peu en dégâts (9 à 10 % à toute profondeur) : la Meute sert de bouclier.
- Le Bourreau est celui qui encaisse le plus, et ce qui faisait sa carcasse s'efface : ses +40 PV valent +40 % de vie
  à l'étage 1 (140 contre 100) et **+3 % à l'étage 325** (1 300 contre 1 260). Voir « PV fixes » plus bas.

## (c) Les rangs et les ultimes suivent-ils l'échelle des ennemis ?

**Oui pour les dégâts.** Dans les règles, TOUT coup du héros — arme, compétence à n'importe quel rang, ultime, morsure
d'un limier, brûlure — est multiplié par `dégâts de l'arme portée ÷ weaponBase` (`D6Combat._scaled_amount`). Un nombre
« fixe » des données suit donc l'arme : la Lance au rang 1 (30) retire 136 % d'un diablotin à l'étage 1, 147 % au 109,
116 % au 325. La jauge d'ultime est à la même échelle (`chargeDamage` × l'arme). Mesuré :

| Part des dégâts, arbre vide, étages 1 / 109 / 325 | Compétences | Ultime |
|---|---|---|
| Revenant | 26 / 32 / 31 % | 27 / 31 / 35 % |
| Bourreau | 19 / 26 / 28 % | 19 / 27 / 34 % |
| Chasseresse | 18 / 26 / 27 % | 9 / 10 / 10 % |

Rien ne devient négligeable ; la part des compétences et de l'ultime MONTE un peu. Arbre plein, les compétences font
38 à 56 % des dégâts à toute profondeur (17 à 28 points de plus qu'à vide) : les rangs comptent autant au 325 qu'à l'étage 1.
Gardé par `tests/regles/v3_profondeur.gd`.

**Non pour les SOINS en PV de l'arbre : défaut d'échelle, CORRIGÉ.** Les PV max du héros passent de 100 à 533 puis
1 260 ; un soin écrit en PV ne suivait rien :

| Soin de l'arbre | Avant, étage 1 → 325 | Après, étage 1 → 325 |
|---|---|---|
| Moisson (Stigmate) : 6 PV quand le marqué explose | 6,0 % → 0,5 % des PV max | 6,0 % → 4,7 % |
| Dîme de sang (Triple sentence) : 4 PV par ennemi frappé | 4,0 % → 0,3 % | 4,0 % → 3,1 % |
| Soif (Tourbillon de colère) : 1 PV par ennemi touché | 1,0 % → 0,08 % | 1,0 % → 0,8 % |

Règle : `D6Combat.heal_scaled` multiplie ces soins par les PV d'un héros équipé du niveau de l'étage (`hpGrowth` de
`D6Floors.floor_scaling` : ×1 à l'étage 1, ×4,0 au 109, ×9,9 au 325). Les objets le faisaient déjà (« PV par ennemi tué »
d'un affixe grandit avec le niveau de l'objet). Test : `v3_profondeur.gd`, « Moisson, Soif et Dîme de sang soignent à
l'échelle de l'étage ». Aucune partie de référence ne change ; les mesures sont identiques avant et après (la
politique d'arbre de la mesure ne prend aucune de ces trois améliorations).

**La jauge se remplit plus vite en profondeur (non corrigé, à juger).** Ultimes lancés par section, arbre vide :
Revenant 7,8 → 8,8 → 12,1 ; Bourreau 9,6 → 11,7 → 17,8 ; Chasseresse 7,1 → 8,3 → 11,6. La jauge suit l'arme (×23,9 au
325), les PV des ennemis montent plus vite (×28) et les salles sont plus peuplées : il y a plus de dégâts à faire par
salle, donc plus de jauge.

## (d) La Forme du Damné, le saut du Bourreau

**Forme du Damné** — soupçonnée trop forte. Le bot dit : forte au début avec un arbre vide, PERDANTE en profondeur
avec un arbre plein.

| Revenant | En forme (part du combat) | Dégâts / s en forme ÷ hors forme | Reçus / min en forme | Reçus / min hors forme |
|---|---|---|---|---|
| étage 1, vide | 19 ± 3 % | ×1,79 | 17 ± 22 % | 12 ± 10 % |
| étage 1, plein | 29 ± 7 % | ×1,35 | 5 ± 12 % | 7 ± 8 % |
| étage 109, vide | 25 ± 6 % | ×1,42 | 6 ± 12 % | 1,5 ± 2 % |
| étage 109, plein | 34 ± 5 % | ×0,93 | 2 ± 5 % | 2 ± 5 % |
| étage 325, vide | 31 ± 4 % | ×1,30 | 7 ± 9 % | 4 ± 5 % |
| étage 325, plein | 37 ± 10 % | ×0,86 | 2 ± 4 % | 1 ± 2 % |

- Elle ne rend pas intouchable : en forme le héros prend au moins autant de coups par minute qu'hors forme (les
  griffes le collent aux ennemis ; le vol de vie de 5 % ne compense pas — ces nombres sont très bruités).
- Arbre plein, elle fait MOINS de dégâts que le kit qu'elle remplace (×0,93 puis ×0,86) : les compétences au rang 5
  sont figées pendant la forme, et les griffes ne profitent d'aucun rang. Elle occupe pourtant un tiers du combat.

**Saut du Bourreau** — au ras des seuils. Ce que vaut le geste (dégâts reçus par salle sans ÷ avec, arbre vide) :

| | Étage 1 | Étage 109 | Étage 325 |
|---|---|---|---|
| Revenant (dash) | ×5,6 | ×27 | ×13 |
| Bourreau (saut) | **×2,5** | ×7,2 | ×4,0 |
| Chasseresse (roulade) | ×31 | plus de ×84 | plus de ×116 |

Le saut reste le geste qui protège le moins, mais il n'est au ras du seuil de l'oracle (×2) QU'en section 1 ; en
profondeur il compte nettement. Sans lui le Bourreau ne bat la section que 25 %, 50 % et 65 % du temps.

## Recommandations NON appliquées (équilibrage de goût : à Pierre)

1. **PV fixes.** Les bonus de PV écrits en dur ne suivent pas la vie du héros : classe (Bourreau +40, Chasseresse −20),
   passifs de l'arbre (Sang vif +8 par rang, Cuir épais +12), Ville (Vitalité), bénédiction Voracité (+30). Trois
   points d'arbre dans Sang vif donnent +24 % de vie à l'étage 1 et **+1,9 % au 325**. Proposition : les écrire en
   pourcentage des PV max (Bourreau +40 %, Chasseresse −20 %, Sang vif +8 % par rang, Cuir épais +9 %) ou les passer
   par la même échelle que les soins. Cela change la force relative des classes en profondeur : non touché.
2. **Soins fixes des bénédictions** (Festin : 2 PV par ennemi tué, et les autres soins en PV de
   `data/benedictions.json`) : le même défaut que celui corrigé dans l'arbre, dans un contenu d'avant le combat V3.
   Proposition : les passer par `D6Combat.heal_scaled`.
3. **Jauge d'ultime en profondeur** : ×1,5 à ×1,9 d'ultimes par section au 325. Si ce n'est pas voulu : faire suivre
   `chargeDamage` par les PV des ennemis de l'étage (`floor_scaling.hp`) au lieu de l'arme — le nombre d'ultimes par
   section resterait celui de la section 1 (8 à 10).
4. **Forme du Damné** : ne pas la baisser sur la foi du bot. Pour qu'elle ne soit plus perdante à l'arbre plein
   (×0,86 au 325), il lui manque environ 15 à 20 % de dégâts : par exemple griffes 11 / 11 / 18 → 13 / 13 / 21, ou un
   rang de « Forme tenace » qui donne aussi des dégâts. Si elle paraît trop forte EN MAIN au début (×1,8 à l'étage 1,
   arbre vide), c'est sa durée de 10 s qui est le réglage (elle tient 19 % du combat).
5. **Chasseresse au-dessus** (0,1 % de vie perdue par salle, Gardien tué deux fois plus vite) : écart déjà présent en
   section 1, donc pas un effet de profondeur. À juger en main avant tout réglage : le bot tient la distance mieux
   qu'un joueur. Piste si l'écart se confirme : le Gardien (Nuée de traits, rang 5 de la Volée) plutôt que la survie.
6. **Saut du Bourreau** : rien à faire en profondeur. En section 1 la marge sur l'oracle reste mince (×2,5 pour un
   seuil de ×2) : ne pas le ralentir davantage.

## Vu, non corrigé : le bot coincé

Parties bloquées (salle nettoyée, récompense non rejointe pendant 30 s, héros libre de ses mouvements) : arbre plein,
étage 325 — Bourreau graines 6, 9, 18 ; Revenant graine 16 ; Chasseresse graine 12 ; arbre vide, étage 1 —
Chasseresse, une graine. Exemple (Bourreau, graine 9, étage 326) : disposition « chicane », héros qui oscille autour
de (240, 245) au coin nord-ouest du mur (272, 270)–(792, 310), récompense en (700, 396). La navigation du bot
(`outils/bots/base.gd`, `nav_dir`) hésite à ce coin. Non corrigé : ce bot joue les oracles de jouabilité et les
parties de référence ; le changer demande un lot à part (et de réenregistrer les références).

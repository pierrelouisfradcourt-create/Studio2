# World Scan Tetris — carte de progression

*Produit le 2026-08-03. ADVISORY. Sources : `observation_manifest.json`.*

## La progression n'est pas du contenu, c'est de la vitesse

Tetris n'a ni déblocage, ni arbre de compétences, ni contenu ajouté. La seule variable
de progression est **la gravité**. C'est une propriété rare et structurante : le jeu
ne devient pas plus riche, il devient plus rapide.

| Horizon | Ce qui change | Ce que le joueur doit apprendre |
|---|---|---|
| minute 1 | rien | les 7 formes, la rotation |
| minute 10 | gravité légèrement accrue | creuser un puits, réserver la pièce I |
| heure 5 | gravité au-delà du confort | arbitrer survie vs score |
| fin | gravité au-delà de la décision | rien — la limite est physiologique |

## Courbe observée (NES, la mieux documentée)

Le niveau avance de 1 lorsque le joueur nettoie `startLevel × 10 + 10` lignes ou
`max(100, startLevel × 10 − 50)`, selon ce qui arrive en premier ; ensuite **+1 tous
les 10 lignes**. Source : [tetris.wiki/Tetris_(NES,_Nintendo)](https://tetris.wiki/Tetris_(NES,_Nintendo)).

La table de gravité elle-même est une donnée du ROM (adresse `$898E`), pas une formule
publiée — **on ne la reproduit pas ici** : recopier des valeurs qu'on n'a pas mesurées
serait exactement la promesse trop forte que ce studio refuse.

## Conséquence pour un build Forge

La courbe de gravité est un **paramètre à calibrer**, pas une valeur à copier. Le
charter doit la déclarer `A_CALIBRER` et la wiremap doit l'isoler dans `params/` —
jamais la disperser dans la boucle de jeu.

## Limite déclarée

Aucune mesure de progression réelle sur un joueur. Cette carte décrit la *structure*
de la progression, pas son rythme ressenti.

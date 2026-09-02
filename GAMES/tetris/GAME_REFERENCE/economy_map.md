# World Scan Tetris — carte d'économie

*Produit le 2026-08-03. ADVISORY. Sources : `observation_manifest.json`.*

## Il n'y a pas de monnaie — il y a une ressource rare

Tetris n'a aucune économie au sens habituel : pas de monnaie, pas d'achat, pas
d'inventaire. Ce qui circule, c'est **l'espace vertical**, et il est strictement
conservé : chaque pièce posée en consomme, chaque ligne nettoyée en rend.

| Ressource | Produite par | Consommée par | Épuisement |
|---|---|---|---|
| espace vertical | nettoyage de ligne | pose de pièce | = fin de partie |
| temps de décision | palier de gravité | chute de la pièce | = erreur forcée |
| pièce I | générateur (sac de 7) | quadruple, ou gâchée à plat | = puits jamais vidé |

## Le barème est le seul levier d'incitation

Au niveau 0 de la version NES : **40** points pour une ligne, **100/ligne** pour un
triple, **300/ligne** pour un quadruple, et 1 point par case de soft-drop continu.
Source : [harddrop.com/wiki/Tetris_(NES,_Nintendo)](https://harddrop.com/wiki/Tetris_(NES,_Nintendo)).

Lecture de conception : le facteur ~7,5× entre le simple et le quadruple **par ligne**
n'est pas un détail d'équilibrage, c'est ce qui crée la tension centrale du jeu. Un
barème plat rendrait le jeu mécaniquement identique et psychologiquement mort.

## Ce qu'il ne faut pas copier

Les chiffres ci-dessus appartiennent à une version précise, avec sa gravité et sa
taille de terrain. Les transposer tels quels dans un autre équilibrage serait une
réutilisation de type CONCEPT présentée comme du CODE_COPIE. **Ce qui se réutilise
ici est le rapport entre les paliers, pas les valeurs.**

## Limite déclarée

Aucune simulation, aucune mesure de distribution de score. La hiérarchie des
récompenses est documentée ; son effet sur le comportement réel du joueur ne l'est pas.

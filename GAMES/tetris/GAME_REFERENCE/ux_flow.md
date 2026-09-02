# World Scan Tetris — flux d'expérience

*Produit le 2026-08-03. ADVISORY. Sources : `observation_manifest.json`.*

## Le flux tient en un seul écran

Il n'y a ni menu profond, ni navigation, ni écran intermédiaire pendant la partie.
Tout ce dont le joueur a besoin est visible en permanence : le terrain, la pièce
courante, l'aperçu, le score. **Un Tetris qui exige de détourner le regard est cassé.**

## Boucle d'entrée → action → retour

| Étape | Entrée joueur | Retour immédiat attendu |
|---|---|---|
| déplacer | gauche / droite | la pièce bouge d'une case, ou ne bouge pas (mur/collision) — jamais d'ambiguïté |
| tourner | rotation | la pièce tourne, ou refuse visiblement ; avec SRS, elle peut « glisser » (kick) |
| accélérer | soft drop | la chute s'accélère tant que la touche est tenue |
| poser | hard drop, ou atterrissage | la pièce se fige ; les lignes pleines disparaissent |

## Le seul moment de récompense

Le nettoyage de ligne est **le** point de satisfaction du genre. Trois choses doivent
y être lisibles sans être expliquées : quelles lignes partent, que la pile descend, et
que le score monte. Aucune des trois n'a besoin de texte.

## Ce que le joueur doit pouvoir observer (contrainte pour la wiremap)

Une ligne de wiremap qui prétend `observable_by_player: true` doit désigner un de ces
faits :

- la pièce courante se déplace / tourne / refuse de tourner ;
- une ligne pleine disparaît et la pile se compacte ;
- le score et le compteur de lignes changent ;
- la partie s'arrête parce qu'une pièce ne peut plus apparaître.

Tout le reste (générateur, état interne, paramètres) est observable **indirectement**
et doit porter `observable_by_player: false` avec sa note — même règle que Breakout V2.

## Limite déclarée

Aucun playtest, aucune capture. Ce document décrit le flux **documenté et déduit**, pas
un flux mesuré sur un joueur réel.

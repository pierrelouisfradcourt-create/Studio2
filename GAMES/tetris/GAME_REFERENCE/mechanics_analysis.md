# World Scan Tetris — analyse mécanique

*Produit le 2026-08-03. ADVISORY : cette observation informe la Genre Bible, elle ne
décide rien. Sources citées par URL dans `observation_manifest.json`.*

## Table de provenance

| Observation | Source | Confiance | Décision qu'elle informe |
|---|---|---|---|
| Terrain 10×40, dont 20 lignes visibles | [tetris.wiki/Tetris_Guideline](https://tetris.wiki/Tetris_Guideline) | HAUTE (spec éditeur) | dimensions du terrain, zone de spawn |
| 7 tetrominos, sac de 7 sans répétition | [tetris.wiki/Tetris_Guideline](https://tetris.wiki/Tetris_Guideline) | HAUTE | générateur de pièces |
| SRS : 5 points de rotation, wall kicks | [tetris.wiki/Super_Rotation_System](https://tetris.wiki/Super_Rotation_System) · [harddrop.com/wiki/SRS](https://harddrop.com/wiki/SRS) | HAUTE | règle de rotation |
| Wall kick introduit en 2001 (Tetris Worlds) — absent avant | [harddrop.com/wiki/SRS](https://harddrop.com/wiki/SRS) | MOYENNE (historique) | choix : avec ou sans kick |
| NES : niveau +1 tous les 10 lignes après le premier palier | [tetris.wiki/Tetris_(NES,_Nintendo)](https://tetris.wiki/Tetris_(NES,_Nintendo)) | HAUTE | courbe de gravité |
| NES niveau 0 : 40/100/300 pts par ligne selon 1/3/4 lignes | [harddrop.com/wiki/Tetris_(NES,_Nintendo)](https://harddrop.com/wiki/Tetris_(NES,_Nintendo)) | HAUTE | barème |
| NES : maxout à 999 999 | [tetris.wiki/Tetris_(NES,_Nintendo)](https://tetris.wiki/Tetris_(NES,_Nintendo)) | HAUTE | condition de fin |

## Ce qui fait qu'un Tetris est un Tetris

1. **Chute continue sous gravité discrète.** La pièce descend d'une case à intervalle
   régulier. Le joueur agit *pendant* la chute, jamais après.
2. **Empilement irréversible.** Une pièce posée ne bouge plus. C'est la propriété qui
   crée la dette : toute erreur reste visible et contraint le futur.
3. **Ligne pleine → disparition + compactage.** La seule façon de réduire la dette.
4. **Rotation contrainte par le terrain.** Une rotation qui collisionne est refusée
   (ou rattrapée par un kick, selon la variante). C'est ce qui rend le terrain
   *tactique* plutôt que décoratif.
5. **Fin par blocage, pas par victoire.** En marathon, la partie ne se gagne pas. La
   condition de fin est « la pièce entrante ne peut pas apparaître ».

## Écarts entre les deux références observées

| Point | Guideline (2001+) | NES (1989) |
|---|---|---|
| wall kick | oui (SRS) | non |
| réserve (hold) | oui | non |
| aperçu | plusieurs pièces | une pièce |
| fin | blocage | blocage **ou** maxout 999 999 |

**Conséquence pour la conception :** ces quatre écarts sont des *choix*, pas des
invariants du genre. Une Genre Bible honnête doit distinguer ce qui est constitutif
(points 1-5 ci-dessus) de ce qui est une variante (le tableau).

## Limite déclarée

Aucune observation de session réelle : cette analyse porte sur des faits mécaniques
documentés. Le *ressenti* (lisibilité, timing, satisfaction du quadruple) n'est pas
mesuré ici et ne doit pas être revendiqué à partir de ce document.

# World Scan Tetris — hypothèse d'architecture

*Produit le 2026-08-03. ADVISORY, et **hypothèse** : aucun code source des jeux
observés n'a été lu. Ce document propose un découpage, il ne constate rien.*

## Découpage proposé (systèmes, au sens `05_SYSTEMS/` du standard)

| Système | Responsabilité | Ne fait PAS |
|---|---|---|
| `params` | toutes les constantes nommées (terrain, gravité, barème) | aucune règle |
| `game_state` | détient l'état (grille, pièce courante, score, statut) | ne décide rien |
| `piece_bag` | générateur : sac de 7 sans répétition, déterministe par seed | ne pose pas |
| `rotation_rules` | rotation + refus + kicks | ne dessine pas |
| `collision` | une position est-elle légale ? | ne déplace pas |
| `gravity` | quand la pièce descend d'une case | ne teste pas la collision |
| `lock_rules` | quand une pièce se fige | ne nettoie pas |
| `line_clear` | détecte les lignes pleines, les retire, compacte | ne score pas |
| `scoring` | barème par nombre de lignes simultanées | ne connaît pas la grille |
| `game_loop` | ordonne les systèmes sur un tick | n'implémente aucune règle |
| `input_rules` | traduit une entrée brute en intention légale | n'applique pas |
| `debug_state` | point d'observation pour l'oracle | n'est pas du gameplay |

## Deux invariants d'architecture que l'observation impose

1. **La rotation ne peut pas connaître le rendu.** SRS est une table de décalages
   testée contre la grille ; c'est de la règle pure, testable sans fenêtre.
2. **Le scoring ne doit pas connaître la grille.** Il reçoit *un nombre de lignes*.
   Les mélanger rendrait le barème intestable indépendamment.

## Réutilisation attendue depuis les jeux déjà forgés

`params`, `game_state`, `game_loop`, `input_rules`, `debug_state` existent déjà en
forme prouvée dans `games/snake/` et `games/breakout_v2/`. La réutilisation sera de
type **CONCEPT** (la discipline, pas le code) — une grille discrète de Tetris n'a pas
la même nature que la physique continue de Breakout.

**Conséquence directe** : chaque ligne de wiremap portant `reused_from.type: CONCEPT`
devra porter une requalification non vide, sans quoi l'oracle standard la remontera
(règle posée en réponse à la leçon `forge.wiremap_concept_reuse_requalification`).

## Limite déclarée

Découpage **proposé**, non validé par un oracle. Il n'a autorité qu'après passage en
wiremap gelée et vérification par `check_line_states` / `check_placement`.

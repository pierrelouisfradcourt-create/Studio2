# Pattern — Full Reachability (atteignabilité complète du niveau généré)

- **brick_id** : `pat-full-reachability`
- **kind** : pattern (advisory, cité — ZÉRO code repris)
- **source** : Shattered Pixel Dungeon — génération de donjon
- **provenance_url** : https://github.com/00-Evan/shattered-pixel-dungeon
- **licence** : GPL-3.0-only (concept cité uniquement ; aucune ligne de code SPD copiée)
- **runtime** : agnostic — **advisory_only: true**

## Énoncé

Un niveau généré procéduralement n'est **valide** que si **toute case objectif requise** (sortie,
clé, ressource nécessaire à la victoire) est **atteignable** depuis la position de départ du joueur,
en respectant les obstacles. La génération rejette et régénère (ou répare) tout niveau où un
objectif requis est isolé.

## Vérification (BFS de couverture)

Un parcours en largeur (BFS) depuis la case de départ, à travers les cases non bloquées, doit
**visiter toutes les cases objectif requises**. Sinon → niveau invalide.

## Pourquoi (recoupe la doctrine solvabilité TCS)

C'est la version « génération » de la leçon `oracle_solvability_lesson` : un jeu dont l'objectif
est inatteignable passe tous les tests de mécanique en isolation tout en étant **injouable**. Le
pattern déplace la garantie en amont, dans le générateur de niveau.

## Invariants testables (à faire tenir chez tout système inspiré)

1. Pour tout niveau accepté : `BFS(depart) ⊇ objectifs_requis`.
2. Déterminisme : même seed ⇒ même niveau (RNG injecté).
3. Terminaison : la réparation/régénération est bornée (pas de boucle infinie ; échec explicite
   après N tentatives).

## Usage advisory

Cité en conception pour justifier une garantie d'atteignabilité au niveau du générateur. Le CODE
inspiré (`knowledge_base/systems/procgen/`) est une réécriture propre sous licence permissive.

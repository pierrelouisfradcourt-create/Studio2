# Contrat ROLE gameplay — schéma canonique

- **Cible** : `docs/forge/STUDIO_AGENT_ATLAS.md` §2.3 (ROLE-SIM Oracle) et §4 (`knowledge_base/roles/`).
- **Principe** (`docs/forge/STUDIO_ARCHITECTURE.md` §3) : un ROLE est un contrat gameplay
  ABSTRAIT (« poursuivant mobile, cible de difficulté X »). Il déclare `requires{}` — les
  propriétés qu'une pièce LOGIC du catalogue doit fournir pour l'incarner. Un ROLE se lie
  à une pièce **ssi** `affordances(piece) ⊇ requires(role)` (pont vérifiable, pas un
  jugement). La validité d'un ROLE n'est jamais un booléen gagné/perdu (ça, c'est
  `solvability.mjs`, un oracle plus grossier) — c'est une **bande de difficulté mesurée
  par simulation**, comparée à une bande DÉCLARÉE avant la mesure.
- **Règle des 3 états** (comme les contrats d'agent Forge, `scripts/forge/contracts/SCHEMA.md`) :
  un champ est rempli, déclaré-vide (`aucun`), ou absent → absent = contrat refusé par
  `role_sim.mjs` (garde mécanique, pas une convention à la confiance).

## Champs (13)

1. **role_id** (Critique) — identifiant stable, préfixe `role-` (ex. `role-pursuer-mobile`).
2. **archetype** (Critique) — description courte, en langage produit (ex. « poursuivant
   mobile qui doit rattraper une cible fuyante en terrain ouvert »). Pas d'implémentation.
3. **requires** (Critique) — objet `{capacité: {type, description}}` : les fonctions/
   propriétés pures qu'une pièce LOGIC doit exposer pour incarner ce rôle. Exemple :
   `{ movement: { type: "fn(pos, targetPos, speed) -> pos", description: "pas borné par speed, vers la cible" } }`.
4. **fulfilled_by** (Important — `[]` autorisé si aucune pièce ne remplit encore le rôle) —
   liste de `brick_id` du catalogue dont les `affordances` couvrent `requires`.
5. **simulation_module** (Critique, depuis le 2e rôle) — chemin repo-relatif d'un module
   `.mjs` exportant `runTrial(seed, cfg) -> {succeeded, ticks}` — la mécanique CONCRÈTE
   d'UN essai (ex. `knowledge_base/systems/ai/pursuer_scenario.mjs`). `role_sim.mjs` est
   générique : il ne connaît AUCUNE mécanique de jeu, il charge ce module dynamiquement.
   Chaque rôle a le sien — c'est ce qui rend le mécanisme testable sur des archétypes
   différents sans dupliquer l'oracle.
6. **simulation_config** (Critique) — paramètres REPRODUCTIBLES passés à `runTrial`, PLUS
   `trials`/`seed_start` (consommés par `role_sim.mjs` lui-même pour boucler). Toute mesure
   de bande de difficulté doit être rejouable à l'identique depuis ces paramètres seuls
   (déterminisme, comme `solvability.mjs`). Le contenu exact dépend du scénario (un
   poursuivant n'a pas les mêmes paramètres qu'un gardien statique) — `role_sim.mjs` ne
   valide QUE la présence du bloc, pas son contenu (c'est au `simulation_module` de gérer
   des paramètres manquants/invalides s'il le souhaite).
7. **difficulty_target** (Critique) — bande DÉCLARÉE avant toute mesure officielle :
   `{metric, min, max}`. `metric` doit être une clé connue de `role_sim.mjs`
   (`ticks_to_catch_median`, `ticks_to_reach_goal_median`, `success_rate`, ... — voir
   `METRIC_KEYS` dans `role_sim.mjs`, alias domaine → champ générique). Une bande déclarée
   APRÈS avoir lu une mesure de calibration reste légitime (c'est du tuning de design),
   mais DOIT être figée avant la mesure de VALIDATION officielle — sinon c'est exactement
   le retuning post-lecture que `WORKFLOW_LAB_PROTOCOL.md` interdit.
8. **calibration_note** (Important — `aucun` si non calibré) — trace de la mesure
   exploratoire qui a permis de choisir `difficulty_target` (evidence_path + résumé).
9. **proof_of_use** (Critique — `null` tant que non validé) — chemin du reçu signé
   `role_sim.mjs` (comme `mutation_proof.py`) : lié au sha256 du rôle + de la simulation.
10. **tier** (Critique) — `candidate` (déclaré, non prouvé) → `validated` (EXIGE
    `proof_of_use` non nul, bande mesurée dans la bande déclarée).
11. **license** (Critique) — SPDX du contrat lui-même (les pièces LOGIC ont leur propre
    licence, déjà gouvernée par `kb-validate.mjs`).
12. **path** (Critique) — chemin repo-relatif du fichier `.yaml` du rôle lui-même.
13. **out_of_scope** (Important — `aucun` autorisé) — ce que ce rôle NE couvre PAS
    explicitement (ex. « ne couvre pas la coordination multi-poursuivants »).

## Garde-fous

- `role_sim.mjs` REFUSE tout rôle avec un champ Critique absent (pas juste vide).
- `tier: validated` sans `proof_of_use` non-null = contrat invalide (même garde que
  `is_clean_pass()` côté Forge — un seul prédicat de promotion, jamais une déduction).
- La bande mesurée est rapportée TELLE QUELLE, y compris si elle sort de
  `difficulty_target` — jamais arrondie/édulcorée pour « faire passer » le rôle.

```
claim_verdict: NO_CLAIM_ALLOWED (ce schéma ne certifie rien par lui-même)
```

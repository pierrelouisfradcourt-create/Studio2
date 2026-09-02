# Lot C.4-code — la Forge devient incapable de déclarer un jeu complet sans boucles fermées

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. TDD, fixtures réelles (run 10h en
> observation : `lab/forge_runs/kitten_clicker/{gm_worldscan.json, design_questions.json, art_bible.md}` — NE PAS les modifier ;
> les copier en fixtures). Jamais de commit par un sous-agent ; un commit de clôture (gate Pierre). **Aucune mécanique nouvelle,
> aucune station, aucune architecture nouvelle.** Objectif : R1/R2 de C.4 deviennent des invariants mécaniques.

*Date : 2026-08-24 · Source : ratification C.4 V1.1 (Pierre) + verrou : « le prochain lot ne doit pas essayer de faire passer
Kitten Clicker ; il doit rendre la Forge incapable de déclarer un jeu complet lorsqu'elle n'a pas fermé les boucles ».*

## Vocabulaire figé (C.3/C.4)
- 9 boucles GM : `core_loop, gameplay_loop, progression_loop, content_loop, economy_loop, skill_loop, world_loop, quest_loop,
  meta_loop` (la 10ᵉ, ART↔GM, EST le canal design_questions ; `player_loop` de l'ancien schéma est ABSORBÉ par `gameplay_loop`).
- Champs de boucle (schéma) : les étapes existantes (kind/actor/why/metric_ref/proof_ref) + **par boucle** : `produces` (string),
  `consumes` (liste de noms de boucles), `unlocks` (liste de noms de boucles = NEXT_LOOP), `transformation_perceptible`
  (texte non vide + `proof_ref` dont le how ∈ player_loop|hud|decision|registry — jamais humangate seul),
  `metric_propre` (id de `progression_metrics` utilisé par AUCUNE autre boucle — exclusivité validée).
- `design_questions.questions[].loop_id` ∈ les 9 boucles + `art_gm` — OBLIGATOIRE ; une question sans boucle est refusée.
- `design_state.loops` : par boucle → `COMPLETE | OPEN(n) | PROPOSED | DEFERRED` ; `shared_design_pct` = COMPLETE / 9.
- `COMPLETE` (calculé, jamais déclaré) = boucle présente ∧ R2a (son `produces` apparaît dans le `consumes` d'≥ 1 autre boucle ∧
  ses `unlocks` existent) ∧ R2b (`transformation_perceptible` + proof_ref valide) ∧ `metric_propre` exclusif ∧ 0 question ouverte
  portant son `loop_id`.
- `DEFERRED` = UNIQUEMENT via `design/deferred_loops.json` (fichier HUMAIN, jamais écrit par un agent ni par le driver ;
  l'orchestrateur le crée en matérialisant la ratification écrite de Pierre 2026-08-24 : phase 1 = `core_loop`, `gameplay_loop`
  COMPLETE exigées — décision 1 incluse dans gameplay —, les 7 autres DEFERRED avec raison et date).
- R1 étendu : `ready_for_freeze` d'un pilier refusé s'il reste une question bloquante NON FERMÉE qu'il a REÇUE **ou ÉMISE**.
- R3-lite (« la réponse modifie la boucle ») : pour chaque boucle ayant reçu une réponse à une question bloquante, le contenu
  sérialisé de cette boucle dans `gm_worldscan.json` doit DIFFÉRER de la ronde précédente (archives `artifacts/*-r1.*`) —
  sinon la gate refuse en nommant les boucles (« réponse sans modification = théâtre de questions »).
- `heritage/` écrit DÈS `design_freeze` passé (art_bible.md, gm_worldscan.json, design_questions.json, manifest) ; l'écriture
  post-s9 existante s'y AJOUTE (art_response) au lieu de conditionner le tout à `project.godot`.
- Gate `design_freeze` : toutes boucles `COMPLETE` ou `DEFERRED` ∧ R1 des deux piliers ∧ R3-lite ∧ 0 blocking — sinon HALTED
  « design non convergé » avec l'état PAR BOUCLE.

## Répartition
- **Agent A** (`game_master_schema.mjs` + `run_real.py` + contrats s2.5/s2.7 + tests) : schéma 9 boucles + nouveaux champs +
  exclusivité `metric_propre` + `loop_id` obligatoire dans design_questions + R1 étendu dans `_validate_design_questions` ;
  contrats : protocole C.4 par boucle (GM propose avec trous = questions ; ART vérifie représentation ; réponses qui RÉÉCRIVENT
  la boucle), squelettes mis à jour (loop_id dans l'exemple JSON). Fixtures : gm du run 10h (valide aujourd'hui) → doit être
  REFUSÉ par le nouveau schéma avec des raisons nommées (boucles manquantes, metric_propre absents) — c'est le but du lot.
- **Agent B** (`driver.py` + tests) : `design_state.loops` calculé (COMPLETE/OPEN/PROPOSED/DEFERRED, lecture de
  `design/deferred_loops.json`) ; R3-lite (comparaison sérialisée par boucle vs archive r1) ; gate `design_freeze` réécrite sur
  ces règles (HALTED avec état par boucle) ; `heritage/` au freeze (+ ajout art_response post-s9) ; reçus dans state.
- **Fable** : plan, `design/deferred_loops.json` (ratification Pierre matérialisée), `tasks.json` (protocole par boucle, viser
  core+gameplay COMPLETE), confrontation, commit, relance `kitten_clicker-20260824e`, Monitor, rapport.

## Critère de réussite du lot (fidèle au verrou)
Le `gm_worldscan.json` du run 10h — aujourd'hui « valide » — est REFUSÉ par le nouveau schéma ; un design qui ne ferme pas
core+gameplay au sens R2 ne peut plus atteindre s1 ; et un design honnêtement partiel (7 boucles DEFERRED par Pierre) PASSE.

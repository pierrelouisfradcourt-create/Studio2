# ADR-003 — Audit cohérence/efficacité du workflow Forge (agents · étapes · skill)

- **Date** : 2026-08-15
- **Statut** : PROPOSED — aucune décision ratifiée, tout passe par HumanGate (Pierre)
- **Source** : session Fable 5 (poste de commande), audit multi-agents 2 passes —
  7 lecteurs de zone (Sonnet/Opus) + 7 vérificateurs adversariaux (Sonnet), ~2,5 M tokens sous-agents.
  Chaque finding retenu ci-dessous a été **reproduit indépendamment** par un vérificateur
  (fichier:ligne ou commande ré-exécutée). Les claims réfutés sont listés en §7 — ils comptent autant.
- **Périmètre** : `.claude/skills/forge/SKILL.md` · `scripts/forge/` (dispatch, driver, run_real,
  contrats, oracles, chaîne décision V2, rôles) · preuves d'usage `lab/forge_runs/`, `lab/forge_evidence/`,
  `lab/reports/`. Lecture seule, working tree courant (non commité inclus).

Classes (doctrine 2026-08-03) : A=boucle cassée · B=prévu non construit · C=construit non câblé ·
D=mal câblé · D'=bloqué (prédicat jamais vrai) · D''=erreur d'usage · E=décision Pierre.

---

## 1. Diagnostic central — le skill n'est plus le chemin d'exécution, mais il ne le dit pas

Le chemin canonique d'un run réel est **`forge.run_real` → `ForgeDriver`** (seul appelant de
production : `run_real.py:2100` ; runs réels jusqu'au 2026-08-15). Or `SKILL.md` (386 lignes) consacre
**36 % de son volume (l.92-231)** à faire dérouler à la main, par la session orchestratrice, une boucle
que `driver.py` encapsule déjà — son docstring dit littéralement « Remplace la prose d'orchestration de
`.claude/skills/forge/skill.md` par un artefact EXÉCUTABLE ». Le skill ne cite ni `driver.py` ni
`run_real.py` dans « Le socle », et n'a pas bougé depuis le 2026-08-03 pendant que le driver évoluait
jusqu'à aujourd'hui.

Ce n'est pas que de la duplication : le chemin manuel du skill est **cassé en trois endroits**, prouvés :

| # | Défaut (classe, sévérité) | Preuve |
|---|---|---|
| 1.1 | **Re-tentative interdite dès la 2ᵉ** (D, **P0**) : le marqueur prescrit (`FORGE_DISPATCH:<etape>:<run_id>`, sans `attempt`, aussi collé par `contract.py:475`) fait refuser tout re-spawn par `hook_guard.check_spawn` dès ≥2 `spawn_prepared` pour le couple. Ajouter le marqueur 4 champs ne sauve rien : la regex prend la 1ʳᵉ occurrence. | `check_spawn` exécuté → refus « 7 dispatches pour cette clé » ; 111/394 couples de l'audit ont ≥2 prepared |
| 1.2 | **Recette de verdict qui désarme `verify_run`** (D, **P0**) : `verify_run.py:96-100` infère la « game-ness » des clés `e2e`/`mutation`/`solvability` du reçu code ; la recette du skill (l.217-219) ne met que `{"returncode"}` → un verdict de JEU sort AUTHENTIQUE sans qu'aucune preuve mutation n'ait été vérifiée. | lecture croisée verify_run/skill, confirmée |
| 1.3 | **Prédicats faux** (D'') : `etape ∈ DETERMINISTIC` est faux pour `s10s-oracle-standard` (il faut `is_deterministic_step`) ; itérer `ORDER` n'est juste que pour le profil `full` (15 profils existent, 7 documentés) ; « outils = `payload.allowed_tools` » ne borne rien (ce champ contient `skill`/`plugin` — de la prose pour s4-archi) — le bornage réel (`_STEP_TOOLS`/`_derive_disallowed`) ne vit que dans `run_real.py`. | exécutions directes confirmées |

À l'inverse, le chemin driver est plus complet sur presque tous les axes (state.json/reprise,
RETURN_REASON, télémétrie, repair, reçu mutation signé, verify_run rejoué) **sauf un** : l'oracle
charter R7 — le skill le gate, le driver stocke le reçu `yaml_check` (driver.py:1092-1094) **que
personne ne lit** (D', P1). Et deux mécanismes restent propres au chemin interactif : le spawn de
vrais sous-agents via l'outil Agent (inaccessible à un sous-processus), et les connecteurs
`propose_ledger_entry`/`propose_project_record` (aucun appel dans driver.py).

**Proposition A (la structurelle)** — réécrire `SKILL.md` en trois blocs :
1. doctrine + invariants (inchangés) ;
2. **chemin unique d'un run réel** : `PYTHONPATH=scripts .venv312/Scripts/python.exe -m forge.run_real --project <p> --profile <prof>` + lecture de `state.json`/`humangate_notes`/`verify_run` ;
3. points d'intervention humaine (cadrage s0, gates, HumanGate).
La boucle manuelle survivante part en appendice marqué « chemin de secours, non couvert par les gardes
du driver » — après correction 1.1/1.2/1.3 — ou est supprimée (décision E).
Compléments mécaniques : porter `attempt` dans le marqueur à sa source (`contract._render_prompt`,
l'info existe déjà dans `prepare_dispatch`) ; extraire `_STEP_TOOLS`/`_derive_disallowed` vers un
module partagé `forge.step_tools` ; faire lire `yaml_check` par `_run_llm` (échec rejouable ou
`humangate_flag`) ; signer un champ `is_game` explicite dans le verdict au lieu de l'inférer.

## 2. La couche « preuve produit » est décorative au sommet (étapes/oracles)

| # | Défaut (classe, sévérité) | Preuve |
|---|---|---|
| 2.1 | **`observable_coverage` calculé puis jeté** (A, **P0**) : `_CORE_FACETS` (driver.py:2406) ne l'inclut pas → breakout_v2 : `observable_coverage.verdict=BLOCKED`, 3 volets rouges, et pourtant s10s=OK, s10a=OK, **verdict signé OK / HUMANGATE_READY**. | state.json + verdict.json relus |
| 2.2 | **Rouges fabriqués sur les volets pixel** (D, **P0**) : `product_oracle_godot.py:357` route `--headless` sauf directive `forge:run_mode = gpu_window` ; breakout_v2 ne la déclare qu'en **commentaire** (0 fichier sur 23 ne la porte ; seuls bomberman_3d ×2 et snake ×1 dans tout `games/`) → 3 FAIL « fenetre GPU requise ». Cas d'école « aucune décision dans un commentaire » (ratifié 2026-07-23). | grep + reçus relus |
| 2.3 | **12/23 oracles `.gd` de breakout_v2 sans exécuteur** (C, P1) : ni marqueur `FORGE_ORACLE` (filtre unique du collecteur, product_oracle_godot.py:178) ni énumérés par `run_tests.gd` (qui ne lit que `07_TESTS/unit`). Idem tetris, bomberman_3d ; **pacman fait juste** (run_tests.gd:114-115, deux dossiers). | comptages reproduits |
| 2.4 | Pacman : fournisseur d'oracle produit **structurellement inactivable** (D', P1) — 0/104 `.gd` marqués + `proof:` absent du contrat → prédicat driver.py:1789 jamais vrai, raison écrite dans un reçu que rien ne lit. | vérifié (3 jeux portent une trace d'activation, pas 2) |

**Proposition B** — remonter la preuve produit dans le verdict : (E, Pierre tranche) soit
`observable_coverage` entre dans `_CORE_FACETS`, soit il devient une **OBJECTION signée**
(`DECISION_READY_OBJECTION` existe déjà, verdict.py:203) — le statu quo (calculé, stocké, ignoré) est
le pire des trois. Mécaniques : volet qui REFUSE un `.gd` mentionnant « fenetre GPU » en prose sans la
directive structurée ; volet `check_oracle_files_have_an_executor` (diff entre `07_TESTS/oracle/*.gd`
et l'union marqués ∪ énumérés) ; ajout des directives manquantes dans breakout_v2/pacman = écriture
sous `games/**` → gate Pierre.

## 3. La boucle d'apprentissage écrit ce qu'elle ne peut pas relire

| # | Défaut (classe, sévérité) | Preuve |
|---|---|---|
| 3.1 | **Leçons jamais injectées** (D, **P0**) : `format_premortem_lessons` trie par `lesson_id` alphabétique et tronque à 5 (learning_memory.py:640-642, `limit` jamais passé par driver.py:1295) → les 6 leçons `manifest-*` du post-mortem Pacman sont aux index 21-26 sur 27 : **aucun run ne les verra jamais**. | ré-exécuté, index confirmés |
| 3.2 | **Marqueur devenu la règle** (D, P1) : 100 % des 5 leçons injectées portent `GENERATION_DIFFERENTE_A_REEXAMINER` (`genome_generation.yaml` dit 2, 13 leçons disent 3) — capteur mort. | ré-exécuté |
| 3.3 | `learning_curve.jsonl` « dormant 14,6 j » = **faux signal d'auto-audit** (D', P2) : l'écrivain ne se déclenche qu'après un s10a vert, et tous les runs récents sont `oracle_only` (une seule étape s10s). Le selfaudit dit « probablement débranché » — c'est « non déclenché ». | garde driver.py:1617 + state.json relus |
| 3.4 | Maillon failure_event→leçon **sans producteur** (D'', P2) : 7/7 événements avec `lesson` vide, 1 leçon sur 29 porte un `failure_id`. En-tête d'`agent_factory.mjs` qui nie un `--execute` implémenté 470 lignes plus bas. | comptages confirmés |

**Proposition C** — tri par récence (`-ts` puis id — déterministe, ts est un champ écrit) + `limit`
couvrant le corpus + **test « une leçon écrite dans les 7 derniers jours apparaît dans le premortem »** ;
décision Pierre sur `current_generation` (2 vs 3) ; selfaudit : statut `non_declenche` distinct de
`dormant` ; corriger l'en-tête d'agent_factory ; file visible des failure_events sans leçon (ou retirer
les champs sans producteur du schéma).

## 4. Efficacité mesurée (pas d'hypothèses)

- **21 s sur 22,6 s** d'un test driver = sous-processus git non mémoïsés : 41× `git rev-parse HEAD`
  (verdict.py:188, un par signature de reçu) + 12× `git ls-files` (reference_guard.py:166). Reproduit
  à l'identique (41/12) par le vérificateur. → `lru_cache` sur `current_git_head` (HEAD est justement
  l'invariant que le champ scelle) + cache par pathspec. Gain ~19 s/run, ~6 min sur la suite. (D'', P1)
- **L'auto-oracle `forge` est inexécutable** : timeout 300 s en dur (oracle.py:65) vs suite à 1700
  tests qui dépasse 600 s (`test_driver.py` seul : 343-382 s). Tout `forge_gate("forge")` rend un FAIL
  structurel. → champ `timeout_s` déclaratif dans `oracles.json` + découpage de `test_driver.py`
  (assertions de câblage sans run complet). (D', P1)
- **Un HALT perd son coût réel** : `run_real.py:1698-1703` retourne le dict d'échec sans copier
  tokens/coût de `res` → 14/14 lignes HALT à `cost_usd=0.0` même quand l'appel a été facturé (le
  commentaire driver.py:1028 promettant le contraire est faux sur ce chemin). → fusionner les clés
  mesurées dans `failure`. (D, P1)
- **Coût depuis M1 (2026-07-26)** : 301,54 $ / 13,3 M tokens ; **79 % sur 2 étapes**
  (`s9-build-godot-standard` 170,65 $/33 appels/12,9 h ; `s11-redteam-code` 67,85 $). Un plafond
  budget par étape avant le prochain run complet = décision E.
- Ne PAS regrouper s10a/b/c/s10s : coût réel concentré dans s10a, granularité d'escalade = 4 reçus
  signés distincts (vérifié). Contrats : ne pas fusionner non plus — hygiène seulement (§6).

## 5. Rôles, identité, routage (agents)

- **Reçus d'exécution sans identité** (C, P1) : `append_spawn_event` n'écrit que (etape, run_id,
  attempt) — 184 `spawn_executed` avec `model=''`/`capability_role=''`. Le défaut §7.1 « PostToolUse
  matche Task » est CORRIGÉ (matchers Task ET Agent) ; c'est le contenu du reçu qui est vide.
  → élargir `record_execution` (subagent_type, session_id, model_passed), trois états
  valeur/`<ABSENT>`/NOT_MEASURED, jamais `''`.
- **Aucun canal rôle→type d'agent** (C, P1) : `DispatchPayload` n'a pas de champ `agent_type`, 9/9
  spawns mesurés en `general-purpose` ; les 17 personas `.claude/agents/` = taxonomie parallèle
  qu'aucun code Forge ne lit. → champ `agent_type` au contrat (défaut explicite `general-purpose`),
  **mesurer avant de politiser** ; le mapping vers les personas = chantier E séparé.
- **Diversité cognitive : 2 rôles conformes sur 5 familles** (E, P1) : 9 rôles concentrés sur
  `claude-opus-4-8` (prisme, redteam_code, game_forger compris) ; pas d'entrée Gemini ; `reasoning`
  résolu par modèle, pas par rôle. → mécanique immédiate : `reasoning` au niveau rôle + champ
  `doctrine_target:` structuré ; les déplacements de modèle restent conditionnés aux expériences E4/E7.
- **Falsification utile** : `claude-opus-4-8` n'est PAS un ID mort — servi le 2026-08-14 (28 mesures
  `model_used`). C'est un **épinglage sans champ** : décision E (le garder avec `pinned_reason:`, ou
  passer opus-5 après mesure). En revanche l'escalade écrit l'alias nu (`sonnet`/`opus`) →
  `--effort` perdu (résout None) et le tier signé est ambigu ; `asset_producer` résout None/None
  (89 reçus HMAC à modèle vide, le test de garde skippe exactement ce cas) — deux D mécaniques.
- Témoin d'autorité : construit, testé, `mode=off` partout — **conforme à la phase d'observation
  ratifiée 2026-08-14**, mais sans critère de sortie mesurable (9 spawns classifiés à ce jour).
  → poser le seuil en champ structuré, puis `observe` avant `enforce`.
- 2 personas invalides (`economy-designer`, `ui-programmer` : pas de `description:`, `model:
  claude-sonnet-4-6`) — déjà mesuré le 2026-08-09, jamais corrigé. Lane `.claude/` → gate Pierre.

## 6. Îles, files et index

- **Chaîne décision V2** : construite, testée, **exécutée en CLI isolé** (preuves datées 04-07/08 dans
  `lab/forge_evidence/AGENT_FACTORY_V0`, `EXECUTION_PROOF_*`, `MCTS_WORLDSCAN_QWEN`) mais **0 appelant**
  dans driver/run_real/dispatch/skill. `mcts_selector` = aiguillage à une voie (facteur de branchement
  1 sur les 4 root problems — la cause est en AMONT : 1 recette/problème dans `agent_recipes.json`,
  `measurement_method` non défini). `search_usage` : sortie identique pour 4 jeux (journal global non
  filtré par projet) — variance nulle, contraire à la règle ratifiée 2026-07-21. → décision E :
  brancher un point d'entrée unique, ou bandeau NOT_WIRED assumé. Préalable au branchement : ≥2
  recettes exécutables et une métrique mesurable, sinon « MCTS » est une promesse trop forte.
- **pending_review fonctionne, le goulot est humain** : 219/269 à trancher (190 pacman). Les 2
  divergences selfaudit = 2 lignes JSON + `--apply` — **mais `game.collision` demande une décision de
  standard, pas un ACCEPT mécanique**. → mode d'agrégation par `capability_id` dans pending_review
  (trancher 190 lignes une à une n'est pas praticable).
- **RUN_INDEX.md est incomplet** (découvert par réfutation) : `breakout_v2-run3-20260731`
  (profil `standard_godot`, vrai jeu, verdict signé HUMANGATE_READY) **absent de l'index**. Question à
  instruire : combien d'autres runs réels manquent ? + 3 répertoires `driver_smoke_v6_20260808*` pour
  un même run logique (state.json divergents). + documenter la coupure d'époque `spawn_authorized`
  (mesurable seulement depuis 2026-08-07 : 69/77 ≈ 90 % dessus, 0 avant — ne pas relire 69/1346 comme
  un échec de la porte).
- **Test rouge en zone protégée** (E) : `test_full_profile_is_untouched_by_the_standard_addition`
  fige l'ordre d'avant l'inversion Prisme/WorldScan — ratifier l'inversion (MAJ du test, zone
  protégée → gate) ou annuler l'inversion. Un rouge permanent éteint la valeur d'alerte de la suite.
  Corriger aussi le commentaire périmé driver.py:3103-3108 (cite un test renommé, aujourd'hui vert).
- Hygiène contrats (P2/P3) : 30/51 yaml = missions one-shot à plat dans `contracts/` (résolution par
  nom exact — aucune collision réelle, mais migration `missions/` à faire en un lot, ~30 refs doc) ;
  titre SCHEMA.md « 16 champs » vs 17 réels ; test paramétré `validate_contract` sur tout le dossier.

## 7. Claims réfutés ou corrigés par la contre-vérification (à ne pas répéter)

- « Aucun run complet réel en 30 j » — **RÉFUTÉ** : breakout_v2-run3-20260731 existe ; le vrai défaut
  est l'index (§6).
- « 74/114 run_id dispatch-only » — chiffre non reconstructible (asymétrie réelle : 149 dispatch /
  99 execution / 13 return ; 12/52 run_id dispatch-only).
- « 3/4 root problems sans candidat mesurant la métrique » → **2/4**.
- « asset_results.jsonl : 10 lignes » → **89 lignes** (16 `model_id=''`, 73 sans champ).
- « 29/104 run_id instrumentés (28 %) » → **29/130 (~22 %)**.
- « claude-opus-4-8 périmé » (hypothèse initiale de la mission) — **falsifié**, cf. §5.
- Zone A saine sur les symboles : les 21 API Python citées par le skill existent toutes ; les 3
  contrats orphelins connus le sont toujours ; « 13 en full, 4 en patch » exact.

## 8. Ordre d'exécution proposé (chaque lot = GO Pierre séparé)

| Lot | Contenu | Nature |
|---|---|---|
| 1 | Les 5 P0 : marqueur `attempt` (1.1) · recette verdict → renvoi driver + `is_game` signé (1.2) · `observable_coverage` gate/objection (2.1, choix E) · directive `gpu_window` en champ vérifié (2.2) · tri premortem par récence + test (3.1) | mécanique + 1 choix E |
| 2 | Réécriture SKILL.md (Proposition A) + prédicats 1.3 + `forge.step_tools` partagé + lecteur `yaml_check` | structurel |
| 3 | Efficacité : cache git · découpage test_driver · `timeout_s` · coût des HALT | mécanique |
| 4 | Identité des spawns + `agent_type` au contrat + `reasoning` par rôle + alias d'escalade + `asset_producer` | mécanique |
| 5 | Décisions E en bloc : génération 2/3 · ordre Prisme/WorldScan (zone protégée) · épinglage opus-4-8 · chaîne V2 (brancher ou NOT_WIRED) · plafond budget s9-godot · sortie de la phase de sondes (6+ fogs DISCOVERED à regrouper en UNE décision) | HumanGate |
| 6 | Hygiène : RUN_INDEX (réconciliation avec lab/forge_runs) · dossiers dupliqués · contrats `missions/` · SCHEMA.md 17 · personas · agrégation pending_review | mécanique + gate ciblées |

## Verdict (architecture-review)

**[GATE PIERRE]** — rien d'irréversible n'a été fait (audit lecture seule) ; les lots 1-4/6 sont
exécutables sur GO, le lot 5 est entièrement décisionnel.

```
software_verdict: OK          # l'audit s'est exécuté ; findings reproduits mécaniquement
evidence_verdict: MECHANICAL_VALIDATION_ONLY
claim_verdict: NO_CLAIM_ALLOWED
```

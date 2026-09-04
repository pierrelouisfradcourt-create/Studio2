<!-- Source : audit parallèle lecture seule du 2026-09-03, session Fable (orchestration + 7 audits délégués), HEAD V2 7e494fd → 3481089 ; déposé dans docs/ le 2026-09-04 sur décision Pierre (GO Lot 5). Aucune ligne modifiée depuis. Les 22 pertes de LOSS_RISKS_FOR_LOT2 ont désormais un propriétaire dans forge/capability_registry.yaml (bloc transport). -->

# AUDIT PARALLÈLE V2 — CAPABILITIES / SKILLS / MODELS

*2026-09-03 · lecture seule · dépôt `C:\Users\Studio-Dev\Desktop\Studio` · aucune écriture, aucun test, aucun appel LLM · source : session Fable (orchestration) + 7 audits délégués (Opus/Sonnet), chaque rapport confronté au dépôt avant intégration.*

## PRELIGHT

| item | valeur |
|---|---|
| dépôt audité | `C:\Users\Studio-Dev\Desktop\Studio` (Studio V2), cwd nommé sur chaque commande |
| HEAD au début de l'audit | `7e494fd` (Lot 0) |
| HEAD à la clôture (16:38 UTC) | **`3481089`** (Lot 1 — GAME_BLUEPRINT v0) + **arbre sale** : Lot 2 v0 non commité (`forge/capability.py`, `forge/capability_registry.yaml`, `forge/tests/test_capability_lot2.py`, `forge/dispatch.py` modifié, sonde `EVIDENCE/runs/lot2_decompose_probe/`, `EVIDENCE/reports/lot2_capability/`) ; à 16:35 UTC un **Lot 3 v0** est apparu (`forge/director.py` 504 l., `forge/tests/test_director_lot3.py`, `forge/blueprint.py` modifié, `EVIDENCE/runs/lot3_director_probe/`), **hors périmètre de cet audit, non lu au-delà de son en-tête** |
| conséquence | une autre session construit pendant l'audit ; `driver.py`, `run_real.py`, `contract.py`, `contracts/`, `escalate.py`, `runtime.py`, `control_plane/` sont **inchangés** entre `7e494fd` et `3481089` (diff vide) — les lignes citées valent pour les deux HEAD ; le Lot 2 v0 est audité tel que lu à 16:26 UTC, non commité ; toute affirmation « 0 appelant » vaut pour l'arbre **hors** `director.py` |
| V1 | `C:\TACTICAL_CHESS_STUDIO` lecture seule, non ouvert sauf le plan `docs/forge/STUDIO_V2_PLAN_CONSTRUCTION_20260903.md` (définition du Lot 2 et des 4 recherches externes) |
| méthode | 6 domaines délégués en parallèle (driver · exécuteur · contrats/registre · baseline · oracles · skills/hooks) ; 4 relances après 529/429 ; 2 sous-rapports supplémentaires (boucle d'apprentissage, voie asset) ; ancres de vérité posées par l'orchestrateur avant lecture des rapports (table des modèles, chaîne d'effort, 4 tables, prompts, assemblage, escalade, pool, hook, adaptateur Qwen) |
| interdits respectés | pas de `CAPABILITY_HARVEST.md`/`CAPABILITY_MAP.md` comme point de départ (relus en fin pour comparaison seulement) ; aucune ligne du dépôt modifiée |

## SOURCE_STATE

```
forge/driver.py        5 777 l.   ForgeDriver : ORDER + profils + _run_llm + oracles + escalade + verdict
forge/run_real.py      4 017 l.   exécuteur claude -p + 4 tables + prompts + matérialiseurs + validateurs + réparation
forge/dispatch.py        722 l.   ORDER (13) · PROFILES (17) · prepare_dispatch (porte, audit HMAC)   [+1 param contracts_dir, non commité]
forge/contract.py        706 l.   17 champs · _render_prompt (13 sections) · resolve_runtime (rôle → modèle)
forge/contracts/         27 contrats + roles.yaml (6 modèles) + SCHEMA.md
control_plane/registry.py 115 l.  premier modèle déclarant le rôle gagne ; reasoning par MODÈLE
forge/escalate.py        105 l.   LADDER (haiku, sonnet, opus) · MAX_ESCALATIONS 2 · alias NUS
forge/runtime.py         161 l.   route_step : forge→oracle · claude-local→claude · lmstudio→qwen | claude-blind
forge/capability.py      453 l.   Lot 2 v0 (NON COMMITÉ) : spec() + invoke_capability()
forge/capability_registry.yaml 235 l.  15 capacités déclarées, 4 invocables v0
EVIDENCE/runs/runm_breakout/     baseline M ter (13/13, verdict signé, verify_run AUTHENTIQUE) — seule preuve DÉMONTRÉE
EVIDENCE/runs/lot2_decompose_probe/  1 convocation réelle `decompose` (opus-4-8, 1,42 $, check_decompo 2 codes K7)
```

## CAPABILITIES_FOUND

Inventaire des capacités RÉELLEMENT exécutables, établi depuis `dispatch.ORDER`/`PROFILES`, les handlers du driver, les tables de `run_real`, `roles.yaml`, et confronté à la baseline. Classement : DÉMONTRÉ = code + appelant réel + trace dans la baseline ou test nommé · PARTIEL = code + appelant, pas de trace · DOCUMENTAIRE = texte seul · INCONNU.

| # | capacité (id contrat) | rôle → modèle / reasoning déclaré | handler / appelant réel | déclencheur | reads (amont injecté) | writes / artefact | validateur | outils effectifs | class. |
|---|---|---|---|---|---|---|---|---|---|
| 1 | contract_author (`s0-contrat`) | contract_author → opus-4-8 / high | `driver._run_llm` → `run_real.claude_executor` | position dans ORDER | contrat + PROJECT BRIEF entier (`run_real.py:3270-3278`) + PROJECT BIBLE si présente + pré-mortem | `charter.yaml` (bloc ```yaml, `_materialize_yaml`) + `artifacts/s0-contrat.txt` | `static_oracles.check_charter` (`yaml_check`, 8/8 champs baseline) | Read | DÉMONTRÉ |
| 2 | worldscan (`s2-worldscan`) | worldscan → haiku-4-5 / low | idem | ORDER (avant s1) | contrat seulement (aucune entrée `_UPSTREAM_BY_STEP`) + pré-mortem | `worldscan.json` (bloc ```json terminal, exécuteur matérialise) | `_validate_worldscan` + `check_worldscan.mjs` via `run_repair_step` (advisory) | Read, WebFetch, WebSearch (dérivés de la prose `permissions`, `run_real.py:373-388`) | DÉMONTRÉ · verrou Q2/R8 |
| 3 | prisme (`s1-prisme`) | prisme → opus-4-8 / high | idem ; panel multi-lentilles seulement si `--charter` (`run_real.py:3959-3985`) | ORDER | s2 + s2.6 + s2.7 + design_questions + design/* | `prisme.json` + `product_snapshot.md` + `loop.json` (projection pure `loop_spec.mjs`, jamais écrite par le LLM) | `_validate_prisme` (+ gm sources) · `check_prisme.mjs` (markdown) · `loop_check` (FAIL advisory en baseline) · repair | Read | DÉMONTRÉ |
| 4 | decompose (`s3-decompo`) | decompose → opus-4-8 / high | idem ; **Lot 2 v0** `invoke_capability` (sonde réelle) | ORDER · convocation | charter + s1 + s2 + s2.6 + s2.7 + art_bible + asset_requests + loop.json (73 % du prompt baseline) | `featuremap.json` | `_validate_featuremap` · repair `s3-decompo` (STATUS ESCALADE en baseline, étape restée OK) · `check_decompo.mjs` (Lot 2, 7 codes K7) | Read (baseline : `tools_used {}`) | DÉMONTRÉ |
| 5 | architect (`s4-archi`) | architect → opus-4-8 / high | `_run_llm` | ORDER | charter + s3 | `blueprint.json` (= ARCHITECTURE_CONTRACT, pas GAME_BLUEPRINT) | `_validate_blueprint` · repair `s4-archi-contract` · `check_blueprint_contract.mjs` · `check_architecture` (s10b) | Read | DÉMONTRÉ |
| 6 | wiremap (`s5-wiremap`) | wiremap → opus-4-8 / high | `_run_llm` + `_freeze_rules` (`driver.py:3023`, s5 exactement) | ORDER | charter + s3 + blueprint + s2.6 + art_bible + asset_requests + loop | `wiremap.json` + `wiremap_frozen.json` | `_validate_wiremap`/`_v2` · `check_wiremap_join` (5 régimes, advisory ; VOID + 9 fantômes en baseline) · repair `s5-wiremap-contract` · `check_wiremap` (s10c) | Read | DÉMONTRÉ |
| 7 | redteam_plan (`s6-redteam-plan`) | redteam_reviewer → qwen2.5-14b (lmstudio, temp 0.2, `lm_adapter.py`) ; repli claude-blind tracé | `_run_llm` → `route_step` → `run_qwen_step` | ORDER | charter + s3 + s4 + s5 | `artifacts/s6-redteam-plan.txt` (texte) | aucun oracle ; `extract_redteam_findings` → 0 finding par construction (défaut connu) | aucun | DÉMONTRÉ (Qwen réel, 0 token mesuré) |
| 8 | builder (`s9-build`) | builder → haiku-4-5 / low ; **escaladable** | `_run_llm` ; rejoué par `_maybe_escalate` (pool 2 → sonnet → opus, cap 2) | ORDER · oracle rouge · `ESCALATE_REQUEST` | blueprint + wiremap (+ pré-mortem, + RETOUR DU MATÉRIALISEUR) | code sous `GAMES/<p>` (agent écrit) + `artifacts/s9-build.txt` | s10a/s10b/s10c après build | Write, Edit, Read, Bash(node:*) ; 20 outils refusés | DÉMONTRÉ (6 tentatives) |
| 9 | redteam_code (`s11-redteam-code`) | redteam_code → opus-4-8 / high | `_run_llm` ; mode indépendant Qwen sous `full_content` seulement | ORDER | wiremap | `artifacts/s11-redteam-code.txt` (14 findings baseline) | `extract_redteam_findings` → `findings_note` → `humangate_flags` | Read (baseline : Bash:1 observé hors allowlist) | DÉMONTRÉ (sur `claude-opus-5` par héritage d'escalade, ESC-1 corrigé depuis) |
| 10 | qa_code (`s10a-oracle-code`) | deterministic → non-llm | `driver._run_code_oracle` (18 volets) | ORDER | `oracles.json`, wiremap, `GAMES/<p>/09_WIREMAP`, `00_CHARTER`, project.godot, brief | reçu mutation signé `evidence/mutation_*.json`, `detail` | lui-même | node / python du driver | DÉMONTRÉ (5 évaluations, 41/41 tués au final) |
| 11 | qa_architecture (`s10b`) | non-llm | inline `check_architecture` (`driver.py:3222-3232`) | ORDER | blueprint.json + src_root | `detail` | lui-même | — | DÉMONTRÉ |
| 12 | qa_wiremap (`s10c`) | non-llm | `_run_wiremap_oracle` ; **`check_feature_set_frozen` bloquant** (`driver.py:4331`) ; `amont_traversal` advisory | ORDER | wiremap + snapshot gelé | `detail` | lui-même | — | DÉMONTRÉ |
| 13 | evidence / verdict (`s12-verdict`) | non-llm | `_run_verdict` → `verdict.py` (HMAC) → `verify_run` | ORDER | tous les `detail` | `verdict.json` signé ; `_propose_bricks` | `verify_run` = AUTHENTIQUE | — | DÉMONTRÉ |
| 14 | game_forger (`s9-build-standard`, `s9-build-godot-standard`) | game_forger → opus-4-8 / high | `_run_llm` (profils standard*) | profil | blueprint + wiremap (+ art_bible, asset_requests, loop, economy, design/* pour godot) | squelette gelé rempli | s10s (11 volets) | Write, Edit, Read, Bash(node:*) ; timeouts 5 400 / 9 000 s | PARTIEL (aucune trace V2) |
| 15 | qa_standard (`s10s-oracle-standard`) | non-llm | `_run_standard_oracle` | profils standard* | 5 entrées requises (`00_CHARTER`, `09_WIREMAP`, `forge/standard/*.yaml`, `01_DESIGN/genre_bible.json`, `07_TESTS/oracle`) | `detail` + propositions capability_gap / bible | lui-même | — | PARTIEL |
| 16 | art_director (`s2.5-artbible`, `-r2`) | art_director → opus-4-8 / high | `_run_llm_gated` → **post-gate `_run_artbible_check`** (`driver.py:2071`, budget partagé, re-spawn) | profils artbible/full_content | charter + s2 + s2.6 + heritage + design/* | `art_bible.md` + `asset_requests.json` **écrits par l'agent** (Write) | `check_artbible.mjs` (importe `asset_request.mjs`, dont l'import `../../knowledge_base/search.mjs` pointe HORS dépôt en V2 — effet non exécuté : UNKNOWN, NOT_MEASURED probable) | Write, Read, Bash(node:*) | PARTIEL |
| 17 | story_bible (`s2.6-story-bible`) | **art_director** (pas de rôle propre) → opus-4-8 / high | `_run_llm` | profils amont_narratif* | charter + s2 | `story_bible.json` | `_validate_story_bible` | Read | PARTIEL |
| 18 | game_master (`s2.7-gm-worldscan`, `-r2`) | game_master → opus-4-8 / high | `_run_llm` + `_record_design_state_best_effort` | profils gm_worldscan/full_content | s2 + s2.6 + art_bible + asset_requests + heritage + design_intent + design/* | `gm_worldscan.json` + `economy.json` (projection pure `game_master_schema.mjs`) + `design_questions.json` | `_validate_gm_worldscan` + `_validate_game_master_block` + `_validate_design_questions` | Read | PARTIEL |
| 19 | micro-redéclaration (`<base>-r<N≥3>`) | modèle du contrat de base | `_run_micro_redeclaration` (`driver.py:1514`, `allow_unprofiled`) hors boucle `run()` | boucle design C2 (`_design_freeze_gate`) | design_questions.json | `artifacts/<etape>.txt` | — | idem base | PARTIEL (11 tests, 0 run) |
| 20 | repair_runtime | Qwen via `repair_step.mjs` (temp 0, max_tokens 400, `FORGE_REPAIR=0`) | `run_real.run_repair_step` (`:3502`) sur s2/s1/s3/s4/s5 | après validateur d'artefact | artefact + finding d'oracle | artefact réparé (champs bornés) | oracle rejoué avant/après ; advisory | — | DÉMONTRÉ (5 reçus `repair` baseline) |
| 21 | porte de spawn | — | `dispatch.prepare_dispatch` + `hook_guard.check_spawn` (count==1) + `pretool_forge_guard.py` (fail-closed sur marqueur) | tout spawn | contrat 17 champs | `dispatch_audit.jsonl` (prepared/authorized/executed, HMAC) | `verify_audit_line` | — | DÉMONTRÉ |
| 22 | boucle d'apprentissage (segment réel) | — | `record_error/fix` → `studio_link.premortem` + `learning_memory.premortem_lessons` → `context["premortem"]` → section PRÉ-MORTEM | chaque étape LLM | `error_journal/html.jsonl` (247), `lessons.jsonl` (42, toutes `candidate`, toutes `GENERATION_DIFFERENTE_A_REEXAMINER`) | prompt (5 leçons max) | — | DÉMONTRÉ (28 prompts persistés) ; segment leçon → KB PASSIF (0 validated, catalog figé 2026-08-06) |
| 23 | run_orchestrator (`orchestrator.yaml`) | run_orchestrator → opus-4-8 / high | spawn par la session (skill /forge) ; en pratique la session lance `run_real.py` | — | — | — | — | PARTIEL (dry-run `plan_chain` testé, aucun spawn réel tracé) |
| 24 | asset_spec_author (`s-asset-spec`) | asset_spec_author → qwen (`qwen_spec.py`, `http://localhost:1234` codé en dur, temp 0, max_tokens 600) | `asset_dispatch.py` **CLI seule** ; 0 référence dans dispatch/driver/run_real | — | demande NL | `<id>.spec.json` | énumérations fermées (7 archétypes ≠ 11 côté `build_asset.py`) | — | PARTIEL (preuve V1 migrée, 0 reçu V2) |
| 25 | asset_producer (`s-asset-produce`) | rôle **non résolu** par le registre (`RoleUnresolved`, test figé) ; Blender 5.1.1 via WSL | `asset_dispatch.run_producer` CLI | — | spec | `.glb` + metadata + generation_report | `asset_geometry/oracle.py` (8 checks déterministes) | Blender | BLOCKED sur ce poste (`blender.config.json` absent) |
| 26 | observer (fin de run) | — | `_trigger_observer_best_effort` → `TOOLS/observer/cli.py` | après s12 | run_dir | rapports observer | — | — | PARTIEL (baseline : `transition INCOMPLETE returncode=2`, avant Lot 0) |
| 27 | **Lot 2 v0 — `invoke_capability`** (non commité) | modèle du contrat (via `resolve_runtime`) | `forge/capability.py:286` ; CLI `python -m forge.capability invoke` | convocation explicite | sections GAME_BLUEPRINT (`reads`) projetées en run_dir | artefact JSON + `blueprint.write_section` (propriétaire mécanique) | `_materialize_artifact` (validateur de production) + oracle déclaré (node) → codes K7 | `_effective_step_tools` | DÉMONTRÉ pour `decompose` (1 sonde) ; 4/15 invocables |

**Hors chaîne (0 appelant dans dispatch/driver/run_real)** : `s10d-oracle-visual` (docs seulement), `redteam-artdirector.yaml`, `s9-build-godot.yaml` (trace figée), `wm1-wiremap-*.yaml` (cités par `GAMES/*/09_WIREMAP`, `RAIL_REGISTER.md`, l'Observer ; aucun profil), `forge_toolsmith` (rôle sans contrat), île V2 gelée (`candidate_selector`, `execution_proof`, registres mutation), `emitter.py` / `consumption.py` / `amendment_log.py` (0 appelant à HEAD ; le `forge/director.py` du Lot 3 non commité les importe tous trois), `kb_proposal` (CLI humaine).

## VALIDATORS_AND_PROBLEM_CODES (addendum à CAPABILITIES_FOUND — audit oracles, confronté)

### Chaîne exacte de `software_verdict` (vérifiée sur `verdict.py` / `verify_run.py` / `driver.py`)

1. `driver._run_verdict` (`driver.py:4674`) collecte 4 reçus signés (code s10a, archi s10b, wiremap s10c, standard s10s ou SKIPPED signé hors profil) via `_receipt` (`driver.py:5038`).
2. `verdict.build_aggregate_verdict` (`verdict.py:463`) re-vérifie chaque reçu (HMAC, `run_id`, `evidence_sha256` relu du disque, `:551-591`) ; provenance rompue ⇒ `BLOCKED` inconditionnel (`:596`).
3. Règle (`verdict.py:614-625`) : `BLOCKED` si un reçu BLOCKED ; sinon `FAIL` si un FAIL ; sinon `OK` seulement si `code.status == OK` et tous ∈ {OK, SKIPPED} ; sinon `BLOCKED`.
4. Signature HMAC-SHA256 du mapping trié, clé `forge/.forge_key` (`verdict.py:23`, `:105-125`).
5. `verify_run` (`verify_run.py:255`) : `hmac_ok`, `evidence_ok`, `mutation_integrity_ok` (dur), `coherence_problems` (dur) ; `knowledge_trace_ok` et `context_manifest` **advisory** depuis N-2 (2026-09-02, `:355-376`).
6. `driver.py:4722-4752` : toute divergence ⇒ s12 BLOCKED.

**Ce que `software_verdict` ne voit jamais** (advisory pur) : red-team (s6, s11), panel Prisme, `check_reuse_ratio_wired`, `check_search_consulted`, `run_product_oracle` / `run_godot_product_oracle` (sauf lecture indirecte par `check_observable_coverage`, qui gate en s10s), `knowledge_trace.mjs`, `check_genre_coverage`, `reference_guard`, réparation Qwen, jointure wiremap, `loop_check`.

### Codes structurés réellement émis (champs, pas texte)

| champ | valeurs | émetteur | consommateur |
|---|---|---|---|
| `status` d'étape | OK / FAIL / BLOCKED / SKIPPED / RUNNING / PENDING | `driver._finish_step`, `TERMINAL_STATUSES` (`driver.py:163`) | agrégation verdict, reprise |
| `verdict` (check_artbible, observable_coverage, genre_coverage, gpu_window) | OK / BLOCKED / FAIL | `.mjs` / `standard_oracles.py` | driver (gate ou advisory selon volet) |
| `_volet_status` | OK / FAIL / NOT_MEASURED | `standard_oracles.py:1431` | `check_observable_coverage` |
| `timed_out` | bool nommé | `oracle.py:96` | `gate.py:67` |
| `software_verdict` / `decision` / `scope` | OK-FAIL-BLOCKED / HUMANGATE_READY(_WITH_OBJECTION)-BLOCKED / FULL-PARTIAL | `verdict.py:423, 637-644, 441` | `is_clean_pass` (égalité stricte), `verify_run` |
| `attestation` / `execution_proof_attestation` | `self` (AUTO_ATTESTED) | `driver.py:3055`, `:4699` | HumanGate — n'entre dans aucun calcul |
| `regime_preuve` | historique / descripteur | `driver.py:4007` | routage s10a |
| `JOIN_REGIMES` | NOT_APPLICABLE / EMPTY_FORM / VOID / PARTIAL / JOINED | `run_real.py:2173` | état persisté, jamais gate |
| `transition` | OK / INCOMPLETE: … | `driver.py:1704-1717` | lecture humaine |
| `RETURN_REASON.status` | DISCOVERED / NOT_DISCOVERED / NOT_TRANSMITTED | `run_real.py:518` | manifest `return` |
| codes K7 (Lot 2 v0) | `DECOMPO_*` (7), `ARCHI_PROBLEM`, `WIREMAP_*` (4), `CAPABILITY_*`, `BLUEPRINT_SECTION_ABSENT`, `SPAWN_REFUSED`, `EXECUTOR_FAILED`, `ARTIFACT_*`, `VALIDATOR_NOT_MEASURED`, `SECTION_WRITE_REFUSED` | `capability.py:58-67`, `_run_validator` | résultat JSON (`problems[]`, producteur nommé) |

**Tout le reste est du texte libre** : `raisons[]` / `violations[]` / `reason` des `check_*`, les messages des `_validate_*` (chaîne vide = OK, sinon phrase), et la seule détection de retry du driver est une correspondance de chaîne (`_is_materialize_refusal_reason`, `driver.py:276`, « non materialisable » ou « design_questions.json »).

### Orphelins et gelés confirmés par grep (0 importateur de production)

`check_prerun.py` · `check_runtime_truth.py` · `check_playtest_report.py` · `pair_preflight.py` · `runtime_inventory_oracle.py` (cité en commentaire seulement) · `skipped_validation.py` (cité par `contract.py` en commentaire, importé par `consumption.py`, lui-même orphelin jusqu'au `forge/director.py` naissant) · `consumption.py` · `static_oracles.check_gm_worldscan` et `check_story_bible` (cités en docstring dans `run_real.py:2068, 2100`, jamais appelés : les validateurs réels sont `_validate_gm_worldscan` / `_validate_story_bible`) · `product_oracle_godot.run_divergence_oracle` (correspond à `DIVERGENCE_ORACLE_V1` non tracké) · `repair_runtime_adapter.mjs` (l'entrée reste `repair_step.mjs`) · `prisme/check_gameplay_review.mjs` · `wiremap_nav.mjs` · `search_usage.mjs` côté studio · île V2 (`candidate_selector`, `execution_binding`, `execution_proof`, `mcts_selector`, `agent_factory`) · `templates/solvability.template.mjs` (modèle à copier) · `solvability_budget_audit.py` (dupliqué en JS dans `studio_selfaudit.mjs`).

### Contexte qu'un validateur exige (à emporter avec la capacité)

| famille | dépendances réelles |
|---|---|
| validateurs d'artefact `run_real._validate_*` | Python seul + `run_dir` ; `_validate_prisme` lit `gm_worldscan.json` s'il existe ; `_validate_gm_worldscan` spawn `node game_master_schema.mjs` (60 s) et lit `worldscan.json`, `story_bible.json`, `art_bible.md` ; `_validate_design_questions` lit les 3 artefacts + le `design_questions.json` précédent |
| réparation / jointure | `node`, artefacts amont du run_dir, `FORGE_REPAIR_URL` (LM Studio :1234), 180 s |
| oracles statiques Python | `run_dir/*.json`, `GAMES/<p>/00_CHARTER/game_contract.yaml`, `09_WIREMAP/wiremap.json`, `forge/standard/*.yaml`, `knowledge_base/catalog.json`, `EVIDENCE/briefs/<p>/project_brief.yaml` |
| s10a (code) | commande `oracles.json` du projet (node / godot via `godot_oracle.mjs`), `test_argv` de mutation, `06_RUNTIME`/`05_SYSTEMS`/`07_TESTS` pour le product oracle web, binaire Godot + `proof:` pour Godot |
| s12 | `forge/.forge_key`, `git` (git_head), `run_dir/verdict.json` |
| check_artbible / art_response / amont_traversal | `node`, `run_dir` (+ `game_dir`), `art_bible.md`, `asset_requests.json` ; `asset_request.mjs:15` importe hors dépôt (UNKNOWN) |

## CAPABILITY_MATRIX

Légende par champ : **PROUVÉ** = porté par un mécanisme exécuté (code + appelant + trace ou test nommé) · **PARTIEL** = porté en prose, ou par un mécanisme sans trace, ou seulement dans le Lot 2 v0 non commité · **ABSENT** = aucun mécanisme · **UNKNOWN**.

Rappel des porteurs réels de chaque champ (source de vérité) :
- mission → `contract.objectif` rendu en section OBJECTIF (`contract.py:600`) ; skill → 13 sections de contrat + `default_task_by_step` + RESTITUTION_RULE ; **aucun skill.md n'est transporté** ;
- reasoning_policy / model_policy → `roles.yaml` via `capability_role` (`contract.py:665`, `registry.py:36-41`) + `--effort` par modèle (`run_real.py:766`) ;
- reads → `_UPSTREAM_BY_STEP` (`run_real.py:2928`) · Lot 2 : `capability_registry.yaml` `reads[]` ;
- writes → « l'exécuteur matérialise » (`_materialize_artifact`) · agent écrit seulement s9*/s2.5 · Lot 2 : `blueprint.write_section` ;
- artifact → `_ARTIFACT_BY_STEP` + `_YAML_BY_STEP` + `_MARKDOWN_BY_STEP` ;
- validator → `_ARTIFACT_VALIDATORS` (texte libre) + `check_*.mjs` (repair/join, advisory) + oracles s10* (reçus) ;
- tools → `_STEP_TOOLS` / prose `permissions` (`run_real.py:389`) ;
- escalation → `escalate.py` + `driver._maybe_escalate` (builder seul) ;
- problem_codes → **texte libre en production** (`_is_materialize_refusal_reason` = correspondance de chaîne) ; statuts structurés côté oracles (`NOT_MEASURED`, `regime_preuve`, `attestation`, `transition`) ; codes K7 seulement dans le Lot 2 v0.

| capacité | mission | skill existant | reasoning_policy | model_policy | reads | writes | artifact | validator | tools | escalation | problem_codes |
|---|---|---|---|---|---|---|---|---|---|---|---|
| contract_author (s0) | PROUVÉ | PARTIEL (contrat + tâche « texte seul » alors que l'exécuteur attend un bloc yaml) | PROUVÉ (high transmis) / mesure ABSENT | PROUVÉ opus-4-8 | PROUVÉ (brief entier + bible) | PROUVÉ (exécuteur, `_materialize_yaml`) | PROUVÉ `charter.yaml` | PROUVÉ `check_charter` (8/8) | PROUVÉ Read | ABSENT (aucun) | ABSENT (texte) |
| worldscan (s2) | PROUVÉ | PARTIEL (méthode = tâche : ≥2 jeux, ≥3 sources, schéma) ; `skill: world-scan` déclaré **non transporté** | PROUVÉ (low) | PROUVÉ haiku-4-5 | PARTIEL (contrat seul, 0 amont) | PROUVÉ (exécuteur) | PROUVÉ `worldscan.json` | PROUVÉ `_validate_worldscan` + repair `check_worldscan` (advisory) | PROUVÉ Read/WebFetch/WebSearch (dérivés de prose) | ABSENT | ABSENT (texte) ; verrou Q2/R8 |
| prisme (s1) | PROUVÉ | PARTIEL (3 angles en tâche) | PROUVÉ (high) | PROUVÉ opus-4-8 | PROUVÉ (6 amonts) | PROUVÉ (exécuteur ; `loop.json` projection pure) | PROUVÉ `prisme.json` + `product_snapshot.md` + `loop.json` | PROUVÉ `_validate_prisme` + `check_prisme.mjs` + `loop_check` (FAIL advisory) | PROUVÉ Read | ABSENT | ABSENT (texte) |
| decompose (s3) | PROUVÉ | PARTIEL | PROUVÉ (high) | PROUVÉ opus-4-8 | PROUVÉ (8 amonts) ; Lot 2 : 4 sections Blueprint | PROUVÉ (exécuteur) ; Lot 2 : `write_section` PROUVÉ (sonde) | PROUVÉ `featuremap.json` | PROUVÉ `_validate_featuremap` + repair ; Lot 2 : `check_decompo.mjs` | PROUVÉ Read (mesuré `{}`) | ABSENT | PARTIEL (7 codes K7 déclarés Lot 2, non commité) |
| architect (s4) | PROUVÉ | PARTIEL (schéma `{modules, deps_interdites}` en tâche) ; `skill: architecture-review` **non transporté** | PROUVÉ (high) | PROUVÉ opus-4-8 | PROUVÉ (charter + s3) | PROUVÉ (exécuteur) | PROUVÉ `blueprint.json` | PROUVÉ `_validate_blueprint` + repair `s4-archi-contract` + s10b | PROUVÉ Read | ABSENT | PARTIEL (1 code K7 Lot 2) |
| wiremap (s5) | PROUVÉ | PARTIEL (schéma v1 en tâche ; v2/`couvre` non offert par la tâche) | PROUVÉ (high) | PROUVÉ opus-4-8 | PROUVÉ (7 amonts) | PROUVÉ (exécuteur + `_freeze_rules`) | PROUVÉ `wiremap.json` + `wiremap_frozen.json` | PROUVÉ `_validate_wiremap(_v2)` + jointure 5 régimes (advisory) + repair + s10c | PROUVÉ Read | ABSENT | PARTIEL (régimes de jointure structurés ; 3 codes K7 Lot 2) |
| redteam_plan (s6) | PROUVÉ | PARTIEL (findings seulement) | ABSENT (Qwen, temp 0.2) | PROUVÉ qwen + repli claude-blind tracé | PROUVÉ (4 amonts) | PROUVÉ (texte) | PROUVÉ `artifacts/s6-redteam-plan.txt` | ABSENT (0 finding par construction) | PROUVÉ aucun | ABSENT (hors échelle) | ABSENT |
| builder (s9) | PROUVÉ | PARTIEL (tâche profile-aware ; interdit de commit ; 34 contrats exigent `next_reason`) | PROUVÉ (low) puis **ABSENT après escalade** | PROUVÉ haiku → sonnet → opus (alias nus, version non épinglée) | PROUVÉ (blueprint + wiremap + pré-mortem + retour matérialiseur) | PARTIEL (agent écrit sous `GAMES/`, borné par prompt + deny) | PROUVÉ code + `artifacts/s9-build.txt` | PROUVÉ s10a (18 volets, mutation) + s10b + s10c | PROUVÉ Write/Edit/Read/Bash(node:*) ; 20 refusés | PROUVÉ pool 2 + ladder cap 2 + scope (ESC-1 non rejoué) | PARTIEL (`last_root_cause`, `responsible_level` structurés ; raisons en texte) |
| redteam_code (s11) | PROUVÉ | PARTIEL (lecture seule, 4 clés de finding) | PROUVÉ (high) — baseline : ABSENT (alias `opus`) | PROUVÉ opus-4-8 — baseline : `claude-opus-5` | PROUVÉ (wiremap) | PROUVÉ (texte) | PROUVÉ `artifacts/s11-redteam-code.txt` | PARTIEL (`extract_redteam_findings` → `findings_note`, advisory) | PROUVÉ Read (Bash:1 observé hors allowlist) | ABSENT (ESC-1) | ABSENT |
| qa_code (s10a) | PROUVÉ | PROUVÉ (code déterministe) | n/a | PROUVÉ non-llm | PROUVÉ (oracles.json, wiremap, GAMES/…) | PROUVÉ (`detail`, reçu mutation) | PROUVÉ `evidence/mutation_*.json` | PROUVÉ (lui-même) | PROUVÉ node/python du driver | ABSENT (déclencheur) | PROUVÉ (`NOT_MEASURED`, `regime_preuve`, volets rouges nommés) |
| qa_architecture (s10b) | PROUVÉ | PROUVÉ | n/a | PROUVÉ | PROUVÉ (blueprint + src_root) | PROUVÉ | PROUVÉ `detail` | PROUVÉ | — | ABSENT (déclencheur depuis 2026-08-12) | PROUVÉ (`modules_sans_test`, `deps_interdites_violées`) |
| qa_wiremap (s10c) | PROUVÉ | PROUVÉ | n/a | PROUVÉ | PROUVÉ (wiremap + snapshot gelé) | PROUVÉ | PROUVÉ `detail` + `amont_traversal` | PROUVÉ (`check_feature_set_frozen` bloquant) | — | ABSENT (déclencheur) | PROUVÉ |
| evidence (s12) | PROUVÉ | PROUVÉ (HMAC + verify_run) | n/a | PROUVÉ | PROUVÉ (tous `detail`) | PROUVÉ `verdict.json` | PROUVÉ | PROUVÉ `verify_run` AUTHENTIQUE | — | — | PROUVÉ (`software_verdict`, `humangate_flags`, `attestation`) |
| game_forger (s9-build-standard / -godot-standard) | PROUVÉ | PARTIEL (squelette gelé, constat vs promesse) ; **godot-standard sans tâche par défaut** (UNKNOWN) | PROUVÉ (high) | PROUVÉ opus-4-8 | PROUVÉ (table) | PARTIEL (agent) | PARTIEL | PARTIEL s10s (11 volets) | PROUVÉ (table) | PROUVÉ (dérivé `_builder_step`) — 0 trace | PARTIEL |
| qa_standard (s10s) | PROUVÉ | PROUVÉ | n/a | PROUVÉ | PROUVÉ (5 entrées requises) | PROUVÉ | PARTIEL | PARTIEL | — | ABSENT (déclencheur) | PROUVÉ (structuré) — 0 trace V2 |
| art_director (s2.5, -r2) | PROUVÉ | PARTIEL (procédure v0.1 en tâche + skill `art-bible` **non transporté**) | PROUVÉ (high) | PROUVÉ opus-4-8 | PROUVÉ (10 amonts) | PARTIEL (**agent écrit** `art_bible.md` + `asset_requests.json`) | PARTIEL | PARTIEL (`check_artbible.mjs` ; import `../../knowledge_base/search.mjs` hors dépôt : UNKNOWN) | PROUVÉ Write/Read/Bash(node:*) | ABSENT | PARTIEL (`verdict_structure`, `coverage_status`) |
| story_bible (s2.6) | PROUVÉ | PARTIEL (ancrage, `NOT_GROUNDED`) | PROUVÉ (high) | PROUVÉ opus-4-8 (rôle `art_director`, pas de rôle propre) | PROUVÉ (charter + s2) | PROUVÉ (exécuteur) | PARTIEL `story_bible.json` (0 test, 0 trace) | PARTIEL `_validate_story_bible` | PROUVÉ Read | ABSENT | ABSENT |
| game_master (s2.7, -r2) | PROUVÉ | PARTIEL (8 dimensions, `NOT_MEASURED` avec raison) | PROUVÉ (high) | PROUVÉ opus-4-8 | PROUVÉ (12 amonts) | PROUVÉ (exécuteur ; `economy.json` projection) | PARTIEL | PARTIEL (`_validate_gm_worldscan` + `game_master_schema.mjs` + `_validate_design_questions`) | PROUVÉ Read | ABSENT | PARTIEL (statuts design `COMPLETE/DEFERRED/OPEN/PROPOSED`) |
| micro-redéclaration (-rN) | PARTIEL | PARTIEL | idem base | idem base | PROUVÉ (`design_questions.json`) | PARTIEL | PARTIEL | ABSENT | idem base | ABSENT | PARTIEL |
| repair_runtime | PROUVÉ (`roles.yaml::runtime_contracts`) | PROUVÉ (`repair_loop.mjs`, champs bornés) | ABSENT (temp 0) | PROUVÉ qwen (`FORGE_REPAIR_MODEL`) | PROUVÉ (artefact + finding) | PROUVÉ (artefact réécrit, hash avant/après) | PROUVÉ | PROUVÉ (oracle rejoué ; advisory) | — | ABSENT | PARTIEL (`STATUS: ESCALADE`, `PROBLEMS_BEFORE/AFTER`) |
| run_orchestrator | PROUVÉ (contrat) | PARTIEL | PROUVÉ (high) | PROUVÉ opus-4-8 | PARTIEL | — | — | PARTIEL (`verify_run`) | PARTIEL (`skill: forge` déclaré) | ABSENT | ABSENT |
| asset_spec_author | PROUVÉ | PARTIEL (`qwen_spec.py` : énumérations fermées, 1 réparation) | ABSENT (temp 0) | PROUVÉ qwen (endpoint dupliqué, non pilotable) | PROUVÉ (demande NL) | PROUVÉ (`spec.json`) | PROUVÉ | PROUVÉ (structurel) | — | ABSENT | PARTIEL (rejets nommés) |
| asset_producer | PROUVÉ (`runtime_contracts`) | PROUVÉ (11 archétypes, Blender) | n/a | **ABSENT** (rôle non résolu par le registre) | PROUVÉ (spec) | PROUVÉ (`.glb` + metadata + report) | PROUVÉ | PROUVÉ `asset_geometry/oracle.py` (8 checks) | BLOCKED (Blender non configuré) | ABSENT | PROUVÉ (`BLENDER_EXECUTOR_UNAVAILABLE`, `SPEC_VIOLATES_BATCH_CONSTRAINT`, `VARIANTS_MATCH_GEOMETRY`…) |
| **Lot 2 v0 — `decompose` via `invoke_capability`** | PROUVÉ (dérivé) | PARTIEL (contrat + tâche, **sans pré-mortem**) | PROUVÉ (high) | PROUVÉ opus-4-8 (déclaré ; mesuré **jeté**) | PROUVÉ (4 sections, sha du composite) | PROUVÉ (`write_section` propriétaire) | PROUVÉ `featuremap.json` | PROUVÉ (`_validate_featuremap` + `check_decompo.mjs`) | PROUVÉ Read | PARTIEL (déclaré `aucun`) | PROUVÉ (2 × `DECOMPO_LOOP_NO_ENTRY`, producteur nommé, JSON) |

## SKILLS_FOUND

Question posée : quelle compétence réelle se cache derrière chaque capacité, où vit-elle, et par quel mécanisme atteint-elle l'agent exécutant ?

**Constat central (vérifié trois fois : `contract.py:650-656`, `run_real.py:3298-3306`, `_TOOL_UNIVERSE` sans outil `Skill`)** : le champ `skill:` d'un contrat devient `payload.allowed_tools` (une liste de NOMS), qui ne sert qu'à la ligne d'audit signée. Il n'atteint ni l'argv de `claude -p` ni le prompt. **Aucun skill.md n'est jamais injecté dans un prompt Forge.** La compétence réelle vit à quatre endroits, tous transportés par le prompt :

| porteur réel | contenu | mécanisme de transport | preuve |
|---|---|---|---|
| contrat (13 sections rendues) | rôle, exigences cognitives, mémoire (+ fiches KB citées), objectif, in/out scope, permissions, garde-fou, critères, oracles, contrat de sortie, rapport final, `mandatory_read` (chemins seulement, jamais le contenu) | `contract._render_prompt` (`:572-619`) → `payload.prompt` | 46 premières lignes de chaque prompt persisté |
| tâche par étape (`default_task_by_step`, `run_real.py:3566-3719`) | LA méthode opérationnelle : schéma JSON dicté, seuils (≥2 jeux, ≥3 sources), interdits (aucun fichier, aucun commit), postures (« mesure, pas conception », « ancrage, pas invention », « constat, jamais promesse ») | section TÂCHE CONCRÈTE | prompts baseline + sonde Lot 2 |
| RESTITUTION_RULE (`contract.py:155-188`) | vocabulaire de verdict, SKIPPED_VALIDATION, `RETURN_REASON` JSON | injectée verbatim en fin de prompt | `*.return.manifest.jsonl` (DISCOVERED / NOT_DISCOVERED / NOT_TRANSMITTED observés) |
| contexte amont | `_UPSTREAM_BY_STEP` (73 % du prompt s3), pré-mortem (5 leçons, toutes `GENERATION_DIFFERENTE_A_REEXAMINER`), brief/bible (s0), retour du matérialiseur | `claude_executor` (`run_real.py:3237-3290`) | prompt baseline s3 : charter 5 518 + s1 15 144 + s2 15 150 car. |

Skills `.claude/skills/` (audit délégué, confronté) :

| skill | référencé par contrat | consommé par du code | nature réelle | class. |
|---|---|---|---|---|
| `forge` (387 l.) | `orchestrator.yaml:145` | 25/25 fonctions citées existent et sont appelées ; profils et `--dry-run` exacts ; 3 contrats orphelins listés à raison | pilotage de la session ; affirme à tort (l.116) que `allowed_tools` borne l'exécuteur | DÉMONTRÉ (session), DOCUMENTAIRE pour l'exécuteur |
| `world-scan` | `s2-worldscan.yaml:143` | aucun ; 14 mentions d'IMP-ID, 0 mention de `worldscan.json` | protocole V1 « knowledge packet par IMP » ; **homonyme sans rapport** avec le s2 réel (méthode = tâche `default_task_by_step`) | DOCUMENTAIRE |
| `art-bible`, `asset-spec` | aucun (s2.5 déclare `skill: aucun`) | aucun (`design/`, `.claude/docs/` absents) | skills génériques importés, sans rapport avec s2.5 / s-asset-spec | DOCUMENTAIRE |
| `asset-generator` | `s-asset-produce.yaml:194` | aucun (CLI humaine) | architecture juste, 6 écarts de chemins/énumérations avec le code V2 | DOCUMENTAIRE |
| `verdict`, `gate`, `joust`, `smoke-check`, `fog`, `playtest`, `handoff` | aucun | aucun ; chemins V1 (`scripts/forge/`, `lab/reports/`, `.venv312`, `studio_brain/`) | résidus V1 ; `gate` cite `lab/reports/pending_review_decisions.jsonl` alors que le code lit `EVIDENCE/reports/…` | DOCUMENTAIRE |

Agents `.claude/agents/` (17) : 15 avec `disallowedTools: Write, Edit`, modèles sonnet (14) / haiku (2) / `claude-sonnet-4-6` (2 inertes sans `description`) ; **aucun n'est appelé par la Forge** — disponibles à la session seulement.

Garde-fous réellement actifs sur un spawn (à emporter) :

| # | garde-fou | fichier:ligne | chemin `Agent` (session) | chemin `claude -p` (headless, run_real / capability) |
|---|---|---|---|---|
| 1 | hooks PreToolUse : `Task`/`Agent` → `pretool_forge_guard.py` (+ `pretool_agent_classify.py`) ; `Bash`/`PowerShell` → `pretool_git_guard.py` | `.claude/settings.json:33-74` | oui | **non** (processus séparé) |
| 2 | marqueur `FORGE_DISPATCH` + count==1 de lignes d'audit HMAC (fail-closed en périmètre) | `hook_guard.check_spawn:49-106`, `hook_decision:158` | oui | reproduit par appel direct (`capability.py:329`) ; le driver ne l'appelle pas mais écrit `spawn_authorized/executed` en code |
| 3 | héritage d'autorité (allowlist types d'agents) | `pretool_forge_guard.py:588-606` | **inerte** : `authority_witness.json` absent, `TCS_AUTHORITY_INHERITANCE` non posé ⇒ mode `off` | non |
| 4 | `spawn_authorized` (hook) / `spawn_executed` (PostToolUse) | `pretool_forge_guard.py:676`, `posttool_forge_executed.py` | oui | écrits en code (`driver._record_spawn_executed`, `capability.append_spawn_event`) |
| 5 | allowlist ratifiée + complément refusé + `--strict-mcp-config` + `--permission-mode` + `add_dir` | `run_real.py:808-852` | non | **oui** (seule borne réelle du headless) |
| 6 | deny statique `_STEP_DISALLOWED` (git entier, NotebookEdit, `tests/**`, `.claude/**`, branche de contrôle) | `run_real.py:277-330` | non | oui |

## MODEL_REASONING_MATRIX

**Réponse à la question obligatoire : NON, toutes les capacités ne finissent pas sur le même modèle ni le même reasoning — et l'escalade change les deux sans le dire.**

Chaîne de décision (chaque maillon vérifié) :
1. Le contrat ne porte **aucun** champ `model`/`reasoning` (0/27) ; il déclare `capability_role` (`contract.py:665`).
2. `resolve_runtime` → `registry.get_model_for_role(role, caps_path=roles.yaml)` : **premier modèle déclarant le rôle** (`registry.py:36-41`) ; nom court `id.split("/")[-1]`.
3. `payload.model` → `run_real.claude_executor` : `model = model_override si (override et (scope absent ou scope == etape)) sinon payload.model` (`run_real.py:3334-3336`, ESC-1).
4. `_claude_call_raw` : `--model <model>` ; `--effort` ajouté **seulement** si `get_reasoning_for_model(model)` rend une valeur CLI-compatible (`run_real.py:766-793`, `:838-840`).
5. `escalate.LADDER` écrit des alias **nus** (`haiku`/`sonnet`/`opus`) ; pour eux `get_reasoning_for_model` rend `None` (vérifié mécaniquement) ⇒ **aucun `--effort`** ; le CLI résout l'alias vers `claude-sonnet-5` / `claude-opus-5`, pas vers le `claude-opus-4-8` épinglé.
6. Provider `lmstudio` → `route_step` → Qwen réel (HTTP, temp 0.2) ou repli `claude-blind` tracé (`runtime.py`) ; provider `forge` → oracle.

| capacité / rôle | modèle déclaré (roles.yaml) | reasoning déclaré | `--effort` transmis | modèle OBSERVÉ baseline | reasoning OBSERVÉ | source config | fallback / escalade |
|---|---|---|---|---|---|---|---|
| contract_author, prisme, decompose, architect, wiremap | claude-opus-4-8 | high | `--effort high` | `claude-opus-4-8` (s0, s1, s3, s4, s5) | déclaré seulement — **aucune mesure** (13 fichiers `reasoning_observability` : champ `declared` uniquement) | `roles.yaml:100-138` | aucun (sommet de l'échelle) |
| worldscan | claude-haiku-4-5-20251001 | low | `--effort low` | `claude-haiku-4-5-20251001` (s2) | idem | `roles.yaml:141-148` | **jamais escaladé** (`_builder_step` ne matche que `s9-build*`) |
| builder | claude-haiku-4-5-20251001 | low | `--effort low` (a1, a2) | a1-a2 haiku · a4-a5 **`claude-sonnet-5`** · a6 **`claude-opus-5`** | a1-a2 low ; **a4-a6 : aucun flag** (alias nu) | `roles.yaml` + `escalate.py:19-20` + `driver.py:5401-5402` | pool 2 même tier → ladder sonnet → opus, cap 2 ; `model_override` |
| redteam_code (s11) | claude-opus-4-8 | high | high attendu | **`claude-opus-5`** (override `opus` de portée RUN, `redteam_ran=false`) | aucun flag (alias nu) | idem | ESC-1 (`model_override_scope`, `run_real.py:3334`) corrige en code, **non rejoué en run réel** |
| game_forger, art_director (s2.5 + s2.6), game_master, run_orchestrator | claude-opus-4-8 | high | high | aucune trace V2 | UNKNOWN | `roles.yaml` | aucun |
| redteam_reviewer (s6) | lmstudio/qwen2.5-14b-instruct | false | n/a | `qwen2.5-14b-instruct` réel (runner `qwen`, `qwen_ok: true`, tokens 0 = non mesuré) | n/a (temp 0.2 dans `lm_adapter.py`) | `roles.yaml:169-183` | claude-blind si LM Studio down (motif tracé) |
| repair_runtime | qwen | false | n/a | reçus `repair` sur s2/s1/s3/s4/s5 | temp 0, max_tokens 400 | `roles.yaml::runtime_contracts` | kill switch `FORGE_REPAIR=0` |
| asset_spec_author | qwen | false | n/a | 0 reçu V2 | temp 0 (`qwen_spec.py`, endpoint dupliqué et non pilotable par env) | `roles.yaml:184-197` | 1 réparation puis échec |
| forge_toolsmith | claude-sonnet-5 | high | — | 0 contrat | — | `roles.yaml:159-166` | — |
| deterministic (s10a/b/c/s10s/s12) | non-llm | false | n/a | `non-llm` | n/a | `roles.yaml:255-260` | — |
| orchestrator (la session) | claude-fable-5 | high | — | non résolu par le code (descriptif) | — | `roles.yaml:41-50` | — |

Différences réelles entre capacités : **3 familles de modèles en production** (opus-4-8 × 10 rôles, haiku-4-5 × 2, qwen × 3) et **2 niveaux d'effort transmis** (high, low) ; après escalade un **3e état** apparaît : effort absent + version de modèle non épinglée. Rien ne mesure le reasoning effectivement appliqué (UNKNOWN structurel).

## EXTERNAL_COMPARISON (conceptuel, aucune architecture importée)

| source | primitive | ce que V2 possède déjà (preuve) | ce qui manque réellement |
|---|---|---|---|
| Spec Kit — state / journal / resume | `state.json` atomique, reprise RUNNING/BLOCKED → PENDING, OK/FAIL acquis (`driver.py:1866-1925`) ; `run.log` ; `spawn_links.jsonl` ; audit HMAC ; `RUN_INDEX.md` (append-only, **périmé** : affiche encore le HALT du 2 sept.) | un état **par convocation hors ORDER** : `invoke_capability` v0 ne persiste rien (résultat dict + fichiers) ; aucun journal de décisions du Director (Lot 3) ; reprise « au niveau de l'objet bloquant » (K8) inexistante |
| GameStudio — ownership | déjà **au-delà** : l'exécuteur matérialise (`_materialize_artifact`), l'agent n'écrit rien sauf builder/artbible ; `blueprint.write_section` refuse hors `OWNERS` (`blueprint.py:106-116`, mécanique) ; deny-list complémentaire (`_derive_disallowed`) | l'ownership des **fichiers** du builder sous `GAMES/` n'est bornée que par prompt + contrat (`Bash(node:*)` laisse `node -e` ouvert, limite déclarée `run_real.py`) ; `s2.5-artbible` écrit elle-même ses fichiers (régime différent, non porté par le registre) |
| Summer — skills / bridge / tool economy | économie d'outils réelle : allowlist ratifiée + complément refusé + `--strict-mcp-config` + `--permission-mode` (`run_real.py:838-852`) ; observabilité déclarée (`tool_observability`) et mesurée (`tools_used`) | **aucun pont de skill** : `skill:` de contrat → `payload.allowed_tools` (noms) → jamais dans l'argv ni le prompt (`contract.py:650-656`, `run_real.py:3298-3306`) ; les skill.md ne sont jamais injectés ; la « compétence » vit dans 13 sections de contrat + `default_task_by_step` + RESTITUTION_RULE ; le canal KB (`_render_kb_section`) n'a jamais produit une section dans un prompt réel |
| Vitric — observe / replay / variant / perturbation | verdict HMAC (origine) ; `verify_run` (intégrité) ; mutation gate 41/41 (perturbation du **code**) ; bot de solvabilité ; 5 régimes de jointure ; codes K7 dans `check_decompo.mjs` → `problems[]` JSON (Lot 2) | `verify_run` n'a **aucun mode replay** (grep `replay` = 0) ; aucun certificat `seed + inputs + hash` ; le jeu baseline **se gagne sans joueur** (politique nulle non testée) ; le Blueprint n'a **aucun historique de section** à HEAD (`blueprint.py` : compteur `version`, contenu écrasé ; sous-entrées composites partagent le sha du parent — `blueprint_inputs` de la sonde : 3 shas identiques pour prisme/worldscan/product_snapshot) ; le Lot 3 v0 non commité pose des `snapshots/wiremap.v1.json` dans son run (non audité) |

Ce qui manque à V2 en une phrase : un **transport** (de la méthode vers l'agent, du problème vers le Director, de l'état vers la reprise) — les mécanismes existent aux deux bouts, le milieu est de la prose ou du vide.

## LOSS_RISKS_FOR_LOT2 — confrontation `invoke_capability` v0 (non commité, lu 16:26 UTC) ↔ `_run_llm` + `claude_executor`

Méthode : chaque mécanisme de production (driver `_run_llm` l.2217-2691, exécuteur `claude_executor` l.3208-3551) est cherché dans `forge/capability.py` (grep négatif exhaustif sur `context_manifest | premortem | project_bible | spawn_link | telemetry | _extract_return_reason | return.manifest | next_reason | journal | failure_event | learning | model_override | route_step | run_qwen_step | _timeout_effectif | repair | materialize_feedback | failed` = **0 occurrence**), puis vérifié sur la sonde réelle `lot2_decompose_probe`.

### Emporté par v0 (préservé)

| mécanisme | production | v0 | preuve sonde |
|---|---|---|---|
| porte contractuelle + audit HMAC + marqueur 3 champs | `dispatch.prepare_dispatch` | `capability.py:322-326` | `dispatch_audit.jsonl` : prepared/authorized/executed, `reason={"signal":"convocation","by":"forge.capability"}` |
| contrôle d'unicité du spawn (count==1) | hook `pretool_forge_guard` → `hook_guard.check_spawn` | `capability.py:329` (appel direct, même fonction) | `spawn_allowed: true` |
| prompt de contrat (13 sections + mandatory_read + RESTITUTION_RULE) | `contract._render_prompt` | via `payload.prompt` | 46 premières lignes identiques au prompt baseline |
| méthode de la tâche (`default_task_by_step`) | `run_real.py:3566` | `capability.py:340-342` (import direct) | section TÂCHE CONCRÈTE présente |
| modèle par rôle + `--effort` par modèle + allowlist/deny + `--strict-mcp-config` | `_claude_call_raw` | `_default_executor` → `_claude_call_with_transient_retry` (même argv) | `model: claude-opus-4-8`, `tools_effective_signed ['Read']` |
| retry transitoire ≤ 2 | `_claude_call_with_transient_retry` | idem | — |
| prompt persisté | `_persist_final_prompt` | `capability.py:345` | `context/prompt_s3-decompo_a1.txt` |
| matérialisation + validateur de schéma de production | `_materialize_artifact` (+ `select_artifact_payload`) | `capability.py:365` | `featuremap.json` |
| oracle déterministe déclaré → codes K7 JSON, producteur nommé | (nouveau) | `_run_validator` `capability.py:225-269` | `check_decompo.mjs` exit 1, 2 × `DECOMPO_LOOP_NO_ENTRY` transportés en JSON |
| propriétaire mécanique de la section écrite | (nouveau, au-delà de GameStudio) | `blueprint.write_section` + `_check_owner` (`blueprint.py:106-116,132`) | `feature_map` v1 → v2, `writer: decompose` |
| demande d'escalade de l'agent rendue comme `requests`, jamais comme code | `parse_agent_escalation` | `capability.py:360-362` | `requests: []` |
| observabilité déclarée reasoning/outils (écrite par la porte) | `dispatch.prepare_dispatch` | héritée | `s3-decompo.reasoning_observability.jsonl` (`declared.raw: high`), `tool_observability.jsonl` |
| projections de sections en fichiers pour les oracles legacy | (nouveau) | `_materialize_reads` | `charter.yaml`, `prisme.json`, `worldscan.json`, `product_snapshot.md` écrits dans le run_dir |

### Perdu ou déplacé par v0 (à emporter, ou à assigner explicitement au Director)

| # | mécanisme perdu | où il vit en production | effet mesuré sur la sonde | gravité |
|---|---|---|---|---|
| L1 | **PRÉ-MORTEM** (journal d'erreurs + leçons + flags HumanGate du dernier verdict signé) | `driver._premortem` l.2973 → `context["premortem"]` → `run_real.py:3247-3252` | section absente du prompt sonde (présente l.607 du prompt baseline) | haute : seul canal d'apprentissage démontré |
| L2 | **PROJECT BIBLE + PROJECT BRIEF** (s0) | `driver.py:2371`, `run_real.py:3262-3278` | s0 non invocable v0 ; aucun équivalent Blueprint `identity/vision/constraints` → prompt s0 | haute pour s0 |
| L3 | **retry de matérialisation avec RETOUR DU MATÉRIALISEUR** (3 tentatives, feedback injecté) | `driver.py:2420-2444`, `run_real.py:3281-3288` | v0 rend `ARTIFACT_NOT_MATERIALIZABLE` + `reconvoke` ; la re-convocation reçoit le **même prompt** (rupture 11 mesurée sur run 10c) | haute |
| L4 | **escalade exécutée** (pool même tier, ladder, cap 2, `model_override_scope`, rejeu s9+s10*) | `driver._maybe_escalate` l.5274-5420 | v0 déclare `builder_ladder` mais ne l'exécute pas (builder non invocable) | déplacée au Director, à déclarer |
| L5 | **routage provider** (`route_step` : Qwen réel / claude-blind tracé / oracle) | `driver.py:2298-2345`, `runtime.py` | v0 appelle toujours `claude -p` avec `payload.model` ; une capacité `lmstudio` recevrait `--model qwen2.5-14b-instruct` sur le CLI Claude | haute dès que redteam_plan devient invocable |
| L6 | **timeout par profil/étape** (`PROFILE_STEP_TIMEOUTS_S`, 5 400 / 9 000 s) | `dispatch.py:492-508`, `run_real.py:3176` | v0 : `timeout_s` paramètre, défaut 1 800 s | moyenne (builders) |
| L7 | **Context Manifest kind `execution`** (sha du prompt final, sha pré-mortem, sha brief, outils effectifs) | `run_real.py:3302-3311` | sonde : manifest `['dispatch']` seul ; baseline `['dispatch','execution']` | haute : lignée Intent/Activation coupée |
| L8 | **le manifest `dispatch` mesure encore `_UPSTREAM_BY_STEP`** | `context_manifest` via `prepare_dispatch` | sonde : 8 sources `upstream` `exists:false` alors que le contexte est venu du Blueprint | haute : « mesurer la cible, pas la source » ; l'observabilité ment par construction |
| L9 | **RETURN_REASON → manifest kind `return`** | `run_real.py:3402-3409` | aucun `s3-decompo.return.manifest.jsonl` dans la sonde | moyenne (lignée Return) |
| L10 | **spawn_link** (joint contrat↔prompt↔outils↔modèle↔artefact↔verdict, attestation AUTO_ATTESTED) | `run_real.py:3363`, `driver.py:3064` | absent | haute : invariant preuve=producteur |
| L11 | **modèle MESURÉ** (`model_used`, `session_id`, `tokens_measured`, `tools_used`) | `_capture_stream_metrics` → `stage_telemetry_extra` → `detail` | v0 : `result["model"] = payload.model` (déclaré) ; `model_used` de `res` **jeté** | haute : v0 réintroduit « déclaré ≠ exécuté » |
| L12 | **télémétrie** (`forge_telemetry.jsonl`, outcome OK/HALT, modèle réel) | `driver.py:2670`, `3182` | absente | moyenne |
| L13 | **`next_reason`** (cause durable, consommée par l'escalade et `humangate_notes`) | `driver._parse_next_reason` l.5013 | non extrait | moyenne |
| L14 | **journal d'erreurs / réparation, FailureEvent, promotion de leçons, learning_hook** | `driver.py:2736-2803`, `3251`, `588-731` | rien n'apprend d'une convocation | haute (boucle fermée seulement côté driver) |
| L15 | **sortie brute persistée** (`artifacts/<etape>.txt`, `.failed-N.txt`, `output_excerpt`) | `driver.py:2405-2412`, `2492-2510` | v0 ne conserve que le JSON matérialisé ; RAPPORT FINAL / SKIPPED_VALIDATION perdus | moyenne |
| L16 | **réparation Qwen** (5 étapes), **jointure** (s5), matérialiseurs annexes (`product_snapshot.md`, `loop.json`, `charter.yaml`, `economy.json`, `design_questions.json`) | `run_real.py:3432-3522` | v0 n'appelle que `_materialize_artifact` ; d'où 11 capacités « non invocables v0 » | haute pour prisme / s0 / GM |
| L17 | **diagnostic d'échec** (`process_state`, `stderr_tail`, `returncode`, `timeout`, `salvage`) | `driver._halt_step` + `_executor_diagnostic` l.3103 | v0 : `EXECUTOR_FAILED` + chaîne `reason` | moyenne |
| L18 | **coût cumulé multi-tentatives** + `spawn_links` RETRY/HALTED | `driver.py:2231, 2484` | v0 : coût de la tentative seule | faible |
| L19 | **gel des règles** (s5 → `wiremap_frozen.json`, opposable en s10c), **gate design freeze**, **post-gate artbible** | `driver.py:3023, 1309, 2071` | hors v0 (capacités non invocables) | déplacée, à nommer |
| L20 | **`add_dir`** = `src_root` (racine du jeu) en production | `run_real.py:3956` | v0 : `add_dir=run_dir` | neutre pour Read seul, bloquant pour un builder |
| L21 | **état persistant / reprise** | `driver._load_state` l.1866 | v0 : aucun état, résultat dict + fichiers | déplacée au Director (Lot 3) |
| L22 | **provenance des sous-entrées** | (nouveau défaut) | `blueprint_inputs` : prisme, worldscan, product_snapshot portent le **même sha** (celui du composite `understanding`) | moyenne : une section lue n'est pas identifiable à la sous-entrée près |

### Réponse à la question critère

« Si demain on extrait cette capacité hors de `ForgeDriver`, qu'est-ce qu'il faut emporter avec elle pour qu'elle reste la même compétence ? »

1. **Le prompt complet, pas le contrat seul** : contrat (13 sections) + tâche (`default_task_by_step`) + RESTITUTION_RULE + **pré-mortem** + (s0) brief/bible + **retour du matérialiseur** à la re-convocation. v0 en emporte 3 sur 6.
2. **Le modèle ET son effort ET son provider** : `capability_role → roles.yaml → --model/--effort` (préservé), **plus** `route_step` pour `lmstudio`/`forge` (perdu), plus la règle « alias nu = effort absent » à corriger avant toute escalade hors driver.
3. **Les trois lignées de preuve** : audit signé (préservé), **execution manifest + spawn_link + modèle mesuré** (perdus), RETURN_REASON (perdu).
4. **La politique de tentative** : retry de matérialisation avec feedback, retry transitoire (préservé), pool/escalade (Director). Chacune doit avoir un propriétaire nommé.
5. **Les validateurs de production ET les annexes** : `_materialize_artifact` (préservé) ; réparation Qwen, jointure, checkers markdown/yaml/loop/economy/design_questions (perdus). Sinon prisme, s0, GM restent hors Blueprint.
6. **Les consommateurs des reçus** : ce que `run_real` produit dans `res` (23 clés) n'existe que si quelqu'un le persiste ; v0 en garde 5 (`ok`, `reason`, `tokens`, `duration_s`, `cost_usd`).
7. **Les garde-fous d'exécution** : allowlist ratifiée + complément refusé + `--strict-mcp-config` + `add_dir` correct (préservés sauf `add_dir`) ; hook PreToolUse (préservé par `check_spawn` direct, chemin B headless seulement).
8. **Le contexte d'observabilité juste** : le manifest ne doit plus mesurer `_UPSTREAM_BY_STEP` quand le contexte vient du Blueprint (L8).

## UNKNOWN

- **Reasoning réellement appliqué** par le modèle : aucun champ mesuré nulle part (13 fichiers `reasoning_observability` = `declared` seul) ; seul le flag `--effort` transmis est connu.
- **Effet de l'import cassé** `forge/asset_request.mjs:15` (`../../knowledge_base/search.mjs` hors dépôt) sur `check_artbible.mjs` et la gate s2.5 : chemin mesuré inexistant, effet non exécuté (`node` interdit).
- **Profils jamais tracés en V2** : `standard*`, `full_godot*`, `full_content`, `proof_only`, `oracle_only`, `amont_*`, `artbible`, `gm_worldscan`, `story_bible` — classés PARTIEL sur code + tests.
- **`model_override_scope` (ESC-1)** en run réel : code + 7 tests, 0 run.
- **Tentative 3 de s9-build** : `spawn_prepared` seul, prompt persisté, 0 coût ; cause narrative (lanceur tué à 60 min) non re-vérifiable mécaniquement.
- **Consommateur réel de `wm1-wiremap-*.yaml`** : cités par `GAMES/*/09_WIREMAP/wiremap.json`, `GAMES/RAIL_REGISTER.md` et l'Observer ; aucun profil, aucun appel `prepare_dispatch` trouvé.
- **`s10d-oracle-visual`** : contrat + 2 docs de proposition/adjudication ; absent de `dispatch.py` ; raison non tranchée dans le code.
- **Ordre réel des sections composites** : `blueprint_inputs` porte le sha du composite, pas de la sous-entrée.
- **Résultat des tests** : aucun `pytest` lancé (interdit) ; les tests sont cités comme existence d'un exercice nommé, jamais comme un vert constaté.
- **État de l'autre session** : le Lot 2 v0 lu à 16:26 UTC peut avoir changé depuis (non commité).

## BLOCKED

- Exécution de quoi que ce soit (pytest, node, LLM, Blender, LM Studio) : interdite par la mission ; tout ce qui n'a pas de trace dans `EVIDENCE/` reste PARTIEL.
- Voie asset sur ce poste : `forge/blender.config.json` absent, `BLENDER_BIN` absent ⇒ `BLOCKED · BLENDER_EXECUTOR_UNAVAILABLE` par construction.
- Limite de session API rencontrée pendant l'audit (529 puis 429) : 4 relances, 2 audits basculés d'Opus vers Sonnet (contrats, baseline, oracles, skills) — modèle noté sur chaque rapport.

## RECOMMENDATIONS (aucun code, propose-only)

1. **Faire du registre la liste des pertes, pas seulement des gains** : ajouter à `capability_registry.yaml` (ou à `spec()`) un champ par capacité qui nomme le propriétaire de chaque mécanisme déplacé — pré-mortem, retry avec feedback, escalade, routage provider, timeout, journal — « Director », « invoke », ou « perdu volontairement ». Sans propriétaire nommé, L1/L3/L5/L14 disparaissent en silence.
2. **Réparer l'observabilité avant de convoquer davantage** : le manifest `dispatch` de la sonde mesure `_UPSTREAM_BY_STEP` (8 amonts « absents ») alors que le contexte vient du Blueprint (L8) ; ajouter un enregistrement `execution` portant les `blueprint_inputs` (section, version, sha de la sous-entrée) et le modèle MESURÉ (L7, L11). C'est la condition pour que la sonde Lot 2 soit une preuve et non une attestation.
3. **Épingler l'effort à l'escalade** : `escalate.LADDER` devrait produire des identifiants résolubles par `roles.yaml` (ou `roles.yaml` déclarer les alias) pour que `--effort` survive à l'escalade et que la version de modèle reste épinglée ; aujourd'hui l'escalade change trois choses (famille, version, effort) pour une seule décision.
4. **Transporter le pré-mortem dans `invoke_capability`** (L1) : c'est le seul canal d'apprentissage démontré ; sa perte annule la boucle « journal → prompt suivant » pour toute capacité convoquée hors driver. Idem retour du matérialiseur à la re-convocation (L3).
5. **Nommer le régime d'écriture** : trois régimes coexistent (exécuteur matérialise ; agent écrit sous `GAMES/` ; agent écrit `art_bible.md`) ; le registre n'en connaît qu'un. Une capacité extraite doit déclarer le sien.
6. **Décider le sort des skills homonymes** : `skill: world-scan` et `skill: architecture-review` dans les contrats désignent des skills sans rapport avec les étapes ; soit retirer le champ (il est inerte), soit construire le pont (injection du skill.md) — pas l'entre-deux actuel.
7. **Mettre à jour les auto-descriptions périmées** repérées : `RUN_INDEX.md` (HALT du 2 sept.), `pretool_git_guard.py:4-8` (« non câblé » alors que câblé), `hook_guard.py:113-120`, docstring `_run_mutation_descriptor_regime`, `last_root_cause` figé après succès.
8. **Une capacité = un contrat résoluble** : `asset_producer` (rôle absent de `models[]`) et `story_bible` (rôle emprunté à `art_director`) ne passent pas ce critère ; à trancher avant d'entrer au registre.

## STATUS_BY_SURFACE

```
status_by_surface:
  porte_de_spawn (prepare_dispatch + hook + audit HMAC):           TESTED        # baseline + sonde Lot 2
  contrats_17_champs / prompt rendu (13 sections):                 TESTED
  resolution_modele_par_role (roles.yaml, registry):               TESTED        # 3 familles, 2 efforts
  effort_transmis (--effort par modele):                           IMPLEMENTED   # declare seulement ; absent apres escalade
  reasoning_mesure:                                                NOT_FOUND     # aucun champ nulle part
  escalade builder (pool + ladder + cap):                          TESTED        # 2 escalades baseline
  escalade_scope ESC-1 (model_override_scope):                     IMPLEMENTED   # 0 run
  routage_provider (route_step, Qwen reel / claude-blind):         TESTED        # s6 sur Qwen reel
  executeur headless (argv, allow/deny, strict-mcp, add_dir):      TESTED
  4_tables_run_real + prompts par etape:                           TESTED
  validateurs_artefact (texte libre) + repair Qwen (5 etapes):     TESTED        # advisory
  jointure_wiremap (5 regimes):                                    TESTED        # VOID + 9 fantomes en baseline
  oracles_deterministes s10a/b/c + verdict HMAC + verify_run:      TESTED
  oracle_standard s10s / profils standard*:                        IMPLEMENTED   # 0 trace V2
  capacites_amont dediees (s2.5, s2.6, s2.7, -rN):                 IMPLEMENTED   # 0 trace V2
  check_artbible (import ../../knowledge_base hors depot):         UNKNOWN
  premortem -> prompt (journal + lessons):                         TESTED        # 28 prompts ; lecons toutes "a reexaminer"
  boucle lecon -> KB (validated, catalog, emitter, learning_curve): PASSIVE      # 0 validated, 0 consommateur
  canal fiches KB dans le prompt (_render_kb_section):              PASSIVE      # 0 prompt reel
  skills .claude/skills -> agent executant:                        NOT_FOUND     # aucun pont ; champ skill inerte
  agents .claude/agents dans la Forge:                             NOT_FOUND
  heritage_autorite (couche 2 du hook):                            PASSIVE       # mode off, temoin absent
  voie_asset (Qwen spec + Blender + oracle geometrie):             BLOCKED       # CLI seule ; Blender non configure ; preuve V1
  observer fin de run:                                             IMPLEMENTED   # baseline INCOMPLETE (avant Lot 0)
  RUN_INDEX.md:                                                    PASSIVE       # perime (HALT du 2 sept.)
  exit code run_real apres HALT:                                   IMPLEMENTED   # toujours 0
  GAME_BLUEPRINT + importeur (Lot 1, 3481089):                     IMPLEMENTED   # commite, hors perimetre detaille
  CAPABILITY_REGISTRY + invoke_capability (Lot 2 v0):              IMPLEMENTED   # NON COMMITE ; 1 sonde reelle ; 4/15 invocables
  pertes Lot 2 (22 items) nommees dans le registre:                NOT_FOUND     # 13 emportes, 22 perdus/deplaces, 0 declares
  director / journal de decisions / reprise objet bloquant:        NOT_FOUND
  replay / certificat seed+inputs+hash / historique de section:    NOT_FOUND
no_global_ready_verdict: true
```

## SOFTWARE_VERDICTS_BY_SURFACE

```
porte_de_spawn:                         OK        # mecanisme exerce, reçus signes
contrats_et_prompt:                     OK
resolution_modele:                      OK
effort_apres_escalade:                  FAIL      # flag absent, version non epinglee (mesure baseline s9 a4-a6, s11)
reasoning_mesure:                       BLOCKED   # rien a mesurer
escalade:                               OK        # bornee, tracee ; portee corrigee non rejouee
routage_provider:                       OK
executeur_headless:                     OK
validateurs_et_reparation:              OK        # advisory ; STATUS ESCALADE sur s3/s5 sans effet sur le statut d'etape
oracles_et_verdict:                     OK        # AUTHENTIQUE
capacites_dediees_sans_trace:           BLOCKED   # aucune evidence V2
check_artbible_v2:                      BLOCKED   # import hors depot
premortem:                              OK
boucle_kb:                              FAIL      # producteurs sans consommateurs, 0 validated
skills_vers_executant:                  FAIL      # champ declare, jamais transporte
voie_asset:                             BLOCKED
lot2_v0_invoke:                         OK        # 1 convocation reelle validee par l'oracle existant (2 codes K7)
lot2_v0_conservation_de_la_competence:  FAIL      # 22 mecanismes perdus/deplaces, non declares
```

## EVIDENCE_VERDICTS_BY_SURFACE

```
toutes surfaces: MECHANICAL_VALIDATION_ONLY
  # preuves = fichiers du depot lus a HEAD 3481089 (+ arbre sale Lot 2), traces EVIDENCE/runs/runm_breakout
  # (git_head 2769dc8) et EVIDENCE/runs/lot2_decompose_probe (git_head 3481089), tests cites par nom,
  # jamais executes. Signatures HMAC non re-verifiees (execution interdite).
```

## CLAIM_VERDICTS_BY_SURFACE

```
toutes surfaces: NO_CLAIM_ALLOWED
no_global_ready_verdict: true
```

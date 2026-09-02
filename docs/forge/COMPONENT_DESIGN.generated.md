# COMPONENT DESIGN — carte des composants du code Forge (auto-généré)

> ⚠ Fichier **AUTO-GÉNÉRÉ, ne pas éditer à la main.**
> Produit par `python -m forge.component_design --write`. Chaque ligne est
> extraite des modules `scripts/forge/*.py` via le module `ast` (docstring de
> module → responsabilité ; `def`/`class` publics → interface ; imports
> `forge.*` → dépendances). Déterministe, non-LLM, sans horodatage → il ne
> change que si le code change (zéro bruit git). La table DÉCRIT, elle ne
> JUGE pas. `claim_verdict: NO_CLAIM_ALLOWED`.

| Module | Responsabilité | Interface publique | Dépend de |
|---|---|---|---|
| `contract` | Dispatcher de contrat d'agent Forge — la porte d'entrée bornée. | `ContractIncomplete`, `DispatchPayload`, `RoleUnresolved`, `build_dispatch_payload`, `field_state`, `load_contract`, `resolve_runtime`, `validate_contract` | — |
| `dispatch` | Dispatch gouverné de la chaîne Forge — la porte unique. | `DispatchRecord`, `main`, `order_for_profile`, `plan_chain`, `prepare_dispatch`, `sign_audit_record`, `verify_audit_line` | `contract`, `verdict` |
| `driver` | Driver Forge (P0.1) — la machine à états déterministe du pipeline. | `ForgeDriver` | `contract`, `dispatch`, `escalate`, `gate`, `mutation_proof`, `pool`, `runtime`, `static_oracles`, `studio_link`, `verdict` |
| `escalate` | Escalade de modèle — un tier faible demande (ou déclenche) une montée en puissance. | `EscalationDecision`, `escalation_decision`, `next_tier`, `parse_agent_escalation`, `tier_of` | — |
| `gate` | forge_gate — the FORCER brick. | `GateResult`, `forge_gate` | `oracle`, `verdict` |
| `hook_guard` | Garde de spawn Forge — la logique du hook dur (ADR-002 connecteur 2). | `check_spawn`, `hook_decision` | `dispatch` |
| `mutation` | Mutation testing — le MÉTA-oracle : « tes tests attrapent-ils vraiment un bug ? ». | `Mutant`, `generate_mutants`, `main`, `run_mutation_test` | — |
| `mutation_proof` | Reçu mutation signé (P0.2) — ferme les trous I1/I2 du chemin critique. | `emit_mutation_receipt`, `fingerprint`, `logic_files_from_wiremap`, `run_mutation_for_game`, `verify_mutation_receipt` | `mutation`, `static_oracles`, `verdict` |
| `oracle` | Per-project oracle resolution and execution. | `OracleNotFound`, `OracleResult`, `OracleSpec`, `resolve_oracle`, `run_oracle` | — |
| `panel` | panel.py — panel Prisme (Tier 2 #6, WFL-02) : N lenses isolées + recombinaison | `lens_prompt`, `panel_prisme_executor` | — |
| `pool` | Pool de builders réactif (Concept A, Tier 2 #5) — best-of-N au MÊME tier. | `PoolDecision`, `pool_decision` | — |
| `run_real` | scripts/forge/run_real.py — premier point d'entrée RÉEL de `forge.driver.ForgeDriver`. | `build_parser`, `claude_executor`, `default_task_by_step`, `extract_json_payload`, `load_tasks_file`, `main`, `make_panel_claude_call`, `merge_task_overrides`, `stale_run_dir_reason`, `upstream_artifacts_section` | `dispatch`, `driver`, `panel`, `pool`, `verify_run` |
| `runtime` | Aiguilleur runtime des étapes LLM de la chaîne Forge (A2). | `RouteDecision`, `qwen_available`, `route_step`, `run_qwen_step` | `contract` |
| `static_oracles` | Oracles statiques déterministes de Forge — ARCHI (s10b) + WIREMAP (s10c). | `check_architecture`, `check_e2e_harness`, `check_feature_set_frozen`, `check_mutation_gate`, `check_reuse_ratio_wired`, `check_solvability_wired`, `check_wiremap`, `frozen_features_from_wiremap`, `load_frozen_features`, `load_mutation_triage` | — |
| `studio_link` | Connecteurs studio de Forge — ADR-002 §3 (connecteurs 3/4/5/6). | `generate_journal_index`, `list_journals`, `main`, `pool_stats`, `premortem`, `project_bible`, `propose_bible_entry`, `propose_ledger_entry`, `propose_project_record`, `record_builder_run`, `record_error`, `record_fix`, `record_global_lesson`, `record_telemetry`, `run_cost`, `write_journal_index` | `verdict` |
| `verdict` | Signed forge verdict — the anti-over-claim epistemology brick. | `AggregateVerdict`, `OracleReceipt`, `SignedReceipt`, `Verdict`, `build_aggregate_verdict`, `build_verdict`, `current_git_head`, `is_clean_pass`, `make_signed_receipt`, `new_nonce`, `sha256_file`, `sign_aggregate`, `sign_receipt`, `sign_verdict`, `signed_aggregate_record`, `status_from_passed`, `verify_aggregate`, `verify_receipt`, `verify_verdict` | — |
| `verify_run` | Vérification MÉCANIQUE d'un verdict Forge — le maillon que `/gate` doit appeler. | `main`, `verify_run` | `mutation_proof`, `verdict` |

**Modules cartographiés** : 17 · **sans docstring de module** : 0


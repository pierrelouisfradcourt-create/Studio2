# VALIDATION DE CLÔTURE — STUDIO V2

*2026-09-02 · V0 gel · V1 structurel · V2 fonctionnel · V3 classification.
Outil rejouable : `TOOLS/validate_v2.py`.*

---

## V0 · Gel de l'état — **la provenance est étanche**

```
V1  C:\TACTICAL_CHESS_STUDIO       HEAD 58095ba91822
    écarts scripts/forge : 4, TOUS de l'autre session — aucune absorption
V2  C:\Users\Studio-Dev\Desktop\Studio
    dépôt git indépendant · 0 commit · aucun historique V1
    58095ba9 INTROUVABLE dans le dépôt V2
```

> **Le piège que tu avais anticipé s'est produit, et le validateur le neutralise par construction.**
> Depuis le `git init`, une commande git lancée avec `cwd = Studio` interroge **le dépôt V2**.
> Ma première mesure de `docs/` a ainsi rendu « 0 fichier présent au HEAD » — elle posait une
> question V1 au dépôt V2. `TOOLS/validate_v2.py` **nomme le `cwd` à chaque appel git** ; c'est
> écrit en tête du module.

## V1 · Structurel — **17 PASS · 0 FAIL**

```
surfaces attendues .............. 9/9        forge · knowledge_base · GAMES · EVIDENCE
                                             TOOLS · docs · .claude · control_plane · MASTER_SCHEMA
modules forge importables ....... 50/50
chemins runtime résolus ......... 6/6
knowledge_base .................. 50 entrées · 26 propositions (jamais servies, R7)
contrats d'agent ................ 28 · consumption_evidence filled 0 / absent 28 (base P3)
mandatory_read .................. 69/69
.claude — références fantômes ... 0
chemins `games/` actifs ......... 0
chemins `scripts/forge` actifs .. 0
résidus `lab/` .................. 46, tous classés
docs ............................ 44 (critère : cité par contrat ou code actif)
Control Plane — lane ............ absente     registry — CONSERVÉ (ADR-002 gate 1)
```

**Deux gardes de mesure ajoutées après un faux positif chacune :**
- `Path("FORGE").exists()` renvoyait **True** alors que le dossier n'existe pas — **casse Windows**.
  Le contrôle passe par `os.listdir`, qui ne ment pas.
- une mention **datée** `` `scripts/forge` (V1) `` est un **constat historique**, pas une
  désignation active : elle est exclue du compte, explicitement.

## V2 · Fonctionnel — les capacités rejouées

```
2446 passed · 62 skipped · 10 deselected (gpu_window)
```
dont : oracles code/archi/wiremap · `run_real`/driver · knowledge_trace **advisory** ·
journal d'amendements · émetteur · consumption · jointure Feature Map ↔ Wiremap ·
oracle produit / volet visuel · **sceau d'évidence + git**.

## V3 · Classification de la suite complète — **45 résultats, 0 FAIL**

| n | tests | catégorie | raison mesurée |
|---|---|---|---|
| 10 | `micro_redeclaration` | OUT_OF_SCOPE | run_dirs V1 (`p1_alpha`, `p1_beta`…) non migrés |
| 9 | `r3_locus` | OUT_OF_SCOPE | idem — corpus de runs V1 |
| 5 | `s9_contract_loop_rule` · `s9_contract_runtime_rule` | OUT_OF_SCOPE | `EVIDENCE/runs/kitten_clicker/tasks.json` — **run_dir V1**, non migré |
| 3 | `runtime_inventory_oracle` | OUT_OF_SCOPE | attend `scripts/council.py`, `claude_proxy.py` — hors périmètre ratifié |
| 3 | `prisme_gm_source_gate` | OUT_OF_SCOPE | artefacts de run V1 |
| 2 | `reference_guard` | OUT_OF_SCOPE | capacité **RETIRE** ratifiée (contrôle d'orphelins) |
| 2 | `mutation_scope_categories` · 1 `mutation_regime_coexistence` | OUT_OF_SCOPE | reçus de mutation de runs V1 |
| 2 | `learning_memory` | OUT_OF_SCOPE | corpus `EVIDENCE/reports` hérité de V1 |
| 2 | `e2e_harness` · `e2e_harness_acceptance` | OUT_OF_SCOPE | visent `collect_runner_legacy` / `_r1` — **jeux non retenus** |
| 1 | `run_real_redteam_findings` | OUT_OF_SCOPE | rapport historique `pong_r2` |
| 1 | `reuse_ratio_wired` | OUT_OF_SCOPE | jeu `kb_tactics` non retenu |
| 1 | `observer_integration_real` | OUT_OF_SCOPE | instantanés Observer V1 |
| 1 | `manifest_lesson_promotion` | OUT_OF_SCOPE | corpus de manifestes V1 |
| 1 | `charter_gate` | OUT_OF_SCOPE | fixture `EVIDENCE/runs/p2_beta/artifacts/` non migrée |
| **1** | `commit_scope_guard::…asset_library…` | **NOT_YET_PRODUCED** | `EVIDENCE/bundles/asset_lessons` — **dossier non créé artificiellement** |

```
PASS ...................... 2446   (+ 17 contrôles structurels)
INTENTIONALLY_OUT_OF_SCOPE .. 44
NOT_YET_PRODUCED ............. 1
BLOCKED ...................... 0
FAIL ......................... 0
```

### Ce que j'ai réparé plutôt que classé — 11 tests, tous des propriétés V2 réelles
| réparation | pourquoi ce n'était pas « hors périmètre » |
|---|---|
| `.gitignore` récupéré de V1 (6 tests) | `evidence_seal` **s'en sert comme critère** — sans `*.log`, un flux de bruit devenait scellable. **Modifier ce fichier, c'est modifier un mécanisme de preuve** ; c'est écrit en tête du fichier |
| instances **nommées** dans `.gitignore` (1) | V1 : *« un motif ne dit pas QUI il protège »*. J'avais gardé le motif et perdu les noms — le test avait raison |
| `test_hook_guard_stdlib_only` (2) | ancrage `REPO_ROOT/"scripts"` → layout L1 |
| `test_standard_step_wiring` (1) | `parent.name == "games"` → `"GAMES"` : la propriété tient, la surface a changé de nom |
| `test_commit_scope_guard` séparateurs (1) | périmètre en **antislash** `scripts\forge\…` — forme que ma migration n'avait pas couverte |

**Aucun test supprimé.** Aucune dépendance externe installée pour verdir un compteur.

### Dépendances externes — par capacité, jamais globales
```
Forge core · oracles s10a-c · Pong navigateur  →  ni Blender ni Godot
volet visuel Godot · solvabilité · product_oracle Godot  →  Godot   CONDITIONNEL
asset producer · asset_geometry  →  Blender                        CONDITIONNEL
```
`godot.config.json` / `blender.config.json` portent un chemin de poste, sont **ignorés par
construction**, et restent à configurer localement — comme `.forge_key`.

---

## VERDICT

```
V2 VALIDATION
────────────────────────────────────
PASS ....................... 2463
OUT_OF_SCOPE ................. 44
NOT_YET_PRODUCED .............. 1
BLOCKED ....................... 0
FAIL .......................... 0
────────────────────────────────────
VERDICT : VALIDATION V2 FRANCHIE
```

**Tous les `OUT_OF_SCOPE` sont justifiés par le modèle V2** — artefacts V1 délibérément non migrés,
capacités retirées, jeux non retenus. Le seul `NOT_YET_PRODUCED` est un état de production, pas un
défaut.

### Ce que cette validation NE dit pas
Elle prouve que **le Studio V2 est structurellement cohérent et que ses capacités s'exécutent**.
Elle **ne prouve pas qu'un jeu a été forgé de bout en bout en V2** — aucun run réel n'a été lancé.
C'est le prochain sujet, et c'est un run, pas une validation.

```
status_by_surface:
  v0_gel:            TESTED   # HEAD 58095ba9 · provenance étanche
  v1_structurel:     TESTED   # 17 PASS / 0 FAIL
  v2_fonctionnel:    TESTED   # 2446 passed
  v3_classification: TESTED   # 45 classés, 0 FAIL
  premier_run_reel:  BLOCKED  # jamais tenté — hors validation
  v1_intact:         TESTED   # 58095ba9, 4 écarts de l'autre session
```
`software_verdict: OK` · `evidence_verdict: MECHANICAL_VALIDATION_ONLY` ·
`claim_verdict: NO_CLAIM_ALLOWED` · `no_global_ready_verdict: true`

**Pacman `00_CHARTER` / `09_WIREMAP` : UNAVAILABLE @ 58095ba9. Q2 / R8 : intactes.**

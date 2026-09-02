# ÉTAPE 9 — MIGRATION DES SURFACES · 9A → 9K

*2026-09-02 · **V1 non modifié** (`58095ba9`, seuls les 4 fichiers de l'autre session en écart).
Correspondance ratifiée Pierre le 2026-09-02.*

---

## 9A–9G · surfaces créées
```
EVIDENCE/runs/        ex-lab/forge_runs        EVIDENCE/briefs/    ex-lab/forge_briefs
EVIDENCE/bundles/     ex-lab/forge_evidence    EVIDENCE/chains/    ex-lab/chains
EVIDENCE/reports/     ex-lab/reports           EVIDENCE/amendments/ (J1)
EVIDENCE/runs/RUN_INDEX.md   index, pas destination
```
> **9G — un écart entre le document et le code, tranché en faveur du code récupéré.**
> `TOPOLOGY.md` §124 plaçait l'index à `EVIDENCE/RUN_INDEX.md` ; le code récupéré
> (`driver._run_index_target`) le place sous `EVIDENCE/runs/`. J'ai **aligné le document sur le
> code**, pas l'inverse — on récupère l'existant, on ne le réécrit pas pour coller à un brouillon.

## 9H · migration par famille — **pas un remplacement aveugle**

**Trois formes distinctes ont dû être traitées**, et c'est la raison pour laquelle un
`replace("lab/", …)` aurait échoué :

| forme | exemple | occurrences |
|---|---|---|
| chemin littéral | `"lab/forge_runs"` | **643** |
| segments Python | `REPO_ROOT / "lab" / "forge_runs"` | inclus ci-dessus |
| **segments JS/py** | `join(root, 'lab', 'forge_runs')` | **63** — *survivaient à la première passe* |

```
lab/forge_evidence -> EVIDENCE/bundles   264
lab/forge_runs     -> EVIDENCE/runs      255
lab/reports        -> EVIDENCE/reports   167
lab/forge_briefs   -> EVIDENCE/briefs     12
lab/chains         -> EVIDENCE/chains      8
```
**`.md` volontairement NON migrés** — trace historique. Une mesure datée qui cite `lab/forge_runs`
décrit ce qui a été observé alors ; la réécrire falsifierait le constat.

### Deux corrections de comportement (classe 3), trouvées par les tests et non par grep
1. **`amendment_log.JOURNAL_DIR`** : la migration par famille l'avait envoyé dans
   `EVIDENCE/bundles/amendments`. **Le journal n'est pas un bundle** — corrigé en
   `EVIDENCE/amendments/`, conformément à J1.
2. **Ancrage racine des `.mjs`** : `resolve(here, '..', '..')` remontait d'un cran de trop dans le
   layout L1 → `runsRoot` pointait hors du Studio et **`writeTrace` refusait toute écriture**.
   **29 occurrences / 29 fichiers** corrigées (`'..','..'` → `'..'`), pendant exact du décrément
   `parents[N]` côté Python.

## 9I–9J · résidus `lab/`, classés

**55 occurrences restantes**, aucune accidentelle :

| résidu | n | classe | pourquoi |
|---|---|---|---|
| `lab/agent_policy` | 28 | **UNKNOWN** | matrice de permissions lue par `declaration_readers.mjs` — `CLAUDE.md` la déclare *« legacy de fait, consommée par la SEULE lane STUDIO »*, or cette lane n'existe pas en V2. **Les fichiers n'ont pas été récupérés** : soit les lecteurs sont morts en V2, soit la matrice doit venir. À trancher |
| `lab/workflow_lab` | 5 | **UNKNOWN** | surface sans destination dans la correspondance ratifiée |
| `lab/forge_sensors` | 3 | attendu | contrat `s10d`, hors ORDER (V-3 : ne pas brancher) |
| `lab/forge_runs` · `lab/forge_evidence` | 4 | attendu | `.md` et une fixture de test — trace historique, non migrés **par décision** |
| `lab/chess_fantasy` | 1 | **erreur** | entrée de `oracles.json` pointant une lane exclue. **Non retirée** : modifier une config récupérée est un lot distinct |
| `lab/nexiste_pas` · `lab/x.json` · `lab/pas_la` | 8 | attendu | chemins volontairement inexistants dans des tests |

> **`games/` n'était pas dans la correspondance ratifiée** : 378 occurrences laissées telles
> quelles. Elles fonctionnent **par insensibilité à la casse de Windows** (`games/` résout vers
> `GAMES/`). **C'est fragile et non portable** — à trancher, pas à corriger en passant.

## 9K · tests ciblés

```
forge/tests/{amendment_log, consumption, consumption_evidence_layer, emitter, join_advisory}
   → 67 passed
suite complète V2   → 2435 passed · 56 failed · 62 skipped · 10 deselected   (2:37)
```

### Les 56 échecs, par nature
| fichier | n | cause mesurée |
|---|---|---|
| `test_micro_redeclaration` · `test_r3_locus` | 19 | s'appuient sur des **run_dirs V1 réels** (`p1_alpha`, `kitten_clicker`) non migrés |
| `test_s9_contract_*` | 5 | lisent `.claude/tasks.json` — **non récupéré** |
| `test_runtime_inventory_oracle` | 3 | attendent `scripts/council.py` et `scripts/claude_proxy.py` — **hors périmètre V2** |
| `test_evidence_seal_*` · `test_commit_scope_guard` · `test_reference_guard` | 10 | exigent un **dépôt git** — V2 n'en est pas un |
| `test_blender_bin` · `test_e2e_harness*` · `test_observer_integration_real` · autres | 19 | binaires/config d'environnement absents (Blender, Godot) ou artefacts V1 |

> **Aucun de ces 56 échecs n'est un défaut du code récupéré.** Ce sont des tests **ancrés sur des
> artefacts V1 que nous avons décidé de ne pas migrer**. Les nommer ainsi n'est pas les excuser :
> tant qu'ils échouent, la suite V2 n'est pas un oracle utilisable — c'est un lot à traiter, et il
> n'est pas dans les 10 étapes.

```
status_by_surface:
  surfaces_creees:        TESTED   # 6 dossiers + index
  migration_3_formes:     TESTED   # 706 occurrences, dont 63 en forme segmentée
  md_non_migres:          TESTED   # trace historique préservée
  journal_corrige:        TESTED   # EVIDENCE/amendments, pas bundles
  ancrage_mjs:            TESTED   # 29 fichiers, writeTrace débloqué
  residus_classes:        TESTED   # 55, aucun accidentel
  lots_session_en_V2:     TESTED   # 67 passed
  suite_v2:               TESTED   # 2435 passed / 56 failed
  agent_policy:           UNKNOWN  # arbitrage Pierre
  workflow_lab:           UNKNOWN  # arbitrage Pierre
  games_casse:            BLOCKED  # hors correspondance ratifiée
  v1_untouched:           TESTED   # 58095ba9
```
`software_verdict: OK` · `evidence_verdict: MECHANICAL_VALIDATION_ONLY` ·
`claim_verdict: NO_CLAIM_ALLOWED` · `no_global_ready_verdict: true`

**Pacman** : `00_CHARTER/` et `09_WIREMAP/` restent **NON DISPONIBLES DANS LE HEAD CANONIQUE — NON
COPIÉS — NON REMPLACÉS**. **Q2 / R8 : non touchée.**

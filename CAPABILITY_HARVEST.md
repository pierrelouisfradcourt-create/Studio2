# CAPABILITY HARVEST — de quoi la Forge optimale a besoin, et où c'est déjà construit

*2026-09-01 · **DOCUMENTED_ONLY** · aucun code, aucune suppression, aucun déplacement, aucun test
exécuté. Dépôt source à `feeb29cb`, non touché. `FORGE_TARGET_ARCHITECTURE.md` laissé en place.*

Cible : `FORGE_TARGET_MODEL.md`. On ne demande plus *« qu'est-ce qu'on supprime ? »* mais
**« de quoi la Forge optimale a-t-elle besoin, et où est-ce déjà construit ? »**

Classement : `REUSE` (utilisable tel quel) · `ADAPT` (bonne capacité, mauvaise interface) ·
`MERGE` (doublon / capacité répartie) · `REBUILD` (idée valable, implémentation inutilisable) ·
`RETIRE` (relique du workflow) · `UNKNOWN` (pas assez de preuve).

---

## ⚠ Correction d'une affirmation antérieure

J'ai écrit deux fois que **System Design n'était pas un rôle** et que `economy.json` / `loop.json`
étaient des *« sorties orphelines que personne ne possède »*. **C'est faux, et la mesure dit
quelque chose de bien plus intéressant.**

```
run_real.py:2372 — VERROU ABSOLU (GO Pierre 2026-08-22)
  « loop.json est une PROJECTION DÉTERMINISTE de prisme.json, JAMAIS une source de vérité.
    deriveLoopSpec (loop_spec.mjs) est une fonction PURE — c'est l'EXÉCUTEUR qui la lance
    et écrit le résultat, AUCUN LLM n'écrit jamais ce fichier. Si la sortie d'un agent s1
    contenait un bloc json nommé `loop` ou tentait d'écrire loop.json, ce serait IGNORÉ. »
```

Idem `economy.json` : projection déterministe de `gm_worldscan.json` via
`game_master_schema.mjs` — *« fonction PURE : aucune horloge, aucun aléa »*. Et les deux sont
**vérifiés par sha256** contre `03_WORLD/*.json` du build : altération → violation nommée.

**Le studio a donc déjà tranché** : les nombres du jeu ne sont écrits par **aucun agent**, ils sont
**dérivés du design** et l'altération est détectée par hash. Ce n'est pas un trou — c'est un choix
d'architecture délibéré, daté, gardé.

**Ce qui manque réellement** : les `design_metrics` (les cibles) n'entrent **nulle part** dans cette
dérivation. La chaîne existe à moitié — `prisme.json → loop.json`, `gm_worldscan.json →
economy.json` — mais rien ne relie une **intention chiffrée** de Pierre à ces projections.

---

## La carte — capacité par capacité

### 1 · `GAME_BLUEPRINT` — l'objet central
| | |
|---|---|
| **source actuelle** | `FORGE_PROJECT_INPUT_V0` (Brief, 10 champs) · `FORGE_DESIGN_FREEDOM_SPEC_V0` (N1–N9) · `forge/static_oracles.py::check_project_brief` · `forge/context_manifest.py` (empreinte sha256) |
| **consommateur** | `run_real.py` (23 réf.), pré-vol **fail-closed avant toute dépense LLM** · `context_manifest` (4) · `static_oracles` (4) · `driver` (2) |
| **contrat** | `FORGE_PROJECT_INPUT_V0` §1 — chemin ratifié 2026-08-29 ; entrées alternatives **interdites** |
| **preuves** | oracle déterministe `check_project_brief` ; `provenance` par champ, source absente = FAIL |
| **dépendances** | PyYAML |
| **réutilisabilité** | **haute** — le mécanisme d'entrée unique + validation fail-closed est exactement ce qu'il faut |
| **verdict** | **ADAPT** — le Brief devient les sections `identity/vision/constraints` du Blueprint ; il faut lui ajouter `research`, `understanding`, `systems`, `design_metrics`, `ux`, `art`, `technical` |

### 2 · Director (Fable)
| | |
|---|---|
| **source actuelle** | `contracts/orchestrator.yaml` · `contracts/roles.yaml` · `forge/escalate.py` · `forge/driver.py` (la boucle) |
| **consommateur** | `roles.yaml` distingue `orchestrator` (**la session**, résolue par aucun code) de `run_orchestrator` (l'agent) |
| **contrat** | `orchestrator.yaml` grave *« Pierre → session Claude à contexte propre → agent orchestrateur → workers »* |
| **preuves** | 29 fichiers de test sur `driver` — la boucle, l'escalade, les renvois sont couverts |
| **dépendances** | contrats · dispatch · registry de rôles |
| **réutilisabilité** | **partielle** — le *rôle* est nommé et séparé de l'exécution ; la **composition** n'existe pas |
| **verdict** | **ADAPT** — garder la boucle, l'escalade, l'agrégation ; remplacer `self.order = order_for_profile(profile)` par une composition pilotée par le Blueprint |

### 3 · Research + World Scan
| | |
|---|---|
| **source actuelle** | `contracts/s2-worldscan.yaml` · `contracts/s2.7-gm-worldscan.yaml` · `forge/check_worldscan.mjs` · skill `world-scan` |
| **consommateur** | profils `amont_only`, `amont_narratif`, `gm_worldscan` (mono-étape) |
| **contrat** | s2-worldscan déclare `run: WebSearch, WebFetch` · `skill: world-scan` — **la capacité web est contractualisée** |
| **preuves** | `check_worldscan.test.mjs` · worker Qwen calibré et validé |
| **dépendances** | outils de l'orchestrateur (WebSearch/WebFetch), **pas** du code Forge |
| **réutilisabilité** | **haute** — rien à construire |
| **verdict** | **REUSE** — débrancher du chemin obligatoire, appeler à la demande. ⚠ **verrou actif Pierre** : *« World Scan hors périmètre »* + *« R8 BLOQUÉ »* |
| **manque** | l'axe *« pourquoi les joueurs abandonnent »* et la **capitalisation en KB** (aujourd'hui le résultat reste dans le run_dir) |

### 4 · Prisme — rétro-ingénierie
| | |
|---|---|
| **source actuelle** | `contracts/s1-prisme.yaml` · `prisme.json` · `forge/check_prisme.mjs` · `check_prisme_manifest.test.mjs` |
| **consommateur** | driver (étape active) · **`s3-decompo` en dépend structurellement** : chaque unité cite l'`id` exact d'une exigence de `prisme.json` |
| **contrat** | s1-prisme (1 agent) |
| **preuves** | 1 test `.py` + `check_prisme.test.mjs` + `check_prisme_manifest.test.mjs` |
| **dépendances** | — |
| **réutilisabilité** | **haute** — et **critique** : il est la source des exigences traçables |
| **verdict** | **REUSE** — capacité de renseignement du Director. Le retirer casserait la couverture |
| **à ne pas confondre** | le **panel multi-lentilles** (`panel.py`, `prisme/merge_prisme.mjs`, 8 fichiers) est gelé, `--charter` jamais passé → **RETIRE** |

### 5 · Gameplay Design
| | |
|---|---|
| **source actuelle** | `contracts/s0-contrat.yaml` → `charter.yaml` |
| **consommateur** | driver ; le charter est l'entrée de tout l'aval |
| **preuves** | `check_charter` (advisory) |
| **réutilisabilité** | haute |
| **verdict** | **ADAPT** — le charter devient la section `gameplay` du Blueprint, plus un artefact d'étape |

### 6 · System Design — **corrigé**
| | |
|---|---|
| **source actuelle** | `forge/loop_spec.mjs` (`prisme.json → loop.json`, fonction PURE) · `forge/game_master_schema.mjs` (`gm_worldscan.json → economy.json`, fonction PURE) · vérification sha256 dans `product_oracle_godot.py` |
| **consommateur** | `run_real.py` (matérialiseurs) · `driver.py` (comparaison sha256) · builder (reçoit `loop.json`+`economy.json` dans son contexte) |
| **contrat** | **verrou absolu daté** — aucun LLM n'écrit ces fichiers ; altération = violation nommée |
| **preuves** | `loop_spec.test.mjs` (avec fixture d'un run réel) · `game_master_schema.test.mjs` · comparaison de hash au build |
| **réutilisabilité** | **très haute** — mécanisme déterministe, testé, gardé |
| **verdict** | **REUSE** pour la projection · **REBUILD partiel** pour l'amont : il manque le chaînon `design_metrics` (cibles de Pierre) → paramètres de la projection |

### 7 · UX — **confirmé absent**
| | |
|---|---|
| **recherche exhaustive** | `\bUX\b` : **2 contrats**, et uniquement comme *chose à observer chez les autres* (`s2-worldscan` : « flux UX » des jeux de référence ; `s2.7` idem). `\bux\b` · « expérience utilisateur » · « user experience » : **0**. `ergonomie` : 0. `onboarding` : 0 contrat |
| **verdict** | **NOT_FOUND → REBUILD** — aucun rôle, aucun contrat, aucun oracle, aucune sortie. À créer si le Blueprint l'exige |

### 8 · Art Direction
| | |
|---|---|
| **source actuelle** | `contracts/s2.5-artbible.yaml` (+ profil mono-étape `artbible`) · `contracts/redteam-artdirector.yaml` · `forge/check_artbible.mjs` · `check_art_response.mjs` |
| **consommateur** | driver ; `art_bible.md` injecté au builder |
| **preuves** | 2 tests `.py` + `check_artbible.test.mjs` + `check_art_response.test.mjs` |
| **réutilisabilité** | haute, avec sa red-team dédiée déjà écrite |
| **verdict** | **REUSE** |

### 9 · Narration / GM
| | |
|---|---|
| **source actuelle** | `s2.6-story-bible.yaml` · `s2.7-gm-worldscan.yaml` (2 profils mono-étape) |
| **consommateur** | driver ; `gm_worldscan.json` alimente la projection `economy.json` |
| **réutilisabilité** | haute |
| **verdict** | **REUSE** — capacité optionnelle selon le jeu |

### 10 · Feature Map (ex-Décomposition)
| | |
|---|---|
| **source actuelle** | `contracts/s3-decompo.yaml` → `featuremap.json` · `check_decompo.test.mjs` |
| **consommateur** | `s5-wiremap` · oracles |
| **contrat** | **règle dure** : *« `source_ref` cite l'`id` EXACT d'une exigence de `prisme.json` — une feuille qui n'en cite aucune est une invention non déclarée, une exigence que nulle feuille ne porte est une omission silencieuse »* ; chaque feuille porte un `expected_proof` {kind, statement} |
| **preuves** | `check_decompo.test.mjs` |
| **réutilisabilité** | **haute** — la règle dure est le meilleur mécanisme anti-oubli du studio |
| **verdict** | **MERGE** — l'étape « Décomposition » disparaît, sa fonction passe au Director/System Design, **sa règle dure devient un invariant du Blueprint**, sa sortie devient la section `feature_map` |

### 11 · Wiremap / Technical Architecture
| | |
|---|---|
| **source actuelle** | `contracts/s5-wiremap.yaml` · `s4-archi.yaml` · `wm1-wiremap-breakout/tetris.yaml` · `check_wiremap_contract.mjs` · `09_WIREMAP/` |
| **consommateur** | `s10c-oracle-wiremap` · `s10s` · builder |
| **preuves** | 4 tests `.py` + `check_wiremap_contract.test.mjs` |
| **réutilisabilité** | haute |
| **verdict** | **ADAPT** — conserver l'objet (fonction · fichiers · preuve · statut) ; **déplacer** son déclenchement sous le Build Orchestrator, et lui donner le droit de **remonter** vers Fable au lieu d'inventer une décision de design |
| **dette connue** | `TRANSITION_INTEGRITY NOT_FOUND` — rien ne garantit la conservation des ids gel→build |

### 12 · **La jointure `expected_proof ↔ actual_proof`** — à construire
| | |
|---|---|
| **source actuelle** | **aucune.** `featuremap.json` : 26 ids · `wiremap.json` : 25 entrées · **intersection : 0** (mesuré sur `p2_alpha`, `card_engine`, `chain_probe_v1`) |
| **conséquence mesurée** | finding PAIRE 2 : *« économie = canon Cookie Clicker, interdit du Brief violé, non gardé par oracle »* — le `must_not_have` n'est jamais devenu une unité, donc jamais une preuve attendue, donc jamais un oracle |
| **verdict** | **REBUILD** — c'est la capacité manquante la plus rentable. Les deux moitiés existent et sont testées ; il manque l'anneau qui les relie |

### 13 · Build
| | |
|---|---|
| **source actuelle** | `s9-build.yaml` · `s9-build-standard` · `s9-build-godot` · `s9-build-godot-standard` · `forge/standard/` (squelette gelé : `repo_map.yaml`, `core_requirements.yaml`, `capabilities.yaml`, `factory_capabilities.yaml`) |
| **consommateur** | driver ; reçoit charter + art_bible + loop.json + economy.json + asset_requests |
| **preuves** | couvert par les 29 tests `driver` |
| **dépendances** | `claude` CLI · Node · Godot (profils Godot) |
| **réutilisabilité** | haute |
| **verdict** | **REUSE** — les 4 variantes deviennent des **workers** choisis par le Build Orchestrator selon `technical` du Blueprint |

### 14 · QA — oracles
| | |
|---|---|
| **source actuelle** | `oracle.py` (284 l., résolution+exécution) · `static_oracles.py` (1818 l. — ARCHI s10b + WIREMAP s10c) · `standard_oracles.py` (1854 l. — oracles du STANDARD) · `product_oracle.py` (800 l. — oracle PRODUIT, *« ce que le gate mutation ne peut structurellement pas juger »*) · `product_oracle_godot.py` (1056 l. — capture GPU) · `mutation.py` (*« le MÉTA-oracle : tes tests attrapent-ils vraiment un bug ? »*) · `mutation_proof.py` (reçu signé) |
| **consommateur** | `gate.forge_gate` · driver |
| **preuves** | **14 tests `oracle` + 13 tests `mutation`** |
| **dépendances** | Node · Godot (visuel) · `oracles.json` (registre) |
| **réutilisabilité** | **très haute** — 5 800 lignes d'oracles déterministes non-LLM, testées |
| **verdict** | **REUSE** — le cœur de la valeur accumulée |
| **manque** | **QA design** : rien ne mesure la conformité aux `design_metrics` (elles n'existent pas encore) |

### 15 · Red Team
| | |
|---|---|
| **source actuelle** | `s6-redteam-plan.yaml` (profil mono-étape `review`) · `s11-redteam-code.yaml` · `redteam-artdirector.yaml` |
| **consommateur** | driver |
| **contrat** | **advisory, jamais juge du code** (ADR-002) |
| **réutilisabilité** | haute |
| **verdict** | **REUSE** · ⚠ **indépendance BLOCKED** — elle exigeait `council`/Qwen, hors V2. Dégradation `claude-blind` visible, jamais silencieuse |

### 16 · Evidence
| | |
|---|---|
| **source actuelle** | `verdict.py` (HMAC, 49 paramètres de surcharge) · `verify_run.py` · `studio_link.py` · `RUN_INDEX.md` append-only |
| **consommateur** | `gate` · `run_real` · driver · preflight (10 modules citent `verify_run`) |
| **preuves** | **4 tests `verdict` + 5 tests `verify` + 2 `studio_link`** ; 12 `verdict.json` signés dans les run_dirs ; traces `AUTHENTIQUE` |
| **dépendances** | `.forge_key` (**absente du V2 — à générer, jamais copier**) |
| **réutilisabilité** | **très haute** |
| **verdict** | **REUSE** — rebrancher les sorties sur `EVIDENCE/` |

### 17 · Observer
| | |
|---|---|
| **source actuelle** | `TOOLS/observer/` (40 fichiers) |
| **consommateur** | humain ; lien Forge prouvé : `from forge.anonymize_session_paths import …` |
| **preuves** | produit `lab/reports/observer/**` (vues, drifts, fiches agents) |
| **réutilisabilité** | haute |
| **verdict** | **ADAPT** — conserver l'interface réelle, réancrer les sorties sur `EVIDENCE/` |

### 18 · KB
| | |
|---|---|
| **source actuelle** | `knowledge_base/` (129 fichiers ; `catalog.json` 50 entrées, 7 `validated`, 26 propositions) · `kb_proposal.py` · `search.mjs` · `kb-validate.mjs` |
| **consommateur** | `contract.py` (injection) · `kb_proposal` (écriture propose-only) · driver · preflight · `search_usage.mjs` · `reuse_ratio.mjs` · Observer |
| **contrat** | *« une proposition sous `proposals/` n'est **jamais** servie ; servir son contenu court-circuiterait le HumanGate »* |
| **preuves** | 1 test `kb_` + 3 `learning` + `kb-validate.test.mjs` + `search.test.mjs` |
| **réutilisabilité** | **très haute** |
| **verdict** | **REUSE** — et **étendre** : c'est là que la Research doit se capitaliser pour ne pas re-chercher un genre déjà étudié |

### 19 · Boucle d'apprentissage
| | |
|---|---|
| **source actuelle** | `learning_hook.py` · `learning_memory.py` (`lesson.v2` : `cause` est un **champ**) · `kb_proposal.py` |
| **preuves** | 3 tests `learning` ; **18 leçons ratifiées sur 326** |
| **verdict** | **REUSE** — la seule boucle du système qui tourne vraiment. Goulot = la ratification humaine |

### 20 · HumanGate
| | |
|---|---|
| **source actuelle** | `forge/gate.py` (*« the FORCER brick »* — oracle vert ⇒ verdict OK signé ; rouge/absent/injouable ⇒ FAIL/BLOCKED ; *« l'appelant NE DOIT PAS poursuivre au-delà d'une porte non-OK »*) · `kb_proposal --apply --ratifie-par` |
| **consommateur** | driver ; le skill `/gate` |
| **preuves** | verdicts signés + objections conservées (`HUMANGATE_READY_WITH_OBJECTION`) |
| **dépendances** | `decision-log.md` — **absent du V2** |
| **verdict** | **REUSE** ⚠ le gate peut produire un verdict, il n'a **pas où inscrire la décision** |

### 21 · La porte de spawn
| | |
|---|---|
| **source actuelle** | `.claude/hooks/pretool_forge_guard.py` · `forge/hook_guard.py` · `forge/dispatch.py::prepare_dispatch` |
| **invariant mesuré** | ne lit **aucun fichier de contrat** : marqueur `FORGE_DISPATCH:<etape>:<run_id>` confronté au journal d'audit — `count==1` allow, `0` refus, `≥2` refus (rejeu) |
| **preuves** | **7 tests `guard` + 4 tests `spawn` + 6 `dispatch` + 11 `contract`** |
| **réutilisabilité** | **haute — et compatible avec la composition dynamique** |
| **verdict** | **REUSE** — l'invariant est *« un spawn ⇔ exactement un dispatch enregistré »*, pas *« il existe un YAML »* |

---

## Ce qui sort — reliques du workflow

| élément | preuve du retrait | verdict |
|---|---|---|
| `dispatch.ORDER` (13 étapes) | le workflow imposé lui-même | **RETIRE** |
| `dispatch.PROFILES` (19) | 5 mono-capacité = déjà des appels de capacité ; le reste = compositions préfabriquées | **MERGE** → composition dynamique |
| panel Prisme multi-lentilles (8 f.) | `--charter` jamais passé · `panel.LENSES` jamais alimenté · gel ratifié | **RETIRE** |
| île MCTS / candidate_selector (17 f.) | **0 appelant** sur les 8 modules de la chaîne · gel ratifié | **RETIRE** — remplacée par le Director |
| `wiremap_nav` (2 f.) | 0 consommateur, tous canaux | **RETIRE** |
| 7 CLI de protocole de paires | 0 dans V2 ; servaient l'**expérience sur le workflow** | **RETIRE** |
| `control_plane` | 3 fn/9 utilisées ; 1 import bloquant `contract.py:76` | **hors V2** — résolution de rôle interne |
| `council` / Qwen | import paresseux, fallback visible | **hors V2** — capacité à redéfinir si un profil l'exige |

## UNKNOWN — pas assez de preuve

| élément | ce qui manque |
|---|---|
| `reference_guard` | 11 références, **349 diffs à chaque run depuis le 2026-07-31**, et le DRIFT **n'atteint aucune décision**. Mesurer avant de trancher |
| chaîne asset (`asset_geometry`, `asset_producer`, 7 tests) | **hors du fermé transitif** de `run_real` ; contrats écrits mais `asset_dispatch` ne les charge pas |
| rail des 25 nœuds | plan de portefeuille **ou** carte de compétences ? |
| `s10d-oracle-visual` | contrat présent ; part réellement exercée non mesurée |

---

## Bilan du harvest

**Sur 21 capacités de la cible : 16 existent déjà et sont réutilisables.**

```
REUSE     11   Research/World Scan · Prisme · Art · Narration · Build · QA-oracles
               Red Team · Evidence · KB · apprentissage · porte de spawn
ADAPT      5   Blueprint(Brief) · Director(driver) · Gameplay(charter) · Wiremap · Observer
MERGE      2   Décomposition → Feature Map · PROFILES → composition
REBUILD    3   UX · jointure expected↔actual · chaînon design_metrics → projections
RETIRE     6   ORDER · panel Prisme · île MCTS · wiremap_nav · 7 CLI · (hors V2 : control_plane, council)
UNKNOWN    4   reference_guard · chaîne asset · rail · s10d
```

**Ce que ça dit du ménage.** Le travail des semaines passées n'est pas à jeter : **5 800 lignes
d'oracles déterministes testés**, une KB avec sa règle de service, une porte de spawn compatible
avec la composition dynamique, des projections déterministes verrouillées, une boucle
d'apprentissage qui tourne. **Ce qui était mal placé, ce n'était pas les capacités — c'était la
file qui les obligeait à se suivre.**

**Les trois seules constructions neuves** : le rôle **UX**, la **jointure `expected_proof ↔
actual_proof`**, et le chaînon **`design_metrics` → projections déterministes**. Aucune n'est un
framework ; les trois sont des connexions entre des pièces qui existent.

---

```
status_by_surface:
  capability_harvest:          DOCUMENTED_ONLY
  target_model:                DOCUMENTED_ONLY
  implementation:              BLOCKED
  runtime_validation:          BLOCKED
  system_design_correction:    TESTED        # verrou loop.json/economy.json lu au code
  ux_absence:                  TESTED        # recherche par mot entier, 4 formes
  test_coverage_per_capability:TESTED        # 220 tests .py + 51 .test.mjs répartis
  expected_proof_join:         NOT_FOUND
  ux_role:                     NOT_FOUND
  design_metrics_chain:        NOT_FOUND
```
`software_verdict: OK` (document) · `evidence_verdict: MECHANICAL_VALIDATION_ONLY` ·
`claim_verdict: NO_CLAIM_ALLOWED` · `no_global_ready_verdict: true`

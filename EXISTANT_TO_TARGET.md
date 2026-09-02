# EXISTANT → TARGET — matrice ligne par ligne

*2026-09-01 · DOCUMENTED_ONLY · aucun code, aucun renommage, aucun déplacement, aucune suppression.
Dépôt source `feeb29cb`, non touché. **On copie, jamais on ne déplace.***

---

## Verrouillé (Pierre, 2026-09-01)

`Q1 → F1` · `GAME_BLUEPRINT.game_flow` · `FEATURE_MAP ≠ WIREMAP` · Research obligatoire à l'entrée ·
World Scan / Prisme = capacités du Director · relations ≠ portes · Art et Gameplay = intelligences
distinctes · **optimal ≠ minimal** · `loop.json` reste une projection déterministe.

---

## Q4 — mesure de réutilisabilité de `mandatory_read` : **réponse en deux temps**

> *Peut-on réutiliser `mandatory_read` comme primitive de synchronisation sans lui faire porter des
> responsabilités qu'il ne possède pas ?*

**`mandatory_read` seul : NON.** Sa destination est `prompt` (SCHEMA §75) — il est *rendu comme
section de texte* par `contract.py:525`. Sa qualité de « précondition dure » est **doctrinale**, pas
mécanique. Rien ne vérifie que l'agent a lu quoi que ce soit.

**`mandatory_read` + `knowledge_trace --verify` : OUI — et le plus dur est déjà construit.**
`knowledge_trace.mjs` porte une **sonde ANTI-THÉÂTRE**, verbatim :
> *« pour chaque item de la trace, cherche une **preuve de consommation réelle** dans les fichiers
> du run. `ref` doit apparaître **textuellement** quelque part. Un item tracé mais introuvable =
> FAUX POSITIF de trace = échec visible (exit 1), jamais un vert par défaut. »*

`mandatory_read` est l'une de ses 4 `ALLOWED_SOURCES`. Et `verify_run._check_knowledge_trace` la
câble en **gate DUR** — *« même sévérité que la preuve mutation »* — repris par `driver.py:4667`.

### Mais la mesure révèle le miroir exact de `reference_guard`
```
knowledge_trace.json présent dans   1 run_dir sur 89
appels d'écriture en production      0   (verify_run et driver ne font que LIRE)
trace absente                        avertissement NON BLOQUANT
statut du protocole                  PROPOSED, en attente gate Pierre
```

| | producteur | consommateur |
|---|---|---|
| `reference_guard` | **349 diffs / run** | **0 décision** |
| `knowledge_trace` | **1 run sur 89** | **gate DUR câblé** |

> **Le studio a un capteur sans destinataire et un destinataire sans capteur.** Ce n'est pas deux
> pannes, c'est deux moitiés du même défaut : *déclaré ≠ exécuté*.

### Ce que N2 exige réellement — trois gestes, pas un mécanisme
1. **un émetteur** : le journal d'amendements écrit des items de trace (`source: mandatory_read`
   ou une 5ᵉ source `amendment`) — **c'est la seule pièce manquante** ;
2. **rendre `trace absente` bloquante** pour une capacité qui a été notifiée — une condition, pas
   un système ;
3. **ratifier** le protocole `KNOWLEDGE_RESOLVER_V1`, aujourd'hui PROPOSED.

**N2 ne demande pas de construire une notification. Il demande de brancher un émetteur sur une
vérification qui existe, est testée, et bloque déjà.**

---

## La matrice — composant existant → rôle cible

`REUSE` tel quel · `ADAPT` bonne capacité, mauvaise interface · `MERGE` fusionné ·
`REBUILD` à construire · `RETIRE` relique · `UNKNOWN` preuve insuffisante.

| # | composant existant | **consommateur réel mesuré** | rôle cible | verdict |
|---|---|---|---|---|
| 1 | `FORGE_PROJECT_INPUT_V0` + `check_project_brief` | `run_real` (23 réf.), pré-vol fail-closed **avant dépense LLM** · `context_manifest` (4) · `static_oracles` (4) | sections `vision/identity/constraints` du Blueprint | **ADAPT** |
| 2 | `s0-contrat` → `charter.yaml` | `s4-archi` (`mandatory_read`), `s3`, driver | section `intent/charter` | **ADAPT** |
| 3 | `s2-worldscan` (`run: WebSearch, WebFetch`) | profils `amont_only`, `amont_narratif`, `gm_worldscan` | capacité **Research** + World Scan | **REUSE** ⚠ verrou Q2 |
| 4 | `s1-prisme` + `prisme.json` + `check_prisme.mjs` | driver · **source des `source_ref` de `s3`** · `loop_spec.mjs` | capacité **Prisme** | **REUSE** |
| 5 | `s3-decompo` → `featuremap.json` | `s5-wiremap`, `s10c`, `s10s` | section `feature_map` ; sa **règle dure** devient invariant du Blueprint | **MERGE** |
| 6 | *(rien)* | — | section **`game_flow`** — qui déclenche quoi, quel effet, où le joueur reprend la main | **REBUILD** |
| 7 | `s4-archi` → `blueprint.json` | `s5-wiremap` (`mandatory_read`), `s10b-oracle-archi` | **`ARCHITECTURE_CONTRACT`** — après Feature Map + Flow | **ADAPT** |
| 8 | `s5-wiremap` → `wiremap.json` | `s10c`, `s10s`, builder | **WIREMAP** — où c'est réellement | **REUSE** |
| 9 | `loop_spec.mjs` → `loop.json` | `product_oracle_godot.run_player_loop` (rejeu par bot), sha256 vs `03_WORLD/loop.json` | **inchangé** — projection déterministe, observabilité | **REUSE** |
| 10 | `game_master_schema.mjs` → `economy.json` | driver (comparaison sha256), builder (contexte) | **inchangé** — projection déterministe | **REUSE** |
| 11 | `s2.5-artbible` + `redteam-artdirector` | driver ; `art_bible.md` injecté au builder | capacité **Art Direction** | **REUSE** |
| 12 | `s2.6-story-bible` · `s2.7-gm-worldscan` | driver ; `gm_worldscan.json` → projection `economy.json` | capacité **Narration/GM** | **REUSE** |
| 13 | *(rien — `\bUX\b` : 2 contrats, et seulement comme *chose observée chez les concurrents*)* | — | capacité **UX** de première classe | **REBUILD** |
| 14 | `s9-build` ×4 + `forge/standard/` | driver | **workers** du Build Orchestrator | **REUSE** |
| 15 | `oracle.py` · `static_oracles` · `standard_oracles` · `product_oracle` · `product_oracle_godot` · `mutation` · `mutation_proof` — ≈5 800 l. | `gate.forge_gate`, driver · **14 tests `oracle` + 13 `mutation`** | **QA mécanique et visuelle** | **REUSE** |
| 16 | *(rien)* | — | **QA design** — conformité aux `design_metrics` | **REBUILD** |
| 17 | `s6-redteam-plan` · `s11-redteam-code` | driver ; advisory | **Red Team** | **REUSE** ⚠ indépendance : 1 profil sur 19 |
| 18 | `verdict.py` HMAC · `verify_run.py` · `studio_link.py` | `gate`, `run_real`, driver, preflight — **10 modules citent `verify_run`** | **EVIDENCE** | **REUSE** |
| 19 | *(rien — `featuremap` 26 ids ⟷ `wiremap` 25 entrées, **intersection 0**)* | — | **jointure `expected_proof ↔ actual_proof`** | **REBUILD** |
| 20 | `knowledge_trace.mjs --verify` | `verify_run._check_knowledge_trace` → **gate DUR** · `driver.py:4667` | **socle de la notification N2** | **REUSE** — il manque l'**émetteur** |
| 21 | `mandatory_read` (champ) | `contract.py:525` → **prompt** ; `context_manifest` (sha256 des sources path-like) | **précondition de convocation** | **ADAPT** — doctrinal aujourd'hui |
| 22 | `design_questions.json` | matérialisé au RUN 1 (2 questions ART→GM répondues) | canal **QUESTION** | **ADAPT** |
| 23 | objections dans les verdicts (`HUMANGATE_READY_WITH_OBJECTION`) | `gate`, HumanGate | canal **OBJECTION** | **REUSE** |
| 24 | *(rien)* | — | **journal d'amendements** (émetteur N2) | **REBUILD** |
| 25 | `knowledge_base/` + `kb_proposal` propose-only | `contract.py` (injection), driver, preflight, `search_usage.mjs`, `reuse_ratio.mjs`, observer | **KB** + capitalisation Research | **REUSE** |
| 26 | `learning_hook` · `learning_memory` · `kb_proposal` | driver — **18 leçons ratifiées / 326** | boucle d'apprentissage | **REUSE** |
| 27 | `gate.py` (*the FORCER brick*) | driver, skill `/gate` | **HUMAN_GATE** | **REUSE** ⚠ `decision-log` absent du V2 |
| 28 | `TOOLS/observer/` (40 f.) | humain ; `from forge.anonymize_session_paths import …` | **Observer** — sorties vers `EVIDENCE/` | **ADAPT** |
| 29 | `hook_guard` + `prepare_dispatch` + `.claude/hooks` | porte fail-closed — **7 tests `guard` + 4 `spawn` + 6 `dispatch` + 11 `contract`** | **porte de spawn** — invariant *un spawn ⇔ un dispatch enregistré* | **REUSE** |
| 30 | `escalate.py` | driver (haiku→sonnet→opus) | politique de tier | **REUSE** |
| 31 | `contracts/*.yaml` — 17 champs, 28 fichiers | `load_contract` + porte | **chartes de rôle** | **REUSE — le socle** |
| 32 | `dispatch.ORDER` (13 étapes) | `driver.py:348` | — | **RETIRE** |
| 33 | `dispatch.PROFILES` (19, dont 5 mono-capacité) | `driver.py:348` | composition dynamique par Fable | **MERGE** |
| 34 | panel Prisme (`panel.py`, `prisme/`, 8 f.) | **aucun** — `--charter` jamais passé, `LENSES` jamais alimenté | — | **RETIRE** |
| 35 | île MCTS (`candidate_selector`…, 17 f.) | **0 appelant** sur les 8 modules de la chaîne | remplacée par le Director | **RETIRE** |
| 36 | `wiremap_nav` (2 f.) | **0**, tous canaux | — | **RETIRE** |
| 37 | contrat `s10d-oracle-visual` | **absent de `ORDER` et des 19 profils** | *(la capacité vit dans `product_oracle_godot`)* | **RETIRE** |
| 38 | `reference_guard` (11 réf. de code) | **0 consommateur de décision** — 349 diffs/run | — | **RETIRE** |
| 39 | 7 CLI de protocole de paires | **0 dans V2** — servaient l'expérience *sur le workflow* | — | **RETIRE** |
| 40 | `control_plane` · `council` · `openclaw` | 3 fn/9 · import paresseux · legacy | résolution de rôle interne à la Forge | **hors V2** |
| 41 | chaîne asset (`asset_geometry`, `asset_producer`) | **hors du fermé transitif** de `run_real` ; `asset_spec_author` résout, `asset_producer` = sous-processus Blender (correct) | capacité optionnelle | **REUSE** à la demande |
| 42 | rail des 25 nœuds | `RAIL_REGISTER.md` | **catalogue de compétences**, plus une file | **ADAPT** |

### Bilan
```
REUSE   19      ADAPT 7      MERGE 2      REBUILD 5      RETIRE 7      hors V2 1      UNKNOWN 1
```
**Cinq constructions, et aucune n'est un framework** : `game_flow` (une section) · UX (un rôle) ·
QA design (un volet) · la jointure `expected ↔ actual` (un anneau) · le journal d'amendements
(un émetteur sur une vérification déjà bloquante).

---

## Prochain trou structurel à spécifier

```
feature X → requirement X → implementation X → expected_proof X → actual_proof X
                                            ╲______ 0 id partagé ______╱
```
On peut avoir une feature conçue, une architecture, une implémentation **et** une preuve réelle,
sans pouvoir démontrer mécaniquement qu'elles parlent de la même chose. À spécifier, pas encore à
construire.

## Questions ouvertes
| # | question | état |
|---|---|---|
| Q2 | verrou *« World Scan hors périmètre »* + R8 vs Research obligatoire | **ouverte — décision explicite séparée requise, jamais levée implicitement** |
| Q3 | qui prouve la variance d'une `design_metric` avant qu'elle devienne une cible | ouverte |
| Q4 | N2 + `mandatory_read` | **mesuré ci-dessus** — décision : ratifier le protocole + écrire l'émetteur |
| Q5 | qui décide du prochain jeu (rail = catalogue) | ouverte |

```
status_by_surface:
  mandatory_read_reusability:  TESTED      # destination prompt ; garantie = knowledge_trace --verify
  knowledge_trace_usage:       TESTED      # 1 run_dir / 89 ; 0 écrivain en production
  existant_to_target_matrix:   DOCUMENTED_ONLY
  expected_actual_join:        NOT_FOUND
  amendment_log:               NOT_FOUND
  ux · qa_design · game_flow:  NOT_FOUND
  implementation:              BLOCKED
```
`software_verdict: OK` (document) · `evidence_verdict: MECHANICAL_VALIDATION_ONLY` ·
`claim_verdict: NO_CLAIM_ALLOWED` · `no_global_ready_verdict: true`

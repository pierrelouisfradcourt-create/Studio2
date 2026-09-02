# Lot F — Boucle de complétion mutuelle Art ↔ GM (pré-WireMap) : « il me manque X » comme mécanisme normal

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. TDD, fixtures réelles (run 9 archivé).
> Jamais de commit par un sous-agent ; un commit de clôture (gate Pierre). **Aucune station, aucun agent nouveau, aucun oracle LLM.**
> Ce plan est PROPOSED : rien n'est engagé sans GO Pierre.

*Date : 2026-08-23 · Source : doctrine Pierre (mémoire `mutual_completion_loop_doctrine`) : le jeu émerge de l'échange ; pas de
design freeze tant qu'un pilier a une question ouverte ; le WireMap se déclenche à la convergence.*

## Ce qui existe (mesuré) et ce qui manque
| Besoin | Existe ? | Pièce minimale |
|---|---|---|
| Ré-activer s2.5 et s2.7 plusieurs fois dans un run | **Non** : contrat = `contracts/<etape>.yaml` 1:1 ; `state.steps` = dict par id ; aucun alias | **Alias d'étape** : `s2.5-artbible-r2`, `s2.7-gm-worldscan-r2` → même contrat ; manifeste et `_UPSTREAM_BY_STEP` par alias |
| « Il me manque X » adressé à l'autre pilier | **Non** (seulement `artist_requirements` → `art_response`, inter-run, Lot B) | **`design_questions.json`** partagé, écrit par les deux (append par ronde), validé à la matérialisation |
| État intermédiaire PARTIAL / OPEN / BLOCKING / SHARED % | Non | calculé déterministement depuis `design_questions.json` → `design_state.json` (reçu du driver) |
| Gate de freeze avant le WireMap | Non (s5 vérifie la forme de la WireMap, pas la convergence) | **`design_freeze`** : s1 (Prisme) refuse de tourner si `blocking > 0` ou si un pilier n'a pas déclaré `ready_for_freeze` |
| Boucle post-WireMap Art ↔ GM ↔ réalité | Partiellement : `art_response` + gates Lot B + HumanGate | inchangé dans ce lot |

## Topologie cible (profil `full_godot_content`, 19 étapes ; narratif inchangé)
```text
s0 → s2 World Scan → s2.6 Story Bible
   → s2.5 Art (vue 1 : « voilà ce que je vois » + questions → GM)
   → s2.7 GM (vue 1 : game_master PARTIAL autorisé + réponses + questions → Art)
   → s2.5-r2 Art (réponses + art_bible complétée + questions résiduelles)
   → s2.7-r2 GM (réponses + game_master COMPLET + ready_for_freeze)
   → [design_freeze : blocking == 0 ∧ ready_for_freeze des deux ∧ game_master valide] → s1 Prisme → s3 → s4 → s5 → …
```
Nombre de rondes : **2 fixes** (R1 vue, R2 complétion), extensible à 3 par profil si la convergence n'est pas atteinte — jamais
une boucle sans borne (coût, zombies). Si après R2 il reste un `blocking`, le run est **HALTED « design non convergé »** avec la liste
des questions ouvertes : c'est un résultat, pas un échec de la chaîne.

## L'artefact `design_questions.json` (forme figée)
```text
{ "schema_version": 1, "round": 2,
  "questions": [ { "id": "q_gm_001", "from": "GM", "to": "ART", "round": 1,
                   "about": "grey_blocks.garden", "missing": ["états visuels LOCKED/AVAILABLE/ACTIVE/FULL", "feedback d'ouverture"],
                   "why": "le joueur doit comprendre pourquoi il ne peut pas encore entrer",
                   "blocking": true,
                   "answer": { "round": 2, "by": "ART", "ref": "art_bible:character_states#garden", "text": "…" } | null } ],
  "declarations": { "ART": { "round": 2, "ready_for_freeze": true, "open_to_gm": 0 },
                    "GM":  { "round": 2, "ready_for_freeze": true, "open_to_art": 0 } } }
```
Règles déterministes : `about` résout dans l'artefact du demandeur (`gm_worldscan:game_master.*` ou `art_bible:<section>`) ; une
question `blocking` sans `answer.ref` résoluble = ouverte ; `ready_for_freeze` d'un pilier est refusé s'il lui reste une question
reçue sans réponse ; `SHARED_DESIGN %` = questions répondues / questions posées (affiché, jamais gaté).

## Tâches (TDD, fichiers, baselines)
- **T1 alias d'étape** — `contract.py` (`load_contract` résout `<etape>-r<N>` → `<etape>.yaml`), `context_manifest.py`, `dispatch.py`
  (profil 19 étapes, timeouts par alias), `run_real.py` (`_UPSTREAM_BY_STEP` : s2.5-r2 ← art_bible.md (r1), gm_worldscan.json (r1),
  design_questions.json ; s2.7-r2 ← art_bible.md (r2), design_questions.json ; s1 ← design_questions.json en plus) ; artefacts : r2
  ÉCRASE art_bible.md / gm_worldscan.json (une seule vérité par run ; les r1 archivés `artifacts/*-r1.*`). Tests : dry-run 19 ;
  manifeste d'un alias cite le bon contrat et le bon round.
- **T2 `design_questions.json`** — validateur de matérialisation (forme + résolution des `about`/`answer.ref`), produit par s2.5 et s2.7
  (chaque étape lit la version courante, APPEND ses questions/réponses, réécrit) ; `design_state.json` calculé par l'exécuteur après
  chaque étape de la boucle (PARTIAL/OPEN/BLOCKING/SHARED) ; contrats s2.5/s2.7 : sections « ce que je vois », « ce qui me manque »
  (questions CAUSALES, jamais des cases), « réponses », `ready_for_freeze` ; game_master PARTIAL autorisé en R1 (schéma : blocs
  absents tolérés si `design_state.round == 1`), COMPLET exigé en R2.
- **T3 gate `design_freeze`** — dans le driver avant s1 : `blocking == 0` ∧ deux `ready_for_freeze` ∧ `game_master` valide ; sinon
  HALTED « design non convergé » + liste. Test : fixture avec 1 blocking → HALTED ; fixture convergée → s1 tourne.
- **T4 Kitten Clicker** — `tasks.json` s2.5/s2.7 : le Gameplay Loop & Content Contract V1.1b est la GRAINE partagée (les deux le
  reçoivent via la tâche) ; la boucle doit fermer au moins les questions que le test de reconstruction a laissées hors périmètre
  (palette, animations, états visuels des lieux) côté Art, et (boucles, métriques, preuves) côté GM.
- **T5 confrontation + commit + run 10** (Lot E absorbé) : premier run avec boucle ; mesure : nombre de questions par ronde,
  blocking résiduels, `SHARED_DESIGN %`, et si le freeze est atteint en 2 rondes.

## Hors périmètre
Boucle post-WireMap (déjà partiellement couverte : `art_response`, gates, HumanGate) · 3ᵉ ronde automatique · station de médiation ·
tout oracle LLM de « qualité du design » (la convergence est déclarée par les agents et vérifiée par la forme, la qualité reste au
HumanGate).

## Risques nommés
- Coût : 2 étapes Opus de plus par run (s2.7-r2 ≈ +3 $, s2.5-r2 ≈ +3 $).
- Convergence déclarée de complaisance (« ready » sans avoir répondu) : bloquée par la règle « ready refusé s'il reste une question
  reçue sans réponse » — mais une réponse VIDE de sens passe la forme ; c'est le HumanGate et le test de reconstruction qui jugent.
- Les alias touchent la matérialisation (`_ARTIFACT_BY_STEP` par id) : à couvrir par test.

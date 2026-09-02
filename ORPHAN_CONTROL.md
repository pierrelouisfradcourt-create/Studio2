# CONTRÔLE D'ORPHELINS — 42 lignes contre la cible

*2026-09-01 · DOCUMENTED_ONLY · aucun code, aucun déplacement, aucune suppression.
Dépôt source `feeb29cb`, non touché.*

**Objet** : dernier contrôle avant de toucher au dépôt. Pour chacune des 42 lignes de
`EXISTANT_TO_TARGET.md` — a-t-elle **un consommateur cible** et **une place dans le graphe de
communication** ? Une capacité « conservée » sans consommateur cible est un orphelin déguisé.

Statuts : `ANCRÉ` (consommateur cible + place dans le graphe) · `CONDITIONNEL` (dépend d'une
décision ouverte) · **`ORPHELIN`** (aucun consommateur cible) · `SORTANT` (retiré, sans objet).

---

## Les trois trouvailles

### ⚠ O-1 · `economy.json` dépend d'une capacité **optionnelle** — trou structurel
```
run_real._materialize_economy :
  « Après matérialisation OK de gm_worldscan.json (s2.7-gm-worldscan), dérive economy.json
    via game_master_schema.mjs »
  → « gm_worldscan.json absent — economy.json non derivable »
```
Dans la cible, **Narration/GM est optionnelle** (*« un jeu sans narration n'appelle pas la
Narration »*). Or l'économie du jeu **n'est dérivable que si le GM a été convoqué**.
**Un tower defense sans narration n'aurait donc pas d'économie projetée.**

Le nom trompe : `s2.7-gm-worldscan` s'appelle *Game Master* mais **produit l'économie**. Ce n'est
pas de la narration — **c'est du System Design**. Ça explique aussi pourquoi System Design était si
difficile à placer : la capacité existe, elle est cachée sous un nom de narration.

**Trois issues, non tranchées** :
| # | issue | conséquence |
|---|---|---|
| A | **GM n'est pas optionnel** — il porte l'économie | contredit « capacités à la demande » |
| B | **Scinder** : la partie économique de `s2.7` rejoint System Design, la narration reste optionnelle | requalification de contrat, pas de code neuf |
| C | `economy.json` acquiert une **seconde source** : la section `systems` du Blueprint | nouvelle dérivation à spécifier |

*Je penche pour **B** — c'est une requalification de ce qui existe, pas une construction. Mais c'est
ta décision.*

### O-2 · `knowledge_packet.json` — producteur **hors Forge**, à nommer
```
occurrences dans scripts/forge (py/mjs, hors tests) : 0
présent dans les runs                                : 3 fichiers
cité en mandatory_read par                           : s3-decompo, s4-archi
                                                       « ADVISORY jamais prescriptif »
```
Quelque chose l'écrit — mais **pas la Forge**. Vraisemblablement le skill `/world-scan`
(advisory-only). Ce n'est pas un orphelin : c'est un artefact dont **le producteur est hors du
graphe mesuré**. Dans la cible, il faut le nommer : **c'est la capacité Research**. Sinon on
conserve un `mandatory_read` pointant vers un fichier que personne du modèle ne produit.

### ✅ O-3 · `product_snapshot.md` — le précédent qui montre qu'on sait fermer ce trou
```
run_real.py:2222 « product_snapshot.md avait un validateur (check_prisme.mjs), deux
consommateurs déclarés (s2.5-artbible, s3-decompo) et AUCUN producteur »
→ mécanisme JUMEAU décidé avec Pierre, GO 2026-08-13 : matérialiseur TEXTE
```
Exactement le motif *« validateur sans producteur »*. **Il a été fermé**, avec un patron nommé et
une preuve advisory jointe au reçu. C'est le modèle à réappliquer pour O-1 et O-2.

---

## Le contrôle, ligne par ligne

| # | composant | consommateur **cible** | place dans le graphe | statut |
|---|---|---|---|---|
| 1 | `FORGE_PROJECT_INPUT_V0` + `check_project_brief` | Fable, toutes capacités | L1 `HUMAN → FABLE` | ANCRÉ |
| 2 | `s0-contrat` → charter | Architect (`mandatory_read`), Feature Map | L4 · section `intent` | ANCRÉ |
| 3 | `s2-worldscan` | Fable, design | L2 · capacité Research | **CONDITIONNEL — Q2** |
| 4 | `s1-prisme` + `prisme.json` | Feature Map (`source_ref`), `loop_spec` | L3 · capacité Prisme | ANCRÉ |
| 5 | `s3-decompo` → `featuremap` | Architect, Build, QA | L4/L5 · section `feature_map` | ANCRÉ |
| 6 | *(à construire)* `game_flow` | **Architect**, QA | L5 · section du Blueprint | ANCRÉ (par construction) |
| 7 | `s4-archi` → `ARCHITECTURE_CONTRACT` | Build, Wiremap | L5 | ANCRÉ |
| 8 | `s5-wiremap` → `wiremap.json` | QA (`s10c`, `s10s`), Evidence | L6 | ANCRÉ |
| 9 | `loop_spec.mjs` → `loop.json` | `product_oracle_godot.run_player_loop` | L6 · QA mécanique | ANCRÉ |
| 10 | `game_master_schema.mjs` → `economy.json` | driver (sha256), builder | L5/L6 | **⚠ O-1** |
| 11 | `s2.5-artbible` + red-team art | Build, QA visuelle | L3/L5 · Art Direction | ANCRÉ |
| 12 | `s2.6-story-bible` · `s2.7-gm-worldscan` | Narration ; **et l'économie (O-1)** | L3 | **⚠ O-1** |
| 13 | *(à construire)* UX | Gameplay, Art, Architect, QA | L3 | ANCRÉ (par construction) |
| 14 | `s9-build` ×4 + `forge/standard/` | QA, Evidence | L5→L6 | ANCRÉ |
| 15 | oracles (≈5 800 l.) | Fable, Human via Evidence | L6/L7 | ANCRÉ |
| 16 | *(à construire)* QA design | Fable | L7 · dépend de `design_metrics` | **CONDITIONNEL — Q3** |
| 17 | `s6` · `s11` red-team | Fable (objections) | L3/L7 | ANCRÉ |
| 18 | `verdict` HMAC · `verify_run` · `studio_link` | Fable, Human | L6→L7→L8 | ANCRÉ |
| 19 | *(à construire)* jointure `expected ↔ actual` | porte de suffisance, critère de sortie | L5 + L8 | ANCRÉ (par construction) |
| 20 | `knowledge_trace --verify` | `verify_run` → **gate DUR** | L3 · socle N2 | ANCRÉ — **il manque l'émetteur** |
| 21 | `mandatory_read` | convocation d'une capacité | L2/L3 | ANCRÉ |
| 22 | `design_questions.json` | destinataire, Fable | L3 · canal QUESTION | ANCRÉ |
| 23 | objections dans les verdicts | Fable, Human | L3/L8 · canal OBJECTION | ANCRÉ |
| 24 | *(à construire)* journal d'amendements | toutes capacités notifiées | L3 · émetteur N2 | ANCRÉ (par construction) |
| 25 | `knowledge_base/` + `kb_proposal` | `contract.py` (injection), Research | L3/L4 | ANCRÉ |
| 26 | boucle d'apprentissage | KB via HumanGate | L7→I7 | ANCRÉ |
| 27 | `gate.py` | Pierre | L8 | ANCRÉ — ⚠ `decision-log` absent |
| 28 | `TOOLS/observer/` | Fable, Human | L7 | ANCRÉ |
| 29 | porte de spawn (`hook_guard`, `prepare_dispatch`) | toute convocation | L2 | ANCRÉ |
| 30 | `escalate.py` | Fable | L2 · politique de tier | ANCRÉ |
| 31 | 28 contrats, 17 champs | `load_contract`, porte | L2 · chartes de rôle | ANCRÉ |
| 32 | `dispatch.ORDER` | — | — | SORTANT |
| 33 | `dispatch.PROFILES` | Fable (composition) | L2 | ANCRÉ (fusionné) |
| 34 | panel Prisme (8 f.) | — | — | SORTANT |
| 35 | île MCTS (17 f.) | — | — | SORTANT |
| 36 | `wiremap_nav` (2 f.) | — | — | SORTANT |
| 37 | contrat `s10d` | — *(capacité vit dans `product_oracle_godot`)* | — | SORTANT |
| 38 | `reference_guard` | — | — | SORTANT |
| 39 | 7 CLI de protocole | — | — | SORTANT |
| 40 | `control_plane` · `council` · `openclaw` | — | — | SORTANT (hors V2) |
| 41 | chaîne asset | Art Direction via `asset_requests.json` | L3/L5 · capacité optionnelle | ANCRÉ |
| 42 | rail des 25 nœuds | **personne dans la cible** | aucune | **ORPHELIN — Q5** |
| — | `knowledge_packet.json` | Architect, Feature Map (`mandatory_read`) | L2 — **producteur hors graphe** | **⚠ O-2** |

### Bilan du contrôle
```
ANCRÉ         30      dont 5 "par construction" (les REBUILD)
CONDITIONNEL   2      Research (Q2) · QA design (Q3)
ORPHELIN       1      le rail (Q5)
ATTENTION      2      O-1 economy⟸GM optionnel · O-2 knowledge_packet sans producteur nommé
SORTANT        9
```

**Un seul vrai orphelin sur 42.** Le rail : conservé comme catalogue de compétences, mais **personne
ne le consomme dans le graphe cible** tant que Q5 — *qui décide du prochain jeu ?* — n'est pas
tranchée. Il n'est pas faux, il est **sans destinataire**. Exactement le motif `reference_guard`.

---

## L'ordre logique, verrouillé

```
1. TARGET MODEL                    ✅ fait
2. COMMUNICATION CONTRACT          ← prochain
3. TRACE / CONSUMPTION CONTRACT
4. EXPECTED ↔ ACTUAL PROOF CONTRACT
5. EXISTANT → TARGET               ✅ fait + contrôlé ici
6. seulement ensuite : patch
```
**Le journal d'amendements et la jointure de preuve ne s'implémentent pas ensemble** — on ne
fabrique pas une mécanique avant d'avoir défini ce qu'elle doit prouver.

## Décisions restant à prendre — par nature

| # | question | nature |
|---|---|---|
| **O-1** | GM non optionnel · scinder économie/narration · seconde source pour `economy.json` | **structurelle** — révélée par ce contrôle |
| **O-2** | nommer Research comme producteur de `knowledge_packet.json` | inscription |
| **Q2** | **R8 est-il encore une contrainte du modèle cible, ou l'était-il d'une version antérieure du Forge ?** | **gouvernance** — décision explicite séparée, jamais déduite |
| Q3 | qui prouve la variance d'une `design_metric` | technique |
| Q4 | N2 — émetteur + blocage si non consommé | **conceptuellement résolu**, reste à ratifier le protocole PROPOSED |
| Q5 | qui décide du prochain jeu | gouvernance — **débloque le rail** |

```
status_by_surface:
  orphan_control:            TESTED       # 42 lignes confrontées au graphe cible
  economy_gm_dependency:     TESTED       # « gm_worldscan.json absent — economy.json non derivable »
  knowledge_packet_producer: TESTED       # 0 occurrence Forge, 3 fichiers présents
  product_snapshot_precedent:TESTED       # trou identique déjà fermé (GO Pierre 2026-08-13)
  rail_target_consumer:      NOT_FOUND
  amendment_log_emitter:     NOT_FOUND
  implementation:            BLOCKED
```
`software_verdict: OK` (document) · `evidence_verdict: MECHANICAL_VALIDATION_ONLY` ·
`claim_verdict: NO_CLAIM_ALLOWED` · `no_global_ready_verdict: true`

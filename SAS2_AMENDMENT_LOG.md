# SAS 2 — AMENDMENT / NOTIFICATION LOG

*2026-09-02 · **SPÉCIFICATION UNIQUEMENT** · aucun code, aucun fichier créé dans le dépôt source,
aucun renommage. Cinq sujets, et rien d'autre.*

## Préflight
```
dépôt   C:\TACTICAL_CHESS_STUDIO   branche master
HEAD    feeb29cb   (2026-09-01 16:33:44 +0200)
status  76 lignes  ·  dérive depuis le snapshot du sas 1 : 0 commit
```
Le dépôt n'a pas bougé depuis la clôture du sas 1. R6 satisfaite.

---

## 0 · Trois contraintes du cadre ratifié qui gouvernent ce sas

`KNOWLEDGE_RESOLVER_V1_PROTOCOL.md` §1 — *« Cadre ratifié (Pierre, 2026-07-20 — verbatim
d'intention) »*. Elles ne sont pas négociables ici, elles bornent la spécification.

| # | règle, verbatim | ce qu'elle impose au sas 2 |
|---|---|---|
| **C1** | *« Rasoir à 4 conditions : déterministe · recomputable depuis ses entrées · **append-only / non destructif** · non liant »* | le journal doit passer le rasoir |
| **C2** | *« **Règle anti-couches** : aucun nouveau composant s'il ne remplace pas explicitement plusieurs composants existants. Priorité : consolidation et preuve »* | le journal doit **consolider**, pas s'ajouter |
| **C3** | *« Explicitement hors V1 : […] **toute écriture par l'outillage** »* — mais `knowledge_trace.json` est *« déposé […] **par l'orchestrateur** au moment du run »* | l'émetteur est **un geste de l'orchestrateur**, jamais un outil qui écrit de lui-même |

---

## 1 · ÉMETTEUR — spécification

### Qui émet
**L'orchestrateur (Fable), jamais un outil autonome.** C3 l'exige, et c'est cohérent avec le modèle
déjà verrouillé : *Claude Code est l'opérateur, `forge/` est le paquet*. Aucun daemon, aucun
watcher, aucune écriture spontanée.

### Ce que l'émission fait — deux écritures distinctes, jamais confondues
```
1. LE MESSAGE          → JOURNAL, hors run_dir (J1)          append-only
   {id, type, from, to[], subject, reason, impact[], evidence_ref[], blocking, issued_at}

2. L'ITEM DE TRACE     → knowledge_trace.json, DANS le run_dir (obligé, cf. §2)
   {source, ref: <id du message>, provenance, valid_as_of, reason}
   — un item par capacité destinataire effectivement convoquée
```
Le premier dit *ce qui a été décidé*. Le second dit *à qui on l'a opposé*. Les séparer est ce qui
rend l'acquittement vérifiable.

### Interface — elle existe déjà, entièrement
```
writeTrace(repoRoot, runDirArg, items, opts)     export programmatique
node knowledge_trace.mjs write <run_dir> <items.json>       CLI
validateTraceItems(items)                        schéma strict AVANT écriture ; invalide ⇒ RIEN n'est écrit
```
**L'émetteur n'a aucun mécanisme d'écriture à construire pour la trace.** Il lui reste à écrire le
journal — un fichier append-only, hors run_dir.

### C2 — ce que le journal remplace *(sinon il n'a pas le droit d'exister)*
| canal actuel | état | devient |
|---|---|---|
| `design_questions.json` | matérialisé au RUN 1, 2 questions ART→GM répondues — **un fichier par run, aucun lecteur transversal** | entrées `type: question` du journal |
| objections dans les verdicts | conservées, mais **en fin de chaîne seulement** | entrées `type: objection` |
| amendements | **aucun canal** | entrées `type: amendment` |

> Le journal **unifie deux canaux qui s'ignorent et en absorbe un troisième qui n'existait pas.**
> C'est exactement l'argument qui a justifié `knowledge_trace` — *« unifie 3 lecteurs qui
> s'ignorent »*. **C2 est satisfaite par consolidation, pas par exception.**

### C1 — le rasoir, ligne à ligne
| condition | le journal |
|---|---|
| déterministe | ✔ un message, un `id`, aucun calcul |
| recomputable depuis ses entrées | ✔ le journal EST l'entrée ; la trace en dérive |
| **append-only / non destructif** | ✔ et c'est déjà une règle du protocole : *une objection rejetée est conservée, jamais effacée* |
| non liant | ✔ il ne fait pas doctrine — il transporte |

---

## 2 · J1 — emplacement, et pourquoi il ne heurte aucune garde

**Mesure décisive** : `writeTrace` **refuse d'écrire hors de `lab/forge_runs/`** —
> *« run_dir hors zone autorisée : … ne résout pas sous `lab/forge_runs/` »*

Ce n'est **pas** un obstacle à J1, parce que ce sont **deux fichiers différents** :

| fichier | emplacement | pourquoi |
|---|---|---|
| `knowledge_trace.json` | **DANS** le run_dir — imposé par la garde | déjà exclu du corpus : `listFilesRecursive(absRunDir, tracePath)` |
| **le journal** | **HORS** du run_dir — `EVIDENCE/amendments/` | s'il y était, la `ref` s'y trouverait par construction → faux `FOUND` (F-1) |

> **J1 ne demande aucune modification de la sonde ni de sa garde.** Il demande que le journal soit
> écrit ailleurs — une décision d'emplacement, garantie par le contrat, pas par le code.

⚠ **Ce que J1 ne résout pas** : F-2, le prompt. La `ref` apparaîtra toujours dans
`context/prompt_<etape>_a<n>.txt`, qui est dans le corpus. **Seule la règle d'acquittement du
sas 1 le ferme** — la ref doit être dans l'artefact désigné, pas dans le prompt.

---

## 3 · P1 — advisory d'abord, avec son point de mesure

**Correction assumée** : je proposais `trace absente → BLOCKED` d'emblée. Le précédent ratifié du
2026-07-26 impose l'inverse — *advisory + point de mesure d'abord, gate dur comme décision
ultérieure et distincte*.

### Le point de mesure, calqué sur le précédent
`SKIPPED_VALIDATION` est arrivé avec `skipped_validation_status(agent_output)` → trois états
`filled / declared_empty / absent`. Le pendant exact :

```
consumption_status(message, capability, run_dir) → trois états

  consumed             la ref est dans l'artefact DÉSIGNÉ de la capacité
  not_consumed         la capacité a produit, la ref n'y est pas
  no_evidence_declared la capacité n'a pas déclaré quel artefact fait foi  (→ P3)
```
Aucune exception levée, aucun verdict consulté ni modifié — **exactement le régime de
`skipped_validation_status`**.

### Ce qu'on mesure avant de décider
```
sur N runs portant au moins un message adressé :
  combien de capacités notifiées sont `consumed` ?
  combien `not_consumed` ?
  combien `no_evidence_declared` ?
```
**Le gate dur n'est proposé qu'après cette mesure**, et il reste borné aux **capacités
effectivement notifiées** — sans quoi les **88 run_dirs sur 89** sans trace deviendraient un
blocage global.

---

## 4 · P3 — les deux options, mises en forme ratifiable

Rappel de l'instruction du sas 1 : **(c) prose est exclue** (règle 2026-07-23). Restent (a) et (b),
et **les deux exigent la même chose** : une **4ᵉ couche**.

### Pourquoi une 4ᵉ couche, et pas seulement un champ
`SCHEMA.md` §79 — *« Amendement layer, ratifié Pierre 2026-08-02 »* — impose que **tout champ
déclare sa couche**, et le code porte l'invariant : *« Un champ sans consommateur déclaré ne doit
pas être présenté comme une capacité injectée »*.

| couche existante | définition | accueille `consumption_evidence` ? |
|---|---|---|
| `prompt` | rendu en section de texte par `_render_prompt` | **non** — l'agent n'a pas à le lire |
| `dispatch` | construit le payload (modèle/provider/outils) | **non** |
| `documentation` | **aucun consommateur d'exécution** | **non** — il en a un, machine |

⇒ **4ᵉ couche `verification`** : *champ lu par la vérification après production, jamais rendu à
l'agent, jamais dans le payload.*

### Les deux formes
| | **(a)** structurer `output_contract` | **(b)** champ `consumption_evidence`, couche `verification` |
|---|---|---|
| forme | `output_contract: {production_outputs: [...], consumption_evidence: [...]}` | liste YAML, comme `mandatory_read` |
| contrats YAML à modifier | **23** — `output_contract` est en prose dans 23/23 | **0** si optionnel (précédent `delegation_context`, obligation levée) |
| `_render_prompt` | à réécrire — il rend `output_contract` en texte | inchangé |
| risque | casse un champ `prompt` rendu, couvert par `_verify_prompt_layer_rendered` | aucun champ existant touché |

**Coût commun aux deux** : 3 fichiers de code (`contract.py`, `agent_context_map.mjs`,
`context_check.mjs`) · 3 fichiers de test · 1 doc (`SCHEMA.md`) · l'invariant
`_verify_prompt_layer_rendered` à ne pas casser.

> **(b) coûte 0 contrat, (a) en coûte 23.** Je le note comme un fait mesuré ; l'arbitrage de schéma
> reste à Pierre, et il porte sur la 4ᵉ couche, pas sur le champ.

### Conditions d'entrée, quelle que soit la forme
1. **livré avec son lecteur** — `consumption_status()` le même jour (C1 du précédent, et invariant
   du code : pas de champ sans consommateur déclaré) ;
2. **advisory d'abord**, gate séparé ensuite (C2 du précédent) ;
3. **optionnel** — un contrat sans `consumption_evidence` reste chargeable, sinon 23 contrats
   deviennent invalides d'un coup.

---

## 5 · Ratification `KNOWLEDGE_RESOLVER_V1` — ce qui est ratifié, ce qui ne l'est pas

```
§1 « Cadre ratifié (Pierre, 2026-07-20) »        → RATIFIÉ
le document lui-même                              → PROPOSED — « en attente gate Pierre
                                                    avant toute construction »
```

### ⚠ La ratification est partiellement rétroactive — à dire, pas à masquer
`knowledge_trace.mjs` est **construit**, **testé**, et **câblé en gate DUR** dans
`verify_run._check_knowledge_trace`, repris par `driver.py:4667` — *« même sévérité que la preuve
mutation »*. Or son protocole est PROPOSED depuis le 2026-07-20, avec la mention *« avant toute
construction »*.

**Un composant issu d'un protocole non ratifié bloque déjà des runs en production.** Ce n'est pas
une faute à corriger en urgence — c'est un état à **nommer** avant de ratifier, sinon la
ratification couvre rétroactivement une construction qu'elle était censée autoriser.

### Ce que la ratification doit couvrir, précisément
| pièce | état | à ratifier ? |
|---|---|---|
| `knowledge_trace.json` — lineage de lecture | **construit + gate DUR** | oui, **rétroactivement** |
| `pending_review` — outil read-only, 3 files agrégées | **non construit** | oui, ou retirer de V1 |
| §3.3 *« Rien d'autre »* — hors V1 : scoring, distillation, vectoriel, daemon, **toute écriture par l'outillage** | frontière | oui — **et l'émetteur doit s'y conformer** (§1, C3) |

---

## 6 · État du sas 2

> **Clôturé le 2026-09-02** — décisions Pierre enregistrées dans `SAS2_RATIFICATION.md`.
> Une mesure post-ratification y corrige un point de ce document : le gate `knowledge_trace` est
> **conditionnellement** dur (trace absente = warning), et brancher l'émetteur l'activerait.

| # | sujet | état | décision |
|---|---|---|---|
| 1 | **Émetteur** | **spécifié** — orchestrateur, 2 écritures, interface existante, C1/C2 satisfaites | prêt à ratifier |
| 2 | **J1** | **résolu** — journal en `EVIDENCE/amendments/`, aucune garde heurtée | prêt à ratifier |
| 3 | **P1** | **requalifié** — advisory + `consumption_status()` à trois états ; gate dur = décision ultérieure | prêt à ratifier *(le régime, pas le gate)* |
| 4 | **P3** | **instruit** — 4ᵉ couche `verification` requise ; (b) coûte 0 contrat, (a) en coûte 23 | **RATIFIÉ 2026-09-02** → `SAS2_RATIFICATION.md` |
| 5 | **Ratification V1** | **instruite** — cadre ratifié, document PROPOSED, gate DUR déjà en production | **RATIFIÉ 2026-09-02 sous réserve N-1/N-2/N-3** → `SAS2_RATIFICATION.md` |

### Ce que ce sas n'a pas fait
Aucun code · aucun fichier dans le dépôt source · aucun renommage · **aucune implémentation du
journal ni de l'émetteur** · la jointure `expected ↔ actual` reste au sas 3 · **Q2 / R8 non
touchée**.

```
status_by_surface:
  preflight_head:              TESTED       # feeb29cb, 0 dérive
  emitter_spec:                DOCUMENTED_ONLY
  writeTrace_interface:        TESTED       # export + CLI + garde de zone mesurés
  j1_guard_compatibility:      TESTED       # writeTrace refuse hors lab/forge_runs/ — 2 fichiers distincts
  p1_measurement_point:        DOCUMENTED_ONLY
  p3_fourth_layer:             TESTED       # 3 couches existantes, aucune n'accueille le champ
  v1_retroactivity:            TESTED       # protocole PROPOSED, composant en gate DUR
  anti_layer_rule_c2:          TESTED       # journal consolide 2 canaux + 1 manquant
  implementation:              BLOCKED
```
`software_verdict: OK` (spécification) · `evidence_verdict: MECHANICAL_VALIDATION_ONLY` ·
`claim_verdict: NO_CLAIM_ALLOWED` · `no_global_ready_verdict: true`

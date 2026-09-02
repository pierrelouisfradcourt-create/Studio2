# DÉCISIONS RATIFIÉES — NON ENCORE EXÉCUTÉES

> ## ⏹ STOP AUDIT — 2026-09-02
> **Le prochain chantier n'est plus J / P / W / U. C'est l'inventaire de récupération V1 → V2.**
> Les lignes restantes ci-dessous ne sont **ni annulées, ni urgentes** : elles sortent du chemin
> de migration. Aucune n'est un prérequis pour copier.
> `W-3` est **close autrement** : inscrite comme règle de vérité **R11** dans `TOPOLOGY.md` —
> *« `visual` = preuve de liveness / rendu observable, pas preuve de qualité visuelle »*.
>
> **Principe de la suite** : *on ne migre pas le passé ; on migre ce qui doit continuer à vivre.*
> Et : **on ne reconstruit pas ce qui existe et fonctionne — on le copie.** W-1 (fabriquer des
> adaptateurs) est donc **abandonné comme chantier** : `capture_browser.mjs` et
> `capture_godot.mjs` existent et sont exploitables ; ils se copient. On ne construira que si la
> copie révèle un manque **réel**.

*Registre ouvert le 2026-09-02 · **aucune de ces lignes n'est implémentée**.
Objet : empêcher qu'une décision ratifiée soit relue comme un état du système.*

> **Règle de lecture.** *Ratifié* ≠ *fait*. Une ligne de ce registre décrit une autorisation, pas
> un comportement. Tant qu'elle est ici, le code se comporte **comme avant la décision**.

## Préflight
```
HEAD dépôt source : feeb29cb (2026-09-01 16:33:44 +0200) · 76 lignes · 0 dérive
```

---

## L'ordre est contraignant

*Ordre ratifié Pierre le 2026-09-02, après exécution de N-2 :*
```
N-2      rétrograder knowledge_trace en advisory   ← ✅ EXÉCUTÉE (non commitée)
  ↓
J1 · P3  le mécanisme de consommation              ← ✅ EXÉCUTÉES (non commitées)
  ↓
E        brancher l'émetteur                        ← ✅ EXÉCUTÉE (non commitée)
  ↓
P1 ✅    le point de mesure existe
M        mesurer — ⚠ POPULATION VIDE aujourd'hui (0 message, 0 déclaration)
  ↓
G        décider du régime du gate — forme (iv) à étudier
```
**Deux inversions sont interdites, pour deux raisons distinctes :**
- **N-2 avant E** — sans quoi une anomalie à 1/89 devient un blocage systémique. C'est la raison
  même de la décision N-2 ; l'ordre en fait partie.
- **P3 avant ou avec E** — `consumption_evidence` **appartient au mécanisme de consommation**.
  Le livrer après une mesure qui en dépend reviendrait à mesurer une adoption dont l'objet
  déclaratif n'existe pas encore.

---

## Le registre

| # | décision | ratifiée | état | dépend de |
|---|---|---|---|---|
| ~~**N-2**~~ | `knowledge_trace` : `problems` → `warnings` — la vérification tourne et rapporte, **elle ne bloque plus** | 2026-09-02 | ✅ **EXÉCUTÉE 2026-09-02** → `N2_EXECUTION.md` · non commitée | — |
| ~~**J1**~~ | journal d'amendements en `EVIDENCE/amendments/` (hors `run_dir`) | 2026-09-02 | ✅ **EXÉCUTÉE 2026-09-02** → `J1_P3_EXECUTION.md` · non commitée | — |
| ~~**E**~~ | émetteur = geste d'orchestrateur : message → journal · item → `knowledge_trace.json` | 2026-09-02 | ✅ **EXÉCUTÉE 2026-09-02** → `E_EXECUTION.md` · non commitée | — |
| ~~**P3**~~ | 4ᵉ couche `verification` + champ `consumption_evidence`, **optionnel**, advisory, livré avec son lecteur | 2026-09-02 | ✅ **EXÉCUTÉE 2026-09-02** → `J1_P3_EXECUTION.md` · non commitée | — |
| ~~**P1**~~ | `consumption_status(message, capability, run_dir)` → `consumed` / `not_consumed` / `no_evidence_declared`, **advisory** | 2026-09-02 | ✅ **EXÉCUTÉE 2026-09-02** → `P1_EXECUTION.md` · non commitée | — |
| **M** | **mesurer** l'adoption sur population réelle | — | **BLOQUÉE — population vide** : 0 message au journal, 0 contrat portant `consumption_evidence` | usage réel de E |
| **G** | régime définitif du gate, sur adoption mesurée | — | **NON PRISE** | M |
| **U-2** ⏸ | régime `UNADDRESSABLE` distinct de `NOT_APPLICABLE` + compteurs `leaves_total` · `leaves_addressable` · `leaves_unaddressable` · `leaves_covered` | 2026-09-02 (J-3) | **NON EXÉCUTÉE** | — |
| **U-3** ⏸ | vérifier qu'un `couvre[]` ne mélange pas `feature.id` et `leaf.id` — l'interdiction n'a **aucun mécanisme** aujourd'hui | 2026-09-02 (J-3) | **NON EXÉCUTÉE** | — |
| **P-1** ⏸ | étendre le contrôle d'existence des fichiers cités par `preuve` au-delà de `.gd` — **ADVISORY**, `check_wiremap.passed` NON modifié ; `vérifiable → FOUND/MISSING`, `format non reconnu → NOT_MEASURED` | 2026-09-02 (J-5) | **NON EXÉCUTÉE** | — |
| ~~**V-2**~~ | vérifier **READ-ONLY** la valeur probante du volet 3c sur `pong` | 2026-09-02 (J-4) | ✅ **EXÉCUTÉE** → `V2_POND_VALEUR_PROBANTE.md` | — |
| ~~**W-2**~~ | découpler le statut de `check_visual_capture` par moteur | 2026-09-02 (V-2) | ✅ **EXÉCUTÉE 2026-09-02** → `W2_EXECUTION.md` · non commitée | — |
| ~~**W-1**~~ | fabriquer des adaptateurs de capture | — | **ABANDONNÉ comme chantier** (STOP AUDIT) — les adaptateurs existants se **copient** | — |
| ~~**W-3**~~ | inscrire ce que `visual` prouve | — | ✅ **CLOSE** — règle **R11** de `TOPOLOGY.md` | — |
| ~~**U-1**~~ | feuille = unité canonique, `capacites_couvertes` = feuilles distinctes avec `id` | 2026-09-02 (J-3) | ✅ **CONFORME À L'EXISTANT** — rien à exécuter | — |

### N-2 — périmètre exact de l'exécution à venir
```
scripts/forge/verify_run.py   _check_knowledge_trace  → problems devient warnings   (1 fonction)
scripts/forge/driver.py       aucun changement — il agrège une liste devenue vide
scripts/forge/tests/test_verify_run_knowledge_trace.py   2 assertions sur 5 à inverser
scripts/forge/contract.py:307 « traite les problèmes […] comme BLOQUANTS » → devient faux, à corriger
```
**Non touché** : `knowledge_trace.mjs`, `verifyTrace`, la sonde anti-théâtre. N-2 déplace une
liste ; il ne retire aucune capacité.

**Précondition mesurée ce jour** : les 4 fichiers concernés sont **propres** dans l'arbre de travail
(`git status --porcelain` vide sur les 4), alors que 76 lignes du dépôt ne le sont pas et qu'une
autre session écrit dans `scripts/forge/`. À **re-mesurer au moment d'exécuter** — cette ligne
porte son HEAD, `feeb29cb`, et ne vaut pas pour un autre.

### Acquis de N-2 — la distinction que l'exécution a établie
> **capacité de contrôle ≠ autorité du contrôle.**
> La sonde détecte exactement comme avant ; elle ne décide plus. Et le signal reste **observable**
> (`detail.knowledge_trace_advisory`, ratifié 2026-09-02) — sans quoi on aurait rétrogradé le
> contrôle **en supprimant la surface** qui permet d'observer son adoption, c'est-à-dire en rendant
> M impossible.

### Ce que (iv) n'est pas
**L'armement déclaré est la forme à étudier dans la décision G — pas une précondition à bricoler
maintenant.** Rien de (iv) n'entre dans N-2 ni dans E.

---

## Décisions prises qui n'ouvrent aucune ligne exécutable
`U-1` (conforme à l'existant) · `P-3` conserver `preuve.strip() != ""` comme **contrôle de
non-vacuité et rien de plus** · `V-1` `visual` reste déclarable · `V-3` **ne pas brancher** s10d /
`quality_sensor` · **`actual_proof` : NE PAS CONSTRUIRE** — `rattachable ≠ prouvé`.

## Ce que ce registre ne contient pas
La jointure `expected ↔ actual` — **sas 3, fermé**. Le patch de frontière — **sas 4**.
**Q2 / R8 — hors sujet, inchangée.**

```
status_by_surface:
  preflight_head:          TESTED   # feeb29cb, 0 dérive
  n2_target_files_clean:   TESTED   # 4/4 propres à feeb29cb
  register_entries:        RECORDED # 5 ratifiées non exécutées + 1 non prise
  execution:               BLOCKED  # aucune ligne implémentée
```
`software_verdict: OK` (registre) · `evidence_verdict: MECHANICAL_VALIDATION_ONLY` ·
`claim_verdict: NO_CLAIM_ALLOWED` · `no_global_ready_verdict: true`

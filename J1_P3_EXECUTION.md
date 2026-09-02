# J1 + P3 — EXÉCUTION

*2026-09-02 · **PATCH APPLIQUÉ dans le dépôt source**, sur GO explicite Pierre.
Non commité, non poussé. HEAD : `feeb29cb`.*

## Preuve d'exécution
```
.venv312 -m pytest scripts/forge/tests -q -m "not gpu_window"
→ 2512 passed, 1 skipped, 10 deselected   (5:31)     [2485 avant · +27 tests neufs]

node --test scripts/forge/agent_context_map.test.mjs   → 10 pass / 0 fail
node scripts/forge/studio_selfaudit.mjs                → "ok": true
```

---

## J1 — le journal d'amendements

**Fichier neuf** : `scripts/forge/amendment_log.py` · **tests** : `tests/test_amendment_log.py` (13).

### L'emplacement est le fond de J1, pas un détail de rangement
```
JOURNAL_DIR = lab/forge_evidence/amendments/     ← surface EVIDENCE, HORS run_dir
RUNS_ZONE   = lab/forge_runs/                    ← le journal y est REFUSÉ
```
`append_message` lève si on lui désigne un emplacement sous `lab/forge_runs/`. **C'est le
symétrique exact de la garde de `writeTrace`**, qui refuse d'écrire la trace *hors* de cette même
zone : deux fichiers, deux zones, jamais la même. Un journal dans le corpus d'un run fabriquerait un
`FOUND` par construction (F-1) — la garde rend cette faute impossible, au lieu de la confier à la
discipline.

*Lecture de correspondance* : `EVIDENCE/` est le nom **V2** de la surface ; dans le dépôt source
c'est `lab/forge_evidence/`. Aucun nouveau lieu inventé.

### C2 — le journal remplace, il ne s'ajoute pas
`question` (remplace `design_questions.json`, un fichier par run sans lecteur transversal) ·
`objection` (remplace les objections coincées en fin de chaîne) · `amendment` (**n'avait aucun
canal**). Deux canaux unifiés, un troisième absorbé.

### C1 — vérifié par les tests, pas seulement affirmé
déterministe (`new_message_id` : même sujet + même horodatage ⇒ même id, aucun hasard) ·
recomputable · **append-only** (un `id` déjà présent est refusé ; une ligne illisible est ignorée
à la lecture mais **jamais effacée** — lire ne répare pas) · non liant.

**Schéma strict, et refus total** : un message invalide ⇒ `AmendmentLogError` et **aucun octet
écrit**, même discipline que `validateTraceItems`.

### ⚠ Ce que J1 ne ferme pas
**F-2, le prompt.** La référence restera dans `context/prompt_<etape>_a<n>.txt`, qui est dans le
corpus. Seule la règle d'acquittement du sas 1 — la ref doit être dans l'artefact **désigné** — le
ferme. C'est précisément ce que P3 rend déclarable.

---

## P3 — la 4ᵉ couche `verification`

**Forme (b), 0 contrat YAML touché.** Modifiés : `contract.py` · `contracts/SCHEMA.md` ·
**tests neufs** : `tests/test_consumption_evidence_layer.py` (14).

```
VERIFICATION       = ("consumption_evidence",)      hors CRITICAL / IMPORTANT / RECOMMENDED
LAYER_VERIFICATION = ("consumption_evidence",)      4ᵉ couche, disjointe des 3 autres
```

### Les trois conditions d'entrée, chacune figée par un test
1. **livré avec son lecteur** — `consumption_evidence_status(contract)` → `filled` /
   `declared_empty` / `absent`, et `consumption_evidence_adoption()` sur tout un répertoire.
   Vocabulaire et régime calqués sur `skipped_validation_status`.
2. **advisory** — aucun verdict lu ni modifié, aucun gate touché, ne lève jamais.
3. **optionnel** — un contrat sans le champ reste valide ; présent mais malformé, il est refusé
   (précédent `delegation_context`).

### Une garde que j'ai ajoutée parce que l'invariant l'exigeait
`_verify_prompt_layer_rendered` fige *« tout champ `prompt` rempli est rendu »*. Un champ de la 4ᵉ
couche ne doit **jamais** être rendu à l'agent. Plutôt que d'ajouter une exception à cet invariant,
le champ est tenu hors de `LAYER_PROMPT` — et un test le **prouve** en comparant les deux prompts
rendus octet pour octet, avec et sans le champ : `rendu == sans`. **L'invariant reste intact, sans
exception.**

### Le chiffre de départ, honnête
```
consumption_evidence_adoption()  →  filled 0 · declared_empty 0 · absent 28  (total 28)
```
**Aucun contrat ne porte encore le champ.** C'est ce zéro que la décision ultérieure sur le gate
devra voir bouger — et c'est exactement pourquoi il ne pouvait pas être obligatoire.

*Correction de mesure* : l'instruction annonçait « 23 contrats ». Le répertoire en contient **28**
(les 23 d'étape + orchestrateur et apparentés). Le coût reste **0**, le champ étant optionnel.
`agent_context_map.mjs` et `context_check.mjs`, annoncés impactés par le document du sas 1,
**ne l'étaient pas** : ni l'un ni l'autre n'énumère les champs du schéma.

---

## Périmètre
**Fichiers de mon fait** : `amendment_log.py` (neuf) · `contract.py` · `contracts/SCHEMA.md` ·
`tests/test_amendment_log.py` (neuf) · `tests/test_consumption_evidence_layer.py` (neuf).
**Non touchés** : `knowledge_trace.mjs`, `verify_run.py`, `driver.py`, `verdict.py`, `gate.py`,
les 28 contrats YAML. **Aucun commit, aucun push.** Q2/R8 inchangée, sas 3 fermé.

## Suite
```
N-2 ✅  →  J1 ✅ · P3 ✅  →  E (émetteur)  →  P1 · M  →  G
```
**E est désormais débloquée** : ses trois dépendances sont exécutées.

```
status_by_surface:
  j1_journal:              TESTED   # 13 tests — emplacement, append-only, refus total
  j1_location_guard:       TESTED   # refus sous lab/forge_runs/, symétrique de writeTrace
  p3_fourth_layer:         TESTED   # 14 tests — couches disjointes, non rendu, optionnel
  p3_prompt_invariant:     TESTED   # prompt identique octet pour octet avec/sans le champ
  p3_adoption_baseline:    TESTED   # 0 / 0 / 28
  full_suite:              TESTED   # 2512 passed / 1 skipped / 10 deselected
  node_tests_selfaudit:    TESTED   # 10 pass · selfaudit ok:true
  emitter_E:               BLOCKED  # non entamée
  commit:                  BLOCKED  # gate Pierre
```
`software_verdict: OK` · `evidence_verdict: MECHANICAL_VALIDATION_ONLY` ·
`claim_verdict: NO_CLAIM_ALLOWED` · `no_global_ready_verdict: true`

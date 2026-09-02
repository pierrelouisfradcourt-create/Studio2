# N-2 — EXÉCUTION

*2026-09-02 · **PATCH APPLIQUÉ dans le dépôt source**, sur GO explicite Pierre.
Non commité, non poussé. HEAD inchangé : `feeb29cb`.*

## Préflight (avant patch)
```
HEAD : feeb29cb · 4 fichiers cibles PROPRES au moment d'écrire
```

## Ce qui a été fait

| fichier | changement |
|---|---|
| `scripts/forge/verify_run.py` | `_check_knowledge_trace` retourne `(problems, warnings, ok)` · l'échec part en **warning** · `problems` **toujours vide** (point de ré-armement) · `knowledge_trace_ok` **retiré de `integrity_ok`/`overall`** · CLI honnête |
| `scripts/forge/driver.py` | commentaires corrigés (le lineage n'est plus un gate dur) · **+ surface advisory** dans le détail de l'étape OK |
| `scripts/forge/contract.py` | commentaire l.307 corrigé — il affirmait « traite […] comme BLOQUANTS » |
| `scripts/forge/tests/test_verify_run_knowledge_trace.py` | 2 tests retournés |
| `scripts/forge/tests/test_driver.py` | **1 test retourné — non prévu (voir corrections)** |

**Non touchés** : `knowledge_trace.mjs`, `verifyTrace`, la sonde anti-théâtre. N-2 retire une
**autorité**, pas une **capacité**.

## Deux corrections à mon instruction

> **Toutes deux validées par Pierre le 2026-09-02.** C-1 : le rayon d'impact se mesure **par
> consommateur réel, pas par nom de module** — renfort de R8. C-2 : `detail.knowledge_trace_advisory`
> est **conservé** — *« moins d'autorité, même capacité de détection, signal observable »*, et il est
> indispensable à M.

**C-1 · le rayon d'impact des tests était sous-estimé.** J'annonçais *« 2 assertions sur 5 »*, dans
**un** fichier. Il y en avait **6, dans 3 fichiers** : `test_driver.py::test_knowledge_trace_
theatrale_bloque_s12_meme_si_oracles_verts` est la preuve **bout-en-bout** du gate au niveau du
driver. Ma mesure n'avait porté que sur le fichier de test portant le nom du module. **Motif connu :
un consommateur ne se trouve pas à la forme du nom (R8).** La suite complète l'a rattrapé.

**C-2 · une addition que je n'avais pas spécifiée — à vetoer si elle dépasse le mandat.**
Sur le chemin OK du driver, le détail de l'étape ne portait aucune trace du contrôle. Rétrograder
sans rien ajouter aurait donc rendu un lineage théâtral **invisible** dans `state.json` : ce
n'aurait pas été une rétrogradation mais une **suppression du signal** — et la mesure d'adoption
qui doit précéder la décision sur le gate n'aurait eu **aucune surface où observer**.
J'ai ajouté `detail.knowledge_trace_advisory` (les avertissements, uniquement quand le contrôle est
faux). C'est ce que les tests figent désormais : **plus d'autorité, toujours visible.**

## Preuve d'exécution

```
.venv312 -m pytest scripts/forge/tests -q -m "not gpu_window"
→ 2485 passed, 1 skipped, 10 deselected  (5:26)
```
Et sur le seul run réellement armé du dépôt :
```
python -m forge.verify_run lab/forge_runs/card_engine/verdict.json
knowledge_trace  : OK
INTÉGRITÉ : REJET     ← dû aux `coherence_problems` (hashes de code divergents),
                        PRÉEXISTANTS et SANS RAPPORT avec N-2 — les autres gates
                        (HMAC, évidence, cohérence) sont intacts.
```

## Périmètre — ce qui n'a pas été touché
`git diff --stat` porte 8 fichiers ; **5 sont les miens** (ci-dessus). Les 3 autres —
`dispatch.py`, `oracles.json`, `test_evidence_isolation_fixture.py` — **étaient déjà modifiés
avant ce patch** par une autre session, et ne sont pas de mon fait.

**Aucun commit, aucun push** (gate Pierre). HEAD toujours `feeb29cb`.
`GAMES/`, `EVIDENCE/`, Q2/R8, sas 3 : **non touchés**.

## Suite ratifiée
```
✅ advisory  →  brancher l'émetteur (E, J1)  →  mesurer l'adoption (P1)  →  décision Pierre (G)
```

```
status_by_surface:
  n2_patch_applied:        TESTED   # 5 fichiers, suite complète verte
  full_suite:              TESTED   # 2485 passed / 1 skipped / 10 deselected
  real_armed_run:          TESTED   # card_engine — knowledge_trace OK, autres gates intacts
  test_blast_radius_fix:   TESTED   # 6 tests / 3 fichiers, pas 2 / 1
  advisory_surface_added:  TESTED   # detail.knowledge_trace_advisory — RATIFIÉ Pierre 2026-09-02
  commit:                  BLOCKED  # gate Pierre
```
`software_verdict: OK` · `evidence_verdict: MECHANICAL_VALIDATION_ONLY` ·
`claim_verdict: NO_CLAIM_ALLOWED` · `no_global_ready_verdict: true`

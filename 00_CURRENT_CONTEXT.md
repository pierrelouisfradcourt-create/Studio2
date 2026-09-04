# ÉTAT COURANT — Studio V2

*2026-09-03. Handoff inter-sessions. **< 100 lignes**, comme la règle l'exige.*

> ✅ **RATIFIÉ Pierre 2026-09-03** — ce fichier **est** le handoff de V2, et `studio_brain/
> 00_CURRENT_CONTEXT.md` (en V1) n'est **pas** mis à jour depuis cette phase.
>
> **Une règle documentée ne devient jamais un prétexte pour rompre un invariant plus fort.**
> `CLAUDE.md` décrit un handoff en V1 ; l'invariant « V1 en lecture seule » prime, et il a tenu
> toute la session. Écrire dans V1 « parce que la doc le dit » aurait invalidé, d'un seul geste,
> les dizaines de vérifications `V1 INTACT` sur lesquelles reposent tous les rapports de cette
> phase.

## Où en est le studio

```
V1  C:\TACTICAL_CHESS_STUDIO        HEAD 58095ba9   SOURCE CANONIQUE, lecture seule
    4 écarts (dispatch.py, oracles.json, 2 tests) = autre session, jamais migrés
V2  C:\Users\Studio-Dev\Desktop\Studio
    2769dc8  état migré           cf89ffb  socle sécurisé
```

**Phase close : sécurisation du socle.** V2 est migré, validé et prouvé par un run complet.
**Phase suivante : construire la vraie V2** — elle n'existe pas encore.

## Session 2026-09-03 → 04 — Lots 2, 3, 4 commités (GO Pierre 2026-09-04, playtest OK)

- **Lot 2** : `forge/capability.py` + `forge/capability_registry.yaml` (15 capacités, 4 invocables v0),
  `prepare_dispatch(contracts_dir)` ; sonde réelle `EVIDENCE/runs/lot2_decompose_probe/` (opus-4-8, 1,42 $,
  `check_decompo` → 2 codes K7).
- **Lot 3** : `forge/director.py` (noyau déterministe, décisions K6, effet mesuré, objections via `emitter`),
  `blueprint.restore_section` ; sonde `EVIDENCE/runs/lot3_director_probe/`, `EVIDENCE/amendments/journal.jsonl`.
- **Lot 4** : `forge/build_orchestrator.py`, jeu `GAMES/v2_breakout_slice/`, run `EVIDENCE/runs/v2_breakout_slice_r1/` :
  verdict OK / HUMANGATE_READY, `verify_run` AUTHENTIQUE (re-vérifié 2026-09-04), couverture JOINED 10/10,
  15 pas / 13 décisions, 6,67 $, playtest Pierre : 7 critères OK. Tests des 3 lots : 26 verts (46 s, `.venv` V2).
- ⚠ **Trois réserves conservées, non résolues** :
  1. ownership de `forge/oracles.json` : l'entrée globale `v2_breakout_slice` a été ajoutée hors mécanisme
     (`build_orchestrator` n'écrit que l'`oracles.json` du run, R3) ; propriétaire de la surface non défini ;
  2. `timeout_policy` par capacité : inexistante — un seul `--timeout` du Director pour toutes les convocations
     (`director.py:394-403, 564`), aucun champ au registre ;
  3. objections du dossier non filtrées par `run_id` : `journal.jsonl` porte `run_id: null` (4/4), le dossier du
     slice liste une objection venue de `lot3_director_probe`.
- Audit parallèle capacités / skills / modèles (2026-09-03, HEAD 3481089, hors dépôt) : `invoke_capability` v0
  emporte 13 mécanismes de production et en perd ou déplace 22 (pré-mortem, manifest d'exécution, spawn_link,
  modèle mesuré, routage provider, réparation, timeouts…) ; aucun n'a de propriétaire déclaré au registre.

## La baseline — ne pas y toucher

```
EVIDENCE/runs/runm_breakout/      RUN M ter · 13/13 · verdict signé · verify_run AUTHENTIQUE
GAMES/runm_breakout/              le jeu produit
```
⛔ **Ni déplacer ni renommer ni écraser** — le reçu d'oracle porte un chemin relatif.
**Un prochain run doit porter un AUTRE nom de projet.**
Archives conservées : `_ARCHIVE_RUN_M_*` (preuves du VOID et du HALT d'encodage).

## Ce qui est fait, et ce qui ne l'est pas

**Fait** — migration sélective · git V2 · `.gitignore` récupéré (c'est un mécanisme de preuve,
pas un confort) · lots B, C-1, C-2, D-1, D-1-tuyau, D-2, encodage, ESC-1 · outils
`TOOLS/scan_imports.py` et `TOOLS/validate_v2.py` · 2459 tests verts, 43 classés.

**Pas fait, et c'est le sujet suivant** — la thèse V2 :
```
dispatch.ORDER            13 stations FIXES de V1
GAME_BLUEPRINT            cité dans 0 fichier
GAME_FLOW                 cité dans 0 fichier
ARCHITECTURE_CONTRACT     cité dans 0 fichier
forge/emitter.py          0 appel dans la chaîne — le geste existe, personne ne le pose
```

## Défauts connus, nommés, non corrigés

| | |
|---|---|
| le jeu produit **se gagne sans joueur** (456 frames = partie sans entrée) et son oracle de solvabilité le valide | variance nulle, règle 2026-07-21 |
| `s6-redteam-plan` rend **0 finding par construction** | hérité V1, profil identique sur 3 runs V1 |
| convention `logic.test.mjs` / `properties.test.mjs` **écrite dans aucun contrat** | coût mesuré : une tentative de builder |
| `premortem_lessons` **sans filtre projet** | fuite de leçons inter-projets |
| ESC-1 **non vérifié en run réel** | prouvé au point de décision seulement |
| `U-2` · `U-3` · `P-1` | hors chemin de migration, au registre |

## Décisions ouvertes

- **Q2 / R8** — verrou World Scan, **jamais levé implicitement** ; intact depuis le début.
- `GAMES/pacman/00_CHARTER` et `09_WIREMAP` : absents du HEAD canonique, **non copiés, non reconstitués**.
- `docs/ARCHI.md` · `docs/forge/RUN2_PROTOCOLE_V1_PROPOSED.md` : cités, absents du HEAD, non inventés.

## Registres

`DECISIONS_TO_EXECUTE.md` — décisions ratifiées non exécutées · `BASELINE_M_TER.md` ·
`RUN_M_*_RESULTAT.md` · `LOT_*.md` · `V2_VALIDATION_CLOTURE.md` · `TOPOLOGY.md` (règles R1–R11).

**Aucun push. `claim_verdict: NO_CLAIM_ALLOWED`.**

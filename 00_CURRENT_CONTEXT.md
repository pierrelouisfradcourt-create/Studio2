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
V2  C:\Users\Studio-Dev\Desktop\Studio2   (renommé 2026-09-04 ; remote github.com/pierrelouisfradcourt-create/Studio2)
    2769dc8 migré · cf89ffb socle · 3481089 Lot 1 · 523bd07 Lots 2-4 · Lot 5 en attente de GO commit
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
- Audit capacités / skills / modèles (2026-09-03) : `docs/forge/AUDIT_V2_CAPABILITIES_SKILLS_MODELS_20260903.md`.

## Lot 5 — transport et propriétaires (2026-09-04, GO Pierre ; plan `docs/superpowers/plans/2026-09-04-lot5-*.md`)
- Registre : bloc `transport` = 28 mécanismes avec propriétaire (18 carried par invoke · 3 director · 6 deferred
  avec raison · 1 dropped → Pierre : entrée globale `forge/oracles.json`) ; `timeout_policy` par capacité (builder 5400 s, détaché).
- `invoke_capability` : manifest dispatch sur les SECTIONS lues (plus `_UPSTREAM_BY_STEP`), manifest `execution`,
  spawn_link, RETURN_REASON, modèle MESURÉ ≠ déclaré, diagnostic, next_reason, sha par sous-entrée, pré-mortem
  (studio + `error_journal.jsonl` du run), retour du matérialiseur transmis par le Director, journal d'échec du run.
- Réserves 523bd07 : 1 fermée par déclaration (`pierre`, test R3 sur `prepare_build`) · 2 fermée (registre) · 3 fermée
  (objections avec `run_id`, dossier filtré + `objections_autres_runs`). Tests : 114 verts (lot + voisins) ; T0 complet
  2511 verts / 42 échecs = population V1 classée, inchangée.
- Sonde réelle `EVIDENCE/runs/lot5_transport_probe/` (decompose, opus-4-8 mesuré, 1,61 $) : lignées écrites, 4 sections citées.
  **Trouvé par la sonde** : `check_decompo.mjs` exige une preuve `main.tscn` (lignée Godot) pour toute action joueur,
  même sur un jeu web → `DECOMPO_LOOP_NO_ENTRY` structurel sur runm_breakout ; à paramétrer par lignée (Lot 6).

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

**Thèse V2 (état 2026-09-04)** : GAME_BLUEPRINT, capacités convocables, Director, emitter branché = Lots 1→5 ;
`dispatch.ORDER` reste (13 stations, contourné, jamais retiré) ; GAME_FLOW · UX · design_metrics : DOCUMENTED_ONLY.

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

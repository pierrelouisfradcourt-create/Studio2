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
    2769dc8 migré · cf89ffb socle · 3481089 Lot 1 · 523bd07 Lots 2-4 · bc23133 Lot 5
    464150e spec+plan Lot 6 · Lot 6 en attente de GO commit
```

**Phase close : sécurisation du socle.** V2 est migré, validé et prouvé par un run complet.
**Phase suivante : construire la vraie V2** — elle n'existe pas encore.

## Lots 2 → 5 — commités, détail dans les messages de commit et `docs/superpowers/plans/`

- **523bd07 (Lots 2-4)** : capacités convocables (`capability.py` + registre, 15 capacités, 4 invocables
  v0) · Director v0 (`director.py`, décisions K6, effet mesuré, objections) · slice vertical
  (`build_orchestrator.py`, `GAMES/v2_breakout_slice/`, run `v2_breakout_slice_r1` : verdict OK /
  HUMANGATE_READY, `verify_run` AUTHENTIQUE, couverture JOINED 10/10, 6,67 $, playtest Pierre 7/7).
- **bc23133 (Lot 5, transport)** : bloc `transport` au registre = 28 mécanismes avec propriétaire
  (18 invoke · 3 director · 6 deferred motivés · 1 dropped → Pierre) ; le manifest de dispatch mesure les
  SECTIONS lues et non plus `_UPSTREAM_BY_STEP` ; lignées `execution` / `return` / spawn_link ; modèle
  MESURÉ ≠ déclaré ; pré-mortem et retour du matérialiseur ; `timeout_policy` par capacité ; dossier
  HumanGate filtré par `run_id`. **Les trois réserves du 523bd07 sont fermées.**
- Audit capacités / skills / modèles : `docs/forge/AUDIT_V2_CAPABILITIES_SKILLS_MODELS_20260903.md`.
- Trouvé par la sonde du Lot 5, **non corrigé** : `check_decompo.mjs` exige une preuve `main.tscn`
  (lignée Godot) pour toute action joueur, même sur un jeu web → `DECOMPO_LOOP_NO_ENTRY` structurel.

## Lot 6 — contrat de re-convocation (2026-09-04, GO Pierre ; spec+plan `464150e`)

- **Identité de section** (`forge/identity.py`) : le registre déclare une clé canonique par section —
  `feature_map: …capacites[].id` · `architecture_contract: modules[]` · `wiremap.design:
  @frozen_features_from_wiremap` (résolveur nommé : la production calcule déjà cette identité, v2
  `lines[].id` sinon `features[].feature`, et c'est elle que le gel oppose au jeu courant). Une
  re-convocation reçoit sa **production précédente** ; un identifiant encore cité en aval qui disparaît
  refuse l'écriture (`ID_REFERENCED_DROPPED`, producteur `identity_check`, section intacte, spawn_link
  HALTED). Un retrait déclaré n'est accepté que si plus rien ne le cite (correction 1 de Pierre).
- **Acquittement** (`forge/acknowledgement.py`) : fence ```acquittement``` `{message_id, action, changes,
  reason}` ; cinq statuts (`acknowledged`, `claimed_without_effect`, `rejected`, `unknown_message`,
  `not_acknowledged`) ; un message ne s'acquitte qu'une fois. Un `rejected` produit un **désaccord**
  (objection capacité → director, `in_reply_to`) **puis** une question ouverte : les trois objets
  restent distincts. La recherche de sous-chaîne disparaît du chemin d'acquittement.
- **Director** : le refus d'identité est imputé à l'**écrivain de la section** d'après le registre —
  mesuré : sans ce bloc, un renommage par `decompose` était imputé à `wiremap`
  (`JOIN_LINES_WITHOUT_COUVRE`). Le libellé de tâche s3 n'invite plus au renommage.
- **Preuve réelle** `EVIDENCE/runs/lot6_identity_probe/` (opus-4-8 mesuré, 0,86 $, 104 s) : **10/10
  identifiants conservés**, section v2, lignées écrites. Au Lot 5, la même capacité sur le même projet
  avait renommé 10/10. Tests : 34 verts sur le lot, 147 avec les Lots 2 à 5 et voisins.
- **Frontière déclarée** : `wiremap.built` (builder) n'a pas de règle d'identité en v0 — le gel la
  couvre déjà par un STOP dur en s10c. Constat annexe consigné, non traité : un doublon d'identité rend
  l'ancre du gel malformée, donc un dédoublonnage changerait un BLOCKED en PASS.

## La baseline — ne pas y toucher

```
EVIDENCE/runs/runm_breakout/      RUN M ter · 13/13 · verdict signé · verify_run AUTHENTIQUE
GAMES/runm_breakout/              le jeu produit
```
⛔ **Ni déplacer ni renommer ni écraser** — le reçu d'oracle porte un chemin relatif.
**Un prochain run doit porter un AUTRE nom de projet.**
Archives conservées : `_ARCHIVE_RUN_M_*` (preuves du VOID et du HALT d'encodage).

## Ce qui est fait, et ce qui ne l'est pas

**Fait** — migration sélective · git V2 · `.gitignore` récupéré (mécanisme de preuve, pas un confort) ·
lots B, C-1, C-2, D-1, D-1-tuyau, D-2, encodage, ESC-1 · `TOOLS/scan_imports.py`, `TOOLS/validate_v2.py`.
**T0 au 2026-09-04** : 2544 verts / 42 échecs — population V1 classée au Lot 0, **strictement inchangée
depuis** (comparaison de la liste des `FAILED` à chaque lot).

**Thèse V2 (état 2026-09-04)** : GAME_BLUEPRINT, capacités convocables, Director, emitter branché,
contrat de re-convocation = Lots 1→6 ; `dispatch.ORDER` reste (13 stations, contourné, jamais retiré) ;
GAME_FLOW · UX · design_metrics : DOCUMENTED_ONLY.

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

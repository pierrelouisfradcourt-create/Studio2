# ÉTAT COURANT — Studio V2

*2026-09-04. Handoff inter-sessions, **< 100 lignes**. Ratifié Pierre 2026-09-03 : ce fichier EST le
handoff de V2, `studio_brain/00_CURRENT_CONTEXT.md` (V1) n'est plus mis à jour — une règle documentée
ne rompt jamais un invariant plus fort, « V1 en lecture seule » prime sur `CLAUDE.md`.*

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

- **523bd07 (Lots 2-4)** : capacités convocables · Director v0 · slice vertical `v2_breakout_slice`
  (verdict OK / HUMANGATE_READY, `verify_run` AUTHENTIQUE, JOINED 10/10, 6,67 $, playtest Pierre 7/7).
- **bc23133 (Lot 5, transport)** : 28 mécanismes de production avec propriétaire au registre (18 invoke ·
  3 director · 6 deferred motivés · 1 dropped → Pierre) ; manifest de dispatch sur les SECTIONS lues ;
  lignées execution/return/spawn_link ; modèle MESURÉ ≠ déclaré ; pré-mortem et retour du matérialiseur ;
  `timeout_policy`. **Les trois réserves du 523bd07 sont fermées.** Audit :
  `docs/forge/AUDIT_V2_CAPABILITIES_SKILLS_MODELS_20260903.md`.
- Trouvé par la sonde du Lot 5, **non corrigé** : `check_decompo.mjs` exige `main.tscn` (lignée Godot)
  pour toute action joueur, même sur un jeu web → `DECOMPO_LOOP_NO_ENTRY` structurel.

## Lot 6 — contrat de re-convocation (2026-09-04, GO Pierre ; spec+plan `464150e`)

*Détail complet : message du commit `8892189` et `docs/superpowers/specs|plans/2026-09-04-lot6-*`.*

- **Identité** (`forge/identity.py`) : clé canonique par section au registre — `feature_map:
  …capacites[].id` · `architecture_contract: modules[]` · `wiremap.design:
  @frozen_features_from_wiremap` (résolveur nommé : la production calcule déjà cette identité, et c'est
  elle que le gel oppose au jeu courant en s10c ; mesure dans `EVIDENCE/reports/lot6_reconvocation/`).
  Une re-convocation reçoit sa **production précédente** ; un id encore cité en aval qui disparaît
  refuse l'écriture (`ID_REFERENCED_DROPPED`, section intacte). Un retrait déclaré n'est accepté que si
  plus rien ne le cite.
- **Acquittement** (`forge/acknowledgement.py`) : fence dédiée, cinq statuts, un message ne s'acquitte
  qu'une fois ; un `rejected` produit un **désaccord** (objection capacité → director) **puis** une
  question — trois objets distincts. La recherche de sous-chaîne disparaît de ce chemin.
- **Director** : le refus d'identité vise l'**écrivain de la section** d'après le registre (sans cela,
  un renommage par `decompose` était imputé à `wiremap`). Le libellé s3 n'invite plus au renommage.
- **Preuve réelle** `EVIDENCE/runs/lot6_identity_probe/` (opus-4-8, 0,86 $) : **10/10 ids conservés** ;
  au Lot 5 la même capacité en avait renommé 10/10. Tests : 34 sur le lot, 147 avec les Lots 2→5.
- **Frontière** : `wiremap.built` sans règle d'identité en v0 (le gel la couvre). Consigné non traité :
  un doublon d'identité rend l'ancre du gel malformée — dédoublonner changerait un BLOCKED en PASS.

## La baseline — ne pas y toucher

```
EVIDENCE/runs/runm_breakout/      RUN M ter · 13/13 · verdict signé · verify_run AUTHENTIQUE
GAMES/runm_breakout/              le jeu produit
```
⛔ **Ni déplacer ni renommer ni écraser** (le reçu d'oracle porte un chemin relatif) ; un prochain run
porte un AUTRE nom de projet. Archives : `_ARCHIVE_RUN_M_*` (preuves du VOID et du HALT d'encodage).

## État de la thèse V2 et de T0

**T0 au 2026-09-04** : 2544 verts / 42 échecs — population V1 classée au Lot 0, **strictement inchangée**
(liste des `FAILED` comparée à chaque lot). **Thèse V2** : GAME_BLUEPRINT, capacités convocables,
Director, emitter branché, contrat de re-convocation = Lots 1→6 ; `dispatch.ORDER` reste (13 stations,
contourné, jamais retiré) ; GAME_FLOW · UX · design_metrics : DOCUMENTED_ONLY.

## Défauts connus, nommés, non corrigés

| | |
|---|---|
| le jeu produit **se gagne sans joueur** (456 frames = partie sans entrée) et son oracle de solvabilité le valide | variance nulle, règle 2026-07-21 |
| `s6-redteam-plan` rend **0 finding par construction** | hérité V1, profil identique sur 3 runs V1 |
| convention `logic.test.mjs` / `properties.test.mjs` **écrite dans aucun contrat** | coût mesuré : une tentative de builder |
| `premortem_lessons` **sans filtre projet** · ESC-1 **non vérifié en run réel** · `U-2` · `U-3` · `P-1` | fuite inter-projets ; prouvé au point de décision seulement ; hors migration, au registre |

## À faire au prochain lot (tranché Pierre 2026-09-04)

**Isoler le journal des tests.** Les suites Lots 4→6 écrivent dans le journal de production partagé
`EVIDENCE/reports/error_journal/html.jsonl` (13 lignes `jeu-1` / `p3_alpha-1`) : `record_error` retombe
sur `_domain_journal_path` sans `journal_path` explicite (`studio_link.py:357`). Ces lignes **ne sont
pas commitées** — mélanger données de test et historique réel serait de la dette documentaire. Geste :
forcer un `journal_path` tmp_path dans les 5 fichiers concernés (`test_driver_journal_autowire`,
`test_error_journal_resolution`, `test_journal_domains`, `test_playtest_capture`, `test_studio_link`),
puis nettoyer dans un lot dédié. Jamais nettoyer avant d'avoir supprimé la cause.

## Décisions ouvertes

- **Q2 / R8** — verrou World Scan, **jamais levé implicitement** ; intact depuis le début.
- `GAMES/pacman/00_CHARTER` et `09_WIREMAP` : absents du HEAD canonique, **non copiés, non reconstitués**.
- `docs/ARCHI.md` · `docs/forge/RUN2_PROTOCOLE_V1_PROPOSED.md` : cités, absents du HEAD, non inventés.

## Registres

`DECISIONS_TO_EXECUTE.md` · `BASELINE_M_TER.md` · `RUN_M_*_RESULTAT.md` · `LOT_*.md` ·
`V2_VALIDATION_CLOTURE.md` · `TOPOLOGY.md` (règles R1–R11).

**`claim_verdict: NO_CLAIM_ALLOWED`.**

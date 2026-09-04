# ÉTAT COURANT — Studio V2

*2026-09-04. Handoff inter-sessions, **< 100 lignes**. Ratifié Pierre 2026-09-03 : ce fichier EST le
handoff de V2, `studio_brain/00_CURRENT_CONTEXT.md` (V1) n'est plus mis à jour — une règle documentée
ne rompt jamais un invariant plus fort, « V1 en lecture seule » prime sur `CLAUDE.md`.*

## Où en est le studio

```
V1  C:\TACTICAL_CHESS_STUDIO        HEAD 58095ba9   SOURCE CANONIQUE, lecture seule
    4 écarts (dispatch.py, oracles.json, 2 tests) = autre session, jamais migrés
V2  C:\Users\Studio-Dev\Desktop\Studio2   (renommé 2026-09-04 ; remote github.com/pierrelouisfradcourt-create/Studio2)
    3481089 Lot 1 · 523bd07 Lots 2-4 · bc23133 Lot 5 · 8892189 Lot 6 · ba2d046 poussé
    Lot 7 en attente de GO commit

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

## Lot 6 — contrat de re-convocation (commité `8892189` ; spec+plan `464150e`)

*Détail complet : message du commit et `docs/superpowers/specs|plans/2026-09-04-lot6-*`.*

- **Identité de section** (`forge/identity.py`) : clé canonique par section au registre
  (`wiremap.design` = résolveur nommé `@frozen_features_from_wiremap`, mesuré). Une re-convocation
  reçoit sa **production précédente** ; un id encore cité en aval qui disparaît refuse l'écriture
  (`ID_REFERENCED_DROPPED`, section intacte) ; un retrait déclaré n'est accepté que si plus rien ne
  le cite. **Preuve réelle** : 10/10 ids conservés, là où le Lot 5 en avait renommé 10/10.
- **Acquittement** (`forge/acknowledgement.py`) : fence dédiée, 5 statuts, un message ne s'acquitte
  qu'une fois ; `rejected` produit un **désaccord** puis une question — trois objets distincts.
- **Director** : le refus d'identité vise l'écrivain de la section d'après le registre.
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

## Lot 7 — isolation du journal des tests (2026-09-04, GO Pierre ; spec+plan `docs/superpowers/`)

**Cause mesurée par bissection**, et elle a falsifié ma note précédente : les 5 fichiers que j'avais
désignés d'après leur nom ne fuient pas ; les coupables sont `test_measure_tick` (+2392 octets) et
`test_mutation_path_repo_relative` (+537), somme = le delta de la suite entière. Ils monkeypatchent
`driver._REPO_ROOT` sur leur `tmp_path` pour exercer la branche « run_dir sous le dépôt » :
`_journal_target()` rend alors `None` (route par domaine) et l'écriture part dans le vrai journal.
Leur passer un `journal_path` supprimerait ce qu'ils mesurent — c'est la **destination** qu'on isole.

**Correctif** : la fixture `autouse` `_isolate_evidence_writes` (qui couvrait déjà l'audit et deux
fichiers de résultats) redirige aussi `DOMAIN_JOURNAL_DIR`, `DEFAULT_ERROR_JOURNAL` et `FORGE_REPORTS`
— dans `studio_link` **et** `learning_memory`, à la même valeur (import par valeur, même piège que les
deux `DEFAULT_AUDIT`). 4 tests de périmètre ajoutés. Aucun code de production touché.
**Mesuré : 2929 → 0 octets**, index compris.

**Reste : un lot de nettoyage dédié** pour les lignes déjà écrites (78 au HEAD du Lot 6 + celles du
rouge de ce lot), non commitées. La cause étant supprimée, le nettoyage est désormais possible.

## Décisions ouvertes

- **Q2 / R8** — verrou World Scan, **jamais levé implicitement** ; intact depuis le début.
- `GAMES/pacman/00_CHARTER` et `09_WIREMAP` : absents du HEAD canonique, **non copiés, non reconstitués**.
- `docs/ARCHI.md` · `docs/forge/RUN2_PROTOCOLE_V1_PROPOSED.md` : cités, absents du HEAD, non inventés.

## Registres

`DECISIONS_TO_EXECUTE.md` · `BASELINE_M_TER.md` · `RUN_M_*_RESULTAT.md` · `LOT_*.md` ·
`V2_VALIDATION_CLOTURE.md` · `TOPOLOGY.md` (règles R1–R11).

**`claim_verdict: NO_CLAIM_ALLOWED`.**

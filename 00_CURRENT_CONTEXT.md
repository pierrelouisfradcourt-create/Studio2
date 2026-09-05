# ÉTAT COURANT — Studio V2

*2026-09-05. Handoff inter-sessions, **< 100 lignes**, écrit depuis l'état git mesuré. Aucun
verdict global « ready » n'est émis ici — `claim_verdict: NO_CLAIM_ALLOWED`.*

## Où en est le studio

```
V1  C:\TACTICAL_CHESS_STUDIO          HEAD 58095ba9   SOURCE CANONIQUE, lecture seule
V2  C:\Users\Studio-Dev\Desktop\Studio2   HEAD d954acb+  (voir git log — ce fichier ne peut porter son propre commit)
```

⚠️ **V2 n'a PAS de `CLAUDE.md`** (retiré de `reference_protected.yaml` le 2026-09-04) : seules les règles
de `.claude/rules/` sont injectées. **Ouvrir les sessions DANS Studio2** (hooks V1 sinon ; `pretool_git_guard` V2 refuse `git checkout --` sans sentinel).

## ReferenceGuard — actif, advisory, jamais exécuté en run réel

```
status CLEAN · 541 fichiers · baseline ancrée sur 80b6847 · 51dd64693f211a49…
surfaces protégées : GAMES/pong/** · forge/** · control_plane/registry.py · .claude/hooks/**
```
Détection **prouvée trois fois** (falsification, restauration, GO U1–U6 : `DRIFT` sur exactement les
6 fichiers autorisés). Advisory, **jamais exécutée dans un run Forge de bout en bout** — dette de
preuve principale. Ré-ancrée : un `DRIFT` en run sera un mouvement DU RUN.

## Surfaces de test — doctrine ratifiée 2026-09-04

`forge/test_surfaces.yaml` → `forge.protected_surfaces` → `run_real._STEP_DISALLOWED`. Régime
**`create_allowed_modify_denied`** : créer permis, MODIFIER un test préexistant = gate. Surfaces :
`forge/tests/**` · `GAMES/*/tests/**` · `GAMES/*/07_TESTS/**`. **Portée : étapes Forge SEULES** —
sessions et sous-agents bornés par AUCUN mécanisme (hook abandonné), empreinte pour témoin.

⚠️ **14 fichiers de `forge/tests/**` modifiés sous GO CONVERSATIONNEL (`AUTO_ATTESTED`)** : le
sentinel `.claude/HUMAN_GIT_OVERRIDE.json` **n'existe pas dans V2** — la garde rapporte
`authorized: false`, légitimement. Commits `445dd5d`, `d591dd6`, `80b6847` ; empreinte ré-ancrée APRÈS.

## Architecture Director — pipeline fixe + boucles de reprise

`dispatch.ORDER` = **13 stations** immuables (`full_content` : 18). Le Director décide ENTRE les
stations : `convoke` · `reconvoke` (objection nommée) · escalade · `halt`. Mesuré sur
`v2_breakout_slice_r1` : 13 décisions, wiremap ×2, builder ×3, `halt` après 3 oracles rouges, puis
`requalify` (Pierre) et `humangate`. **4 capacités pilotées** (`decompose` · `architect` · `wiremap`
· `builder`), le reste en dispatch classique. Coût de référence : 6,67 $ / 57 min.

## T0 — 3 rouges / 2639 verts / 66 skipped / 4 xfailed (mesuré HEAD 80b6847)

41 → 20 (`d591dd6`, fixtures V1) → **3** (`80b6847`, GO U1–U6 : 13 tests ré-ancrés sur
`_V1_FIXTURES`, 4 rouges V1 rendus VISIBLES en `xfail(strict=True)` nommé — témoins, pas
maquillage ; « 0 failed » n'est pas l'objectif). Zéro changement de production.
**3 rouges = HUMANGATE_REQUIRED**, non touchés : `learning_memory` ×2 (corpus de méthode V1
absent, ET `conftest.py:54-100` redirige le journal pour tout module — inatteignables par
construction) · `manifest_lesson_promotion` (`EVIDENCE/runs/pacman-v3` non migré).
**4 xfail** : `runtime_inventory_oracle` ×2 (conditionnel : `scripts/` absent ∧ `CODE_GLOBS`
V1) · `reuse_ratio_wired` (`kb_tactics` non retenu) · `commit_scope_guard` (`asset_lessons`
NOT_YET_PRODUCED, dérivé du producteur, jamais créé).

## Fixtures V1 — migrées, isolées, provenance marquée

`EVIDENCE/_V1_FIXTURES/` (README = source des règles) : **PAS des preuves V2**, lues par 33 tests / 10 fichiers
(+ `pacman-v3`, HG2). Briefs `p1_alpha/`, `p1_beta/` restent canoniques (lus par la PRODUCTION), avec `PROVENANCE_V1.md`.

## Ce qui bloquait, et qui est levé

`check_decompo.mjs` exigeait `main.tscn` pour toute action joueur → tout jeu **web** refusé.
`POINTS_ENTREE` + `--entree` (`80b2e08`), contrat `s3-decompo` aligné, cas réel rejoué 2 → 0.
**Sur 12 dossiers de `GAMES/`, V2 n'en a produit que 3 — tous WEB** ; la lignée Godot existe
(contrats, oracles, 4 profils) mais **jamais exercée par V2**.

## Défauts de qualité connus, non corrigés

- le jeu produit **se gagne sans joueur** et l'oracle de solvabilité le valide (variance nulle, 2026-07-21)
- `s6-redteam-plan` rend **0 finding par construction** (hérité V1)
- convention `logic.test.mjs` / `properties.test.mjs` **écrite dans aucun contrat** — le builder l'a devinée
- `runtime_inventory_oracle` : branche `scripts/**` (`CODE_GLOBS`, l.37) **structurellement morte en
  V2** — `observed_in_code()` rend `[]`, `runtime_drift.jsonl` ne portera jamais d'`ALERTE_CODE` ;
  mesuré : 3 appelants de modèle dans `forge/` invisibles (`qwen_spec.py`, `repair_step.mjs`,
  `run_real.py` — seul ce dernier non déclaré dans `roles.yaml`). Ré-ancrage = chantier production.
- `forge/oracles.json` : **17/32** entrées `cwd` vers des dossiers absents ; 3 tests node hors T0 rouges (`kb_tactics`).
- ⚠️ une **autre session écrit dans Studio2** (`dispatch_dryrun.jsonl`, `briefs/chaton_clicker/`, `test_slice_lot4`
  écrit dans le VRAI `EVIDENCE/runs/` + `GAMES/`) — TOPOLOGY §8.3.
- **DIRECTOR-V0-BOOTSTRAP-001** — Director v0 **ne démarre pas d'un blueprint issu du seul brief** : il exige
  `gameplay` (← `contract_author`) puis `understanding.prisme` (← `prisme`), capacités `locked`/non `invokable_v0`,
  matérialisées par `run_real` hors chemin JSON. Mesuré `v2_breakout_full_r1` : halt à D-1, 0 $, aucun `decompose`
  atteint. Pas un défaut du blueprint (`validate()==[]`), pas un échec de la boucle aval (`_slice_r1` l'a exercée
  depuis un amont importé). **Chantier v1 : amorçage depuis brief.**

## Chantiers différés, décidés non ouverts

- **providers** — 33 lignes, 0 consommateur, `providers.yaml` absent, 0 test ; `TOPOLOGY.md` a tranché « dehors », l'exécution manque.
- **`TOOLS/`** — `control_plane/` non tranché ; ⚠️ `scan_reasoning_readers` lit `registry.py` comme un fichier. **Synthèse V2** non écrite.
- **Prochaine décision** (HG1–HG3 closes `9be78d2`/`420d5a7`/`7a0e6df`) : suite de `v2_breakout_full` — A1 amorcer l'amont
  depuis `_slice` (2ᵉ échantillon Director) · A2 amont neuf par `run_real` (2 runs) · A3 chantier v1 seulement.
- Résidus V1 hors périmètre : `src/` dans 4 contrats · `scripts/**` dans `wm1` ·
  `pretool_agent_classify` journalise dans `lab/` (fantôme) avec `mkdir(parents=True)`.

## La baseline à ne pas toucher

`EVIDENCE/runs/runm_breakout/` + `GAMES/runm_breakout/` — ⛔ ni déplacer, renommer ni écraser (reçu
d'oracle à chemin relatif ; gel doctrinal, hors empreinte). Q2/R8 (verrou World Scan) intact.
**`software_verdict: OK` · `evidence_verdict: MECHANICAL_VALIDATION_ONLY` · `claim_verdict: NO_CLAIM_ALLOWED`**

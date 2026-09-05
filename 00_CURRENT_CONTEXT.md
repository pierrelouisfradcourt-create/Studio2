# ÉTAT COURANT — Studio V2

*2026-09-05. Handoff inter-sessions, **< 100 lignes**, écrit depuis l'état git mesuré. Aucun
verdict global « ready » n'est émis ici — `claim_verdict: NO_CLAIM_ALLOWED`.*

## Où en est le studio

```
V1  C:\TACTICAL_CHESS_STUDIO          HEAD 58095ba9   SOURCE CANONIQUE, lecture seule
V2  C:\Users\Studio-Dev\Desktop\Studio2   HEAD cda4cac   propre, synchronisé origin/master
```

⚠️ **V2 n'a PAS de `CLAUDE.md`** — fait mesuré, motif retiré de `reference_protected.yaml` le
2026-09-04. Une session ouverte ici n'a donc aucun fichier de doctrine projet chargé ; seules les
règles de `.claude/rules/` sont injectées. **Ouvrir les sessions DANS Studio2** : jusqu'au
2026-09-05 elles tournaient depuis V1, donc gardées par les hooks et permissions de V1 (mesuré :
`pretool_git_guard` de V1 a bloqué une commande en lisant le sentinel V1 vieux de 14 jours).

## ReferenceGuard — actif, advisory, jamais exécuté en run réel

```
status CLEAN · 541 fichiers · baseline ancrée sur 80b2e08 · c5fd9495b64397e6…
surfaces protégées : GAMES/pong/** · forge/** · control_plane/registry.py · .claude/hooks/**
```
Détection **prouvée deux fois** (falsification → `DRIFT`, restauration → `CLEAN`). Advisory : elle
rapporte, ne bloque rien, et n'a **jamais tourné dans un run Forge de bout en bout** — dette de
preuve principale. Ré-ancrée avant campagne : un `DRIFT` en run sera un mouvement DU RUN.

## Surfaces de test — doctrine ratifiée 2026-09-04

`forge/test_surfaces.yaml` → `forge.protected_surfaces` (lecteur unique) →
`run_real._STEP_DISALLOWED`. Régime **`create_allowed_modify_denied`** : créer un test est permis
(livrable du builder), MODIFIER un test préexistant demande une gate. Surfaces : `forge/tests/**` ·
`GAMES/*/tests/**` · `GAMES/*/07_TESTS/**`. **Portée : étapes Forge SEULES** — sessions et
sous-agents bornés par AUCUN mécanisme (hook spécifié puis **abandonné**), empreinte pour témoin.

⚠️ **8 tests de `forge/tests/**` ont été modifiés sous GO CONVERSATIONNEL, donc `AUTO_ATTESTED`**,
sans dérogation mécanique : le sentinel `.claude/HUMAN_GIT_OVERRIDE.json` **n'existe pas dans V2**
(un seul exemplaire sur le poste, dans V1, daté du 21 août, sans champ `paths`). La garde rapporte
donc légitimement `authorized: false` sur ces écarts. Voir commits `d591dd6` et `445dd5d`.

## Architecture Director — pipeline fixe + boucles de reprise

Ni linéaire pur, ni plan libre. `dispatch.ORDER` = **13 stations** en ordre immuable ; le profil
`full_content` en active **18** (étapes de contenu insérées avant le prisme).
Le Director décide ENTRE les stations, sur mesure : `convoke` · `reconvoke` (avec objection
nommée) · escalade de modèle · `halt`. Mesuré sur `v2_breakout_slice_r1` : 13 décisions, wiremap
re-convoqué ×2, builder ×3, `halt` après 3 oracles rouges, puis `requalify` (Pierre) et `humangate`.
**4 capacités pilotées** par le Director v0 : `decompose` · `architect` · `wiremap` · `builder`.
Les autres étapes passent par le dispatch classique. Coût de référence : 6,67 $ / 57 min.

## T0 — 20 rouges / 2626 verts

Population passée de **41 à 20** le 2026-09-05 : 21 tests de la chaîne étaient **inertes faute de
fixtures V1**, jamais cassés (tous en `FileNotFoundError`, aucun sur une assertion).
Répartition restante, **non triée** — plusieurs portent encore des noms de fixtures V1, même cause
probable, NON MESURÉE :
`10 micro_redeclaration · 2 runtime_inventory_oracle (scripts/council.py, claude_proxy.py) ·
2 mutation_scope_categories · 2 learning_memory · 1 chacun : reuse_ratio_wired, reference_guard
(cli), manifest_lesson_promotion, commit_scope_guard`

## Fixtures V1 — migrées, isolées, provenance marquée

`EVIDENCE/_V1_FIXTURES/` : 417 fichiers versionnés (565 copiés, le reste = caches `.godot` et
`.log`), avec un `README.md` portant provenance et règles. **Ce ne sont PAS des preuves V2.**
**Limite** : l'isolement ne vaut que là où le TEST résout le chemin. Deux briefs
(`EVIDENCE/briefs/p1_alpha/`, `p1_beta/`) ont dû rester à l'emplacement CANONIQUE car lus par du
code de PRODUCTION ; chacun porte un `PROVENANCE_V1.md`. À exclure de tout inventaire de projets.

## Ce qui bloquait, et qui est levé

`check_decompo.mjs` exigeait le littéral `main.tscn` pour toute action joueur → tout jeu **web**
refusé structurellement. `POINTS_ENTREE` (mesuré : 6 jeux Godot en `main.tscn`, 4 web en
`index.html`/`main.mjs`) + `--entree` ; contrat `s3-decompo` aligné ; cas réel rejoué 2 → 0.
**Sur 12 dossiers de `GAMES/`, V2 n'en a produit que 3 — tous WEB** (les 9 autres viennent de
`2769dc8`). La lignée Godot existe (contrats, oracles, 4 profils) mais **jamais exercée par V2**.

## Défauts de qualité connus, non corrigés

- le jeu produit **se gagne sans joueur** et l'oracle de solvabilité le valide (variance nulle, 2026-07-21)
- `s6-redteam-plan` rend **0 finding par construction** (hérité V1)
- convention `logic.test.mjs` / `properties.test.mjs` **écrite dans aucun contrat** — le builder l'a devinée

## Chantiers différés, décidés non ouverts

- **providers** — 33 lignes, **0 consommateur** mesuré par import, `providers.yaml` absent, 0 test.
  `TOPOLOGY.md` a déjà tranché « elles restent dehors » ; l'exécution manque. NB : la gate 2 a
  orphelin `load_capabilities`.
- **`TOOLS/`** — emplacement de `control_plane/` non tranché. ⚠️ `scan_reasoning_readers` lit
  `control_plane/registry.py` **comme un fichier** : le déplacer la casse. · **synthèse V2** non écrite.
- Résidus V1 hors périmètre : `src/` dans 4 contrats · `scripts/**` dans `wm1` ·
  `pretool_agent_classify` journalise dans `lab/` (fantôme) avec `mkdir(parents=True)`.

## La baseline à ne pas toucher

`EVIDENCE/runs/runm_breakout/` + `GAMES/runm_breakout/` — ⛔ ni déplacer, renommer ni écraser (le reçu
d'oracle porte un chemin relatif). Q2/R8 (verrou World Scan) intact, jamais levé.

**`software_verdict: OK` · `evidence_verdict: MECHANICAL_VALIDATION_ONLY` · `claim_verdict: NO_CLAIM_ALLOWED`**

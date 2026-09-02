# Chantier unique — GAMEPLAY CONTRACT, extension DÉCISION : point de décision + sonde à deux trajectoires

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. TDD strict, fixtures RÉELLES
> (Prisme / loop.json / build du run 8b archivés `lab/forge_runs/kitten_clicker/_run8_20260821h2/` = baseline), jamais de
> commit par un sous-agent, un seul commit de clôture (gate Pierre). **Aucun système nouveau** : `loop.json` reste la projection
> déterministe du Prisme ; on ajoute UN rôle (`DECISION`) et la sonde apprend à produire des trajectoires contre-factuelles.
> Hors périmètre : oracle LLM, station, profil, narration, architecture, « plusieurs heures », vocabulaire STANDARD/Prisme,
> reuse, red-team, `check_wiremap_contract` (passif connu), solvabilité descripteur, e2e `DirAccess`, retry BLOCKED.

*Date : 2026-08-23 · Source : GO Pierre « contrat exécutable : point de décision + sonde à deux trajectoires », sur la
définition ratifiée `studio_brain/gamedesign/kitten_clicker_decision_significative.md` (V2).*

**Goal :** qu'un run de la Forge puisse dire FAIL si le jeu n'offre pas de décision significative (6 preuves
INFORMATION · CHOICE · IMMEDIATE · FUTURE · NON-DOMINANCE · PLAYER GOAL), mesurée par le bot-joueur (InputEvent + écran
seulement) sur **plusieurs trajectoires depuis le même état initial**, sans override.

**Architecture :** le Prisme porte une exigence `loop_role: DECISION` (`options` = 2 refs d'exigences à affordance, `policies`
≥ 2, `metric` hud, `horizon_frames`) → `loop_spec.mjs` la projette en step `DECISION` → `player_loop.gd`, à ce step, rejoue
le préfixe sur une scène ré-instanciée pour chaque (option × politique), puis évalue les 6 preuves → le driver gate déjà
(`loop_dead`). Contrat s9 : deux dépenses exclusives, coût + effet affichés, affordance propre à chaque branche,
objectif qui nomme la possibilité ouverte, économie déterministe.

## Le step DECISION (projection déterministe ; forme figée)
```json
{ "role": "DECISION", "ref": "d_first_spend",
  "options": ["p_buy_kitten", "p_upgrade_click"],         // refs de steps B ou F portant `affordance`
  "metric": "ronrons",                                    // hud mesuré pour la non-dominance
  "horizon_frames": 300,
  "policies": [ { "name": "idle",  "click": null,     "every_frames": 0 },
                { "name": "actif", "click": "pelote", "every_frames": 3 } ],
  "observe": { "hud": "objectif", "predicate": "changes" }, "wait_frames": 30 }
```
Les six preuves, telles que la sonde les calcule (tout par groupes `affordance` / `hud`) :
1. **INFORMATION** : au step, pour chaque option `x` : affordance `x` visible (`is_visible_in_tree()`, non `disabled` si
   BaseButton) ET Labels hud `cout_<x>` et `effet_<x>` non vides.
2. **CHOICE / DIFFÉRENCE** : pour chaque option, ré-instancier `main.tscn`, vérifier `hud_vector(boot) == hud_vector(boot de
   la 1ʳᵉ trajectoire)` (sinon FAIL « état initial non reproductible »), rejouer le PRÉFIXE (tous les steps avant DECISION, même
   mécanique), cliquer l'option, attendre `wait_frames` → `S_x = {hud_vector, affordance_set}`. PASS ssi `S_A ≠ S_B`.
3. **IMMEDIATE** : pour chaque option, `hud_vector` après clic ≠ `hud_vector` juste avant le clic.
4. **FUTURE** : `affordance_set(A') ≠ affordance_set(B')` OU (`cout_*` labels différents entre A' et B').
5. **NON-DOMINANCE** : pour chaque politique p et chaque option x : trajectoire (préfixe → x → politique p pendant
   `horizon_frames`) → `metric_{x,p}` = nombre du hud `metric`. PASS ssi ∃ p, q : `metric_{A,p} > metric_{B,p}` ET
   `metric_{B,q} > metric_{A,q}` (strict). Rapporter la matrice complète.
6. **PLAYER GOAL** : `objectif(A') ≠ objectif(B')` ET `objectif(A') ≠ objectif(avant)` ET `objectif(B') ≠ objectif(avant)`.
Trajectoires : 2 (preuves 2-4, 6 ; `wait_frames`) + 2 × |policies| (preuve 5). Le step DECISION PASS ssi les 6 passent ;
raison nommée par preuve (`DECISION d_first_spend : FUTURE — affordances identiques {…}`). Après le step DECISION, la sonde
**continue la séquence** sur la trajectoire de la PREMIÈRE option (convention : `options[0]`), scène ré-instanciée et
préfixe rejoué, pour que F…J restent mesurables.

---

### T1 — `upstream_schema.mjs` + `loop_spec.mjs` + contrat s1 + tâche s1 (Sonnet)
**Files :** `scripts/forge/upstream_schema.mjs`, `scripts/forge/loop_spec.mjs` (+`.test.mjs`), `scripts/forge/contracts/s1-prisme.yaml`,
`lab/forge_runs/kitten_clicker/tasks.json` (clé `s1-prisme` seulement), `scripts/forge/tests/test_loop_spec_materialized.py`.
- `LOOP_ROLES` += `DECISION` (dans `ROLE_ORDER` entre `REWARD` et `UNLOCK`) ; `validateExigence` additif : `options` (2 strings
  distincts), `policies` (≥ 2, `name` distincts, `click` string|null, `every_frames` int ≥ 0, `click` ⇒ `every_frames` ≥ 1),
  `metric` string, `horizon_frames` int ≥ 60.
- `deriveLoopSpec` : recopie `options`, `metric`, `horizon_frames`, `policies` sur le step DECISION (ordre des policies =
  ordre du Prisme ; tri stable inchangé).
- `checkLoopSpec` : ≥ 1 DECISION ; chaque `options[i]` est la `ref` d'un step de rôle B ou F **portant `affordance`**, affordances
  distinctes ; `policies` ≥ 2 dont `click` référence une affordance d'un step B (ou null) ; `metric` = un hud déjà observé par un
  autre step ; `observe.hud === 'objectif'`. Problèmes nommés par maillon (`DECISION (ref) : …`).
- Baselines : `_run8_20260821h2/loop.json` → FAIL « aucun step DECISION » ; fixture synthétique avec DECISION → OK ; déterminisme
  (hash identique). `test_loop_spec_materialized.py` : la matérialisation porte le step DECISION.
- Contrat s1 : exigence DECISION obligatoire, sa forme, ses règles ; tâche s1 : les deux branches ratifiées (A adopter
  `acheter_chaton` / B améliorer `acheter_amelioration`), politiques `idle` / `actif` (pelote toutes les 3 frames), metric
  `ronrons`, horizon 300.

### T2 — Sonde `player_loop.gd` : trajectoires contre-factuelles (Sonnet, confrontation Fable sur le build 8b)
**Files :** `scripts/forge/godot_probes/player_loop.gd`, `scripts/forge/tests/test_player_loop_probe.py`, `scripts/forge/product_oracle_godot.py`
(seulement si un passthrough manque).
- Invariant : InputEvent + groupes `affordance`/`hud` seulement (test statique inchangé, `check_loop_bypass` inchangé).
- Ré-instanciation : `_reset_scene()` libère l'enfant racine courant (`queue_free` + attendre une frame), `seed(0)`,
  instancie de nouveau la PackedScene, attend `boot_frames` (= frames écoulées avant le 1ᵉʳ step de la 1ʳᵉ trajectoire),
  compare `hud_vector` au vecteur de boot initial.
- Machine à phases existante (`before → inject → wait → evaluate`) réutilisée : le step DECISION s'étend à l'init en une file de
  tâches (`decision_traj` × N, `decision_eval`, puis `decision_continue`), comme REPEAT l'a fait (`_build_run_queue`).
- Sortie : `data.decision = { ref, options, boot_reproducible, information:{A:…,B:…}, states:{A:{hud,affordances,objectif},B:…},
  immediate:{A:bool,B:bool}, future:bool, nondominance:{matrix:{A:{idle:n,actif:n},B:{…}}, pass:bool},
  player_goal:bool, pass:bool, reasons:[…] }` ; `reached_role` inchangé en sémantique.
- Tests : (a) statiques (tokens `DECISION`, `policies`, `_reset_scene`) ; (b) payload passthrough ; (c) **réel sur le build 8b
  archivé** (`_run8_20260821h2/game_build8`, `KC_LOOP_JSON_OVERRIDE`, tmp) avec un step DECISION synthétique
  `options: [p_buy_kitten, p_unlock_location]` (les deux affordances existent) : attendu mesuré — INFORMATION FAIL (pas de
  `cout_*`/`effet_*`) et/ou FUTURE FAIL (4 → 4 affordances) ; la matrice non-dominance est RAPPORTÉE même si le step FAIL ;
  figer les valeurs mesurées, jamais ajuster la sonde au plan ; (d) `boot_reproducible` vrai sur ce build (aucun autoload).

### T3 — Contrat s9 + tâche s9 (Fable, en direct)
- s9 (ajouts) : réaliser la DÉCISION de loop.json : les options sont deux dépenses **exclusives à l'instant** (acheter l'une
  rend l'autre inaccessible jusqu'au prochain seuil — ou coût commun), chaque option a un Label hud `cout_<affordance>` et
  `effet_<affordance>` non vides, chaque branche fait APPARAÎTRE une affordance qui lui est propre (A : `placer_au_jardin`,
  B : `caresse_longue`), les courbes de coût divergent, `objectif` nomme la possibilité ouverte par la branche prise ;
  **économie déterministe** (aucun `randi/randf` sur les valeurs économiques ; la rareté visuelle peut rester aléatoire mais
  ne touche aucun nombre du HUD) ; aucun état hors scène (pas d'autoload, pas de `static var` sur l'économie).
- Tâche s9 `tasks.json` : mêmes phrases, concrètes pour Kitten Clicker ; hypothèse de balance idle/actif à RÉALISER (c'est
  au jeu d'être équilibré, à la sonde de le mesurer).
- Validation : `pytest test_contract_sync.py test_s9_contract_loop_rule.py test_contract.py`, dry-run 17.

### T4 — Confrontation + commit + run 9
- Fable rejoue : `node --test scripts/forge/**/*.test.mjs` (0 fail), `pytest scripts/forge/tests -q` (0 fail hors skips Godot),
  `node loop_spec.mjs _run8_20260821h2/prisme.json` → FAIL nommant DECISION absent, sonde réelle sur `game_build8`.
- Un commit. Archivage : le build courant `games/kitten_clicker/` = run 8b (déjà archivé) → déplacé au scratchpad ; run_dir purgé
  (`design_intent.md`, `tasks.json` conservés). Run 9 `kitten_clicker-20260823a`, `full_godot_content`, sans `--charter`,
  depuis la session, Monitor.
- **PASS logiciel** = le bot traverse A → J ET le step DECISION PASS (6/6) sans override. Toute rupture reste une rupture
  (spec / décompo / wiremap / build / runtime / **balance** : la non-dominance est une mesure de design, un FAIL ici est une
  information, pas un bug de sonde). HumanGate Pierre ensuite, jamais codé.

## Risques nommés
- Aléa dans l'économie (rareté des chatons) → trajectoires non comparables : contrat s9 + `seed(0)` + contrôle
  `boot_reproducible` ; si la valeur HUD diffère au boot, FAIL explicite.
- Durée de sonde : 1 + 2 + 4 trajectoires × (préfixe ≈ 300 frames + 300) ≈ 2 500 frames ≈ 45 s en fenêtre GPU — sous le
  timeout `run_player_loop` (à vérifier ; relever le timeout si mesuré insuffisant).
- Le builder pré-sélectionne une option (une seule achetable au seuil) → INFORMATION FAIL : c'est voulu.
- La politique `actif` clique `pelote` ; si la pelote est remplacée par `caresse_longue` après B, la politique reste sur
  `pelote` (convention : la politique ne connaît que les affordances de départ).

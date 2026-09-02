# Lot V4 — GAME LOOP : le sujet PLAYER entre dans le contrat de production, et un bot-joueur le prouve

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. TDD strict, fixtures
> RÉELLES (run 6 : `lab/forge_runs/kitten_clicker/_run6_*` + build `games/kitten_clicker/`), jamais de commit par
> un sous-agent (un seul commit de clôture, gate Pierre). Plan avant code — ce document EST l'artefact demandé.

*Date : 2026-08-22 · Source : session Fable, cadrage Pierre après playtest du run 6 et audit gameplay confronté.*

**Diagnostic (mesuré)** : *la boucle n'a pas été perdue par le runtime ; elle a été transformée en effets sans sujet
joueur avant d'arriver au Builder.* Charter (d) : « quêtes affichées à l'écran » → Prisme : 25 exigences à la voix
passive (« Acheter un chaton fait apparaître… »), **0 « le joueur PEUT »** → Grey Blocks / WireMap / Builder / oracles
reproduisent fidèlement : `input.gd` = 1 signal `clic_pelote`, `api_buy_kitten/upgrade/prestige` 0 appelant runtime,
production gardée par `kittens.size() > 0` jamais vraie, quêtes lues jamais consommées, objets sans effet, ni menu ni
guidage ; **les oracles ont validé la boucle par un canal que le joueur n'a pas** (`main_screen_render.gd:82` appelle
`api_buy_kitten` ; `solvability.gd` pilote `Economy` sans `main.tscn`) — d'où « solvabilité 20/20 » sur un jeu
injouable.

**Séquence imposée (Pierre)** : PLAYER_GOAL → PLAYER_ACTION → AFFORDANCE → GAME_RESPONSE → REWARD → UNLOCK → NEXT_GOAL
→ META_LOOP, puis seulement WireMap → Builder → Runtime. **On ne touche pas au Builder d'abord** : le contrat de
production de la boucle joueur est corrigé en amont ; le builder est re-joué (run 7) sous ce contrat. Pas de nouveau
système, pas d'oracle général. V3.1 (sonde inconditionnelle, dépôt `09_WIREMAP`) reste un lot séparé.

## Verrous d'exécution (GO Pierre 2026-08-22)
- **`loop.json` = projection DÉTERMINISTE du Prisme, jamais une source de vérité.** `Prisme → projection →
  loop.json → s3 → s5 → s9 → main.tscn → player_loop`. JAMAIS `LLM → loop.json → jeu` : l'exécuteur dérive et
  écrit ; si un agent émet un `loop.json`, il est ignoré/écrasé ; le builder DÉPOSE une COPIE (`03_WORLD/loop.json`)
  dont le sha256 doit égaler celui du run_dir — mismatch = FAIL de la sonde (« loop.json altéré »).
- Ordre strict avec gate de confrontation (orchestrateur) entre chaque : T1 → `checkLoopSpec` → T2 → test
  décomposition → T3/T4 → T5 (sonde validée sur le build réel du run 6 = baseline) → commit → run 7 → `player_loop`.
- **Garde anti-contournement NON NÉGOCIABLE** : `player_loop` = uniquement `InputEvent` + lecture écran ; interdits
  partout où une boucle est prouvée (volets, `solvability.gd`, sonde) : `Economy`, `api_buy_kitten()`,
  `api_buy_upgrade()`, `api_prestige()`, `05_SYSTEMS`, `runtime.gd`.
- Critère V4 logiciel : le bot atteint META_LOOP depuis `main.tscn` avec les seules entrées d'un joueur. HumanGate
  ensuite : Pierre comprend-il quoi faire sans explication externe ? Les deux peuvent diverger — c'est voulu.
- Pas de dérive : ni station, ni profil, ni famille de preuve, ni refonte WireMap, ni reuse_ratio, ni s10s, ni
  théorie de solvabilité ; V3.1 séparé. Question du run 7 : *peut-on réellement jouer ce que la Forge a forgé ?*

## Global Constraints
- Jamais `git commit/push` par un agent ; jamais `git add -A` ; `tests/**` racine intouché ; driver sans `subprocess`.
- `PROOF_KINDS` fermé, inchangé ; `acteur` / `affordance` / `observe` / `loop_role` sont des champs ADDITIFS
  (les validateurs n'ont pas de schéma fermé — mesuré `upstream_schema.mjs`).
- Le bot-joueur n'appelle JAMAIS `Economy`, `Runtime`, `api_*`, un script `05_SYSTEMS` : uniquement `main.tscn`,
  des `InputEvent`, et la lecture de `Label` en groupe `hud`. Toute violation = FAIL statique.
- `claim_verdict: NO_CLAIM_ALLOWED` ; une mesure impossible = NOT_MEASURED, jamais un OK.

## Le contrat de boucle (données, pas code) — `loop.json`
Dérivé DÉTERMINISTEMENT de `prisme.json` (aucun LLM), matérialisé dans le run_dir après s1, injecté dans s3/s5/s9,
déposé par le builder en `03_WORLD/loop.json`, rejoué par le bot-joueur :
```json
{ "schema_version": 1, "game_id": "kitten_clicker",
  "steps": [
    {"role": "PLAYER_GOAL",   "ref": "PG1", "observe": {"hud": "objectif", "predicate": "nonempty"}},
    {"role": "PLAYER_ACTION", "ref": "PA1", "affordance": "pelote", "repeat": 15,
                              "observe": {"hud": "ronrons", "predicate": "increases"}},
    {"role": "PLAYER_ACTION", "ref": "PA2", "affordance": "acheter_chaton",
                              "observe": {"hud": "collection", "predicate": "increases"}},
    {"role": "GAME_RESPONSE", "ref": "GR1", "observe": {"hud": "taux", "predicate": "increases", "wait_frames": 120}},
    {"role": "REWARD",        "ref": "RW1", "observe": {"hud": "ronrons", "predicate": "increases", "wait_frames": 120}},
    {"role": "UNLOCK",        "ref": "UN1", "affordance": "acheter_amelioration", "observe": {"hud": "taux", "predicate": "increases"}},
    {"role": "NEXT_GOAL",     "ref": "NG1", "observe": {"hud": "objectif", "predicate": "changes"}},
    {"role": "META_LOOP",     "ref": "ML1", "affordance": "prestige", "observe": {"hud": "prestige", "predicate": "increases"}}
  ]}
```
Conventions runtime (exigées par le contrat s9, prouvées par le bot) : chaque `affordance` = un nœud **`Control`**
(Button/TextureButton/Area cliquable) ajouté au groupe `affordance` avec `name` = l'affordance ; chaque `observe.hud`
= un `Label` ajouté au groupe `hud` avec `name` = la clé. Prédicats : `nonempty` · `increases` · `changes` · `contains:<txt>`.

---

### Task 1 — Prisme : le sujet PLAYER (contrat s1 + validateur additif + dérivation de `loop.json`)
**Files:** Modify `scripts/forge/contracts/s1-prisme.yaml` · Modify `scripts/forge/upstream_schema.mjs`
(`validateExigence`) · Create `scripts/forge/loop_spec.mjs` (+ `.test.mjs`) · Modify `scripts/forge/run_real.py`
(matérialiser `loop.json` après `prisme.json`, même patron que `_materialize_yaml`, reçu `loop_check`) ·
Test `scripts/forge/tests/test_loop_spec_materialized.py`.
- **Contrat s1** (ajouts, rien retiré) : chaque exigence porte `acteur: "PLAYER"|"SYSTEM"` ; une exigence PLAYER
  porte `affordance` (nom de la cible cliquable) **ou** est un objectif affiché ; chaque exigence porte
  `loop_role` ∈ {PLAYER_GOAL, PLAYER_ACTION, GAME_RESPONSE, REWARD, UNLOCK, NEXT_GOAL, META_LOOP, NONE} et
  `observe: {hud, predicate}` quand elle est observable à l'écran. RÈGLE : **au moins une exigence par rôle**, et
  les rôles PLAYER_ACTION / UNLOCK / META_LOOP sont à la **voix active avec le joueur pour sujet**
  (« Le joueur peut acheter un chaton en cliquant la cible `acheter_chaton` ; la collection affichée augmente »).
- **`validateExigence`** (additif) : si `acteur` présent → ∈ {PLAYER, SYSTEM} ; si `loop_role` présent → dans la
  liste ; si `loop_role` ∈ {PLAYER_ACTION, UNLOCK, META_LOOP} → `acteur == "PLAYER"` ET `affordance` non vide ET
  `observe.hud`/`observe.predicate` valides ; si `loop_role` ∈ {PLAYER_GOAL, NEXT_GOAL} → `observe.hud` non vide.
  Une exigence sans ces champs reste valide (rétro-compatibilité des runs passés) — c'est `check_loop_spec` qui
  exige la complétude de la boucle.
- **`loop_spec.mjs`** : `deriveLoopSpec(prisme) -> {steps[]}` (ordre des rôles ci-dessus, puis ordre des ids) ;
  `checkLoopSpec(spec) -> {ok, problems}` : les 7 rôles présents ≥ 1, chaque PLAYER_ACTION/UNLOCK/META_LOOP a
  `affordance` + `observe`, PLAYER_GOAL/NEXT_GOAL ont `observe.hud`. CLI `node loop_spec.mjs <prisme.json> [--json]`.
- **run_real** : après matérialisation de `prisme.json` (s1), écrire `loop.json` (dérivé) + `res["loop_check"]`
  (reçu de `checkLoopSpec`, **advisory au run 7**, gaté au run 8 — règle de variance : on mesure d'abord).
- Tests (rouges d'abord) : fixture réelle `prisme.json` du run 6 → `checkLoopSpec` FAIL « 0 PLAYER_ACTION avec
  affordance » (c'est la mesure du diagnostic) ; fixture synthétique complète → OK ; dérivation déterministe
  (même entrée → même sortie) ; matérialisation dans tmp run_dir.

### Task 2 — Grey Blocks / WireMap : une action joueur = une capacité d'entrée réelle
**Files:** Modify `scripts/forge/check_decompo.mjs` · Modify `scripts/forge/contracts/s3-decompo.yaml`,
`s5-wiremap.yaml` (texte) · Tests `check_decompo.test.mjs` (ajouts) · `_UPSTREAM_BY_STEP` : + `loop.json` pour
s3, s5, s9 (2 copies, test d'égalité).
- `check_decompo` : une feuille dont `source_ref` pointe une exigence `acteur: PLAYER` avec `affordance` DOIT avoir
  `expected_proof.kind == "bot_action"` et `expected_proof.statement` contenant `main.tscn` (la preuve passe par la
  scène) ; sinon finding `boucle: feuille '<id>' réalise une action joueur sans preuve depuis main.tscn`.
  Mesure sur la featuremap du run 6 : 0 finding (aucune exigence PLAYER n'existe) — le test documente ce vide.
- Contrat s5 : une ligne par affordance (`category: system.adapter`, `provides: ["affordance:<nom>"]`,
  fichiers = l'adaptateur d'entrée) ; contrat s3 : « une action joueur se décompose en capacité d'ENTRÉE + capacité
  d'EFFET, jamais l'effet seul ».

### Task 3 — Runtime : le contrat s9 exige les affordances, pas le code (le builder sera re-joué)
**Files:** Modify `scripts/forge/contracts/s9-build-godot-standard.yaml` · Modify `tasks.json` (s9) · Test
`test_s9_contract_loop_rule.py`.
- Ajouts : « Chaque `affordance` de `loop.json` est un nœud `Control` cliquable, groupe `affordance`, `name` =
  l'affordance, relié par `input.gd` (ou signal Godot) à la règle `05_SYSTEMS` correspondante ; chaque `observe.hud`
  est un `Label` groupe `hud` nommé ; `03_WORLD/loop.json` déposé ; `solvability.gd` et les volets n'appellent
  JAMAIS `Economy`/`api_*`/`05_SYSTEMS` directement — ils passent par `main.tscn` et des `InputEvent`. »
- **Aucune modification manuelle de `games/kitten_clicker/`** : la connexion `input.gd` ↔ achat/upgrade/prestige est
  l'affaire du run 7 sous ce contrat (Pierre : ne pas corriger le Builder avant le contrat).

### Task 4 — Guidage : objectif visible, prochaine étape visible
Couvert par les données : `PLAYER_GOAL` et `NEXT_GOAL` = `observe.hud: "objectif"` (`nonempty` au boot, `changes`
après le 1er objectif atteint). Contrat s9 : « au boot, le label `objectif` dit quoi faire en une phrase ; après
chaque objectif atteint, il change ». Pas de station : c'est une exigence PLAYER_GOAL du Prisme + un Label.

### Task 5 — Test de régression : le bot-joueur (`godot_probes/player_loop.gd`) + garde anti-contournement
**Files:** Create `scripts/forge/godot_probes/player_loop.gd` · Modify `scripts/forge/product_oracle_godot.py`
(`run_player_loop(game_dir)`, même forme que `run_runtime_alive` ; garde statique étendue : tokens interdits
`api_buy_|api_prestige|Economy\.|preload\("res://05_SYSTEMS` dans `07_TESTS/oracle/*.gd` ET `solvability.gd` →
FAIL statique « boucle validée par un canal que le joueur n'a pas ») · Modify `driver.py` (`loop_dead` aux 3 points
d'agrégation, même patron que `runtime_dead` ; SKIPPED sans `03_WORLD/loop.json`) · Tests
`test_player_loop_probe.py`, `test_loop_bypass_guard.py`, `test_driver_loop_gate.py`.
- Sonde (générique, hors projet, fenêtre GPU) : charge `run/main_scene` ; lit `res://03_WORLD/loop.json` ; pour chaque
  step : `observed_before` = texte du `Label` groupe `hud` nommé ; si `affordance` : trouve le nœud groupe
  `affordance` nommé (Control → `get_global_rect().get_center()`), injecte `repeat` × (press+release) ; attend
  `wait_frames` (défaut 30) ; `observed_after` ; évalue `predicate` ; un step `pass=false` arrête la boucle (le
  joueur est bloqué là — c'est l'information). Émet `FORGE_ORACLE player_loop {ok, fails, data:{steps:[{role, ref,
  affordance, before, after, pass}], reached_role}}`. `ok` ssi tous les steps passent jusqu'à META_LOOP.
- Baseline RÉELLE : sur le build du run 6 avec un `loop.json` dérivé du Prisme du run 6 → `checkLoopSpec` FAIL
  (aucune affordance) ; avec un `loop.json` synthétique minimal (pelote ×15 → ronrons increases) → step PA1 pass,
  step PA2 `affordance 'acheter_chaton' introuvable` → `reached_role: PLAYER_ACTION`. C'est le « NON » que V4
  doit éliminer. Garde anti-contournement sur les volets/solvability du run 6 → FAIL statique (mesure du maillon 3).
- Gate : `loop_dead` = `checked and not passed` → `final = "FAIL"` (run 8 ; au run 7, ADVISORY dans le reçu —
  variance d'abord, décision Pierre à la lecture du run 7).

### Task 6 — Clôture, run 7, mesure
- Revalidation orchestrateur (nouveaux tests + `test_driver.py` + `test_static_oracles.py` + node + dry-run +
  `diff --check`) ; UN commit ; archiver run 6 + build (`_run6_20260821f/` + `game_build6/`).
- Run 7 `kitten_clicker-20260821g`, `full_godot_content`, sans `--charter` (≈ 40-60 $, 3 h).
- **V4 PASS CONDITION** : `loop.json` dérivé complet (7 rôles) · `check_decompo` boucle OK · `runtime_alive` OK ·
  **`player_loop` atteint META_LOOP depuis `main.tscn` par les seuls `InputEvent`** · volets/solvability sans
  contournement · capture · **playtest Pierre** : « je comprends quoi faire, j'achète, ça change, je débloque ».
- Hors V4 (PASSIVE / DOCUMENTED_ONLY) : vocabulaire STANDARD/Prisme, reuse_ratio, red-team Qwen, V3.1.

## Self-review
- Cadrage Pierre 1-5 → Tasks 1-5 ; « ne pas toucher au Builder d'abord » → Task 3 est un contrat, le code du jeu
  n'est pas modifié à la main ; « aucun appel direct à Economy/Runtime/api_* » → garde statique + sonde par
  `InputEvent` seulement ; « bot part comme un joueur » → `player_loop.gd` lit l'écran (Labels) et clique des
  affordances nommées, rien d'autre.
- Pièces réutilisées : `runtime_alive` (patron de sonde, gate, injection), `_materialize_yaml` (patron de
  matérialisation), `check_decompo` (règle de provenance), `_VOLET_REAL_SCENE` (patron de garde).
- Ce que ce plan ne prouve pas : que la boucle est *bonne* — il prouve qu'elle est *traversable par un joueur*.

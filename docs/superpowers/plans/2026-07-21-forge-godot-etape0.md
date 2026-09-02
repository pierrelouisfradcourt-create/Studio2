# Forge Godot Étape 0 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prouver la chaîne complète `brick → implémentation Godot → simulation headless → oracle → verdict signé → certification` sur une seule mécanique (M01 navigation en grille), sans créer de dépendance irréversible au moteur.

**Architecture:** Le contrat `role` reste moteur-agnostique et constitue la frontière stable. Godot n'apparaît que dans l'implémentation (`brick.runtime: "godot"`) et dans un module de scénario adaptateur qui expose la même signature `runTrial(seed, cfg)` que les scénarios JS existants — `role_sim.mjs` n'est jamais modifié. Les gardes de validation (`kb-validate.mjs`) et le méta-oracle (`mutation.py`) sont étendus au GDScript sans desserrer aucune règle existante.

**Tech Stack:** Godot 4.6.3 (headless), Node 20+ (ESM `.mjs`, `node --test`), Python 3.12 (`.venv312`, pytest), JSON/YAML de contrat.

**Spec source:** [docs/superpowers/specs/2026-07-21-forge-godot-etape0-design.md](../specs/2026-07-21-forge-godot-etape0-design.md)

## Global Constraints

- **Aucun `git commit` ni `git push` sans go explicite de Pierre** (règle absolue CLAUDE.md). Chaque tâche se termine par `git add` + affichage du diff, puis **STOP** en attente du go. Un sous-agent ne commite jamais.
- **Périmètre FORGE — Tâche 8 exceptée :** les tâches 1-7 et 9-11 sont de l'**outillage studio** (délégation libre autorisée). La **Tâche 8** produit du code de jeu → périmètre Forge → **aucun sous-agent sans contrat validé** (porte `forge.dispatch.prepare_dispatch` + hook `pretool_forge_guard`). Gate Pierre avant de la lancer.
- **Chemins repo-relatifs uniquement**, jamais de chemin absolu utilisateur (`C:\Users\...`) dans un fichier versionné.
- **`encoding='utf-8'` explicite** sur tout `open()` Python.
- **Aucune règle de validation existante ne doit être desserrée.** Baselines à maintenir vertes : `kb-validate.test.mjs` = **65/65**, `role_sim.test.mjs` = **6/6**.
- **Vocabulaire de verdict unique :** `OK` / `FAIL` / `BLOCKED`. Jamais `PASS/CONCERNS/FAIL`.
- **`claim_verdict: NO_CLAIM_ALLOWED`** dans tout rapport de fin de tâche.
- **Zone protégée :** ne jamais modifier `tests/studioV2/`. **Lane STUDIO gelée :** ne jamais toucher `autopilot.py`, `scripts/studioV2/`, `start_studio.ps1`, `stop_studio.ps1`.
- **Déterminisme obligatoire** dans tout scénario de simulation : pas de `Math.random`, `Date.now`, `randi()`, `Time.get_*`. Seeds explicites.

---

## Structure de fichiers

| Fichier | Responsabilité | Statut |
|---|---|---|
| `scripts/forge/godot_bin.mjs` | Résout le binaire Godot (config repo-relative + override env). Une seule responsabilité : *où est Godot*. | Créer |
| `scripts/forge/godot.config.json` | Configuration locale du chemin Godot (gitignorée). | Créer |
| `scripts/forge/godot.config.example.json` | Exemple versionné. | Créer |
| `knowledge_base/systems/adapters/godot_trial.mjs` | Adaptateur générique : expose `runTrial(seed, cfg)`, spawn Godot headless, parse un reçu JSON. Ne connaît aucune mécanique. | Créer |
| `knowledge_base/systems/adapters/godot_trial.test.mjs` | Tests de l'adaptateur (fixture Godot déterministe). | Créer |
| `fixtures/godot_trial_probe/` | Mini-projet Godot déterministe servant de fixture de test à l'adaptateur. | Créer |
| `knowledge_base/kb-validate.mjs` | Validateur catalogue. Amendements R6 (code Godot testable) + R10 (impuretés GDScript) + `learned_from`. | Modifier |
| `scripts/forge/mutation.py` | Moteur de mutation. Ajout des règles GDScript. | Modifier |
| `scripts/forge/solvability_godot.mjs` | Oracle R9 pour un projet Godot : un bot déterministe gagne. | Créer |
| `games/grid_nav_probe/` | Artefact Godot consommateur de la brique M01 (preuve d'usage, pas un jeu). | Créer |
| `knowledge_base/systems/navigation/grid_nav.gd` | La brique M01 elle-même. | Créer |
| `knowledge_base/roles/grid-navigator.yaml` | Contrat de rôle moteur-agnostique. | Créer |
| `scripts/forge/oracles.json` | Registre des oracles : entrée `grid_nav_probe`. | Modifier |
| `scripts/forge/learning_metrics.mjs` | Journal des 3 métriques d'apprentissage. | Créer |
| `external_sources/` | Protocole de capital externe (studied / imported_code / extracted_knowledge). | Créer |

---

## Task 1: Résolution du binaire Godot

Aucune convention n'existe dans le repo : `games/chess_tcg/README.md` documente un placeholder littéral `"<Godot>/Godot_v4.6.3-stable_win64_console.exe"`. Le binaire réel vit hors repo, sur le Desktop de l'utilisateur. Il faut donc un résolveur, sinon chaque script suivant embarquera un chemin absolu — interdit.

**Files:**
- Create: `scripts/forge/godot_bin.mjs`
- Create: `scripts/forge/godot_bin.test.mjs`
- Create: `scripts/forge/godot.config.example.json`
- Modify: `.gitignore`

**Interfaces:**
- Produces: `resolveGodotBin(opts?: {env?: object, configPath?: string}) => string` — retourne un chemin absolu vers l'exécutable Godot console. Jette `Error` avec message actionnable si introuvable.
- Ordre de résolution : `env.GODOT_BIN` → `scripts/forge/godot.config.json` champ `godot_bin` → erreur explicite.

- [ ] **Step 1: Write the failing test**

Create `scripts/forge/godot_bin.test.mjs`:

```javascript
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { writeFileSync, mkdtempSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { resolveGodotBin } from './godot_bin.mjs';

test('GODOT_BIN dans l env a la priorite', () => {
  const dir = mkdtempSync(join(tmpdir(), 'gb-'));
  const fake = join(dir, 'godot.exe');
  writeFileSync(fake, 'x');
  const got = resolveGodotBin({ env: { GODOT_BIN: fake }, configPath: join(dir, 'absent.json') });
  assert.equal(got, fake);
});

test('fallback sur le fichier de config', () => {
  const dir = mkdtempSync(join(tmpdir(), 'gb-'));
  const fake = join(dir, 'godot.exe');
  writeFileSync(fake, 'x');
  const cfg = join(dir, 'godot.config.json');
  writeFileSync(cfg, JSON.stringify({ godot_bin: fake }), 'utf-8');
  const got = resolveGodotBin({ env: {}, configPath: cfg });
  assert.equal(got, fake);
});

test('binaire declare mais absent du disque -> erreur actionnable', () => {
  const dir = mkdtempSync(join(tmpdir(), 'gb-'));
  const cfg = join(dir, 'godot.config.json');
  writeFileSync(cfg, JSON.stringify({ godot_bin: join(dir, 'nope.exe') }), 'utf-8');
  assert.throws(
    () => resolveGodotBin({ env: {}, configPath: cfg }),
    /introuvable sur le disque/
  );
});

test('aucune source de configuration -> erreur qui explique quoi faire', () => {
  const dir = mkdtempSync(join(tmpdir(), 'gb-'));
  assert.throws(
    () => resolveGodotBin({ env: {}, configPath: join(dir, 'absent.json') }),
    /GODOT_BIN|godot\.config\.json/
  );
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `node --test scripts/forge/godot_bin.test.mjs`
Expected: FAIL — `Cannot find module './godot_bin.mjs'`

- [ ] **Step 3: Write minimal implementation**

Create `scripts/forge/godot_bin.mjs`:

```javascript
// godot_bin.mjs — resolution du binaire Godot. Une seule responsabilite : OU est Godot.
// Le binaire vit hors repo (installation utilisateur) : aucun chemin absolu n'est
// versionne. Ordre : env GODOT_BIN -> scripts/forge/godot.config.json -> erreur.
import { existsSync, readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const DEFAULT_CONFIG = resolve(HERE, 'godot.config.json');

const HOWTO =
  'Configure Godot : soit la variable d environnement GODOT_BIN, soit le champ ' +
  '"godot_bin" dans scripts/forge/godot.config.json (cf. godot.config.example.json). ' +
  'Utiliser l executable CONSOLE (…_console.exe) pour capturer stdout.';

/**
 * @param {{env?: object, configPath?: string}} [opts]
 * @returns {string} chemin absolu vers l executable Godot
 */
export function resolveGodotBin(opts = {}) {
  const env = opts.env ?? process.env;
  const configPath = opts.configPath ?? DEFAULT_CONFIG;

  let candidate = null;
  let origin = null;

  if (env.GODOT_BIN) {
    candidate = env.GODOT_BIN;
    origin = 'GODOT_BIN';
  } else if (existsSync(configPath)) {
    let parsed;
    try {
      parsed = JSON.parse(readFileSync(configPath, 'utf-8'));
    } catch (e) {
      throw new Error(`godot.config.json illisible (${configPath}) : ${e.message}`);
    }
    if (parsed && typeof parsed.godot_bin === 'string' && parsed.godot_bin.length > 0) {
      candidate = parsed.godot_bin;
      origin = configPath;
    }
  }

  if (!candidate) throw new Error(`Binaire Godot non configure. ${HOWTO}`);
  if (!existsSync(candidate)) {
    throw new Error(`Binaire Godot introuvable sur le disque : ${candidate} (declare par ${origin}). ${HOWTO}`);
  }
  return candidate;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `node --test scripts/forge/godot_bin.test.mjs`
Expected: PASS — `pass 4  fail 0`

- [ ] **Step 5: Créer l'exemple de config et ignorer la config locale**

Create `scripts/forge/godot.config.example.json`:

```json
{
  "_comment": "Copier en godot.config.json et adapter. Utiliser l executable CONSOLE pour capturer stdout.",
  "godot_bin": "C:/chemin/vers/Godot_v4.6.3-stable_win64_console.exe"
}
```

Ajouter à la fin de `.gitignore` :

```
# Chemin local du binaire Godot (machine-dependant, jamais versionne)
scripts/forge/godot.config.json
```

- [ ] **Step 6: Créer la config locale réelle et vérifier**

Créer `scripts/forge/godot.config.json` (non versionné) pointant vers l'exécutable **console** réellement installé sur le poste.

Run: `node -e "import('./scripts/forge/godot_bin.mjs').then(m=>console.log(m.resolveGodotBin()))"`
Expected: le chemin absolu s'affiche, aucune exception.

Run: `git status --short scripts/forge/godot.config.json`
Expected: **aucune sortie** (le fichier est bien ignoré).

- [ ] **Step 7: Préparer le commit (NE PAS COMMITER)**

```bash
git add scripts/forge/godot_bin.mjs scripts/forge/godot_bin.test.mjs scripts/forge/godot.config.example.json .gitignore
git diff --cached --stat
```

STOP — attendre le go de Pierre.

---

## Task 2: Fixture Godot déterministe

L'adaptateur de la Tâche 3 a besoin d'une cible testable. Cette fixture est un mini-projet Godot qui ne fait qu'une chose : lire un seed, produire un reçu JSON déterministe sur stdout. Elle sert de contrôle — si l'adaptateur échoue, on saura si c'est lui ou le projet mesuré.

**Files:**
- Create: `fixtures/godot_trial_probe/project.godot`
- Create: `fixtures/godot_trial_probe/trial.gd`

**Interfaces:**
- Produces: un projet Godot invocable par
  `<godot> --headless --path fixtures/godot_trial_probe --script res://trial.gd -- --seed=<N> --max_ticks=<M>`
  qui écrit sur stdout une ligne unique préfixée `FORGE_TRIAL ` suivie d'un JSON `{"succeeded": bool, "ticks": number|null}` et sort avec le code 0.
- Comportement déterministe défini : `succeeded = (seed % 10) != 0`, `ticks = (seed % 7) + 3` si succès sinon `null`. Aucune source d'aléa.

- [ ] **Step 1: Créer le projet Godot minimal**

Create `fixtures/godot_trial_probe/project.godot`:

```ini
; Fixture deterministe pour godot_trial.mjs — AUCUNE logique de jeu.
config_version=5

[application]

config/name="forge_trial_probe"
config/features=PackedStringArray("4.6")
```

- [ ] **Step 2: Écrire le script de trial**

Create `fixtures/godot_trial_probe/trial.gd`:

```gdscript
# Fixture DETERMINISTE — controle de l adaptateur godot_trial.mjs.
# Ne modelise aucune mecanique : mappe seed -> resultat par une formule fixe,
# pour que l adaptateur puisse etre teste independamment de tout jeu reel.
extends SceneTree

const PREFIX := "FORGE_TRIAL "

func _initialize() -> void:
	var args := _parse_args()
	if not args.has("seed"):
		printerr("argument --seed=<N> manquant")
		quit(2)
		return
	var seed_value: int = int(args["seed"])
	var succeeded: bool = (seed_value % 10) != 0
	var ticks = (seed_value % 7) + 3 if succeeded else null
	print(PREFIX + JSON.stringify({"succeeded": succeeded, "ticks": ticks}))
	quit(0)

func _parse_args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			var parts := a.substr(2).split("=", true, 1)
			out[parts[0]] = parts[1]
	return out
```

- [ ] **Step 3: Vérifier la fixture à la main**

Run (remplacer `<godot>` par la valeur retournée en Tâche 1 step 6) :

```bash
"<godot>" --headless --path fixtures/godot_trial_probe --script res://trial.gd -- --seed=13
```

Expected: la sortie contient la ligne `FORGE_TRIAL {"succeeded":true,"ticks":9}` et exit code 0.

Run: `"<godot>" --headless --path fixtures/godot_trial_probe --script res://trial.gd -- --seed=20`
Expected: `FORGE_TRIAL {"succeeded":false,"ticks":null}`

- [ ] **Step 4: Vérifier le déterminisme**

Lancer trois fois `--seed=13` et confirmer une sortie strictement identique à chaque fois.

- [ ] **Step 5: Préparer le commit (NE PAS COMMITER)**

```bash
git add fixtures/godot_trial_probe/
git diff --cached --stat
```

STOP — attendre le go de Pierre.

---

## Task 3: Adaptateur `godot_trial.mjs`

`role_sim.mjs` (l. 199-212) fait `await import(moduleUrl)` et exige un export `runTrial(seed, cfg)`. C'est un `import()` ESM natif : il ne charge que du `.mjs`. Une brique Godot ne peut pas fournir ce `runTrial` directement. L'adaptateur comble exactement cet écart — **`role_sim.mjs` n'est pas modifié**.

**Files:**
- Create: `knowledge_base/systems/adapters/godot_trial.mjs`
- Create: `knowledge_base/systems/adapters/godot_trial.test.mjs`

**Interfaces:**
- Consumes: `resolveGodotBin()` de la Tâche 1 ; la fixture de la Tâche 2.
- Produces: `makeGodotRunTrial(spawnFn?) => (seed, cfg) => {succeeded: boolean, ticks: number|null}` et l'export `runTrial(seed, cfg)` attendu par `role_sim.mjs`.
- `cfg` doit contenir : `godot_project` (chemin repo-relatif), `godot_script` (`res://…`), `trial_timeout_ms` (nombre). Tout champ manquant → `Error` explicite.

- [ ] **Step 1: Write the failing test**

Create `knowledge_base/systems/adapters/godot_trial.test.mjs`:

```javascript
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { makeGodotRunTrial, parseReceipt } from './godot_trial.mjs';

const CFG = { godot_project: 'fixtures/godot_trial_probe', godot_script: 'res://trial.gd', trial_timeout_ms: 30000 };

test('parseReceipt extrait la ligne prefixee au milieu du bruit', () => {
  const out = 'Godot Engine v4.6.3\nblabla\nFORGE_TRIAL {"succeeded":true,"ticks":9}\nautre bruit\n';
  assert.deepEqual(parseReceipt(out), { succeeded: true, ticks: 9 });
});

test('parseReceipt rejette une sortie sans recu', () => {
  assert.throws(() => parseReceipt('rien ici'), /aucun recu FORGE_TRIAL/);
});

test('parseReceipt rejette un recu mal forme', () => {
  assert.throws(() => parseReceipt('FORGE_TRIAL {pas du json}'), /recu FORGE_TRIAL illisible/);
});

test('parseReceipt rejette un recu au mauvais type', () => {
  assert.throws(() => parseReceipt('FORGE_TRIAL {"succeeded":"oui","ticks":9}'), /champ succeeded/);
});

test('runTrial passe le seed a Godot et rend le recu', () => {
  const calls = [];
  const spawnFn = (bin, args) => {
    calls.push({ bin, args });
    return { status: 0, stdout: 'FORGE_TRIAL {"succeeded":true,"ticks":5}', stderr: '' };
  };
  const runTrial = makeGodotRunTrial(spawnFn, () => 'FAKE_GODOT');
  const res = runTrial(42, CFG);
  assert.deepEqual(res, { succeeded: true, ticks: 5 });
  assert.equal(calls[0].bin, 'FAKE_GODOT');
  assert.ok(calls[0].args.includes('--headless'));
  assert.ok(calls[0].args.includes('--seed=42'));
});

test('exit code non nul -> erreur incluant stderr', () => {
  const spawnFn = () => ({ status: 1, stdout: '', stderr: 'SCRIPT ERROR: boom' });
  const runTrial = makeGodotRunTrial(spawnFn, () => 'FAKE_GODOT');
  assert.throws(() => runTrial(1, CFG), /exit 1.*boom/s);
});

test('cfg incomplet -> erreur explicite avant tout spawn', () => {
  let spawned = false;
  const spawnFn = () => { spawned = true; return { status: 0, stdout: '', stderr: '' }; };
  const runTrial = makeGodotRunTrial(spawnFn, () => 'FAKE_GODOT');
  assert.throws(() => runTrial(1, { godot_project: 'x' }), /godot_script/);
  assert.equal(spawned, false);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `node --test knowledge_base/systems/adapters/godot_trial.test.mjs`
Expected: FAIL — module introuvable.

- [ ] **Step 3: Write minimal implementation**

Create `knowledge_base/systems/adapters/godot_trial.mjs`:

```javascript
// godot_trial.mjs — ADAPTATEUR : expose la signature runTrial(seed, cfg) attendue par
// role_sim.mjs, en deleguant l execution a Godot headless. role_sim.mjs n est PAS
// modifie : le couplage au moteur vit ici, dans un module de scenario, exactement la
// ou le schema de contrat le prevoit deja (champ simulation_module).
//
// Contrat de sortie du projet Godot : une ligne stdout `FORGE_TRIAL <json>` avec
// {"succeeded": bool, "ticks": number|null}. Exit 0 exige.
import { spawnSync } from 'node:child_process';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { resolveGodotBin } from '../../../scripts/forge/godot_bin.mjs';

const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..', '..');
const PREFIX = 'FORGE_TRIAL ';
const REQUIRED_CFG = ['godot_project', 'godot_script', 'trial_timeout_ms'];

/**
 * Extrait le recu JSON d une sortie Godot bruitee (banniere moteur, warnings…).
 * @param {string} stdout
 * @returns {{succeeded: boolean, ticks: (number|null)}}
 */
export function parseReceipt(stdout) {
  const line = String(stdout).split(/\r?\n/).find((l) => l.startsWith(PREFIX));
  if (!line) throw new Error(`aucun recu FORGE_TRIAL dans la sortie Godot`);
  let parsed;
  try {
    parsed = JSON.parse(line.slice(PREFIX.length));
  } catch (e) {
    throw new Error(`recu FORGE_TRIAL illisible : ${e.message}`);
  }
  if (typeof parsed.succeeded !== 'boolean') throw new Error('champ succeeded absent ou non booleen');
  if (parsed.ticks !== null && typeof parsed.ticks !== 'number') throw new Error('champ ticks doit etre number ou null');
  return { succeeded: parsed.succeeded, ticks: parsed.ticks };
}

/**
 * Fabrique un runTrial. Les dependances sont injectables pour rendre l adaptateur
 * testable sans lancer Godot (tests unitaires) tout en restant reel en production.
 * @param {Function} [spawnFn] signature (bin, args, opts) -> {status, stdout, stderr}
 * @param {Function} [binResolver]
 */
export function makeGodotRunTrial(spawnFn, binResolver) {
  const doSpawn = spawnFn ?? ((bin, args, opts) => spawnSync(bin, args, opts));
  const getBin = binResolver ?? resolveGodotBin;

  return function runTrial(seed, cfg) {
    for (const k of REQUIRED_CFG) {
      if (cfg == null || cfg[k] === undefined) {
        throw new Error(`simulation_config incomplet : champ '${k}' requis par godot_trial`);
      }
    }
    const bin = getBin();
    const args = [
      '--headless',
      '--path', resolve(REPO_ROOT, cfg.godot_project),
      '--script', cfg.godot_script,
      '--',
      `--seed=${seed}`,
      `--max_ticks=${cfg.max_ticks ?? 0}`,
    ];
    const res = doSpawn(bin, args, {
      encoding: 'utf-8',
      timeout: cfg.trial_timeout_ms,
      windowsHide: true,
    });
    if (res.error) throw new Error(`spawn Godot impossible : ${res.error.message}`);
    if (res.status !== 0) {
      throw new Error(`Godot exit ${res.status} (seed=${seed})\nstderr: ${res.stderr}\nstdout: ${res.stdout}`);
    }
    return parseReceipt(res.stdout);
  };
}

export const runTrial = makeGodotRunTrial();
```

- [ ] **Step 4: Run test to verify it passes**

Run: `node --test knowledge_base/systems/adapters/godot_trial.test.mjs`
Expected: PASS — `pass 7  fail 0`

- [ ] **Step 5: Test d'intégration réel contre la fixture**

Run:

```bash
node -e "import('./knowledge_base/systems/adapters/godot_trial.mjs').then(m=>{const cfg={godot_project:'fixtures/godot_trial_probe',godot_script:'res://trial.gd',trial_timeout_ms:30000};console.log(JSON.stringify(m.runTrial(13,cfg)));console.log(JSON.stringify(m.runTrial(20,cfg)));})"
```

Expected exactement :

```
{"succeeded":true,"ticks":9}
{"succeeded":false,"ticks":null}
```

C'est la première preuve d'exécution réelle Node → Godot headless. Si cette étape échoue, ne pas continuer : diagnostiquer avant.

- [ ] **Step 6: Préparer le commit (NE PAS COMMITER)**

```bash
git add knowledge_base/systems/adapters/
git diff --cached --stat
```

STOP — attendre le go de Pierre.

---

## Task 4: `mutation.py` — règles GDScript

**Trou identifié hors spec, comblé ici.** `scripts/forge/mutation.py` définit `RULES` avec des opérateurs JS (`===`, `!==`, `&&`, `||`). GDScript utilise `==`, `!=`, `and`, `or`. Sans cette tâche, seuls `>=`, `<=`, `+=`, `-=`, `true`/`false` muteraient sur un `.gd` : le gate mutation serait quasi édenté, alors que le critère de succès n°3 du spec en dépend.

**Files:**
- Modify: `scripts/forge/mutation.py`
- Modify: `scripts/forge/tests/test_mutation.py`

**Interfaces:**
- Consumes: `generate_mutants(text)` existant.
- Produces: comportement étendu de `generate_mutants` — les mots-clés GDScript `and`/`or` et les opérateurs `==`/`!=` génèrent des mutants, **sans casser** les règles JS existantes (`===`/`!==` restent prioritaires et ne doivent pas être fragmentés en `==`).

- [ ] **Step 1: Write the failing test**

Ajouter à `scripts/forge/tests/test_mutation.py` :

```python
def test_gdscript_and_or_mutes():
    """GDScript utilise and/or, pas &&/||. Sans ces regles, le gate mutation
    est edente sur .gd (cf. plan etape 0, tache 4)."""
    from forge.mutation import generate_mutants
    names = {m.name for m in generate_mutants("if a and b:\n")}
    assert "and->or" in names
    names = {m.name for m in generate_mutants("if a or b:\n")}
    assert "or->and" in names


def test_gdscript_equality_mutes():
    from forge.mutation import generate_mutants
    names = {m.name for m in generate_mutants("if hp == 0:\n")}
    assert "eqeq->neq" in names
    names = {m.name for m in generate_mutants("if hp != 0:\n")}
    assert "neq->eqeq" in names


def test_js_strict_equality_not_fragmented():
    """GARDE ANTI-REGRESSION : `===` ne doit jamais produire un mutant `==`->`!=`
    qui casserait la syntaxe JS. Les regles JS existantes restent prioritaires."""
    from forge.mutation import generate_mutants
    mutants = generate_mutants("if (a === b) {}\n")
    names = {m.name for m in mutants}
    assert "eq->neq" in names
    assert "eqeq->neq" not in names
    for m in mutants:
        assert "=!=" not in m.mutant_text
        assert "!===" not in m.mutant_text


def test_and_or_only_as_whole_words():
    """`and`/`or` ne doivent pas muter a l interieur d un identifiant
    (`operand`, `random`, `for`, `word`) — sinon avalanche de faux mutants."""
    from forge.mutation import generate_mutants
    for src in ["var operand = 1\n", "var random_x = 2\n", "var sword = 3\n"]:
        names = {m.name for m in generate_mutants(src)}
        assert "and->or" not in names
        assert "or->and" not in names
```

- [ ] **Step 2: Run test to verify it fails**

Run: `.venv312/Scripts/python.exe -m pytest scripts/forge/tests/test_mutation.py -q -k "gdscript or fragmented or whole_words"`
Expected: FAIL — `assert 'and->or' in names`

- [ ] **Step 3: Write minimal implementation**

Dans `scripts/forge/mutation.py`, remplacer le bloc `_WORD_RULES` par :

```python
# Règles à frontière de mot. Regroupe les booléens (tous langages) et les opérateurs
# logiques GDScript/Python (`and`/`or`), qui n'ont pas d'équivalent dans RULES —
# RULES ne couvre que `&&`/`||` (JS/Rust). Sans ces entrées, muter un `.gd` ne
# produisait presque aucun mutant : gate mutation édenté (plan étape 0, tâche 4).
# Frontière \b obligatoire : sinon `operand`, `random`, `sword` génèrent des mutants
# syntaxiquement absurdes en masse.
_WORD_RULES = (
    (r"\btrue\b", "false", "true->false"),
    (r"\bfalse\b", "true", "false->true"),
    (r"\band\b", "or", "and->or"),
    (r"\bor\b", "and", "or->and"),
)

# Égalité non stricte (GDScript/Python). Ces règles sont appliquées APRÈS celles de
# RULES et jamais à l'intérieur d'un `===`/`!==` : muter le `==` d'un `===` JS
# produirait `=!=`, une faute de syntaxe (mutant inkillable et trompeur).
_EQ_RULES = (
    (re.compile(r"(?<![=!<>])==(?!=)"), "!=", "eqeq->neq"),
    (re.compile(r"(?<![=!<>])!=(?!=)"), "==", "neq->eqeq"),
)
```

Puis, dans `generate_mutants`, après la boucle qui applique `_WORD_RULES`, ajouter la boucle des règles d'égalité, en suivant la même structure que le code existant (une occurrence mutée à la fois, numéro de ligne conservé, lignes de commentaire pur et lignes portant `SKIP_MARKER` ignorées comme actuellement).

**Note d'implémentation :** lire le corps existant de `generate_mutants` avant d'éditer et calquer exactement sa forme (parcours ligne à ligne, construction du texte muté, champ `Mutant(name, line, mutant_text)`). Ne pas réécrire la fonction.

- [ ] **Step 4: Run test to verify it passes**

Run: `.venv312/Scripts/python.exe -m pytest scripts/forge/tests/test_mutation.py -q`
Expected: PASS, tous les tests existants inclus.

- [ ] **Step 5: Vérifier l'absence de régression sur toute la Forge**

Run: `.venv312/Scripts/python.exe -m pytest scripts/forge/tests/ -q`
Expected: aucun échec. Noter le total de tests dans le rapport de tâche.

- [ ] **Step 6: Préparer le commit (NE PAS COMMITER)**

```bash
git add scripts/forge/mutation.py scripts/forge/tests/test_mutation.py
git diff --cached --stat
```

STOP — attendre le go de Pierre.

---

## Task 5: `kb-validate.mjs` — R6 ouvre le code Godot testable

**Constat vérifié** (`kb-validate.mjs:372`) : `runtime === "godot"` force `path` **et** `tests` à `null`. En l'état, une brique Godot ne peut avoir ni sha256 ni fichier de tests — donc **ne peut pas être certifiée**. La règle « manifest-only » est légitime pour un *asset 3D non ingéré*, pas pour du *code GDScript testable*.

**Files:**
- Modify: `knowledge_base/kb-validate.mjs:371-379`
- Modify: `knowledge_base/kb-validate.test.mjs`

**Interfaces:**
- Produces: une brick `kind: "system"`, `runtime: "godot"` avec `path` pointant un `.gd` sous `knowledge_base/systems/`, `sha256` réel et `tests` non-null est **acceptée**. Une brick `runtime: "godot"` sans `path` reste **rejetée** (R7, alignée sur le traitement non-godot l. 377).

- [ ] **Step 1: Write the failing test**

Ajouter à `knowledge_base/kb-validate.test.mjs` (calquer la forme des tests existants pour construire un catalogue minimal et appeler `validateCatalog`) :

```javascript
test('R6: brick system runtime godot avec path .gd + tests + sha256 -> ACCEPTEE', () => {
  // Utilise un .gd reellement present sous knowledge_base/systems/ et son sha256 reel.
  const cat = makeCatalog([godotSystemBrick()]);
  const { ok, errors } = validateCatalog(cat, { root: REPO_ROOT });
  assert.deepEqual(errors.filter((e) => e.rule === 'R6'), []);
  assert.equal(ok, true);
});

test('R6: brick system runtime godot SANS path -> rejet R7 (pas d esquive de preuve)', () => {
  const b = godotSystemBrick();
  b.path = null; b.sha256 = null; b.tests = null;
  const { ok, errors } = validateCatalog(makeCatalog([b]), { root: REPO_ROOT });
  assert.equal(ok, false);
  assert.ok(errors.some((e) => e.rule === 'R7'));
});

test('R6 INCHANGEE: asset 3D/godot ingere reste rejete (manifest-only)', () => {
  const a = godotAssetEntry();      // runtime: 'godot', ingested: true
  const { ok, errors } = validateCatalog(makeCatalog([a]), { root: REPO_ROOT });
  assert.equal(ok, false);
  assert.ok(errors.some((e) => e.rule === 'R6'));
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `node --test knowledge_base/kb-validate.test.mjs`
Expected: FAIL sur le premier test — une erreur `R6` est présente alors qu'on n'en attend aucune.

- [ ] **Step 3: Write minimal implementation**

Dans `knowledge_base/kb-validate.mjs`, remplacer le bloc l. 371-379 par :

```javascript
  // R6 — « manifest-only » s'applique aux ASSETS godot/3D (modèles non ingérés),
  // PAS au code GDScript, qui doit être prouvable comme n'importe quel autre code.
  // Amendement étape 0 (spec 2026-07-21 §8a) : un system/template Godot suit
  // exactement le même régime de preuve qu'un module non-godot — path + sha256
  // + tests. Aucune garde existante n'est desserrée : le cas asset reste traité
  // par validateAsset (R6, inchangé), et l'exigence de path ci-dessous devient
  // universelle pour le code au lieu d'exempter Godot.
  if (isCode && e.path === null) {
    err(id, "R7", `${e.kind} exige un path (module) — path null esquive purete/tests`);
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `node --test knowledge_base/kb-validate.test.mjs`
Expected: PASS.

- [ ] **Step 5: Vérifier la non-régression sur le catalogue réel**

Run: `node knowledge_base/kb-validate.mjs`
Expected: `VERDICT CATALOGUE: PASS (30 entree(s) conformes, 0 violation)` — le nombre d'entrées doit être **inchangé** par rapport à l'état d'avant modification.

Run: `node --test knowledge_base/kb-validate.test.mjs 2>&1 | tail -8`
Expected: `pass` ≥ **65** (baseline) `fail 0`.

- [ ] **Step 6: Préparer le commit (NE PAS COMMITER)**

```bash
git add knowledge_base/kb-validate.mjs knowledge_base/kb-validate.test.mjs
git diff --cached
```

Lire le diff intégralement : vérifier qu'**aucune** règle existante n'a été assouplie. STOP — attendre le go de Pierre.

---

## Task 6: `kb-validate.mjs` — motifs d'impureté GDScript (R10)

**Constat vérifié** (`kb-validate.mjs:74-92`) : les motifs d'impureté sont du JS pur (`Math.random`, `process.env`, `fetch`, `window`, `require('fs')`). Une brique GDScript non déterministe passerait la garde de pureté **sans être vue** — ce qui invaliderait silencieusement toute mesure de bande de difficulté.

**Files:**
- Modify: `knowledge_base/kb-validate.mjs` (après `IMPURITY_STRIPPED`, l. 92)
- Modify: `knowledge_base/kb-validate.test.mjs`

**Interfaces:**
- Produces: constante exportable `IMPURITY_GDSCRIPT` et application de ces motifs aux seuls fichiers `.gd`, en plus des motifs existants appliqués aux `.mjs`.

- [ ] **Step 1: Write the failing test**

Ajouter à `knowledge_base/kb-validate.test.mjs` :

```javascript
test('R10 GDScript: randi() dans une brique godot -> rejet R10', () => {
  // Ecrit un .gd temporaire sous knowledge_base/systems/ contenant `var x = randi()`,
  // le reference depuis une brick godot avec son sha256 reel.
  const { errors } = validateCatalog(makeCatalog([godotBrickWithSource('var x = randi()\n')]), { root: REPO_ROOT });
  assert.ok(errors.some((e) => e.rule === 'R10' && /randi/.test(e.msg)));
});

test('R10 GDScript: Time.get_ticks_msec() -> rejet R10 (non deterministe)', () => {
  const { errors } = validateCatalog(makeCatalog([godotBrickWithSource('var t = Time.get_ticks_msec()\n')]), { root: REPO_ROOT });
  assert.ok(errors.some((e) => e.rule === 'R10'));
});

test('R10 GDScript: FileAccess.open() -> rejet R10 (I/O)', () => {
  const { errors } = validateCatalog(makeCatalog([godotBrickWithSource('var f = FileAccess.open("x", 1)\n')]), { root: REPO_ROOT });
  assert.ok(errors.some((e) => e.rule === 'R10'));
});

test('R10 GDScript: du .gd pur ne declenche AUCUN R10', () => {
  const src = 'func step(pos: Vector2i, dir: Vector2i) -> Vector2i:\n\treturn pos + dir\n';
  const { errors } = validateCatalog(makeCatalog([godotBrickWithSource(src)]), { root: REPO_ROOT });
  assert.deepEqual(errors.filter((e) => e.rule === 'R10'), []);
});

test('R10 GDScript: le mot randi en COMMENTAIRE ne declenche pas R10 (pas de faux positif)', () => {
  const src = '# ne jamais utiliser randi() ici\nfunc f() -> int:\n\treturn 1\n';
  const { errors } = validateCatalog(makeCatalog([godotBrickWithSource(src)]), { root: REPO_ROOT });
  assert.deepEqual(errors.filter((e) => e.rule === 'R10'), []);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `node --test knowledge_base/kb-validate.test.mjs`
Expected: FAIL — aucune erreur R10 produite sur `randi()`.

- [ ] **Step 3: Write minimal implementation**

Dans `knowledge_base/kb-validate.mjs`, ajouter après `IMPURITY_STRIPPED` :

```javascript
// R10 — motifs d'impureté GDScript. Symétrique d'IMPURITY_STRIPPED (JS), appliqué aux
// seuls fichiers .gd : les motifs JS n'ont aucun équivalent lexical en GDScript, donc
// sans cette liste une brique Godot non déterministe passait la garde sans être vue
// (amendement étape 0, spec 2026-07-21 §8b). Scanné APRÈS retrait des commentaires
// (`#` en GDScript) et des chaînes, comme pour le JS.
const IMPURITY_GDSCRIPT = [
  [/\brand[if]\b/, "randi/randf (aleatoire non seede)"],
  [/\brandi_range\b/, "randi_range"],
  [/\brandf_range\b/, "randf_range"],
  [/\brandomize\b/, "randomize"],
  [/\brand_from_seed\b/, "rand_from_seed"],
  [/\bRandomNumberGenerator\b/, "RandomNumberGenerator"],
  [/\bOS\s*\./, "OS.* (environnement)"],
  [/\bTime\s*\./, "Time.* (non deterministe)"],
  [/\bFileAccess\b/, "FileAccess (I/O)"],
  [/\bDirAccess\b/, "DirAccess (I/O)"],
  [/\bHTTPRequest\b/, "HTTPRequest (reseau)"],
  [/\bHTTPClient\b/, "HTTPClient (reseau)"],
  [/\bEngine\s*\./, "Engine.* (etat moteur)"],
  [/\bInput\s*\./, "Input.* (etat externe)"],
];

// Retire commentaires `#` et littéraux de chaîne d'une source GDScript.
function stripGdscriptCommentsAndStrings(src) {
  return src
    .replace(/"""[\s\S]*?"""/g, '""')
    .replace(/#[^\n]*/g, " ")
    .replace(/"(?:\\.|[^"\\])*"/g, '""')
    .replace(/'(?:\\.|[^'\\])*'/g, "''");
}
```

Puis, dans `validateBrick`, dans le bloc d'inspection de contenu (l. 409-426), aiguiller selon l'extension :

```javascript
  if (isCode && abs !== null) {
    let raw = "";
    try { raw = readFileSync(abs, "utf-8"); } catch { /* déjà couvert */ }
    const isGd = e.path.endsWith(".gd");
    if (isGd) {
      const code = stripGdscriptCommentsAndStrings(raw);
      for (const [re, label] of IMPURITY_GDSCRIPT) {
        if (re.test(code)) err(id, "R10", `motif d'impurete GDScript: ${label}`);
      }
    } else {
      const code = stripCommentsAndStrings(raw);
      for (const [re, label] of IMPURITY_RAW) {
        if (re.test(raw)) err(id, "R10", `motif d'impurete: ${label}`);
      }
      for (const [re, label] of IMPURITY_STRIPPED) {
        if (re.test(code)) err(id, "R10", `motif d'impurete: ${label}`);
      }
    }
    // R11 + marqueur GPL : inchangés, appliqués aux DEUX langages (texte brut).
    for (const re of PATTERN_IMPORT) {
      if (re.test(raw)) { err(id, "R11", "import depuis patterns/ interdit (cites, jamais injectes)"); break; }
    }
    if (/GNU (Lesser |Affero )?General Public License/i.test(raw) || /SPDX-License-Identifier:\s*(?:LGPL|GPL|AGPL)/i.test(raw)) {
      err(id, "R4", "marqueur GPL/LGPL/AGPL dans un module declare permissif — contamination");
    }
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `node --test knowledge_base/kb-validate.test.mjs`
Expected: PASS.

- [ ] **Step 5: Vérifier la non-régression**

Run: `node --test knowledge_base/kb-validate.test.mjs 2>&1 | tail -8`
Expected: `fail 0`, `pass` ≥ 73 (65 baseline + 3 tâche 5 + 5 tâche 6).

Run: `node knowledge_base/kb-validate.mjs`
Expected: `VERDICT CATALOGUE: PASS`, nombre d'entrées inchangé.

- [ ] **Step 6: Préparer le commit (NE PAS COMMITER)**

```bash
git add knowledge_base/kb-validate.mjs knowledge_base/kb-validate.test.mjs
git diff --cached
```

STOP — attendre le go de Pierre.

---

## Task 7: `learned_from` sur `BRICK_SPEC`

Unique extension de schéma de l'étape 0 (spec §9). Enregistre de quel jeu du curriculum et de quelle référence commerciale la mécanique est issue — c'est ce qui distingue une bibliothèque d'une mémoire de studio.

**Files:**
- Modify: `knowledge_base/kb-validate.mjs` (`BRICK_SPEC`, l. 193-215)
- Modify: `knowledge_base/kb-validate.test.mjs`

**Interfaces:**
- Produces: champ **facultatif** `learned_from` sur une brick, de forme `{game: string, reference: string}` exactement (schéma fermé, 2 clés). Facultatif via le helper `optional()` déjà présent l. 133 — les 9 bricks existantes restent valides sans modification.

- [ ] **Step 1: Write the failing test**

```javascript
test('learned_from absent -> brick valide (facultatif, retrocompatible)', () => {
  const b = validBrick();
  delete b.learned_from;
  const { errors } = validateCatalog(makeCatalog([b]), { root: REPO_ROOT });
  assert.deepEqual(errors.filter((e) => /learned_from/.test(e.msg)), []);
});

test('learned_from bien forme -> accepte', () => {
  const b = validBrick();
  b.learned_from = { game: '01_grid_nav_probe', reference: 'Pac-Man (1980)' };
  const { errors } = validateCatalog(makeCatalog([b]), { root: REPO_ROOT });
  assert.deepEqual(errors.filter((e) => /learned_from/.test(e.msg)), []);
});

test('learned_from avec une cle inconnue -> rejet R1 (schema ferme)', () => {
  const b = validBrick();
  b.learned_from = { game: 'x', reference: 'y', extra: 'z' };
  const { ok } = validateCatalog(makeCatalog([b]), { root: REPO_ROOT });
  assert.equal(ok, false);
});

test('learned_from avec un champ manquant -> rejet R1', () => {
  const b = validBrick();
  b.learned_from = { game: 'x' };
  const { ok } = validateCatalog(makeCatalog([b]), { root: REPO_ROOT });
  assert.equal(ok, false);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `node --test knowledge_base/kb-validate.test.mjs`
Expected: FAIL — `champ inconnu (schema ferme): learned_from`

- [ ] **Step 3: Write minimal implementation**

Ajouter le prédicat près des helpers de typage :

```javascript
// Provenance d'apprentissage (spec etape 0 §9) : de quel jeu du curriculum et de
// quelle reference commerciale la mecanique est issue. Schema ferme a 2 cles.
function isLearnedFrom(v) {
  return isPlainObj(v) && isStr(v.game) && isStr(v.reference) && Object.keys(v).length === 2;
}
```

Puis ajouter dans `BRICK_SPEC`, après `usage_examples` :

```javascript
  learned_from: optional(isLearnedFrom),
```

- [ ] **Step 4: Run test to verify it passes**

Run: `node --test knowledge_base/kb-validate.test.mjs`
Expected: PASS.

- [ ] **Step 5: Non-régression catalogue réel**

Run: `node knowledge_base/kb-validate.mjs`
Expected: `VERDICT CATALOGUE: PASS`, entrées inchangées (les 9 bricks existantes n'ont pas `learned_from` et restent valides).

- [ ] **Step 6: Préparer le commit (NE PAS COMMITER)**

```bash
git add knowledge_base/kb-validate.mjs knowledge_base/kb-validate.test.mjs
git diff --cached --stat
```

STOP — attendre le go de Pierre.

---

## Task 7b: `role_sim.mjs` — garde fail-closed sur `simulation_runtime`

Le spec §5 exige que l'ouverture aux futurs runtimes soit **fail-closed** : `unity`/`unreal` sont réservés au schéma, et toute valeur non implémentée doit produire `INVALID_CONTRACT`. Sans cette tâche, le lecteur YAML minimal de `role_sim.mjs` (l. 100-108, extraction par clé nommée) **ignorerait silencieusement** le champ — un point d'extension déclaré et non exécuté, exactement le mode de panne que le spec dénonce.

**Nuance d'architecture :** modifier `role_sim.mjs` est autorisé **ici et seulement ici**, parce que la garde est **générique** — elle ne contient aucune connaissance de Godot. La contrainte du spec est « `role_sim.mjs` ne connaît aucun moteur », pas « le fichier est immuable ».

**Files:**
- Modify: `knowledge_base/role_sim.mjs` (`loadRole`, l. 96-128)
- Modify: `knowledge_base/role_sim.test.mjs`

**Interfaces:**
- Produces: constante `IMPLEMENTED_RUNTIMES = ['node', 'godot']` et `RESERVED_RUNTIMES = ['unity', 'unreal']`. `simulation_runtime` **facultatif** (défaut `node` — les 2 rôles existants n'ont pas ce champ et doivent rester valides). Valeur réservée mais non implémentée → finding explicite → `INVALID_CONTRACT` (exit 2). Valeur totalement inconnue → finding → exit 2.

- [ ] **Step 1: Write the failing test**

Ajouter à `knowledge_base/role_sim.test.mjs` :

```javascript
import { checkSimulationRuntime } from './role_sim.mjs';

test('simulation_runtime absent -> defaut node, aucun finding (retrocompatible)', () => {
  assert.deepEqual(checkSimulationRuntime(null), []);
});

test('simulation_runtime: godot -> implemente, aucun finding', () => {
  assert.deepEqual(checkSimulationRuntime('godot'), []);
});

test('simulation_runtime: node -> implemente, aucun finding', () => {
  assert.deepEqual(checkSimulationRuntime('node'), []);
});

test('simulation_runtime: unity -> RESERVE mais non implemente -> finding explicite', () => {
  const f = checkSimulationRuntime('unity');
  assert.equal(f.length, 1);
  assert.match(f[0], /reconnu par le schema, non implemente/);
});

test('simulation_runtime: unreal -> reserve, meme traitement', () => {
  assert.equal(checkSimulationRuntime('unreal').length, 1);
});

test('simulation_runtime inconnu -> finding, jamais un silence', () => {
  const f = checkSimulationRuntime('bricolage');
  assert.equal(f.length, 1);
  assert.match(f[0], /inconnu/);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `node --test knowledge_base/role_sim.test.mjs`
Expected: FAIL — `checkSimulationRuntime is not a function`

- [ ] **Step 3: Write minimal implementation**

Ajouter dans `knowledge_base/role_sim.mjs`, avant `loadRole` :

```javascript
// Ouverture aux futurs runtimes — FAIL-CLOSED (spec etape 0 §5). Le schema NOMME des
// runtimes futurs pour que les contrats restent ecrits sans eux ; l executeur REFUSE
// tout ce qu il ne sait pas executer. Declarer un point d extension sans le fermer,
// c est reproduire le mode de panne « declare != execute ».
export const IMPLEMENTED_RUNTIMES = ['node', 'godot'];
export const RESERVED_RUNTIMES = ['unity', 'unreal'];

/**
 * @param {string|null} value valeur declaree (null/absent = defaut 'node')
 * @returns {string[]} findings (vide = accepte)
 */
export function checkSimulationRuntime(value) {
  if (value === null || value === undefined || value === '') return [];
  if (IMPLEMENTED_RUNTIMES.includes(value)) return [];
  if (RESERVED_RUNTIMES.includes(value)) {
    return [`simulation_runtime '${value}' : reconnu par le schema, non implemente par l executeur `
      + `(implementes : ${IMPLEMENTED_RUNTIMES.join(', ')})`];
  }
  return [`simulation_runtime '${value}' : inconnu du schema `
    + `(implementes : ${IMPLEMENTED_RUNTIMES.join(', ')} · reserves : ${RESERVED_RUNTIMES.join(', ')})`];
}
```

Puis, dans `loadRole`, après l'extraction des autres scalaires :

```javascript
  const simulationRuntime = extractScalar(text, 'simulation_runtime');
  findings.push(...checkSimulationRuntime(simulationRuntime));
```

et ajouter `simulationRuntime` à l'objet `role` retourné.

- [ ] **Step 4: Run test to verify it passes**

Run: `node --test knowledge_base/role_sim.test.mjs`
Expected: PASS — `pass 12  fail 0` (6 baseline + 6 nouveaux).

- [ ] **Step 5: Vérifier la rétrocompatibilité des rôles existants**

Run: `node knowledge_base/role_sim.mjs knowledge_base/roles/pursuer-mobile.yaml; echo "exit=$?"`
Expected: `exit=0`, `RESULT: PASS` — le rôle n'a pas de `simulation_runtime` et reste valide.

Répéter pour le second rôle existant (`knowledge_base/roles/*.yaml`).

- [ ] **Step 6: Vérifier que la garde ne connaît aucun moteur**

Run: `grep -n -i "godot\|spawn\|child_process\|\.gd" knowledge_base/role_sim.mjs`
Expected: **uniquement** les occurrences de `'godot'` dans `IMPLEMENTED_RUNTIMES` — aucun import, aucun spawn, aucune extension de fichier. Si autre chose apparaît, le couplage a fui dans le mauvais fichier.

- [ ] **Step 7: Préparer le commit (NE PAS COMMITER)**

```bash
git add knowledge_base/role_sim.mjs knowledge_base/role_sim.test.mjs
git diff --cached
```

STOP — attendre le go de Pierre.

---

## Task 8: La brique M01 + son artefact consommateur ⚠️ GATE FORGE

> **⚠️ PÉRIMÈTRE FORGE.** Cette tâche produit du **code de jeu**, pas de l'outillage studio. Invariant ADR-002 : **aucun sous-agent sans contrat validé**. Elle doit passer par la porte `forge.dispatch.prepare_dispatch` (hook `pretool_forge_guard` actif, fail-closed). **Ne pas la déléguer librement.** Gate Pierre explicite avant lancement.

**Files:**
- Create: `knowledge_base/systems/navigation/grid_nav.gd` (la brique)
- Create: `games/grid_nav_probe/project.godot`
- Create: `games/grid_nav_probe/core/grid_nav.gd` (copie de travail chargée par le projet)
- Create: `games/grid_nav_probe/tests/run_tests.gd` (oracle headless, garde anti-faux-vert)
- Create: `games/grid_nav_probe/trial.gd` (point d'entrée `runTrial` pour l'adaptateur)

**Interfaces:**
- Consumes: l'adaptateur de la Tâche 3 (contrat de sortie `FORGE_TRIAL <json>`).
- Produces: `GridNav.next_step(from: Vector2i, to: Vector2i, walls: Dictionary) -> Vector2i` — un pas vers `to` en évitant les murs, déterministe, pur (aucun état global). `GridNav.path_length(from, to, walls) -> int` — longueur du chemin le plus court, `-1` si inatteignable.
- `run_tests.gd` doit suivre exactement le patron de `games/chess_tcg/tests/run_tests.gd` : `extends SceneTree`, `const EXPECTED_ASSERTS := <N>`, exit 0 si tous verts **et** total atteint, sinon exit 1.

- [ ] **Step 1: Lire le patron de référence**

Lire intégralement `games/chess_tcg/tests/run_tests.gd` et `games/chess_tcg/core/moves.gd`. Le nouveau harnais doit en reprendre la structure (garde anti-faux-vert comprise), pas en inventer une autre.

- [ ] **Step 2: Écrire les tests headless AVANT l'implémentation**

Créer `games/grid_nav_probe/tests/run_tests.gd` avec au minimum ces assertions, `EXPECTED_ASSERTS` fixé à leur nombre exact :

- un pas vers une cible adjacente atteint la cible
- un pas vers une cible en ligne droite réduit la distance de 1
- un mur direct force un contournement (le pas n'entre jamais dans un mur)
- cible inatteignable (murée) → `path_length == -1`
- `next_step(p, p, {})` retourne `p` (cas dégénéré, pas de mouvement)
- déterminisme : 100 appels identiques → 100 résultats identiques
- pureté : deux appels avec le même `walls` ne modifient pas `walls`

- [ ] **Step 3: Run test to verify it fails**

Run: `"<godot>" --headless --path games/grid_nav_probe --script res://tests/run_tests.gd`
Expected: exit ≠ 0 (le script `grid_nav.gd` n'existe pas encore / assertions rouges).

- [ ] **Step 4: Implémenter la brique**

Écrire `games/grid_nav_probe/core/grid_nav.gd` : BFS déterministe sur grille 4-directions, ordre d'exploration **fixe** (haut, droite, bas, gauche — jamais dépendant de l'ordre d'itération d'un `Dictionary`), aucun appel à `randi`/`Time`/`OS` (interdits par R10, Tâche 6).

- [ ] **Step 5: Run test to verify it passes**

Run: `"<godot>" --headless --path games/grid_nav_probe --script res://tests/run_tests.gd; echo "exit=$?"`
Expected: `exit=0` et le total d'assertions annoncé égal à `EXPECTED_ASSERTS`.

- [ ] **Step 6: Écrire le point d'entrée de trial**

Créer `games/grid_nav_probe/trial.gd` sur le modèle exact de `fixtures/godot_trial_probe/trial.gd` (Tâche 2) : lit `--seed=`, génère un labyrinthe déterministe à partir du seed (fonction de hash explicite, **pas** `randi`), fait naviguer l'agent, émet `FORGE_TRIAL {"succeeded":…,"ticks":…}`, exit 0.

- [ ] **Step 7: Vérifier le trial réel via l'adaptateur**

Run:

```bash
node -e "import('./knowledge_base/systems/adapters/godot_trial.mjs').then(m=>{const cfg={godot_project:'games/grid_nav_probe',godot_script:'res://trial.gd',trial_timeout_ms:30000,max_ticks:200};for(const s of [1,2,3])console.log(s,JSON.stringify(m.runTrial(s,cfg)));})"
```

Expected: trois reçus valides, et **relancer la commande donne exactement la même sortie** (déterminisme).

- [ ] **Step 8: Gate mutation**

Run:

```bash
PYTHONPATH=scripts .venv312/Scripts/python.exe -m forge.mutation games/grid_nav_probe/core/grid_nav.gd --cwd . -- "<godot>" --headless --path games/grid_nav_probe --script res://tests/run_tests.gd
```

Expected: **100 % de mutants tués**. Tout survivant doit être soit tué par un test supplémentaire, soit justifié dans `games/grid_nav_probe/mutation_triage.json` avec une raison d'équivalence prouvée. Un survivant non justifié = tâche non terminée.

- [ ] **Step 9: Publier la brique dans la KB**

Copier le fichier validé vers `knowledge_base/systems/navigation/grid_nav.gd`, puis ajouter l'entrée au catalogue avec : `kind: "system"`, `runtime: "godot"`, `license: "MIT"`, `source` commençant par `ORIGINAL — aucune inspiration externe citee` **ou** `provenance_url` de la référence étudiée, `tests` pointant le fichier de tests, `sha256` réel, `tier: "candidate"`, `proof_of_use: null`, `affordances` déclarant les capacités exposées, `learned_from: {game: "grid_nav_probe", reference: "Pac-Man (1980)"}`.

Run: `node knowledge_base/kb-validate.mjs`
Expected: `VERDICT CATALOGUE: PASS`, une entrée de plus.

- [ ] **Step 10: Préparer le commit (NE PAS COMMITER)**

```bash
git add knowledge_base/systems/navigation/ games/grid_nav_probe/ knowledge_base/catalog.json
git diff --cached --stat
```

STOP — attendre le go de Pierre.

---

## Task 9: Le contrat de rôle et sa mesure

C'est ici que la **substituabilité certifiée** devient opérationnelle : le rôle ne mentionne aucun moteur, et la bande mesurée via l'adaptateur Godot est comparée à la bande déclarée.

**Files:**
- Create: `knowledge_base/roles/grid-navigator.yaml`
- Create: `knowledge_base/systems/navigation/grid_nav_scenario.mjs`
- Modify: `knowledge_base/catalog.json` (entrée `role`)

**Interfaces:**
- Consumes: `makeGodotRunTrial` (Tâche 3) ; la brique `sys-grid-nav-godot` (Tâche 8).
- Produces: `runTrial(seed, cfg)` réexporté depuis `grid_nav_scenario.mjs`, consommé par `role_sim.mjs` **sans modification de celui-ci**.

- [ ] **Step 1: Écrire le module de scénario**

Create `knowledge_base/systems/navigation/grid_nav_scenario.mjs`:

```javascript
// Scenario du role role-grid-navigator. Delegue a Godot headless via l adaptateur :
// le contrat de role reste moteur-agnostique, le couplage vit ICI (spec etape 0 §4).
// Substituabilite certifiee : un futur backend fournira son propre scenario, mesure
// avec LA MEME simulation_config et LES MEMES seeds. Si la bande retombe dans la
// bande declaree, la substitution est PROUVEE, pas affirmee.
export { runTrial } from '../adapters/godot_trial.mjs';
```

- [ ] **Step 2: Calibrer la bande de difficulté**

**Ne jamais fixer la bande avant de mesurer** (règle du studio : pas de tuning post-hoc, mais pas de bande inventée non plus). Lancer une passe de calibration sur les seeds de production, relever `min` / `médiane` / `max`, et fixer `difficulty_target` **à partir des valeurs observées**, en consignant la mesure brute dans `knowledge_base/proofs/role_sim_grid_navigator_calibration.log`.

- [ ] **Step 3: Écrire le contrat de rôle**

Create `knowledge_base/roles/grid-navigator.yaml`, calqué sur `knowledge_base/roles/pursuer-mobile.yaml` (12 champs, règle des 3 états). Contraintes :

- `archetype` : ≥ 20 caractères, décrit la **capacité**, sans nommer Godot ni aucun moteur.
- `requires` : capacités typées (`next_step`, `path_length`) au format `{type, description}`.
- `fulfilled_by: [sys-grid-nav-godot]` — **liste**, c'est le point d'extension de la substituabilité.
- `simulation_module: knowledge_base/systems/navigation/grid_nav_scenario.mjs`
- `simulation_config` : `trials`, `seed_start`, `max_ticks`, **plus** `godot_project`, `godot_script`, `trial_timeout_ms` requis par l'adaptateur.
- `simulation_runtime: godot` — champ d'ouverture (spec §5). Valeurs implémentées : `node`, `godot`. Toute autre valeur → `INVALID_CONTRACT`.
- `difficulty_target` : la bande mesurée au Step 2.
- `tier: candidate`, `proof_of_use: null` à ce stade.

- [ ] **Step 4: Exécuter role_sim**

Run: `node knowledge_base/role_sim.mjs knowledge_base/roles/grid-navigator.yaml`
Expected: `RESULT: PASS (bande mesuree dans la bande declaree)`, exit 0, avec le reçu JSON mécanique affiché.

Si `INVALID_CONTRACT` : un champ critique manque — corriger le YAML, **pas** `role_sim.mjs`.

- [ ] **Step 5: Vérifier que `role_sim.mjs` ne connaît toujours aucun moteur**

La seule modification autorisée de ce fichier est la garde générique de la Tâche 7b. Aucun couplage Godot ne doit y avoir fui.

Run: `grep -n -i "godot\|spawn\|child_process\|\.gd\|--headless" knowledge_base/role_sim.mjs`
Expected: **uniquement** l'occurrence de `'godot'` dans `IMPLEMENTED_RUNTIMES`. Toute autre correspondance = violation de la contrainte d'architecture centrale du spec — revenir en arrière.

Run: `node --test knowledge_base/role_sim.test.mjs 2>&1 | tail -8`
Expected: `pass 12  fail 0` (6 baseline + 6 de la Tâche 7b, toutes intactes).

- [ ] **Step 6: Cataloguer le rôle**

Ajouter l'entrée `entry_type: "role"` au catalogue avec `requires` (miroir machine-lisible), `fulfilled_by: ["sys-grid-nav-godot"]`, `path`, `tier: "candidate"`, `proof_of_use: null`.

Run: `node knowledge_base/kb-validate.mjs`
Expected: `VERDICT CATALOGUE: PASS`. **R14 est le test réel ici** : `affordances(sys-grid-nav-godot)` doit couvrir toutes les clés de `requires(role-grid-navigator)`, sinon rejet — c'est le pont vérifié, pas déclaré.

- [ ] **Step 7: Sauvegarder la preuve**

Enregistrer la sortie complète de `role_sim` dans `knowledge_base/proofs/role_sim_grid_navigator_validation.log`.

- [ ] **Step 8: Préparer le commit (NE PAS COMMITER)**

```bash
git add knowledge_base/roles/ knowledge_base/systems/navigation/ knowledge_base/proofs/ knowledge_base/catalog.json
git diff --cached --stat
```

STOP — attendre le go de Pierre.

---

## Task 10: Oracle de solvabilité Godot + câblage

Seul vrai code neuf du plan (spec §8 A3). Décline R9 « un bot gagne » pour un projet Godot, et branche le projet sur le registre d'oracles de la Forge.

**Files:**
- Create: `scripts/forge/solvability_godot.mjs`
- Create: `scripts/forge/solvability_godot.test.mjs`
- Create: `games/grid_nav_probe/solvability.gd`
- Modify: `scripts/forge/oracles.json`

**Interfaces:**
- Consumes: `resolveGodotBin()` (Tâche 1) ; le projet `games/grid_nav_probe` (Tâche 8).
- Produces: CLI `node scripts/forge/solvability_godot.mjs <projet> <script> <trials>` → exit 0 si **tous** les essais sont gagnés par le bot, 1 sinon ; reçu JSON `{project, trials, won, lost, failed_seeds, verdict}` sur stdout.
- Le verdict utilise exclusivement `OK` / `FAIL` / `BLOCKED`.

- [ ] **Step 1: Write the failing test**

Create `scripts/forge/solvability_godot.test.mjs` :

```javascript
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { runSolvability } from './solvability_godot.mjs';

test('tous les essais gagnes -> verdict OK', () => {
  const fakeTrial = () => ({ succeeded: true, ticks: 4 });
  const r = runSolvability({ trials: 5, seed_start: 1 }, fakeTrial);
  assert.equal(r.verdict, 'OK');
  assert.equal(r.won, 5);
  assert.deepEqual(r.failed_seeds, []);
});

test('un seul essai perdu -> verdict FAIL et le seed est nomme', () => {
  const fakeTrial = (seed) => ({ succeeded: seed !== 3, ticks: 4 });
  const r = runSolvability({ trials: 5, seed_start: 1 }, fakeTrial);
  assert.equal(r.verdict, 'FAIL');
  assert.deepEqual(r.failed_seeds, [3]);
});

test('une exception de trial -> BLOCKED, jamais un faux vert', () => {
  const fakeTrial = () => { throw new Error('Godot exit 1'); };
  const r = runSolvability({ trials: 3, seed_start: 1 }, fakeTrial);
  assert.equal(r.verdict, 'BLOCKED');
});

test('trials=0 -> BLOCKED (aucune preuve n est pas une preuve)', () => {
  const r = runSolvability({ trials: 0, seed_start: 1 }, () => ({ succeeded: true, ticks: 1 }));
  assert.equal(r.verdict, 'BLOCKED');
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `node --test scripts/forge/solvability_godot.test.mjs`
Expected: FAIL — module introuvable.

- [ ] **Step 3: Write minimal implementation**

Create `scripts/forge/solvability_godot.mjs` exportant `runSolvability(cfg, trialFn)` qui : rejette `trials <= 0` en `BLOCKED` (aucune preuve n'est pas une preuve — même doctrine que le cas `total==0` du gate mutation) ; capture toute exception en `BLOCKED` ; ne renvoie `OK` que si `won === trials`. La CLI en dessous résout le binaire, construit `trialFn` via `makeGodotRunTrial`, imprime le reçu JSON et sort avec 0/1.

- [ ] **Step 4: Run test to verify it passes**

Run: `node --test scripts/forge/solvability_godot.test.mjs`
Expected: `pass 4  fail 0`

- [ ] **Step 5: Écrire le bot déterministe côté Godot**

Créer `games/grid_nav_probe/solvability.gd` : un bot qui utilise `GridNav.next_step` pour atteindre la sortie d'un labyrinthe seedé, émet `FORGE_TRIAL {"succeeded":…,"ticks":…}`. `succeeded = true` seulement si la sortie est atteinte sous `max_ticks`.

- [ ] **Step 6: Exécuter la solvabilité réelle**

Run: `node scripts/forge/solvability_godot.mjs games/grid_nav_probe res://solvability.gd 50`
Expected: `"verdict": "OK"`, `won: 50`, exit 0.

Si `FAIL` : ne pas ajuster la cible pour faire passer le test. Les seeds échoués sont l'information utile — corriger la brique ou documenter pourquoi ces cas sont hors contrat.

- [ ] **Step 7: Câbler le registre d'oracles**

Ajouter à `scripts/forge/oracles.json` :

```json
 "grid_nav_probe": {
  "cwd": ".",
  "command": ["node", "scripts/forge/godot_oracle.mjs", "games/grid_nav_probe"]
 }
```

Créer `scripts/forge/godot_oracle.mjs` : enchaîne `run_tests.gd` headless **puis** la solvabilité, et sort 0 seulement si **les deux** sont verts. Le binaire est résolu via `resolveGodotBin()` — jamais un chemin en dur.

- [ ] **Step 8: Vérifier l'oracle via la Forge**

Run: `PYTHONPATH=scripts .venv312/Scripts/python.exe -c "from forge.oracle import resolve_oracle, run_oracle; print(run_oracle(resolve_oracle('grid_nav_probe')).passed)"`
Expected: `True`

- [ ] **Step 9: Non-régression Forge**

Run: `.venv312/Scripts/python.exe -m pytest scripts/forge/tests/ -q`
Expected: aucun échec.

- [ ] **Step 10: Préparer le commit (NE PAS COMMITER)**

```bash
git add scripts/forge/solvability_godot.mjs scripts/forge/solvability_godot.test.mjs scripts/forge/godot_oracle.mjs scripts/forge/oracles.json games/grid_nav_probe/solvability.gd
git diff --cached --stat
```

STOP — attendre le go de Pierre.

---

## Task 11: Certification — `proof_of_use` et verdict signé

Le gate du spec (§6) est **preuve mécanique + preuve d'usage**. Cette tâche ferme la boucle : la brique n'est `validated` que parce qu'un artefact la consomme et que sa solvabilité est prouvée.

**Files:**
- Create: `knowledge_base/proofs/grid_nav_probe_oracle.log`
- Create: `knowledge_base/proofs/grid_nav_probe_verdict.json`
- Modify: `knowledge_base/catalog.json`

**Interfaces:**
- Consumes: l'oracle de la Tâche 10 ; la brique et le rôle des Tâches 8-9.
- Produces: `sys-grid-nav-godot` et `role-grid-navigator` en `tier: "validated"` avec `proof_of_use` non-null, plus un verdict signé re-vérifiable.

- [ ] **Step 1: Produire le log de preuve**

Run: `node scripts/forge/godot_oracle.mjs games/grid_nav_probe > knowledge_base/proofs/grid_nav_probe_oracle.log 2>&1; echo "exit=$?"`
Expected: `exit=0`, le log contient les résultats de `run_tests.gd` **et** de la solvabilité.

- [ ] **Step 2: Générer le verdict signé**

Produire `knowledge_base/proofs/grid_nav_probe_verdict.json` via la chaîne de verdict existante (`forge.verdict`), en y embarquant les reçus d'oracle (code, mutation, solvabilité, role_sim). Suivre le format de `knowledge_base/proofs/kb_tactics_verdict.json`, qui sert de modèle vérifié.

- [ ] **Step 3: Re-vérifier mécaniquement le verdict**

Run: `PYTHONPATH=scripts .venv312/Scripts/python.exe -m forge.verify_run knowledge_base/proofs/grid_nav_probe_verdict.json; echo "exit=$?"`
Expected: `exit=0` — verdict authentique, évidence intacte.

**Exit 2 = falsification/altération : STOP immédiat, ne pas certifier.**

- [ ] **Step 4: Promouvoir en `validated`**

Dans `knowledge_base/catalog.json`, pour `sys-grid-nav-godot` **et** `role-grid-navigator` : `tier: "validated"` et `proof_of_use: "knowledge_base/proofs/grid_nav_probe_oracle.log"`.

- [ ] **Step 5: Valider le catalogue**

Run: `node knowledge_base/kb-validate.mjs`
Expected: `VERDICT CATALOGUE: PASS`. La règle R8 vérifie réellement que `proof_of_use` pointe un fichier existant sous `knowledge_base/proofs/` — un chemin inventé est rejeté.

- [ ] **Step 6: Vérifier les 8 critères de succès du spec**

Reprendre §12 du spec **un par un** et consigner pour chacun la commande exécutée et sa sortie. Tout critère rouge = étape 0 non franchie. **Aucun succès partiel déclaré.**

- [ ] **Step 7: Préparer le commit (NE PAS COMMITER)**

```bash
git add knowledge_base/proofs/ knowledge_base/catalog.json
git diff --cached --stat
```

STOP — attendre le go de Pierre.

---

## Task 12: Instrumentation d'apprentissage et protocole de capital externe

Livrables E1 et C1 du spec. Sans cette tâche, l'étape 0 produit une brique mais **aucune trace de ce que la Forge a appris** — l'objectif réel du curriculum.

**Files:**
- Create: `scripts/forge/learning_metrics.mjs`
- Create: `scripts/forge/learning_metrics.test.mjs`
- Create: `lab/forge_evidence/learning_curve.jsonl`
- Create: `external_sources/README.md`
- Create: `external_sources/studied/.gitkeep`, `external_sources/imported_code/.gitkeep`, `external_sources/extracted_knowledge/.gitkeep`

**Interfaces:**
- Produces: `recordLearning({brick_id, reuse_ratio, oracle_iterations, joust_delta}) => object` — ajoute une ligne à `lab/forge_evidence/learning_curve.jsonl`. `joust_delta` vaut `null` quand aucune référence n'existe (autorisé, mais la ligne est marquée `no_comparison: true`).

- [ ] **Step 1: Write the failing test**

```javascript
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildRecord } from './learning_metrics.mjs';

test('un enregistrement complet porte les 3 metriques', () => {
  const r = buildRecord({ brick_id: 'sys-grid-nav-godot', reuse_ratio: 0, oracle_iterations: 2, joust_delta: null });
  assert.equal(r.brick_id, 'sys-grid-nav-godot');
  assert.equal(r.oracle_iterations, 2);
  assert.equal(r.no_comparison, true);
});

test('joust_delta present -> no_comparison false', () => {
  const r = buildRecord({ brick_id: 'x', reuse_ratio: 0.5, oracle_iterations: 1, joust_delta: 0.12 });
  assert.equal(r.no_comparison, false);
});

test('brick_id manquant -> erreur (pas de ligne anonyme dans la courbe)', () => {
  assert.throws(() => buildRecord({ reuse_ratio: 0, oracle_iterations: 1, joust_delta: null }), /brick_id/);
});

test('oracle_iterations negatif -> erreur', () => {
  assert.throws(() => buildRecord({ brick_id: 'x', reuse_ratio: 0, oracle_iterations: -1, joust_delta: null }), /oracle_iterations/);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `node --test scripts/forge/learning_metrics.test.mjs`
Expected: FAIL — module introuvable.

- [ ] **Step 3: Write minimal implementation**

Créer `scripts/forge/learning_metrics.mjs` avec `buildRecord()` (pur, validant, testable) séparé de `recordLearning()` (qui écrit sur disque). L'horodatage est **injecté en paramètre**, jamais `Date.now()` interne — sinon la fonction devient non testable et non déterministe.

- [ ] **Step 4: Run test to verify it passes**

Run: `node --test scripts/forge/learning_metrics.test.mjs`
Expected: `pass 4  fail 0`

- [ ] **Step 5: Enregistrer la ligne de base M01**

Mesurer `reuse_ratio` via `node scripts/forge/reuse_ratio.mjs` sur `grid_nav_probe`, relever le nombre réel d'itérations d'oracle nécessaires en Tâches 8-10, puis écrire la première ligne de `learning_curve.jsonl`.

- [ ] **Step 6: Écrire le protocole de capital externe**

Créer `external_sources/README.md` documentant la règle non négociable :

```
source externe → analyse → connaissance propriétaire → réimplémentation Forge
```

et **jamais** `dépôt trouvé → copier-coller → KB`. Documenter les trois dossiers, et **citer les gardes existantes qui rendent la règle exécutoire** (`kb-validate.mjs`) : R2 licences en liste fermée SPDX · R4 GPL interdite sur du code · R4-contenu détection d'un marqueur GPL dans un module déclaré permissif · R3 `provenance_url` obligatoire pour un pattern · R5/R11 patterns `advisory_only`, cités jamais injectés · R3 marqueur exact `ORIGINAL — aucune inspiration externe citee`.

Inclure le gabarit de `studied/<source>/source_reference.yaml` (nom, URL, licence, ce qui a été retenu, ce qui a été rejeté et pourquoi).

- [ ] **Step 7: Documenter honnêtement la limite**

Ajouter en tête de `learning_curve.jsonl` (dans le README de `lab/forge_evidence/`) la mention du spec §10 : **sur une seule mécanique, ces trois nombres n'ont aucune valeur statistique.** Ils établissent la ligne de base et prouvent que l'instrumentation enregistre. Aucune conclusion sur l'apprentissage n'est tirée à l'étape 0.

- [ ] **Step 8: Préparer le commit (NE PAS COMMITER)**

```bash
git add scripts/forge/learning_metrics.mjs scripts/forge/learning_metrics.test.mjs lab/forge_evidence/ external_sources/
git diff --cached --stat
```

STOP — attendre le go de Pierre.

---

## Rapport de fin de plan

À produire une fois les 12 tâches terminées :

```
software_verdict: OK|FAIL|BLOCKED
evidence_verdict: MECHANICAL_VALIDATION_ONLY
claim_verdict: NO_CLAIM_ALLOWED
```

Joindre, pour chacun des 8 critères de succès du spec §12, la commande exécutée et sa sortie réelle. **Preuve d'exécution, pas preuve d'existence.**

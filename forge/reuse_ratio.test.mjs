// reuse_ratio.test.mjs — tests de reuse_ratio.mjs, avec un fixture jetable (pas de
// dépendance à un vrai jeu du repo — déterministe, isolé).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync, rmSync, mkdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { measureReuseRatio } from './reuse_ratio.mjs';

function makeFixture(files) {
  const dir = mkdtempSync(join(tmpdir(), 'reuse-ratio-test-'));
  for (const [name, content] of Object.entries(files)) {
    writeFileSync(join(dir, name), content, 'utf-8');
  }
  return dir;
}

test('zéro import knowledge_base -> reuse_ratio == 0', () => {
  const dir = makeFixture({
    'game.mjs': "import { foo } from './level.mjs';\nexport function bar(){}\n",
    'level.mjs': 'export function foo(){}\n',
  });
  const result = measureReuseRatio(dir);
  assert.equal(result.reuseRatio, 0);
  assert.equal(result.reusedModules.length, 0);
  rmSync(dir, { recursive: true, force: true });
});

test('tous les fichiers importent la bibliothèque -> ratio calculé correctement', () => {
  const dir = makeFixture({
    'game.mjs': "import { a } from '../../knowledge_base/systems/x/a.mjs';\nimport { b } from '../../knowledge_base/systems/y/b.mjs';\n",
  });
  const result = measureReuseRatio(dir);
  // 1 fichier de logique, 2 modules KB réutilisés -> 2 / (1+2) = 0.667
  assert.equal(result.logicFiles.length, 1);
  assert.equal(result.reusedModules.length, 2);
  assert.ok(Math.abs(result.reuseRatio - 2 / 3) < 1e-9);
  rmSync(dir, { recursive: true, force: true });
});

test('les fichiers de harnais (main/server/e2e/run-oracle/solvability) sont EXCLUS du scan', () => {
  const dir = makeFixture({
    'game.mjs': "import { a } from '../../knowledge_base/systems/x/a.mjs';\n",
    'main.mjs': "import { spy } from '../../knowledge_base/systems/should-not-count.mjs';\n",
    'server.mjs': "import { spy2 } from '../../knowledge_base/systems/should-not-count-2.mjs';\n",
    'e2e.mjs': "import { spy3 } from '../../knowledge_base/systems/should-not-count-3.mjs';\n",
  });
  const result = measureReuseRatio(dir);
  assert.deepEqual(result.logicFiles, ['game.mjs']);
  assert.deepEqual(result.reusedModules, ['../../knowledge_base/systems/x/a.mjs']);
  rmSync(dir, { recursive: true, force: true });
});

test('les fichiers *.test.mjs sont EXCLUS du scan', () => {
  const dir = makeFixture({
    'game.mjs': 'export function f(){}\n',
    'game.test.mjs': "import { spy } from '../../knowledge_base/systems/should-not-count.mjs';\n",
  });
  const result = measureReuseRatio(dir);
  assert.deepEqual(result.logicFiles, ['game.mjs']);
  assert.equal(result.reusedModules.length, 0);
  rmSync(dir, { recursive: true, force: true });
});

test('un import externe (npm, ni local ni knowledge_base) n\'est compté dans aucune des deux catégories', () => {
  const dir = makeFixture({
    'game.mjs': "import chalk from 'chalk';\nexport function f(){}\n",
  });
  const result = measureReuseRatio(dir);
  assert.equal(result.reusedModules.length, 0);
  const externalImport = result.imports.find((i) => i.specifier === 'chalk');
  assert.equal(externalImport.classification, 'external');
  rmSync(dir, { recursive: true, force: true });
});

test('déterminisme : deux appels sur le même dossier donnent le même résultat', () => {
  const dir = makeFixture({
    'game.mjs': "import { a } from '../../knowledge_base/systems/x/a.mjs';\nimport { b } from './level.mjs';\n",
    'level.mjs': 'export function b(){}\n',
  });
  const a = measureReuseRatio(dir);
  const b = measureReuseRatio(dir);
  assert.deepEqual(a, b);
  rmSync(dir, { recursive: true, force: true });
});

test('vérifié contre un vrai jeu du repo (kb_tactics) : reuse_ratio == 2/6 == 0.333...', () => {
  // Ancrage à la réalité (pas seulement des fixtures synthétiques) — kb_tactics est le
  // seul jeu du repo qui importe réellement depuis knowledge_base/ à ce jour.
  const result = measureReuseRatio('GAMES/kb_tactics');
  assert.deepEqual(result.logicFiles.sort(), ['game.mjs', 'input.mjs', 'level.mjs', 'render.mjs']);
  assert.equal(result.reusedModules.length, 2);
  assert.ok(Math.abs(result.reuseRatio - 2 / 6) < 1e-9, `attendu ~0.333, got ${result.reuseRatio}`);
});

// --- Extension cross_game (2026-07-28) --------------------------------------------
// Fixtures avec une arborescence GAMES/<jeu>/ réelle (pas juste un dossier plat) car la
// résolution cross_game dépend de la présence du segment 'games' dans le chemin résolu.

function makeMultiGameFixture(gamesSpec) {
  const root = mkdtempSync(join(tmpdir(), 'reuse-ratio-crossgame-test-'));
  const gamesRoot = join(root, 'GAMES');
  for (const [gameName, files] of Object.entries(gamesSpec)) {
    for (const [name, content] of Object.entries(files)) {
      const filePath = join(gamesRoot, gameName, name);
      const fileDir = join(filePath, '..');
      mkdirSync(fileDir, { recursive: true });
      writeFileSync(filePath, content, 'utf-8');
    }
  }
  return { root, gamesRoot };
}

test('import relatif intra-jeu (même dossier de jeu) reste classé local, jamais cross_game', () => {
  const { root, gamesRoot } = makeMultiGameFixture({
    pong: {
      'game.mjs': "import { a } from './level.mjs';\n",
      'level.mjs': 'export function a(){}\n',
    },
  });
  const result = measureReuseRatio(join(gamesRoot, 'pong'));
  const imp = result.imports.find((i) => i.specifier === './level.mjs');
  assert.equal(imp.classification, 'local');
  assert.equal(result.crossGameModules.length, 0);
  assert.equal(result.crossGameReuse, 0);
  rmSync(root, { recursive: true, force: true });
});

test('import relatif qui résout vers GAMES/<autre_jeu>/ est classé cross_game, résolution mécanique', () => {
  const { root, gamesRoot } = makeMultiGameFixture({
    pong: {
      'game.mjs': "import { paddle } from '../snake/paddle.mjs';\n",
    },
    snake: {
      'paddle.mjs': 'export function paddle(){}\n',
    },
  });
  const result = measureReuseRatio(join(gamesRoot, 'pong'));
  const imp = result.imports.find((i) => i.specifier === '../snake/paddle.mjs');
  assert.equal(imp.classification, 'cross_game');
  assert.equal(imp.resolved, join(gamesRoot, 'snake', 'paddle.mjs'));
  assert.equal(result.crossGameModules.length, 1);
  // 1 fichier de logique, 1 module cross_game -> 1 / (1+1) = 0.5
  assert.ok(Math.abs(result.crossGameReuse - 0.5) < 1e-9);
  rmSync(root, { recursive: true, force: true });
});

test('knowledge_base reste classé knowledge_base (inchangé) même avec la résolution cross_game active', () => {
  const { root, gamesRoot } = makeMultiGameFixture({
    pong: {
      'game.mjs': "import { a } from '../../knowledge_base/systems/x/a.mjs';\n",
    },
  });
  const result = measureReuseRatio(join(gamesRoot, 'pong'));
  const imp = result.imports.find((i) => i.specifier.includes('knowledge_base'));
  assert.equal(imp.classification, 'knowledge_base');
  assert.equal(result.reusedModules.length, 1);
  assert.ok(Math.abs(result.reuseRatio - 1 / 2) < 1e-9);
  assert.equal(result.crossGameModules.length, 0);
  rmSync(root, { recursive: true, force: true });
});

test('specifier nu (paquet npm / node:) reste ignoré (external), pas résolu comme cross_game', () => {
  const { root, gamesRoot } = makeMultiGameFixture({
    pong: {
      'game.mjs': "import fs from 'node:fs';\nimport chalk from 'chalk';\n",
    },
  });
  const result = measureReuseRatio(join(gamesRoot, 'pong'));
  const nodeImp = result.imports.find((i) => i.specifier === 'node:fs');
  const chalkImp = result.imports.find((i) => i.specifier === 'chalk');
  assert.equal(nodeImp.classification, 'external');
  assert.equal(chalkImp.classification, 'external');
  assert.equal(result.crossGameModules.length, 0);
  assert.equal(result.crossGameReuse, 0);
  rmSync(root, { recursive: true, force: true });
});

test('sortie CLI réelle sur GAMES/pong : reuse_ratio inchangé (0.000) et cross_game_reuse == 0', () => {
  // GAMES/pong n'importe aujourd'hui aucun autre jeu — ancrage à la réalité, comme le
  // test kb_tactics ci-dessus.
  const result = measureReuseRatio('GAMES/pong');
  assert.equal(result.reuseRatio, 0);
  assert.equal(result.crossGameReuse, 0);
  assert.deepEqual(result.crossGameModules, []);
});

// --- Extension GDScript preload/load (2026-07-28) ---------------------------------
// Correctif mesuré : extractImportSpecifiers ne matchait que `from "..."` (imports ES),
// jamais preload()/load() GDScript, donnant reuse_ratio = 0 par construction sur tout
// jeu Godot (ex. GAMES/grid_nav_probe, cf. CLI réelle plus bas). Fixtures avec un vrai
// `project.godot` sous gameDir : c'est de là que `res://` doit se résoudre mécaniquement
// (findGodotProjectRoot), pas depuis gameDir si un sous-dossier contenait le projet.

function makeGdFixture(files) {
  const dir = mkdtempSync(join(tmpdir(), 'reuse-ratio-gd-test-'));
  for (const [name, content] of Object.entries(files)) {
    const filePath = join(dir, name);
    mkdirSync(join(filePath, '..'), { recursive: true });
    writeFileSync(filePath, content, 'utf-8');
  }
  return dir;
}

test('preload("res://...") vers une COPIE LOCALE (dans le jeu) est classé local, pas reuse', () => {
  const dir = makeGdFixture({
    'project.godot': '[application]\nconfig/name="Fixture"\n',
    'trial.gd': 'const GridNav = preload("res://core/grid_nav.gd")\n',
    'core/grid_nav.gd': 'extends Node\nfunc _ready(): pass\n',
  });
  const result = measureReuseRatio(dir);
  const imp = result.imports.find((i) => i.file === 'trial.gd');
  assert.equal(imp.classification, 'local');
  assert.equal(imp.resolved, join(dir, 'core', 'grid_nav.gd'));
  assert.equal(result.reusedModules.length, 0);
  rmSync(dir, { recursive: true, force: true });
});

test('preload("res://...") qui se résout DANS knowledge_base/ est classé reuse (knowledge_base)', () => {
  // Fixture : project.godot placé de sorte que knowledge_base/ soit visible depuis la
  // racine du projet Godot détectée — simule le seul cas où res:// peut mécaniquement
  // atteindre la bibliothèque (elle est dans l'arbre du projet).
  const dir = makeGdFixture({
    'project.godot': '[application]\nconfig/name="Fixture"\n',
    'trial.gd': 'const Nav = preload("res://knowledge_base/systems/navigation/grid_nav.gd")\n',
    'knowledge_base/systems/navigation/grid_nav.gd': 'extends Node\n',
  });
  const result = measureReuseRatio(dir);
  const imp = result.imports.find((i) => i.file === 'trial.gd');
  assert.equal(imp.classification, 'knowledge_base');
  assert.deepEqual(result.reusedModules, ['res://knowledge_base/systems/navigation/grid_nav.gd']);
  // 2 fichiers de logique scannés (trial.gd + la brique knowledge_base/... elle-même
  // vit sous gameDir dans cette fixture et est donc aussi comptée comme fichier de
  // logique) + 1 module KB réutilisé -> 1 / (2+1) = 0.333...
  assert.equal(result.logicFiles.length, 2);
  assert.ok(Math.abs(result.reuseRatio - 1 / 3) < 1e-9, `attendu ~0.333, got ${result.reuseRatio}`);
  rmSync(dir, { recursive: true, force: true });
});

test('load(...) est extrait au même titre que preload(...)', () => {
  const dir = makeGdFixture({
    'project.godot': '[application]\nconfig/name="Fixture"\n',
    'trial.gd': 'func f():\n\tvar x = load("res://core/grid_nav.gd")\n',
    'core/grid_nav.gd': 'extends Node\n',
  });
  const result = measureReuseRatio(dir);
  const imp = result.imports.find((i) => i.file === 'trial.gd');
  assert.ok(imp, 'load(...) devrait être extrait comme un import');
  assert.equal(imp.specifier, 'res://core/grid_nav.gd');
  assert.equal(imp.classification, 'local');
  rmSync(dir, { recursive: true, force: true });
});

test('fichier .gd sans preload/load -> 0 import extrait', () => {
  const dir = makeGdFixture({
    'project.godot': '[application]\nconfig/name="Fixture"\n',
    'trial.gd': 'extends Node\nfunc _ready():\n\tpass\n',
  });
  const result = measureReuseRatio(dir);
  const gdImports = result.imports.filter((i) => i.file === 'trial.gd');
  assert.equal(gdImports.length, 0);
  rmSync(dir, { recursive: true, force: true });
});

test('specifier non résoluble mécaniquement (ni res://, ni chemin relatif) -> external, resolved:null', () => {
  const dir = makeGdFixture({
    'project.godot': '[application]\nconfig/name="Fixture"\n',
    'trial.gd': 'const X = preload("weird_bare_specifier")\n',
  });
  const result = measureReuseRatio(dir);
  const imp = result.imports.find((i) => i.file === 'trial.gd');
  assert.equal(imp.classification, 'external');
  assert.equal(imp.resolved, null);
  rmSync(dir, { recursive: true, force: true });
});

test('sortie CLI réelle sur GAMES/grid_nav_probe : preload("res://core/grid_nav.gd") est vu, classé local (copie dans le jeu, pas la brique knowledge_base)', () => {
  // Ancrage à la réalité : GAMES/grid_nav_probe/core/grid_nav.gd est une COPIE locale
  // (project.godot vit à la racine du jeu -> res:// se résout dans le jeu, jamais dans
  // knowledge_base/systems/navigation/grid_nav.gd qui est hors de l'arbre du projet).
  const result = measureReuseRatio('GAMES/grid_nav_probe');
  const localGdImports = result.imports.filter(
    (i) => i.specifier === 'res://core/grid_nav.gd' && i.classification === 'local',
  );
  assert.ok(localGdImports.length >= 1, 'attendu au moins un preload res://core/grid_nav.gd classé local');
  assert.equal(result.reusedModules.length, 0, 'aucune brique knowledge_base réellement importée ici');
});

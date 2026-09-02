// backfill_learning_curve.test.mjs — tests du backfill de knowledge_base/learning_curve.jsonl
// depuis les runs Forge archivés (EVIDENCE/runs/<run>/state.json).
//
// LEARNING_SUBJECT_MODEL_V1 (2026-07-26) : un run qui forge un JEU produit désormais
// subject:{type:'game', id:<projet effectif>} SANS exiger de correspondance dans
// knowledge_base/catalog.json — c'était exactement le bug (« un jeu n'est pas une brique »,
// donc exiger qu'il matche le catalogue des briques garantissait 0 ligne). Un run non-jeu
// (is_game!==true) reste SKIPPED : ce pipeline (driver.py) n'a aucune source pour mesurer
// reuse_ratio d'une brique de bibliothèque (pas de gameDir équivalent) — brancher cette
// source est explicitement l'étape 2 du plan ratifié, hors périmètre ici (pas d'anticipation
// d'étape). Aucune entrée catalogue n'est créée ou promue par ce module (jeu != brique).
//
// Discipline : fixtures jetables (mkdtempSync, hors dépôt) pour tous les cas synthétiques —
// AUCUNE écriture durable dans le dépôt. Un seul test tape le vrai dépôt (runs réels), en
// lecture seule, avec une cible d'écriture temporaire : il documente/verrouille le résultat
// honnête actuel (falsifiable : N lignes réelles > 0 depuis la correction du modèle de sujet).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync, mkdirSync, writeFileSync, readFileSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  backfillLearningCurve,
  normalizeEscalations,
  resolveOracleIterations,
  DEFAULT_RUNS_DIR,
  DEFAULT_GAMES_DIR,
} from './backfill_learning_curve.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));

function makeRun(runsDir, name, state) {
  const dir = join(runsDir, name);
  mkdirSync(dir, { recursive: true });
  writeFileSync(join(dir, 'state.json'), JSON.stringify(state), 'utf-8');
  return dir;
}

function makeGame(gamesDir, name, files) {
  const dir = join(gamesDir, name);
  mkdirSync(dir, { recursive: true });
  for (const [rel, content] of Object.entries(files)) {
    writeFileSync(join(dir, rel), content, 'utf-8');
  }
  return dir;
}

function readLines(path) {
  if (!existsSync(path)) return [];
  return readFileSync(path, 'utf-8').trim().split('\n').filter(Boolean).map((l) => JSON.parse(l));
}

function withTmp(fn) {
  const root = mkdtempSync(join(tmpdir(), 'backfill-lc-'));
  const runsDir = join(root, 'runs');
  const gamesDir = join(root, 'GAMES');
  mkdirSync(runsDir, { recursive: true });
  mkdirSync(gamesDir, { recursive: true });
  const targetPath = join(root, 'learning_curve.jsonl');
  try {
    fn({ root, runsDir, gamesDir, targetPath });
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

// --- normalizeEscalations : schéma hétérogène (entier ancien vs liste récent) -------
test('normalizeEscalations: entier -> renvoyé tel quel', () => {
  assert.equal(normalizeEscalations(2), 2);
  assert.equal(normalizeEscalations(0), 0);
});
test('normalizeEscalations: liste -> longueur', () => {
  assert.equal(normalizeEscalations(['e1', 'e2']), 2);
  assert.equal(normalizeEscalations([]), 0);
});
test('normalizeEscalations: valeur inattendue (null/undefined/string) -> 0, jamais un crash', () => {
  assert.equal(normalizeEscalations(null), 0);
  assert.equal(normalizeEscalations(undefined), 0);
  assert.equal(normalizeEscalations('oops'), 0);
});

// --- resolveOracleIterations : steps hétérogènes ------------------------------------
test('resolveOracleIterations: steps vide -> null', () => {
  assert.equal(resolveOracleIterations({}), null);
  assert.equal(resolveOracleIterations(null), null);
  assert.equal(resolveOracleIterations(undefined), null);
});
test('resolveOracleIterations: s10a-oracle-code OK -> attempts', () => {
  const r = resolveOracleIterations({ 's10a-oracle-code': { status: 'OK', attempts: 5, ts: 100 } });
  assert.equal(r.iterations, 5);
  assert.equal(r.stepName, 's10a-oracle-code');
});
test('resolveOracleIterations: statut non-OK (jamais vert) -> null', () => {
  const r = resolveOracleIterations({ 's10a-oracle-code': { status: 'BLOCKED', attempts: 1 } });
  assert.equal(r, null);
});
test('resolveOracleIterations: profil standard -> s10s-oracle-standard', () => {
  const r = resolveOracleIterations({ 's10s-oracle-standard': { status: 'OK', attempts: 1, ts: 1 } });
  assert.equal(r.stepName, 's10s-oracle-standard');
});

// --- backfillLearningCurve : cas limites -------------------------------------------

test('backfill: run de JEU (is_game=true) -> ligne écrite subject:{type:"game"}, AUCUNE correspondance catalogue exigée', () => {
  // Verrouille le correctif LEARNING_SUBJECT_MODEL_V1 : avant, ce run était SKIPPED
  // ("n'est pas une brique du catalogue") alors que rien n'a jamais promis qu'un jeu en
  // soit une. C'était le bug qui produisait 0 ligne sur les 7 runs archivés.
  withTmp(({ runsDir, gamesDir, targetPath }) => {
    makeRun(runsDir, 'pong', {
      project: 'pong', is_game: true,
      steps: { 's10a-oracle-code': { status: 'OK', attempts: 3, ts: 1700000000 } },
    });
    makeGame(gamesDir, 'pong', { 'game.mjs': 'export function f(){}\n' });
    const results = backfillLearningCurve({ runsDir, gamesDir, targetPath });
    assert.equal(results.length, 1);
    assert.equal(results[0].skipped, false);
    const lines = readLines(targetPath);
    assert.equal(lines.length, 1);
    assert.deepEqual(lines[0].subject, { type: 'game', id: 'pong' });
  });
});

test('backfill: oracle jamais vert (status FAIL) -> SKIPPED', () => {
  withTmp(({ runsDir, gamesDir, targetPath }) => {
    makeRun(runsDir, 'pong', {
      project: 'pong', is_game: true,
      steps: { 's10a-oracle-code': { status: 'FAIL', attempts: 2 } },
    });
    const results = backfillLearningCurve({ runsDir, gamesDir, targetPath });
    assert.equal(results[0].skipped, true);
    assert.match(results[0].reason, /jamais atteint le vert/);
  });
});

test('backfill: is_game=false -> SKIPPED (pas de gameDir/source de reuse_ratio dans ce pipeline, étape 2 hors périmètre)', () => {
  withTmp(({ runsDir, gamesDir, targetPath }) => {
    makeRun(runsDir, 'driver_smoke', {
      project: 'driver_smoke', is_game: false,
      steps: { 's10a-oracle-code': { status: 'OK', attempts: 1, ts: 1700000000 } },
    });
    const results = backfillLearningCurve({ runsDir, gamesDir, targetPath });
    assert.equal(results[0].skipped, true);
    assert.match(results[0].reason, /is_game=false/);
    assert.equal(existsSync(targetPath), false);
  });
});

test('backfill: gameDir absent du disque -> SKIPPED', () => {
  withTmp(({ runsDir, gamesDir, targetPath }) => {
    makeRun(runsDir, 'ghost_game', {
      project: 'ghost_game', is_game: true,
      steps: { 's10a-oracle-code': { status: 'OK', attempts: 1, ts: 1700000000 } },
    });
    // pas de makeGame() : gameDir n'existe pas
    const results = backfillLearningCurve({ runsDir, gamesDir, targetPath });
    assert.equal(results[0].skipped, true);
    assert.match(results[0].reason, /gameDir introuvable/);
  });
});

test('backfill: state.json corrompu -> SKIPPED avec raison, ne fait PAS planter les autres runs', () => {
  withTmp(({ runsDir, gamesDir, targetPath }) => {
    mkdirSync(join(runsDir, 'broken'), { recursive: true });
    writeFileSync(join(runsDir, 'broken', 'state.json'), '{ ceci nest pas du json', 'utf-8');
    makeRun(runsDir, 'ok_game', {
      project: 'ok_game', is_game: true,
      steps: { 's10a-oracle-code': { status: 'OK', attempts: 2, ts: 1700000000 } },
    });
    makeGame(gamesDir, 'ok_game', { 'game.mjs': 'export function f(){}\n' });
    const results = backfillLearningCurve({ runsDir, gamesDir, targetPath });
    assert.equal(results.length, 2);
    const broken = results.find((r) => r.run === 'broken');
    const ok = results.find((r) => r.run === 'ok_game');
    assert.equal(broken.skipped, true);
    assert.match(broken.reason, /illisible|corrompu/);
    assert.equal(ok.skipped, false);
  });
});

test('backfill: run dir sans state.json -> ignoré silencieusement (hors périmètre "7 runs archivés")', () => {
  withTmp(({ runsDir, gamesDir, targetPath }) => {
    mkdirSync(join(runsDir, 'no_state_here'), { recursive: true });
    const results = backfillLearningCurve({ runsDir, gamesDir, targetPath });
    assert.equal(results.length, 0);
  });
});

test('backfill: run sans champ "project" -> retombe sur le nom du dossier', () => {
  withTmp(({ runsDir, gamesDir, targetPath }) => {
    makeRun(runsDir, 'anon_run', {
      is_game: true,
      steps: { 's10a-oracle-code': { status: 'OK', attempts: 1, ts: 1700000000 } },
    });
    makeGame(gamesDir, 'anon_run', { 'game.mjs': 'export function f(){}\n' });
    const results = backfillLearningCurve({ runsDir, gamesDir, targetPath });
    assert.equal(results[0].project, 'anon_run');
    assert.equal(results[0].skipped, false);
    const lines = readLines(targetPath);
    assert.deepEqual(lines[0].subject, { type: 'game', id: 'anon_run' });
  });
});

// --- Cas HEUREUX : jeu réel, reuse_ratio mesuré via measureReuseRatio --------------
test('backfill: run éligible (jeu + gameDir réel) -> ligne écrite, valeurs mesurées', () => {
  withTmp(({ runsDir, gamesDir, targetPath }) => {
    makeRun(runsDir, 'fixture_run', {
      project: 'sys-fixture-01', is_game: true,
      steps: { 's10a-oracle-code': { status: 'OK', attempts: 3, ts: 1700000000 } },
    });
    makeGame(gamesDir, 'sys-fixture-01', {
      'game.mjs': "import { a } from '../../knowledge_base/systems/x/a.mjs';\nimport { b } from './level.mjs';\n",
      'level.mjs': 'export function b(){}\n',
    });
    const results = backfillLearningCurve({ runsDir, gamesDir, targetPath });
    assert.equal(results.length, 1);
    assert.equal(results[0].skipped, false);
    const lines = readLines(targetPath);
    assert.equal(lines.length, 1);
    assert.deepEqual(lines[0].subject, { type: 'game', id: 'sys-fixture-01' });
    assert.equal(lines[0].oracle_iterations, 3);
    assert.equal(lines[0].joust_delta, null);
    assert.equal(lines[0].no_comparison, true);
    // reuse_ratio réellement mesuré par measureReuseRatio (2 fichiers logique, 1 module KB)
    assert.ok(Math.abs(lines[0].reuse_ratio - 1 / 3) < 1e-9, `attendu ~0.333, got ${lines[0].reuse_ratio}`);
    assert.equal(lines[0].timestamp, new Date(1700000000 * 1000).toISOString());
  });
});

test('backfill: gameDir dérivé du reçu de mutation (patch qui cible le jeu de base)', () => {
  withTmp(({ runsDir, gamesDir, targetPath }) => {
    const realGameDir = makeGame(gamesDir, 'sys-fixture-base', { 'game.mjs': 'export function f(){}\n' });
    makeRun(runsDir, 'sys-fixture-base_patch1', {
      project: 'sys-fixture-base_patch1', is_game: true,
      steps: {
        's10a-oracle-code': {
          status: 'OK', attempts: 6, ts: 1700000100,
          detail: { mutation: { receipt: { detail: { game_dir: realGameDir } } } },
        },
      },
    });
    const results = backfillLearningCurve({ runsDir, gamesDir, targetPath });
    assert.equal(results[0].skipped, false);
    assert.equal(results[0].effective_project, 'sys-fixture-base');
    const lines = readLines(targetPath);
    assert.deepEqual(lines[0].subject, { type: 'game', id: 'sys-fixture-base' });
  });
});

// --- Préservation de la ligne existante + idempotence -------------------------------
test('backfill: ligne manuelle historique (brick_id seul) JAMAIS réécrite/supprimée', () => {
  withTmp(({ runsDir, gamesDir, targetPath }) => {
    const manualLine = JSON.stringify({
      brick_id: 'sys-grid-nav-m01', reuse_ratio: 0, oracle_iterations: 5, joust_delta: null,
      no_comparison: true, timestamp: '2026-07-21T00:00:00.000Z', note: 'saisie manuelle',
    });
    writeFileSync(targetPath, manualLine + '\n', 'utf-8');

    makeRun(runsDir, 'fixture_run2', {
      project: 'sys-fixture-02', is_game: true,
      steps: { 's10a-oracle-code': { status: 'OK', attempts: 2, ts: 1700000200 } },
    });
    makeGame(gamesDir, 'sys-fixture-02', { 'game.mjs': 'export function f(){}\n' });

    backfillLearningCurve({ runsDir, gamesDir, targetPath });

    const lines = readLines(targetPath);
    assert.equal(lines.length, 2);
    // ligne historique : intacte à l'octet près (toujours brick_id, jamais convertie en subject)
    assert.equal(lines[0].brick_id, 'sys-grid-nav-m01');
    assert.equal(lines[0].subject, undefined);
    assert.equal(lines[0].note, 'saisie manuelle');
    assert.deepEqual(lines[1].subject, { type: 'game', id: 'sys-fixture-02' });
  });
});

test('backfill: fichier cible pré-existant mais VIDE -> traité comme absent, première ligne écrite normalement', () => {
  withTmp(({ runsDir, gamesDir, targetPath }) => {
    writeFileSync(targetPath, '', 'utf-8'); // 0 octet, existe déjà sur disque
    makeRun(runsDir, 'fixture_run_empty', {
      project: 'sys-fixture-empty', is_game: true,
      steps: { 's10a-oracle-code': { status: 'OK', attempts: 2, ts: 1700000500 } },
    });
    makeGame(gamesDir, 'sys-fixture-empty', { 'game.mjs': 'export function f(){}\n' });

    const results = backfillLearningCurve({ runsDir, gamesDir, targetPath });
    assert.equal(results[0].skipped, false);
    const lines = readLines(targetPath);
    assert.equal(lines.length, 1);
    assert.deepEqual(lines[0].subject, { type: 'game', id: 'sys-fixture-empty' });
  });
});

test('backfill: runsDir vide (aucun sous-dossier) -> résultats vides, rien écrit', () => {
  withTmp(({ runsDir, gamesDir, targetPath }) => {
    const results = backfillLearningCurve({ runsDir, gamesDir, targetPath });
    assert.deepEqual(results, []);
    assert.equal(existsSync(targetPath), false);
  });
});

test('backfill: double exécution -> pas de doublon (idempotent)', () => {
  withTmp(({ runsDir, gamesDir, targetPath }) => {
    makeRun(runsDir, 'fixture_run3', {
      project: 'sys-fixture-03', is_game: true,
      steps: { 's10a-oracle-code': { status: 'OK', attempts: 4, ts: 1700000300 } },
    });
    makeGame(gamesDir, 'sys-fixture-03', { 'game.mjs': 'export function f(){}\n' });

    const r1 = backfillLearningCurve({ runsDir, gamesDir, targetPath });
    const r2 = backfillLearningCurve({ runsDir, gamesDir, targetPath });

    assert.equal(r1[0].skipped, false);
    assert.equal(r2[0].skipped, true);
    assert.match(r2[0].reason, /idempotent|déjà présent/);

    const lines = readLines(targetPath);
    assert.equal(lines.length, 1); // toujours une seule ligne malgré 2 exécutions
  });
});

test('backfill: double exécution reste idempotente même en présence de la ligne historique brick_id', () => {
  // Cas limite explicite : le fichier cible mélange une ligne historique (brick_id seul,
  // jamais réécrite) et des lignes "game" nouvelles -> _recordExists doit ignorer la ligne
  // historique (subject non déterminable pour ce couple type/id) sans jamais planter.
  withTmp(({ runsDir, gamesDir, targetPath }) => {
    writeFileSync(targetPath, JSON.stringify({
      brick_id: 'sys-grid-nav-m01', reuse_ratio: 0, oracle_iterations: 5, joust_delta: null,
      no_comparison: true, timestamp: '2026-07-21T00:00:00.000Z',
    }) + '\n', 'utf-8');
    makeRun(runsDir, 'fixture_run4', {
      project: 'sys-fixture-04', is_game: true,
      steps: { 's10a-oracle-code': { status: 'OK', attempts: 1, ts: 1700000400 } },
    });
    makeGame(gamesDir, 'sys-fixture-04', { 'game.mjs': 'export function f(){}\n' });

    backfillLearningCurve({ runsDir, gamesDir, targetPath });
    backfillLearningCurve({ runsDir, gamesDir, targetPath });

    const lines = readLines(targetPath);
    assert.equal(lines.length, 2); // 1 historique + 1 nouvelle, jamais de doublon
  });
});

// --- Intégration réelle (lecture seule dépôt, écriture cible temporaire) ------------
// Verrouille/documente le résultat honnête actuel APRÈS le correctif du modèle de sujet :
// les runs de JEU archivés dont l'oracle de code a atteint le vert et dont le gameDir
// existe sur disque produisent désormais une ligne réelle (subject:{type:'game'}).
test('INTEGRATION (réel, lecture seule) : les 7 runs archivés connus sont tous couverts, >=1 ligne backfillée', () => {
  const root = mkdtempSync(join(tmpdir(), 'backfill-lc-real-'));
  const targetPath = join(root, 'learning_curve.jsonl');
  try {
    const results = backfillLearningCurve({ targetPath }); // runsDir/gamesDir réels par défaut
    const known = ['driver_smoke', 'pong', 'pong_verif', 'shmup_slice', 'shmup_slice_art', 'shmup_slice_patch1', 'shmup_slice_patch2'];
    for (const name of known) {
      const r = results.find((x) => x.run === name);
      assert.ok(r, `run ${name} attendu dans les résultats (state.json connu)`);
    }
    const written = results.filter((r) => !r.skipped);
    // Critère falsifiable (ratification 2026-07-26) : le backfill doit passer de 0 ligne à
    // N lignes réelles. Si ce compte retombe à 0, le modèle de sujet n'était pas la cause du
    // blocage -> ce test échouerait alors franchement (pas de tuning post-hoc ici).
    assert.ok(written.length > 0, `attendu >0 ligne backfillée réellement, got ${JSON.stringify(written)}`);
    for (const w of written) {
      assert.equal(w.record.subject.type, 'game', 'un run Forge archivé produit un JEU, jamais une brique promue');
    }
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('DEFAULT_* pointent bien vers le dépôt réel (EVIDENCE/runs, GAMES/)', () => {
  assert.ok(DEFAULT_RUNS_DIR.replace(/\\/g, '/').endsWith('EVIDENCE/runs'));
  assert.ok(DEFAULT_GAMES_DIR.replace(/\\/g, '/').endsWith('/games'));
});

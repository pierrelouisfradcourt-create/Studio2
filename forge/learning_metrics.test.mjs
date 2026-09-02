import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, rmSync, readFileSync, writeFileSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  buildRecord,
  recordLearning,
  normalizeSubject,
  SUBJECT_TYPES,
  DEFAULT_LEARNING_CURVE_PATH,
} from './learning_metrics.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const CLI_PATH = join(__dirname, 'learning_metrics.mjs');

// --- buildRecord : sujet typé subject:{type, id} (LEARNING_SUBJECT_MODEL_V1) -------
// brick_id devient un cas particulier de subject (type='brick'). La rétro-compat ne se
// fait PAS ici (côté écriture) : buildRecord écrit toujours le nouveau format. La lecture
// d'anciennes lignes {brick_id} est couverte par normalizeSubject (voir plus bas).

test('un enregistrement complet porte subject + les 3 metriques', () => {
  const r = buildRecord({ subject: { type: 'brick', id: 'sys-grid-nav-godot' }, reuse_ratio: 0, oracle_iterations: 2, joust_delta: null });
  assert.deepEqual(r.subject, { type: 'brick', id: 'sys-grid-nav-godot' });
  assert.equal(r.oracle_iterations, 2);
  assert.equal(r.no_comparison, true);
});

test('subject.type "game" -> accepte, sujet = {type:"game", id}', () => {
  const r = buildRecord({ subject: { type: 'game', id: 'shmup_slice' }, reuse_ratio: 0.333, oracle_iterations: 5, joust_delta: null });
  assert.deepEqual(r.subject, { type: 'game', id: 'shmup_slice' });
});

test('joust_delta present -> no_comparison false', () => {
  const r = buildRecord({ subject: { type: 'brick', id: 'x' }, reuse_ratio: 0.5, oracle_iterations: 1, joust_delta: 0.12 });
  assert.equal(r.no_comparison, false);
});

test('subject manquant -> erreur (pas de ligne anonyme dans la courbe)', () => {
  assert.throws(() => buildRecord({ reuse_ratio: 0, oracle_iterations: 1, joust_delta: null }), /subject/);
});

test('subject.type inconnu -> erreur explicite (enumeration contrainte, jamais un champ libre)', () => {
  assert.throws(
    () => buildRecord({ subject: { type: 'agent', id: 'x' }, reuse_ratio: 0, oracle_iterations: 1, joust_delta: null }),
    /subject\.type/,
  );
});

test('subject sans id -> erreur', () => {
  assert.throws(
    () => buildRecord({ subject: { type: 'brick' }, reuse_ratio: 0, oracle_iterations: 1, joust_delta: null }),
    /subject\.id/,
  );
});

test('subject.id vide -> erreur', () => {
  assert.throws(
    () => buildRecord({ subject: { type: 'brick', id: '' }, reuse_ratio: 0, oracle_iterations: 1, joust_delta: null }),
    /subject\.id/,
  );
});

test('subject non-objet (string) -> erreur', () => {
  assert.throws(
    () => buildRecord({ subject: 'sys-grid-nav-godot', reuse_ratio: 0, oracle_iterations: 1, joust_delta: null }),
    /subject/,
  );
});

test('oracle_iterations negatif -> erreur', () => {
  assert.throws(() => buildRecord({ subject: { type: 'brick', id: 'x' }, reuse_ratio: 0, oracle_iterations: -1, joust_delta: null }), /oracle_iterations/);
});

// --- SUBJECT_TYPES : énumération figée, jamais un champ libre ----------------------
test('SUBJECT_TYPES contient exactement brick et game', () => {
  assert.deepEqual([...SUBJECT_TYPES].sort(), ['brick', 'game']);
});

// --- normalizeSubject : rétro-compatibilité PAR NORMALISATION À LA LECTURE ---------
// Même patron que hook_guard.marker_key (marqueur 2-champs -> triplet avec attempt=0) et
// studio_link.premortem (entrées sans resolution/status) : le lecteur s'adapte, jamais
// une réécriture de la ligne historique.

test('normalizeSubject: entrée historique brick_id seul -> {type:"brick", id:<brick_id>}', () => {
  const historical = { brick_id: 'sys-grid-nav-m01', reuse_ratio: 0, oracle_iterations: 5, joust_delta: null, no_comparison: true, timestamp: '2026-07-21T00:00:00.000Z', note: 'saisie manuelle' };
  assert.deepEqual(normalizeSubject(historical), { type: 'brick', id: 'sys-grid-nav-m01' });
});

test('normalizeSubject: entrée subject complète -> pass-through validé', () => {
  const rec = { subject: { type: 'game', id: 'shmup_slice' }, reuse_ratio: 0.1, oracle_iterations: 6, joust_delta: null };
  assert.deepEqual(normalizeSubject(rec), { type: 'game', id: 'shmup_slice' });
});

test('normalizeSubject: subject.type inconnu -> refuse explicitement (jamais une coercion silencieuse)', () => {
  assert.throws(() => normalizeSubject({ subject: { type: 'agent', id: 'x' } }), /subject\.type/);
});

test('normalizeSubject: subject sans id -> erreur', () => {
  assert.throws(() => normalizeSubject({ subject: { type: 'brick' } }), /subject\.id/);
});

test('normalizeSubject: subject.id vide -> erreur', () => {
  assert.throws(() => normalizeSubject({ subject: { type: 'brick', id: '' } }), /subject\.id/);
});

test('normalizeSubject: brick_id vide -> erreur', () => {
  assert.throws(() => normalizeSubject({ brick_id: '' }), /brick_id/);
});

test('normalizeSubject: subject ET brick_id présents simultanément -> refuse (ambigu, anti-invention)', () => {
  // Règle décidée et documentée : on ne devine JAMAIS lequel des deux prime. Un
  // enregistrement porte l'un OU l'autre, jamais les deux -> rejet explicite.
  assert.throws(
    () => normalizeSubject({ subject: { type: 'brick', id: 'a' }, brick_id: 'b' }),
    /à la fois|ambigu/,
  );
});

test('normalizeSubject: ni subject ni brick_id -> erreur (sujet non identifiable)', () => {
  assert.throws(() => normalizeSubject({ reuse_ratio: 0 }), /subject|identifiable/);
});

test('normalizeSubject: record non-objet -> erreur', () => {
  assert.throws(() => normalizeSubject(null), /record/);
  assert.throws(() => normalizeSubject(undefined), /record/);
});

// --- recordLearning : chemin par défaut repo-relatif, indépendant du cwd -----------
test('DEFAULT_LEARNING_CURVE_PATH est un chemin absolu ancré sur le module, pas le cwd', () => {
  const expected = join(__dirname, '..', 'knowledge_base', 'learning_curve.jsonl');
  assert.equal(DEFAULT_LEARNING_CURVE_PATH, expected);
  assert.ok(DEFAULT_LEARNING_CURVE_PATH.endsWith('learning_curve.jsonl'));
});

test('DEFAULT_LEARNING_CURVE_PATH ne bouge pas quand le cwd change', () => {
  const before = DEFAULT_LEARNING_CURVE_PATH;
  const originalCwd = process.cwd();
  const elsewhere = mkdtempSync(join(tmpdir(), 'learning-metrics-cwd-'));
  try {
    process.chdir(elsewhere);
    assert.equal(DEFAULT_LEARNING_CURVE_PATH, before);
  } finally {
    process.chdir(originalCwd);
    rmSync(elsewhere, { recursive: true, force: true });
  }
});

// --- recordLearning : effet de bord, sur cible temporaire (jamais le vrai fichier) --
test('recordLearning ajoute une ligne JSON valide au fichier cible (append, pas d\'écrasement)', () => {
  const dir = mkdtempSync(join(tmpdir(), 'learning-metrics-record-'));
  const target = join(dir, 'sub', 'learning_curve.jsonl');
  try {
    const r1 = recordLearning(
      { subject: { type: 'brick', id: 'sys-fake-01' }, reuse_ratio: 0.25, oracle_iterations: 3, joust_delta: null },
      '2026-01-01T00:00:00.000Z',
      target,
    );
    const r2 = recordLearning(
      { subject: { type: 'game', id: 'sys-fake-02' }, reuse_ratio: 0.5, oracle_iterations: 1, joust_delta: 0.1 },
      '2026-01-02T00:00:00.000Z',
      target,
    );
    const lines = readFileSync(target, 'utf-8').trim().split('\n');
    assert.equal(lines.length, 2);
    const parsed = lines.map((l) => JSON.parse(l));
    assert.deepEqual(parsed[0].subject, { type: 'brick', id: 'sys-fake-01' });
    assert.deepEqual(parsed[1].subject, { type: 'game', id: 'sys-fake-02' });
    assert.deepEqual(parsed[0], r1);
    assert.deepEqual(parsed[1], r2);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

// --- CLI : point d'entrée en ligne de commande, sans dupliquer buildRecord/recordLearning ---
test('CLI "record" écrit un enregistrement valide dans --target', () => {
  const dir = mkdtempSync(join(tmpdir(), 'learning-metrics-cli-'));
  const target = join(dir, 'learning_curve.jsonl');
  try {
    const out = execFileSync('node', [
      CLI_PATH, 'record',
      '--subject-type', 'brick',
      '--subject-id', 'sys-fake-cli',
      '--reuse-ratio', '0.333',
      '--oracle-iterations', '4',
      '--timestamp', '2026-02-02T00:00:00.000Z',
      '--target', target,
    ], { encoding: 'utf-8' });
    const record = JSON.parse(out.trim().split('\n').pop());
    assert.deepEqual(record.subject, { type: 'brick', id: 'sys-fake-cli' });
    assert.equal(record.oracle_iterations, 4);
    assert.ok(Math.abs(record.reuse_ratio - 0.333) < 1e-9);
    assert.equal(record.no_comparison, true);
    const written = JSON.parse(readFileSync(target, 'utf-8').trim());
    assert.deepEqual(written, record);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('CLI "record" --subject-type game -> subject.type "game"', () => {
  const dir = mkdtempSync(join(tmpdir(), 'learning-metrics-cli-'));
  const target = join(dir, 'learning_curve.jsonl');
  try {
    const out = execFileSync('node', [
      CLI_PATH, 'record',
      '--subject-type', 'game',
      '--subject-id', 'shmup_slice',
      '--reuse-ratio', '0.1',
      '--oracle-iterations', '5',
      '--timestamp', '2026-02-02T00:00:00.000Z',
      '--target', target,
    ], { encoding: 'utf-8' });
    const record = JSON.parse(out.trim().split('\n').pop());
    assert.deepEqual(record.subject, { type: 'game', id: 'shmup_slice' });
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('CLI "record" avec --joust-delta -> no_comparison false', () => {
  const dir = mkdtempSync(join(tmpdir(), 'learning-metrics-cli-'));
  const target = join(dir, 'learning_curve.jsonl');
  try {
    const out = execFileSync('node', [
      CLI_PATH, 'record',
      '--subject-type', 'brick',
      '--subject-id', 'sys-fake-cli-2',
      '--reuse-ratio', '0',
      '--oracle-iterations', '1',
      '--joust-delta', '0.05',
      '--timestamp', '2026-02-03T00:00:00.000Z',
      '--target', target,
    ], { encoding: 'utf-8' });
    const record = JSON.parse(out.trim());
    assert.equal(record.no_comparison, false);
    assert.equal(record.joust_delta, 0.05);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('CLI "record" sans --subject-id -> échoue proprement (exit non-zéro), rien écrit', () => {
  const dir = mkdtempSync(join(tmpdir(), 'learning-metrics-cli-'));
  const target = join(dir, 'learning_curve.jsonl');
  try {
    assert.throws(() => execFileSync('node', [
      CLI_PATH, 'record',
      '--subject-type', 'brick',
      '--reuse-ratio', '0',
      '--oracle-iterations', '1',
      '--target', target,
    ], { encoding: 'utf-8', stdio: ['ignore', 'pipe', 'pipe'] }));
    assert.equal(existsSync(target), false);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('CLI "record" avec --subject-type inconnu -> échoue proprement, rien écrit', () => {
  const dir = mkdtempSync(join(tmpdir(), 'learning-metrics-cli-'));
  const target = join(dir, 'learning_curve.jsonl');
  try {
    assert.throws(() => execFileSync('node', [
      CLI_PATH, 'record',
      '--subject-type', 'agent',
      '--subject-id', 'x',
      '--reuse-ratio', '0',
      '--oracle-iterations', '1',
      '--target', target,
    ], { encoding: 'utf-8', stdio: ['ignore', 'pipe', 'pipe'] }));
    assert.equal(existsSync(target), false);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('CLI commande inconnue -> exit non-zéro, message utile', () => {
  assert.throws(() => execFileSync('node', [CLI_PATH, 'bogus'], { stdio: ['ignore', 'pipe', 'pipe'] }));
});

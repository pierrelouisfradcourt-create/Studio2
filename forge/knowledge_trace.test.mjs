// Tests de knowledge_trace.mjs — node --test. Fixtures ephemeres sous un faux repoRoot
// (meme discipline que declaration_readers.test.mjs) : le vrai repo peut bouger, ces tests non.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, existsSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import {
  validateTraceItems,
  writeTrace,
  verifyTrace,
  ALLOWED_SOURCES,
  ALLOWED_PROVENANCE,
  SCHEMA_VERSION,
} from './knowledge_trace.mjs';

function fakeRepo() {
  const root = mkdtempSync(join(tmpdir(), 'ktrace-'));
  return root;
}
function makeRun(root, runId) {
  const runDir = join(root, 'EVIDENCE', 'runs', runId);
  mkdirSync(join(runDir, 'artifacts'), { recursive: true });
  mkdirSync(join(runDir, 'evidence'), { recursive: true });
  return runDir;
}

const VALID_ITEM = {
  source: 'premortem',
  ref: 'premortem-item-42',
  provenance: 'VERIFIED',
  valid_as_of: '2026-07-20',
  reason: 'evite une erreur connue de placement UI',
};

// --- validateTraceItems -----------------------------------------------------------------

test('validateTraceItems: item valide passe', () => {
  const r = validateTraceItems([VALID_ITEM]);
  assert.equal(r.ok, true);
  assert.deepEqual(r.errors, []);
});

test('validateTraceItems: tableau vide est valide (0 erreurs)', () => {
  const r = validateTraceItems([]);
  assert.equal(r.ok, true);
});

test('validateTraceItems: items non-tableau refuse', () => {
  const r = validateTraceItems({ not: 'an array' });
  assert.equal(r.ok, false);
  assert.ok(r.errors.length >= 1);
});

test('validateTraceItems: champ manquant refuse et nomme le champ', () => {
  const { reason, ...missingReason } = VALID_ITEM;
  const r = validateTraceItems([missingReason]);
  assert.equal(r.ok, false);
  assert.ok(r.errors.some((e) => e.includes('reason')));
});

test('validateTraceItems: source hors enum refuse', () => {
  const r = validateTraceItems([{ ...VALID_ITEM, source: 'wikipedia' }]);
  assert.equal(r.ok, false);
  assert.ok(r.errors.some((e) => e.includes('source')));
});

test('validateTraceItems: provenance hors enum refuse', () => {
  const r = validateTraceItems([{ ...VALID_ITEM, provenance: 'MAYBE' }]);
  assert.equal(r.ok, false);
  assert.ok(r.errors.some((e) => e.includes('provenance')));
});

test('validateTraceItems: valid_as_of non-date refuse', () => {
  const r = validateTraceItems([{ ...VALID_ITEM, valid_as_of: 'pas une date' }]);
  assert.equal(r.ok, false);
  assert.ok(r.errors.some((e) => e.includes('valid_as_of')));
});

test('validateTraceItems: ref vide refuse', () => {
  const r = validateTraceItems([{ ...VALID_ITEM, ref: '' }]);
  assert.equal(r.ok, false);
});

test('ALLOWED_SOURCES et ALLOWED_PROVENANCE couvrent le schema du contrat', () => {
  assert.deepEqual(ALLOWED_SOURCES, ['premortem', 'knowledge_base', 'mandatory_read', 'packet']);
  assert.deepEqual(ALLOWED_PROVENANCE, ['VERIFIED', 'HUMAN_RATIFIED', 'ADVISORY', 'DERIVED', 'DOCTRINE']);
  assert.equal(SCHEMA_VERSION, 1);
});

// --- writeTrace ---------------------------------------------------------------------------

test('writeTrace: ecrit knowledge_trace.json avec en-tete correct dans un run valide', () => {
  const root = fakeRepo();
  const runDir = makeRun(root, 'testrun-1');
  const r = writeTrace(root, join('EVIDENCE', 'runs', 'testrun-1'), [VALID_ITEM]);
  assert.equal(r.written, true);
  assert.ok(existsSync(r.path));
  const content = JSON.parse(readFileSync(r.path, 'utf-8'));
  assert.equal(content.run_id, 'testrun-1');
  assert.equal(content.schema_version, 1);
  assert.ok(content.created);
  assert.equal(content.items.length, 1);
});

test('writeTrace: accepte un run_id explicite different du nom de dossier', () => {
  const root = fakeRepo();
  makeRun(root, 'testrun-2');
  const r = writeTrace(root, join('EVIDENCE', 'runs', 'testrun-2'), [VALID_ITEM], { runId: 'override-id' });
  const content = JSON.parse(readFileSync(r.path, 'utf-8'));
  assert.equal(content.run_id, 'override-id');
});

test('writeTrace: schema invalide -> rien n\'est ecrit', () => {
  const root = fakeRepo();
  const runDir = makeRun(root, 'testrun-3');
  const r = writeTrace(root, join('EVIDENCE', 'runs', 'testrun-3'), [{ ...VALID_ITEM, source: 'bogus' }]);
  assert.equal(r.written, false);
  assert.ok(r.errors.length > 0);
  assert.equal(existsSync(join(runDir, 'knowledge_trace.json')), false);
});

test('writeTrace: refuse d\'ecrire hors de EVIDENCE/runs/ meme sur demande explicite', () => {
  const root = fakeRepo();
  mkdirSync(join(root, 'knowledge_base'), { recursive: true });
  const r = writeTrace(root, join('knowledge_base'), [VALID_ITEM]);
  assert.equal(r.written, false);
  assert.equal(r.path, null);
  assert.ok(r.errors[0].includes('hors zone autorisée'));
});

test('writeTrace: refuse un run_dir inexistant plutot que de le creer', () => {
  const root = fakeRepo();
  const r = writeTrace(root, join('EVIDENCE', 'runs', 'never-created'), [VALID_ITEM]);
  assert.equal(r.written, false);
  assert.ok(r.errors[0].includes('introuvable'));
});

// --- verifyTrace ----------------------------------------------------------------------------

test('verifyTrace: trace absente -> status TRACE_ABSENT, ok false', () => {
  const root = fakeRepo();
  makeRun(root, 'testrun-4');
  const r = verifyTrace(root, join('EVIDENCE', 'runs', 'testrun-4'));
  assert.equal(r.status, 'TRACE_ABSENT');
  assert.equal(r.ok, false);
});

test('verifyTrace: run_dir absent -> status distinct RUN_DIR_ABSENT', () => {
  const root = fakeRepo();
  const r = verifyTrace(root, join('EVIDENCE', 'runs', 'never-existed'));
  assert.equal(r.status, 'RUN_DIR_ABSENT');
  assert.equal(r.ok, false);
});

test('verifyTrace: item reellement cite dans un artefact -> FOUND, ok true (cas honnete)', () => {
  const root = fakeRepo();
  const runDir = makeRun(root, 'testrun-5');
  writeFileSync(join(runDir, 'artifacts', 's3-decompo.txt'), 'Contexte utilise : premortem-item-42 evite le piege connu.\n', 'utf-8');
  const w = writeTrace(root, join('EVIDENCE', 'runs', 'testrun-5'), [VALID_ITEM]);
  assert.equal(w.written, true);
  const r = verifyTrace(root, join('EVIDENCE', 'runs', 'testrun-5'));
  assert.equal(r.status, 'VERIFIED');
  assert.equal(r.ok, true);
  assert.equal(r.items[0].status, 'FOUND');
  assert.ok(r.items[0].found_in[0].includes('s3-decompo.txt'));
});

test('verifyTrace: item theatral (jamais cite nulle part) -> NOT_FOUND, ok false (anti-theatre)', () => {
  const root = fakeRepo();
  const runDir = makeRun(root, 'testrun-6');
  writeFileSync(join(runDir, 'artifacts', 's3-decompo.txt'), 'Rien a voir avec la trace.\n', 'utf-8');
  const theatrical = { ...VALID_ITEM, ref: 'ref-jamais-consommee-XYZ' };
  const w = writeTrace(root, join('EVIDENCE', 'runs', 'testrun-6'), [theatrical]);
  assert.equal(w.written, true);
  const r = verifyTrace(root, join('EVIDENCE', 'runs', 'testrun-6'));
  assert.equal(r.status, 'VERIFIED');
  assert.equal(r.ok, false);
  assert.equal(r.items[0].status, 'NOT_FOUND');
});

test('verifyTrace: trace corrompue (JSON invalide) -> status TRACE_CORRUPT', () => {
  const root = fakeRepo();
  const runDir = makeRun(root, 'testrun-7');
  writeFileSync(join(runDir, 'knowledge_trace.json'), '{ not valid json', 'utf-8');
  const r = verifyTrace(root, join('EVIDENCE', 'runs', 'testrun-7'));
  assert.equal(r.status, 'TRACE_CORRUPT');
  assert.equal(r.ok, false);
});

test('verifyTrace: ne se cite pas elle-meme comme preuve (le fichier trace est exclu du corpus)', () => {
  const root = fakeRepo();
  const runDir = makeRun(root, 'testrun-8');
  const selfRef = { ...VALID_ITEM, ref: 'ref-uniquement-dans-la-trace' };
  const w = writeTrace(root, join('EVIDENCE', 'runs', 'testrun-8'), [selfRef]);
  assert.equal(w.written, true);
  const r = verifyTrace(root, join('EVIDENCE', 'runs', 'testrun-8'));
  assert.equal(r.items[0].status, 'NOT_FOUND');
});

test('verifyTrace: mentions dans state.json/verdict.json a la racine du run comptent', () => {
  const root = fakeRepo();
  const runDir = makeRun(root, 'testrun-9');
  writeFileSync(join(runDir, 'state.json'), JSON.stringify({ notes: 'brique-kb-import-shield' }), 'utf-8');
  const kbItem = { ...VALID_ITEM, source: 'knowledge_base', ref: 'brique-kb-import-shield' };
  writeTrace(root, join('EVIDENCE', 'runs', 'testrun-9'), [kbItem]);
  const r = verifyTrace(root, join('EVIDENCE', 'runs', 'testrun-9'));
  assert.equal(r.items[0].status, 'FOUND');
  assert.ok(r.items[0].found_in[0].includes('state.json'));
});

// --- CLI (spawn reel du script) --------------------------------------------------------------

test('CLI: write puis --verify sur fixture honnete -> exit 0/0', () => {
  const root = fakeRepo();
  const runDir = makeRun(root, 'cli-run-1');
  writeFileSync(join(runDir, 'artifacts', 's1.txt'), 'utilise premortem-item-42 pour eviter le piege', 'utf-8');
  const itemsPath = join(root, 'items.json');
  writeFileSync(itemsPath, JSON.stringify([VALID_ITEM]), 'utf-8');

  const scriptPath = join(process.cwd(), 'scripts', 'forge', 'knowledge_trace.mjs');
  const w = spawnSync(process.execPath, [scriptPath, 'write', join('EVIDENCE', 'runs', 'cli-run-1'), itemsPath, '--repo-root', root], { encoding: 'utf-8' });
  assert.equal(w.status, 0, w.stderr);

  const v = spawnSync(process.execPath, [scriptPath, '--verify', join('EVIDENCE', 'runs', 'cli-run-1'), '--repo-root', root], { encoding: 'utf-8' });
  assert.equal(v.status, 0, v.stderr);
});

test('CLI: --verify sur fixture theatrale -> exit 1', () => {
  const root = fakeRepo();
  const runDir = makeRun(root, 'cli-run-2');
  writeFileSync(join(runDir, 'artifacts', 's1.txt'), 'aucun rapport avec quoi que ce soit', 'utf-8');
  const itemsPath = join(root, 'items.json');
  writeFileSync(itemsPath, JSON.stringify([{ ...VALID_ITEM, ref: 'jamais-vu-nulle-part' }]), 'utf-8');

  const scriptPath = join(process.cwd(), 'scripts', 'forge', 'knowledge_trace.mjs');
  spawnSync(process.execPath, [scriptPath, 'write', join('EVIDENCE', 'runs', 'cli-run-2'), itemsPath, '--repo-root', root], { encoding: 'utf-8' });
  const v = spawnSync(process.execPath, [scriptPath, '--verify', join('EVIDENCE', 'runs', 'cli-run-2'), '--repo-root', root], { encoding: 'utf-8' });
  assert.equal(v.status, 1, v.stderr);
});

test('CLI: --verify sur trace absente -> exit 3', () => {
  const root = fakeRepo();
  makeRun(root, 'cli-run-3');
  const scriptPath = join(process.cwd(), 'scripts', 'forge', 'knowledge_trace.mjs');
  const v = spawnSync(process.execPath, [scriptPath, '--verify', join('EVIDENCE', 'runs', 'cli-run-3'), '--repo-root', root], { encoding: 'utf-8' });
  assert.equal(v.status, 3, v.stderr);
});

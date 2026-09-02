// Tests de pending_review.mjs — node --test. Fixtures ephemeres sous un faux repoRoot,
// meme discipline que les autres capteurs Forge : le repo reel peut bouger, ces tests non.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { loadQueueFile, normalizeItem, aggregate, QUEUE_FILES } from './pending_review.mjs';

function fakeRepo() {
  const root = mkdtempSync(join(tmpdir(), 'pendrev-'));
  mkdirSync(join(root, 'EVIDENCE', 'reports'), { recursive: true });
  return root;
}
function writeJsonl(root, relPath, lines) {
  const full = join(root, relPath);
  mkdirSync(join(full, '..'), { recursive: true });
  writeFileSync(full, lines.join('\n') + '\n', 'utf-8');
}

const LEDGER_CFG = QUEUE_FILES.find((f) => f.id === 'forge_ledger_proposals');
const ERROR_CFG = QUEUE_FILES.find((f) => f.id === 'error_proposals');
const BRICK_CFG = QUEUE_FILES.find((f) => f.id === 'forge_brick_proposals');

// --- loadQueueFile ------------------------------------------------------------------------

test('loadQueueFile: fichier absent -> status ABSENT, jamais fatal', () => {
  const root = fakeRepo();
  const r = loadQueueFile(root, LEDGER_CFG);
  assert.equal(r.status, 'ABSENT');
  assert.deepEqual(r.raw_items, []);
});

test('loadQueueFile: fichier vide -> status OK, 0 items', () => {
  const root = fakeRepo();
  writeJsonl(root, LEDGER_CFG.path, ['']);
  const r = loadQueueFile(root, LEDGER_CFG);
  assert.equal(r.status, 'OK');
  assert.equal(r.raw_items.length, 0);
});

test('loadQueueFile: ligne JSONL corrompue -> comptee ignoree, pas de crash, autres lignes lues', () => {
  const root = fakeRepo();
  writeJsonl(root, LEDGER_CFG.path, [
    JSON.stringify({ project: 'a', ts: 1000 }),
    '{ceci n est pas du json',
    JSON.stringify({ project: 'b', ts: 2000 }),
  ]);
  const r = loadQueueFile(root, LEDGER_CFG);
  assert.equal(r.status, 'OK');
  assert.equal(r.raw_items.length, 2);
  assert.equal(r.ignored_lines, 1);
});

test('loadQueueFile: ligne JSON valide mais pas un objet (ex. tableau/nombre) -> ignoree', () => {
  const root = fakeRepo();
  writeJsonl(root, LEDGER_CFG.path, [
    JSON.stringify([1, 2, 3]),
    JSON.stringify('juste une string'),
    JSON.stringify({ project: 'ok', ts: 1000 }),
  ]);
  const r = loadQueueFile(root, LEDGER_CFG);
  assert.equal(r.raw_items.length, 1);
  assert.equal(r.ignored_lines, 2);
});

test('loadQueueFile: CRLF ne casse rien', () => {
  const root = fakeRepo();
  const full = join(root, LEDGER_CFG.path);
  mkdirSync(join(full, '..'), { recursive: true });
  writeFileSync(full, `${JSON.stringify({ project: 'a', ts: 1000 })}\r\n${JSON.stringify({ project: 'b', ts: 2000 })}\r\n`, 'utf-8');
  const r = loadQueueFile(root, LEDGER_CFG);
  assert.equal(r.raw_items.length, 2);
});

// --- normalizeItem --------------------------------------------------------------------------

test('normalizeItem: calcule age_days a partir du champ ts documente', () => {
  const now = 1000 + 10 * 86400; // 10 jours plus tard
  const item = normalizeItem(LEDGER_CFG, { project: 'p1', ts: 1000 }, now);
  assert.equal(item.age_days, 10);
  assert.equal(item.subject_key, 'p1');
  assert.equal(item.key_fallback, false);
});

test('normalizeItem: champ cle sujet absent -> repli documente, jamais de crash', () => {
  const item = normalizeItem(LEDGER_CFG, { ts: 1000 }, 2000);
  assert.equal(item.key_fallback, true);
  assert.ok(item.subject_key.startsWith('__no_subject_field__:'));
});

test('normalizeItem: ts absent ou non-numerique -> age_days null, pas de NaN qui fuit', () => {
  const item = normalizeItem(LEDGER_CFG, { project: 'p1' }, 2000);
  assert.equal(item.age_days, null);
  assert.equal(item.ts_field_present, false);
});

test('normalizeItem: error_proposals utilise error_signature et created_ts', () => {
  const item = normalizeItem(ERROR_CFG, { error_signature: 'abc123', created_ts: 1000, title: 'boom' }, 1000 + 86400);
  assert.equal(item.subject_key, 'abc123');
  assert.equal(item.age_days, 1);
  assert.equal(item.label, 'boom');
});

test('normalizeItem: colonne decision toujours null (l\'outil ne stocke jamais de decision)', () => {
  const item = normalizeItem(LEDGER_CFG, { project: 'p1', ts: 1000 }, 2000);
  assert.equal(item.decision, null);
});

// --- aggregate : occurrences + tri deterministe ---------------------------------------------

test('aggregate: occurrences comptees par (source_file, subject_key), intra-fichier', () => {
  const root = fakeRepo();
  writeJsonl(root, LEDGER_CFG.path, [
    JSON.stringify({ project: 'auto_battler', run_id: 'r1', ts: 1000 }),
    JSON.stringify({ project: 'auto_battler', run_id: 'r2', ts: 2000 }),
    JSON.stringify({ project: 'shmup_slice', run_id: 'r3', ts: 3000 }),
  ]);
  const r = aggregate(root, 100000);
  const abItems = r.ranked.filter((it) => it.subject_key === 'auto_battler');
  assert.equal(abItems.length, 2);
  assert.equal(abItems[0].occurrences, 2);
  const shmupItem = r.ranked.find((it) => it.subject_key === 'shmup_slice');
  assert.equal(shmupItem.occurrences, 1);
});

test('aggregate: meme sujet dans 2 fichiers differents NE fusionne PAS (dedup intra-fichier uniquement)', () => {
  const root = fakeRepo();
  writeJsonl(root, LEDGER_CFG.path, [JSON.stringify({ project: 'auto_battler', ts: 1000 })]);
  writeJsonl(root, QUEUE_FILES.find((f) => f.id === 'forge_project_proposals').path, [JSON.stringify({ project: 'auto_battler', ts: 1000 })]);
  const r = aggregate(root, 100000);
  const items = r.ranked.filter((it) => it.subject_key === 'auto_battler');
  assert.equal(items.length, 2);
  assert.ok(items.every((it) => it.occurrences === 1));
});

test('aggregate: tri = occurrences desc puis age desc, deterministe et documente', () => {
  const root = fakeRepo();
  writeJsonl(root, LEDGER_CFG.path, [
    JSON.stringify({ project: 'low_occ_old', ts: 100 }),      // occ=1, tres vieux
    JSON.stringify({ project: 'high_occ', ts: 5000 }),
    JSON.stringify({ project: 'high_occ', ts: 6000 }),        // occ=2
  ]);
  const r = aggregate(root, 100000);
  assert.equal(r.ranked[0].subject_key, 'high_occ');
  assert.equal(r.ranked[1].subject_key, 'high_occ');
  assert.equal(r.ranked[2].subject_key, 'low_occ_old');
});

test('aggregate: total_items reste exact meme au-dela du plafond d\'affichage', () => {
  const root = fakeRepo();
  const lines = [];
  for (let i = 0; i < 12; i += 1) lines.push(JSON.stringify({ project: `p${i}`, ts: 1000 }));
  writeJsonl(root, LEDGER_CFG.path, lines);
  const r = aggregate(root, 100000);
  assert.equal(r.total_items, 12);
});

test('aggregate: fichier absent + fichier present cohabitent sans erreur fatale', () => {
  const root = fakeRepo();
  writeJsonl(root, LEDGER_CFG.path, [JSON.stringify({ project: 'a', ts: 1000 })]);
  const r = aggregate(root, 100000);
  const absentSource = r.sources.find((s) => s.id === 'forge_project_proposals');
  assert.equal(absentSource.status, 'ABSENT');
  assert.equal(r.total_items, 1);
});

// --- forge_brick_proposals (le dépositaire, 5e file) -----------------------------------------

test('QUEUE_FILES: forge_brick_proposals est bien la 5e file, cle sujet brick_id', () => {
  assert.ok(BRICK_CFG, 'forge_brick_proposals doit etre dans QUEUE_FILES');
  assert.equal(BRICK_CFG.subject_field, 'brick_id');
  assert.equal(BRICK_CFG.ts_field, 'ts');
});

test('forge_brick_proposals: lu par aggregate, brick_id distinct compte comme sujet distinct meme projet identique', () => {
  const root = fakeRepo();
  writeJsonl(root, BRICK_CFG.path, [
    JSON.stringify({ type: 'brick', brick_id: 'sys-a', project: 'shmup_slice', run_id: 'r1', kind: 'system', function: 'f', path: 'GAMES/shmup_slice/logic/a.mjs', ts: 1000 }),
    JSON.stringify({ type: 'brick', brick_id: 'sys-b', project: 'shmup_slice', run_id: 'r2', kind: 'system', function: 'g', path: 'GAMES/shmup_slice/logic/b.mjs', ts: 2000 }),
  ]);
  const r = aggregate(root, 100000);
  assert.equal(r.total_items, 2);
  const items = r.ranked.filter((it) => it.source_file === 'forge_brick_proposals');
  assert.equal(items.length, 2);
  // memes projet, brick_id different -> deux sujets distincts, occurrences=1 chacun
  assert.ok(items.every((it) => it.occurrences === 1));
  const a = items.find((it) => it.subject_key === 'sys-a');
  assert.equal(a.fields.path, 'GAMES/shmup_slice/logic/a.mjs');
  assert.equal(a.fields.project, 'shmup_slice');
});

test('fichier absent: forge_brick_proposals absent ne casse pas aggregate (statut ABSENT)', () => {
  const root = fakeRepo();
  const r = aggregate(root, 100000);
  const absentSource = r.sources.find((s) => s.id === 'forge_brick_proposals');
  assert.equal(absentSource.status, 'ABSENT');
});

// --- CLI (spawn reel du script) ---------------------------------------------------------------

test('CLI: exit 0 meme quand les 3 files sont absentes', () => {
  const root = fakeRepo();
  const scriptPath = join(process.cwd(), 'scripts', 'forge', 'pending_review.mjs');
  const r = spawnSync(process.execPath, [scriptPath, '--repo-root', root], { encoding: 'utf-8' });
  assert.equal(r.status, 0, r.stderr);
  const json = JSON.parse(r.stdout);
  assert.equal(json.total_items, 0);
  assert.ok(json.sources.every((s) => s.status === 'ABSENT'));
});

test('CLI: sortie stdout est un JSON valide avec total_items et displayed plafonne', () => {
  const root = fakeRepo();
  const lines = [];
  for (let i = 0; i < 8; i += 1) lines.push(JSON.stringify({ project: `p${i}`, ts: 1000 }));
  writeJsonl(root, LEDGER_CFG.path, lines);
  const scriptPath = join(process.cwd(), 'scripts', 'forge', 'pending_review.mjs');
  const r = spawnSync(process.execPath, [scriptPath, '--repo-root', root], { encoding: 'utf-8' });
  assert.equal(r.status, 0, r.stderr);
  const json = JSON.parse(r.stdout);
  assert.equal(json.total_items, 8);
  assert.equal(json.displayed_count, 5);
  assert.equal(json.displayed.length, 5);
});

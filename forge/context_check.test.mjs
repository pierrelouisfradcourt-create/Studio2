// Tests de context_check.mjs — node --test. Fixtures ephemeres sous un faux repoRoot,
// meme discipline que les autres capteurs Forge (pending_review.test.mjs) : jamais les
// vrais fichiers du repo, jamais git write.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { execFileSync, spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import {
  checkEtape,
  checkProject,
  diffSources,
  computeScore,
  computeSignals,
  toEpochMs,
  loadManifest,
} from './context_check.mjs';

function fakeRepo() {
  const root = mkdtempSync(join(tmpdir(), 'ctxcheck-'));
  return root;
}

function writeManifest(root, project, etape, lines) {
  const dir = join(root, 'EVIDENCE', 'runs', project, 'context');
  mkdirSync(dir, { recursive: true });
  writeFileSync(join(dir, `${etape}.manifest.jsonl`), lines.map((l) => JSON.stringify(l)).join('\n') + '\n', 'utf-8');
}

function writeSourceFile(root, relPath, content) {
  const full = join(root, relPath);
  mkdirSync(join(full, '..'), { recursive: true });
  writeFileSync(full, content, 'utf-8');
}

function sha256Of(content) {
  return createHash('sha256').update(content).digest('hex');
}

function initGitRepo(root) {
  execFileSync('git', ['init', '-q'], { cwd: root });
  execFileSync('git', ['config', 'user.email', 'test@example.com'], { cwd: root });
  execFileSync('git', ['config', 'user.name', 'Test'], { cwd: root });
}

function gitCommit(root, msg) {
  execFileSync('git', ['add', '-A'], { cwd: root });
  execFileSync('git', ['commit', '-q', '-m', msg, '--allow-empty'], { cwd: root });
  return execFileSync('git', ['rev-parse', 'HEAD'], { cwd: root, encoding: 'utf-8' }).trim();
}

const nowSeconds = () => Date.now() / 1000;

// --- toEpochMs -----------------------------------------------------------------------------

test('toEpochMs: epoch secondes (convention Forge time.time()) -> ms', () => {
  assert.equal(toEpochMs(1000), 1000000);
});

test('toEpochMs: chaine ISO -> ms parseable', () => {
  const ms = toEpochMs('2026-07-20');
  assert.ok(typeof ms === 'number' && !Number.isNaN(ms));
});

test('toEpochMs: valeur non exploitable -> null, jamais NaN', () => {
  assert.equal(toEpochMs(undefined), null);
  assert.equal(toEpochMs(null), null);
  assert.equal(toEpochMs('n\'importe quoi'), null);
});

// --- loadManifest ----------------------------------------------------------------------------

test('loadManifest: fichier absent -> status ABSENT, jamais fatal', () => {
  const root = fakeRepo();
  const r = loadManifest(join(root, 'nope.manifest.jsonl'));
  assert.equal(r.status, 'ABSENT');
  assert.deepEqual(r.dispatches, []);
});

test('loadManifest: ligne corrompue toleree, comptee, autres lignes lues', () => {
  const root = fakeRepo();
  const path = join(root, 'm.manifest.jsonl');
  mkdirSync(root, { recursive: true });
  writeFileSync(path, [
    JSON.stringify({ schema: 'forge.context_manifest.v1', kind: 'dispatch', ts: 1000 }),
    '{ceci n est pas du json',
    JSON.stringify({ schema: 'forge.context_manifest.v1', kind: 'execution', ts: 2000 }),
  ].join('\n') + '\n', 'utf-8');
  const r = loadManifest(path);
  assert.equal(r.status, 'OK');
  assert.equal(r.dispatches.length, 1);
  assert.equal(r.executions.length, 1);
  assert.equal(r.ignored_lines, 1);
});

test('loadManifest: kind inconnu signale proprement, pas de crash', () => {
  const root = fakeRepo();
  const path = join(root, 'm.manifest.jsonl');
  mkdirSync(root, { recursive: true });
  writeFileSync(path, JSON.stringify({ kind: 'mystere', ts: 1 }) + '\n', 'utf-8');
  const r = loadManifest(path);
  assert.equal(r.status, 'OK');
  assert.equal(r.unknown_kind_lines, 1);
  assert.equal(r.dispatches.length, 0);
});

// --- diffSources -----------------------------------------------------------------------------

test('diffSources: source inchangee -> unchanged', () => {
  const root = fakeRepo();
  writeSourceFile(root, 'wiremap.json', 'contenu-A');
  const sha = createHash('sha256').update('contenu-A').digest('hex');
  const diffs = diffSources([{ path: 'wiremap.json', sha256: sha, exists: true, role: 'upstream' }], root);
  assert.equal(diffs[0].status, 'unchanged');
});

test('diffSources: source modifiee -> changed', () => {
  const root = fakeRepo();
  writeSourceFile(root, 'wiremap.json', 'contenu-B');
  const diffs = diffSources([{ path: 'wiremap.json', sha256: 'sha-perime', exists: true, role: 'upstream' }], root);
  assert.equal(diffs[0].status, 'changed');
});

test('diffSources: source supprimee -> removed', () => {
  const root = fakeRepo();
  const diffs = diffSources([{ path: 'disparu.json', sha256: 'abc', exists: true, role: 'contract' }], root);
  assert.equal(diffs[0].status, 'removed');
});

test('diffSources: source nouvellement presente (exists:false au manifest) -> added', () => {
  const root = fakeRepo();
  writeSourceFile(root, 'nouveau.json', 'contenu');
  const diffs = diffSources([{ path: 'nouveau.json', sha256: null, exists: false, role: 'upstream' }], root);
  assert.equal(diffs[0].status, 'added');
});

// --- computeScore ------------------------------------------------------------------------------

test('computeScore: rien de change -> FRESH', () => {
  const { score, causes } = computeScore({
    sourceDiffs: [{ path: 'a', role: 'upstream', status: 'unchanged' }],
    signals: { age_hours: 1, commits_since: 0, premortem_new_count: 0, decisions_new_count: 0 },
  });
  assert.equal(score, 'FRESH');
  assert.deepEqual(causes, []);
});

test('computeScore: source upstream changed -> REQUIRES_REFRESH', () => {
  const { score } = computeScore({
    sourceDiffs: [{ path: 'wiremap.json', role: 'upstream', status: 'changed' }],
    signals: { age_hours: 1, commits_since: 0, premortem_new_count: 0, decisions_new_count: 0 },
  });
  assert.equal(score, 'REQUIRES_REFRESH');
});

test('computeScore: source contract removed -> REQUIRES_REFRESH', () => {
  const { score } = computeScore({
    sourceDiffs: [{ path: 'contract.yaml', role: 'contract', status: 'removed' }],
    signals: { age_hours: 1, commits_since: 0, premortem_new_count: 0, decisions_new_count: 0 },
  });
  assert.equal(score, 'REQUIRES_REFRESH');
});

test('computeScore: source upstream added (absente au dispatch, presente maintenant) -> REQUIRES_REFRESH', () => {
  const { score, causes } = computeScore({
    sourceDiffs: [{ path: 'wiremap.json', role: 'upstream', status: 'added' }],
    signals: { age_hours: 1, commits_since: 0, premortem_new_count: 0, decisions_new_count: 0 },
  });
  assert.equal(score, 'REQUIRES_REFRESH');
  assert.ok(causes[0].includes('added'));
});

test('computeScore: source non-critique added -> STALE_CRITICAL', () => {
  const { score } = computeScore({
    sourceDiffs: [{ path: 'notes.md', role: 'mandatory_read', status: 'added' }],
    signals: { age_hours: 1, commits_since: 0, premortem_new_count: 0, decisions_new_count: 0 },
  });
  assert.equal(score, 'STALE_CRITICAL');
});

test('computeScore: nouvelle decision Pierre -> STALE_CRITICAL', () => {
  const { score, causes } = computeScore({
    sourceDiffs: [{ path: 'a', role: 'upstream', status: 'unchanged' }],
    signals: { age_hours: 1, commits_since: 0, premortem_new_count: 0, decisions_new_count: 2 },
  });
  assert.equal(score, 'STALE_CRITICAL');
  assert.ok(causes.some((c) => c.includes('décision')));
});

test('computeScore: source secondaire (role autre) changed -> STALE_CRITICAL', () => {
  const { score } = computeScore({
    sourceDiffs: [{ path: 'kb.json', role: 'kb', status: 'changed' }],
    signals: { age_hours: 1, commits_since: 0, premortem_new_count: 0, decisions_new_count: 0 },
  });
  assert.equal(score, 'STALE_CRITICAL');
});

test('computeScore: age > 72h -> STALE_WARNING', () => {
  const { score, causes } = computeScore({
    sourceDiffs: [],
    signals: { age_hours: 80, commits_since: 0, premortem_new_count: 0, decisions_new_count: 0 },
  });
  assert.equal(score, 'STALE_WARNING');
  assert.ok(causes.some((c) => c.includes('72')));
});

test('computeScore: commits_since > 0 -> STALE_WARNING', () => {
  const { score } = computeScore({
    sourceDiffs: [],
    signals: { age_hours: 1, commits_since: 3, premortem_new_count: 0, decisions_new_count: 0 },
  });
  assert.equal(score, 'STALE_WARNING');
});

test('computeScore: REQUIRES_REFRESH prioritaire sur STALE_CRITICAL/WARNING simultanes', () => {
  const { score } = computeScore({
    sourceDiffs: [{ path: 'wiremap.json', role: 'upstream', status: 'changed' }],
    signals: { age_hours: 200, commits_since: 5, premortem_new_count: 2, decisions_new_count: 3 },
  });
  assert.equal(score, 'REQUIRES_REFRESH');
});

// --- checkEtape (integration fixtures) ---------------------------------------------------------

test('checkEtape: manifest absent -> rapport propre, score NO_MANIFEST, exit propre', () => {
  const root = fakeRepo();
  const r = checkEtape(root, 'projet_x', 's9-build');
  assert.equal(r.manifest_status, 'ABSENT');
  assert.equal(r.score, 'NO_MANIFEST');
  assert.ok(r.recommendations.length > 0);
});

test('checkEtape: cas FRESH complet (source inchangee, pas de commit, pas de decision, age faible)', () => {
  const root = fakeRepo();
  writeSourceFile(root, 'contract.yaml', 'contenu-contrat');
  const sha = createHash('sha256').update('contenu-contrat').digest('hex');
  const dispatchTs = nowSeconds() - 60; // 1 minute
  writeManifest(root, 'proj', 's9-build', [
    {
      schema: 'forge.context_manifest.v1', kind: 'dispatch', run_id: 'proj-1', etape: 's9-build',
      activation: 1, ts: dispatchTs, git_head: null, model: 'sonnet', provider: 'anthropic',
      contract_sha256: 'x', payload_prompt_sha256: 'y',
      sources: [{ path: 'contract.yaml', sha256: sha, exists: true, role: 'contract' }],
      claim_verdict: 'NO_CLAIM_ALLOWED', hmac: 'deadbeef',
    },
  ]);
  const r = checkEtape(root, 'proj', 's9-build');
  assert.equal(r.manifest_status, 'OK');
  assert.equal(r.score, 'FRESH');
  assert.deepEqual(r.causes, []);
});

test('checkEtape: source upstream modifiee -> REQUIRES_REFRESH', () => {
  const root = fakeRepo();
  writeSourceFile(root, 'wiremap.json', 'contenu-neuf');
  const dispatchTs = nowSeconds() - 60;
  writeManifest(root, 'proj', 's9-build', [
    {
      schema: 'forge.context_manifest.v1', kind: 'dispatch', run_id: 'proj-1', etape: 's9-build',
      activation: 1, ts: dispatchTs, git_head: null, model: 'sonnet', provider: 'anthropic',
      contract_sha256: 'x', payload_prompt_sha256: 'y',
      sources: [{ path: 'wiremap.json', sha256: 'sha-perime-du-manifest', exists: true, role: 'upstream' }],
      claim_verdict: 'NO_CLAIM_ALLOWED', hmac: 'deadbeef',
    },
  ]);
  const r = checkEtape(root, 'proj', 's9-build');
  assert.equal(r.score, 'REQUIRES_REFRESH');
  assert.ok(r.causes.some((c) => c.includes('wiremap.json')));
});

test('checkEtape: nouvelle decision Pierre posterieure au dispatch -> STALE_CRITICAL', () => {
  const root = fakeRepo();
  const dispatchTs = nowSeconds() - 3600; // il y a 1h
  writeManifest(root, 'proj', 's9-build', [
    {
      schema: 'forge.context_manifest.v1', kind: 'dispatch', run_id: 'proj-1', etape: 's9-build',
      activation: 1, ts: dispatchTs, git_head: null, model: 'sonnet', provider: 'anthropic',
      contract_sha256: 'x', payload_prompt_sha256: 'y', sources: [],
      claim_verdict: 'NO_CLAIM_ALLOWED', hmac: 'deadbeef',
    },
  ]);
  // decision datee de demain (ISO date-only, format reel de pending_review_decisions.jsonl) :
  // garanti posterieur au dispatch d'il y a 1h quelle que soit l'heure UTC d'execution du test.
  const tomorrow = new Date(Date.now() + 24 * 3600 * 1000).toISOString().slice(0, 10);
  mkdirSync(join(root, 'EVIDENCE', 'reports'), { recursive: true });
  writeFileSync(join(root, 'EVIDENCE', 'reports', 'pending_review_decisions.jsonl'),
    JSON.stringify({ ts: tomorrow, decision: 'ACCEPT', item: 'x' }) + '\n', 'utf-8');
  const r = checkEtape(root, 'proj', 's9-build');
  assert.equal(r.score, 'STALE_CRITICAL');
  assert.equal(r.signals.decisions_new_count, 1);
});

test('checkEtape: age_hours > 72 -> STALE_WARNING', () => {
  const root = fakeRepo();
  const dispatchTs = nowSeconds() - (80 * 3600); // 80h
  writeManifest(root, 'proj', 's9-build', [
    {
      schema: 'forge.context_manifest.v1', kind: 'dispatch', run_id: 'proj-1', etape: 's9-build',
      activation: 1, ts: dispatchTs, git_head: null, model: 'sonnet', provider: 'anthropic',
      contract_sha256: 'x', payload_prompt_sha256: 'y', sources: [],
      claim_verdict: 'NO_CLAIM_ALLOWED', hmac: 'deadbeef',
    },
  ]);
  const r = checkEtape(root, 'proj', 's9-build');
  assert.equal(r.score, 'STALE_WARNING');
  assert.ok(r.signals.age_hours > 72);
});

test('checkEtape: ligne execution fournit le budget context', () => {
  const root = fakeRepo();
  const dispatchTs = nowSeconds() - 60;
  writeManifest(root, 'proj', 's6-context', [
    {
      schema: 'forge.context_manifest.v1', kind: 'dispatch', run_id: 'proj-1', etape: 's6-context',
      activation: 1, ts: dispatchTs, git_head: null, model: 'sonnet', provider: 'anthropic',
      contract_sha256: 'x', payload_prompt_sha256: 'y', sources: [],
      claim_verdict: 'NO_CLAIM_ALLOWED', hmac: 'deadbeef',
    },
    {
      schema: 'forge.context_manifest.v1', kind: 'execution', run_id: 'proj-1', etape: 's6-context',
      ts: dispatchTs + 5, final_prompt_sha256: 'z', final_prompt_chars: 12000,
      premortem_sha256: 'p',
      prompt_budget: { model_window_tokens: 200000, estimated_tokens: 3000, status: 'OK' },
      claim_verdict: 'NO_CLAIM_ALLOWED', hmac: 'deadbeef',
    },
  ]);
  const r = checkEtape(root, 'proj', 's6-context');
  assert.equal(r.budget.status, 'OK');
  assert.equal(r.budget.estimated_tokens, 3000);
});

test('extractBudget accepte le nom LEGACY context_budget (manifestes historiques, jamais réécrits)', () => {
  const root = fakeRepo();
  const dispatchTs = nowSeconds() - 60;
  writeManifest(root, 'proj', 's6-context', [
    {
      schema: 'forge.context_manifest.v1', kind: 'dispatch', run_id: 'proj-legacy', etape: 's6-context',
      activation: 1, ts: dispatchTs, git_head: null, model: 'sonnet', provider: 'anthropic',
      contract_sha256: 'x', payload_prompt_sha256: 'y', sources: [],
      claim_verdict: 'NO_CLAIM_ALLOWED', hmac: 'deadbeef',
    },
    {
      schema: 'forge.context_manifest.v1', kind: 'execution', run_id: 'proj-legacy', etape: 's6-context',
      ts: dispatchTs + 5, final_prompt_sha256: 'z', final_prompt_chars: 12000,
      premortem_sha256: 'p',
      context_budget: { model_window_tokens: 200000, estimated_tokens: 2600, status: 'OK' },
      claim_verdict: 'NO_CLAIM_ALLOWED', hmac: 'deadbeef',
    },
  ]);
  const r = checkEtape(root, 'proj', 's6-context');
  assert.equal(r.budget.status, 'OK');
  assert.equal(r.budget.estimated_tokens, 2600);
});

test('checkEtape: aucune ligne execution -> budget NO_EXECUTION_RECORD', () => {
  const root = fakeRepo();
  const dispatchTs = nowSeconds() - 60;
  writeManifest(root, 'proj', 's9-build', [
    {
      schema: 'forge.context_manifest.v1', kind: 'dispatch', run_id: 'proj-1', etape: 's9-build',
      activation: 1, ts: dispatchTs, git_head: null, model: 'sonnet', provider: 'anthropic',
      contract_sha256: 'x', payload_prompt_sha256: 'y', sources: [],
      claim_verdict: 'NO_CLAIM_ALLOWED', hmac: 'deadbeef',
    },
  ]);
  const r = checkEtape(root, 'proj', 's9-build');
  assert.equal(r.budget.status, 'NO_EXECUTION_RECORD');
});

test('checkEtape: commits_since via git_head reel (repo git jetable)', () => {
  const root = fakeRepo();
  initGitRepo(root);
  const head1 = gitCommit(root, 'commit initial');
  gitCommit(root, 'un autre commit');
  const dispatchTs = nowSeconds() - 60;
  writeManifest(root, 'proj', 's9-build', [
    {
      schema: 'forge.context_manifest.v1', kind: 'dispatch', run_id: 'proj-1', etape: 's9-build',
      activation: 1, ts: dispatchTs, git_head: head1, model: 'sonnet', provider: 'anthropic',
      contract_sha256: 'x', payload_prompt_sha256: 'y', sources: [],
      claim_verdict: 'NO_CLAIM_ALLOWED', hmac: 'deadbeef',
    },
  ]);
  const r = checkEtape(root, 'proj', 's9-build');
  assert.equal(r.signals.commits_since, 1);
  assert.equal(r.score, 'STALE_WARNING');
});

// --- checkProject ------------------------------------------------------------------------------

test('checkProject: dossier context/ absent -> liste vide, aucun crash', () => {
  const root = fakeRepo();
  const r = checkProject(root, 'inexistant');
  assert.equal(r.context_dir_exists, false);
  assert.deepEqual(r.etapes, []);
  assert.equal(r.claim_verdict, 'NO_CLAIM_ALLOWED');
});

test('checkProject: liste toutes les etapes ayant un manifest', () => {
  const root = fakeRepo();
  const ts = nowSeconds() - 60;
  for (const etape of ['s6-context', 's9-build']) {
    writeManifest(root, 'proj', etape, [
      {
        schema: 'forge.context_manifest.v1', kind: 'dispatch', run_id: 'proj-1', etape,
        activation: 1, ts, git_head: null, model: 'sonnet', provider: 'anthropic',
        contract_sha256: 'x', payload_prompt_sha256: 'y', sources: [],
        claim_verdict: 'NO_CLAIM_ALLOWED', hmac: 'deadbeef',
      },
    ]);
  }
  const r = checkProject(root, 'proj');
  const names = r.etapes.map((e) => e.etape).sort();
  assert.deepEqual(names, ['s6-context', 's9-build']);
});

test('checkProject: --etape cible uniquement l etape demandee', () => {
  const root = fakeRepo();
  const r = checkProject(root, 'proj', { etape: 's9-build' });
  assert.equal(r.etapes.length, 1);
  assert.equal(r.etapes[0].etape, 's9-build');
});

// --- CLI (spawn reel du script) ------------------------------------------------------------------

test('CLI: exit 0 meme quand le projet n a aucun manifest', () => {
  const scriptPath = join(process.cwd(), 'scripts', 'forge', 'context_check.mjs');
  const r = spawnSync(process.execPath, [scriptPath, 'projet-fantome-inexistant-xyz', '--json'], { encoding: 'utf-8' });
  assert.equal(r.status, 0, r.stderr);
  const json = JSON.parse(r.stdout);
  assert.equal(json.etapes.length, 0);
  assert.equal(json.claim_verdict, 'NO_CLAIM_ALLOWED');
});

test('CLI: --json produit un JSON parseable avec le score par etape', () => {
  // utilise le vrai repo (lecture seule) sur un projet reel qui n a probablement pas de
  // manifest V1.1 encore (shmup_slice) : verifie juste que la sortie reste propre.
  const scriptPath = join(process.cwd(), 'scripts', 'forge', 'context_check.mjs');
  const r = spawnSync(process.execPath, [scriptPath, 'shmup_slice', '--json'], { encoding: 'utf-8' });
  assert.equal(r.status, 0, r.stderr);
  const json = JSON.parse(r.stdout);
  assert.equal(json.project, 'shmup_slice');
  assert.ok(Array.isArray(json.etapes));
});

test('CLI: sans argument -> exit 0 (advisory, jamais de blocage meme sur usage incorrect)', () => {
  const scriptPath = join(process.cwd(), 'scripts', 'forge', 'context_check.mjs');
  const r = spawnSync(process.execPath, [scriptPath], { encoding: 'utf-8' });
  assert.equal(r.status, 0, r.stderr);
});

// Tests de wiremap_nav.mjs — node --test. Fixtures ephemeres sous un faux repoRoot, meme
// discipline que context_check.test.mjs : jamais les vrais fichiers du repo dans les tests
// unitaires (le repo reel n'est touche que par les tests CLI d'integration, en lecture seule).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { execFileSync, spawnSync } from 'node:child_process';
import {
  loadWiremap,
  loadWiremapFrozen,
  computeFrozenDrift,
  loadStateSteps,
  loadDispatchAudit,
  loadProjectDecisions,
  loadArtifacts,
  resolveGameFile,
  findFeaturesByQuery,
  findFeaturesByFileQuery,
  buildFeatureChain,
  buildOverview,
  runFeatureQuery,
  runFileQuery,
} from './wiremap_nav.mjs';

function fakeRepo() {
  return mkdtempSync(join(tmpdir(), 'wiremapnav-'));
}

function writeWiremap(root, project, obj) {
  const dir = join(root, 'EVIDENCE', 'runs', project);
  mkdirSync(dir, { recursive: true });
  writeFileSync(join(dir, 'wiremap.json'), JSON.stringify(obj), 'utf-8');
}

function writeWiremapFrozen(root, project, obj) {
  const dir = join(root, 'EVIDENCE', 'runs', project);
  mkdirSync(dir, { recursive: true });
  writeFileSync(join(dir, 'wiremap_frozen.json'), JSON.stringify(obj), 'utf-8');
}

function writeState(root, project, obj) {
  const dir = join(root, 'EVIDENCE', 'runs', project);
  mkdirSync(dir, { recursive: true });
  writeFileSync(join(dir, 'state.json'), JSON.stringify(obj), 'utf-8');
}

function writeDispatchAudit(root, lines) {
  const dir = join(root, 'EVIDENCE', 'bundles');
  mkdirSync(dir, { recursive: true });
  writeFileSync(join(dir, 'dispatch_audit.jsonl'), lines.map((l) => JSON.stringify(l)).join('\n') + '\n', 'utf-8');
}

function writeDecisions(root, lines) {
  const dir = join(root, 'EVIDENCE', 'reports');
  mkdirSync(dir, { recursive: true });
  writeFileSync(join(dir, 'pending_review_decisions.jsonl'), lines.map((l) => JSON.stringify(l)).join('\n') + '\n', 'utf-8');
}

function writeGameFile(root, project, relFichier, content) {
  const full = join(root, 'games', project, relFichier);
  mkdirSync(join(full, '..'), { recursive: true });
  writeFileSync(full, content, 'utf-8');
}

function writeArtifact(root, project, etape) {
  const dir = join(root, 'EVIDENCE', 'runs', project, 'artifacts');
  mkdirSync(dir, { recursive: true });
  writeFileSync(join(dir, `${etape}.txt`), 'rapport auto-declare', 'utf-8');
}

const sampleFeature = {
  feature: 'R1 test feature',
  fonction: 'doThing',
  fichiers: ['logic/thing.mjs'],
  version: 'v1',
  statut: 'fait',
  preuve: 'preuve texte',
};

// --- loadWiremap ---------------------------------------------------------------------------

test('loadWiremap: absent -> status ABSENT, features vide', () => {
  const root = fakeRepo();
  const r = loadWiremap(root, 'nope');
  assert.equal(r.status, 'ABSENT');
  assert.deepEqual(r.features, []);
});

test('loadWiremap: JSON corrompu tolere -> status CORRUPT, jamais de throw', () => {
  const root = fakeRepo();
  const dir = join(root, 'EVIDENCE', 'runs', 'broken');
  mkdirSync(dir, { recursive: true });
  writeFileSync(join(dir, 'wiremap.json'), '{ceci n est pas du json', 'utf-8');
  const r = loadWiremap(root, 'broken');
  assert.equal(r.status, 'CORRUPT');
  assert.deepEqual(r.features, []);
});

test('loadWiremap: schema shmup_slice (sans section) normalise correctement', () => {
  const root = fakeRepo();
  writeWiremap(root, 'proj', { _comment: 'x', features: [sampleFeature] });
  const r = loadWiremap(root, 'proj');
  assert.equal(r.status, 'OK');
  assert.equal(r.features.length, 1);
  assert.equal(r.features[0].feature, 'R1 test feature');
  assert.equal(r.features[0].section, null);
});

test('loadWiremap: schema card_engine (avec section + statut construit) tolere', () => {
  const root = fakeRepo();
  writeWiremap(root, 'proj', {
    run_id: 'proj-1', etape: 's5-wiremap',
    features: [{ feature: 'core_x', section: 'GAMES/proj/core/x.mjs', fichiers: ['core/x.mjs'], fonction: 'makeX', version: '0.1.0', preuve: 'p', statut: 'construit' }],
  });
  const r = loadWiremap(root, 'proj');
  assert.equal(r.status, 'OK');
  assert.equal(r.features[0].section, 'GAMES/proj/core/x.mjs');
  assert.equal(r.features[0].statut, 'construit');
  assert.equal(r.run_id, 'proj-1');
});

// --- loadWiremapFrozen + computeFrozenDrift --------------------------------------------------

test('loadWiremapFrozen: absent -> status ABSENT', () => {
  const root = fakeRepo();
  const r = loadWiremapFrozen(root, 'nope');
  assert.equal(r.status, 'ABSENT');
});

test('computeFrozenDrift: wiremap et frozen identiques -> non divergent', () => {
  const features = [{ feature: 'A' }, { feature: 'B' }];
  const frozen = { status: 'OK', names: ['A', 'B'] };
  const d = computeFrozenDrift(features, frozen);
  assert.equal(d.divergent, false);
});

test('computeFrozenDrift: feature ajoutee depuis le gel -> divergent, added_since_freeze', () => {
  const features = [{ feature: 'A' }, { feature: 'B' }, { feature: 'C' }];
  const frozen = { status: 'OK', names: ['A', 'B'] };
  const d = computeFrozenDrift(features, frozen);
  assert.equal(d.divergent, true);
  assert.deepEqual(d.added_since_freeze, ['C']);
  assert.deepEqual(d.missing_since_freeze, []);
});

test('computeFrozenDrift: feature gelee disparue -> divergent, missing_since_freeze', () => {
  const features = [{ feature: 'A' }];
  const frozen = { status: 'OK', names: ['A', 'B'] };
  const d = computeFrozenDrift(features, frozen);
  assert.equal(d.divergent, true);
  assert.deepEqual(d.missing_since_freeze, ['B']);
});

test('computeFrozenDrift: frozen absent -> checked false, jamais un crash', () => {
  const d = computeFrozenDrift([{ feature: 'A' }], { status: 'ABSENT' });
  assert.equal(d.checked, false);
  assert.equal(d.divergent, false);
});

// --- loadStateSteps -------------------------------------------------------------------------

test('loadStateSteps: absent (run prose type card_engine) -> status ABSENT, jamais fatal', () => {
  const root = fakeRepo();
  const r = loadStateSteps(root, 'prose_project');
  assert.equal(r.status, 'ABSENT');
  assert.deepEqual(r.steps, []);
});

test('loadStateSteps: steps extraits et tries par ts, model depuis detail', () => {
  const root = fakeRepo();
  writeState(root, 'proj', {
    run_id: 'proj-1', run_status: 'DONE',
    steps: {
      's9-build': { attempts: 1, status: 'OK', ts: 200, detail: { model: 'claude-opus', reviewer: 'claude-opus' } },
      's0-contrat': { attempts: 1, status: 'OK', ts: 100, detail: { model: 'claude-opus' } },
      's10a-oracle-code': { attempts: 5, status: 'OK', ts: 150, detail: { passed: true } },
    },
  });
  const r = loadStateSteps(root, 'proj');
  assert.equal(r.status, 'OK');
  assert.equal(r.steps.length, 3);
  assert.deepEqual(r.steps.map((s) => s.etape), ['s0-contrat', 's10a-oracle-code', 's9-build']);
  assert.equal(r.steps[1].model, null);
  assert.equal(r.steps[1].is_oracle_step, true);
  assert.equal(r.steps[2].model, 'claude-opus');
});

test('loadStateSteps: JSON corrompu -> CORRUPT, jamais de throw', () => {
  const root = fakeRepo();
  const dir = join(root, 'EVIDENCE', 'runs', 'broken');
  mkdirSync(dir, { recursive: true });
  writeFileSync(join(dir, 'state.json'), '{not json', 'utf-8');
  const r = loadStateSteps(root, 'broken');
  assert.equal(r.status, 'CORRUPT');
});

// --- loadDispatchAudit -----------------------------------------------------------------------

test('loadDispatchAudit: filtre par run_id.startsWith(project)', () => {
  const root = fakeRepo();
  writeDispatchAudit(root, [
    { etape: 's0-contrat', model: 'opus', capability_role: 'contract_author', run_id: 'shmup_slice-1', ts: 1 },
    { etape: 's0-contrat', model: 'opus', capability_role: 'contract_author', run_id: 'card_engine-1', ts: 2 },
    { etape: 's9-build', model: 'haiku', capability_role: 'builder', run_id: 'shmup_slice-1', ts: 3 },
  ]);
  const r = loadDispatchAudit(root, 'shmup_slice');
  assert.equal(r.status, 'OK');
  assert.equal(r.entries.length, 2);
  assert.ok(r.entries.every((e) => e.run_id.startsWith('shmup_slice')));
});

test('loadDispatchAudit: absent -> status ABSENT', () => {
  const root = fakeRepo();
  const r = loadDispatchAudit(root, 'proj');
  assert.equal(r.status, 'ABSENT');
});

// --- loadProjectDecisions --------------------------------------------------------------------

test('loadProjectDecisions: filtre par item OU queue mentionnant le projet', () => {
  const root = fakeRepo();
  writeDecisions(root, [
    { ts: '2026-07-20', queue: 'forge_ledger_proposals', item: 'shmup_slice-20260714a', decision: 'ACCEPT' },
    { ts: '2026-07-20', queue: 'forge_ledger_proposals', item: 'card_engine-20260720a', decision: 'ACCEPT' },
    { ts: '2026-07-20', actor: 'Pierre', verbatim: 'sans item ni queue projet' },
  ]);
  const r = loadProjectDecisions(root, 'shmup_slice');
  assert.equal(r.decisions.length, 1);
  assert.equal(r.decisions[0].item, 'shmup_slice-20260714a');
});

// --- loadArtifacts ----------------------------------------------------------------------------

test('loadArtifacts: absent -> status ABSENT (cas card_engine reel)', () => {
  const root = fakeRepo();
  const r = loadArtifacts(root, 'prose_project');
  assert.equal(r.status, 'ABSENT');
});

test('loadArtifacts: liste triee, etiquetee auto-declare', () => {
  const root = fakeRepo();
  writeArtifact(root, 'proj', 's9-build');
  writeArtifact(root, 'proj', 's0-contrat');
  const r = loadArtifacts(root, 'proj');
  assert.equal(r.status, 'OK');
  assert.deepEqual(r.files.map((f) => f.etape), ['s0-contrat', 's9-build']);
  assert.ok(r.files.every((f) => f.label === 'auto-déclaré'));
});

// --- resolveGameFile --------------------------------------------------------------------------

test('resolveGameFile: resout via GAMES/<project>/<fichier>', () => {
  const root = fakeRepo();
  writeGameFile(root, 'proj', 'logic/thing.mjs', 'x');
  const r = resolveGameFile(root, 'proj', 'logic/thing.mjs');
  assert.equal(r.exists, true);
  assert.equal(r.resolved, join('games', 'proj', 'logic', 'thing.mjs'));
});

test('resolveGameFile: fichier introuvable -> exists false, deux candidats essayes', () => {
  const root = fakeRepo();
  const r = resolveGameFile(root, 'proj', 'logic/absent.mjs');
  assert.equal(r.exists, false);
  assert.equal(r.tried.length, 2);
});

// --- findFeaturesByQuery ----------------------------------------------------------------------

test('findFeaturesByQuery: match exact insensible a la casse sur feature', () => {
  const features = [sampleFeature];
  const r = findFeaturesByQuery(features, 'r1 test feature');
  assert.equal(r.matches.length, 1);
  assert.equal(r.match_kind, 'exact_feature_name');
});

test('findFeaturesByQuery: match exact sur fonction si feature ne matche pas', () => {
  const features = [sampleFeature];
  const r = findFeaturesByQuery(features, 'dothing');
  assert.equal(r.matches.length, 1);
  assert.equal(r.match_kind, 'exact_fonction_name');
});

test('findFeaturesByQuery: substring en dernier recours', () => {
  const features = [sampleFeature];
  const r = findFeaturesByQuery(features, 'test feat');
  assert.equal(r.matches.length, 1);
  assert.equal(r.match_kind, 'substring_feature_name');
});

test('findFeaturesByQuery: aucun match -> matches vide, match_kind none', () => {
  const r = findFeaturesByQuery([sampleFeature], 'inexistant-xyz');
  assert.deepEqual(r.matches, []);
  assert.equal(r.match_kind, 'none');
});

// --- findFeaturesByFileQuery (requete inverse) -------------------------------------------------

test('findFeaturesByFileQuery: match exact sur chemin declare', () => {
  const r = findFeaturesByFileQuery([sampleFeature], 'proj', 'logic/thing.mjs');
  assert.equal(r.matches.length, 1);
  assert.equal(r.match_kind, 'exact');
});

test('findFeaturesByFileQuery: prefixe GAMES/<project>/ retire avant comparaison', () => {
  const r = findFeaturesByFileQuery([sampleFeature], 'proj', 'GAMES/proj/logic/thing.mjs');
  assert.equal(r.matches.length, 1);
  assert.equal(r.match_kind, 'exact');
  assert.equal(r.normalized_query, 'logic/thing.mjs');
});

test('findFeaturesByFileQuery: aucun match -> vide', () => {
  const r = findFeaturesByFileQuery([sampleFeature], 'proj', 'ailleurs/rien.mjs');
  assert.deepEqual(r.matches, []);
});

// --- buildFeatureChain ------------------------------------------------------------------------

test('buildFeatureChain: assemble fichiers+runs+decisions, note de granularite toujours presente', () => {
  const root = fakeRepo();
  writeGameFile(root, 'proj', 'logic/thing.mjs', 'x');
  const ctx = {
    stateSteps: { status: 'OK', steps: [{ etape: 's9-build', status: 'OK', attempts: 1, ts: 100, model: 'opus' }] },
    dispatchByEtape: new Map([['s9-build', [{ model: 'opus', capability_role: 'builder', provider: 'claude-local', ts: 100 }]]]),
    decisions: [{ ts: '2026-07-20', item: 'proj-1', decision: 'ACCEPT' }],
    artifacts: [{ etape: 's9-build', filename: 's9-build.txt', label: 'auto-déclaré' }],
  };
  const chain = buildFeatureChain(root, 'proj', sampleFeature, ctx);
  assert.equal(chain.feature, 'R1 test feature');
  assert.equal(chain.files[0].resolved.exists, true);
  assert.equal(chain.run_steps.length, 1);
  assert.equal(chain.run_steps[0].models_roles[0].model, 'opus');
  assert.equal(chain.run_steps[0].artifact.filename, 's9-build.txt');
  assert.equal(chain.decisions.length, 1);
  assert.ok(chain.granularity_note.includes('run+étape+modèle'));
  assert.equal(chain.claim_verdict, 'NO_CLAIM_ALLOWED');
});

// --- buildOverview / runFeatureQuery / runFileQuery (integration fixtures) ---------------------

test('buildOverview: projet sans wiremap -> sortie propre, aucune exception', () => {
  const root = fakeRepo();
  const r = buildOverview(root, 'inexistant');
  assert.equal(r.wiremap.status, 'ABSENT');
  assert.equal(r.claim_verdict, 'NO_CLAIM_ALLOWED');
});

test('buildOverview: compteurs corrects sur fixture complete', () => {
  const root = fakeRepo();
  writeWiremap(root, 'proj', { features: [sampleFeature, { ...sampleFeature, feature: 'R2', fichiers: ['logic/other.mjs'] }] });
  writeDecisions(root, [{ ts: '2026-07-20', item: 'proj-run1', decision: 'ACCEPT' }]);
  writeDispatchAudit(root, [{ etape: 's0-contrat', model: 'opus', capability_role: 'contract_author', run_id: 'proj-run1', ts: 1 }]);
  const r = buildOverview(root, 'proj');
  assert.equal(r.wiremap.feature_count, 2);
  assert.equal(r.wiremap.unique_file_count, 2);
  assert.equal(r.decisions.count, 1);
  assert.equal(r.dispatch_audit.matched_entries, 1);
  assert.equal(r.state.status, 'ABSENT');
  assert.ok(r.orchestration_note.includes('orchestration prose'));
});

test('runFeatureQuery: projet sans wiremap -> sortie propre exit-safe (pas de throw)', () => {
  const root = fakeRepo();
  const r = runFeatureQuery(root, 'inexistant', 'quoi-que-ce-soit');
  assert.equal(r.wiremap_status, 'ABSENT');
  assert.equal(r.claim_verdict, 'NO_CLAIM_ALLOWED');
});

test('runFeatureQuery: chaine complete nominale avec drift de gel signale', () => {
  const root = fakeRepo();
  writeWiremap(root, 'proj', { features: [sampleFeature, { ...sampleFeature, feature: 'R2-nouvelle', fichiers: ['logic/new.mjs'] }] });
  writeWiremapFrozen(root, 'proj', { features: ['R1 test feature'] }); // R2-nouvelle absente du gel
  writeGameFile(root, 'proj', 'logic/thing.mjs', 'x');
  const r = runFeatureQuery(root, 'proj', 'R1 test feature');
  assert.equal(r.match_count, 1);
  assert.equal(r.chains[0].feature, 'R1 test feature');
  assert.equal(r.frozen_drift.checked, true);
  assert.equal(r.frozen_drift.divergent, true);
  assert.deepEqual(r.frozen_drift.added_since_freeze, ['R2-nouvelle']);
});

test('runFileQuery: requete inverse nominale', () => {
  const root = fakeRepo();
  writeWiremap(root, 'proj', { features: [sampleFeature] });
  writeGameFile(root, 'proj', 'logic/thing.mjs', 'x');
  const r = runFileQuery(root, 'proj', 'logic/thing.mjs');
  assert.equal(r.match_count, 1);
  assert.equal(r.chains[0].feature, 'R1 test feature');
});

test('runFileQuery: fichier hors wiremap -> match_count 0, jamais un crash', () => {
  const root = fakeRepo();
  writeWiremap(root, 'proj', { features: [sampleFeature] });
  const r = runFileQuery(root, 'proj', 'nimporte/quoi.mjs');
  assert.equal(r.match_count, 0);
});

test('wiremap.json corrompu tolere par runFeatureQuery -> statut CORRUPT, exit-safe', () => {
  const root = fakeRepo();
  const dir = join(root, 'EVIDENCE', 'runs', 'broken');
  mkdirSync(dir, { recursive: true });
  writeFileSync(join(dir, 'wiremap.json'), 'pas du json du tout', 'utf-8');
  const r = runFeatureQuery(root, 'broken', 'x');
  assert.equal(r.wiremap_status, 'CORRUPT');
  assert.deepEqual(r.matches, []);
});

// --- CLI (spawn reel du script) ------------------------------------------------------------------

test('CLI: exit 0 meme sans argument', () => {
  const scriptPath = join(process.cwd(), 'scripts', 'forge', 'wiremap_nav.mjs');
  const r = spawnSync(process.execPath, [scriptPath], { encoding: 'utf-8' });
  assert.equal(r.status, 0, r.stderr);
});

test('CLI: projet fantome -> exit 0, JSON parseable, claim_verdict correct', () => {
  const scriptPath = join(process.cwd(), 'scripts', 'forge', 'wiremap_nav.mjs');
  const r = spawnSync(process.execPath, [scriptPath, 'projet-fantome-inexistant-xyz', '--json'], { encoding: 'utf-8' });
  assert.equal(r.status, 0, r.stderr);
  const json = JSON.parse(r.stdout);
  assert.equal(json.wiremap.status, 'ABSENT');
  assert.equal(json.claim_verdict, 'NO_CLAIM_ALLOWED');
});

test('CLI: --json sur shmup_slice reel (vue d ensemble) produit un JSON parseable', () => {
  const scriptPath = join(process.cwd(), 'scripts', 'forge', 'wiremap_nav.mjs');
  const r = spawnSync(process.execPath, [scriptPath, 'shmup_slice', '--json'], { encoding: 'utf-8' });
  assert.equal(r.status, 0, r.stderr);
  const json = JSON.parse(r.stdout);
  assert.equal(json.project, 'shmup_slice');
  assert.ok(Array.isArray(json.features));
  assert.equal(json.claim_verdict, 'NO_CLAIM_ALLOWED');
});

test('CLI: --feature reel sur shmup_slice (R1) retourne une chaine avec git_log', () => {
  const scriptPath = join(process.cwd(), 'scripts', 'forge', 'wiremap_nav.mjs');
  const r = spawnSync(process.execPath, [scriptPath, 'shmup_slice', '--feature', 'moveShip', '--json'], { encoding: 'utf-8' });
  assert.equal(r.status, 0, r.stderr);
  const json = JSON.parse(r.stdout);
  assert.equal(json.match_count, 1);
  assert.equal(json.chains[0].fonction, 'moveShip');
});

test('CLI: --file reel sur card_engine (prose, sans state.json)', () => {
  const scriptPath = join(process.cwd(), 'scripts', 'forge', 'wiremap_nav.mjs');
  const r = spawnSync(process.execPath, [scriptPath, 'card_engine', '--file', 'core/card.mjs', '--json'], { encoding: 'utf-8' });
  assert.equal(r.status, 0, r.stderr);
  const json = JSON.parse(r.stdout);
  assert.ok(json.match_count >= 1);
  assert.ok(json.orchestration_note && json.orchestration_note.includes('orchestration prose'));
});

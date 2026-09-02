// Tests de l'Execution Proof V0.
// node --test forge/execution_proof.test.mjs
//
// AUCUN test ne lance le runtime reel : `executer` est toujours injecte. Le seul run
// reel de cette couche est versionne dans EVIDENCE/bundles/EXECUTION_PROOF_V0/.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, writeFile, mkdir } from 'node:fs/promises';
import { readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  MATCH, MISMATCH, MISMATCHES, comparer, construireTrace, diffSnapshots, pointDAppel,
  posix, snapshot, executerSousObservation, mutationsAcceptables, verifierMaillonRepris,
  argumentsDInvocation, parserSortie,
} from './execution_proof.mjs';

const PLAN = (o = {}) => ({
  execution_id: 'exec-test',
  root_problem_id: 'REPAIR_NON_CONVERGENCE',
  mutation_id: 'REPAIR-LOOP-V1',
  selected_recipe: 'world_scan_repair_v1',
  runtime_to_call: o.runtime ?? {
    runtime_role: 'repair_runtime',
    entrypoints: ['forge/repair_step.mjs'],
    adapter: 'forge/repair_runtime_adapter.mjs',
  },
  required_inputs: o.inputs ?? ['finding_id', 'artifact_ref'],
  expected_outputs: o.outputs ?? ['before', 'after'],
  evidence_targets: o.evidence ?? [],
});

const OBS = (o = {}) => ({
  runtime_called: { module: o.module ?? 'forge/repair_runtime_adapter.mjs' },
  exit_code: 0,
  output_keys: o.keys ?? ['after', 'before'],
  output: o.output ?? { root_problem_id: 'REPAIR_NON_CONVERGENCE', mutation_used: 'REPAIR-LOOP-V1' },
  files: o.files ?? { created: [], modified: ['scope/a.json'], deleted: [] },
});

const OPTS = { scope: ['scope'], requeteFournie: { finding_id: 'x', artifact_ref: 'y' } };

// --- comparaison ------------------------------------------------------------------

test('plan valide -> MATCH, les 7 verifications passent', () => {
  const v = comparer(PLAN(), OBS(), OPTS);
  assert.equal(v.match_status, MATCH);
  assert.deepEqual(v.mismatches, []);
  assert.equal(v.checks.length, 7);
  assert.ok(v.checks.every((c) => c.ok));
});

test('runtime different -> MISMATCH nomme, jamais corrige', () => {
  const v = comparer(PLAN(), OBS({ module: 'forge/autre_chose.mjs' }), OPTS);
  assert.equal(v.match_status, MISMATCH);
  assert.equal(v.mismatches[0].mismatch, MISMATCHES.WRONG_RUNTIME);
});

test('sortie manquante -> MISMATCH avec le nom du champ absent', () => {
  const v = comparer(PLAN({ outputs: ['before', 'after', 'patch'] }), OBS(), OPTS);
  const m = v.mismatches.find((x) => x.mismatch === MISMATCHES.DIFFERENT_OUTPUT);
  assert.match(m.detail, /patch/);
});

test('fichier hors scope -> MISMATCH, le fichier est nomme', () => {
  const v = comparer(PLAN(), OBS({
    files: { created: ['ailleurs/secret.json'], modified: [], deleted: [] },
  }), OPTS);
  const m = v.mismatches.find((x) => x.mismatch === MISMATCHES.UNEXPECTED_FILE);
  assert.match(m.detail, /ailleurs\/secret\.json/);
});

test('evidence absente -> MISMATCH', () => {
  const v = comparer(PLAN({ evidence: ['lab/nexiste_pas.json'] }), OBS(), OPTS);
  assert.ok(v.mismatches.some((x) => x.mismatch === MISMATCHES.MISSING_EVIDENCE));
});

test('entree declaree non fournie -> MISMATCH', () => {
  const v = comparer(PLAN({ inputs: ['finding_id', 'artifact_ref', 'allowed_fields'] }), OBS(), OPTS);
  const m = v.mismatches.find((x) => x.mismatch === MISMATCHES.MISSING_INPUT);
  assert.match(m.detail, /allowed_fields/);
});

test('root_problem ou mutation qui derive -> MISMATCH', () => {
  const derive = comparer(PLAN(), OBS({
    output: { root_problem_id: 'AUTRE', mutation_used: 'REPAIR-LOOP-V1' },
  }), OPTS);
  assert.ok(derive.mismatches.some((x) => x.mismatch === MISMATCHES.ROOT_PROBLEM_DRIFT));

  const autreMut = comparer(PLAN(), OBS({
    output: { root_problem_id: 'REPAIR_NON_CONVERGENCE', mutation_used: 'M-autre' },
  }), OPTS);
  assert.ok(autreMut.mismatches.some((x) => x.mismatch === MISMATCHES.WRONG_MUTATION));
});

test('un plan MODIFIE apres coup est rejete', () => {
  // meme execution observee, plan trafique : le verdict doit basculer.
  const obs = OBS();
  assert.equal(comparer(PLAN(), obs, OPTS).match_status, MATCH);
  const trafique = { ...PLAN(), mutation_id: 'M-substituee' };
  assert.equal(comparer(trafique, obs, OPTS).match_status, MISMATCH);
});

// --- observation ------------------------------------------------------------------

test('snapshot + diffSnapshots voient creation, modification, suppression', async () => {
  const d = await mkdtemp(join(tmpdir(), 'proof-'));
  await writeFile(join(d, 'a.json'), '1', 'utf-8');
  const avant = await snapshot(d);
  await writeFile(join(d, 'a.json'), '2', 'utf-8');
  await mkdir(join(d, 'sous'), { recursive: true });
  await writeFile(join(d, 'sous', 'b.json'), '3', 'utf-8');
  const diff = diffSnapshots(avant, await snapshot(d));
  assert.deepEqual(diff.modified, ['a.json']);
  assert.deepEqual(diff.created, ['sous/b.json']);
  assert.deepEqual(diff.deleted, []);
});

test('posix normalise les separateurs — le defaut trouve par le 1er run reel', () => {
  assert.equal(posix(String.raw`EVIDENCE\bundles\X`), 'EVIDENCE/bundles/X');
  assert.equal(posix('EVIDENCE/bundles/X'), 'EVIDENCE/bundles/X');
});

test('pointDAppel prefere l adapter — c est lui qui accepte le contrat d entree', () => {
  assert.deepEqual(pointDAppel(PLAN()),
    { module: 'forge/repair_runtime_adapter.mjs', niveau: 'adapter' });
  assert.deepEqual(pointDAppel(PLAN({ runtime: { entrypoints: ['x.mjs'] } })),
    { module: 'x.mjs', niveau: 'entrypoint' });
  assert.deepEqual(pointDAppel({}), { module: null, niveau: null });
});

test('executerSousObservation appelle le module du PLAN, jamais un autre', async () => {
  const d = await mkdtemp(join(tmpdir(), 'proof-'));
  let vu = null;
  const obs = await executerSousObservation(PLAN(), {
    racine: d, scope: ['.'], requeteRuntime: 'req.json',
    executer: async ({ args }) => { vu = args; return { code: 0, stdout: '{"a":1}', stderr: '' }; },
  });
  assert.equal(vu[0], 'forge/repair_runtime_adapter.mjs');
  assert.equal(obs.runtime_called.module, vu[0]);
  assert.deepEqual(obs.output_keys, ['a']);
  assert.equal(obs.exit_code, 0);
});

test('sortie illisible : observee, jamais une exception', async () => {
  const d = await mkdtemp(join(tmpdir(), 'proof-'));
  const obs = await executerSousObservation(PLAN(), {
    racine: d, scope: ['.'], requeteRuntime: 'req.json',
    executer: async () => ({ code: 1, stdout: 'pas du json', stderr: 'boom' }),
  });
  assert.equal(obs.stdout_parsed, false);
  assert.deepEqual(obs.output_keys, []);
  assert.equal(obs.exit_code, 1);
});

// --- invariants -------------------------------------------------------------------

test('DETERMINISME : meme plan + meme observation -> meme verdict et meme trace', () => {
  const p = PLAN();
  const o = OBS();
  assert.deepEqual(comparer(p, o, OPTS), comparer(p, o, OPTS));
  const t1 = construireTrace(p, o, comparer(p, o, OPTS));
  const t2 = construireTrace(p, o, comparer(p, o, OPTS));
  assert.deepEqual(t1, t2);
  assert.equal(t1.plan_id, 'exec-test');
});

test('la trace porte exactement les champs exiges', () => {
  const t = construireTrace(PLAN(), OBS(), comparer(PLAN(), OBS(), OPTS));
  for (const c of ['plan_id', 'runtime_called', 'files_changed', 'outputs_created',
    'evidence_created', 'mutation_used', 'match_status']) {
    assert.ok(c in t, `champ manquant : ${c}`);
  }
});

test('AUCUN LLM hors du runtime prevu : le module n appelle aucun modele', () => {
  const src = readFileSync(fileURLToPath(new URL('./execution_proof.mjs', import.meta.url)), 'utf-8');
  const code = src.split('\n').filter((l) => !l.trim().startsWith('//') && !l.trim().startsWith('*')).join('\n');
  for (const i of ['fetch(', 'localhost', '/v1/chat', 'anthropic', 'openai']) {
    assert.ok(!code.includes(i), `la preuve ne doit pas contenir « ${i} »`);
  }
  // le SEUL processus lance est `node <module du plan>` — aucune commande en dur
  assert.ok(!/spawn\(\s*['"](?!.*\$\{)/.test(code.replace("spawn(cmd,", "")),
    'aucune commande codee en dur');
});

test('HumanGate : sans --confirm, la CLI refuse (verifie sur la source)', () => {
  const src = readFileSync(fileURLToPath(new URL('./execution_proof.mjs', import.meta.url)), 'utf-8');
  assert.ok(src.includes("argv.includes('--confirm')"));
  assert.ok(src.includes('HumanGate'));
});

// --- composition (ambiguites levees le 2026-08-04) ---------------------------------

const PLAN_COMPO = (o = {}) => ({
  ...PLAN(),
  mutation_id: 'M-ws6',
  capability_chain: [
    { capability: 'instance_separation', evidence: 'M-ws5' },
    { capability: 'targeted_field_repair', evidence: 'REPAIR-LOOP-V1' },
  ],
  runtime_chain: o.chaine ?? [
    { runtime_role: 'worldscan', contract_kind: 'step_contract', callable: null },
    { runtime_role: 'repair_runtime', contract_kind: 'runtime_contract',
      callable: 'forge/repair_runtime_adapter.mjs' },
  ],
});

test('pointDAppel suit `callable` — plus aucune devinette entrypoint/adapter', () => {
  const p = PLAN({ runtime: { entrypoints: ['moteur.mjs'], adapter: 'porte.mjs',
    callable: 'porte.mjs', callable_level: 'adapter' } });
  assert.deepEqual(pointDAppel(p), { module: 'porte.mjs', niveau: 'adapter' });
});

test('COMPOSITION : un maillon repris sous empreinte VERIFIEE est accepte', () => {
  const repris = [{ capability: 'instance_separation', verified: true, sha256_16: 'abc' }];
  const v = comparer(PLAN_COMPO(), OBS({ output: {
    root_problem_id: 'REPAIR_NON_CONVERGENCE', mutation_used: 'REPAIR-LOOP-V1' } }),
  { ...OPTS, resumedLegs: repris });
  assert.equal(v.match_status, MATCH, JSON.stringify(v.mismatches));
  assert.ok(v.checks.some((c) => c.check === 'composition_legs' && c.ok));
});

test('COMPOSITION : un maillon NON justifie -> MISMATCH nomme', () => {
  const v = comparer(PLAN_COMPO(), OBS({ output: {
    root_problem_id: 'REPAIR_NON_CONVERGENCE', mutation_used: 'REPAIR-LOOP-V1' } }), OPTS);
  const m = v.mismatches.find((x) => x.mismatch === MISMATCHES.LEG_UNACCOUNTED);
  assert.match(m.detail, /instance_separation/);
  assert.match(m.detail, /aucune reprise declaree/);
});

test('COMPOSITION : une empreinte qui ne correspond PAS est refusee', () => {
  const repris = [{ capability: 'instance_separation', verified: false, motif: 'sha aaa != bbb' }];
  const v = comparer(PLAN_COMPO(), OBS({ output: {
    root_problem_id: 'REPAIR_NON_CONVERGENCE', mutation_used: 'REPAIR-LOOP-V1' } }),
  { ...OPTS, resumedLegs: repris });
  assert.equal(v.match_status, MISMATCH);
  assert.match(v.mismatches.find((x) => x.mismatch === MISMATCHES.LEG_UNACCOUNTED).detail, /sha/);
});

test('mutationsAcceptables : celle du plan ET celle du maillon execute', () => {
  const a = mutationsAcceptables(PLAN_COMPO(), 'forge/repair_runtime_adapter.mjs');
  assert.deepEqual(a.sort(), ['M-ws6', 'REPAIR-LOOP-V1']);
  // un module non declare n apporte aucune mutation supplementaire
  assert.deepEqual(mutationsAcceptables(PLAN_COMPO(), 'autre.mjs'), ['M-ws6']);
});

test('une mutation ETRANGERE aux deux niveaux reste un ecart', () => {
  const v = comparer(PLAN_COMPO(), OBS({ output: {
    root_problem_id: 'REPAIR_NON_CONVERGENCE', mutation_used: 'M-inconnue' } }),
  { ...OPTS, resumedLegs: [{ capability: 'instance_separation', verified: true }] });
  assert.equal(v.match_status, MISMATCH);
  assert.ok(v.mismatches.some((x) => x.mismatch === MISMATCHES.WRONG_MUTATION));
});

test('verifierMaillonRepris recalcule l empreinte, ne fait pas confiance', async () => {
  const d = await mkdtemp(join(tmpdir(), 'proof-'));
  await writeFile(join(d, 'a.json'), 'contenu', 'utf-8');
  const bon = verifierMaillonRepris('a.json', null, d);
  assert.equal(bon.verified, true);
  assert.equal(bon.sha256_16.length, 16);
  assert.equal(verifierMaillonRepris('a.json', bon.sha256_16, d).verified, true);
  assert.equal(verifierMaillonRepris('a.json', '0000000000000000', d).verified, false);
  assert.equal(verifierMaillonRepris('absent.json', null, d).verified, false);
});

// --- branche deterministic / entrypoint / positional_artifact ----------------------

const PLAN_DET = (o = {}) => ({
  execution_id: 'exec-det',
  root_problem_id: 'ORACLE_FALSE_NEGATIVE',
  mutation_id: 'Q1-DISCRIMINANCE',
  selected_recipe: 'duplicate_content_gate_v1',
  capability_chain: [{ capability: 'duplicate_content_detection', evidence: 'Q1-DISCRIMINANCE' }],
  runtime_to_call: {
    runtime_role: 'deterministic',
    entrypoints: ['forge/oracle_quality.mjs'],
    adapter: null,
    callable: o.callable ?? 'forge/oracle_quality.mjs',
    callable_level: 'entrypoint',
    invocation: o.invocation ?? 'positional_artifact',
  },
  runtime_chain: [{ runtime_role: 'deterministic', contract_kind: 'runtime_contract',
    callable: 'forge/oracle_quality.mjs' }],
  required_inputs: ['artifact_ref'],
  expected_outputs: ['verdict', 'signaux', 'compte'],
  evidence_targets: o.evidence ?? [],
});

const OBS_DET = (o = {}) => ({
  runtime_called: { module: o.module ?? 'forge/oracle_quality.mjs', niveau: 'entrypoint' },
  exit_code: 0,
  output_keys: o.keys ?? ['compte', 'signaux', 'verdict'],
  output: o.output ?? { verdict: 'PASS', signaux: [], compte: {} },
  files: o.files ?? { created: [], modified: [], deleted: [] },
});

const OPTS_DET = { scope: ['EVIDENCE/bundles/X'], requeteFournie: { artifact_ref: 'a.json' } };

test('DETERMINISTIC : runtime + entrypoint valides -> MATCH', () => {
  const v = comparer(PLAN_DET(), OBS_DET(), OPTS_DET);
  assert.equal(v.match_status, MATCH, JSON.stringify(v.mismatches));
  assert.equal(pointDAppel(PLAN_DET()).niveau, 'entrypoint',
    'cette branche exerce un entrypoint DIRECT, pas un adapter');
});

test('DETERMINISTIC : un autre runtime que celui du plan -> MISMATCH', () => {
  const v = comparer(PLAN_DET(), OBS_DET({ module: 'forge/repair_runtime_adapter.mjs' }),
    OPTS_DET);
  assert.equal(v.match_status, MISMATCH);
  assert.equal(v.mismatches[0].mismatch, MISMATCHES.WRONG_RUNTIME);
});

test('DETERMINISTIC : sortie aux mauvais noms -> MISMATCH (le contrat doit dire vrai)', () => {
  // le contrat declarait « compteurs », le code rend « compte » : corrige le 2026-08-04.
  const v = comparer(PLAN_DET(), OBS_DET({ keys: ['verdict', 'signaux', 'compteurs'] }), OPTS_DET);
  const m = v.mismatches.find((x) => x.mismatch === MISMATCHES.DIFFERENT_OUTPUT);
  assert.match(m.detail, /compte/);
});

test('DETERMINISTIC : evidence absente -> MISMATCH', () => {
  const v = comparer(PLAN_DET({ evidence: ['lab/pas_la.json'] }), OBS_DET(), OPTS_DET);
  assert.ok(v.mismatches.some((x) => x.mismatch === MISMATCHES.MISSING_EVIDENCE));
});

test('DETERMINISTIC : mutation etrangere -> MISMATCH', () => {
  const v = comparer(PLAN_DET(), OBS_DET({
    output: { verdict: 'PASS', mutation_used: 'M-etrangere' },
  }), OPTS_DET);
  assert.ok(v.mismatches.some((x) => x.mismatch === MISMATCHES.WRONG_MUTATION));
});

test('argumentsDInvocation suit la convention DECLAREE, ne la devine pas', () => {
  assert.deepEqual(
    argumentsDInvocation(PLAN_DET(), { declaredInputs: { artifact_ref: 'a.json' } }),
    ['a.json'], 'positional_artifact : le chemin de l artefact');
  assert.deepEqual(
    argumentsDInvocation(PLAN(), { requeteRuntime: 'req.json' }),
    ['req.json'], 'request_file : le fichier de requete');
  assert.throws(() => argumentsDInvocation(PLAN_DET(), { declaredInputs: {} }),
    /artifact_ref absent/, 'jamais un chemin invente');
});

test('parserSortie enregistre SA propre indulgence', () => {
  assert.deepEqual(parserSortie('{"a":1}'), { parsed: { a: 1 }, mode: 'strict' });
  const t = parserSortie('SEMANTIC_SIGNAL: PASS\n{"verdict":"PASS"}');
  assert.equal(t.mode, 'trailing_json');
  assert.deepEqual(t.parsed, { verdict: 'PASS' });
  assert.deepEqual(parserSortie('rien'), { parsed: null, mode: 'unparseable' });
});

test('DETERMINISTIC : le runtime n ecrit RIEN — verifie, pas suppose', () => {
  const v = comparer(PLAN_DET(), OBS_DET(), OPTS_DET);
  assert.ok(v.checks.find((c) => c.check === 'files_in_scope').detail.startsWith('0 fichier'));
});

test('DETERMINISME sur la branche deterministic', () => {
  assert.deepEqual(comparer(PLAN_DET(), OBS_DET(), OPTS_DET),
    comparer(PLAN_DET(), OBS_DET(), OPTS_DET));
});

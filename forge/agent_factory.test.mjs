// Tests de l'Agent Factory V0.
// node --test forge/agent_factory.test.mjs
//
// La Factory ne choisit pas, ne raisonne pas, ne score pas et n'exécute pas. Quatre
// tests le vérifient mécaniquement, dont un sur la source elle-même.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, writeFile, readdir, mkdir } from 'node:fs/promises';
import { readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  BLOCKERS, CHAMPS_REQUETE, blocContratRuntime, parseContratRuntime, validerRequete,
  empreinteExecution, instancier, chargerContexteFactory, requeteDepuisMutation,
  executerPlan,
} from './agent_factory.mjs';

const ROLES_YAML = [
  'models:', '  - id: lmstudio/qwen', '    roles:', '      - repair_runtime',
  'runtime_contracts:', '', '  repair_runtime:', '    mission: >-', '      reparer',
  '    implementation:', '      adapter:    forge/repair_runtime_adapter.mjs',
  '      entrypoint: forge/repair_step.mjs', '      model:      lmstudio/qwen',
  '      kill_switch: FORGE_REPAIR=0', '    inputs:  [finding_id, artifact_ref]',
  '    outputs: [before, after]', '  autre:', '    mission: x',
].join('\n');

const M = (o = {}) => ({
  id: o.id ?? 'M-1', root_problem_id: o.rp ?? 'P1', accepted: o.accepted ?? true,
  evidence_refs: { artifacts: ['README.md'] }, evidence_status: 'VERSIONED',
});

const CTX = (o = {}) => ({
  mutations: o.mutations ?? [M()],
  capacites: { capabilities: o.capacites ?? [{ id: 'cap_a',
    capability_status: o.capStatus ?? 'PROVEN_EXECUTABLE', runtime_role: 'repair_runtime' }] },
  recettes: { recipes: o.recettes ?? [{
    id: 'r_v1', proven: true, recipe_status: 'EXECUTABLE',
    capability_chain: [{ capability: 'cap_a', evidence: 'M-1' }],
    runtime_roles: [{ capability: 'cap_a', capability_role: 'repair_runtime' }],
    evidence_requirements: ['README.md'],
  }] },
  roles: o.roles ?? new Set(['repair_runtime']),
  runtime_contracts: o.contrats ?? new Set(['repair_runtime']),
  contrats_etape: o.etapes ?? new Map(),
  runtime_contracts_detail: o.detail ?? new Map([['repair_runtime',
    parseContratRuntime(ROLES_YAML, 'repair_runtime')]]),
});

const REQ = (o = {}) => ({
  root_problem_id: 'P1', mutation_id: 'M-1', recipe_id: 'r_v1', capability_id: 'cap_a',
  runtime_role: 'repair_runtime', evidence_required: [],
  execution_contract_ref: 'roles.yaml#runtime_contracts.repair_runtime', ...o,
});

async function racine() {
  const dir = await mkdtemp(join(tmpdir(), 'factory-'));
  await writeFile(join(dir, 'README.md'), 'x', 'utf-8');
  return dir;
}

const blockers = (p) => p.blockers.map((b) => b.blocker);

// --- contrat d'entrée -----------------------------------------------------------

test('CHAMPS_REQUETE est exactement le contrat FactoryRequest', () => {
  assert.deepEqual([...CHAMPS_REQUETE].sort(), [
    'capability_id', 'evidence_required', 'execution_contract_ref', 'mutation_id',
    'recipe_id', 'root_problem_id', 'runtime_role',
  ]);
});

test('validerRequete refuse un champ manquant ou un passager clandestin', () => {
  for (const champ of CHAMPS_REQUETE) {
    const r = REQ();
    delete r[champ];
    assert.throws(() => validerRequete(r), new RegExp(`manquant.*${champ}`), champ);
  }
  assert.throws(() => validerRequete({ ...REQ(), model: 'opus' }), /hors contrat.*model/);
});

// --- lecture du contrat de runtime ----------------------------------------------

test('parseContratRuntime lit entrypoint, adapter, modele, coupure, entrees, sorties', () => {
  const c = parseContratRuntime(ROLES_YAML, 'repair_runtime');
  assert.deepEqual(c.entrypoints, ['forge/repair_step.mjs']);
  assert.equal(c.adapter, 'forge/repair_runtime_adapter.mjs');
  assert.equal(c.model, 'lmstudio/qwen');
  assert.equal(c.kill_switch, 'FORGE_REPAIR=0');
  assert.deepEqual(c.inputs, ['finding_id', 'artifact_ref']);
  assert.deepEqual(c.outputs, ['before', 'after']);
  assert.equal(blocContratRuntime(ROLES_YAML, 'inexistant'), null);
});

// --- les sept vérifications -----------------------------------------------------

test('chemin complet valide -> FactoryExecutionPlan executable', async () => {
  const p = instancier(REQ(), CTX(), await racine());
  assert.equal(p.executable, true, JSON.stringify(p.blockers));
  assert.deepEqual(p.blockers, []);
  assert.equal(p.execution_mode, 'PLAN_ONLY');
  assert.ok(p.execution_id.startsWith('exec-'));
  assert.equal(p.selected_recipe, 'r_v1');
  assert.equal(p.runtime_to_call.runtime_role, 'repair_runtime');
  assert.deepEqual(p.required_inputs, ['finding_id', 'artifact_ref']);
  assert.deepEqual(p.expected_outputs, ['before', 'after']);
  assert.deepEqual(p.evidence_targets, ['README.md']);
});

test('mutation inexistante -> STOP, aucun plan partiel', async () => {
  const p = instancier(REQ({ mutation_id: 'JAMAIS' }), CTX(), await racine());
  assert.deepEqual(blockers(p), [BLOCKERS.MUTATION_NOT_FOUND]);
  assert.equal(p.selected_recipe, null);
  assert.equal(p.runtime_to_call, null);
});

test('mutation non acceptee -> blocker nomme', async () => {
  const p = instancier(REQ(), CTX({ mutations: [M({ accepted: false })] }), await racine());
  assert.equal(p.executable, false);
  assert.ok(blockers(p).includes(BLOCKERS.MUTATION_NOT_ACCEPTED));
});

test('recette absente -> STOP', async () => {
  const p = instancier(REQ({ recipe_id: 'inconnue' }), CTX(), await racine());
  assert.deepEqual(blockers(p), [BLOCKERS.RECIPE_NOT_FOUND]);
});

test('recette non executable -> blocker, verdict RECALCULE par le binding', async () => {
  const p = instancier(REQ(), CTX({
    recettes: [{ id: 'r_v1', proven: false, recipe_status: 'EXECUTABLE',
      capability_chain: [{ capability: 'cap_a', evidence: 'M-1' }],
      runtime_roles: [{ capability: 'cap_a', capability_role: 'repair_runtime' }],
      evidence_requirements: ['README.md'] }],
  }), await racine());
  assert.equal(p.executable, false);
  assert.ok(blockers(p).includes(BLOCKERS.RECIPE_NOT_EXECUTABLE),
    'recipe_status=EXECUTABLE ne suffit pas : le binding tranche');
});

test('capacite absente -> STOP', async () => {
  const p = instancier(REQ(), CTX({ capacites: [] }), await racine());
  assert.ok(blockers(p).includes(BLOCKERS.CAPABILITY_NOT_FOUND));
  assert.equal(p.runtime_to_call, null);
});

test('capacite pas PROVEN_EXECUTABLE -> blocker', async () => {
  const p = instancier(REQ(), CTX({ capStatus: 'PROVEN_EXECUTED_EMBEDDED' }), await racine());
  assert.equal(p.executable, false);
  assert.ok(blockers(p).includes(BLOCKERS.CAPABILITY_NOT_PROVEN_EXECUTABLE));
});

test('runtime sans contrat -> blocker, aucun runtime_to_call invente', async () => {
  const p = instancier(REQ(), CTX({ contrats: new Set(), detail: new Map() }), await racine());
  assert.ok(blockers(p).includes(BLOCKERS.RUNTIME_CONTRACT_MISSING));
  assert.equal(p.runtime_to_call, null);
});

test('evidence absente -> blocker avec les fichiers manquants', async () => {
  const p = instancier(REQ({ evidence_required: ['lab/nexiste_pas.json'] }), CTX(), await racine());
  assert.equal(p.executable, false);
  const b = p.blockers.find((x) => x.blocker === BLOCKERS.EVIDENCE_MISSING);
  assert.match(b.detail, /nexiste_pas/);
});

test('declaration incoherente -> declaration_mismatch, jamais un silence', async () => {
  const r = await racine();
  const mauvaisProbleme = instancier(REQ({ root_problem_id: 'AUTRE' }), CTX(), r);
  assert.ok(blockers(mauvaisProbleme).includes(BLOCKERS.DECLARATION_MISMATCH));

  const mauvaisContrat = instancier(REQ({ execution_contract_ref: 'roles.yaml#autre' }), CTX(), r);
  assert.ok(blockers(mauvaisContrat).includes(BLOCKERS.DECLARATION_MISMATCH));
});

// --- invariants -----------------------------------------------------------------

test('DETERMINISME : meme requete -> meme plan ET meme execution_id', async () => {
  const r = await racine();
  const a = instancier(REQ(), CTX(), r);
  const b = instancier(REQ(), CTX(), r);
  assert.deepEqual(a, b);
  assert.equal(a.execution_id, b.execution_id);
});

test('execution_id CHANGE si le plan change', async () => {
  const r = await racine();
  const ok = instancier(REQ(), CTX(), r);
  const ko = instancier(REQ(), CTX({ mutations: [M({ accepted: false })] }), r);
  assert.notEqual(ok.execution_id, ko.execution_id);
  assert.equal(empreinteExecution({ a: 1 }), empreinteExecution({ a: 1 }));
});

test('AUCUN effet fichier en mode plan', async () => {
  const r = await racine();
  const avant = (await readdir(r)).sort();
  instancier(REQ(), CTX(), r);
  instancier(REQ({ mutation_id: 'JAMAIS' }), CTX(), r);
  assert.deepEqual((await readdir(r)).sort(), avant);
});

test('AUCUN LLM, AUCUN reseau, AUCUNE ecriture, AUCUNE horloge : verifie sur la source', () => {
  const src = readFileSync(fileURLToPath(new URL('./agent_factory.mjs', import.meta.url)), 'utf-8');
  const code = src.split('\n').filter((l) => !l.trim().startsWith('//') && !l.trim().startsWith('*')).join('\n');
  for (const i of ['fetch(', 'localhost', 'subprocess', 'child_process', 'spawn(',
    'writeFile', 'appendFile', 'mkdir(', 'Date.now', 'Math.random']) {
    assert.ok(!code.includes(i), `la Factory ne doit pas contenir « ${i} »`);
  }
});

test('AUCUN score : le plan ne porte aucune note', async () => {
  const brut = JSON.stringify(instancier(REQ(), CTX(), await racine())).toLowerCase();
  for (const i of ['"score', '"reward"', '"fitness', '"rank', '"weight']) {
    assert.ok(!brut.includes(i), `champ interdit : ${i}`);
  }
});

// --- le dépôt réel --------------------------------------------------------------

test('DEPOT REEL : REPAIR-LOOP-V1 produit un plan valide, sans rien lancer', async () => {
  const ctx = await chargerContexteFactory();
  const plan = instancier(requeteDepuisMutation('REPAIR-LOOP-V1', ctx), ctx);
  assert.equal(plan.executable, true, JSON.stringify(plan.blockers));
  assert.equal(plan.execution_mode, 'PLAN_ONLY');
  assert.equal(plan.selected_recipe, 'world_scan_repair_v1');
  assert.equal(plan.runtime_to_call.runtime_role, 'repair_runtime');
  assert.deepEqual(plan.runtime_to_call.entrypoints, ['forge/repair_step.mjs']);
  assert.equal(plan.runtime_to_call.kill_switch, 'FORGE_REPAIR=0');
  assert.deepEqual(plan.required_inputs, ['finding_id', 'root_problem_id', 'artifact_ref',
    'evidence_ref', 'allowed_fields', 'forbidden_fields']);
  assert.deepEqual(plan.expected_outputs, ['before', 'after', 'patch', 'oracle_before',
    'oracle_after', 'evidence_created', 'mutation_used']);
  assert.equal(plan.evidence_targets.length, 4);
});

test('DEPOT REEL : une mutation interne ne produit AUCUN plan', async () => {
  const ctx = await chargerContexteFactory();
  const plan = instancier(requeteDepuisMutation('Q2-LANGUE', ctx), ctx);
  assert.equal(plan.executable, false);
  assert.ok(blockers(plan).includes(BLOCKERS.REQUEST_INVALID),
    'sans recette resolue, la requete elle-meme est incomplete — et c est dit');
});

// --- EXECUTE V1 : les cinq conditions ---------------------------------------------

/** Plan minimal executable, avec un runtime dont le callable est declare. */
const PLAN_EXEC = (o = {}) => ({
  execution_id: 'exec-x',
  executable: true,
  root_problem_id: 'P1',
  mutation_id: 'M-1',
  selected_recipe: 'r_v1',
  capability_chain: [{ capability: 'cap_a', evidence: 'M-1' }],
  runtime_chain: [{ runtime_role: 'repair_runtime', contract_kind: 'runtime_contract',
    callable: 'faux_runtime.mjs' }],
  runtime_to_call: { runtime_role: 'repair_runtime', callable: 'faux_runtime.mjs',
    callable_level: 'adapter', invocation: 'request_file' },
  required_inputs: ['artifact_ref'],
  expected_outputs: o.outputs ?? ['before', 'after'],
  evidence_targets: o.evidence ?? [],
  blockers: [],
});

const EXEC_OK = async () => ({ code: 0, stdout: '{"before":1,"after":2}', stderr: '' });

const OPTS_EXEC = (o = {}) => ({
  confirm: o.confirm ?? true,
  scope: o.scope ?? ['scope'],
  runtimeRequest: 'runtimeRequest' in o ? o.runtimeRequest : 'req.json',
  declaredInputs: o.declaredInputs ?? { artifact_ref: 'a.json' },
  executer: o.executer ?? EXEC_OK,
  racine: o.racine,
});

test('EXECUTE : plan valide -> exécution MATCH', async () => {
  const r = await executerPlan(PLAN_EXEC(), OPTS_EXEC({ racine: await racine() }));
  assert.deepEqual(r.refus, []);
  assert.equal(r.execution.verdict.match_status, 'MATCH', JSON.stringify(r.execution.verdict.mismatches));
  assert.equal(r.execution.trace.plan_id, 'exec-x');
});

test('EXECUTE : HumanGate absent -> REFUS, rien n est lance', async () => {
  let lance = false;
  const r = await executerPlan(PLAN_EXEC(), OPTS_EXEC({
    confirm: false, executer: async () => { lance = true; return EXEC_OK(); },
  }));
  assert.equal(r.execution, null);
  assert.ok(r.refus[0].startsWith('HUMANGATE_ABSENT'));
  assert.equal(lance, false, 'le runtime ne doit PAS avoir ete appele');
});

test('EXECUTE : scope absent -> REFUS', async () => {
  const r = await executerPlan(PLAN_EXEC(), OPTS_EXEC({ scope: [] }));
  assert.ok(r.refus.some((x) => x.startsWith('SCOPE_ABSENT')));
  assert.equal(r.execution, null);
});

test('EXECUTE : un plan NON validé ne s exécute jamais', async () => {
  let lance = false;
  const r = await executerPlan(
    { ...PLAN_EXEC(), executable: false, blockers: [{ blocker: 'recipe_missing' }] },
    OPTS_EXEC({ executer: async () => { lance = true; return EXEC_OK(); } }),
  );
  assert.ok(r.refus.some((x) => x.includes('PLAN_NON_EXECUTABLE')));
  assert.equal(lance, false);
});

test('EXECUTE : la Factory ne fabrique pas les VALEURS des entrees', async () => {
  const r = await executerPlan(PLAN_EXEC(), OPTS_EXEC({ runtimeRequest: null }));
  assert.ok(r.refus.some((x) => x.startsWith('RUNTIME_REQUEST_ABSENTE')));
});

test('EXECUTE : ecriture HORS du perimetre declare -> MISMATCH, aucune correction', async () => {
  const r = await racine();
  await mkdir(join(r, 'declare'), { recursive: true });
  await mkdir(join(r, 'ailleurs'), { recursive: true });
  const res = await executerPlan(PLAN_EXEC(), OPTS_EXEC({
    racine: r,
    scope: ['declare'],                       // seul ce dossier est annonce
    executer: async () => {
      await writeFile(join(r, 'declare', 'attendu.json'), 'x', 'utf-8');
      await writeFile(join(r, 'ailleurs', 'intrus.json'), 'x', 'utf-8');
      return EXEC_OK();
    },
  }));
  // l intrus est HORS scope : il n est meme pas observe (le snapshot ne couvre que le
  // perimetre annonce). C est la limite honnete de cette couche, et elle est testee ici.
  assert.equal(res.execution.verdict.match_status, 'MATCH');
  assert.deepEqual(res.execution.trace.files_changed.created, ['declare/attendu.json']);
});

test('EXECUTE : un fichier inattendu DANS le perimetre est signale', async () => {
  const r = await racine();
  await mkdir(join(r, 'declare'), { recursive: true });
  const res = await executerPlan(PLAN_EXEC(), OPTS_EXEC({
    racine: r,
    scope: ['declare'],
    executer: async () => {
      await writeFile(join(r, 'declare', 'a.json'), 'x', 'utf-8');
      return EXEC_OK();
    },
  }));
  assert.equal(res.execution.trace.files_changed.created.length, 1);
});

test('EXECUTE : runtime different de celui du plan -> MISMATCH', async () => {
  const plan = PLAN_EXEC();
  // le plan declare `faux_runtime.mjs` ; on observe un appel a un autre module en
  // trafiquant le plan APRES l observation — le verdict doit basculer.
  const r = await executerPlan(plan, OPTS_EXEC({ racine: await racine() }));
  assert.equal(r.execution.verdict.match_status, 'MATCH');
  const proof = await import('./execution_proof.mjs');
  const trafique = { ...plan, runtime_to_call: { ...plan.runtime_to_call, callable: 'autre.mjs' } };
  const v = proof.comparer(trafique, { ...r.execution.trace, runtime_called: { module: 'faux_runtime.mjs' },
    output_keys: ['after', 'before'], output: {}, files: { created: [], modified: [], deleted: [] } },
  { scope: ['scope'], requeteFournie: { artifact_ref: 'a.json' } });
  assert.equal(v.match_status, 'MISMATCH');
  assert.equal(v.mismatches[0].mismatch, 'mauvais runtime');
});

test('EXECUTE : output manquant -> MISMATCH, arret sans retry', async () => {
  let appels = 0;
  const r = await executerPlan(PLAN_EXEC({ outputs: ['before', 'after', 'patch'] }), OPTS_EXEC({
    racine: await racine(),
    executer: async () => { appels += 1; return EXEC_OK(); },
  }));
  assert.equal(r.execution.verdict.match_status, 'MISMATCH');
  assert.equal(appels, 1, 'AUCUN retry : une invocation, une seule');
});

test('EXECUTE : evidence absente -> MISMATCH', async () => {
  const r = await executerPlan(PLAN_EXEC({ evidence: ['lab/nexiste_pas.json'] }),
    OPTS_EXEC({ racine: await racine() }));
  assert.equal(r.execution.verdict.match_status, 'MISMATCH');
  assert.ok(r.execution.verdict.mismatches.some((m) => /preuve absente/.test(m.mismatch)));
});

test('EXECUTE : aucun retry, aucune reparation, aucune boucle', async () => {
  let appels = 0;
  await executerPlan(PLAN_EXEC({ outputs: ['inexistant'] }), OPTS_EXEC({
    racine: await racine(),
    executer: async () => { appels += 1; return EXEC_OK(); },
  }));
  assert.equal(appels, 1);
  const src = readFileSync(fileURLToPath(new URL('./agent_factory.mjs', import.meta.url)), 'utf-8');
  const code = src.split('\n').filter((l) => !l.trim().startsWith('//') && !l.trim().startsWith('*')).join('\n');
  // On cherche des CONSTRUCTIONS, pas des mots : le mot « retry » apparait dans les
  // messages qui expliquent qu il n y en a pas.
  for (const i of ['while (', 'for (;;', 'setInterval', 'setTimeout', '.retry(']) {
    assert.ok(!code.includes(i), `--execute ne doit contenir aucun « ${i} »`);
  }
});

test('EXECUTE : n ecrit AUCUN registre et ne touche pas production_ready', () => {
  const src = readFileSync(fileURLToPath(new URL('./agent_factory.mjs', import.meta.url)), 'utf-8');
  const code = src.split('\n').filter((l) => !l.trim().startsWith('//') && !l.trim().startsWith('*')).join('\n');
  for (const i of ['writeFile', 'appendFile', 'production_ready', 'mutation_registry.json',
    'root_problems.json']) {
    assert.ok(!code.includes(i), `la Factory ne doit pas contenir « ${i} »`);
  }
});

// --- ADVERSARIAL : la colonne vertebrale tient-elle sous attaque ? -----------------
//
// Ces tests ne verifient pas que la chaine marche (c'est deja fait). Ils verifient
// qu'elle REFUSE quand on essaie de la contourner.

test('ADVERSARIAL 1 : ecriture hors du perimetre declare -> MISMATCH', async () => {
  const r = await racine();
  await mkdir(join(r, 'declare'), { recursive: true });
  // Le plan annonce deux dossiers ; le runtime en touche un troisieme, non annonce.
  const res = await executerPlan(PLAN_EXEC(), OPTS_EXEC({
    racine: r,
    scope: ['declare', 'ailleurs'],           // les DEUX sont observes
    executer: async () => {
      await mkdir(join(r, 'ailleurs'), { recursive: true });
      await writeFile(join(r, 'ailleurs', 'intrus.json'), 'x', 'utf-8');
      return EXEC_OK();
    },
  }));
  // observe ET dans le scope -> conforme. On force l ecart en retirant 'ailleurs' du
  // perimetre APRES coup : le meme fait devient un ecart.
  const proof = await import('./execution_proof.mjs');
  const v = proof.comparer(PLAN_EXEC(), {
    ...res.execution.trace,
    runtime_called: res.execution.trace.runtime_called,
    output_keys: ['after', 'before'],
    output: {},
    files: { created: ['ailleurs/intrus.json'], modified: [], deleted: [] },
  }, { scope: ['declare'], requeteFournie: { artifact_ref: 'a.json' } });
  assert.equal(v.match_status, 'MISMATCH');
  assert.equal(v.mismatches[0].mismatch, 'fichier inattendu');
  assert.match(v.mismatches[0].detail, /intrus\.json/);
});

test('ADVERSARIAL 2 : runtime declare != runtime execute -> MISMATCH', async () => {
  const proof = await import('./execution_proof.mjs');
  const plan = PLAN_EXEC();
  const v = proof.comparer(plan, {
    runtime_called: { module: 'forge/un_autre_module.mjs' },
    exit_code: 0, output_keys: ['after', 'before'], output: {},
    files: { created: [], modified: [], deleted: [] },
  }, { scope: ['scope'], requeteFournie: { artifact_ref: 'a.json' } });
  assert.equal(v.match_status, 'MISMATCH');
  assert.equal(v.mismatches[0].mismatch, 'mauvais runtime');
  assert.match(v.mismatches[0].detail, /n est pas declare dans le plan/);
});

test('ADVERSARIAL 3 : evidence falsifiee (empreinte qui ne correspond pas) -> MISMATCH', async () => {
  const proof = await import('./execution_proof.mjs');
  const d = await racine();
  await writeFile(join(d, 'repris.json'), 'contenu REEL', 'utf-8');
  const vrai = proof.verifierMaillonRepris('repris.json', null, d);
  // on declare une empreinte qui n est pas celle du fichier : falsification
  const faux = proof.verifierMaillonRepris('repris.json', '0000000000000000', d);
  assert.equal(vrai.verified, true);
  assert.equal(faux.verified, false);
  assert.match(faux.motif, /sha/);

  const plan = { ...PLAN_EXEC(), mutation_id: 'M-compo',
    capability_chain: [{ capability: 'cap_a', evidence: 'M-x' }, { capability: 'cap_b', evidence: 'M-y' }],
    runtime_chain: [{ runtime_role: 'r1', callable: null },
      { runtime_role: 'repair_runtime', callable: 'faux_runtime.mjs' }] };
  const v = proof.comparer(plan, {
    runtime_called: { module: 'faux_runtime.mjs' }, exit_code: 0,
    output_keys: ['after', 'before'], output: {},
    files: { created: [], modified: [], deleted: [] },
  }, { scope: ['scope'], requeteFournie: { artifact_ref: 'a.json' },
    resumedLegs: [{ capability: 'cap_a', ...faux }] });
  assert.equal(v.match_status, 'MISMATCH');
  assert.ok(v.mismatches.some((m) => /maillon de composition non justifie/.test(m.mismatch)));
});

test('ADVERSARIAL 4 : MATCH mecanique NE VAUT PAS qualite prouvee', async () => {
  const r = await executerPlan(PLAN_EXEC(), OPTS_EXEC({ racine: await racine() }));
  assert.equal(r.execution.verdict.match_status, 'MATCH');
  // Le verdict ne contient AUCUNE affirmation de qualite, et n en fabrique aucune.
  const brut = JSON.stringify(r.execution).toLowerCase();
  for (const i of ['"quality_ok', '"quality_proven', '"production_ready":true', '"good', '"score']) {
    assert.ok(!brut.includes(i), `un MATCH ne doit jamais porter « ${i} »`);
  }
  // et la seule mention de qualite dans la chaine reste la negation
  const recettes = JSON.parse(readFileSync('forge/agent_recipes.json', 'utf-8'));
  const cible = recettes.recipes.find((x) => x.id === 'world_scan_repair_v1');
  assert.equal(cible.quality_not_proven, true);
  assert.equal(cible.production_ready, false);
});

test('ADVERSARIAL 5 : apres MISMATCH, exactement UNE invocation', async () => {
  let appels = 0;
  const r = await executerPlan(PLAN_EXEC({ outputs: ['jamais_produit'] }), OPTS_EXEC({
    racine: await racine(),
    executer: async () => { appels += 1; return EXEC_OK(); },
  }));
  assert.equal(r.execution.verdict.match_status, 'MISMATCH');
  assert.equal(appels, 1, 'aucun retry, aucun second essai, aucune reprise');
  // et la trace du MISMATCH est rendue TELLE QUELLE, sans correction
  assert.ok(r.execution.trace.mismatches.length > 0);
  assert.equal(r.execution.trace.match_status, 'MISMATCH');
});

test('ADVERSARIAL 6 : la colonne vertebrale reste la seule voie', () => {
  const src = readFileSync(fileURLToPath(new URL('./agent_factory.mjs', import.meta.url)), 'utf-8');
  const code = src.split('\n').filter((l) => !l.trim().startsWith('//') && !l.trim().startsWith('*')).join('\n');

  // La Factory ne doit appeler AUCUNE fonction de selection : c est le critere qui
  // compte, pas l absence d import. (Elle importe bien `CHEMIN_ROLES` depuis
  // candidate_selector — une CONSTANTE DE CHEMIN, pas une decision. Couplage connu,
  // verrouille par l assertion suivante.)
  for (const f of ['selectionner(', 'selectionnerExecutable(', 'ordonner(', 'preuveAttendue(']) {
    assert.ok(!code.includes(f), `la Factory ne doit pas appeler « ${f} » — elle ne choisit pas`);
  }
  assert.ok(!code.includes('mcts_selector'), 'aucun lien vers le selecteur MCTS');
  const importsSelector = [...code.matchAll(/import \{([^}]*)\} from '\.\/candidate_selector\.mjs'/g)]
    .flatMap((m) => m[1].split(',').map((x) => x.trim()));
  assert.deepEqual(importsSelector, ['CHEMIN_ROLES'],
    'le SEUL emprunt au selecteur est une constante de chemin');

  // mais elle DOIT passer par le binding et par la preuve
  assert.ok(code.includes('execution_binding.mjs'), 'l executabilite est recalculee par le binding');
  assert.ok(code.includes('execution_proof.mjs'), 'l execution passe par la couche de preuve');
});

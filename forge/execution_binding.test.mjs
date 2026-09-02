// Tests de l'Execution Binding V1.
// node --test forge/execution_binding.test.mjs
//
// Aucun réseau, aucun LLM, aucune écriture : trois tests le vérifient — deux sur le
// comportement (déterminisme, aucun fichier créé), un sur la source elle-même.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, writeFile, readdir } from 'node:fs/promises';
import { readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  BLOCKERS, CAPABILITY_STATUS_COMPATIBLE, parseRuntimeContracts, parseContratsDEtape,
  cheminCiteLaMutation, planifier, chargerContexteExecution,
} from './execution_binding.mjs';

const M = (o = {}) => ({
  id: o.id ?? 'M-1',
  root_problem_id: 'P1',
  accepted: o.accepted ?? true,
  evidence_refs: { artifacts: o.preuves ?? ['README.md'] },
  evidence_status: 'VERSIONED',
  status: 'ACCEPTED',
});

const CTX = (o = {}) => ({
  mutations: o.mutations ?? [M()],
  capacites: {
    capabilities: o.capacites ?? [
      { id: 'cap_a', capability_status: 'PROVEN_EXECUTABLE', runtime_role: 'repair_runtime' },
    ],
  },
  recettes: {
    recipes: o.recettes ?? [{
      id: 'r_v1', proven: true, recipe_status: 'EXECUTABLE',
      capability_chain: [{ capability: 'cap_a', evidence: 'M-1' }],
      runtime_roles: [{ capability: 'cap_a', capability_role: 'repair_runtime' }],
    }],
  },
  roles: o.roles ?? new Set(['repair_runtime', 'worldscan']),
  runtime_contracts: o.contrats ?? new Set(['repair_runtime']),
});

async function racine() {
  const dir = await mkdtemp(join(tmpdir(), 'binding-'));
  await writeFile(join(dir, 'README.md'), 'x', 'utf-8');
  return dir;
}

const blockers = (plan) => plan.blockers.map((b) => b.blocker);

// --- le chemin complet ---------------------------------------------------------------

test('mutation valide, chaine complete -> executable=true', async () => {
  const plan = planifier({ mutation_id: 'M-1' }, CTX(), await racine());
  assert.equal(plan.executable, true);
  assert.deepEqual(plan.blockers, []);
  assert.deepEqual(plan.execution_chain.map((c) => c.step),
    ['mutation', 'evidence', 'recipe', 'capability', 'runtime']);
  assert.ok(plan.execution_chain.every((c) => c.ok));
  assert.equal(plan.runtime_status, 'DECLARE_AVEC_CONTRAT_RUNTIME');
  assert.equal(plan.chain_bindings.length, 1);
  assert.equal(plan.composition, false);
});

// --- les huit règles, une par une ----------------------------------------------------

test('mutation inconnue -> mutation_not_found, et AUCUNE cascade', async () => {
  const plan = planifier({ mutation_id: 'JAMAIS_VUE' }, CTX(), await racine());
  assert.deepEqual(blockers(plan), [BLOCKERS.MUTATION_NOT_FOUND]);
  assert.equal(plan.recipe, null, 'sans mutation, aucun maillon n a de sujet');
});

test('mutation non acceptee -> false, avec le motif du registre', async () => {
  const plan = planifier({ mutation_id: 'M-1' },
    CTX({ mutations: [M({ accepted: false })] }), await racine());
  assert.equal(plan.executable, false);
  assert.ok(blockers(plan).includes(BLOCKERS.MUTATION_NOT_ACCEPTED));
});

test('evidence absente -> false (reference vers un fichier inexistant)', async () => {
  const plan = planifier({ mutation_id: 'M-1' },
    CTX({ mutations: [M({ preuves: ['lab/nexiste_pas.json'] })] }), await racine());
  assert.equal(plan.executable, false);
  assert.ok(blockers(plan).includes(BLOCKERS.EVIDENCE_MISSING));
});

test('aucune recette -> recipe_missing, sans blocage en cascade', async () => {
  const plan = planifier({ mutation_id: 'M-1' }, CTX({ recettes: [] }), await racine());
  assert.deepEqual(blockers(plan), [BLOCKERS.RECIPE_MISSING]);
  assert.equal(plan.capability_status, null);
  assert.equal(plan.runtime_status, null, 'un maillon sans adresse n est pas un 2e probleme');
});

test('recette non prouvee -> recipe_not_proven', async () => {
  const plan = planifier({ mutation_id: 'M-1' }, CTX({
    recettes: [{ id: 'r_v1', proven: false, recipe_status: 'BLOCKED',
      capability_chain: [{ capability: 'cap_a', evidence: 'M-1' }],
      runtime_roles: [{ capability: 'cap_a', capability_role: 'repair_runtime' }] }],
  }), await racine());
  assert.equal(plan.executable, false);
  assert.ok(blockers(plan).includes(BLOCKERS.RECIPE_NOT_PROVEN));
});

test('capacite absente du catalogue -> capability_missing', async () => {
  const plan = planifier({ mutation_id: 'M-1' }, CTX({ capacites: [] }), await racine());
  assert.deepEqual(blockers(plan), [BLOCKERS.CAPABILITY_MISSING]);
  assert.equal(plan.runtime_status, null);
});

test('capacite au mauvais statut -> capability_status_incompatible', async () => {
  const plan = planifier({ mutation_id: 'M-1' }, CTX({
    capacites: [{ id: 'cap_a', capability_status: 'MEASURED_NOT_EXECUTABLE',
      runtime_role: 'repair_runtime' }],
  }), await racine());
  assert.equal(plan.executable, false);
  assert.ok(blockers(plan).includes(BLOCKERS.CAPABILITY_STATUS_INCOMPATIBLE));
  assert.ok([...CAPABILITY_STATUS_COMPATIBLE].includes('PROVEN_EXECUTABLE'));
});

test('runtime absent de roles.yaml -> runtime_role_missing', async () => {
  const plan = planifier({ mutation_id: 'M-1' }, CTX({ roles: new Set(['worldscan']) }),
    await racine());
  assert.equal(plan.executable, false);
  assert.equal(plan.runtime_status, 'NON_DECLARE');
  assert.ok(blockers(plan).includes(BLOCKERS.RUNTIME_ROLE_MISSING));
});

test('aucun role assigne -> runtime_role_missing, jamais un role invente', async () => {
  const plan = planifier({ mutation_id: 'M-1' }, CTX({
    capacites: [{ id: 'cap_a', capability_status: 'PROVEN_EXECUTABLE', runtime_role: null }],
    recettes: [{ id: 'r_v1', proven: true,
      capability_chain: [{ capability: 'cap_a', evidence: 'M-1' }],
      runtime_roles: [{ capability: 'cap_a', capability_role: null }] }],
  }), await racine());
  assert.equal(plan.runtime_role, null);
  assert.equal(plan.runtime_status, 'ABSENT');
  assert.ok(blockers(plan).includes(BLOCKERS.RUNTIME_ROLE_MISSING));
});

test('runtime DECLARE mais SANS runtime_contract -> runtime_contract_missing', async () => {
  const plan = planifier({ mutation_id: 'M-1' }, CTX({ contrats: new Set() }), await racine());
  assert.equal(plan.executable, false);
  assert.equal(plan.runtime_status, 'DECLARE_SANS_CONTRAT');
  assert.deepEqual(blockers(plan), [BLOCKERS.RUNTIME_CONTRACT_MISSING]);
});

// --- parsing de roles.yaml ------------------------------------------------------------

test('parseRuntimeContracts ne prend QUE les cles de runtime_contracts', () => {
  const y = [
    'models:', '  - id: x', '    roles:', '      - worldscan',
    'runtime_contracts:', '', '  repair_runtime:', '    mission: >-',
    '      texte', '    inputs: [a, b]', '  autre_role:', '    mission: y',
  ].join('\n');
  assert.deepEqual([...parseRuntimeContracts(y)].sort(), ['autre_role', 'repair_runtime']);
  assert.deepEqual([...parseRuntimeContracts('models:\n  - id: x\n')], []);
});

// --- invariants -----------------------------------------------------------------------

test('DETERMINISME : deux appels identiques rendent exactement la meme chose', async () => {
  const r = await racine();
  assert.deepEqual(planifier({ mutation_id: 'M-1' }, CTX(), r),
    planifier({ mutation_id: 'M-1' }, CTX(), r));
});

test('AUCUN effet fichier : rien n est cree, rien n est modifie', async () => {
  const r = await racine();
  const avant = (await readdir(r)).sort();
  planifier({ mutation_id: 'M-1' }, CTX(), r);
  planifier({ mutation_id: 'INCONNUE' }, CTX(), r);
  assert.deepEqual((await readdir(r)).sort(), avant);
});

test('AUCUN reseau, AUCUN LLM, AUCUNE ecriture : verifie sur la source', () => {
  const src = readFileSync(fileURLToPath(new URL('./execution_binding.mjs', import.meta.url)), 'utf-8');
  const code = src.split('\n').filter((l) => !l.trim().startsWith('//') && !l.trim().startsWith('*')).join('\n');
  for (const interdit of ['fetch(', 'localhost', 'http', 'subprocess', 'child_process',
    'spawn(', 'writeFile', 'appendFile', 'mkdir(']) {
    assert.ok(!code.includes(interdit), `le binding ne doit pas contenir « ${interdit} »`);
  }
});

test('il ne SELECTIONNE pas : une mutation refusee est evaluee, pas ecartee', async () => {
  const plan = planifier({ mutation_id: 'M-1' },
    CTX({ mutations: [M({ accepted: false })] }), await racine());
  assert.equal(plan.recipe, 'r_v1',
    'le binding remonte la chaine meme pour une mutation refusee — trier est le role du selecteur');
});

// --- le dépôt réel ---------------------------------------------------------------------


test('mutation couverte par evidence_requirements SEULEMENT -> executable=true', async () => {
  // Le faux negatif corrige le 2026-08-04 : la recette EXIGE cette preuve, donc elle
  // couvre la mutation, meme si capability_chain[].evidence ne la cite pas.
  const plan = planifier({ mutation_id: 'M-compo' }, CTX({
    mutations: [M({ id: 'M-compo' })],
    recettes: [{
      id: 'r_v1', proven: true, recipe_status: 'EXECUTABLE',
      capability_chain: [{ capability: 'cap_a', evidence: 'M-autre' }],
      runtime_roles: [{ capability: 'cap_a', capability_role: 'repair_runtime' }],
      evidence_requirements: ['EVIDENCE/bundles/X/M-compo/measured_metrics.json'],
    }],
  }), await racine());
  assert.equal(plan.executable, true, JSON.stringify(plan.blockers));
  assert.equal(plan.recipe, 'r_v1');
});

test('une mutation REELLEMENT absente reste recipe_missing', async () => {
  const plan = planifier({ mutation_id: 'M-orpheline' }, CTX({
    mutations: [M({ id: 'M-orpheline' })],
    recettes: [{
      id: 'r_v1', proven: true,
      capability_chain: [{ capability: 'cap_a', evidence: 'M-autre' }],
      runtime_roles: [{ capability: 'cap_a', capability_role: 'repair_runtime' }],
      evidence_requirements: ['EVIDENCE/bundles/X/M-autre/measured_metrics.json'],
    }],
  }), await racine());
  assert.deepEqual(blockers(plan), [BLOCKERS.RECIPE_MISSING]);
});

test('cheminCiteLaMutation compare des SEGMENTS, jamais des sous-chaines', () => {
  assert.equal(cheminCiteLaMutation('EVIDENCE/bundles/P/M-ws6/m.json', 'M-ws6'), true);
  assert.equal(cheminCiteLaMutation(String.raw`EVIDENCE\bundles\P\M-ws6\m.json`, 'M-ws6'), true);
  assert.equal(cheminCiteLaMutation('EVIDENCE/bundles/P/M-ws60/m.json', 'M-ws6'), false,
    'une correspondance approximative rendrait executable une mutation qui ne l est pas');
});

test('une COMPOSITION exige que TOUS ses maillons tiennent', async () => {
  const plan = planifier({ mutation_id: 'M-compo' }, CTX({
    mutations: [M({ id: 'M-compo' })],
    capacites: [
      { id: 'cap_a', capability_status: 'PROVEN_EXECUTABLE', runtime_role: 'repair_runtime' },
      { id: 'cap_b', capability_status: 'MEASURED_NOT_EXECUTABLE', runtime_role: 'repair_runtime' },
    ],
    recettes: [{
      id: 'r_v1', proven: true,
      capability_chain: [{ capability: 'cap_a', evidence: 'M-x' }, { capability: 'cap_b', evidence: 'M-y' }],
      runtime_roles: [{ capability: 'cap_a', capability_role: 'repair_runtime' },
        { capability: 'cap_b', capability_role: 'repair_runtime' }],
      evidence_requirements: ['EVIDENCE/bundles/X/M-compo/m.json'],
    }],
  }), await racine());
  assert.equal(plan.composition, true);
  assert.equal(plan.chain_bindings.length, 2);
  assert.equal(plan.executable, false, 'le second maillon ne tient pas');
  assert.ok(blockers(plan).includes(BLOCKERS.CAPABILITY_STATUS_INCOMPATIBLE));
});

test('parseContratsDEtape rattache un role a son contrat d etape', async () => {
  const m = await parseContratsDEtape('forge/contracts');
  assert.ok(m.has('worldscan'), 'worldscan est declare par un contrat d etape');
  assert.ok(!m.has('repair_runtime'), 'repair_runtime n est PAS une etape de chaine');
});

// --- le dépôt réel ---------------------------------------------------------------------

test('DEPOT REEL : les 4 chemins attendus sont executables', async () => {
  const ctx = await chargerContexteExecution();
  for (const id of ['REPAIR-LOOP-V1', 'M-ws6', 'Q1-DISCRIMINANCE', 'M-Q5-A']) {
    const plan = planifier({ mutation_id: id }, ctx);
    assert.equal(plan.executable, true, `${id}: ${JSON.stringify(plan.blockers)}`);
  }
});

test('DEPOT REEL : M-ws6 passe par la recette, en COMPOSITION', async () => {
  const plan = planifier({ mutation_id: 'M-ws6' }, await chargerContexteExecution());
  assert.equal(plan.recipe, 'world_scan_repair_v1');
  assert.equal(plan.composition, true);
  assert.deepEqual(plan.chain_bindings.map((b) => b.capability),
    ['instance_separation', 'targeted_field_repair']);
  // worldscan porte son contrat d ETAPE, repair_runtime son contrat de RUNTIME
  assert.deepEqual(plan.chain_bindings.map((b) => b.runtime_status),
    ['DECLARE_AVEC_CONTRAT_ETAPE', 'DECLARE_AVEC_CONTRAT_RUNTIME']);
});

test('DEPOT REEL : M-ws5 reste bloquee — non acceptee', async () => {
  const plan = planifier({ mutation_id: 'M-ws5' }, await chargerContexteExecution());
  assert.equal(plan.executable, false);
  assert.deepEqual(blockers(plan), [BLOCKERS.MUTATION_NOT_ACCEPTED]);
});

test('DEPOT REEL : les mutations internes restent recipe_missing', async () => {
  const ctx = await chargerContexteExecution();
  for (const id of ['Q2-LANGUE', 'Q3-RECOPIE', 'M-rep-par-champ', 'M-schema-claim']) {
    const plan = planifier({ mutation_id: id }, ctx);
    assert.equal(plan.executable, false, id);
    assert.ok(blockers(plan).includes(BLOCKERS.RECIPE_MISSING), id);
  }
});

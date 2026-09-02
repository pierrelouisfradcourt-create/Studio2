// Tests du MCTS Selector V0.
// node --test forge/mcts_selector.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { ECARTES, preuveAttendue, selectionnerExecutable } from './mcts_selector.mjs';
import { chargerContexteExecution } from './execution_binding.mjs';

const PROBLEMES = ['REPAIR_NON_CONVERGENCE', 'ORACLE_FALSE_NEGATIVE',
  'DEFECT_DISPLACEMENT', 'PROMPT_FIELD_OMISSION'];

test('il ne rend QUE des chemins executables', async () => {
  const ctx = await chargerContexteExecution();
  for (const p of PROBLEMES) {
    const r = selectionnerExecutable({ root_problem_id: p }, ctx);
    assert.ok(r.executable_candidates.length >= 1, `${p} : aucun chemin`);
    for (const c of r.executable_candidates) {
      assert.ok(c.recipe, 'un chemin executable a une recette');
      assert.ok(c.capability.length >= 1);
      assert.ok(c.runtime.every((x) => x !== null), 'aucun runtime null dans un chemin retenu');
    }
  }
});

test('un candidat classe premier mais sans chemin est ECARTE, pas silencieux', async () => {
  const ctx = await chargerContexteExecution();
  const r = selectionnerExecutable({ root_problem_id: 'ORACLE_FALSE_NEGATIVE' }, ctx);
  const ecartes = r.discarded_not_executable.map((x) => x.mutation_id);
  assert.ok(ecartes.includes('Q2-LANGUE') && ecartes.includes('Q3-RECOPIE'));
  assert.ok(r.discarded_not_executable.every((x) => x.motif === ECARTES.NON_EXECUTABLE));
  assert.ok(r.discarded_not_executable.every((x) => x.blockers.includes('recipe_missing')),
    'le motif exact est conserve, jamais reduit a « ecarte »');
});

test('chaque chemin porte la preuve qu il devra produire', async () => {
  const ctx = await chargerContexteExecution();
  const r = selectionnerExecutable({ root_problem_id: 'REPAIR_NON_CONVERGENCE' }, ctx);
  const p = r.executable_candidates[0].expected_proof;
  assert.ok(p.evidence_requirements.length > 0);
  assert.ok(p.validation_contract.objective_metric);
  assert.ok(p.validation_contract.oracle);
});

test('preuveAttendue lit la recette, n invente rien', async () => {
  const ctx = await chargerContexteExecution();
  assert.equal(preuveAttendue('recette_inexistante', ctx), null);
  const p = preuveAttendue('duplicate_content_gate_v1', ctx);
  assert.ok(p.evidence_requirements.every((f) => f.startsWith('EVIDENCE/bundles/')));
});

test('une COMPOSITION expose tous ses maillons', async () => {
  const ctx = await chargerContexteExecution();
  const r = selectionnerExecutable({ root_problem_id: 'PROMPT_FIELD_OMISSION' }, ctx);
  const c = r.executable_candidates[0];
  assert.equal(c.mutation_id, 'M-ws6');
  assert.equal(c.composition, true);
  assert.deepEqual(c.capability, ['instance_separation', 'targeted_field_repair']);
  assert.deepEqual(c.runtime, ['worldscan', 'repair_runtime']);
});

test('le facteur de branchement est MESURE, et l exploration declaree ABSENTE', async () => {
  const ctx = await chargerContexteExecution();
  for (const p of PROBLEMES) {
    const r = selectionnerExecutable({ root_problem_id: p }, ctx);
    assert.equal(r.selection_basis.branching_factor, r.executable_candidates.length);
    assert.equal(r.selection_basis.exploration, 'AUCUNE (V0 deterministe)');
    assert.ok(r.reasoning.some((l) => /facteur de branchement/.test(l)));
  }
});

test('AUCUN score, AUCUNE agregation cachee', async () => {
  const ctx = await chargerContexteExecution();
  const brut = JSON.stringify(selectionnerExecutable(
    { root_problem_id: 'REPAIR_NON_CONVERGENCE' }, ctx)).toLowerCase();
  for (const interdit of ['"score', '"reward"', '"fitness', '"rank', '"weight', '"total']) {
    assert.ok(!brut.includes(interdit), `champ interdit : ${interdit}`);
  }
});

test('AUCUN LLM, AUCUN reseau, AUCUNE ecriture : verifie sur la source', () => {
  const src = readFileSync(fileURLToPath(new URL('./mcts_selector.mjs', import.meta.url)), 'utf-8');
  const code = src.split('\n').filter((l) => !l.trim().startsWith('//')).join('\n');
  for (const i of ['fetch(', 'localhost', 'subprocess', 'child_process', 'spawn(',
    'writeFile', 'appendFile', 'mkdir(']) {
    assert.ok(!code.includes(i), `le selecteur ne doit pas contenir « ${i} »`);
  }
});

test('DETERMINISME : deux appels rendent exactement la meme chose', async () => {
  const ctx = await chargerContexteExecution();
  const req = { root_problem_id: 'DEFECT_DISPLACEMENT' };
  assert.deepEqual(selectionnerExecutable(req, ctx), selectionnerExecutable(req, ctx));
});

test('root_problem inconnu : aucun chemin, erreur nommee conservee', async () => {
  const ctx = await chargerContexteExecution();
  const r = selectionnerExecutable({ root_problem_id: 'JAMAIS_VU' }, ctx);
  assert.deepEqual(r.executable_candidates, []);
  assert.equal(r.selection_basis.error, 'ROOT_PROBLEM_NOT_FOUND');
});

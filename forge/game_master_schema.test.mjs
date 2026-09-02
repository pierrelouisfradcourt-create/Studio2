// Tests de game_master_schema.mjs (validateur + projection deterministe du bloc
// `game_master` de gm_worldscan.json, Lot B 2026-08-23).
// node --test forge/game_master_schema.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import {
  validateGameMaster, projectEconomy, LOOP_NAMES, STEP_KINDS,
  METRIC_KINDS, PROOF_HOW, BLOCK_TYPES, BLOCK_ROLES, BLOCK_STATES,
} from './game_master_schema.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(__dirname, '..');
const FIXTURE_VALID = resolve(__dirname, 'tests', 'fixtures', 'gm_game_master_valid.json');
const RUN9_GM_WORLDSCAN = resolve(
  REPO_ROOT, 'EVIDENCE', 'runs', 'kitten_clicker', '_run9_20260823a', 'gm_worldscan.json',
);

function loadValidFixture() {
  return JSON.parse(readFileSync(FIXTURE_VALID, 'utf-8'));
}

function deepClone(obj) {
  return JSON.parse(JSON.stringify(obj));
}

// --- vocabulaire ------------------------------------------------------------

test('vocabulaire ferme : 9 boucles, kinds, block types/roles/states', () => {
  assert.deepEqual(LOOP_NAMES, [
    'core_loop', 'gameplay_loop', 'progression_loop', 'content_loop',
    'economy_loop', 'skill_loop', 'world_loop', 'quest_loop', 'meta_loop',
  ]);
  assert.deepEqual(STEP_KINDS, ['action', 'feedback', 'reward', 'progression', 'decision', 'other']);
  assert.deepEqual(METRIC_KINDS, ['invariant', 'target', 'observation']);
  assert.deepEqual(PROOF_HOW, ['player_loop', 'decision', 'registry', 'hud', 'humangate']);
  assert.deepEqual(BLOCK_TYPES, ['LOCATION', 'ACTOR', 'ITEM', 'RULE', 'UI', 'RESOURCE']);
  assert.deepEqual(BLOCK_ROLES, ['PROGRESSION_GATE', 'AFFORDANCE', 'FEEDBACK', 'REWARD', 'CONTENT', 'META']);
  assert.deepEqual(BLOCK_STATES, ['LOCKED', 'AVAILABLE', 'OWNED', 'PLACED', 'CONSUMED']);
});

// --- fixture synthetique complete valide ------------------------------------

test('fixture synthetique clicker a chatons COMPLETE : ok, 0 probleme', () => {
  const gm = loadValidFixture();
  const result = validateGameMaster(gm);
  assert.deepEqual(result.problems, []);
  assert.equal(result.ok, true);
});

// --- run 9 reel : game_master absent ----------------------------------------

test('run 9 (fixture reelle, anterieure au Lot B) : game_master absent', () => {
  const data = JSON.parse(readFileSync(RUN9_GM_WORLDSCAN, 'utf-8'));
  assert.ok(!('game_master' in data));
  const result = validateGameMaster(data.game_master);
  assert.equal(result.ok, false);
  assert.ok(result.problems.some((p) => p.includes('absent')));
});

// --- determinisme de projectEconomy -----------------------------------------

test('projectEconomy : deterministe, hash identique sur 2 appels', () => {
  const gm = loadValidFixture();
  const a = JSON.stringify(projectEconomy(gm));
  const b = JSON.stringify(projectEconomy(gm));
  assert.equal(a, b);
});

test('projectEconomy : forme attendue, trie par id', () => {
  const gm = loadValidFixture();
  const economy = projectEconomy(gm);
  assert.equal(economy.schema_version, 1);
  assert.deepEqual(economy.resources.map((r) => r.id), ['chatons']);
  assert.deepEqual(economy.formulas.map((f) => f.id), ['cout_cursor']);
  assert.deepEqual(economy.invariants.map((i) => i.id), [
    'economy_transformations_per_spend', 'world_playable_location_ratio',
  ]);
  assert.equal(economy.invariants[0].value, 1);
  assert.equal(economy.invariants[0].unit, 'transformation');
});

// --- 1 cas rouge par regle ---------------------------------------------------

test('world_interpretation absent : refus', () => {
  const gm = deepClone(loadValidFixture());
  delete gm.world_interpretation;
  const result = validateGameMaster(gm);
  assert.equal(result.ok, false);
  assert.ok(result.problems.some((p) => p.includes('world_interpretation')));
});

test('world_interpretation < 3 faits : refus', () => {
  const gm = deepClone(loadValidFixture());
  gm.world_interpretation = gm.world_interpretation.slice(0, 2);
  const result = validateGameMaster(gm);
  assert.equal(result.ok, false);
  assert.ok(result.problems.some((p) => p.includes('world_interpretation')));
});

test('world_interpretation source sans prefixe valide : refus nommant l\'index', () => {
  const gm = deepClone(loadValidFixture());
  gm.world_interpretation[0].source = 'invalid:foo';
  const result = validateGameMaster(gm);
  assert.equal(result.ok, false);
  assert.ok(result.problems.some((p) => p.includes('world_interpretation[0]') && p.includes('source')));
});

test('loops : boucle manquante refusee', () => {
  const gm = deepClone(loadValidFixture());
  delete gm.loops.meta_loop;
  const result = validateGameMaster(gm);
  assert.equal(result.ok, false);
  assert.ok(result.problems.some((p) => p.includes('loops.meta_loop')));
});

test('loops : boucle vide refusee', () => {
  const gm = deepClone(loadValidFixture());
  gm.loops.content_loop.steps = [];
  const result = validateGameMaster(gm);
  assert.equal(result.ok, false);
  assert.ok(result.problems.some((p) => p.includes('loops.content_loop.steps')));
});

test('loops : ordre relatif viole (reward avant action) refuse', () => {
  const gm = deepClone(loadValidFixture());
  gm.loops.core_loop.steps[0].kind = 'reward'; // etait 'action'
  const result = validateGameMaster(gm);
  assert.equal(result.ok, false);
  assert.ok(result.problems.some((p) => p.includes('loops.core_loop.steps') && p.includes("kind 'action'")));
});

test('loops : id de step duplique refuse', () => {
  const gm = deepClone(loadValidFixture());
  gm.loops.core_loop.steps[1].id = gm.loops.core_loop.steps[0].id;
  const result = validateGameMaster(gm);
  assert.equal(result.ok, false);
  assert.ok(result.problems.some((p) => p.includes('duplique')));
});

test('loops : actor invalide refuse', () => {
  const gm = deepClone(loadValidFixture());
  gm.loops.core_loop.steps[0].actor = 'NPC';
  const result = validateGameMaster(gm);
  assert.equal(result.ok, false);
  assert.ok(result.problems.some((p) => p.includes("'actor'")));
});

test('loops : why vide refuse', () => {
  const gm = deepClone(loadValidFixture());
  gm.loops.core_loop.steps[0].why = '';
  const result = validateGameMaster(gm);
  assert.equal(result.ok, false);
  assert.ok(result.problems.some((p) => p.includes("'why'")));
});

test('loops : metric_ref inexistant refuse', () => {
  const gm = deepClone(loadValidFixture());
  gm.loops.core_loop.steps[0].metric_ref = 'ne_existe_pas';
  const result = validateGameMaster(gm);
  assert.equal(result.ok, false);
  assert.ok(result.problems.some((p) => p.includes('metric_ref') && p.includes('ne_existe_pas')));
});

test('loops : proof_ref inexistant refuse', () => {
  const gm = deepClone(loadValidFixture());
  gm.loops.core_loop.steps[0].proof_ref = 'ne_existe_pas';
  const result = validateGameMaster(gm);
  assert.equal(result.ok, false);
  assert.ok(result.problems.some((p) => p.includes('proof_ref') && p.includes('ne_existe_pas')));
});

// --- Lot C.4-code : produces/consumes/unlocks, transformation_perceptible, metric_propre --

test('loops : boucle qui n\'est pas un objet refusee', () => {
  const gm = deepClone(loadValidFixture());
  gm.loops.core_loop = [gm.loops.core_loop.steps[0]];
  const result = validateGameMaster(gm);
  assert.equal(result.ok, false);
  assert.ok(result.problems.some((p) => p.includes('loops.core_loop') && p.includes('objet')));
});

test('loops : produces manquant refuse', () => {
  const gm = deepClone(loadValidFixture());
  delete gm.loops.core_loop.produces;
  const result = validateGameMaster(gm);
  assert.equal(result.ok, false);
  assert.ok(result.problems.some((p) => p.includes('loops.core_loop.produces')));
});

test('loops : consumes referencant un nom de boucle inexistant refuse', () => {
  const gm = deepClone(loadValidFixture());
  gm.loops.core_loop.consumes = ['boucle_qui_nexiste_pas'];
  const result = validateGameMaster(gm);
  assert.equal(result.ok, false);
  assert.ok(result.problems.some((p) => p.includes('loops.core_loop.consumes')));
});

test('loops : unlocks referencant un nom de boucle inexistant refuse', () => {
  const gm = deepClone(loadValidFixture());
  gm.loops.core_loop.unlocks = ['boucle_qui_nexiste_pas'];
  const result = validateGameMaster(gm);
  assert.equal(result.ok, false);
  assert.ok(result.problems.some((p) => p.includes('loops.core_loop.unlocks')));
});

test('R2a : produces orphelin (aucune autre boucle ne le consomme) refuse en nommant la boucle', () => {
  const gm = deepClone(loadValidFixture());
  // gameplay_loop est la SEULE boucle qui consomme core_loop -- on la retire.
  gm.loops.gameplay_loop.consumes = gm.loops.gameplay_loop.consumes.filter((c) => c !== 'core_loop');
  const result = validateGameMaster(gm);
  assert.equal(result.ok, false);
  assert.ok(result.problems.some((p) => p.includes('loops.core_loop') && p.includes('orpheline')));
});

test('R2b : transformation_perceptible.text vide refuse', () => {
  const gm = deepClone(loadValidFixture());
  gm.loops.core_loop.transformation_perceptible.text = '';
  const result = validateGameMaster(gm);
  assert.equal(result.ok, false);
  assert.ok(result.problems.some((p) => p.includes('transformation_perceptible.text')));
});

test('R2b : transformation_perceptible.proof_ref dont how=humangate seul refuse', () => {
  const gm = deepClone(loadValidFixture());
  gm.proof_model.push({
    id: 'proof_humangate_only', measures: 'core_reactions_per_caress',
    how: 'humangate', expected: 'avis HumanGate',
  });
  gm.loops.core_loop.transformation_perceptible.proof_ref = 'proof_humangate_only';
  const result = validateGameMaster(gm);
  assert.equal(result.ok, false);
  assert.ok(result.problems.some((p) => p.includes('transformation_perceptible.proof_ref') && p.includes('humangate')));
});

test('R2b : transformation_perceptible.proof_ref inexistant refuse', () => {
  const gm = deepClone(loadValidFixture());
  gm.loops.core_loop.transformation_perceptible.proof_ref = 'ne_existe_pas';
  const result = validateGameMaster(gm);
  assert.equal(result.ok, false);
  assert.ok(result.problems.some((p) => p.includes('transformation_perceptible.proof_ref') && p.includes('ne_existe_pas')));
});

test('metric_propre : absent refuse', () => {
  const gm = deepClone(loadValidFixture());
  delete gm.loops.core_loop.metric_propre;
  const result = validateGameMaster(gm);
  assert.equal(result.ok, false);
  assert.ok(result.problems.some((p) => p.includes('loops.core_loop.metric_propre')));
});

test('metric_propre : id inexistant dans progression_metrics refuse', () => {
  const gm = deepClone(loadValidFixture());
  gm.loops.core_loop.metric_propre = 'ne_existe_pas';
  const result = validateGameMaster(gm);
  assert.equal(result.ok, false);
  assert.ok(result.problems.some((p) => p.includes('metric_propre') && p.includes('ne_existe_pas')));
});

test('metric_propre : partage entre deux boucles (metric_propre <-> metric_propre) refuse', () => {
  const gm = deepClone(loadValidFixture());
  gm.loops.gameplay_loop.metric_propre = gm.loops.core_loop.metric_propre;
  const result = validateGameMaster(gm);
  assert.equal(result.ok, false);
  assert.ok(result.problems.some((p) => p.includes('metric_propre') && p.includes('partagee')));
});

test('metric_propre : deja utilisee comme metric_ref dans une autre boucle refuse', () => {
  const gm = deepClone(loadValidFixture());
  gm.loops.gameplay_loop.steps[0].metric_ref = gm.loops.core_loop.metric_propre;
  const result = validateGameMaster(gm);
  assert.equal(result.ok, false);
  assert.ok(result.problems.some((p) => p.includes('metric_propre') && p.includes('gameplay_loop')));
});

test('progression_metrics : absent refuse', () => {
  const gm = deepClone(loadValidFixture());
  delete gm.progression_metrics;
  const result = validateGameMaster(gm);
  assert.equal(result.ok, false);
  assert.ok(result.problems.some((p) => p.includes('progression_metrics')));
});

test('progression_metrics : id duplique refuse', () => {
  const gm = deepClone(loadValidFixture());
  gm.progression_metrics.push({ ...gm.progression_metrics[0] });
  const result = validateGameMaster(gm);
  assert.equal(result.ok, false);
  assert.ok(result.problems.some((p) => p.includes('duplique')));
});

test('progression_metrics : invariant sans value numerique refuse', () => {
  const gm = deepClone(loadValidFixture());
  const inv = gm.progression_metrics.find((m) => m.kind === 'invariant');
  delete inv.value;
  const result = validateGameMaster(gm);
  assert.equal(result.ok, false);
  assert.ok(result.problems.some((p) => p.includes('invariant') && p.includes('value')));
});

test('progression_metrics : target avec range.min >= range.max refuse', () => {
  const gm = deepClone(loadValidFixture());
  const tgt = gm.progression_metrics.find((m) => m.kind === 'target');
  tgt.range = { min: 200, max: 100 };
  const result = validateGameMaster(gm);
  assert.equal(result.ok, false);
  assert.ok(result.problems.some((p) => p.includes('target') && p.includes('range')));
});

test('progression_metrics : observation sans unit refuse', () => {
  const gm = deepClone(loadValidFixture());
  const obs = gm.progression_metrics.find((m) => m.kind === 'observation');
  delete obs.unit;
  const result = validateGameMaster(gm);
  assert.equal(result.ok, false);
  assert.ok(result.problems.some((p) => p.includes('observation') && p.includes('unit')));
});

test('progression_metrics : aucun invariant refuse', () => {
  const gm = deepClone(loadValidFixture());
  gm.progression_metrics = gm.progression_metrics.filter((m) => m.kind !== 'invariant');
  const result = validateGameMaster(gm);
  assert.equal(result.ok, false);
  assert.ok(result.problems.some((p) => p.includes('invariant')));
});

test('progression_metrics : aucun target refuse', () => {
  const gm = deepClone(loadValidFixture());
  gm.progression_metrics = gm.progression_metrics.filter((m) => m.kind !== 'target');
  const result = validateGameMaster(gm);
  assert.equal(result.ok, false);
  assert.ok(result.problems.some((p) => p.includes('target')));
});

test('progression_metrics : why vide refuse', () => {
  const gm = deepClone(loadValidFixture());
  gm.progression_metrics[0].why = '';
  const result = validateGameMaster(gm);
  assert.equal(result.ok, false);
  assert.ok(result.problems.some((p) => p.includes("'why'")));
});

test('proof_model : absent refuse', () => {
  const gm = deepClone(loadValidFixture());
  delete gm.proof_model;
  const result = validateGameMaster(gm);
  assert.equal(result.ok, false);
  assert.ok(result.problems.some((p) => p.includes('proof_model')));
});

test('proof_model : how invalide refuse', () => {
  const gm = deepClone(loadValidFixture());
  gm.proof_model[0].how = 'oracle_llm';
  const result = validateGameMaster(gm);
  assert.equal(result.ok, false);
  assert.ok(result.problems.some((p) => p.includes("'how'")));
});

test('proof_model : expected vide refuse', () => {
  const gm = deepClone(loadValidFixture());
  gm.proof_model[0].expected = '';
  const result = validateGameMaster(gm);
  assert.equal(result.ok, false);
  assert.ok(result.problems.some((p) => p.includes("'expected'")));
});

test('proof_model : metrique invariant/target non mesuree refusee', () => {
  const gm = deepClone(loadValidFixture());
  gm.proof_model = gm.proof_model.filter((p) => p.measures !== 'economy_transformations_per_spend');
  const result = validateGameMaster(gm);
  assert.equal(result.ok, false);
  assert.ok(result.problems.some((p) => p.includes('economy_transformations_per_spend') && p.includes('mesuree')));
});

test('economy_model : absent refuse', () => {
  const gm = deepClone(loadValidFixture());
  delete gm.economy_model;
  const result = validateGameMaster(gm);
  assert.equal(result.ok, false);
  assert.ok(result.problems.some((p) => p.includes('economy_model')));
});

test('economy_model : resource sans initial_stock numerique refuse', () => {
  const gm = deepClone(loadValidFixture());
  delete gm.economy_model.resources[0].initial_stock;
  const result = validateGameMaster(gm);
  assert.equal(result.ok, false);
  assert.ok(result.problems.some((p) => p.includes('initial_stock')));
});

test('economy_model : resource dupliquee refusee', () => {
  const gm = deepClone(loadValidFixture());
  gm.economy_model.resources.push({ ...gm.economy_model.resources[0] });
  const result = validateGameMaster(gm);
  assert.equal(result.ok, false);
  assert.ok(result.problems.some((p) => p.includes('resources') && p.includes('duplique')));
});

test('economy_model : formule sans text refusee', () => {
  const gm = deepClone(loadValidFixture());
  delete gm.economy_model.formulas[0].text;
  const result = validateGameMaster(gm);
  assert.equal(result.ok, false);
  assert.ok(result.problems.some((p) => p.includes('formulas') && p.includes('text')));
});

test('loops : resource referencee inexistante refusee', () => {
  const gm = deepClone(loadValidFixture());
  gm.loops.economy_loop.steps[0].resource = 'ne_existe_pas';
  const result = validateGameMaster(gm);
  assert.equal(result.ok, false);
  assert.ok(result.problems.some((p) => p.includes("'resource'") && p.includes('ne_existe_pas')));
});

test('grey_blocks : absent refuse', () => {
  const gm = deepClone(loadValidFixture());
  delete gm.grey_blocks;
  const result = validateGameMaster(gm);
  assert.equal(result.ok, false);
  assert.ok(result.problems.some((p) => p.includes('grey_blocks')));
});

test('grey_blocks : type invalide refuse', () => {
  const gm = deepClone(loadValidFixture());
  gm.grey_blocks[0].type = 'PORTAL';
  const result = validateGameMaster(gm);
  assert.equal(result.ok, false);
  assert.ok(result.problems.some((p) => p.includes("'type'")));
});

test('grey_blocks : role invalide refuse', () => {
  const gm = deepClone(loadValidFixture());
  gm.grey_blocks[0].role = 'BOSS';
  const result = validateGameMaster(gm);
  assert.equal(result.ok, false);
  assert.ok(result.problems.some((p) => p.includes("'role'")));
});

test('grey_blocks : state invalide refuse', () => {
  const gm = deepClone(loadValidFixture());
  gm.grey_blocks[0].state = 'DESTROYED';
  const result = validateGameMaster(gm);
  assert.equal(result.ok, false);
  assert.ok(result.problems.some((p) => p.includes("'state'")));
});

test('grey_blocks : requires reference id inexistant refuse', () => {
  const gm = deepClone(loadValidFixture());
  gm.grey_blocks[0].requires = ['ne_existe_pas'];
  const result = validateGameMaster(gm);
  assert.equal(result.ok, false);
  assert.ok(result.problems.some((p) => p.includes('requires') && p.includes('ne_existe_pas')));
});

test('grey_blocks : proof_ref inexistant refuse', () => {
  const gm = deepClone(loadValidFixture());
  gm.grey_blocks[0].proof_ref = 'ne_existe_pas';
  const result = validateGameMaster(gm);
  assert.equal(result.ok, false);
  assert.ok(result.problems.some((p) => p.includes('proof_ref') && p.includes('ne_existe_pas')));
});

test('grey_blocks : player_meaning vide refuse', () => {
  const gm = deepClone(loadValidFixture());
  gm.grey_blocks[0].player_meaning = '';
  const result = validateGameMaster(gm);
  assert.equal(result.ok, false);
  assert.ok(result.problems.some((p) => p.includes('player_meaning')));
});

// --- Lot D (2026-08-23, GO Pierre, contrat s2.7 C.2) : grey_blocks.unlock / next_goal,
// champs ADDITIFS OPTIONNELS — la fixture existante (sans ces champs) reste valide. ---

test('grey_blocks : unlock/next_goal absents (fixture existante) : toujours ok', () => {
  const gm = loadValidFixture();
  assert.ok(gm.grey_blocks.every((b) => b.unlock === undefined && b.next_goal === undefined));
  const result = validateGameMaster(gm);
  assert.deepEqual(result.problems, []);
  assert.equal(result.ok, true);
});

test('grey_blocks : unlock present referencant un id de grey_block existant : ok', () => {
  const gm = deepClone(loadValidFixture());
  gm.grey_blocks[0].unlock = ['cursor'];
  gm.grey_blocks[0].next_goal = 'Debloquer le curseur automatique.';
  const result = validateGameMaster(gm);
  assert.deepEqual(result.problems, []);
  assert.equal(result.ok, true);
});

test('grey_blocks : unlock referencant un id inexistant (ni grey_block ni affordance) : refus nomme', () => {
  const gm = deepClone(loadValidFixture());
  gm.grey_blocks[0].unlock = ['id_qui_nexiste_pas'];
  const result = validateGameMaster(gm);
  assert.equal(result.ok, false);
  assert.ok(result.problems.some((p) => p.includes('unlock') && p.includes('id_qui_nexiste_pas')));
});

test('grey_blocks : unlock non-tableau refuse', () => {
  const gm = deepClone(loadValidFixture());
  gm.grey_blocks[0].unlock = 'cursor';
  const result = validateGameMaster(gm);
  assert.equal(result.ok, false);
  assert.ok(result.problems.some((p) => p.includes('unlock')));
});

test('grey_blocks : next_goal vide (non-string) refuse', () => {
  const gm = deepClone(loadValidFixture());
  gm.grey_blocks[0].next_goal = 123;
  const result = validateGameMaster(gm);
  assert.equal(result.ok, false);
  assert.ok(result.problems.some((p) => p.includes('next_goal')));
});

test('artist_requirements : absent refuse', () => {
  const gm = deepClone(loadValidFixture());
  delete gm.artist_requirements;
  const result = validateGameMaster(gm);
  assert.equal(result.ok, false);
  assert.ok(result.problems.some((p) => p.includes('artist_requirements')));
});

test('artist_requirements : grey_block inexistant refuse', () => {
  const gm = deepClone(loadValidFixture());
  gm.artist_requirements[0].grey_block = 'ne_existe_pas';
  const result = validateGameMaster(gm);
  assert.equal(result.ok, false);
  assert.ok(result.problems.some((p) => p.includes('grey_block') && p.includes('ne_existe_pas')));
});

test('artist_requirements : states_to_show vide refuse', () => {
  const gm = deepClone(loadValidFixture());
  gm.artist_requirements[0].states_to_show = [];
  const result = validateGameMaster(gm);
  assert.equal(result.ok, false);
  assert.ok(result.problems.some((p) => p.includes('states_to_show')));
});

test('artist_requirements : visible_reason non booleen refuse', () => {
  const gm = deepClone(loadValidFixture());
  gm.artist_requirements[0].visible_reason = 'oui';
  const result = validateGameMaster(gm);
  assert.equal(result.ok, false);
  assert.ok(result.problems.some((p) => p.includes('visible_reason')));
});

test('artist_requirements : couverture manquante pour un grey_block LOCATION refusee', () => {
  const gm = deepClone(loadValidFixture());
  gm.artist_requirements = gm.artist_requirements.filter((a) => a.grey_block !== 'garden');
  const result = validateGameMaster(gm);
  assert.equal(result.ok, false);
  assert.ok(result.problems.some((p) => p.includes("'garden'") && p.includes('artist_requirements')));
});

test('game_master absent (undefined) : refus nommant "absent"', () => {
  const result = validateGameMaster(undefined);
  assert.equal(result.ok, false);
  assert.ok(result.problems.some((p) => p.includes('absent')));
});

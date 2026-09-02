// forge/check_amont_traversal.test.mjs
// node --test forge/check_amont_traversal.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync, mkdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import {
  factAddresses, canonicalize, traverse, loadRunDir, STAGES,
} from './check_amont_traversal.mjs';

function worldscan() {
  return { games: [{ game: 'Cookie Clicker', loops: { minute_1: 'click', minute_10: 'buy grandma' },
    objectives: [{ mode: 'endless', victory_condition: null, defeat_condition: null,
      player_goal: 'maximise cookies' },
      { mode: 'ascension', victory_condition: 'reach 1e12 cookies', defeat_condition: 'none', player_goal: 'prestige' }] }] };
}
function gm() {
  return { genre: 'clicker', games_observed: [], dimensions: [
    { id: 'progression', status: 'MEASURED', variables: [{ name: 'tiers', value: '10' }] },
    { id: 'bonus', status: 'NOT_MEASURED', variables: [] }] };
}
function story() {
  return { game_id: 'kc', inputs_recus: { worldscan: true, charter: true }, sections: [
    { id: 'stakes', status: 'GROUNDED', reason: null, elements: [{ statement: 'refuge', source: 'charter', ref: 'objectif', inferred: false }] },
    { id: 'chronology', status: 'NOT_GROUNDED', reason: 'rien', elements: [] }] };
}
function prisme(refs) {
  return { game_id: 'kc', exigences: refs.map((reference, i) => ({
    id: `EX${i}`, source: 'EXPECTED', source_role: 'gd', reference,
    observation: 'o', claim: 'c', enonce: 'e',
    expected_proof: { kind: 'oracle', statement: 's' }, destination: 's3-decompo' })) };
}
function featuremap(leafToEx) {
  return { game_id: 'kc', systemes: [{ id: 'S', features: [{ id: 'F', capacites:
    Object.entries(leafToEx).map(([id, source_ref]) => ({ id, capacite: id, source_ref,
      expected_proof: { kind: 'oracle', statement: 's' } })) }] }] };
}
function wiremapV2(lineToLeaves) {
  return { schema_version: 2, lines: Object.entries(lineToLeaves).map(([id, couvre]) => ({
    id, couvre, fichiers: [{ path: `05_SYSTEMS/${id}.gd`, category: 'system' }] })) };
}

test('factAddresses : 6 faits, adresses concretes, null/NOT_MEASURED ignores', () => {
  const f = factAddresses({ worldscan: worldscan(), gm_worldscan: gm(), story_bible: story() });
  assert.deepEqual(f.conditions_victoire, ['worldscan:games[0].objectives[1].victory_condition']);
  assert.deepEqual(f.conditions_defaite, ['worldscan:games[0].objectives[1].defeat_condition']);
  assert.equal(f.objectifs_joueur.length, 2);
  assert.deepEqual(f.progression, ['gm_worldscan:dimensions[0]']);
  assert.deepEqual(f.boucles_recompense, ['worldscan:games[0].loops.minute_1', 'worldscan:games[0].loops.minute_10']);
  assert.deepEqual(f.contraintes_narratives, ['story_bible:sections[0]']);
});

test('canonicalize : chemin concret, raccourci par id, prose et adresse fantome', () => {
  const a = { worldscan: worldscan(), gm_worldscan: gm(), story_bible: story() };
  assert.equal(canonicalize('worldscan:games[0].objectives[1].victory_condition', a), 'worldscan:games[0].objectives[1].victory_condition');
  assert.equal(canonicalize('gm_worldscan:progression', a), 'gm_worldscan:dimensions[0]');
  assert.equal(canonicalize('story_bible:stakes', a), 'story_bible:sections[0]');
  assert.equal(canonicalize('Cookie Clicker wiki, page Ascension', a), null);
  assert.equal(canonicalize('worldscan:games[7].objectives[0].victory_condition', a), null);
  assert.equal(canonicalize('worldscan:games[0].objectives[0].victory_condition', a), null, 'valeur null = rien de produit');
  assert.equal(canonicalize('gm_worldscan:progression', { gm_worldscan: null }), null);
});

test('traverse : chaine complete jusqu au BUILD', () => {
  const dir = mkdtempSync(join(tmpdir(), 'amont-'));
  mkdirSync(join(dir, '05_SYSTEMS'));
  writeFileSync(join(dir, '05_SYSTEMS', 'L1.gd'), 'x');
  const r = traverse({
    worldscan: worldscan(), gm_worldscan: gm(), story_bible: story(),
    prisme: prisme(['worldscan:games[0].objectives[1].victory_condition', 'gm_worldscan:progression']),
    featuremap: featuremap({ cap_win: 'EX0', cap_tiers: 'EX1' }),
    wiremap: wiremapV2({ L1: ['cap_win'], L2: ['cap_tiers'] }),
  }, dir);
  assert.equal(r.verdict, 'ADVISORY');
  assert.equal(r.claim_verdict, 'NO_CLAIM_ALLOWED');
  assert.equal(r.facts.conditions_victoire.reached, 'BUILD');
  assert.deepEqual(r.facts.conditions_victoire.exigences, ['EX0']);
  assert.deepEqual(r.facts.conditions_victoire.leaves, ['cap_win']);
  assert.deepEqual(r.facts.conditions_victoire.lines, ['L1']);
  assert.equal(r.facts.progression.reached, 'WIREMAP', 'L2.gd absent du game dir');
  assert.equal(r.facts.progression.files_present, false);
  assert.equal(r.facts.conditions_defaite.reached, 'PRODUCED', 'produit, aucune exigence ne le cite');
  assert.equal(r.facts.contraintes_narratives.reached, 'PRODUCED');
  assert.equal(r.references.expected, 2);
  assert.equal(r.references.resolues, 2);
  assert.deepEqual(STAGES, ['NOT_PRODUCED', 'PRODUCED', 'PRISME', 'GREY_BLOCKS', 'WIREMAP', 'BUILD']);
});

test('traverse : reference en prose = rupture au PRISME, comptee non resolue', () => {
  const r = traverse({
    worldscan: worldscan(), gm_worldscan: gm(), story_bible: story(),
    prisme: prisme(['Cookie Clicker wiki']),
    featuremap: featuremap({ cap_win: 'EX0' }), wiremap: wiremapV2({ L1: ['cap_win'] }),
  }, null);
  assert.equal(r.facts.conditions_victoire.reached, 'PRODUCED');
  assert.equal(r.references.adressables, 0);
  assert.deepEqual(r.references.non_resolues, [{ id: 'EX0', reference: 'Cookie Clicker wiki' }]);
});

test('traverse : sans game-dir le BUILD est NOT_MEASURED (files_present null), jamais invente', () => {
  const r = traverse({
    worldscan: worldscan(), gm_worldscan: gm(), story_bible: story(),
    prisme: prisme(['worldscan:games[0].objectives[1].victory_condition']),
    featuremap: featuremap({ cap_win: 'EX0' }), wiremap: wiremapV2({ L1: ['cap_win'] }),
  }, null);
  assert.equal(r.facts.conditions_victoire.reached, 'WIREMAP');
  assert.equal(r.facts.conditions_victoire.files_present, null);
});

test('traverse : artefact amont absent => NOT_PRODUCED, wiremap v1 acceptee', () => {
  const r = traverse({
    worldscan: worldscan(), gm_worldscan: null, story_bible: null,
    prisme: prisme(['worldscan:games[0].loops.minute_1']),
    featuremap: featuremap({ cap_loop: 'EX0' }),
    wiremap: { features: [{ feature: 'loop', couvre: ['cap_loop'], fichiers: ['src/loop.gd'], fonction: 'tick', preuve: 'p' }] },
  }, null);
  assert.equal(r.facts.progression.reached, 'NOT_PRODUCED');
  assert.equal(r.facts.contraintes_narratives.reached, 'NOT_PRODUCED');
  assert.equal(r.facts.boucles_recompense.reached, 'WIREMAP');
  assert.deepEqual(r.facts.boucles_recompense.lines, ['loop']);
});

test('loadRunDir : fichiers absents => null, jamais une exception', async () => {
  const dir = mkdtempSync(join(tmpdir(), 'amont-run-'));
  writeFileSync(join(dir, 'worldscan.json'), JSON.stringify(worldscan()));
  writeFileSync(join(dir, 'prisme.json'), '{pas du json');
  const a = await loadRunDir(dir);
  assert.equal(a.worldscan.games[0].game, 'Cookie Clicker');
  assert.equal(a.prisme, null);
  assert.equal(a.story_bible, null);
});

// Tests du vocabulaire partagé des artefacts amont.
// node --test forge/upstream_schema.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  validateExpectedProof, validateProvenance, validateChaine, validatePrisme, validateFeaturemap,
  collectLeaves, featureIds, duplicateIds, normalizeText, jaccard,
  validateGmSource, isLoopExigence, hasGmSource,
} from './upstream_schema.mjs';
import { prismeReference, featuremapReference, prismeSourceCore } from './upstream_fixtures.mjs';

test('la reference passe le schema prisme (sinon le schema mesure autre chose)', () => {
  assert.deepEqual(validatePrisme(prismeReference()), []);
});

test('la reference passe le schema featuremap', () => {
  assert.deepEqual(validateFeaturemap(featuremapReference()), []);
});

test('expected_proof: kind hors enum et statement vide sont deux findings distincts', () => {
  assert.equal(validateExpectedProof({ kind: 'vibes', statement: 'ok ok ok' }, 'x').length, 1);
  assert.equal(validateExpectedProof({ kind: 'oracle', statement: '   ' }, 'x').length, 1);
  assert.equal(validateExpectedProof({ kind: 'vibes', statement: '' }, 'x').length, 2);
  assert.equal(validateExpectedProof(null, 'x').length, 1);
});

test('chaine: observation, claim et enonce sont TROIS maillons obligatoires', () => {
  const base = { observation: 'vu ceci', claim: 'donc cela', enonce: 'le jeu doit faire autre chose' };
  assert.deepEqual(validateChaine(base, 'x'), []);
  for (const champ of ['observation', 'claim', 'enonce']) {
    const ko = { ...base, [champ]: '' };
    const f = validateChaine(ko, 'x');
    assert.equal(f.length, 1, `${champ} vide doit produire exactement 1 finding`);
    assert.match(f[0], new RegExp(champ));
  }
});

test('chaine: recopier un maillon dans un autre est refuse (schema satisfait, rien deduit)', () => {
  const memeTexte = 'le compteur monte au clic';
  assert.ok(validateChaine(
    { observation: memeTexte, claim: memeTexte, enonce: 'autre chose entierement' }, 'x',
  ).some((p) => /doivent DIFFERER/.test(p)));
  assert.ok(validateChaine(
    { observation: 'vu ceci', claim: memeTexte, enonce: memeTexte }, 'x',
  ).some((p) => /doivent DIFFERER/.test(p)));
  // la normalisation neutralise ponctuation/accents/casse : « Le Compteur monte. »
  // et « le compteur monte » sont le MEME maillon recopie, pas deux maillons.
  assert.ok(validateChaine(
    { observation: 'Le Compteur monte !', claim: 'le compteur monte', enonce: 'z' }, 'x',
  ).some((p) => /doivent DIFFERER/.test(p)));
});

test('provenance: CORE est refuse dans une sortie de worker', () => {
  const f = validateProvenance({ source: 'CORE', source_role: 'joueur', reference: 'x' }, 'x');
  assert.equal(f.length, 1);
  assert.match(f[0], /CORE ne transite JAMAIS/);
  assert.deepEqual(validatePrisme(prismeSourceCore()).filter((p) => /CORE/.test(p)).length, 1);
});

test('provenance: EXPECTED exige une reference, ADDITIONS exige null EXPLICITE', () => {
  assert.equal(validateProvenance({ source: 'EXPECTED', source_role: 'r' }, 'x').length, 1);
  // champ omis != declare absent
  assert.equal(validateProvenance({ source: 'ADDITIONS', source_role: 'r' }, 'x').length, 1);
  assert.equal(validateProvenance({ source: 'ADDITIONS', source_role: 'r', reference: '' }, 'x').length, 1);
  assert.deepEqual(validateProvenance({ source: 'ADDITIONS', source_role: 'r', reference: null }, 'x'), []);
});

test('provenance: source_role obligatoire (regle check_line_states honoree en amont)', () => {
  const f = validateProvenance({ source: 'ADDITIONS', source_role: '', reference: null }, 'x');
  assert.equal(f.length, 1);
  assert.match(f[0], /source_role/);
});

test('collectLeaves aplatit l arbre et featureIds liste les features', () => {
  const fm = featuremapReference();
  assert.equal(collectLeaves(fm).length, 4);
  assert.deepEqual(featureIds(fm), ['feat.cookie', 'feat.batiments', 'feat.hud']);
});

test('un id duplique est signale (sinon tout alignement aval devient ambigu)', () => {
  assert.equal(duplicateIds(['a', 'b', 'a'], 'loc').length, 1);
  assert.deepEqual(duplicateIds(['a', 'b'], 'loc'), []);
});

test('featuremap: un systeme sans feature, une feature sans capacite sont refuses', () => {
  const fm = featuremapReference();
  fm.systemes[0].features = [];
  assert.ok(validateFeaturemap(fm).some((p) => /features: doit etre un tableau NON VIDE/.test(p)));
  const fm2 = featuremapReference();
  fm2.systemes[0].features[0].capacites = [];
  assert.ok(validateFeaturemap(fm2).some((p) => /capacites: doit etre un tableau NON VIDE/.test(p)));
});

test('normalizeText retire accents et ponctuation, jaccard note la ressemblance', () => {
  assert.equal(normalizeText('Élan, prêt-à-jouer !'), 'elan pret a jouer');
  assert.equal(jaccard('le compteur monte', 'le compteur monte'), 1);
  assert.equal(jaccard('abc', 'xyz'), 0);
  assert.ok(jaccard('le compteur monte au clic', 'le compteur monte') > 0.5);
});

// --- Lot B, T3 (2026-08-23) : sourcage GM des exigences de boucle (ADDITIF) -----

test('validateGmSource: exigence hors boucle -> 0 finding', () => {
  assert.deepEqual(validateGmSource({ id: 'x' }, 'x'), []);
});

test('validateGmSource: acteur PLAYER sans reference GM -> finding boucle_sans_source_gm', () => {
  const f = validateGmSource({ id: 'a1', acteur: 'PLAYER', reference: 'worldscan:games[0]' }, 'exigences[0]');
  assert.equal(f.length, 1);
  assert.match(f[0], /boucle_sans_source_gm/);
  assert.match(f[0], /id=a1/);
});

test('validateGmSource: loop_role != NONE sans reference GM -> finding', () => {
  const f = validateGmSource({ id: 'b1', loop_role: 'PLAYER_ACTION', reference: null }, 'x');
  assert.equal(f.length, 1);
});

test('validateGmSource: loop_role == NONE -> 0 finding (hors boucle)', () => {
  assert.deepEqual(validateGmSource({ id: 'c1', loop_role: 'NONE', reference: null }, 'x'), []);
});

test('validateGmSource: reference gm_worldscan:game_master.loops.* -> 0 finding', () => {
  const f = validateGmSource(
    { id: 'd1', acteur: 'PLAYER', reference: 'gm_worldscan:game_master.loops.core_loop.step1' }, 'x',
  );
  assert.deepEqual(f, []);
});

test('validateGmSource: reference gm_worldscan:game_master.grey_blocks.* -> 0 finding', () => {
  const f = validateGmSource(
    { id: 'e1', loop_role: 'UNLOCK', reference: 'gm_worldscan:game_master.grey_blocks.garden' }, 'x',
  );
  assert.deepEqual(f, []);
});

test('isLoopExigence / hasGmSource : primitives partagees', () => {
  assert.equal(isLoopExigence({ acteur: 'PLAYER' }), true);
  assert.equal(isLoopExigence({ loop_role: 'REWARD' }), true);
  assert.equal(isLoopExigence({ loop_role: 'NONE' }), false);
  assert.equal(isLoopExigence({}), false);
  assert.equal(hasGmSource({ reference: 'gm_worldscan:game_master.loops.x' }), true);
  assert.equal(hasGmSource({ reference: 'worldscan:games[0]' }), false);
  assert.equal(hasGmSource({ reference: null }), false);
});

// Tests de l'oracle d'AVANT-BUILD de l'architecture (blueprint vs featuremap).
// node --test forge/check_blueprint_contract.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { checkBlueprintDoc, detecterCycles, consommateursDerives } from './check_blueprint_contract.mjs';
import {
  blueprintReference, featuremapReference, blueprintVacant,
  blueprintContradictoire, blueprintCyclique,
} from './upstream_fixtures.mjs';

test('VALIDITE: l oracle ACCEPTE le blueprint de reference', () => {
  const r = checkBlueprintDoc(blueprintReference(), featuremapReference());
  assert.deepEqual(r.problems, []);
  assert.deepEqual(r.features_non_couvertes, []);
  assert.deepEqual(r.couverture_fantome, []);
  assert.equal(r.verdict, 'OK');
  assert.equal(r.stats.modules, 3);
  assert.equal(r.stats.features_couvertes, 3);
  assert.equal(r.stats.features, 3);
});

// LE contrôle négatif du chantier : l'artefact qui passait 34 runs sur 34.
test('DISCRIMINATION: le blueprint historique de 82 octets ECHOUE ici', () => {
  const r = checkBlueprintDoc(blueprintVacant(), featuremapReference());
  assert.equal(r.verdict, 'FAIL');
  assert.ok(r.problems.some((p) => /responsabilites: tableau NON VIDE requis/.test(p)));
  assert.equal(r.features_non_couvertes.length, 3); // aucune feature couverte
  assert.equal(r.stats.features_couvertes, 0);
});

test('COUVERTURE: une feature de la featuremap sans module est signalee', () => {
  const d = blueprintReference();
  d.responsabilites[2].couvre = ['feat.cookie'];
  const r = checkBlueprintDoc(d, featuremapReference());
  assert.equal(r.verdict, 'FAIL');
  assert.equal(r.features_non_couvertes.length, 1);
  assert.match(r.features_non_couvertes[0], /feat\.hud/);
});

test('COUVERTURE FANTOME: un couvre qui ne resout aucune feature est signale', () => {
  const d = blueprintReference();
  d.responsabilites[0].couvre = ['feat.inexistante'];
  const r = checkBlueprintDoc(d, featuremapReference());
  assert.equal(r.couverture_fantome.length, 1);
  assert.equal(r.verdict, 'FAIL');
});

test('RESPONSABILITES: module inconnu, responsabilite vide, couvre vide sont refuses', () => {
  const d = blueprintReference();
  d.responsabilites[0].module = 'fantome';
  assert.ok(checkBlueprintDoc(d, featuremapReference()).problems.some((p) => /responsabilite orpheline/.test(p)));
  const d2 = blueprintReference();
  d2.responsabilites[0].responsabilite = '';
  assert.ok(checkBlueprintDoc(d2, featuremapReference()).problems.some((p) => /responsabilite: absente ou vide/.test(p)));
  const d3 = blueprintReference();
  d3.responsabilites[1].couvre = [];
  assert.ok(checkBlueprintDoc(d3, featuremapReference()).problems.some((p) => /couvre: tableau NON VIDE/.test(p)));
});

test('un module sans entree dans responsabilites est signale', () => {
  const d = blueprintReference();
  d.responsabilites = d.responsabilites.slice(0, 2);
  const r = checkBlueprintDoc(d, featuremapReference());
  assert.ok(r.problems.some((p) => /'presentation' n'a aucune entree dans responsabilites/.test(p)));
});

test('PREUVE: un module sans preuve_attendue exploitable est refuse', () => {
  const d = blueprintReference();
  delete d.responsabilites[0].preuve_attendue;
  assert.ok(checkBlueprintDoc(d, featuremapReference()).problems.some((p) => /preuve_attendue/.test(p)));
});

test('DEPENDANCES: absentes = refus, module inconnu = refus, [] = module feuille accepte', () => {
  const d = blueprintReference();
  delete d.responsabilites[0].dependances;
  assert.ok(checkBlueprintDoc(d, featuremapReference()).problems.some((p) => /JAMAIS absent/.test(p)));
  const d2 = blueprintReference();
  d2.responsabilites[1].dependances = ['fantome'];
  assert.ok(checkBlueprintDoc(d2, featuremapReference()).problems.some((p) => /module inconnu 'fantome'/.test(p)));
  // le module feuille de la reference (dependances: []) passe deja
  assert.equal(checkBlueprintDoc(blueprintReference(), featuremapReference()).verdict, 'OK');
});

test('CONTRADICTION: dependre d une paire qu on interdit soi-meme est refuse', () => {
  const r = checkBlueprintDoc(blueprintContradictoire(), featuremapReference());
  assert.equal(r.verdict, 'FAIL');
  assert.ok(r.problems.some((p) => /auto-contradictoire/.test(p)));
});

test('CYCLE: un cycle de dependances est detecte et nomme', () => {
  const r = checkBlueprintDoc(blueprintCyclique(), featuremapReference());
  assert.equal(r.verdict, 'FAIL');
  assert.ok(r.problems.some((p) => /cycle de dependances/.test(p)));
});

test('deps_interdites vide ou pointant un module inconnu est refuse', () => {
  const d = blueprintReference();
  d.deps_interdites = [];
  assert.ok(checkBlueprintDoc(d, featuremapReference()).problems.some((p) => /vacuement vert apres build/.test(p)));
  const d2 = blueprintReference();
  d2.deps_interdites = [['fantome', 'game_state']];
  assert.ok(checkBlueprintDoc(d2, featuremapReference()).problems.some((p) => /module inconnu 'fantome'/.test(p)));
});

test('detecterCycles rend le CHEMIN, pas un booleen', () => {
  const g = new Map([['a', ['b']], ['b', ['c']], ['c', ['a']]]);
  const cycles = detecterCycles(g);
  assert.equal(cycles.length, 1);
  assert.equal(cycles[0][0], cycles[0][cycles[0].length - 1]);
  assert.deepEqual(detecterCycles(new Map([['a', ['b']], ['b', []]])), []);
});

test('consommateurs DERIVES des dependances (jamais saisis deux fois)', () => {
  const g = new Map([['ui', ['state']], ['logic', ['state']], ['state', []]]);
  assert.deepEqual(consommateursDerives(g).state.sort(), ['logic', 'ui']);
  assert.deepEqual(consommateursDerives(g).ui, []);
});

test('une featuremap sans feature rend la couverture invérifiable, et l oracle le dit', () => {
  const r = checkBlueprintDoc(blueprintReference(), { game_id: 'x', systemes: [] });
  assert.equal(r.verdict, 'FAIL');
  assert.ok(r.problems.some((p) => /ni sautee en silence/.test(p)));
});

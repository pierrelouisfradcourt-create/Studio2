// Tests de l'ORACLE QUALITY LAYER V2 (contaminations inter-champs) et du schéma
// AGENT_GENOME_V1.
// node --test forge/cross_field_quality.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  SEUIL_CROISE, STRATEGIES, STRATEGIES_ACTIVES, nomDeChamp, entreeDe,
  strategieA, strategieB, strategieC, strategieD,
  mesurerCroise, cibleEtSource, promptReparationCroisee,
} from './cross_field_quality.mjs';
import { validateGenome, genomeVierge, ROLES } from './agent_genome.mjs';
import {
  worldscanReference, prismeReference, featuremapReference,
  blueprintReference, wiremapReference,
} from './upstream_fixtures.mjs';

const REFS = () => ({
  worldscan: worldscanReference(), prisme: prismeReference(),
  featuremap: featuremapReference(), blueprint: blueprintReference(),
  wiremap: wiremapReference(),
});

// Le défaut RÉELLEMENT observé le 2026-08-04 : après réparation d'une discriminance,
// `games[1].victory_condition` avait pris mot pour mot le `player_goal` de `games[0]`.
function artefactContamine() {
  const ws = worldscanReference();
  ws.games[1].objectives[0].victory_condition = ws.games[0].objectives[0].player_goal;
  return ws;
}

// --- LE test de validite -----------------------------------------------------------

test('VALIDITE: 0 signal sur les 5 artefacts de reference (strategies actives)', () => {
  for (const [nom, doc] of Object.entries(REFS())) {
    const r = mesurerCroise(doc, STRATEGIES_ACTIVES);
    assert.deepEqual(r.signaux, [], `${nom} : ${JSON.stringify(r.signaux)}`);
    assert.equal(r.verdict, 'PASS');
  }
});

test('les strategies ACTIVES sont celles que la calibration a retenues', () => {
  assert.deepEqual(STRATEGIES_ACTIVES, ['A']);
  assert.deepEqual(Object.keys(STRATEGIES).sort(), ['A', 'B', 'C', 'D']);
});

// --- detection ----------------------------------------------------------------------

test('A: un champ qui reprend un AUTRE champ d une AUTRE entree est signale', () => {
  const r = mesurerCroise(artefactContamine(), ['A']);
  assert.equal(r.verdict, 'WARNING_CROSS_FIELD_COPY');
  assert.equal(r.signaux.length, 1);
  assert.deepEqual(r.signaux[0].champs.sort(), ['player_goal', 'victory_condition']);
});

test('A: deux champs de la MEME entree qui coincident ne sont PAS signales', () => {
  // A Bomberman, le but du joueur EST d etre le dernier en vie : la coincidence
  // interne est legitime, la signaler serait une fausse alerte.
  const ws = worldscanReference();
  ws.games[0].objectives[0].victory_condition = ws.games[0].objectives[0].player_goal;
  assert.deepEqual(strategieA(ws), []);
});

test('A: le MEME champ entre deux entrees n est PAS son affaire (c est oracle_quality V1)', () => {
  const ws = worldscanReference();
  ws.games[1].retention_answer = ws.games[0].retention_answer;
  assert.deepEqual(strategieA(ws), []);
});

test('le verdict est un WARNING, jamais un FAIL, et n est pas bloquant', () => {
  const r = mesurerCroise(artefactContamine(), ['A']);
  assert.equal(r.verdict, 'WARNING_CROSS_FIELD_COPY');
  assert.equal(r.bloquant, false);
});

// --- les 4 strategies, telles que calibrees -----------------------------------------

test('B trouve le meme defaut mais via un seuil (donc disponible, pas active)', () => {
  assert.equal(strategieB(artefactContamine()).length, 1);
  assert.equal(strategieB(artefactContamine())[0].strategie, 'B');
  assert.ok(SEUIL_CROISE > 0 && SEUIL_CROISE <= 1);
});

test('C et D sont AVEUGLES au defaut mesure — c est pourquoi elles ne sont pas actives', () => {
  assert.deepEqual(strategieC(artefactContamine()), []);
  assert.deepEqual(strategieD(artefactContamine()), []);
});

test('D attrape ce pour quoi elle est faite : deux ROLES incompatibles confondus', () => {
  const ws = worldscanReference();
  ws.games[0].retention_answer = ws.games[0].objectives[0].player_goal;
  const r = strategieD(ws);
  assert.equal(r.length, 1);
  assert.deepEqual(r[0].champs.sort(), ['player_goal', 'retention_answer']);
});

// --- outils --------------------------------------------------------------------------

test('nomDeChamp et entreeDe lisent correctement un chemin', () => {
  assert.equal(nomDeChamp('games[1].objectives[0].player_goal'), 'player_goal');
  assert.equal(entreeDe('games[1].objectives[0].player_goal'), 1);
  assert.equal(entreeDe('advisory'), null);
});

// --- reparation V3 : source protegee, cible regeneree --------------------------------

test('cibleEtSource: la CIBLE est l entree la plus RECENTE, la source est protegee', () => {
  const s = { chemins: ['games[0].player_goal', 'games[1].victory_condition'] };
  assert.deepEqual(cibleEtSource(s), {
    source: 'games[0].player_goal', target: 'games[1].victory_condition',
  });
  // ordre inverse dans le signal : le sens ne doit PAS s inverser
  const s2 = { chemins: ['games[2].victory_condition', 'games[0].player_goal'] };
  assert.deepEqual(cibleEtSource(s2), {
    source: 'games[0].player_goal', target: 'games[2].victory_condition',
  });
});

test('le prompt V3 porte DEFECT_CLASS / SOURCE / TARGET / ACTION et protege la SOURCE', () => {
  const s = {
    chemins: ['games[0].player_goal', 'games[1].victory_condition'],
    detail: 'reprend mot pour mot',
  };
  const roles = cibleEtSource(s);
  const p = promptReparationCroisee(s, roles, 'survivre et eliminer', { game: 'Super Bomberman R' });
  for (const bloc of ['DEFECT_CLASS:', 'cross_field_copy', 'SOURCE', 'TARGET', 'ACTION:',
    'regenerate TARGET only', 'FORBIDDEN:']) {
    assert.ok(p.includes(bloc), `bloc manquant : ${bloc}`);
  }
  assert.match(p, /intouchable/);
  assert.match(p, /games\[0\]\.player_goal/);
  assert.match(p, /survivre et eliminer/); // la source est MONTREE pour pouvoir s en eloigner
  assert.match(p, /Super Bomberman R/);
});

// --- AGENT_GENOME_V1 -----------------------------------------------------------------

test('GENOME: un genome vierge est VALIDE (rien de mesure != rien a signaler)', () => {
  for (const role of ROLES) {
    assert.deepEqual(validateGenome(genomeVierge(role, 'qwen2.5-14b-instruct', ['check_worldscan'])), [],
      `role ${role}`);
  }
});

test('GENOME: on ne peut PAS creer un worker sans dire qui le juge', () => {
  assert.throws(() => genomeVierge('prisme', 'm', []), /NON VIDE/);
  assert.throws(() => genomeVierge('prisme', 'm'), /NON VIDE/);
});

test('GENOME: role inconnu, model vide, oracle_stack absente sont refuses', () => {
  const g = genomeVierge('prisme', 'm', ['check_prisme_manifest']);
  assert.ok(validateGenome({ ...g, worker_role: 'inconnu' }).some((x) => /worker_role/.test(x)));
  assert.ok(validateGenome({ ...g, model: '' }).some((x) => /model/.test(x)));
  const sansOracle = { ...g };
  delete sansOracle.oracle_stack;
  assert.ok(validateGenome(sansOracle).some((x) => /pas evaluable/.test(x)));
});

test('GENOME: known_failures peut etre VIDE mais jamais ABSENT', () => {
  const g = genomeVierge('prisme', 'm', ['check_prisme_manifest']);
  assert.deepEqual(validateGenome({ ...g, known_failures: [] }), []);
  const sans = { ...g };
  delete sans.known_failures;
  assert.ok(validateGenome(sans).some((x) => /pas regarde/.test(x)));
});

test('GENOME: successful_mutations ne porte que des IDENTIFIANTS, jamais la mesure', () => {
  const g = genomeVierge('worldscan', 'm', ['check_worldscan']);
  // le registre est la source unique : recopier une mesure ici creerait deux versions
  // d un meme fait, et deux faits identiques finissent toujours par diverger
  g.successful_mutations = [{ id: 'M-Q5-A', mesure: { false_positive: 0 } }];
  assert.ok(validateGenome(g).some((x) => /identifiant de mutation/.test(x)));

  g.successful_mutations = ['M-Q5-A', 'REPAIR-LOOP-V1'];
  g.rejected_mutations = ['M-Q4-ANCRAGE'];
  assert.deepEqual(validateGenome(g), []);
});

test('GENOME: confidence_profile est DERIVE, jamais saisi', () => {
  const g = genomeVierge('prisme', 'm', ['check_prisme_manifest']);
  assert.deepEqual(validateGenome(g), []);
  assert.ok(validateGenome({ ...g, confidence_profile: 0.9 }).some((x) => /confidence_profile/.test(x)));
});

test('GENOME: repair_stack n accepte que des strategies connues', () => {
  const g = genomeVierge('repair', 'm', ['check_worldscan']);
  g.repair_stack = ['champ_local', 'cross_field'];
  assert.deepEqual(validateGenome(g), []);
  g.repair_stack = ['a_l_instinct'];
  assert.ok(validateGenome(g).some((x) => /strategie inconnue/.test(x)));
});

test('GENOME: known_blind_spots peut etre VIDE mais jamais ABSENT', () => {
  const g = genomeVierge('prisme', 'm', ['check_prisme_manifest']);
  const sans = { ...g };
  delete sans.known_blind_spots;
  assert.ok(validateGenome(sans).some((x) => /pas regarde/.test(x)));
});

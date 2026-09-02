// Tests de l'oracle s1-prisme sur artefact structuré.
// node --test forge/check_prisme_manifest.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { checkPrismeDoc, worldscanTokens, referenceAncree } from './check_prisme_manifest.mjs';
import {
  prismeReference, prismeSansPreuve, prismeSansProvenance, prismeSourceCore,
  worldscanReference,
} from './upstream_fixtures.mjs';

// --- LE test de validite de l'oracle -------------------------------------------
// Un oracle qui recale l'artefact de reference se mesure lui-meme (leçon 2026-08-04).
test('VALIDITE: l oracle ACCEPTE l artefact de reference', () => {
  const r = checkPrismeDoc(prismeReference());
  assert.deepEqual(r.problems, []);
  assert.deepEqual(r.non_actionnables, []);
  assert.equal(r.verdict, 'OK');
  assert.equal(r.stats.exigences, 4);
  assert.equal(r.stats.actionnables, 4);
  assert.equal(r.stats.expected, 3);
  assert.equal(r.stats.additions, 1);
});

test('VALIDITE: la reference passe aussi avec son World Scan, references ancrees', () => {
  const r = checkPrismeDoc(prismeReference(), worldscanReference());
  assert.equal(r.verdict, 'OK');
  assert.deepEqual(r.references_non_ancrees, []);
  assert.equal(r.stats.references_verifiees, 3);
  assert.equal(r.stats.references_ancrees, 3);
});

// --- discrimination ------------------------------------------------------------
test('un artefact vide/absurde est refuse (pas de vert vacant)', () => {
  assert.equal(checkPrismeDoc({}).verdict, 'FAIL');
  assert.equal(checkPrismeDoc({ game_id: 'x', exigences: [] }).verdict, 'FAIL');
  assert.equal(checkPrismeDoc(null).verdict, 'FAIL');
  assert.equal(checkPrismeDoc('texte libre').verdict, 'FAIL');
});

test('CLASSEMENT: sans preuve attendue, les exigences sont classees non actionnables', () => {
  const r = checkPrismeDoc(prismeSansPreuve());
  assert.equal(r.stats.actionnables, 0);
  assert.equal(r.stats.non_actionnables, 4);
  assert.ok(r.non_actionnables.length >= 4);
  // zero actionnable => l'artefact ne route rien => FAIL, et la raison le dit
  assert.equal(r.verdict, 'FAIL');
  assert.ok(r.problems.some((p) => /ne route rien vers l'aval/.test(p)));
});

test('CLASSEMENT: une seule exigence non actionnable ne fait PAS echouer l artefact', () => {
  const d = prismeReference();
  delete d.exigences[0].expected_proof;
  const r = checkPrismeDoc(d);
  assert.deepEqual(r.problems, []);
  assert.equal(r.verdict, 'OK');
  assert.equal(r.stats.actionnables, 3);
  assert.equal(r.stats.non_actionnables, 1);
  assert.ok(r.non_actionnables.length > 0);
});

test('une destination hors enum est non routable, donc classee', () => {
  const d = prismeReference();
  d.exigences[0].destination = 's42-inexistante';
  const r = checkPrismeDoc(d);
  assert.equal(r.stats.actionnables, 3);
  assert.ok(r.non_actionnables.some((p) => /non routable/.test(p)));
});

test('STRUCTURE: provenance CORE, id/enonce manquants font echouer', () => {
  assert.equal(checkPrismeDoc(prismeSourceCore()).verdict, 'FAIL');
  const d = prismeReference();
  delete d.exigences[1].enonce;
  assert.ok(checkPrismeDoc(d).problems.some((p) => /enonce/.test(p)));
  const d2 = prismeReference();
  d2.exigences[1].id = '';
  assert.ok(checkPrismeDoc(d2).problems.some((p) => /id: absent ou vide/.test(p)));
});

test('STRUCTURE: EXPECTED sans reference echoue (sansProvenance)', () => {
  const r = checkPrismeDoc(prismeSansProvenance());
  assert.equal(r.verdict, 'FAIL');
  assert.equal(r.problems.filter((p) => /reference: obligatoire/.test(p)).length, 3);
});

test('un id duplique est refuse', () => {
  const d = prismeReference();
  d.exigences[1].id = d.exigences[0].id;
  assert.ok(checkPrismeDoc(d).problems.some((p) => /id duplique/.test(p)));
});

// --- ancrage des references ----------------------------------------------------
test('une reference inventee n est pas ancree dans le World Scan', () => {
  const d = prismeReference();
  d.exigences[0].reference = 'https://source-inventee.example/page';
  const r = checkPrismeDoc(d, worldscanReference());
  assert.equal(r.references_non_ancrees.length, 1);
  assert.equal(r.stats.references_ancrees, 2);
  // l'ancrage est CLASSE, il ne fait pas basculer le verdict structurel
  assert.equal(r.verdict, 'OK');
});

test('sans World Scan fourni, l oracle NE PRETEND PAS avoir verifie l ancrage', () => {
  const r = checkPrismeDoc(prismeReference());
  assert.equal(r.stats.references_verifiees, 0);
  assert.equal(r.stats.references_ancrees, 0);
  assert.deepEqual(r.references_non_ancrees, []);
});

test('worldscanTokens / referenceAncree : appariement de sous-chaine, jamais semantique', () => {
  const t = worldscanTokens(worldscanReference());
  assert.ok(referenceAncree('https://cookieclicker.fandom.com/wiki/Building', t));
  assert.ok(!referenceAncree('https://autre-site.example/x', t));
  assert.ok(!referenceAncree('', t));
});

// --- Lot B, T3 (2026-08-23) : stats de sourcage GM des exigences de boucle -----
// ADVISORY, jamais gatant (verrou GO Pierre : gate seulement au run 10).

test('GM: exigence de boucle (acteur PLAYER) sans reference GM -> comptee non sourcee', () => {
  const d = prismeReference();
  d.exigences[0].acteur = 'PLAYER';
  const r = checkPrismeDoc(d);
  assert.equal(r.stats.exigences_boucle, 1);
  assert.equal(r.stats.exigences_sourcees_gm, 0);
  // ADVISORY : ne fait jamais basculer le verdict structurel
  assert.equal(r.verdict, 'OK');
});

test('GM: exigence de boucle avec reference gm_worldscan:game_master.loops.* -> sourcee', () => {
  const d = prismeReference();
  d.exigences[0].acteur = 'PLAYER';
  d.exigences[0].source = 'EXPECTED';
  d.exigences[0].reference = 'gm_worldscan:game_master.loops.core_loop.step1';
  const r = checkPrismeDoc(d);
  assert.equal(r.stats.exigences_boucle, 1);
  assert.equal(r.stats.exigences_sourcees_gm, 1);
});

test('GM: exigence hors boucle (ni acteur PLAYER ni loop_role) -> jamais comptee', () => {
  const r = checkPrismeDoc(prismeReference());
  assert.equal(r.stats.exigences_boucle, 0);
  assert.equal(r.stats.exigences_sourcees_gm, 0);
});

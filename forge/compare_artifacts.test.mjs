// Tests du comparateur référence vs candidat.
// node --test forge/compare_artifacts.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { comparer, itemsOf, aligner, metriques, idsAmontDe } from './compare_artifacts.mjs';
import {
  prismeReference, prismeTronque, prismeSansPreuve, prismeSansProvenance,
  featuremapReference, featuremapAmputee, blueprintReference, blueprintVacant,
  wiremapReference, wiremapAmputee,
} from './upstream_fixtures.mjs';

test('IDENTITE: reference vs elle-meme = convergence totale, aucune perte, aucun ajout', () => {
  const r = comparer('prisme', prismeReference(), prismeReference());
  assert.equal(r.convergence.length, 4);
  assert.equal(r.loss.length, 0);
  assert.equal(r.addition.length, 0);
  assert.equal(r.couverture, 1);
  assert.equal(r.alignement.par_source_ref, 3); // 3 EXPECTED portent une reference
  assert.equal(r.alignement.par_texte, 1);      // l'ADDITIONS (reference null) passe par le texte
});

test('PERTE: un candidat tronque produit exactement la perte attendue', () => {
  const r = comparer('prisme', prismeReference(), prismeTronque());
  assert.equal(r.convergence.length, 1);
  assert.equal(r.loss.length, 3);
  assert.equal(r.addition.length, 0);
  assert.equal(r.couverture, 0.25);
  assert.deepEqual(r.loss.map((l) => l.id).sort(), ['ex.achat', 'ex.production', 'ex.progression']);
});

test('AJOUT: un item du candidat sans equivalent est une addition, et son absence de provenance est visible', () => {
  const cand = prismeReference();
  cand.exigences.push({
    id: 'ex.succes',
    source: 'ADDITIONS',
    source_role: 'ceo',
    reference: null,
    observation: 'Idee propre au candidat.',
    enonce: 'Un systeme de succes recompense les paliers franchis.',
    expected_proof: { kind: 'oracle', statement: 'Franchir un palier debloque exactement un succes.' },
    destination: 's3-decompo',
  });
  const r = comparer('prisme', prismeReference(), cand);
  assert.equal(r.addition.length, 1);
  assert.equal(r.addition[0].id, 'ex.succes');
  assert.equal(r.addition[0].provenance_declaree, true); // ADDITIONS + reference:null explicite
  assert.equal(r.loss.length, 0);
});

// --- ordre d'alignement (règle Pierre) -----------------------------------------
test('ALIGNEMENT 1: source_ref identique prime, meme si les textes different', () => {
  const cand = prismeReference();
  cand.exigences[0].enonce = 'Formulation totalement differente sans aucun mot commun.';
  cand.exigences[0].observation = 'Autre chose.';
  const r = comparer('prisme', prismeReference(), cand);
  const paire = r.convergence.find((c) => c.reference === 'ex.clic');
  assert.equal(paire.align_mode, 'source_ref');
});

test('ALIGNEMENT 2: sans source_ref, la similarite de texte prend le relais', () => {
  const r = comparer('prisme', prismeSansProvenance(), prismeSansProvenance());
  assert.equal(r.alignement.par_source_ref, 0);
  assert.equal(r.alignement.par_texte, 4);
  assert.ok(r.convergence.every((c) => c.similarite >= 0.6));
});

test('ALIGNEMENT 3: deux provenances DIFFERENTES ne sont JAMAIS rapprochees par le texte', () => {
  const cand = prismeReference();
  // texte identique, provenance differente => la similarite ne doit rien inventer
  cand.exigences[0].reference = 'https://une-tout-autre-source.example/page';
  const r = comparer('prisme', prismeReference(), cand);
  assert.ok(!r.convergence.some((c) => c.reference === 'ex.clic'));
  assert.ok(r.loss.some((l) => l.id === 'ex.clic'));
  assert.ok(r.addition.some((a) => a.id === 'ex.clic'));
});

test('un item du candidat ne peut etre apparie qu une seule fois', () => {
  const ref = prismeReference();
  const cand = prismeTronque();
  const r = comparer('prisme', ref, cand);
  const vus = r.convergence.map((c) => c.candidat);
  assert.equal(new Set(vus).size, vus.length);
});

// --- métriques -----------------------------------------------------------------
test('AUCUN score agrege (une composite s optimise sans qu on sache quoi)', () => {
  const r = comparer('prisme', prismeReference(), prismeReference());
  assert.equal(r.score_agrege, null);
});

test('VARIANCE: chaque metrique prend >=2 valeurs distinctes sur l echantillon', () => {
  const base = metriques('prisme', itemsOf('prisme', prismeReference()));
  const sansPreuve = metriques('prisme', itemsOf('prisme', prismeSansPreuve()));
  const sansProv = metriques('prisme', itemsOf('prisme', prismeSansProvenance()));

  // actionnabilite : 1 vs 0
  assert.equal(base.actionnabilite, 1);
  assert.equal(sansPreuve.actionnabilite, 0);
  // tracabilite : 1 vs 0.25 (seule l'ADDITIONS declare encore sa provenance)
  assert.equal(base.tracabilite, 1);
  assert.equal(sansProv.tracabilite, 0.25);
  // compatibilite : varie avec la destination
  const dest = prismeReference();
  dest.exigences.forEach((e) => { e.destination = 'nulle-part'; });
  assert.equal(base.compatibilite, 1);
  assert.equal(metriques('prisme', itemsOf('prisme', dest)).compatibilite, 0);
  // couverture : varie entre identite et troncature
  assert.equal(comparer('prisme', prismeReference(), prismeReference()).couverture, 1);
  assert.equal(comparer('prisme', prismeReference(), prismeTronque()).couverture, 0.25);
});

test('RESOLUTION: null sans amont fourni (on ne pretend pas avoir verifie)', () => {
  const sans = comparer('featuremap', featuremapReference(), featuremapReference());
  assert.equal(sans.metriques.candidat.resolution, null);
  assert.equal(sans.amont_fourni, false);

  const avec = comparer('featuremap', featuremapReference(), featuremapReference(), prismeReference());
  assert.equal(avec.amont_fourni, true);
  assert.equal(avec.metriques.candidat.resolution, 1);
});

test('RESOLUTION: un source_ref invente fait chuter la resolution', () => {
  const cand = featuremapReference();
  cand.systemes[0].features[0].capacites[0].source_ref = 'ex.inexistante';
  const r = comparer('featuremap', featuremapReference(), cand, prismeReference());
  assert.equal(r.metriques.reference.resolution, 1);
  assert.equal(r.metriques.candidat.resolution, 0.75);
});

test('la REFERENCE est mesuree elle aussi (jamais supposee parfaite)', () => {
  const refFaible = prismeSansPreuve();
  const r = comparer('prisme', refFaible, prismeReference());
  assert.equal(r.metriques.reference.actionnabilite, 0);
  assert.equal(r.metriques.candidat.actionnabilite, 1);
});

// --- les 4 types ----------------------------------------------------------------
test('les 4 types se projettent en items comparables', () => {
  assert.equal(itemsOf('prisme', prismeReference()).length, 4);
  assert.equal(itemsOf('featuremap', featuremapReference()).length, 4);
  assert.equal(itemsOf('blueprint', blueprintReference()).length, 3);
  assert.equal(itemsOf('wiremap', wiremapReference()).length, 4);
  assert.deepEqual(itemsOf('inconnu', {}), []);
});

test('featuremap / blueprint / wiremap : perte detectee sur chaque type', () => {
  assert.equal(comparer('featuremap', featuremapReference(), featuremapAmputee()).loss.length, 1);
  assert.equal(comparer('blueprint', blueprintReference(), blueprintVacant()).loss.length, 3);
  assert.equal(comparer('wiremap', wiremapReference(), wiremapAmputee()).loss.length, 1);
});

test('idsAmontDe accepte un prisme comme une featuremap, et rend null si vide', () => {
  assert.equal(idsAmontDe(prismeReference()).size, 4);
  assert.equal(idsAmontDe(featuremapReference()).size, 4);
  assert.equal(idsAmontDe({}), null);
  assert.equal(idsAmontDe(null), null);
});

test('aligner est deterministe (meme entree -> meme sortie)', () => {
  const a = itemsOf('prisme', prismeReference());
  const b = itemsOf('prisme', prismeSansProvenance());
  const r1 = aligner(a, b);
  const r2 = aligner(a, b);
  assert.deepEqual(r1.paires.map((p) => [p.ref.id, p.cand.id]), r2.paires.map((p) => [p.ref.id, p.cand.id]));
});

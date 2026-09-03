// D-1-tuyau — l'enveloppe de `repair_step` ne doit RIEN perdre du résultat de l'oracle.
//
// DÉFAUT RÉEL (RUN M, M ter) : `repair_step.mjs` passait à `repair_loop` un objet réduit
// `{ ok, problems }`, jetant les trois autres listes de `check_wiremap_contract`. La boucle
// remplissait alors les `couvre` manquants, voyait `problems` tomber de 9 à 0, et déclarait
// un progrès — pendant que `couverture_fantome` montait de 0 à 9, hors de son champ de vision.
// Le défaut n'était pas réparé : il était DÉPLACÉ (loi du déplacement, 2026-08-04).
//
// LEÇON DE MÉTHODE, et c'est elle qui dicte la forme de ce fichier : le premier correctif
// (`tousLesFindings`) était accompagné d'un test qui lui passait un objet FABRIQUÉ À LA MAIN,
// complet. La production, elle, fournissait un objet amputé. **Le test validait le collecteur
// sur une entrée que la chaîne ne produit jamais.** Ces tests-ci exercent donc l'ORACLE RÉEL sur
// des FICHIERS RÉELS, jamais un littéral.
//
// NO_CLAIM_ALLOWED.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

import { checkWiremapContractFiles } from './check_wiremap_contract.mjs';
import { tousLesFindings } from './repair_loop.mjs';

/** Un couple featuremap/wiremap RÉEL sur disque. `couvre` pilote le scénario. */
function terrain(couvre) {
  const dir = mkdtempSync(join(tmpdir(), 'd1-tuyau-'));
  const featuremap = {
    game_id: 'sonde', systemes: [{
      id: 'SYS', features: [{
        id: 'FEAT', capacites: [
          { id: 'cap_a', capacite: 'a', source_ref: 'R1', expected_proof: { kind: 'oracle', statement: 's' } },
          { id: 'cap_b', capacite: 'b', source_ref: 'R2', expected_proof: { kind: 'oracle', statement: 's' } },
        ],
      }],
    }],
  };
  const wiremap = {
    features: [{
      feature: 'L0', fonction: 'f', fichiers: ['a.mjs'], preuve: 'p',
      version: '1', statut: 'implemented', couvre,
    }],
  };
  const fm = join(dir, 'featuremap.json');
  const wm = join(dir, 'wiremap.json');
  writeFileSync(fm, JSON.stringify(featuremap), 'utf-8');
  writeFileSync(wm, JSON.stringify(wiremap), 'utf-8');
  return { wm, fm };
}

test("l'oracle REEL rend plus que `problems` — et l'enveloppe doit tout transmettre", async () => {
  const { wm, fm } = terrain([]);                       // aucune ligne ne couvre : violation de FORME
  const r = await checkWiremapContractFiles(wm, fm);

  // Ce que l'oracle rend vraiment, mesuré et non supposé.
  assert.ok(Array.isArray(r.capacites_non_couvertes));
  assert.ok(Array.isArray(r.couverture_fantome));
  assert.ok(Array.isArray(r.maillon_non_lie));

  const complet = tousLesFindings(r).length;
  const tronque = (r.problems || []).length;
  assert.ok(complet > tronque,
    `l'enveloppe amputee perdrait ${complet - tronque} finding(s) sur ${complet}`);
});

test('le DEPLACEMENT du defaut est desormais visible dans le COMPTE', async () => {
  // Avant : couvre vide      -> violation de forme, aucun fantome.
  const a = terrain([]);
  const avant = await checkWiremapContractFiles(a.wm, a.fm);
  // Apres : couvre REMPLI de noms qui ne resolvent aucune capacite — exactement ce que la
  // boucle ecrivait, et ce que l'ancien compte declarait « repare ».
  const t = terrain(['nomDeFonction', 'autreNom']);
  const apres = await checkWiremapContractFiles(t.wm, t.fm);

  assert.equal((apres.problems || []).length, 0,
    'la FORME est satisfaite apres remplissage — c est ce qui trompait l ancien compte');
  assert.ok(apres.couverture_fantome.length > 0, 'les couvre sans referent sont des fantomes');

  // Le coeur du lot : sur le compte COMPLET, il n y a aucun progres.
  assert.ok(tousLesFindings(apres).length >= tousLesFindings(avant).length,
    'remplir `couvre` de noms sans referent ne doit JAMAIS compter comme un progres');
});

test('tousLesFindings ignore `stats` et ne compte que des chaines', async () => {
  const { wm, fm } = terrain([]);
  const r = await checkWiremapContractFiles(wm, fm);
  for (const f of tousLesFindings(r)) assert.equal(typeof f, 'string');
  assert.ok(!tousLesFindings(r).includes(r.stats));
});

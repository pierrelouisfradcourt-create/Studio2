// INJECTION DES PONTS PYTHON DANS `runSelfAudit` (GO Pierre 2026-08-17).
//
// REGRESSION DATEE, 25 jours. Le test « runSelfAudit : studio aligne -> ok=true »
// (`studio_selfaudit.test.mjs:177`) a ete ecrit le 2026-07-15 (d415c9b) contre une formule a
// DEUX signaux : `ok = docDrift ∧ dormancy`. Le 2026-07-23, 74f3dd0 y a ajoute un TROISIEME —
// `contractSync.status === 'ok'` — que le montage du test ne peut PAS satisfaire : `tmpRepo()`
// cree un repertoire temporaire NU (ni `scripts/`, ni `.venv312`), ou le pont Python ne resout
// aucun interpreteur et rend `non_evaluable`. Le test est rouge depuis, dans une lane `.mjs`
// qui n'etait pas exercee.
//
// CE N'EST PAS un test « qui mesure l'environnement par conception » (cas
// `test_pong_git_status_vide`) : c'est un test DEVENU dependant de l'environnement par un
// changement de la surface qu'il valide. La difference compte pour le remede — on ne le rend
// pas conditionnel, on rend la dependance SUBSTITUABLE.
//
// PONTS INJECTABLES plutot que montage alourdi : `runSelfAudit(root, deps)` ou `deps` porte
// les deux ponts Python (`contractSync`, `solvabilityBudget`). Defaut = les vraies fonctions,
// donc AUCUN appelant de production n'est touche (3 appels, tous sans 2e argument). Le chemin
// NOMINAL redevient testable sans dependre d'un poste — ce qu'aucune des deux autres voies
// (saut nomme, ou venv dans le tmp) ne permettait.
import assert from 'node:assert/strict';
import test from 'node:test';
import { mkdtempSync, mkdirSync, writeFileSync, utimesSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

import { runSelfAudit } from './studio_selfaudit.mjs';

/** Depot temporaire NU, avec un manifeste d'attentes ALIGNE (aucune derive, aucun dormant).
 *
 * `connectors.reference` est OBLIGATOIRE : `auditConnectorDormancy` le joint sans le valider,
 * et un manifeste qui l'omet fait lever `join(root, undefined)`. Premiere redaction de cette
 * fixture : manifeste sans `reference` -> 6 tests rouges par MA faute, pas celle du code.
 * La fixture doit ressembler a un manifeste REEL, sinon elle mesure autre chose. */
function tmpRepoAligne() {
  const root = mkdtempSync(join(tmpdir(), 'sa-inj-'));
  const p = join(root, 'forge/studio_expectations.json');
  mkdirSync(join(p, '..'), { recursive: true });
  const ref = join(root, 'EVIDENCE/bundles/forge_telemetry.jsonl');
  mkdirSync(join(ref, '..'), { recursive: true });
  writeFileSync(ref, '');
  writeFileSync(p, JSON.stringify({
    doc_claims: [],
    connectors: { reference: 'EVIDENCE/bundles/forge_telemetry.jsonl',
                  watched: [], threshold_days: 3 },
  }));
  return root;
}

const PONT_OK = { status: 'ok', interpreter: 'stub', violations: [], anomalies: [] };

test('LE CAS DE LA REGRESSION : ponts injectes verts => ok=true', () => {
  // Sans injection, `contractSync` rend `non_evaluable` dans un tmp nu et `ok` est FAUX pour
  // une raison d'ENVIRONNEMENT, jamais de studio.
  const r = runSelfAudit(tmpRepoAligne(),
                         { contractSync: () => PONT_OK, solvabilityBudget: () => PONT_OK });
  assert.equal(r.contractSync.status, 'ok');
  assert.equal(r.ok, true, 'un studio aligne doit pouvoir rendre ok=true');
});

test('le pont reste DISCRIMINANT : contractSync en derive => ok=false', () => {
  // CONTRE-EPREUVE : l'injection ne doit pas neutraliser le signal. Un pont rouge doit
  // toujours faire tomber `ok` — sinon on aurait rendu le test vert en le vidant.
  const dérive = { status: 'derive', interpreter: 'stub', violations: [{ regle: 'x' }] };
  const r = runSelfAudit(tmpRepoAligne(),
                         { contractSync: () => dérive, solvabilityBudget: () => PONT_OK });
  assert.equal(r.ok, false);
  assert.equal(r.contractSync.violations.length, 1);
});

test('`non_evaluable` fait TOUJOURS tomber ok — statut distinct de `derive`', () => {
  const ne = { status: 'non_evaluable', interpreter: null, violations: [], detail: 'stub' };
  const r = runSelfAudit(tmpRepoAligne(),
                         { contractSync: () => ne, solvabilityBudget: () => PONT_OK });
  assert.equal(r.ok, false);
  assert.equal(r.contractSync.status, 'non_evaluable', 'jamais confondu avec `derive`');
});

test('le budget solvabilite reste HORS de ok, meme injecte en anomalie', () => {
  // Regime inchange (5190859) : il RAPPORTE, il ne ratifie pas.
  const anomalies = { status: 'ok', anomalies: [{ jeu: 'x', etat: 'CONTRAT_IGNORE' }] };
  const r = runSelfAudit(tmpRepoAligne(),
                         { contractSync: () => PONT_OK, solvabilityBudget: () => anomalies });
  assert.equal(r.solvabilityBudget.anomalies.length, 1);
  assert.equal(r.ok, true, 'le signal budget ne doit JAMAIS gater');
});

test('SANS deps : comportement inchange, les vrais ponts sont appeles', () => {
  // Retrocompatibilite : les 3 appels de production n'ont pas de 2e argument. Dans un tmp nu
  // le vrai pont rend `non_evaluable` — c'est precisement l'ancien comportement, conserve.
  const r = runSelfAudit(tmpRepoAligne());
  assert.ok(['ok', 'non_evaluable', 'derive'].includes(r.contractSync.status));
  assert.ok(Object.prototype.hasOwnProperty.call(r, 'solvabilityBudget'));
});

test('une injection PARTIELLE laisse l autre pont reel', () => {
  // `deps` est optionnel champ par champ : on ne doit pas devoir tout stuber pour en stuber un.
  const r = runSelfAudit(tmpRepoAligne(), { contractSync: () => PONT_OK });
  assert.equal(r.contractSync.status, 'ok');
  assert.ok(r.solvabilityBudget, 'le pont non injecte doit avoir tourne pour de vrai');
});

// --- SENSIBILITE DE `ok` AUX SIGNAUX DURS -------------------------------------------
//
// Le lot precedent (74d49cf) a rendu le pont injectable ; ces deux tests prouvent ce que
// l'injection RESTAURE : `ok` redevient sensible aux deux signaux durs. Sans pont vert,
// `ok` valait `false` DANS LES DEUX CAS — mesure du 2026-08-17 — et l'assertion
// `ok === false` du test jumeau etait garantie par l'environnement.

/** Depot temporaire porteur d'une derive doc ET d'un connecteur dormant. */
function tmpRepoDerivant() {
  const root = mkdtempSync(join(tmpdir(), 'sa-der-'));
  const ecrire = (rel, ageJours) => {
    const f = join(root, rel);
    mkdirSync(join(f, '..'), { recursive: true });
    writeFileSync(f, '');
    if (ageJours) {
      const t = (Date.now() - ageJours * 86400000) / 1000;
      utimesSync(f, t, t);
    }
  };
  ecrire('knowledge_base/search.mjs');                    // existe mais declare CIBLE -> derive
  ecrire('EVIDENCE/bundles/forge_telemetry.jsonl');
  ecrire('EVIDENCE/reports/forge_ledger_proposals.jsonl', 10); // dormant
  const p = join(root, 'forge/studio_expectations.json');
  mkdirSync(join(p, '..'), { recursive: true });
  writeFileSync(p, JSON.stringify({
    doc_claims: [{ path: 'knowledge_base/search.mjs', claimed: 'target', source: 'carte' }],
    connectors: { reference: 'EVIDENCE/bundles/forge_telemetry.jsonl',
                  watched: ['EVIDENCE/reports/forge_ledger_proposals.jsonl'], threshold_days: 3 },
  }));
  return root;
}

test('pont vert + derive REELLE => ok=false, et pour la BONNE raison', () => {
  const r = runSelfAudit(tmpRepoDerivant(),
                         { contractSync: () => PONT_OK, solvabilityBudget: () => PONT_OK });
  assert.equal(r.contractSync.status, 'ok', 'le pont ne doit PAS etre la cause du false');
  assert.equal(r.ok, false);
  assert.equal(r.docDrift.length, 1);
  assert.equal(r.dormancy.filter((d) => d.status === 'dormant').length, 1);
});

test('LA PAIRE QUI PROUVE LA SENSIBILITE : meme pont vert, sans derive => ok=true', () => {
  // Sans ce second cas, `ok === false` resterait indistinguable d'un `false` structurel.
  // C'est la COMPARAISON des deux qui etablit que `ok` depend bien des signaux durs.
  const r = runSelfAudit(tmpRepoAligne(),
                         { contractSync: () => PONT_OK, solvabilityBudget: () => PONT_OK });
  assert.equal(r.ok, true);
  assert.equal(r.docDrift.length, 0);
});

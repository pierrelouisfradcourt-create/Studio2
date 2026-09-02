// Tests de studio_selfaudit.mjs — node --test. Fixtures ephemeres, aucune dependance au repo reel.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, utimesSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  auditDocClaims,
  auditConnectorDormancy,
  auditMutationRegistry,
  runSelfAudit,
  evaluateDocClaims,
  generateStatusTable,
} from './studio_selfaudit.mjs';

const REPO_ROOT = resolve(fileURLToPath(new URL('.', import.meta.url)), '..');

function tmpRepo() {
  return mkdtempSync(join(tmpdir(), 'studioaudit-'));
}
function touch(root, rel, ageDays = 0) {
  const p = join(root, rel);
  mkdirSync(join(p, '..'), { recursive: true });
  writeFileSync(p, '{}\n');
  if (ageDays) {
    const t = Date.now() / 1000 - ageDays * 86400;
    utimesSync(p, t, t);
  }
  return p;
}
function writeManifest(root, obj) {
  const p = join(root, 'forge/studio_expectations.json');
  mkdirSync(join(p, '..'), { recursive: true });
  writeFileSync(p, JSON.stringify(obj));
}

test('doc-claim : marque « cible » mais le fichier EXISTE -> derive', () => {
  const root = tmpRepo();
  touch(root, 'knowledge_base/search.mjs');
  const findings = auditDocClaims(root, [
    { path: 'knowledge_base/search.mjs', claimed: 'target', source: 'carte X' },
  ]);
  assert.equal(findings.length, 1);
  assert.match(findings[0].drift, /EXISTE/);
});

test('doc-claim : marque « cible » et le fichier est ABSENT -> aligne (pas de derive)', () => {
  const root = tmpRepo();
  const findings = auditDocClaims(root, [
    { path: 'forge/agents_ccgs', claimed: 'target', source: 'carte Y' },
  ]);
  assert.equal(findings.length, 0);
});

test('doc-claim : marque « existe » mais le fichier est ABSENT -> derive', () => {
  const root = tmpRepo();
  const findings = auditDocClaims(root, [
    { path: 'forge/disparu.py', claimed: 'exists', source: 'carte Z' },
  ]);
  assert.equal(findings.length, 1);
  assert.match(findings[0].drift, /ABSENT/);
});

test('doc-claim : marque « existe » et le fichier EXISTE -> aligne', () => {
  const root = tmpRepo();
  touch(root, 'forge/verdict.py');
  const findings = auditDocClaims(root, [
    { path: 'forge/verdict.py', claimed: 'exists', source: 'carte' },
  ]);
  assert.equal(findings.length, 0);
});

test('connecteur bien plus vieux que la telemetrie -> dormant', () => {
  const root = tmpRepo();
  touch(root, 'EVIDENCE/bundles/forge_telemetry.jsonl', 0); // frais
  touch(root, 'EVIDENCE/reports/forge_ledger_proposals.jsonl', 10); // 10 jours de retard
  const findings = auditConnectorDormancy(root, {
    reference: 'EVIDENCE/bundles/forge_telemetry.jsonl',
    watched: ['EVIDENCE/reports/forge_ledger_proposals.jsonl'],
    threshold_days: 3,
  });
  assert.equal(findings.length, 1);
  assert.equal(findings[0].status, 'dormant');
  assert.ok(findings[0].lag_days >= 3);
});

test('connecteur recent -> aucune alerte de dormance', () => {
  const root = tmpRepo();
  touch(root, 'EVIDENCE/bundles/forge_telemetry.jsonl', 0);
  touch(root, 'EVIDENCE/reports/forge_ledger_proposals.jsonl', 1);
  const findings = auditConnectorDormancy(root, {
    reference: 'EVIDENCE/bundles/forge_telemetry.jsonl',
    watched: ['EVIDENCE/reports/forge_ledger_proposals.jsonl'],
    threshold_days: 3,
  });
  assert.equal(findings.filter((f) => f.status === 'dormant').length, 0);
});

test('connecteur jamais ecrit -> informatif, pas une dormance dure', () => {
  const root = tmpRepo();
  touch(root, 'EVIDENCE/bundles/forge_telemetry.jsonl', 0);
  const findings = auditConnectorDormancy(root, {
    reference: 'EVIDENCE/bundles/forge_telemetry.jsonl',
    watched: ['EVIDENCE/reports/forge_bible_proposals.jsonl'],
    threshold_days: 3,
  });
  assert.equal(findings[0].status, 'jamais_ecrit');
});

test('telemetrie de reference absente -> dormance non evaluable, pas d\'invention', () => {
  const root = tmpRepo();
  const findings = auditConnectorDormancy(root, {
    reference: 'EVIDENCE/bundles/forge_telemetry.jsonl',
    watched: ['EVIDENCE/reports/forge_ledger_proposals.jsonl'],
    threshold_days: 3,
  });
  assert.equal(findings[0].status, 'reference_absente');
});

test('runSelfAudit : integration bout-en-bout, derive -> ok=false', () => {
  const root = tmpRepo();
  // manifeste minimal ecrit dans le tmp repo
  touch(root, 'knowledge_base/search.mjs'); // existe mais declare cible -> derive
  touch(root, 'EVIDENCE/bundles/forge_telemetry.jsonl', 0);
  touch(root, 'EVIDENCE/reports/forge_ledger_proposals.jsonl', 10); // dormant
  writeManifest(root, {
    doc_claims: [{ path: 'knowledge_base/search.mjs', claimed: 'target', source: 'carte' }],
    connectors: {
      reference: 'EVIDENCE/bundles/forge_telemetry.jsonl',
      watched: ['EVIDENCE/reports/forge_ledger_proposals.jsonl'],
      threshold_days: 3,
    },
  });
  // PONT INJECTE (2026-08-17), meme motif que son jumeau `ok=true` plus bas. MESURE avant
  // correction : sans injection, `ok` valait `false` MEME sur un studio aligne — le pont
  // `contractSync` rend `non_evaluable` dans un depot temporaire nu, ce qui suffit a faire
  // tomber `ok`. L'assertion `ok === false` etait donc SURNUMERAIRE : garantie par
  // l'environnement, elle ne prouvait rien de la contribution de la derive a l'agregation.
  // (Les DEUX autres assertions, elles, discriminaient deja : `docDrift` et `dormant`
  // tombent a 0 sur un studio aligne. Ce test n'etait pas inerte, il surestimait sa portee.)
  const pontVert = { status: 'ok', interpreter: 'stub', violations: [], anomalies: [] };
  const r = runSelfAudit(root, { contractSync: () => pontVert,
                                 solvabilityBudget: () => pontVert });
  assert.equal(r.ok, false);
  assert.equal(r.docDrift.length, 1);
  assert.equal(r.dormancy.filter((d) => d.status === 'dormant').length, 1);
});

test('evaluateDocClaims : liste TOUS les elements (alignes + derives), pas seulement les derives', () => {
  const root = tmpRepo();
  touch(root, 'a/present.mjs');
  const rows = evaluateDocClaims(root, [
    { path: 'a/present.mjs', claimed: 'exists', source: 's' }, // aligne
    { path: 'a/present.mjs', claimed: 'target', source: 's' }, // derive (existe mais dit cible)
    { path: 'a/absent.mjs', claimed: 'target', source: 's' },  // aligne (encore a construire)
  ]);
  assert.equal(rows.length, 3);
  assert.equal(rows[0].aligned, true);
  assert.equal(rows[1].aligned, false);
  assert.equal(rows[2].aligned, true);
});

test('generateStatusTable : markdown deterministe, sans horodatage, avec le bon statut par ligne', () => {
  const root = tmpRepo();
  touch(root, 'knowledge_base/search.mjs'); // existe mais declare cible -> DERIVE
  touch(root, 'EVIDENCE/bundles/forge_telemetry.jsonl', 0);
  touch(root, 'EVIDENCE/reports/forge_ledger_proposals.jsonl', 10); // dormant
  writeManifest(root, {
    doc_claims: [
      { path: 'knowledge_base/search.mjs', claimed: 'target', source: 'carte' },
      { path: 'forge/agents_ccgs', claimed: 'target', source: 'carte' }, // absent -> aligne
    ],
    connectors: {
      reference: 'EVIDENCE/bundles/forge_telemetry.jsonl',
      watched: ['EVIDENCE/reports/forge_ledger_proposals.jsonl'],
      threshold_days: 3,
    },
  });
  const md1 = generateStatusTable(root);
  assert.match(md1, /AUTO-GÉNÉRÉ/);
  assert.match(md1, /knowledge_base\/search\.mjs.*DÉRIVE/);
  assert.match(md1, /agents_ccgs.*aligné \(encore à construire\)/);
  assert.match(md1, /dormant/);
  // deterministe : deux generations identiques (aucun horodatage -> zero bruit git)
  const md2 = generateStatusTable(root);
  assert.equal(md1, md2);
});

// --- A10 (Paquet A decision 10, ratifie Pierre 2026-08-28) : volet mutationRegistry ---

test('auditMutationRegistry : DEPOT REEL — check_mutation_registry.mjs tourne et repond', () => {
  const r = auditMutationRegistry(REPO_ROOT);
  assert.ok(['ok', 'derive', 'non_evaluable'].includes(r.status), r.status);
  // Le registre reel est ACCEPTED/VERSIONED discipline — s'il derive un jour, ce test doit
  // le VOIR (probleme non vide), pas juste tolerer n'importe quel statut en silence.
  if (r.status === 'derive') assert.ok(r.problems.length > 0, r.detail);
  if (r.status === 'ok') assert.ok(r.stats && r.stats.mutations > 0, 'stats.mutations attendu > 0');
});

test('auditMutationRegistry : checker absent -> non_evaluable, jamais un throw', () => {
  const root = tmpRepo(); // depot nu : forge/check_mutation_registry.mjs n'existe pas
  const r = auditMutationRegistry(root);
  assert.equal(r.status, 'non_evaluable');
  assert.match(r.detail, /absent/);
});

test('runSelfAudit : mutationRegistry est RAPPORTE mais n entre PAS dans `ok` (advisory)', () => {
  const root = tmpRepo();
  touch(root, 'EVIDENCE/bundles/forge_telemetry.jsonl', 0);
  touch(root, 'EVIDENCE/reports/forge_ledger_proposals.jsonl', 1);
  writeManifest(root, {
    doc_claims: [{ path: 'forge/agents_ccgs', claimed: 'target', source: 'carte' }],
    connectors: {
      reference: 'EVIDENCE/bundles/forge_telemetry.jsonl',
      watched: ['EVIDENCE/reports/forge_ledger_proposals.jsonl'],
      threshold_days: 3,
    },
  });
  const pontVert = { status: 'ok', interpreter: 'stub', violations: [], anomalies: [] };
  const pontRegistreEnDerive = { status: 'derive', problems: ['id duplique: X'], stats: null,
    detail: '1 probleme' };
  const r = runSelfAudit(root, { contractSync: () => pontVert,
                                 solvabilityBudget: () => pontVert,
                                 mutationRegistry: () => pontRegistreEnDerive });
  assert.deepEqual(r.mutationRegistry, pontRegistreEnDerive);
  // meme registre EN DERIVE, le studio reste aligne : le signal ne ratifie jamais.
  assert.equal(r.ok, true);
});

test('runSelfAudit : studio aligne -> ok=true', () => {
  const root = tmpRepo();
  touch(root, 'EVIDENCE/bundles/forge_telemetry.jsonl', 0);
  touch(root, 'EVIDENCE/reports/forge_ledger_proposals.jsonl', 1); // frais
  writeManifest(root, {
    doc_claims: [{ path: 'forge/agents_ccgs', claimed: 'target', source: 'carte' }], // cible + absent = aligne
    connectors: {
      reference: 'EVIDENCE/bundles/forge_telemetry.jsonl',
      watched: ['EVIDENCE/reports/forge_ledger_proposals.jsonl'],
      threshold_days: 3,
    },
  });
  // PONT PYTHON INJECTE (2026-08-17). Ce test etait ROUGE depuis 25 jours : ecrit le
  // 2026-07-15 (d415c9b) contre `ok = docDrift ∧ dormancy`, il a vu 74f3dd0 ajouter
  // `contractSync.status === 'ok'` a la formule le 2026-07-23 — condition que son montage ne
  // peut PAS satisfaire, `tmpRepo()` creant un depot NU (ni `scripts/`, ni `.venv312`) ou le
  // pont ne resout aucun interpreteur et rend `non_evaluable`. `ok` tombait donc pour une
  // raison d'ENVIRONNEMENT, jamais de studio.
  // On INJECTE plutot que de sauter : le chemin nominal redevient reellement teste, et
  // `studio_selfaudit_injection.test.mjs` verifie a cote que le pont reste DISCRIMINANT
  // (derive et non_evaluable font toujours tomber `ok`).
  const pontVert = { status: 'ok', interpreter: 'stub', violations: [], anomalies: [] };
  const r = runSelfAudit(root, { contractSync: () => pontVert,
                                 solvabilityBudget: () => pontVert });
  assert.equal(r.ok, true);
});

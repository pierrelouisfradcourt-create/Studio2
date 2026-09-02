// Tests du branchement `registryDivergences` de studio_selfaudit.mjs — node --test.
// Fixtures ephemeres, aucune dependance au depot reel (meme regime que
// studio_selfaudit.test.mjs, non modifie par ce lot).
//
// Dette de preuve fermee ici. `apply_decisions.reconcileRegistries` calculait les
// divergences registre <-> etat de proposition et les imprimait — sans AUCUN lecteur
// mecanique : les divergences n'etaient visibles que si quelqu'un lancait l'outil a la
// main. Le self-audit, lui, est lu a chaque session et son resume s'affiche au hook
// pre-commit : c'est le consommateur qui manquait. Ce lot l'a branche, mais
// `studio_selfaudit.test.mjs` n'a JAMAIS ete modifie — le champ neuf n'etait couvert
// par aucune assertion. Correction d'un statut que j'avais moi-meme annonce TESTED
// alors qu'il n'etait que prouve en vivo.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { runSelfAudit } from './studio_selfaudit.mjs';

function tmpRepo() {
  return mkdtempSync(join(tmpdir(), 'studioaudit-div-'));
}

function write(root, rel, content) {
  const p = join(root, rel);
  mkdirSync(join(p, '..'), { recursive: true });
  writeFileSync(p, content);
  return p;
}

function baseRepo(root) {
  // Manifeste minimal aligne : ni derive doc, ni connecteur dormant — pour que seule
  // la surface des divergences varie d'un test a l'autre.
  write(root, 'EVIDENCE/bundles/forge_telemetry.jsonl', '{}\n');
  write(root, 'forge/studio_expectations.json', JSON.stringify({
    doc_claims: [{ path: 'forge/agents_ccgs', claimed: 'target', source: 'carte' }],
    connectors: {
      reference: 'EVIDENCE/bundles/forge_telemetry.jsonl',
      watched: [],
      threshold_days: 3,
    },
  }));
}

// Registre PRODUIT au format lu par readRegistryIds (extraction line-based des `- id:`).
function writeRegistry(root, ids) {
  write(root, 'forge/standard/capabilities.yaml',
    'capabilities:\n' + ids.map((i) => `  - id: ${i}\n    kind: game\n`).join(''));
}

function writeProposals(root, lignes) {
  write(root, 'EVIDENCE/reports/forge_capability_gap_proposals.jsonl',
    lignes.map((l) => JSON.stringify(l)).join('\n') + '\n');
}

test('registryDivergences : le champ EXISTE dans le rapport (le lecteur mecanique est branche)', () => {
  const root = tmpRepo();
  baseRepo(root);
  const r = runSelfAudit(root);
  assert.ok(r.registryDivergences, 'runSelfAudit doit porter registryDivergences');
  assert.equal(r.registryDivergences.status, 'ok');
  assert.ok(Array.isArray(r.registryDivergences.divergences));
});

test('capacite AU REGISTRE avec une proposition NON tranchee -> divergence rapportee', () => {
  const root = tmpRepo();
  baseRepo(root);
  writeRegistry(root, ['game.collision']);
  writeProposals(root, [{ capability_id: 'game.collision', ts: 1 }]); // pas de review_status
  const r = runSelfAudit(root);
  const sujets = r.registryDivergences.divergences.map((d) => d.subject);
  assert.deepEqual(sujets, ['game.collision']);
});

test('proposition DEJA tranchee -> aucune divergence (la boucle est fermee)', () => {
  const root = tmpRepo();
  baseRepo(root);
  writeRegistry(root, ['game.collision']);
  writeProposals(root, [{ capability_id: 'game.collision', ts: 1, review_status: 'ACCEPTED' }]);
  const r = runSelfAudit(root);
  assert.deepEqual(r.registryDivergences.divergences, []);
});

test('capacite proposee mais ABSENTE du registre -> pas une divergence de ce type', () => {
  // La reconciliation regarde le registre vers les propositions, pas l'inverse :
  // une proposition en attente n'est pas une incoherence, c'est le regime normal.
  const root = tmpRepo();
  baseRepo(root);
  writeRegistry(root, []);
  writeProposals(root, [{ capability_id: 'game.jamais_ratifiee', ts: 1 }]);
  const r = runSelfAudit(root);
  assert.deepEqual(r.registryDivergences.divergences, []);
});

test('les divergences RAPPORTENT, elles ne font PAS basculer le verdict', () => {
  // Doctrine 2026-08-10 : la reconciliation rapporte, elle ne ratifie jamais. En faire
  // un gate dur serait une decision Pierre, pas un cablage. Propriete testee : `ok` est
  // IDENTIQUE avec et sans divergence — on ne teste PAS `ok === true`, qui depend de
  // contractSync (non evaluable sur une fixture ephemere, cause du rouge de baseline
  // de studio_selfaudit.test.mjs).
  const sans = tmpRepo();
  baseRepo(sans);
  writeRegistry(sans, ['game.collision']);
  writeProposals(sans, [{ capability_id: 'game.collision', ts: 1, review_status: 'ACCEPTED' }]);
  const rSans = runSelfAudit(sans);

  const avec = tmpRepo();
  baseRepo(avec);
  writeRegistry(avec, ['game.collision']);
  writeProposals(avec, [{ capability_id: 'game.collision', ts: 1 }]);
  const rAvec = runSelfAudit(avec);

  assert.equal(rSans.registryDivergences.divergences.length, 0);
  assert.equal(rAvec.registryDivergences.divergences.length, 1);
  assert.equal(rAvec.ok, rSans.ok, 'une divergence ne doit rien changer au verdict');
});

test('registre illisible -> statut degrade, jamais une exception ni un faux vert', () => {
  const root = tmpRepo();
  baseRepo(root);
  write(root, 'forge/standard/capabilities.yaml', 'capabilities:\n  - id: game.collision\n');
  write(root, 'EVIDENCE/reports/forge_capability_gap_proposals.jsonl', '{ pas du json\n');
  const r = runSelfAudit(root);
  assert.ok(['ok', 'non_evaluable'].includes(r.registryDivergences.status));
  assert.ok(Array.isArray(r.registryDivergences.divergences),
    'un fichier de proposition corrompu ne doit ni lever ni fabriquer de divergence');
});

test('learning_curve.jsonl est surveille comme connecteur (2e volet du lot)', () => {
  const root = tmpRepo();
  baseRepo(root);
  // Reference fraiche, connecteur JAMAIS ecrit : statut informatif, pas une dormance dure.
  write(root, 'forge/studio_expectations.json', JSON.stringify({
    doc_claims: [],
    connectors: {
      reference: 'EVIDENCE/bundles/forge_telemetry.jsonl',
      watched: ['knowledge_base/learning_curve.jsonl'],
      threshold_days: 3,
    },
  }));
  const r = runSelfAudit(root);
  const noms = r.dormancy.map((d) => d.connector);
  assert.ok(noms.includes('knowledge_base/learning_curve.jsonl'),
    'le connecteur surveille doit apparaitre dans le rapport de dormance');
});

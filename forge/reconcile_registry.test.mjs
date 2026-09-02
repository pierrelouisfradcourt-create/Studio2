// reconcile_registry.test.mjs — FERMETURE registre <-> etat de proposition (2026-08-10).
//
// DEFAUT MESURE ce jour-la, sur donnees reelles : 7 capacites Tetris etaient PRESENTES dans
// forge/standard/capabilities.yaml (ratifiees par Pierre) alors que leurs 39
// occurrences de proposition portaient toujours PROPOSED. Elles remontaient donc dans
// pending_review comme « a trancher » -- 7 sujets de bruit dans la file que Pierre lit.
//
// CAUSE RACINE : la ratification a DEUX points d'entree independants pour UN SEUL acte humain
//   (a) ecrire la capacite dans le registre ;
//   (b) ecrire une ligne dans pending_review_decisions.jsonl.
// La chaine (b) -> review_status existait et fonctionnait (prouvee par les cas REJECTED reels
// chesscolor/collect_runner du 2026-07-20). RIEN ne verifiait que (a) et (b) s'accordent.
//
// CE QUI EST CABLE ICI : un RAPPORT de divergence. Jamais une ratification automatique --
// apposer review_status parce qu'une capacite est au registre inverserait la doctrine
// (`propose_capability_gap` : « depose une proposition que Pierre promeut »).
//
// Fichier NOUVEAU : ne modifie aucun test existant. Fixtures sous mkdtemp uniquement.
// claim_verdict: NO_CLAIM_ALLOWED.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

import { QUEUE_FILES } from './pending_review.mjs';
import {
  planDecisions, writeChanges, readRegistryIds, reconcileRegistries,
} from './apply_decisions.mjs';

const PROD_QUEUE = 'forge_capability_gap_proposals';
const FACT_QUEUE = 'forge_factory_capability_gap_proposals';
const PROD_PATH = 'EVIDENCE/reports/forge_capability_gap_proposals.jsonl';
const FACT_PATH = 'EVIDENCE/reports/forge_factory_capability_gap_proposals.jsonl';
const PROD_REG = 'forge/standard/capabilities.yaml';
const FACT_REG = 'forge/standard/factory_capabilities.yaml';

function makeRepo() {
  const root = mkdtempSync(join(tmpdir(), 'reconc_'));
  mkdirSync(join(root, 'EVIDENCE', 'reports'), { recursive: true });
  mkdirSync(join(root, 'scripts', 'forge', 'standard'), { recursive: true });
  return root;
}

function writeJsonl(root, rel, records) {
  writeFileSync(join(root, rel), records.map((r) => JSON.stringify(r)).join('\n') + '\n', 'utf-8');
}

function readJsonl(root, rel) {
  return readFileSync(join(root, rel), 'utf-8').split('\n').filter(Boolean).map((l) => JSON.parse(l));
}

function writeRegistry(root, rel, key, ids) {
  const body = [`schema_version: 1`, `${key}:`]
    .concat(ids.map((id) => `  - id: ${id}\n    statement: "s"\n    single_owner: true`))
    .join('\n');
  writeFileSync(join(root, rel), body + '\n', 'utf-8');
}

function gap(capability_id, project = 'pacman', extra = {}) {
  return {
    type: 'capability_gap', capability_id, source_line_id: 'core.x',
    run_id: 'r1', project, status: 'PROPOSED', ts: 1_800_000_000, ...extra,
  };
}

function decisions(root, rel, lines) {
  writeFileSync(join(root, rel), lines.map((l) => JSON.stringify(l)).join('\n') + '\n', 'utf-8');
}

// --- la table de correspondance ----------------------------------------------------------

test('QUEUE_FILES porte la correspondance queue -> registre (source unique, pas de table parallele)', () => {
  const prod = QUEUE_FILES.find((q) => q.id === PROD_QUEUE);
  const fact = QUEUE_FILES.find((q) => q.id === FACT_QUEUE);
  assert.equal(prod.registry.path, PROD_REG);
  assert.equal(prod.registry.key, 'capabilities');
  assert.equal(fact.registry.path, FACT_REG);
  assert.equal(fact.registry.key, 'factory_capabilities');
  // Une queue sans registre est hors reconciliation, jamais une erreur.
  const sansRegistre = QUEUE_FILES.filter((q) => !q.registry).map((q) => q.id);
  assert.ok(sansRegistre.length > 0, 'toutes les queues ne sont pas des registres de capacites');
});

// --- lecture du registre (extraction line-based, limite assumee) --------------------------

test('readRegistryIds extrait les id et s arrete a la cle de premier niveau suivante', () => {
  const root = makeRepo();
  writeFileSync(join(root, FACT_REG), [
    '# commentaire ignore',
    'schema_version: 1',
    'namespaces:',
    '  - "probe."',
    '  - "proof."',
    'factory_capabilities:',
    '  - id: probe.state_snapshot',
    '    statement: "s"',
    '  - id: proof.replay',
    '    statement: "s"',
  ].join('\n'), 'utf-8');
  const r = readRegistryIds(root, { path: FACT_REG, key: 'factory_capabilities' });
  assert.equal(r.status, 'OK');
  // `namespaces` ne doit PAS polluer : ses entrees ne sont pas des `- id:`.
  assert.deepEqual([...r.ids].sort(), ['probe.state_snapshot', 'proof.replay']);
  rmSync(root, { recursive: true, force: true });
});

test('readRegistryIds : registre absent -> ABSENT, aucune exception', () => {
  const root = makeRepo();
  const r = readRegistryIds(root, { path: PROD_REG, key: 'capabilities' });
  assert.equal(r.status, 'ABSENT');
  assert.equal(r.ids.size, 0);
  rmSync(root, { recursive: true, force: true });
});

// --- (5) proposition DEJA ratifiee : LE defaut mesure --------------------------------------

test('divergence detectee : capacite au registre, proposition toujours PROPOSED', () => {
  const root = makeRepo();
  writeRegistry(root, PROD_REG, 'capabilities', ['game.gravity']);
  writeRegistry(root, FACT_REG, 'factory_capabilities', []);
  writeJsonl(root, PROD_PATH, [gap('game.gravity', 'tetris'), gap('game.gravity', 'tetris'), gap('maze.walkable')]);
  writeJsonl(root, FACT_PATH, []);

  const { divergences } = reconcileRegistries(root);
  assert.equal(divergences.length, 1);
  assert.equal(divergences[0].subject, 'game.gravity');
  assert.equal(divergences[0].occurrences, 2, 'compte les occurrences, pas les sujets');
  assert.equal(divergences[0].queue, PROD_QUEUE);
  // `maze.walkable` n est PAS au registre -> coherent, aucune divergence.
  rmSync(root, { recursive: true, force: true });
});

test('AUCUNE divergence quand la proposition est deja tranchee (la boucle est fermee)', () => {
  const root = makeRepo();
  writeRegistry(root, PROD_REG, 'capabilities', ['game.gravity']);
  writeRegistry(root, FACT_REG, 'factory_capabilities', []);
  writeJsonl(root, PROD_PATH, [gap('game.gravity', 'tetris', { review_status: 'ACCEPTED' })]);
  writeJsonl(root, FACT_PATH, []);
  assert.equal(reconcileRegistries(root).divergences.length, 0);
  rmSync(root, { recursive: true, force: true });
});

test('le rapport n APPOSE JAMAIS de statut : ratifier reste un acte humain', () => {
  const root = makeRepo();
  writeRegistry(root, PROD_REG, 'capabilities', ['game.gravity']);
  writeRegistry(root, FACT_REG, 'factory_capabilities', []);
  writeJsonl(root, PROD_PATH, [gap('game.gravity', 'tetris')]);
  writeJsonl(root, FACT_PATH, []);
  const avant = readFileSync(join(root, PROD_PATH), 'utf-8');
  reconcileRegistries(root);
  assert.equal(readFileSync(join(root, PROD_PATH), 'utf-8'), avant, 'aucune ecriture');
  assert.equal(readJsonl(root, PROD_PATH)[0].review_status, undefined);
  rmSync(root, { recursive: true, force: true });
});

// --- (1) ACCEPTED et (2) REJECTED : comportements DISTINCTS --------------------------------

function scenarioDecision(root, verdict) {
  writeRegistry(root, PROD_REG, 'capabilities', []);
  writeRegistry(root, FACT_REG, 'factory_capabilities', []);
  writeJsonl(root, PROD_PATH, [gap('maze.walkable')]);
  writeJsonl(root, FACT_PATH, []);
  decisions(root, 'EVIDENCE/reports/dec.jsonl', [
    { ts: '2026-08-10', queue: PROD_QUEUE, item: 'maze.walkable', decision: verdict, motif: 'fixture' },
  ]);
  const plan = planDecisions(root, 'EVIDENCE/reports/dec.jsonl');
  writeChanges(root, plan.fileState);
  return { plan, rows: readJsonl(root, PROD_PATH) };
}

test('ACCEPT -> review_status ACCEPTED, registre INCHANGE (la promotion reste humaine)', () => {
  const root = makeRepo();
  const { rows } = scenarioDecision(root, 'ACCEPT');
  assert.equal(rows[0].review_status, 'ACCEPTED');
  assert.notEqual(rows[0].review_status, 'PROPOSED');
  const reg = readRegistryIds(root, { path: PROD_REG, key: 'capabilities' });
  assert.equal(reg.ids.size, 0, 'aucune ecriture automatique du registre');
  rmSync(root, { recursive: true, force: true });
});

test('REJECT -> review_status REJECTED, registre INCHANGE', () => {
  const root = makeRepo();
  const { rows } = scenarioDecision(root, 'REJECT');
  assert.equal(rows[0].review_status, 'REJECTED');
  assert.notEqual(rows[0].review_status, 'PROPOSED');
  const reg = readRegistryIds(root, { path: PROD_REG, key: 'capabilities' });
  assert.equal(reg.ids.size, 0);
  rmSync(root, { recursive: true, force: true });
});

test('ACCEPTED et REJECTED sont des etats DISTINCTS', () => {
  const a = makeRepo(); const b = makeRepo();
  const ra = scenarioDecision(a, 'ACCEPT').rows[0].review_status;
  const rb = scenarioDecision(b, 'REJECT').rows[0].review_status;
  assert.notEqual(ra, rb);
  rmSync(a, { recursive: true, force: true }); rmSync(b, { recursive: true, force: true });
});

// --- (4) idempotence -----------------------------------------------------------------------

test('idempotence : rejouer ACCEPT ne cree ni ligne ni double changement', () => {
  const root = makeRepo();
  const { rows: r1 } = scenarioDecision(root, 'ACCEPT');
  assert.equal(r1.length, 1);
  const plan2 = planDecisions(root, 'EVIDENCE/reports/dec.jsonl');
  assert.equal(plan2.changes.length, 0, '2e passe : aucun changement');
  assert.equal(plan2.already_up_to_date.length, 1);
  writeChanges(root, plan2.fileState);
  const r2 = readJsonl(root, PROD_PATH);
  assert.equal(r2.length, 1, 'aucune ligne dupliquee');
  assert.equal(r2[0].review_status, 'ACCEPTED');
  rmSync(root, { recursive: true, force: true });
});

test('idempotence : rejouer REJECT ne corrompt pas la queue', () => {
  const root = makeRepo();
  scenarioDecision(root, 'REJECT');
  const plan2 = planDecisions(root, 'EVIDENCE/reports/dec.jsonl');
  assert.equal(plan2.changes.length, 0);
  assert.equal(plan2.already_up_to_date.length, 1);
  assert.equal(readJsonl(root, PROD_PATH).length, 1);
  rmSync(root, { recursive: true, force: true });
});

// --- (3) separation produit / usine --------------------------------------------------------

test('une decision USINE ne touche jamais la file ni le registre PRODUIT', () => {
  const root = makeRepo();
  writeRegistry(root, PROD_REG, 'capabilities', []);
  writeRegistry(root, FACT_REG, 'factory_capabilities', []);
  writeJsonl(root, PROD_PATH, [gap('maze.walkable')]);
  writeJsonl(root, FACT_PATH, [gap('probe.observable')]);
  decisions(root, 'EVIDENCE/reports/dec.jsonl', [
    { ts: '2026-08-10', queue: FACT_QUEUE, item: 'probe.observable', decision: 'ACCEPT', motif: 'fixture' },
  ]);
  const plan = planDecisions(root, 'EVIDENCE/reports/dec.jsonl');
  writeChanges(root, plan.fileState);
  assert.equal(readJsonl(root, FACT_PATH)[0].review_status, 'ACCEPTED');
  assert.equal(readJsonl(root, PROD_PATH)[0].review_status, undefined, 'file produit intacte');
  assert.equal(readRegistryIds(root, { path: PROD_REG, key: 'capabilities' }).ids.size, 0);
  rmSync(root, { recursive: true, force: true });
});

test('intersection des registres vide apres traitement', () => {
  const root = makeRepo();
  writeRegistry(root, PROD_REG, 'capabilities', ['maze.walkable']);
  writeRegistry(root, FACT_REG, 'factory_capabilities', ['probe.observable']);
  writeJsonl(root, PROD_PATH, [gap('maze.walkable')]);
  writeJsonl(root, FACT_PATH, [gap('probe.observable')]);
  reconcileRegistries(root);
  const p = readRegistryIds(root, { path: PROD_REG, key: 'capabilities' }).ids;
  const f = readRegistryIds(root, { path: FACT_REG, key: 'factory_capabilities' }).ids;
  assert.deepEqual([...p].filter((x) => f.has(x)), [], 'registry_product ∩ registry_factory = ∅');
  rmSync(root, { recursive: true, force: true });
});

test('une divergence produit et une divergence usine sont rapportees SEPAREMENT', () => {
  const root = makeRepo();
  writeRegistry(root, PROD_REG, 'capabilities', ['maze.walkable']);
  writeRegistry(root, FACT_REG, 'factory_capabilities', ['probe.observable']);
  writeJsonl(root, PROD_PATH, [gap('maze.walkable')]);
  writeJsonl(root, FACT_PATH, [gap('probe.observable')]);
  const { divergences } = reconcileRegistries(root);
  assert.equal(divergences.length, 2);
  const byQueue = Object.fromEntries(divergences.map((d) => [d.queue, d]));
  assert.equal(byQueue[PROD_QUEUE].registry, PROD_REG);
  assert.equal(byQueue[FACT_QUEUE].registry, FACT_REG);
  rmSync(root, { recursive: true, force: true });
});

// --- (6) proposition inexistante ------------------------------------------------------------

test('decision visant une proposition inexistante -> orpheline, jamais inventee', () => {
  const root = makeRepo();
  writeRegistry(root, PROD_REG, 'capabilities', []);
  writeRegistry(root, FACT_REG, 'factory_capabilities', []);
  writeJsonl(root, PROD_PATH, [gap('maze.walkable')]);
  writeJsonl(root, FACT_PATH, []);
  decisions(root, 'EVIDENCE/reports/dec.jsonl', [
    { ts: '2026-08-10', queue: PROD_QUEUE, item: 'capacite.qui.n.existe.pas', decision: 'ACCEPT', motif: 'fixture' },
  ]);
  const plan = planDecisions(root, 'EVIDENCE/reports/dec.jsonl');
  assert.equal(plan.changes.length, 0);
  assert.equal(plan.orphaned.length, 1);
  assert.equal(readJsonl(root, PROD_PATH).length, 1, 'aucune proposition creee');
  rmSync(root, { recursive: true, force: true });
});

// --- (7) cas ambigu REEL : un sujet a N occurrences ------------------------------------------

test('un sujet a plusieurs occurrences : TOUTES tranchees, aucune laissee derriere', () => {
  const root = makeRepo();
  writeRegistry(root, PROD_REG, 'capabilities', []);
  writeRegistry(root, FACT_REG, 'factory_capabilities', []);
  // Cas REEL : game.gravity porte 6 occurrences issues de 6 runs Tetris distincts.
  writeJsonl(root, PROD_PATH, [gap('game.gravity', 'tetris'), gap('game.gravity', 'tetris'), gap('game.gravity', 'tetris')]);
  writeJsonl(root, FACT_PATH, []);
  decisions(root, 'EVIDENCE/reports/dec.jsonl', [
    { ts: '2026-08-10', queue: PROD_QUEUE, item: 'game.gravity', decision: 'ACCEPT', motif: 'fixture' },
  ]);
  const plan = planDecisions(root, 'EVIDENCE/reports/dec.jsonl');
  writeChanges(root, plan.fileState);
  assert.equal(plan.changes.length, 3, 'la decision porte sur le SUJET, donc sur ses 3 occurrences');
  assert.deepEqual(readJsonl(root, PROD_PATH).map((r) => r.review_status), ['ACCEPTED', 'ACCEPTED', 'ACCEPTED']);
  rmSync(root, { recursive: true, force: true });
});

test('conflit : une 2e decision de verdict oppose n ECRASE PAS la premiere', () => {
  const root = makeRepo();
  scenarioDecision(root, 'ACCEPT');
  decisions(root, 'EVIDENCE/reports/dec.jsonl', [
    { ts: '2026-08-11', queue: PROD_QUEUE, item: 'maze.walkable', decision: 'REJECT', motif: 'fixture' },
  ]);
  const plan = planDecisions(root, 'EVIDENCE/reports/dec.jsonl');
  assert.equal(plan.changes.length, 0);
  assert.equal(plan.conflicts.length, 1);
  assert.equal(readJsonl(root, PROD_PATH)[0].review_status, 'ACCEPTED', 'etat initial preserve');
  rmSync(root, { recursive: true, force: true });
});

// --- (8) compatibilite pending_review --------------------------------------------------------

test('le rapport de divergence est calcule AVANT ecriture -> doit etre recalcule apres --apply', () => {
  // Defaut mesure le 2026-08-10 : `--apply` affichait 7 divergences alors que l'ecriture
  // venait de les fermer. La cause n'est pas la donnee, c'est l'ORDRE : planDecisions
  // calcule la reconciliation, writeChanges ecrit ensuite. Ce test fige le contrat des
  // deux appels pour que main() ne puisse pas revenir a un rapport perime.
  const root = makeRepo();
  writeRegistry(root, PROD_REG, 'capabilities', ['game.gravity']);
  writeRegistry(root, FACT_REG, 'factory_capabilities', []);
  writeJsonl(root, PROD_PATH, [gap('game.gravity', 'tetris'), gap('game.gravity', 'tetris')]);
  writeJsonl(root, FACT_PATH, []);
  decisions(root, 'EVIDENCE/reports/dec.jsonl', [
    { ts: '2026-08-10', queue: PROD_QUEUE, item: 'game.gravity', decision: 'ACCEPT', motif: 'fixture' },
  ]);

  const plan = planDecisions(root, 'EVIDENCE/reports/dec.jsonl');
  assert.equal(plan.registry_divergences.length, 1, 'AVANT ecriture : la divergence existe encore');

  writeChanges(root, plan.fileState);
  const apres = reconcileRegistries(root);
  assert.equal(apres.divergences.length, 0, 'APRES ecriture : la boucle est fermee');
  assert.deepEqual(readJsonl(root, PROD_PATH).map((r) => r.review_status), ['ACCEPTED', 'ACCEPTED']);
  rmSync(root, { recursive: true, force: true });
});

test('planDecisions expose registry_divergences et registries (consommables par un rapport)', () => {
  const root = makeRepo();
  writeRegistry(root, PROD_REG, 'capabilities', ['game.gravity']);
  writeRegistry(root, FACT_REG, 'factory_capabilities', []);
  writeJsonl(root, PROD_PATH, [gap('game.gravity', 'tetris')]);
  writeJsonl(root, FACT_PATH, []);
  decisions(root, 'EVIDENCE/reports/dec.jsonl', []);
  const plan = planDecisions(root, 'EVIDENCE/reports/dec.jsonl');
  assert.ok(Array.isArray(plan.registry_divergences));
  assert.equal(plan.registry_divergences.length, 1);
  assert.ok(plan.registries.some((r) => r.registry === PROD_REG && r.registry_status === 'OK'));
  rmSync(root, { recursive: true, force: true });
});

// pending_review_loop.test.mjs — oracle de la REPARATION DE LA BOUCLE DE REVUE (2026-08-10).
//
// Audit du 2026-08-10 : la boucle proposition -> revue -> decision -> preuve ne se refermait
// pas. Trois defauts mesures, independants, qui se composaient :
//
//   (1) `pending_review.normalizeItem` jetait `review_status` (hors PASSTHROUGH_FIELDS) : les
//       10 propositions tranchees le 2026-07-20 remontaient encore 21 jours plus tard comme a
//       trancher, indistinguables d'une proposition jamais vue. Trancher ne retirait rien.
//   (2) `apply_decisions.MATCH_FIELDS` couvrait 3 queues sur 6 : les 42 items de
//       forge_capability_gap_proposals etaient STRUCTURELLEMENT indecidables — et c'etaient les
//       seuls que l'ecran affichait sous son plafond (tri par occurrences desc, 42 items
//       a 6 occurrences issus d'un seul run monopolisaient les rangs 1 a 42).
//   (3) une decision au verbe invalide (ex. "POSTPONE", propose par la table elle-meme)
//       disparaissait dans `skipped_meta`, indistinguable d'une note de session legitime.
//
// Fichier NOUVEAU : ne modifie AUCUN test existant (44 verts avant/apres cette reparation).
// Toutes les fixtures vivent sous mkdtemp — jamais EVIDENCE/reports/ reel.
// claim_verdict: NO_CLAIM_ALLOWED.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

import {
  QUEUE_FILES, aggregate, normalizeItem, selectDisplayed,
} from './pending_review.mjs';
import {
  MATCH_FIELDS, classifyDecision, planDecisions, writeChanges,
} from './apply_decisions.mjs';

const NOW = 1_800_000_000; // horloge figee : aucun test ne depend de la date reelle

function makeRepo() {
  const root = mkdtempSync(join(tmpdir(), 'prloop_'));
  mkdirSync(join(root, 'EVIDENCE', 'reports'), { recursive: true });
  return root;
}

function writeQueue(root, rel, records) {
  writeFileSync(join(root, rel), records.map((r) => JSON.stringify(r)).join('\n') + '\n', 'utf-8');
}

function cfg(id) {
  return QUEUE_FILES.find((q) => q.id === id);
}

// --- (1) le champ qui etait detruit ------------------------------------------------------

test('normalizeItem CONSERVE review_status/review_ts/review_source (le point de rupture)', () => {
  const it = normalizeItem(cfg('forge_ledger_proposals'), {
    run_id: 'r1', project: 'p1', ts: NOW - 86400,
    review_status: 'REJECTED', review_ts: '2026-07-20',
    review_source: 'EVIDENCE/reports/pending_review_decisions.jsonl',
  }, NOW);

  assert.equal(it.review_status, 'REJECTED');
  assert.equal(it.reviewed, true);
  assert.equal(it.review_ts, '2026-07-20');
  assert.equal(it.fields.review_status, 'REJECTED');
  assert.equal(it.fields.review_source, 'EVIDENCE/reports/pending_review_decisions.jsonl');
});

test('normalizeItem: proposition jamais tranchee -> review_status null, reviewed false', () => {
  const it = normalizeItem(cfg('forge_ledger_proposals'), { run_id: 'r1', project: 'p1', ts: NOW }, NOW);
  assert.equal(it.review_status, null);
  assert.equal(it.reviewed, false);
});

test('normalizeItem: review_status vide ou non-chaine -> jamais devine comme tranche', () => {
  for (const bad of ['', '   ', 42, null, {}, []]) {
    const it = normalizeItem(cfg('forge_ledger_proposals'), { run_id: 'r', project: 'p', ts: NOW, review_status: bad }, NOW);
    assert.equal(it.reviewed, false, `review_status=${JSON.stringify(bad)} ne doit pas compter comme tranche`);
  }
});

test('aggregate: un item tranche SORT de la file par defaut (une decision a un effet visible)', () => {
  const root = makeRepo();
  writeQueue(root, 'EVIDENCE/reports/forge_ledger_proposals.jsonl', [
    { run_id: 'r-tranche', project: 'p1', ts: NOW - 86400, review_status: 'ACCEPTED' },
    { run_id: 'r-attente', project: 'p2', ts: NOW - 86400 },
  ]);

  const res = aggregate(root, NOW);
  assert.equal(res.total_items, 2, 'le volume total reste annonce — rien n\'est cache');
  assert.equal(res.reviewed_items, 1);
  assert.equal(res.ranked.length, 1, 'seul l\'item non tranche reste a faire');
  assert.equal(res.ranked[0].origin, 'r-attente');

  rmSync(root, { recursive: true, force: true });
});

test('aggregate --include-reviewed: les tranches sont reaffiches pour audit', () => {
  const root = makeRepo();
  writeQueue(root, 'EVIDENCE/reports/forge_ledger_proposals.jsonl', [
    { run_id: 'r-tranche', project: 'p1', ts: NOW - 86400, review_status: 'ACCEPTED' },
    { run_id: 'r-attente', project: 'p2', ts: NOW - 86400 },
  ]);

  const res = aggregate(root, NOW, { includeReviewed: true });
  assert.equal(res.ranked.length, 2);
  assert.equal(res.reviewed_included, true);

  rmSync(root, { recursive: true, force: true });
});

test('aggregate: un item tranche ne gonfle plus le rang de ses jumeaux (occurrences recomptees)', () => {
  const root = makeRepo();
  // 3 propositions du MEME projet : 2 deja tranchees, 1 en attente. Avant la reparation, l'item
  // en attente heritait de occurrences=3 et remontait devant des sujets plus anciens.
  writeQueue(root, 'EVIDENCE/reports/forge_project_proposals.jsonl', [
    { project: 'dup', folder: 'GAMES/dup', ts: NOW - 86400, review_status: 'ACCEPTED' },
    { project: 'dup', folder: 'GAMES/dup', ts: NOW - 86400, review_status: 'ACCEPTED' },
    { project: 'dup', folder: 'GAMES/dup', ts: NOW - 86400 },
  ]);

  const res = aggregate(root, NOW);
  assert.equal(res.ranked.length, 1);
  assert.equal(res.ranked[0].occurrences, 1, 'compte sur la file retenue, pas sur le total');

  rmSync(root, { recursive: true, force: true });
});

// --- l'ecran : sujet reel et cle de decision ---------------------------------------------

test('subject_label expose capability_id (l\'ecran montrait 5 fois le meme run_id)', () => {
  const raw = { capability_id: 'game.gravity', source_line_id: 'wm-1', run_id: 'tetris-run', project: 'tetris', ts: NOW };
  const it = normalizeItem(cfg('forge_capability_gap_proposals'), raw, NOW);
  assert.equal(it.subject_label, 'game.gravity');
  assert.equal(it.label, 'tetris-run', 'label historique inchange — contrat preserve');
});

test('decision_item donne la valeur EXACTE a recopier, par queue', () => {
  const ledger = normalizeItem(cfg('forge_ledger_proposals'), { run_id: 'r1', project: 'p1', ts: NOW }, NOW);
  assert.equal(ledger.decision_item, 'r1', 'ledger se rapproche sur run_id');

  const gap = normalizeItem(cfg('forge_capability_gap_proposals'), { capability_id: 'game.input', run_id: 'tetris-run', ts: NOW }, NOW);
  assert.equal(gap.decision_item, 'game.input', 'capability_gap se rapproche sur capability_id, PAS run_id');

  const brick = normalizeItem(cfg('forge_brick_proposals'), { brick_id: 'b-42', project: 'p', ts: NOW }, NOW);
  assert.equal(brick.decision_item, 'b-42');
});

test('decision_item null quand aucun champ de rapprochement n\'est present (jamais devine)', () => {
  const it = normalizeItem(cfg('forge_ledger_proposals'), { ts: NOW, note: 'sans cle' }, NOW);
  assert.equal(it.decision_item, null);
});

// --- (2) le plafond monopolise -----------------------------------------------------------

test('selectDisplayed: une file volumineuse ne peut plus masquer les autres', () => {
  const ranked = [
    ...Array.from({ length: 42 }, (_, i) => ({ source_file: 'forge_capability_gap_proposals', subject_label: `cap${i}` })),
    { source_file: 'error_proposals', subject_label: 'la plus vieille' },
    { source_file: 'forge_project_proposals', subject_label: 'menagerie' },
  ];

  const shown = selectDisplayed(ranked, 5);
  const sources = new Set(shown.map((i) => i.source_file));
  assert.equal(shown.length, 5);
  assert.equal(sources.size, 3, 'les 3 files sources sont representees sous le plafond');
  assert.ok(shown.some((i) => i.subject_label === 'la plus vieille'), 'la plus vieille proposition est visible');
  assert.ok(shown.some((i) => i.subject_label === 'menagerie'));
});

test('selectDisplayed: une seule file source -> comportement inchange (ordre du classement)', () => {
  const ranked = Array.from({ length: 4 }, (_, i) => ({ source_file: 'a', subject_label: `s${i}` }));
  assert.deepEqual(selectDisplayed(ranked, 3).map((i) => i.subject_label), ['s0', 's1', 's2']);
});

test('selectDisplayed: plafond >= volume -> tout est rendu, aucun item perdu', () => {
  const ranked = [
    { source_file: 'a', subject_label: 'a1' },
    { source_file: 'b', subject_label: 'b1' },
    { source_file: 'a', subject_label: 'a2' },
  ];
  assert.equal(selectDisplayed(ranked, 10).length, 3);
  assert.equal(selectDisplayed(ranked, 0).length, 0);
});

// --- (2bis) MATCH_FIELDS derive ----------------------------------------------------------

test('MATCH_FIELDS couvre les 7 queues et derive de QUEUE_FILES (source unique)', () => {
  // Compteur-CANARI : il ne mesure rien en soi, il force a repasser par ce test quand une
  // file est ajoutee. 6 -> 7 le 2026-08-10 : file USINE (forge_factory_capability_gap_
  // proposals), routage produit/usine ratifie Pierre. La garde substantielle est la BOUCLE
  // ci-dessous, qui est independante du compte.
  assert.equal(QUEUE_FILES.length, 7);
  for (const q of QUEUE_FILES) {
    assert.ok(Array.isArray(MATCH_FIELDS[q.id]) && MATCH_FIELDS[q.id].length > 0,
      `queue ${q.id} sans regle de rapprochement -> decisions structurellement orphelines`);
    assert.deepEqual(MATCH_FIELDS[q.id], q.match_fields, 'la table doit DERIVER, jamais dupliquer');
  }
});

test('planDecisions: une decision capability_gap n\'est PLUS orpheline', () => {
  const root = makeRepo();
  writeQueue(root, 'EVIDENCE/reports/forge_capability_gap_proposals.jsonl', [
    { capability_id: 'game.gravity', source_line_id: 'wm-1', run_id: 'tetris', project: 'tetris', ts: NOW },
  ]);
  writeFileSync(join(root, 'EVIDENCE/reports/dec.jsonl'),
    JSON.stringify({ ts: '2026-08-10', queue: 'forge_capability_gap_proposals', item: 'game.gravity', decision: 'ACCEPT', motif: 'test' }) + '\n', 'utf-8');

  const plan = planDecisions(root, 'EVIDENCE/reports/dec.jsonl');
  assert.equal(plan.orphaned.length, 0, 'avant la reparation : orpheline garantie');
  assert.equal(plan.changes.length, 1);
  assert.equal(plan.changes[0].requested_status, 'ACCEPTED');

  rmSync(root, { recursive: true, force: true });
});

// --- (3) decisions invalides rendues explicites ------------------------------------------

test('classifyDecision: POSTPONE est INVALIDE, jamais silencieusement narratif', () => {
  const c = classifyDecision({ queue: 'forge_ledger_proposals', item: 'r1', decision: 'POSTPONE' });
  assert.equal(c.kind, 'invalid');
  assert.match(c.reason, /POSTPONE/);
});

test('classifyDecision: casse incorrecte du verbe -> invalide et motivee', () => {
  const c = classifyDecision({ queue: 'q', item: 'i', decision: 'Accept' });
  assert.equal(c.kind, 'invalid');
  assert.match(c.reason, /non reconnu/);
});

test('classifyDecision: ligne narrative legitime (aucune cle de decision) reste narrative', () => {
  assert.equal(classifyDecision({ ts: '2026-07-20', note: 'fin de session' }).kind, 'narrative');
  assert.equal(classifyDecision({ ts: '2026-07-20', actor: 'Pierre', verbatim: '...' }).kind, 'narrative');
});

test('classifyDecision: decision valide reste actionnable', () => {
  assert.equal(classifyDecision({ queue: 'q', item: 'i', decision: 'ACCEPT' }).kind, 'actionable');
  assert.equal(classifyDecision({ queue: 'q', item: 'i', decision: 'REJECT' }).kind, 'actionable');
});

test('planDecisions rapporte les invalides separement des narratives', () => {
  const root = makeRepo();
  writeQueue(root, 'EVIDENCE/reports/forge_ledger_proposals.jsonl', [{ run_id: 'r1', project: 'p1', ts: NOW }]);
  writeFileSync(join(root, 'EVIDENCE/reports/dec.jsonl'), [
    JSON.stringify({ ts: '2026-08-10', note: 'note de session' }),
    JSON.stringify({ ts: '2026-08-10', queue: 'forge_ledger_proposals', item: 'r1', decision: 'POSTPONE' }),
  ].join('\n') + '\n', 'utf-8');

  const plan = planDecisions(root, 'EVIDENCE/reports/dec.jsonl');
  assert.equal(plan.skipped_meta, 1, 'la note reste narrative');
  assert.equal(plan.invalid.length, 1, 'le POSTPONE devient visible');
  assert.equal(plan.changes.length, 0, 'aucune ecriture sur une decision invalide');

  rmSync(root, { recursive: true, force: true });
});

// --- LE CRITERE DE SORTIE : la boucle complete, bout en bout -----------------------------

test('BOUCLE COMPLETE : proposition -> pending_review -> decision -> apply -> disparait', () => {
  const root = makeRepo();
  writeQueue(root, 'EVIDENCE/reports/forge_ledger_proposals.jsonl', [
    { run_id: 'run-A', project: 'projA', ts: NOW - 86400, status: 'PROPOSED' },
    { run_id: 'run-B', project: 'projB', ts: NOW - 86400, status: 'PROPOSED' },
  ]);

  // 1. la revue voit les 2 propositions, et donne pour chacune la cle a recopier
  const avant = aggregate(root, NOW);
  assert.equal(avant.ranked.length, 2);
  const cible = avant.ranked.find((i) => i.origin === 'run-A');
  assert.equal(cible.decision_item, 'run-A');
  assert.equal(cible.reviewed, false);

  // 2. l'humain ecrit UNE decision, en recopiant exactement decision_item
  writeFileSync(join(root, 'EVIDENCE/reports/dec.jsonl'),
    JSON.stringify({ ts: '2026-08-10', queue: 'forge_ledger_proposals', item: cible.decision_item, decision: 'ACCEPT', motif: 'boucle' }) + '\n', 'utf-8');

  // 3. apply_decisions la consomme et pose la preuve sur la proposition
  const plan = planDecisions(root, 'EVIDENCE/reports/dec.jsonl');
  assert.equal(plan.changes.length, 1);
  assert.equal(plan.orphaned.length, 0);
  const written = writeChanges(root, plan.fileState);
  assert.deepEqual(written, ['EVIDENCE/reports/forge_ledger_proposals.jsonl']);

  // 4. la preuve est sur disque, structuree
  const onDisk = readFileSync(join(root, 'EVIDENCE/reports/forge_ledger_proposals.jsonl'), 'utf-8')
    .trim().split('\n').map((l) => JSON.parse(l));
  assert.equal(onDisk.find((r) => r.run_id === 'run-A').review_status, 'ACCEPTED');
  assert.equal(onDisk.find((r) => r.run_id === 'run-B').review_status, undefined);

  // 5. LE CRITERE : la proposition tranchee a disparu de la file, l'autre reste
  const apres = aggregate(root, NOW);
  assert.equal(apres.total_items, 2, 'aucune donnee perdue');
  assert.equal(apres.reviewed_items, 1);
  assert.equal(apres.ranked.length, 1, 'la decision a eu un effet VISIBLE sur la file');
  assert.equal(apres.ranked[0].origin, 'run-B');

  // 6. idempotence : rejouer la meme decision ne change plus rien
  const rejeu = planDecisions(root, 'EVIDENCE/reports/dec.jsonl');
  assert.equal(rejeu.changes.length, 0);
  assert.equal(rejeu.already_up_to_date.length, 1);

  rmSync(root, { recursive: true, force: true });
});

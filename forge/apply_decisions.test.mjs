// Tests de apply_decisions.mjs — node --test. Fixtures ephemeres sous un faux repoRoot,
// meme discipline que pending_review.test.mjs : le repo reel peut bouger, ces tests non.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import {
  loadDecisions, isActionableDecision, loadProposalLines, matchLines,
  planDecisions, writeChanges, DEFAULT_DECISIONS_FILE,
  extractFutureScope, extractFutureValidation, extractRisks,
} from './apply_decisions.mjs';

function fakeRepo() {
  const root = mkdtempSync(join(tmpdir(), 'applydec-'));
  mkdirSync(join(root, 'EVIDENCE', 'reports'), { recursive: true });
  return root;
}
function writeJsonl(root, relPath, lines) {
  const full = join(root, relPath);
  mkdirSync(join(full, '..'), { recursive: true });
  writeFileSync(full, lines.join('\n') + '\n', 'utf-8');
}
function readJsonl(root, relPath) {
  const text = readFileSync(join(root, relPath), 'utf-8');
  return text.split(/\r?\n/).filter((l) => l.trim() !== '').map((l) => JSON.parse(l));
}

// --- loadDecisions / isActionableDecision --------------------------------------------------

test('loadDecisions: fichier absent -> status ABSENT, jamais fatal', () => {
  const root = fakeRepo();
  const r = loadDecisions(root, DEFAULT_DECISIONS_FILE);
  assert.equal(r.status, 'ABSENT');
  assert.deepEqual(r.raw, []);
});

test('loadDecisions: ligne corrompue ignoree, pas de crash', () => {
  const root = fakeRepo();
  writeJsonl(root, DEFAULT_DECISIONS_FILE, [
    JSON.stringify({ queue: 'q', item: 'a', decision: 'ACCEPT' }),
    '{pas du json',
  ]);
  const r = loadDecisions(root, DEFAULT_DECISIONS_FILE);
  assert.equal(r.raw.length, 1);
  assert.equal(r.ignored_lines, 1);
});

test('loadDecisions: fichier vide (0 octet) -> status OK, raw vide, pas fatal', () => {
  const root = fakeRepo();
  writeJsonl(root, DEFAULT_DECISIONS_FILE, []);
  const r = loadDecisions(root, DEFAULT_DECISIONS_FILE);
  assert.equal(r.status, 'OK');
  assert.deepEqual(r.raw, []);
  assert.equal(r.ignored_lines, 0);
});

test('loadDecisions: BOM UTF-8 en tete de fichier -> ligne 1 ignoree proprement, reste du fichier lu (pas d\'effet domino)', () => {
  const root = fakeRepo();
  const full = join(root, DEFAULT_DECISIONS_FILE);
  const bomLine = '﻿' + JSON.stringify({ queue: 'q', item: 'a', decision: 'ACCEPT' });
  const secondLine = JSON.stringify({ queue: 'q2', item: 'b', decision: 'REJECT' });
  writeFileSync(full, bomLine + '\n' + secondLine + '\n', 'utf-8');
  const r = loadDecisions(root, DEFAULT_DECISIONS_FILE);
  assert.equal(r.status, 'OK');
  assert.equal(r.raw.length, 1); // ligne BOM invalide JSON -> ignoree, jamais tout le fichier perdu
  assert.equal(r.ignored_lines, 1);
  assert.equal(r.raw[0].item, 'b');
});

test('isActionableDecision: ligne meta (sans queue/item) -> false', () => {
  assert.equal(isActionableDecision({ ts: '2026-07-20', note: 'synthese' }), false);
});

test('isActionableDecision: decision valide ACCEPT/REJECT -> true', () => {
  assert.equal(isActionableDecision({ queue: 'q', item: 'a', decision: 'ACCEPT' }), true);
  assert.equal(isActionableDecision({ queue: 'q', item: 'a', decision: 'REJECT' }), true);
  assert.equal(isActionableDecision({ queue: 'q', item: 'a', decision: 'POSTPONE' }), false);
});

// --- loadProposalLines / matchLines ---------------------------------------------------------

test('loadProposalLines: conserve la ligne brute pour reecriture fidele', () => {
  const root = fakeRepo();
  writeJsonl(root, 'EVIDENCE/reports/forge_ledger_proposals.jsonl', [
    JSON.stringify({ project: 'p', run_id: 'p-run1', ts: 1000 }),
  ]);
  const r = loadProposalLines(root, 'EVIDENCE/reports/forge_ledger_proposals.jsonl');
  assert.equal(r.status, 'OK');
  assert.equal(r.lines.length, 1);
  assert.equal(r.lines[0].parsed.run_id, 'p-run1');
});

test('matchLines: egalite stricte sur le premier champ candidat qui existe', () => {
  const lines = [
    { raw: '', parsed: { run_id: 'a-run1', project: 'a' } },
    { raw: '', parsed: { run_id: 'b-run1', project: 'b' } },
  ];
  const idx = matchLines(lines, ['run_id', 'project'], 'b-run1');
  assert.deepEqual(idx, [1]);
});

test('matchLines: pas de sous-chaine, egalite stricte uniquement', () => {
  const lines = [{ raw: '', parsed: { title: '[auto] erreur inconnue: council contract rejete' } }];
  const idx = matchLines(lines, ['title'], 'council contract rejete');
  assert.deepEqual(idx, []); // sous-chaine, pas egal -> pas de match
});

// --- planDecisions : cas nominal -------------------------------------------------------------

test('planDecisions: cas nominal ACCEPT sur forge_ledger_proposals (match run_id)', () => {
  const root = fakeRepo();
  writeJsonl(root, 'EVIDENCE/reports/forge_ledger_proposals.jsonl', [
    JSON.stringify({ project: 'shmup_slice', run_id: 'shmup_slice-20260714a', ts: 1000, status: 'PROPOSED' }),
  ]);
  writeJsonl(root, DEFAULT_DECISIONS_FILE, [
    JSON.stringify({ ts: '2026-07-20', queue: 'forge_ledger_proposals', item: 'shmup_slice-20260714a', decision: 'ACCEPT', motif: 'ok' }),
  ]);
  const plan = planDecisions(root, DEFAULT_DECISIONS_FILE);
  assert.equal(plan.changes.length, 1);
  assert.equal(plan.changes[0].requested_status, 'ACCEPTED');
  assert.equal(plan.already_up_to_date.length, 0);
  assert.equal(plan.conflicts.length, 0);
  assert.equal(plan.orphaned.length, 0);
});

test('planDecisions: REJECT mappe vers REJECTED', () => {
  const root = fakeRepo();
  writeJsonl(root, 'EVIDENCE/reports/forge_project_proposals.jsonl', [
    JSON.stringify({ project: 'collect_runner', folder: 'GAMES/collect_runner', ts: 1000, status: 'PROPOSED' }),
  ]);
  writeJsonl(root, DEFAULT_DECISIONS_FILE, [
    JSON.stringify({ ts: '2026-07-20', queue: 'forge_project_proposals', item: 'collect_runner', decision: 'REJECT', motif: 'ferme' }),
  ]);
  const plan = planDecisions(root, DEFAULT_DECISIONS_FILE);
  assert.equal(plan.changes.length, 1);
  assert.equal(plan.changes[0].requested_status, 'REJECTED');
});

// --- planDecisions : idempotence --------------------------------------------------------------

test('planDecisions + writeChanges: rejouer --apply sur un etat deja applique -> 0 changement', () => {
  const root = fakeRepo();
  writeJsonl(root, 'EVIDENCE/reports/forge_ledger_proposals.jsonl', [
    JSON.stringify({ project: 'shmup_slice', run_id: 'shmup_slice-20260714a', ts: 1000, status: 'PROPOSED' }),
  ]);
  writeJsonl(root, DEFAULT_DECISIONS_FILE, [
    JSON.stringify({ ts: '2026-07-20', queue: 'forge_ledger_proposals', item: 'shmup_slice-20260714a', decision: 'ACCEPT', motif: 'ok' }),
  ]);
  const plan1 = planDecisions(root, DEFAULT_DECISIONS_FILE);
  const written1 = writeChanges(root, plan1.fileState);
  assert.equal(written1.length, 1);
  assert.equal(plan1.changes.length, 1);

  const proposalsAfter = readJsonl(root, 'EVIDENCE/reports/forge_ledger_proposals.jsonl');
  assert.equal(proposalsAfter[0].review_status, 'ACCEPTED');
  assert.equal(proposalsAfter[0].review_ts, '2026-07-20');
  assert.equal(proposalsAfter[0].review_source, DEFAULT_DECISIONS_FILE);
  assert.ok(existsSync(join(root, 'EVIDENCE/reports/forge_ledger_proposals.jsonl.bak')));

  // Re-run : deja a jour, 0 changement, rien reecrit.
  const plan2 = planDecisions(root, DEFAULT_DECISIONS_FILE);
  const written2 = writeChanges(root, plan2.fileState);
  assert.equal(plan2.changes.length, 0);
  assert.equal(plan2.already_up_to_date.length, 1);
  assert.equal(written2.length, 0);
});

// --- planDecisions : orpheline -----------------------------------------------------------------

test('planDecisions: decision sans proposition correspondante -> orpheline, jamais inventee', () => {
  const root = fakeRepo();
  writeJsonl(root, 'EVIDENCE/reports/error_proposals.jsonl', [
    JSON.stringify({ error_signature: '54d9a6ad5f590d7c', title: '[auto] erreur inconnue: council contract rejete: write-path/command interdit', created_ts: 1000 }),
  ]);
  writeJsonl(root, DEFAULT_DECISIONS_FILE, [
    JSON.stringify({ ts: '2026-07-20', queue: 'error_proposals', item: 'council contract write-path interdit', decision: 'ACCEPT', motif: 'lecon reelle' }),
  ]);
  const plan = planDecisions(root, DEFAULT_DECISIONS_FILE);
  assert.equal(plan.changes.length, 0);
  assert.equal(plan.orphaned.length, 1);
  assert.equal(plan.orphaned[0].item, 'council contract write-path interdit');
});

test('planDecisions: queue inconnue -> orpheline (pas un crash)', () => {
  const root = fakeRepo();
  writeJsonl(root, DEFAULT_DECISIONS_FILE, [
    JSON.stringify({ ts: '2026-07-20', queue: 'inconnue_queue', item: 'x', decision: 'ACCEPT' }),
  ]);
  const plan = planDecisions(root, DEFAULT_DECISIONS_FILE);
  assert.equal(plan.orphaned.length, 1);
  assert.match(plan.orphaned[0].reason, /queue inconnue/);
});

test('planDecisions: fichier de propositions absent -> orpheline', () => {
  const root = fakeRepo();
  writeJsonl(root, DEFAULT_DECISIONS_FILE, [
    JSON.stringify({ ts: '2026-07-20', queue: 'forge_ledger_proposals', item: 'x-run1', decision: 'ACCEPT' }),
  ]);
  const plan = planDecisions(root, DEFAULT_DECISIONS_FILE);
  assert.equal(plan.orphaned.length, 1);
  assert.match(plan.orphaned[0].reason, /absent/);
});

// --- planDecisions : conflit ---------------------------------------------------------------

test('planDecisions: proposition deja marquee d\'un statut different -> conflit, pas ecrase', () => {
  const root = fakeRepo();
  writeJsonl(root, 'EVIDENCE/reports/forge_ledger_proposals.jsonl', [
    JSON.stringify({ project: 'x', run_id: 'x-run1', ts: 1000, review_status: 'REJECTED', review_ts: '2026-07-01', review_source: 'manuel' }),
  ]);
  writeJsonl(root, DEFAULT_DECISIONS_FILE, [
    JSON.stringify({ ts: '2026-07-20', queue: 'forge_ledger_proposals', item: 'x-run1', decision: 'ACCEPT', motif: 'nouvelle decision' }),
  ]);
  const plan = planDecisions(root, DEFAULT_DECISIONS_FILE);
  assert.equal(plan.changes.length, 0);
  assert.equal(plan.conflicts.length, 1);
  assert.equal(plan.conflicts[0].existing_status, 'REJECTED');
  assert.equal(plan.conflicts[0].requested_status, 'ACCEPTED');

  const written = writeChanges(root, plan.fileState);
  assert.equal(written.length, 0);
  const after = readJsonl(root, 'EVIDENCE/reports/forge_ledger_proposals.jsonl');
  assert.equal(after[0].review_status, 'REJECTED'); // inchange
});

// --- entrees narratives (skipped_meta) ------------------------------------------------------

test('planDecisions: lignes meta (sans queue/item/decision valide) -> skipped_meta, jamais orpheline', () => {
  const root = fakeRepo();
  writeJsonl(root, DEFAULT_DECISIONS_FILE, [
    JSON.stringify({ ts: '2026-07-20', actor: 'Pierre (HumanGate)', verbatim: 'synthese session' }),
    JSON.stringify({ ts: '2026-07-20', note: 'note de fin de session' }),
  ]);
  const plan = planDecisions(root, DEFAULT_DECISIONS_FILE);
  assert.equal(plan.skipped_meta, 2);
  assert.equal(plan.orphaned.length, 0);
  assert.equal(plan.changes.length, 0);
});

// --- dry-run n'ecrit rien --------------------------------------------------------------------

test('dry-run (planDecisions sans writeChanges) ne touche jamais le disque', () => {
  const root = fakeRepo();
  writeJsonl(root, 'EVIDENCE/reports/forge_project_proposals.jsonl', [
    JSON.stringify({ project: 'auto_battler', folder: 'GAMES/auto_battler', ts: 1000, status: 'PROPOSED' }),
  ]);
  writeJsonl(root, DEFAULT_DECISIONS_FILE, [
    JSON.stringify({ ts: '2026-07-20', queue: 'forge_project_proposals', item: 'auto_battler', decision: 'ACCEPT', motif: 'ok' }),
  ]);
  const before = readFileSync(join(root, 'EVIDENCE/reports/forge_project_proposals.jsonl'), 'utf-8');
  planDecisions(root, DEFAULT_DECISIONS_FILE); // writeChanges jamais appele : c'est le dry-run
  const after = readFileSync(join(root, 'EVIDENCE/reports/forge_project_proposals.jsonl'), 'utf-8');
  assert.equal(before, after);
  assert.equal(existsSync(join(root, 'EVIDENCE/reports/forge_project_proposals.jsonl.bak')), false);
});

// --- plusieurs decisions dans la meme file, matching different par champ -------------------

test('planDecisions: forge_ledger vs forge_project utilisent des champs candidats differents (run_id vs project)', () => {
  const root = fakeRepo();
  writeJsonl(root, 'EVIDENCE/reports/forge_ledger_proposals.jsonl', [
    JSON.stringify({ project: 'card_engine', run_id: 'card_engine-20260720a', ts: 1000 }),
  ]);
  writeJsonl(root, 'EVIDENCE/reports/forge_project_proposals.jsonl', [
    JSON.stringify({ project: 'card_engine', folder: 'GAMES/card_engine', ts: 1000 }),
  ]);
  writeJsonl(root, DEFAULT_DECISIONS_FILE, [
    JSON.stringify({ ts: '2026-07-20', queue: 'forge_ledger_proposals', item: 'card_engine-20260720a', decision: 'ACCEPT' }),
    JSON.stringify({ ts: '2026-07-20', queue: 'forge_project_proposals', item: 'card_engine', decision: 'ACCEPT' }),
  ]);
  const plan = planDecisions(root, DEFAULT_DECISIONS_FILE);
  assert.equal(plan.changes.length, 2);
  assert.equal(plan.orphaned.length, 0);
});

// --- enrichissement optionnel (portee autorisee / validation future / risques) --------------
// Primitive 2, ratification Pierre 2026-07-26 (studio_brain/decisions/PROPOSED_2026-07-26_ratifications.md).
// 3 champs ADDITIONNELS et OPTIONNELS sur une decision : allowed_future_patch_scope (liste de
// chemins/globs), future_validation_required (liste de commandes executables), risks (liste
// structuree). Retro-compatibilite TOTALE : une ligne a 5 champs (ancienne) reste traitee a
// l'identique, ces champs ne deviennent JAMAIS obligatoires. Aucun blocage : ce module expose/
// valide la donnee, il ne fait echouer aucune etape.

test('extractFutureScope/extractFutureValidation/extractRisks: absent/null/malformed -> liste vide, jamais de crash', () => {
  assert.deepEqual(extractFutureScope({}), []);
  assert.deepEqual(extractFutureScope({ allowed_future_patch_scope: null }), []);
  assert.deepEqual(extractFutureScope({ allowed_future_patch_scope: 'pas-une-liste' }), []);
  assert.deepEqual(extractFutureScope({ allowed_future_patch_scope: ['a/**', 42, 'b.mjs'] }), ['a/**', 'b.mjs']);

  assert.deepEqual(extractFutureValidation({}), []);
  assert.deepEqual(extractFutureValidation({ future_validation_required: null }), []);
  assert.deepEqual(extractFutureValidation({ future_validation_required: ['node --test x'] }), ['node --test x']);

  assert.deepEqual(extractRisks({}), []);
  assert.deepEqual(extractRisks({ risks: null }), []);
  assert.deepEqual(extractRisks({ risks: ['pas-un-objet'] }), []);
  assert.deepEqual(extractRisks({ risks: [{ risk_id: 'R1', summary: 's' }] }), [{ risk_id: 'R1', summary: 's' }]);
});

test('planDecisions: ligne 5 champs (ancienne, sans champs d\'enrichissement) -> AUCUN champ ajoute, retro-compat totale', () => {
  const root = fakeRepo();
  writeJsonl(root, 'EVIDENCE/reports/forge_ledger_proposals.jsonl', [
    JSON.stringify({ project: 'shmup_slice', run_id: 'shmup_slice-20260714a', ts: 1000, status: 'PROPOSED' }),
  ]);
  writeJsonl(root, DEFAULT_DECISIONS_FILE, [
    JSON.stringify({ ts: '2026-07-20', queue: 'forge_ledger_proposals', item: 'shmup_slice-20260714a', decision: 'ACCEPT', motif: 'ok' }),
  ]);
  const plan = planDecisions(root, DEFAULT_DECISIONS_FILE);
  assert.equal('allowed_future_patch_scope' in plan.changes[0], false);
  assert.equal('future_validation_required' in plan.changes[0], false);
  assert.equal('risks' in plan.changes[0], false);

  writeChanges(root, plan.fileState);
  const after = readJsonl(root, 'EVIDENCE/reports/forge_ledger_proposals.jsonl');
  assert.equal('review_allowed_future_patch_scope' in after[0], false);
  assert.equal('review_future_validation_required' in after[0], false);
  assert.equal('review_risks' in after[0], false);
});

test('planDecisions: decision enrichie porte scope/validation/risks sur le changement ET sur la proposition ecrite', () => {
  const root = fakeRepo();
  writeJsonl(root, 'EVIDENCE/reports/forge_ledger_proposals.jsonl', [
    JSON.stringify({ project: 'card_engine', run_id: 'card_engine-20260720a', ts: 1000 }),
  ]);
  writeJsonl(root, DEFAULT_DECISIONS_FILE, [
    JSON.stringify({
      ts: '2026-07-20', queue: 'forge_ledger_proposals', item: 'card_engine-20260720a', decision: 'ACCEPT', motif: 'ok',
      allowed_future_patch_scope: ['GAMES/card_engine/**', 'forge/oracle.py'],
      future_validation_required: ['node --test forge/oracle.test.mjs'],
      risks: [{ risk_id: 'R1', summary: 'risque test', mitigation: 'mitig' }],
    }),
  ]);
  const plan = planDecisions(root, DEFAULT_DECISIONS_FILE);
  assert.deepEqual(plan.changes[0].allowed_future_patch_scope, ['GAMES/card_engine/**', 'forge/oracle.py']);
  assert.deepEqual(plan.changes[0].future_validation_required, ['node --test forge/oracle.test.mjs']);
  assert.deepEqual(plan.changes[0].risks, [{ risk_id: 'R1', summary: 'risque test', mitigation: 'mitig' }]);

  writeChanges(root, plan.fileState);
  const after = readJsonl(root, 'EVIDENCE/reports/forge_ledger_proposals.jsonl');
  assert.deepEqual(after[0].review_allowed_future_patch_scope, ['GAMES/card_engine/**', 'forge/oracle.py']);
  assert.deepEqual(after[0].review_future_validation_required, ['node --test forge/oracle.test.mjs']);
  assert.deepEqual(after[0].review_risks, [{ risk_id: 'R1', summary: 'risque test', mitigation: 'mitig' }]);
});

test('planDecisions: champ d\'enrichissement present mais liste vide -> ecrit vide, jamais bloquant', () => {
  const root = fakeRepo();
  writeJsonl(root, 'EVIDENCE/reports/forge_project_proposals.jsonl', [
    JSON.stringify({ project: 'auto_battler', folder: 'GAMES/auto_battler', ts: 1000 }),
  ]);
  writeJsonl(root, DEFAULT_DECISIONS_FILE, [
    JSON.stringify({
      ts: '2026-07-20', queue: 'forge_project_proposals', item: 'auto_battler', decision: 'ACCEPT',
      allowed_future_patch_scope: [], future_validation_required: [], risks: [],
    }),
  ]);
  const plan = planDecisions(root, DEFAULT_DECISIONS_FILE);
  assert.deepEqual(plan.changes[0].allowed_future_patch_scope, []);
  writeChanges(root, plan.fileState);
  const after = readJsonl(root, 'EVIDENCE/reports/forge_project_proposals.jsonl');
  assert.deepEqual(after[0].review_allowed_future_patch_scope, []);
  assert.deepEqual(after[0].review_future_validation_required, []);
  assert.deepEqual(after[0].review_risks, []);
});

test('planDecisions: champ d\'enrichissement null -> normalise en liste vide, pas de crash', () => {
  const root = fakeRepo();
  writeJsonl(root, 'EVIDENCE/reports/forge_project_proposals.jsonl', [
    JSON.stringify({ project: 'auto_battler', folder: 'GAMES/auto_battler', ts: 1000 }),
  ]);
  writeJsonl(root, DEFAULT_DECISIONS_FILE, [
    JSON.stringify({
      ts: '2026-07-20', queue: 'forge_project_proposals', item: 'auto_battler', decision: 'ACCEPT',
      allowed_future_patch_scope: null, risks: null,
    }),
  ]);
  const plan = planDecisions(root, DEFAULT_DECISIONS_FILE);
  assert.deepEqual(plan.changes[0].allowed_future_patch_scope, []);
  assert.deepEqual(plan.changes[0].risks, []);
  assert.equal('future_validation_required' in plan.changes[0], false); // cle absente -> pas ajoutee
});

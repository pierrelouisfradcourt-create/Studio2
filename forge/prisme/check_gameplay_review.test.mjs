// check_gameplay_review.test.mjs — oracle de complétude structurelle pour l'artefact
// Gameplay Review du Prisme. Fixtures en répertoire temporaire (os.tmpdir()) : une
// checklist minimale à 2 items (les tests ne dépendent pas du contenu réel de
// design_review_checklist.yaml, seulement de sa structure).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { checkGameplayReview, parseChecklistItemIds, extractJsonBlock } from './check_gameplay_review.mjs';

const CHECKLIST = `version: 1
categories:
  - id: cat_a
    titre: Categorie A
    lens: [gamedesign]
    items:
      - id: a.un
        question: "Question un ?"
      - id: a.deux
        question: "Question deux ?"
  - id: cat_b
    titre: Categorie B
    lens: [archidepot]
    items:
      - id: b.un
        question: "Question trois ?"
`;

function makeDir(t) {
  const dir = mkdtempSync(join(tmpdir(), 'gameplay-review-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  return dir;
}

function writeChecklist(dir, content = CHECKLIST) {
  const p = join(dir, 'checklist.yaml');
  writeFileSync(p, content, 'utf-8');
  return p;
}

function writeReview(dir, content) {
  const p = join(dir, 'design_review.md');
  writeFileSync(p, content, 'utf-8');
  return p;
}

const VALID_PAYLOAD = {
  checklist_answers: {
    'a.un': { statut: 'oui', raison: 'Le joueur voit un bouton JOUER des la premiere frame.' },
    'a.deux': { statut: 'non', raison: "Pas de boucle explicite pour l'instant, jeu jetable." },
    'b.un': { statut: 'na', raison: 'Categorie hors perimetre de ce prototype.' },
  },
  decisions: [
    {
      sujet: 'Ajout d\'un mode multijoueur',
      decision: 'rejete',
      pourquoi: 'Hors scope du prototype, complexite reseau non justifiee.',
      impact_architecture: 'Aucun, la decision est prise avant toute implementation.',
    },
    {
      sujet: 'Systeme de sauvegarde local',
      decision: 'necessaire',
      pourquoi: 'Le joueur doit pouvoir reprendre sa partie.',
      impact_architecture: 'Ajoute une couche de persistance JSON isolee de la logique pure.',
    },
  ],
  gaps_traites: [{ gap: 'Absence de feedback sonore', traitement: 'Ajout de 3 sons de base.' }],
};

function validReviewContent(payload = VALID_PAYLOAD) {
  return `# Design Review\n\nTexte libre de synthese.\n\n\`\`\`json\n${JSON.stringify(payload, null, 2)}\n\`\`\`\n`;
}

test('document valide -> ok=true, exit attendu 0', async (t) => {
  const dir = makeDir(t);
  const checklistPath = writeChecklist(dir);
  const reviewPath = writeReview(dir, validReviewContent());
  const res = await checkGameplayReview(reviewPath, checklistPath);
  assert.equal(res.ok, true, JSON.stringify(res.problems));
  assert.equal(res.verdict, 'OK');
  assert.deepEqual(res.stats, {
    items_attendus: 3,
    items_repondus: 3,
    oui: 1,
    non: 1,
    na: 1,
    decisions: 2,
    rejets: 1,
  });
});

test('bloc json absent -> rejet', async (t) => {
  const dir = makeDir(t);
  const checklistPath = writeChecklist(dir);
  const reviewPath = writeReview(dir, '# Design Review\n\nAucun bloc json ici.\n');
  const res = await checkGameplayReview(reviewPath, checklistPath);
  assert.equal(res.ok, false);
  assert.ok(res.problems.some((p) => p.includes('bloc ```json absent')));
});

test('bloc json invalide (parse error) -> rejet', async (t) => {
  const dir = makeDir(t);
  const checklistPath = writeChecklist(dir);
  const reviewPath = writeReview(dir, '# Design Review\n\n```json\n{ "checklist_answers": \n```\n');
  const res = await checkGameplayReview(reviewPath, checklistPath);
  assert.equal(res.ok, false);
  assert.ok(res.problems.some((p) => p.includes('bloc json invalide')));
});

test('item de checklist sans reponse -> rejet nomme', async (t) => {
  const dir = makeDir(t);
  const checklistPath = writeChecklist(dir);
  const payload = JSON.parse(JSON.stringify(VALID_PAYLOAD));
  delete payload.checklist_answers['b.un'];
  const reviewPath = writeReview(dir, validReviewContent(payload));
  const res = await checkGameplayReview(reviewPath, checklistPath);
  assert.equal(res.ok, false);
  assert.ok(res.problems.some((p) => p.includes('item manquant : b.un')));
});

test('id inconnu (absent de la checklist) -> rejet', async (t) => {
  const dir = makeDir(t);
  const checklistPath = writeChecklist(dir);
  const payload = JSON.parse(JSON.stringify(VALID_PAYLOAD));
  payload.checklist_answers['z.inexistant'] = { statut: 'oui', raison: 'raison quelconque non vide.' };
  const reviewPath = writeReview(dir, validReviewContent(payload));
  const res = await checkGameplayReview(reviewPath, checklistPath);
  assert.equal(res.ok, false);
  assert.ok(res.problems.some((p) => p.includes('id inconnu') && p.includes('z.inexistant')));
});

test('statut hors enumeration -> rejet', async (t) => {
  const dir = makeDir(t);
  const checklistPath = writeChecklist(dir);
  const payload = JSON.parse(JSON.stringify(VALID_PAYLOAD));
  payload.checklist_answers['a.un'].statut = 'peut-etre';
  const reviewPath = writeReview(dir, validReviewContent(payload));
  const res = await checkGameplayReview(reviewPath, checklistPath);
  assert.equal(res.ok, false);
  assert.ok(res.problems.some((p) => p.includes('a.un.statut invalide')));
});

test('raison vide -> rejet', async (t) => {
  const dir = makeDir(t);
  const checklistPath = writeChecklist(dir);
  const payload = JSON.parse(JSON.stringify(VALID_PAYLOAD));
  payload.checklist_answers['a.deux'].raison = '   ';
  const reviewPath = writeReview(dir, validReviewContent(payload));
  const res = await checkGameplayReview(reviewPath, checklistPath);
  assert.equal(res.ok, false);
  assert.ok(res.problems.some((p) => p.includes('a.deux.raison manquante ou vide')));
});

test('zero decision -> rejet', async (t) => {
  const dir = makeDir(t);
  const checklistPath = writeChecklist(dir);
  const payload = JSON.parse(JSON.stringify(VALID_PAYLOAD));
  payload.decisions = [];
  const reviewPath = writeReview(dir, validReviewContent(payload));
  const res = await checkGameplayReview(reviewPath, checklistPath);
  assert.equal(res.ok, false);
  assert.ok(res.problems.some((p) => p.includes('decisions : au moins une entree requise') || p.includes('decisions : au moins une entrée requise')));
});

test('aucun rejet sans justification -> rejet', async (t) => {
  const dir = makeDir(t);
  const checklistPath = writeChecklist(dir);
  const payload = JSON.parse(JSON.stringify(VALID_PAYLOAD));
  payload.decisions = payload.decisions.map((d) => ({ ...d, decision: 'necessaire' }));
  const reviewPath = writeReview(dir, validReviewContent(payload));
  const res = await checkGameplayReview(reviewPath, checklistPath);
  assert.equal(res.ok, false);
  assert.ok(res.problems.some((p) => p.includes('aucun_rejet_justification')));
});

test('aucun rejet MAIS justification racine fournie -> accepte', async (t) => {
  const dir = makeDir(t);
  const checklistPath = writeChecklist(dir);
  const payload = JSON.parse(JSON.stringify(VALID_PAYLOAD));
  payload.decisions = payload.decisions.map((d) => ({ ...d, decision: 'necessaire' }));
  payload.aucun_rejet_justification = 'Prototype trop tot pour rejeter quoi que ce soit, tout est encore en jeu.';
  const reviewPath = writeReview(dir, validReviewContent(payload));
  const res = await checkGameplayReview(reviewPath, checklistPath);
  assert.equal(res.ok, true, JSON.stringify(res.problems));
  assert.equal(res.stats.rejets, 0);
});

test('placeholder TODO dans le document -> rejet', async (t) => {
  const dir = makeDir(t);
  const checklistPath = writeChecklist(dir);
  const content = validReviewContent().replace('# Design Review', '# Design Review\n\nTODO: relire cette section.');
  const reviewPath = writeReview(dir, content);
  const res = await checkGameplayReview(reviewPath, checklistPath);
  assert.equal(res.ok, false);
  assert.ok(res.problems.some((p) => p.includes('placeholder')));
});

test('checklist introuvable -> echec explicite', async (t) => {
  const dir = makeDir(t);
  const reviewPath = writeReview(dir, validReviewContent());
  const res = await checkGameplayReview(reviewPath, join(dir, 'nexiste-pas.yaml'));
  assert.equal(res.ok, false);
  assert.ok(res.problems.some((p) => p.includes('checklist introuvable')));
});

test('document illisible -> rejet, pas de crash', async (t) => {
  const dir = makeDir(t);
  const checklistPath = writeChecklist(dir);
  const res = await checkGameplayReview(join(dir, 'absent.md'), checklistPath);
  assert.equal(res.ok, false);
  assert.ok(res.problems.some((p) => p.includes('document illisible')));
});

test('parseChecklistItemIds extrait uniquement les ids d\'item (pas les ids de categorie)', () => {
  const ids = parseChecklistItemIds(CHECKLIST);
  assert.deepEqual(ids, ['a.un', 'a.deux', 'b.un']);
});

test('extractJsonBlock retourne null si absent, le contenu sinon', () => {
  assert.equal(extractJsonBlock('rien ici'), null);
  const block = extractJsonBlock('texte\n```json\n{"a":1}\n```\nsuite');
  assert.equal(JSON.parse(block).a, 1);
});

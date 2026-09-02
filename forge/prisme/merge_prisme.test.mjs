// merge_prisme.test.mjs — jamais testé avant promotion (Tier 2 #6). Recombinaison
// mécanique du panel Prisme : union par critère charter cité, zéro LLM-arbitre.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  extractCharterCriteria,
  citedTags,
  extractRulesSection,
  mergePrisme,
  resolveSourceRole,
} from './merge_prisme.mjs';

const CHARTER = `objectif: >-
  Forger un jeu.

criteres_succes:
  - "SOLVABILITE PROUVEE : un bot gagne réellement."
  - "DETERMINISME : même seed, même résultat."
  - "PHYSIQUE STRICTE : rebond exact."

actions_interdites:
  - "Tricher."
`;

test('extractCharterCriteria extrait les 3 tags dans l\'ordre du charter', () => {
  const tags = extractCharterCriteria(CHARTER);
  assert.deepEqual(tags, ['SOLVABILITE PROUVEE', 'DETERMINISME', 'PHYSIQUE STRICTE']);
});

test('citedTags matche par sous-chaine insensible a la casse', () => {
  const tags = ['DETERMINISME', 'PHYSIQUE STRICTE'];
  const found = citedTags('Ce lens couvre le determinisme du jeu.', tags);
  assert.deepEqual(found, ['DETERMINISME']);
});

test('extractRulesSection isole le texte de la section 4 jusqu\'a Tracabilite', () => {
  const doc = `## 4. RÈGLES OBSERVABLES\n\n- **R1 — test.**\n\n## Traçabilité\n\nautre chose\n`;
  const rules = extractRulesSection(doc);
  assert.equal(rules, '- **R1 — test.**');
});

test('extractRulesSection retourne vide si section absente', () => {
  assert.equal(extractRulesSection('# rien ici'), '');
});

test('mergePrisme : couverture complete -> zero gap', () => {
  const { output, controlScopeTags, gaps } = mergePrisme({
    charterText: CHARTER,
    controlContent: 'Le controle couvre SOLVABILITE PROUVEE et DETERMINISME.',
    lenses: [
      { path: 'lens1.md', content: '## 4. RÈGLES OBSERVABLES\n\n- **R1 — solvabilite prouvee ici.**' },
      { path: 'lens2.md', content: '## 4. RÈGLES OBSERVABLES\n\n- **R2 — determinisme assure ici.**' },
    ],
  });
  assert.deepEqual(controlScopeTags, ['SOLVABILITE PROUVEE', 'DETERMINISME']);
  assert.deepEqual(gaps, []);
  assert.ok(output.includes('R1 — solvabilite'));
  assert.ok(output.includes('R2 — determinisme'));
});

test('mergePrisme : critere du controle non couvert par aucun lens -> GAP remonte, pas devine', () => {
  const { gaps, output } = mergePrisme({
    charterText: CHARTER,
    controlContent: 'Le controle couvre SOLVABILITE PROUVEE et PHYSIQUE STRICTE.',
    lenses: [
      { path: 'lens1.md', content: '## 4. RÈGLES OBSERVABLES\n\n- **R1 — solvabilite prouvee ici.**' },
    ],
  });
  assert.deepEqual(gaps, ['PHYSIQUE STRICTE']);
  assert.ok(output.includes('GAP'));
  assert.ok(output.includes('PHYSIQUE STRICTE'));
});

test('mergePrisme : un critere hors perimetre du controle n\'est jamais liste (pas de bruit)', () => {
  const { controlScopeTags } = mergePrisme({
    charterText: CHARTER,
    controlContent: 'Le controle ne couvre que SOLVABILITE PROUVEE.',
    lenses: [{ path: 'lens1.md', content: 'DETERMINISME et PHYSIQUE STRICTE ici aussi.' }],
  });
  assert.deepEqual(controlScopeTags, ['SOLVABILITE PROUVEE']);
});

// --- resolveSourceRole (mission N2-0 2026-07-28) : mapping mecanique chemin -> role ---

test('resolveSourceRole : product_snapshot_gamedesign.md -> gamedesign', () => {
  assert.equal(resolveSourceRole('EVIDENCE/runs/snake/prisme/product_snapshot_gamedesign.md'), 'gamedesign');
});

test('resolveSourceRole : product_snapshot_archidepot.md -> archidepot', () => {
  assert.equal(resolveSourceRole('product_snapshot_archidepot.md'), 'archidepot');
});

test('resolveSourceRole : product_snapshot_gameplayprog.md -> gameplayprog', () => {
  assert.equal(resolveSourceRole('product_snapshot_gameplayprog.md'), 'gameplayprog');
});

test('resolveSourceRole : isControl=true -> control, quel que soit le nom', () => {
  assert.equal(resolveSourceRole('EVIDENCE/runs/snake/product_snapshot.md', true), 'control');
});

test('resolveSourceRole : nom inattendu -> basename sans extension, jamais un echec silencieux', () => {
  assert.equal(resolveSourceRole('quelque/chemin/notes_bizarres.md'), 'notes_bizarres');
});

// --- mergePrisme : bloc machine-lisible source_role -----------------------------------

test('mergePrisme : bloc json final contient coverage_by_role et roles, parsable', () => {
  const { output } = mergePrisme({
    charterText: CHARTER,
    controlContent: 'Le controle couvre SOLVABILITE PROUVEE et DETERMINISME.',
    lenses: [
      { path: 'product_snapshot_gamedesign.md', content: '## 4. RÈGLES OBSERVABLES\n\n- **R1 — solvabilite prouvee ici.**' },
      { path: 'product_snapshot_archidepot.md', content: '## 4. RÈGLES OBSERVABLES\n\n- **R2 — determinisme assure ici.**' },
    ],
  });
  const match = output.match(/```json\n([\s\S]*?)\n```/);
  assert.ok(match, 'bloc json absent de la sortie');
  const parsed = JSON.parse(match[1]);
  assert.deepEqual(new Set(parsed.roles), new Set(['gamedesign', 'archidepot']));
  assert.deepEqual(parsed.coverage_by_role['SOLVABILITE PROUVEE'], ['gamedesign']);
  assert.deepEqual(parsed.coverage_by_role['DETERMINISME'], ['archidepot']);
  assert.deepEqual(parsed.coverage_by_role['PHYSIQUE STRICTE'], []);
});

test('mergePrisme : ne fusionne ni ne selectionne jamais un texte "meilleur" entre lenses (union verbatim)', () => {
  const { output } = mergePrisme({
    charterText: CHARTER,
    controlContent: 'SOLVABILITE PROUVEE.',
    lenses: [
      { path: 'lens-a.md', content: '## 4. RÈGLES OBSERVABLES\n\n- **R1 — version A du lens.**' },
      { path: 'lens-b.md', content: '## 4. RÈGLES OBSERVABLES\n\n- **R1 — version B, divergente, du lens.**' },
    ],
  });
  // les DEUX versions doivent survivre verbatim -- aucun arbitrage semantique.
  assert.ok(output.includes('version A du lens'));
  assert.ok(output.includes('version B, divergente'));
});

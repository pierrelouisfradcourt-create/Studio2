// check_artbible.test.mjs — oracle structurel de l'Art Director (contrat s2.5-artbible.yaml).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  parseFrontmatter,
  splitSections,
  checkArtBibleMarkdown,
  checkAssetRequestsShape,
  validateVisualRequirement,
  extractVisualRequirements,
  checkCoverage,
  checkArtBible,
} from './check_artbible.mjs';

/**
 * Construit un art_bible.md complet (3 sections v0.1) à partir d'une liste de
 * visual_requirements et d'un texte de rationale optionnel (pour tester la
 * "déclaration mensongère" — la prose peut dire ce qu'elle veut, seule la donnée
 * structurée compte pour la couverture).
 */
function bibleWithRequirements(visualRequirements, { rationale = 'Le product_snapshot decrit un jeu tactique de survie sous tension — la palette froide et les silhouettes nettes servent la lisibilite tactique avant tout.' } = {}) {
  return `---
styles: [flat-top-down, gritty]
mood_keywords: [tense, industrial, minimal]
---

## 1. IDENTITÉ VISUELLE

Style top-down plat, palette froide desaturee, silhouettes lisibles à distance.
Références : Kenney top-down shooter pour la lisibilité des unités.

## 2. RATIONALE

${rationale}

## 3. BESOINS VISUELS

\`\`\`json
${JSON.stringify({ visual_requirements: visualRequirements }, null, 2)}
\`\`\`
`;
}

const GOOD_BIBLE = bibleWithRequirements([
  { id: 'player_character', entity_role: 'player', required: true, description: 'Le personnage joueur, sprite vu de dessus.' },
]);

function goodRequest(overrides = {}) {
  return {
    id: 'req-player-1',
    entity_role: 'player',
    purpose: 'gameplay',
    type: 'sprite',
    style: 'flat-top-down',
    references: [],
    constraints: { format: '2D', runtime: 'html', license_allowed: [], genre: ['tactical'], max_size_kb: null },
    acceptance_tests: [{ check: 'resolved' }],
    ...overrides,
  };
}

test('parseFrontmatter lit styles/mood_keywords en listes inline', () => {
  const fm = parseFrontmatter(GOOD_BIBLE);
  assert.deepEqual(fm.styles, ['flat-top-down', 'gritty']);
  assert.deepEqual(fm.mood_keywords, ['tense', 'industrial', 'minimal']);
});

test('parseFrontmatter retourne null si absent', () => {
  assert.equal(parseFrontmatter('## 1. IDENTITÉ VISUELLE\ntexte'), null);
});

test('splitSections trouve les 3 sections requises (v0.1 : + BESOINS VISUELS)', () => {
  const sections = splitSections(GOOD_BIBLE);
  assert.ok(sections.has('identite_visuelle'));
  assert.ok(sections.has('rationale'));
  assert.ok(sections.has('besoins_visuels'));
});

test('checkArtBibleMarkdown : bible bien formee => aucun finding, visual_requirements extraites', () => {
  const { findings, styles, visualRequirements } = checkArtBibleMarkdown(GOOD_BIBLE);
  assert.deepEqual(findings, []);
  assert.deepEqual(styles, ['flat-top-down', 'gritty']);
  assert.equal(visualRequirements.length, 1);
  assert.equal(visualRequirements[0].entity_role, 'player');
});

test('checkArtBibleMarkdown : frontmatter absent => finding', () => {
  const { findings } = checkArtBibleMarkdown('## 1. IDENTITÉ VISUELLE\ntexte suffisamment long pour passer le seuil minimal ici.\n\n## 2. RATIONALE\ntexte suffisamment long pour passer le seuil minimal aussi ici.');
  assert.ok(findings.some((f) => f.includes('frontmatter')));
});

test('checkArtBibleMarkdown : section BESOINS VISUELS manquante => finding (v0.1 mandatoire)', () => {
  const noSection = `---
styles: [flat-top-down]
mood_keywords: [tense]
---

## 1. IDENTITÉ VISUELLE

texte suffisamment long pour passer le seuil minimal ici sans probleme aucun.

## 2. RATIONALE

texte suffisamment long pour passer le seuil minimal aussi ici sans souci.
`;
  const { findings } = checkArtBibleMarkdown(noSection);
  assert.ok(findings.some((f) => f.includes('besoins_visuels')));
});

test('checkArtBibleMarkdown : section trop courte => finding', () => {
  const bad = GOOD_BIBLE.replace(/Le product_snapshot[\s\S]*tactique avant tout\./, 'trop court');
  const { findings } = checkArtBibleMarkdown(bad);
  assert.ok(findings.some((f) => f.includes('trop courte')));
});

test('checkArtBibleMarkdown : placeholder detecte', () => {
  const bad = GOOD_BIBLE.replace('tension', 'à définir');
  const { findings } = checkArtBibleMarkdown(bad);
  assert.ok(findings.some((f) => f.includes('placeholder')));
});

test('checkArtBibleMarkdown : bloc ```json absent dans BESOINS VISUELS => finding', () => {
  const bad = GOOD_BIBLE.replace(/```json[\s\S]*```/, 'pas de json ici, juste du texte suffisamment long pour la section');
  const { findings } = checkArtBibleMarkdown(bad);
  assert.ok(findings.some((f) => f.includes('bloc ```json absent')));
});

test('checkArtBibleMarkdown : JSON invalide dans BESOINS VISUELS => finding', () => {
  const bad = GOOD_BIBLE.replace(/```json[\s\S]*?```/, '```json\n{ceci n\'est pas du json valide}\n```');
  const { findings } = checkArtBibleMarkdown(bad);
  assert.ok(findings.some((f) => f.includes('JSON invalide')));
});

test('validateVisualRequirement : entree bien formee => aucun finding', () => {
  const vr = { id: 'x', entity_role: 'obstacle', required: true, description: 'un obstacle' };
  assert.deepEqual(validateVisualRequirement(vr, 0), []);
});

test('validateVisualRequirement : entity_role invalide => finding', () => {
  const vr = { id: 'x', entity_role: 'monstre-final', required: true, description: 'x' };
  const findings = validateVisualRequirement(vr, 0);
  assert.ok(findings.some((f) => f.includes('entity_role invalide')));
});

test('validateVisualRequirement : required absent (pas un booleen explicite) => finding', () => {
  const vr = { id: 'x', entity_role: 'obstacle', description: 'x' };
  const findings = validateVisualRequirement(vr, 0);
  assert.ok(findings.some((f) => f.includes('required')));
});

test('extractVisualRequirements : bloc json valide => visual_requirements extraites', () => {
  const body = '```json\n{"visual_requirements":[{"id":"a","entity_role":"item","required":false,"description":"une piece"}]}\n```';
  const { findings, visualRequirements } = extractVisualRequirements(body);
  assert.deepEqual(findings, []);
  assert.equal(visualRequirements.length, 1);
});

test('checkAssetRequestsShape : requete valide + style declare => aucun finding', () => {
  const doc = { requests: [goodRequest()], no_assets_needed: false, reason: null };
  const findings = checkAssetRequestsShape(doc, ['flat-top-down']);
  assert.deepEqual(findings, []);
});

test('checkAssetRequestsShape : style non declare dans la bible => finding', () => {
  const doc = { requests: [goodRequest({ style: 'pixel-art' })], no_assets_needed: false, reason: null };
  const findings = checkAssetRequestsShape(doc, ['flat-top-down']);
  assert.ok(findings.some((f) => f.includes('non declare')));
});

test('checkAssetRequestsShape : requete malformee remontee via validateRequestShape (pas duplique)', () => {
  const bad = goodRequest();
  delete bad.type;
  const doc = { requests: [bad], no_assets_needed: false, reason: null };
  const findings = checkAssetRequestsShape(doc, ['flat-top-down']);
  assert.ok(findings.some((f) => f.includes('requests[0]')));
});

test('checkAssetRequestsShape : no_assets_needed=true coherent (requests=[], reason rempli)', () => {
  const doc = { requests: [], no_assets_needed: true, reason: 'jeu textuel, aucun asset visuel requis' };
  assert.deepEqual(checkAssetRequestsShape(doc, []), []);
});

test('checkAssetRequestsShape : no_assets_needed=true mais requests non vide => incoherent', () => {
  const doc = { requests: [goodRequest()], no_assets_needed: true, reason: 'texte' };
  const findings = checkAssetRequestsShape(doc, ['flat-top-down']);
  assert.ok(findings.some((f) => f.includes('incoherente')));
});

test('checkAssetRequestsShape : requests vide sans declaration explicite => finding (pas un oubli silencieux)', () => {
  const doc = { requests: [], no_assets_needed: false, reason: null };
  const findings = checkAssetRequestsShape(doc, []);
  assert.ok(findings.some((f) => f.includes('declarez explicitement')));
});

// --- v0.1 : checkCoverage (fonction pure) ---

test('checkCoverage : besoin required=true couvert par une requete du meme entity_role => satisfied', () => {
  const vr = [{ id: 'a', entity_role: 'obstacle', required: true, description: 'x' }];
  const requests = [{ entity_role: 'obstacle' }];
  const result = checkCoverage(vr, requests, false);
  assert.equal(result.checked, true);
  assert.deepEqual(result.missing, []);
  assert.deepEqual(result.satisfied, ['a']);
});

test('checkCoverage : besoin required=false sans requete correspondante => pas de manque (optionnel)', () => {
  const vr = [{ id: 'a', entity_role: 'decoration', required: false, description: 'x' }];
  const result = checkCoverage(vr, [], false);
  assert.deepEqual(result.missing, []);
});

test('checkCoverage : no_assets_needed=true court-circuite la verification (jeu sans assets externes)', () => {
  const vr = [{ id: 'a', entity_role: 'player', required: true, description: 'x' }];
  const result = checkCoverage(vr, [], true);
  assert.equal(result.checked, false);
  assert.deepEqual(result.missing, []);
});

// --- v0.1 : les 4 scenarios du spec (gate sur checkArtBible bout-en-bout) ---

async function runArtBible(visualRequirements, requests, { noAssetsNeeded = false, reason = null, rationale } = {}) {
  const { writeFile } = await import('node:fs/promises');
  const { tmpdir } = await import('node:os');
  const { join } = await import('node:path');
  const biblePath = join(tmpdir(), `test_art_bible_${Math.floor(Math.random() * 1e9) + Date.now()}.md`);
  const reqPath = join(tmpdir(), `test_asset_requests_${Math.floor(Math.random() * 1e9) + Date.now()}.json`);
  await writeFile(biblePath, bibleWithRequirements(visualRequirements, { rationale }), 'utf-8');
  await writeFile(reqPath, JSON.stringify({ requests, no_assets_needed: noAssetsNeeded, reason }), 'utf-8');
  return checkArtBible(biblePath, reqPath, null);
}

test('scenario 1 (cas valide) : besoins [player, obstacle, environment] tous couverts => OK', async () => {
  const vr = [
    { id: 'p', entity_role: 'player', required: true, description: 'le heros' },
    { id: 'o', entity_role: 'obstacle', required: true, description: 'obstacle mortel' },
    { id: 'e', entity_role: 'environment', required: true, description: 'decor de niveau' },
  ];
  const requests = [
    goodRequest({ id: 'r1', entity_role: 'player' }),
    goodRequest({ id: 'r2', entity_role: 'obstacle' }),
    goodRequest({ id: 'r3', entity_role: 'environment' }),
  ];
  const result = await runArtBible(vr, requests);
  assert.equal(result.verdict, 'OK');
  assert.equal(result.pass, true);
  assert.deepEqual(result.coverage.missing, []);
});

test('scenario 2 (couverture manquante) : besoin [player, obstacle], requete seulement [player] => BLOCKED', async () => {
  const vr = [
    { id: 'p', entity_role: 'player', required: true, description: 'le heros' },
    { id: 'o', entity_role: 'obstacle', required: true, description: 'obstacle mortel' },
  ];
  const requests = [goodRequest({ id: 'r1', entity_role: 'player' })];
  const result = await runArtBible(vr, requests);
  assert.equal(result.verdict, 'BLOCKED');
  assert.equal(result.pass, false);
  assert.equal(result.coverage.missing.length, 1);
  assert.equal(result.coverage.missing[0].entity_role, 'obstacle');
});

test('scenario 3 (declaration mensongere) : rationale affirme "obstacles couverts" sans requete obstacle => BLOCKED quand meme', async () => {
  const vr = [
    { id: 'p', entity_role: 'player', required: true, description: 'le heros' },
    { id: 'o', entity_role: 'obstacle', required: true, description: 'obstacle mortel' },
  ];
  const requests = [goodRequest({ id: 'r1', entity_role: 'player' })];
  const result = await runArtBible(vr, requests, {
    rationale: 'L\'ensemble des surfaces visuelles du jeu — personnage et obstacles — est couvert par les demandes d\'asset ci-dessous, tout est pris en charge.',
  });
  // La prose du rationale n'est jamais lue par checkCoverage : seule la donnee
  // structuree (entity_role des requetes) compte. Ferme exactement le vecteur de
  // la sonde "deceptive builder" (docs/forge/S2_5_ARTBIBLE_DECEPTIVE_PROBE_NOTE.md).
  assert.equal(result.verdict, 'BLOCKED');
  assert.ok(result.coverage.missing.some((m) => m.entity_role === 'obstacle'));
});

test('scenario 4 (no_assets_needed) : jeu sans assets externes => OK, couverture non verifiee', async () => {
  const vr = [{ id: 'p', entity_role: 'player', required: true, description: 'le heros' }];
  const result = await runArtBible(vr, [], { noAssetsNeeded: true, reason: 'rendu 100% primitives canvas, aucun asset externe' });
  assert.equal(result.verdict, 'OK');
  assert.equal(result.coverage.checked, false);
});

test('checkArtBible bout-en-bout : bible+requests valides => OK, stats advisory calculees', async () => {
  const fakeCatalog = {
    catalog_version: 1,
    entries: [
      {
        entry_type: 'asset', asset_id: 'asset-t', source: 's', license: 'CC0-1.0',
        provenance_url: 'https://example.test', style: 'flat-top-down', genre: ['tactical'],
        biome: null, format: '2D', size_kb: 1, sha256: 'a'.repeat(64), runtime: 'html',
        ingested: true, path: 'knowledge_base/assets/characters/kenney_survivor1_stand.png',
        usage_examples: [], tier: 'candidate',
      },
    ],
  };
  const { writeFile } = await import('node:fs/promises');
  const { tmpdir } = await import('node:os');
  const { join } = await import('node:path');
  const biblePath = join(tmpdir(), 'test_art_bible.md');
  const reqPath = join(tmpdir(), 'test_asset_requests.json');
  await writeFile(biblePath, GOOD_BIBLE, 'utf-8');
  await writeFile(reqPath, JSON.stringify({ requests: [goodRequest()], no_assets_needed: false, reason: null }), 'utf-8');

  const result = await checkArtBible(biblePath, reqPath, fakeCatalog);
  assert.equal(result.pass, true);
  assert.equal(result.verdict, 'OK');
  assert.equal(result.resolution_stats.total, 1);
  assert.equal(result.resolution_stats.ok, 1);
});

test('checkArtBible : fichier manquant => FAIL, jamais une exception', async () => {
  const result = await checkArtBible('/inexistant/art_bible.md', '/inexistant/asset_requests.json', null);
  assert.equal(result.pass, false);
  assert.equal(result.verdict, 'FAIL');
  assert.ok(result.findings[0].includes('illisible'));
});

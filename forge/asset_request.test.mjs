// asset_request.test.mjs — couvre l'Asset Contract V0 (docs/forge/ASSET_CONTRACT_V0.md).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { validateRequestShape, resolveRequest, runAcceptanceTests, evaluateAssetRequest, ENTITY_ROLES, PURPOSES } from './asset_request.mjs';

// Catalogue minimal de test — miroir volontairement réduit de knowledge_base/catalog.json
// (mêmes formes que la vraie entrée kenney-survivor1-stand), pour ne pas dépendre du
// contenu réel du catalogue (qui peut évoluer) dans ces tests unitaires.
function fakeCatalog() {
  return {
    catalog_version: 1,
    entries: [
      {
        entry_type: 'asset',
        asset_id: 'asset-test-survivor',
        source: 'Kenney — Top-down Shooter',
        license: 'CC0-1.0',
        provenance_url: 'https://example.test/pack',
        style: 'flat-top-down',
        genre: ['tactical', 'survival'],
        biome: null,
        format: '2D',
        size_kb: 1,
        sha256: 'a'.repeat(64),
        runtime: 'html',
        ingested: true,
        path: 'knowledge_base/assets/characters/kenney_survivor1_stand.png',
        usage_examples: [],
        tier: 'candidate',
      },
      {
        entry_type: 'asset',
        asset_id: 'asset-test-validated',
        source: 'Kenney — Top-down Shooter',
        license: 'CC0-1.0',
        provenance_url: 'https://example.test/pack',
        style: 'flat-top-down',
        genre: ['tactical'],
        biome: null,
        format: '2D',
        size_kb: 1,
        sha256: 'b'.repeat(64),
        runtime: 'html',
        ingested: true,
        path: 'knowledge_base/assets/characters/kenney_manBlue_stand.png',
        usage_examples: ['GAMES/leviathan/public/assets/characters/kenney_manBlue_stand.png'],
        tier: 'validated',
      },
      {
        entry_type: 'asset',
        asset_id: 'asset-test-godot',
        source: 'Quaternius — pack',
        license: 'CC0-1.0',
        provenance_url: 'https://example.test/pack3d',
        style: 'lowpoly',
        genre: ['rpg'],
        biome: null,
        format: '3D',
        size_kb: null,
        sha256: null,
        runtime: 'godot',
        ingested: false,
        path: null,
        usage_examples: [],
        tier: 'candidate',
      },
    ],
  };
}

function baseRequest(overrides = {}) {
  return {
    id: 'test-request-1',
    entity_role: 'player',
    purpose: 'gameplay',
    type: 'sprite',
    style: 'flat-top-down',
    references: [],
    constraints: {
      format: '2D',
      runtime: 'html',
      license_allowed: [],
      genre: ['tactical'],
      max_size_kb: null,
    },
    acceptance_tests: [{ check: 'resolved' }, { check: 'license_in_allowlist' }],
    ...overrides,
  };
}

test('requete bien formee sans erreur de forme', () => {
  assert.deepEqual(validateRequestShape(baseRequest()), []);
});

test('champ Critique absent (type) -> erreur de forme, pas une valeur par defaut', () => {
  const req = baseRequest();
  delete req.type;
  const errors = validateRequestShape(req);
  assert.ok(errors.some((e) => e.includes('type')));
});

test('champ Important absent (references) rejete ; declare vide ([]) accepte', () => {
  const withField = baseRequest();
  assert.deepEqual(validateRequestShape(withField), []);
  const withoutField = baseRequest();
  delete withoutField.references;
  const errors = validateRequestShape(withoutField);
  assert.ok(errors.some((e) => e.includes('references')));
});

test('check inconnu (hors liste fermee) -> erreur de forme', () => {
  const req = baseRequest({ acceptance_tests: [{ check: 'est_ce_que_cest_beau' }] });
  const errors = validateRequestShape(req);
  assert.ok(errors.some((e) => e.includes('check inconnu')));
});

test('acceptance_tests vide -> erreur de forme (au moins "resolved" attendu)', () => {
  const req = baseRequest({ acceptance_tests: [] });
  const errors = validateRequestShape(req);
  assert.ok(errors.some((e) => e.includes('acceptance_tests')));
});

test('requete valide resout une entree existante du catalogue (OK)', () => {
  const catalog = fakeCatalog();
  const result = evaluateAssetRequest(baseRequest(), catalog);
  assert.equal(result.verdict, 'OK');
  assert.ok(result.resolved);
  assert.equal(result.checks.every((c) => c.ok), true);
  assert.match(result.fog, /esthetique/);
});

test('contrainte insatisfiable (genre absent du catalogue) -> BLOCKED, pas FAIL', () => {
  const catalog = fakeCatalog();
  const req = baseRequest({ constraints: { format: '2D', runtime: 'html', license_allowed: [], genre: ['inexistant'], max_size_kb: null } });
  const result = evaluateAssetRequest(req, catalog);
  assert.equal(result.verdict, 'BLOCKED');
  assert.equal(result.resolved, null);
  assert.match(result.fog, /HumanGate/);
});

test('requete malformee -> FAIL, jamais BLOCKED', () => {
  const catalog = fakeCatalog();
  const req = baseRequest();
  delete req.style;
  const result = evaluateAssetRequest(req, catalog);
  assert.equal(result.verdict, 'FAIL');
  assert.ok(result.shape_errors.length > 0);
});

test('usage_referenced exige tier validated + usage_examples non vide', () => {
  const catalog = fakeCatalog();
  const req = baseRequest({ acceptance_tests: [{ check: 'resolved' }, { check: 'usage_referenced' }] });
  const result = evaluateAssetRequest(req, catalog);
  // asset-test-survivor (tier candidate, usage_examples=[]) est premier par tri id ;
  // asset-test-validated (tier validated) doit primer dans le tri (validated avant candidate).
  assert.equal(result.verdict, 'OK');
  assert.equal(result.resolved.asset_id, 'asset-test-validated');
});

test('3D manifest-only : on_disk coherent uniquement si format demande = 3D', () => {
  const catalog = fakeCatalog();
  const req = baseRequest({
    style: 'lowpoly',
    constraints: { format: '3D', runtime: 'godot', license_allowed: [], genre: ['rpg'], max_size_kb: null },
    acceptance_tests: [{ check: 'resolved' }, { check: 'on_disk' }],
  });
  const result = evaluateAssetRequest(req, catalog);
  assert.equal(result.verdict, 'OK');
  assert.equal(result.resolved.asset_id, 'asset-test-godot');
});

test('max_size_kb avec entry.size_kb null (manifest-only) -> BLOCKED, pas un bypass silencieux (gate 4 Qwen 2026-07-14)', () => {
  const catalog = fakeCatalog();
  const req = baseRequest({
    style: 'lowpoly',
    constraints: { format: '3D', runtime: 'godot', license_allowed: [], genre: ['rpg'], max_size_kb: 100 },
    acceptance_tests: [{ check: 'resolved' }],
  });
  const result = evaluateAssetRequest(req, catalog);
  assert.equal(result.verdict, 'BLOCKED');
});

test('v0.1 : entity_role/purpose/id Critiques -- absents rejetes (gate 4 + sonde deceptive builder, 2026-07-14)', () => {
  for (const field of ['id', 'entity_role', 'purpose']) {
    const req = baseRequest();
    delete req[field];
    const errors = validateRequestShape(req);
    assert.ok(errors.some((e) => e.includes(field)), `attendu une erreur citant ${field}`);
  }
});

test('v0.1 : entity_role hors liste fermee -> erreur de forme', () => {
  const req = baseRequest({ entity_role: 'protagoniste' });
  const errors = validateRequestShape(req);
  assert.ok(errors.some((e) => e.includes('entity_role invalide')));
});

test('v0.1 : purpose hors liste fermee -> erreur de forme', () => {
  const req = baseRequest({ purpose: 'esthetique' });
  const errors = validateRequestShape(req);
  assert.ok(errors.some((e) => e.includes('purpose invalide')));
});

test('v0.1 : ENTITY_ROLES/PURPOSES exportes et couvrent les valeurs du spec', () => {
  assert.ok(ENTITY_ROLES.includes('obstacle'));
  assert.ok(ENTITY_ROLES.includes('player'));
  assert.ok(PURPOSES.includes('gameplay'));
});

test('resolveRequest et runAcceptanceTests exposes independamment (composabilite)', () => {
  const catalog = fakeCatalog();
  const req = baseRequest();
  const { resolved, candidates } = resolveRequest(req, catalog);
  assert.ok(candidates.length >= 1);
  const checks = runAcceptanceTests(req, resolved);
  assert.equal(checks.length, req.acceptance_tests.length);
});

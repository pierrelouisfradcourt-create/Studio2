// fill_usage_examples.test.mjs — tests de fill_usage_examples.mjs (R8, Forge V2 §4-A).
// node --test, zéro réseau, zéro LLM.
//
// Deux blocs :
//   1. Unité, sur fixtures ÉPHÉMÈRES (tmpdir, jamais games/ ni knowledge_base/catalog.json réels)
//      — prouve le remplissage réel sur ASSET et BRICK (schéma étendu, arbitrage Pierre), le
//      gap de schéma restant assumé sur ROLE (non étendu), l'idempotence, et la non-altération
//      des autres champs.
//   2. Intégration, sur le VRAI dépôt : les 2 imports connus (kb_tactics, shmup_slice ->
//      sys-damage-floor/sys-reachability) sont réellement écrits dans catalog.json, kb-validate
//      reste vert, et une 2e exécution est idempotente (0 octet changé).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname, resolve } from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

import { detectKnowledgeBaseImports, applyUsageExamples } from './fill_usage_examples.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(__dirname, '..');
const SCRIPT = resolve(__dirname, 'fill_usage_examples.mjs');
const KB_VALIDATE = resolve(__dirname, 'kb-validate.mjs');
const REAL_CATALOG = resolve(__dirname, 'catalog.json');

// --- bloc 1 : fixtures éphémères, isolées du dépôt réel -----------------------------------------

function makeFixtureRepo() {
  const root = mkdtempSync(join(tmpdir(), 'kb-fill-usage-'));
  const gamesDir = join(root, 'games', 'testgame');
  mkdirSync(gamesDir, { recursive: true });

  // Un importateur d'une entrée ASSET (ASSET_SPEC — usage_examples historique).
  writeFileSync(
    join(gamesDir, 'assetUser.mjs'),
    'import { x } from "../../knowledge_base/systems/asset_target.mjs";\nexport const y = x;\n'
  );
  // Un importateur d'une entrée BRICK (BRICK_SPEC — usage_examples FACULTATIF depuis l'arbitrage
  // Pierre R8 ; la fixture ne l'a PAS encore, exactement comme sys-damage-floor/sys-reachability
  // avant ce run — le champ doit être CRÉÉ, pas seulement mis à jour).
  writeFileSync(
    join(gamesDir, 'brickUser.mjs'),
    'import { z } from "../../knowledge_base/systems/brick_target.mjs";\nexport const w = z;\n'
  );
  // Un importateur d'une entrée ROLE — hors périmètre de l'arbitrage (ROLE_SPEC non étendu) :
  // doit rester un gap de schéma assumé, jamais écrit.
  writeFileSync(
    join(gamesDir, 'roleUser.mjs'),
    'import { r } from "../../knowledge_base/roles/role_target.yaml";\nexport const q = r;\n'
  );
  // Un fichier de test — ne doit JAMAIS être scanné (même périmètre que reuse_ratio.mjs).
  writeFileSync(
    join(gamesDir, 'assetUser.test.mjs'),
    'import { x } from "../../knowledge_base/systems/should_not_be_detected.mjs";\n'
  );

  const catalog = {
    catalog_version: 1,
    entries: [
      { entry_type: 'asset', asset_id: 'asset-x', path: 'knowledge_base/systems/asset_target.mjs', usage_examples: [] },
      { entry_type: 'brick', brick_id: 'sys-y', kind: 'system', path: 'knowledge_base/systems/brick_target.mjs' },
      { entry_type: 'role', role_id: 'role-z', path: 'knowledge_base/roles/role_target.yaml' }
    ]
  };

  return { root, gamesDir: join(root, 'games'), catalog };
}

test('détection : trouve les imports knowledge_base/ des trois importateurs, ignore le .test.mjs', () => {
  const { root, gamesDir } = makeFixtureRepo();
  try {
    const detected = detectKnowledgeBaseImports(gamesDir, root);
    assert.equal(detected.length, 3, 'exactement 3 imports détectés (le .test.mjs est exclu)');
    assert.ok(detected.some(d => d.importer === 'games/testgame/assetUser.mjs' &&
      d.kbPath === 'knowledge_base/systems/asset_target.mjs'));
    assert.ok(detected.some(d => d.importer === 'games/testgame/brickUser.mjs' &&
      d.kbPath === 'knowledge_base/systems/brick_target.mjs'));
    assert.ok(detected.some(d => d.importer === 'games/testgame/roleUser.mjs' &&
      d.kbPath === 'knowledge_base/roles/role_target.yaml'));
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('applyUsageExamples : remplit ASSET et BRICK (schéma étendu), classe ROLE en schemaGap SANS le modifier', () => {
  const { root, gamesDir, catalog } = makeFixtureRepo();
  try {
    const detected = detectKnowledgeBaseImports(gamesDir, root);
    const result = applyUsageExamples(catalog.entries, detected);

    assert.equal(result.appended.length, 2, 'ASSET et BRICK sont tous deux remplis');
    assert.ok(result.appended.some(a => a.id === 'asset-x'));
    assert.ok(result.appended.some(a => a.id === 'sys-y'));

    assert.equal(result.schemaGap.length, 1, 'seul ROLE reste en gap (ROLE_SPEC non étendu)');
    assert.equal(result.schemaGap[0].id, 'role-z');
    assert.equal(result.unmatched.length, 0);

    const asset = result.entries.find(e => e.asset_id === 'asset-x');
    assert.deepEqual(asset.usage_examples, ['games/testgame/assetUser.mjs']);

    const brick = result.entries.find(e => e.brick_id === 'sys-y');
    assert.deepEqual(brick.usage_examples, ['games/testgame/brickUser.mjs'],
      'BRICK reçoit désormais la clé (créée, pas seulement mise à jour — elle était absente au départ)');

    const role = result.entries.find(e => e.role_id === 'role-z');
    assert.ok(!('usage_examples' in role), 'ROLE ne reçoit JAMAIS la clé usage_examples (ROLE_SPEC fermé, non étendu)');
    assert.deepEqual(role, catalog.entries[2], 'entrée ROLE strictement inchangée');
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('applyUsageExamples : ne touche à AUCUN autre champ des entrées ASSET/BRICK modifiées', () => {
  const { root, gamesDir } = makeFixtureRepo();
  try {
    const detected = detectKnowledgeBaseImports(gamesDir, root);
    const richAsset = {
      entry_type: 'asset', asset_id: 'asset-x', source: 'Kenney', license: 'CC0-1.0', tier: 'candidate',
      path: 'knowledge_base/systems/asset_target.mjs', usage_examples: []
    };
    const richBrick = {
      entry_type: 'brick', brick_id: 'sys-y', kind: 'system', function: 'un truc pur',
      tier: 'candidate', path: 'knowledge_base/systems/brick_target.mjs'
    };
    const result = applyUsageExamples([richAsset, richBrick], detected);

    const updatedAsset = result.entries.find(e => e.asset_id === 'asset-x');
    assert.equal(updatedAsset.source, 'Kenney');
    assert.equal(updatedAsset.license, 'CC0-1.0');
    assert.equal(updatedAsset.tier, 'candidate');
    assert.deepEqual(updatedAsset.usage_examples, ['games/testgame/assetUser.mjs']);

    const updatedBrick = result.entries.find(e => e.brick_id === 'sys-y');
    assert.equal(updatedBrick.function, 'un truc pur');
    assert.equal(updatedBrick.kind, 'system');
    assert.equal(updatedBrick.tier, 'candidate');
    assert.deepEqual(updatedBrick.usage_examples, ['games/testgame/brickUser.mjs']);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('idempotence : appliquer deux fois les mêmes imports détectés ne duplique rien et stabilise', () => {
  const { root, gamesDir, catalog } = makeFixtureRepo();
  try {
    const detected = detectKnowledgeBaseImports(gamesDir, root);

    const first = applyUsageExamples(catalog.entries, detected);
    assert.equal(first.appended.length, 2);

    const second = applyUsageExamples(first.entries, detected);
    assert.equal(second.appended.length, 0, 'rien de nouveau à ajouter au 2e passage');
    assert.equal(second.alreadyPresent.length, 2, 'le 2e passage reconnaît les 2 entrées déjà remplies');
    assert.equal(second.schemaGap.length, 1, 'le gap de schéma (ROLE) est signalé identiquement aux DEUX passages');
    assert.deepEqual(second.entries, first.entries, 'aucune dérive entre le 1er et le 2e passage');

    const third = applyUsageExamples(second.entries, detected);
    assert.deepEqual(third.entries, first.entries, 'stable au 3e passage aussi (idempotence, pas juste un coup de chance au 2e)');
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

// --- bloc 2 : intégration sur le VRAI dépôt ------------------------------------------------------

test('intégration réelle : détecte les 2 imports connus (kb_tactics, shmup_slice -> sys-damage-floor/sys-reachability)', () => {
  const detected = detectKnowledgeBaseImports();
  const expected = [
    { importer: 'games/kb_tactics/game.mjs', kbPath: 'knowledge_base/systems/combat/damage_floor.mjs' },
    { importer: 'games/kb_tactics/game.mjs', kbPath: 'knowledge_base/systems/procgen/reachability.mjs' },
    { importer: 'games/kb_tactics/level.mjs', kbPath: 'knowledge_base/systems/procgen/reachability.mjs' },
    { importer: 'games/shmup_slice/logic/collisions.mjs', kbPath: 'knowledge_base/systems/combat/damage_floor.mjs' }
  ];
  for (const e of expected) {
    assert.ok(
      detected.some(d => d.importer === e.importer && d.kbPath === e.kbPath),
      `import connu manquant à la détection : ${e.importer} -> ${e.kbPath}`
    );
  }
});

test('intégration réelle : catalog.json a bien REÇU les usage_examples de sys-damage-floor et sys-reachability (schéma débloqué, arbitrage Pierre)', () => {
  const raw = readFileSync(REAL_CATALOG, 'utf-8');
  const catalog = JSON.parse(raw);

  const damageFloor = catalog.entries.find(e => e.brick_id === 'sys-damage-floor');
  const reachability = catalog.entries.find(e => e.brick_id === 'sys-reachability');
  assert.ok(damageFloor, 'sys-damage-floor existe dans catalog.json');
  assert.ok(reachability, 'sys-reachability existe dans catalog.json');

  assert.ok(Array.isArray(damageFloor.usage_examples) && damageFloor.usage_examples.length > 0,
    'sys-damage-floor.usage_examples non vide');
  assert.ok(damageFloor.usage_examples.includes('games/kb_tactics/game.mjs'));
  assert.ok(damageFloor.usage_examples.includes('games/shmup_slice/logic/collisions.mjs'));

  assert.ok(Array.isArray(reachability.usage_examples) && reachability.usage_examples.length > 0,
    'sys-reachability.usage_examples non vide');
  assert.ok(reachability.usage_examples.includes('games/kb_tactics/game.mjs'));
  assert.ok(reachability.usage_examples.includes('games/kb_tactics/level.mjs'));
});

test('intégration réelle : ré-exécuter le script réel est désormais idempotent (catalog.json déjà rempli) et kb-validate reste vert', () => {
  const before = readFileSync(REAL_CATALOG, 'utf-8');

  execFileSync('node', [SCRIPT], { cwd: REPO_ROOT, encoding: 'utf-8' });

  const after = readFileSync(REAL_CATALOG, 'utf-8');
  assert.equal(after, before, 'catalog.json byte-identique après ré-exécution (idempotence confirmée post-remplissage)');

  const kbValidateOut = execFileSync('node', [KB_VALIDATE], { cwd: REPO_ROOT, encoding: 'utf-8' });
  assert.match(kbValidateOut, /VERDICT CATALOGUE: PASS/, 'kb-validate reste vert après exécution du script R8');
});

test('main() préserve le format JSON existant à l\'octet près quand rien ne change (indentation 1 espace + \\n final)', () => {
  assert.ok(existsSync(REAL_CATALOG));
  const raw = readFileSync(REAL_CATALOG, 'utf-8');
  const obj = JSON.parse(raw);
  const reserialized = JSON.stringify(obj, null, 1) + '\n';
  assert.equal(reserialized, raw, 'round-trip JSON.stringify(obj, null, 1) + "\\n" == fichier réel (convention de formatage confirmée)');
});

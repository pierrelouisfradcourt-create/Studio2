// Tests de agent_context_map.mjs — node --test. Fixtures éphémères, aucune dépendance au repo réel.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import {
  parseContractFields,
  parseRoleNames,
  listContractFiles,
  buildAgentContextMap,
  generateContextMapTable,
  validateAgentContext,
} from './agent_context_map.mjs';

function tmpDir() {
  return mkdtempSync(join(tmpdir(), 'ctxmap-'));
}
function writeContract(dir, name, body) {
  mkdirSync(dir, { recursive: true });
  writeFileSync(join(dir, name), body, 'utf-8');
}

// Un contrat complet et valide (tous les champs Critique remplis, capability_role résolvable).
function fullContract(cap = 'builder') {
  return [
    'role: >-',
    '  Rôle de test, posture imposée.',
    `capability_role: ${cap}`,
    'objectif: >-',
    '  Produire quelque chose de testable.',
    'mandatory_read:',
    '  - forge/contracts/SCHEMA.md',
    '  - "un second fichier obligatoire"',
    'permissions: >-',
    '  read: repo. write: rien.',
    'gardeFou: >-',
    '  Ne déborde jamais son périmètre.',
    'output_contract: >-',
    '  un_artefact.md avec {a, b}.',
    'skill: aucun',
    '',
  ].join('\n');
}

const ROLES_YAML = [
  'version: "1.0"',
  'models:',
  '  - id: anthropic/claude-x',
  '    roles:',
  '      - builder             # commentaire de fin',
  '      - architect',
  '  - id: lmstudio/qwen',
  '    roles:',
  '      - redteam_reviewer',
  '',
].join('\n');

test('parseContractFields : scalaire inline, bloc >- et liste', () => {
  const f = parseContractFields(fullContract('builder'));
  assert.equal(f.capability_role, 'builder');
  assert.equal(f.role, 'Rôle de test, posture imposée.');
  assert.deepEqual(f.mandatory_read, ['forge/contracts/SCHEMA.md', 'un second fichier obligatoire']);
  assert.equal(f.output_contract, 'un_artefact.md avec {a, b}.');
  assert.equal(f.skill, 'aucun');
});

test('parseRoleNames : collecte tous les rôles, ignore commentaires de fin de ligne', () => {
  const dir = tmpDir();
  const p = join(dir, 'roles.yaml');
  writeFileSync(p, ROLES_YAML, 'utf-8');
  const roles = parseRoleNames(p);
  assert.ok(roles.has('builder'));
  assert.ok(roles.has('architect'));
  assert.ok(roles.has('redteam_reviewer'));
  assert.equal(roles.has('claude-x'), false); // les `- id:` ne sont pas des rôles
});

test('listContractFiles : exclut roles.yaml et les .md', () => {
  const dir = tmpDir();
  writeContract(dir, 's0-contrat.yaml', fullContract());
  writeContract(dir, 's1-prisme.yaml', fullContract('architect'));
  writeFileSync(join(dir, 'roles.yaml'), ROLES_YAML, 'utf-8');
  writeFileSync(join(dir, 'SCHEMA.md'), '# schema', 'utf-8');
  const files = listContractFiles(dir);
  assert.deepEqual(files, ['s0-contrat.yaml', 's1-prisme.yaml']);
});

test('buildAgentContextMap : une ligne par contrat, triée, champs projetés', () => {
  const dir = tmpDir();
  writeContract(dir, 's1-prisme.yaml', fullContract('architect'));
  writeContract(dir, 's0-contrat.yaml', fullContract('builder'));
  writeFileSync(join(dir, 'roles.yaml'), ROLES_YAML, 'utf-8');
  const rows = buildAgentContextMap(dir);
  assert.equal(rows.length, 2);
  assert.equal(rows[0].etape, 's0-contrat'); // tri déterministe
  assert.equal(rows[1].etape, 's1-prisme');
  assert.equal(rows[0].capability_role, 'builder');
  assert.match(rows[0].lit, /SCHEMA\.md/);
  assert.match(rows[0].ecrit, /un_artefact\.md/);
});

test('generateContextMapTable : markdown avec en-tête, note auto-généré, lignes triées', () => {
  const dir = tmpDir();
  writeContract(dir, 's1-prisme.yaml', fullContract('architect'));
  writeContract(dir, 's0-contrat.yaml', fullContract('builder'));
  writeFileSync(join(dir, 'roles.yaml'), ROLES_YAML, 'utf-8');
  const md = generateContextMapTable(dir);
  assert.match(md, /AUTO-GÉNÉRÉ/);
  assert.match(md, /capability_role/);
  assert.match(md, /\| `s0-contrat` \| builder \|/);
  // ordre déterministe : s0 avant s1
  assert.ok(md.indexOf('`s0-contrat`') < md.indexOf('`s1-prisme`'));
});

test('validateAgentContext : capability_role non résolvable détecté', () => {
  const dir = tmpDir();
  writeContract(dir, 's9-build.yaml', fullContract('inconnu_xyz')); // absent de roles.yaml
  const rolesPath = join(dir, 'roles.yaml');
  writeFileSync(rolesPath, ROLES_YAML, 'utf-8');
  const findings = validateAgentContext(dir, rolesPath);
  const unresolved = findings.filter((f) => f.type === 'capability_role_unresolved');
  assert.equal(unresolved.length, 1);
  assert.equal(unresolved[0].capability_role, 'inconnu_xyz');
});

test('validateAgentContext : champ Critique manquant détecté', () => {
  const dir = tmpDir();
  // Contrat SANS output_contract (champ Critique).
  const body = [
    'role: >-',
    '  Un rôle.',
    'capability_role: builder',
    'objectif: >-',
    '  Un objectif.',
    'mandatory_read:',
    '  - un_fichier',
    'permissions: >-',
    '  read: repo.',
    'gardeFou: >-',
    '  garde.',
    '', // pas d'output_contract
  ].join('\n');
  writeContract(dir, 's9-build.yaml', body);
  const rolesPath = join(dir, 'roles.yaml');
  writeFileSync(rolesPath, ROLES_YAML, 'utf-8');
  const findings = validateAgentContext(dir, rolesPath);
  const missing = findings.filter((f) => f.type === 'critical_field_missing' && f.field === 'output_contract');
  assert.equal(missing.length, 1);
});

test('validateAgentContext : champ Critique déclaré `aucun` = manquant (règle des 3 états)', () => {
  const dir = tmpDir();
  const body = fullContract('builder').replace('capability_role: builder', 'capability_role: aucun');
  writeContract(dir, 's0-contrat.yaml', body);
  const rolesPath = join(dir, 'roles.yaml');
  writeFileSync(rolesPath, ROLES_YAML, 'utf-8');
  const findings = validateAgentContext(dir, rolesPath);
  const missing = findings.filter((f) => f.type === 'critical_field_missing' && f.field === 'capability_role');
  assert.equal(missing.length, 1);
});

test('validateAgentContext : contrat complet et rôle résolvable => aucun finding', () => {
  const dir = tmpDir();
  writeContract(dir, 's0-contrat.yaml', fullContract('builder'));
  const rolesPath = join(dir, 'roles.yaml');
  writeFileSync(rolesPath, ROLES_YAML, 'utf-8');
  const findings = validateAgentContext(dir, rolesPath);
  assert.equal(findings.length, 0);
});

test('déterminisme : deux générations identiques (aucun horodatage)', () => {
  const dir = tmpDir();
  writeContract(dir, 's0-contrat.yaml', fullContract('builder'));
  writeContract(dir, 's1-prisme.yaml', fullContract('architect'));
  writeFileSync(join(dir, 'roles.yaml'), ROLES_YAML, 'utf-8');
  const a = generateContextMapTable(dir);
  const b = generateContextMapTable(dir);
  assert.equal(a, b);
});

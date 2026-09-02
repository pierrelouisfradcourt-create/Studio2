// Tests de master_index.mjs — node --test. Fixtures ephemeres, aucune dependance au repo reel.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import {
  cleanCell,
  extractSourcePath,
  resolveCheckPath,
  parseAtlasMemoryTable,
  buildMasterIndex,
  generateMasterIndexTable,
} from './master_index.mjs';

function tmpRepo() {
  return mkdtempSync(join(tmpdir(), 'masterindex-'));
}
function touch(root, rel) {
  const p = join(root, rel);
  mkdirSync(join(p, '..'), { recursive: true });
  writeFileSync(p, '{}\n');
  return p;
}
function writeAtlas(root, text) {
  const p = join(root, 'docs/forge/STUDIO_AGENT_ATLAS.md');
  mkdirSync(join(p, '..'), { recursive: true });
  writeFileSync(p, text, 'utf-8');
}

// Mini-table §3 fidele au format reel (en-tete + separation + 3 lignes).
function miniAtlas(rows) {
  return [
    '# ATLAS (fixture)',
    '',
    '## 3. PROPRIÉTÉ MÉMOIRE — qui crée quoi',
    '',
    '| Mémoire / fichier | Qui écrit | Nature | Règle |',
    '|---|---|---|---|',
    ...rows,
    '',
    '**Invariant** : fin de table.',
    '',
  ].join('\n');
}

test('cleanCell : retire gras + backticks + normalise espaces', () => {
  assert.equal(cleanCell('  **mécanisme auto-mémoire** (Claude Code) '), 'mécanisme auto-mémoire (Claude Code)');
  assert.equal(cleanCell('via `kaizen_loop.py` ; Forge'), 'via kaizen_loop.py ; Forge');
});

test('extractSourcePath : premier token backtick', () => {
  assert.equal(extractSourcePath('`memory/` (+ `MEMORY.md`)'), 'memory/');
  assert.equal(extractSourcePath('`EVIDENCE/chains/IMPROVEMENT_LEDGER.yaml`'), 'EVIDENCE/chains/IMPROVEMENT_LEDGER.yaml');
  assert.equal(extractSourcePath('pas de backtick'), 'pas de backtick');
});

test('resolveCheckPath : reduit globs/placeholders au prefixe litteral', () => {
  assert.equal(resolveCheckPath('memory/'), 'memory');
  assert.equal(resolveCheckPath('studio_brain/00_CURRENT_CONTEXT.md'), 'studio_brain/00_CURRENT_CONTEXT.md');
  assert.equal(resolveCheckPath('studio_brain/{doctrine,decisions,...}'), 'studio_brain');
  assert.equal(resolveCheckPath('llm-lego/knowledge/<IMP>.json'), 'llm-lego/knowledge');
  assert.equal(resolveCheckPath('EVIDENCE/runs/<projet>/{state.json,verdict.json,artifacts/}'), 'EVIDENCE/runs');
  assert.equal(resolveCheckPath('EVIDENCE/bundles/*.log,*.jsonl'), 'EVIDENCE/bundles');
});

test('parseAtlasMemoryTable : lit les 4 colonnes de la table §3', () => {
  const atlas = miniAtlas([
    '| `knowledge_base/catalog.json` | agents design (propose) | index bibliothèque | `validated` = preuve |',
    '| `llm-lego/knowledge/<IMP>.json` | **world-scan** (s2) | knowledge packet web | gitignored, advisory-only |',
  ]);
  const rows = parseAtlasMemoryTable(atlas);
  assert.equal(rows.length, 2);
  assert.equal(rows[0].source, 'knowledge_base/catalog.json');
  assert.equal(rows[0].ecrit_par, 'agents design (propose)');
  assert.equal(rows[0].nature, 'index bibliothèque');
  assert.equal(rows[1].source, 'llm-lego/knowledge/<IMP>.json');
  assert.equal(rows[1].ecrit_par, 'world-scan (s2)'); // gras retire
});

test('parseAtlasMemoryTable : aucune table -> tableau vide (pas de crash)', () => {
  assert.deepEqual(parseAtlasMemoryTable('# rien ici\n\ndu texte.'), []);
});

test('buildMasterIndex : source presente -> existe=true, absente -> existe=false', () => {
  const root = tmpRepo();
  touch(root, 'knowledge_base/catalog.json');
  // llm-lego/knowledge/ NON cree -> absent
  writeAtlas(root, miniAtlas([
    '| `knowledge_base/catalog.json` | agents design | index | règle A |',
    '| `llm-lego/knowledge/<IMP>.json` | world-scan | packet | règle B |',
  ]));
  const entries = buildMasterIndex(root);
  assert.equal(entries.length, 2);
  const cat = entries.find((e) => e.source === 'knowledge_base/catalog.json');
  const kn = entries.find((e) => e.source === 'llm-lego/knowledge/<IMP>.json');
  assert.equal(cat.existe, true);
  assert.equal(kn.existe, false);
  assert.equal(kn.check_path, 'llm-lego/knowledge'); // prefixe litteral teste
});

test('buildMasterIndex : tri deterministe par source', () => {
  const root = tmpRepo();
  writeAtlas(root, miniAtlas([
    '| `zzz/last.json` | x | y | z |',
    '| `aaa/first.json` | x | y | z |',
  ]));
  const entries = buildMasterIndex(root);
  assert.equal(entries[0].source, 'aaa/first.json');
  assert.equal(entries[1].source, 'zzz/last.json');
});

test('generateMasterIndexTable : note AUTO-GÉNÉRÉ + colonne Existe + signal derive', () => {
  const root = tmpRepo();
  touch(root, 'knowledge_base/catalog.json'); // present
  writeAtlas(root, miniAtlas([
    '| `knowledge_base/catalog.json` | agents design | index | règle A |',
    '| `memory/` (+ `MEMORY.md`) | auto-mémoire | faits durables | règle B |', // absent
  ]));
  const md = generateMasterIndexTable(root);
  assert.match(md, /AUTO-GÉNÉRÉ/);
  assert.match(md, /Source de vérité \| Qui écrit \| Nature \| Existe \| Règle/);
  assert.match(md, /knowledge_base\/catalog\.json.*✅ présent/);
  assert.match(md, /memory\/.*⬜ absent/);
  assert.match(md, /absentes du disque.*: 1/); // signal de derive
});

test('generateMasterIndexTable : deux generations identiques (deterministe, sans horodatage)', () => {
  const root = tmpRepo();
  touch(root, 'knowledge_base/catalog.json');
  writeAtlas(root, miniAtlas([
    '| `knowledge_base/catalog.json` | agents design | index | règle A |',
  ]));
  const md1 = generateMasterIndexTable(root);
  const md2 = generateMasterIndexTable(root);
  assert.equal(md1, md2);
  assert.doesNotMatch(md1, /\d{4}-\d{2}-\d{2}/); // aucun horodatage
});

test('detection de source absente -> au moins une entree existe=false (exit-signal du main)', () => {
  const root = tmpRepo();
  // aucune source touchee sur disque -> toutes absentes
  writeAtlas(root, miniAtlas([
    '| `EVIDENCE/runs/<projet>/{state.json}` | driver | état | règle |',
  ]));
  const entries = buildMasterIndex(root);
  const missing = entries.filter((e) => !e.existe);
  assert.equal(missing.length, 1); // main() exit 1 sur ce cas
});

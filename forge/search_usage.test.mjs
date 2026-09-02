// Tests de SEARCH_USAGE_CONTRACT_V1 (maillons 3 a 5).
// node --test forge/search_usage.test.mjs
//
// Aucun reseau, aucun LLM, aucun embedding : la consommation est une INTERSECTION
// EXACTE, jointe par le catalogue. Un test verifie l'absence de similarite sur la source.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, writeFile, mkdir } from 'node:fs/promises';
import { readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  PROOF_STATES, identitesProposees, mesurerConsommation, referencesConsommees,
  reuseRatioCable, tableCheminVersBrique, journaliserConsommation,
} from './search_usage.mjs';

async function journal(lignes) {
  const d = await mkdtemp(join(tmpdir(), 'usage-'));
  const p = join(d, 'search_log.jsonl');
  await writeFile(p, lignes.map((x) => JSON.stringify(x)).join('\n'), 'utf-8');
  return p;
}

// `main.mjs`, `run-oracle.mjs`, `e2e.mjs`… sont des fichiers de HARNESS pour
// reuse_ratio (HARNESS_FILES) : ils sont exclus des fichiers de LOGIQUE. Les fixtures
// utilisent donc `logique.mjs` — sinon la mesure rend « aucun fichier de logique »,
// ce que le premier jet de ces tests a decouvert.
async function catalogue(entries) {
  const d = await mkdtemp(join(tmpdir(), 'cat-'));
  const p = join(d, 'catalog.json');
  await writeFile(p, JSON.stringify({ catalog_version: 1, entries }), 'utf-8');
  return p;
}

// --- 1 & 2 : caller + matched_ids lus depuis le journal ----------------------------

test('identitesProposees lit caller et matched_ids, et compte par appelant', async () => {
  const p = await journal([
    { kind: 'search', caller: 'preflight', matched_ids: ['a', 'b'], ts: '2026-08-01T00:00:00Z' },
    { kind: 'search', caller: 's9-build', matched_ids: ['b', 'c'], ts: '2026-08-02T00:00:00Z' },
    { kind: 'consumption', consumed_refs: ['zzz'], ts: '2026-08-02T00:00:00Z' },
  ]);
  const r = identitesProposees({ journal: p });
  assert.deepEqual(r.matched_ids, ['a', 'b', 'c']);
  assert.equal(r.searches, 2, 'un enregistrement `consumption` n est pas une recherche');
  assert.deepEqual(r.par_caller, { preflight: 1, 's9-build': 1 });
});

test('une entree LEGACY sans caller ni matched_ids reste lisible', async () => {
  // les 29 entrees d avant le 2026-08-04 : {query, matchCount, ts}
  const p = await journal([{ query: 'x', matchCount: 3, ts: '2026-07-20T00:00:00Z' }]);
  const r = identitesProposees({ journal: p });
  assert.equal(r.searches, 1);
  assert.deepEqual(r.matched_ids, [], 'aucune identite proposee : le champ n existait pas');
  assert.deepEqual(r.par_caller, { undeclared: 1 }, 'non declare est une VALEUR, pas un trou');
});

test('filtrage par caller et par date — declare, jamais devine', async () => {
  const p = await journal([
    { kind: 'search', caller: 'preflight', matched_ids: ['a'], ts: '2026-08-01T00:00:00Z' },
    { kind: 'search', caller: 's9-build', matched_ids: ['b'], ts: '2026-08-03T00:00:00Z' },
  ]);
  assert.deepEqual(identitesProposees({ journal: p, caller: 's9-build' }).matched_ids, ['b']);
  assert.deepEqual(identitesProposees({ journal: p, since: '2026-08-02T00:00:00Z' }).matched_ids, ['b']);
  assert.equal(identitesProposees({ journal: '/nexiste/pas.jsonl' }).searches, 0);
});

// --- jointure EXACTE, jamais une ressemblance -------------------------------------

test('la jointure passe par le CATALOGUE, pas par le nom de fichier', async () => {
  const cat = await catalogue([
    { brick_id: 'sys-reachability', path: 'knowledge_base/systems/procgen/reachability.mjs' },
  ]);
  const t = tableCheminVersBrique(cat);
  assert.equal(t.get('knowledge_base/systems/procgen/reachability.mjs'), 'sys-reachability');
  // `sys-reachability` et `reachability.mjs` ne se ressemblent qu a l oeil : c est le
  // catalogue qui declare qu ils designent la meme chose.
  assert.equal(t.size, 1);
  assert.equal(tableCheminVersBrique('/nexiste/pas.json').size, 0);
});

test('un module reutilise HORS catalogue est signale, jamais rapproche', async () => {
  const d = await mkdtemp(join(tmpdir(), 'jeu-'));
  await writeFile(join(d, 'logique.mjs'),
    "import { a } from '../../knowledge_base/systems/procgen/reachability.mjs';\n"
    + "import { b } from '../../knowledge_base/systems/inconnu/mystere.mjs';\n", 'utf-8');
  const cat = await catalogue([
    { brick_id: 'sys-reachability', path: 'knowledge_base/systems/procgen/reachability.mjs' },
  ]);
  const r = referencesConsommees(d, cat);
  assert.deepEqual(r.consumed, ['sys-reachability']);
  assert.ok(r.reused_unmapped.some((x) => x.includes('mystere')),
    'reutilise mais jamais propose : un fait, pas un defaut');
});

// --- 4 : les TROIS etats de preuve, jamais un quatrieme ---------------------------

test('PROOF_STATES contient exactement trois etats, et il est gele', () => {
  assert.deepEqual([...PROOF_STATES], ['MEASURED', 'NOT_WIRED', 'NOT_MEASURED']);
  assert.ok(Object.isFrozen(PROOF_STATES));
});

test('NOT_MEASURED : dossier absent', async () => {
  const e = mesurerConsommation('GAMES/nexiste_pas', { journal: await journal([]) });
  assert.equal(e.proof_of_consumption.status, 'NOT_MEASURED');
  assert.match(e.proof_of_consumption.raison, /dossier absent/);
  assert.equal(e.proof_of_consumption.invoked_by, null);
});

test('NOT_WIRED : le mecanisme existe, le projet ne l invoque pas', async () => {
  const d = await mkdtemp(join(tmpdir(), 'jeu-'));
  await writeFile(join(d, 'logique.mjs'),
    "import { a } from '../../knowledge_base/systems/procgen/reachability.mjs';\n", 'utf-8');
  await writeFile(join(d, 'run-oracle.mjs'), '// aucun appel ici\nconsole.log(1);\n', 'utf-8');
  const e = mesurerConsommation(d, { journal: await journal([]), racine: '/' });
  assert.equal(e.proof_of_consumption.status, 'NOT_WIRED');
  assert.match(e.proof_of_consumption.raison, /n'invoque pas reuse_ratio/);
});

test('NOT_WIRED aussi quand run-oracle.mjs est ABSENT', async () => {
  const d = await mkdtemp(join(tmpdir(), 'jeu-'));
  await writeFile(join(d, 'logique.mjs'),
    "import { a } from '../../knowledge_base/systems/procgen/reachability.mjs';\n", 'utf-8');
  assert.equal(reuseRatioCable(d).wired, false);
  assert.match(reuseRatioCable(d).raison, /absent/);
});

test('MEASURED : le projet invoque reellement reuse_ratio', async () => {
  const d = await mkdtemp(join(tmpdir(), 'jeu-'));
  await writeFile(join(d, 'logique.mjs'),
    "import { a } from '../../knowledge_base/systems/procgen/reachability.mjs';\n", 'utf-8');
  await writeFile(join(d, 'run-oracle.mjs'),
    "import { measureReuseRatio } from '../../forge/reuse_ratio.mjs';\n", 'utf-8');
  assert.equal(reuseRatioCable(d).wired, true);
  const cat = await catalogue([
    { brick_id: 'sys-reachability', path: 'knowledge_base/systems/procgen/reachability.mjs' },
  ]);
  const e = mesurerConsommation(d, { journal: await journal([]), racine: '/', catalogue: cat });
  assert.equal(e.proof_of_consumption.status, 'MEASURED');
  assert.equal(e.proof_of_consumption.method, 'reuse_ratio');
  assert.ok(e.proof_of_consumption.invoked_by.endsWith('run-oracle.mjs'));
});

test('un appel en COMMENTAIRE n est pas un appel', async () => {
  const d = await mkdtemp(join(tmpdir(), 'jeu-'));
  await writeFile(join(d, 'run-oracle.mjs'),
    "// import { x } from '../../forge/reuse_ratio.mjs';\nconsole.log(1);\n", 'utf-8');
  assert.equal(reuseRatioCable(d).wired, false);
});

// --- 3 : consumed_refs = INTERSECTION EXACTE --------------------------------------

test('consumed_refs = proposees ∩ reutilisees, rien d autre', async () => {
  const d = await mkdtemp(join(tmpdir(), 'jeu-'));
  await writeFile(join(d, 'logique.mjs'),
    "import { a } from '../../knowledge_base/systems/procgen/reachability.mjs';\n"
    + "import { b } from '../../knowledge_base/systems/combat/damage_floor.mjs';\n", 'utf-8');
  await writeFile(join(d, 'run-oracle.mjs'),
    "import { measureReuseRatio } from '../../forge/reuse_ratio.mjs';\n", 'utf-8');
  const cat = await catalogue([
    { brick_id: 'sys-reachability', path: 'knowledge_base/systems/procgen/reachability.mjs' },
    { brick_id: 'sys-damage-floor', path: 'knowledge_base/systems/combat/damage_floor.mjs' },
  ]);
  // une seule des deux a ete PROPOSEE par une recherche
  const p = await journal([
    { kind: 'search', caller: 'cli', matched_ids: ['sys-reachability', 'sys-jamais-utilisee'],
      ts: '2026-08-04T00:00:00Z' },
  ]);
  const e = mesurerConsommation(d, { journal: p, racine: '/', catalogue: cat, caller: 'cli' });
  assert.deepEqual(e.consumed_refs, ['sys-reachability'],
    'proposee ET reutilisee : la seule qui compte');
  assert.ok(e.matched_ids.includes('sys-jamais-utilisee'), 'proposee mais pas reutilisee');
  assert.equal(e.consumed_refs.length, 1);
  assert.equal(e.proof_of_consumption.status, 'MEASURED');
});

test('reutilise SANS avoir ete propose -> hors consumed_refs', async () => {
  const d = await mkdtemp(join(tmpdir(), 'jeu-'));
  await writeFile(join(d, 'logique.mjs'),
    "import { a } from '../../knowledge_base/systems/procgen/reachability.mjs';\n", 'utf-8');
  const cat = await catalogue([
    { brick_id: 'sys-reachability', path: 'knowledge_base/systems/procgen/reachability.mjs' },
  ]);
  const e = mesurerConsommation(d, { journal: await journal([]), racine: '/', catalogue: cat });
  assert.deepEqual(e.consumed_refs, [],
    'la brique est reutilisee, mais aucune recherche ne l a proposee : l intersection est vide');
  assert.equal(e.reused_modules.length, 1);
});

// --- invariants -------------------------------------------------------------------

test('AUCUNE similarite, AUCUN score, AUCUN embedding : verifie sur la source', () => {
  const src = readFileSync(fileURLToPath(new URL('./search_usage.mjs', import.meta.url)), 'utf-8');
  const code = src.split('\n').filter((l) => !l.trim().startsWith('//') && !l.trim().startsWith('*')).join('\n');
  for (const i of ['jaccard', 'similar', 'embedding', 'vector', 'cosine', 'score',
    'levenshtein', 'fuzzy', 'fetch(']) {
    assert.ok(!code.toLowerCase().includes(i), `interdit dans cette couche : « ${i} »`);
  }
});

test('DETERMINISME : deux mesures identiques rendent le meme resultat (hors ts)', async () => {
  const d = await mkdtemp(join(tmpdir(), 'jeu-'));
  await writeFile(join(d, 'logique.mjs'), 'export const a = 1;\n', 'utf-8');
  const p = await journal([]);
  const sansTs = (e) => { const { ts, ...reste } = e; return reste; };
  assert.deepEqual(sansTs(mesurerConsommation(d, { journal: p, racine: '/' })),
    sansTs(mesurerConsommation(d, { journal: p, racine: '/' })));
});

test('journaliser n echoue jamais bruyamment', async () => {
  assert.equal(journaliserConsommation({ kind: 'consumption' },
    join(await mkdtemp(join(tmpdir(), 'j-')), 'sous', 'x.jsonl')), true);
});

// --- le depot reel ----------------------------------------------------------------

test('DEPOT REEL : kb_tactics est MEASURED et consomme une brique proposee', async () => {
  const e = mesurerConsommation('GAMES/kb_tactics');
  assert.equal(e.proof_of_consumption.status, 'MEASURED');
  assert.equal(e.reuse_ratio > 0, true);
  assert.ok(e.reused_modules.length >= 2);
  // la boucle complete : sys-reachability a ete PROPOSEE par une recherche declaree
  // (caller=cli) ET est REUTILISEE par le jeu.
  assert.ok(e.consumed_refs.includes('sys-reachability'),
    `consumed_refs=${JSON.stringify(e.consumed_refs)}`);
});

test('DEPOT REEL : un jeu sans run-oracle reste NOT_WIRED — jamais MEASURED par defaut', async () => {
  const e = mesurerConsommation('GAMES/pong');
  assert.equal(e.proof_of_consumption.status, 'NOT_WIRED');
  assert.match(e.proof_of_consumption.raison, /run-oracle\.mjs absent/);
});

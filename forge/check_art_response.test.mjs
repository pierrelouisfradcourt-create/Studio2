// Tests de l'oracle du contrat de retour GM -> Artiste (Lot B, T3, 2026-08-23).
// node --test forge/check_art_response.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  checkArtResponseDoc, checkArtResponse, artistRequirements,
} from './check_art_response.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(__dirname, '..');

function gmAvec(requirements) {
  return { game_master: { artist_requirements: requirements } };
}

// --- artistRequirements ----------------------------------------------------

test('artistRequirements: gm null -> []', () => {
  assert.deepEqual(artistRequirements(null), []);
});

test('artistRequirements: sans bloc game_master -> []', () => {
  assert.deepEqual(artistRequirements({ genre: 'clicker' }), []);
});

test('artistRequirements: filtre les entrees sans id, defaut states_to_show []', () => {
  const gm = gmAvec([{ id: 'garden_visual', states_to_show: ['LOCKED', 'AVAILABLE'] }, { type: 'ACTOR' }, 'texte']);
  const reqs = artistRequirements(gm);
  assert.deepEqual(reqs, [{ id: 'garden_visual', states_to_show: ['LOCKED', 'AVAILABLE'] }]);
});

// --- checkArtResponseDoc (oracle pur, fileExists injecte) ------------------

test('0 artist_requirements -> OK sans lire le disque, meme doc=null', () => {
  const r = checkArtResponseDoc(null, null, () => { throw new Error('jamais appele'); });
  assert.equal(r.verdict, 'OK');
  assert.deepEqual(r.stats, { requirements: 0, reponses: 0, completes: 0 });
});

test('requirements presentes, doc absent (null) -> FAIL nomme', () => {
  const gm = gmAvec([{ id: 'garden_visual', states_to_show: ['LOCKED'] }]);
  const r = checkArtResponseDoc(null, gm, () => true);
  assert.equal(r.verdict, 'FAIL');
  assert.equal(r.problems.length, 1);
  assert.match(r.problems[0], /absent/);
  assert.match(r.problems[0], /1 artist_requirements/);
  assert.equal(r.stats.requirements, 1);
});

test('doc de forme invalide (pas un objet) -> FAIL', () => {
  const gm = gmAvec([{ id: 'x', states_to_show: [] }]);
  assert.equal(checkArtResponseDoc('texte libre', gm, () => true).verdict, 'FAIL');
  assert.equal(checkArtResponseDoc([], gm, () => true).verdict, 'FAIL');
});

test('schema_version != 1 -> finding nomme', () => {
  const gm = gmAvec([{ id: 'x', states_to_show: [] }]);
  const doc = { schema_version: 2, responses: [{ requirement_id: 'x', asset_files: ['a.svg'], node_group: 'g', states_represented: [] }] };
  const r = checkArtResponseDoc(doc, gm, () => true);
  assert.equal(r.verdict, 'FAIL');
  assert.ok(r.problems.some((p) => /schema_version/.test(p)));
});

test('responses absent/non-tableau -> FAIL nomme', () => {
  const gm = gmAvec([{ id: 'x', states_to_show: [] }]);
  const r = checkArtResponseDoc({ schema_version: 1 }, gm, () => true);
  assert.equal(r.verdict, 'FAIL');
  assert.ok(r.problems.some((p) => /responses/.test(p)));
});

test('1 requirement, 1 reponse complete et conforme -> OK, completes=1', () => {
  const gm = gmAvec([{ id: 'garden_visual', states_to_show: ['LOCKED', 'AVAILABLE'] }]);
  const doc = {
    schema_version: 1,
    responses: [{
      requirement_id: 'garden_visual',
      asset_files: ['04_ASSETS/sprites/garden_locked.svg', '04_ASSETS/sprites/garden_available.svg'],
      node_group: 'garden',
      states_represented: ['LOCKED', 'AVAILABLE'],
      affordance_visual: 'cadenas visible tant que LOCKED',
    }],
  };
  const r = checkArtResponseDoc(doc, gm, () => true);
  assert.equal(r.verdict, 'OK', JSON.stringify(r.problems));
  assert.deepEqual(r.stats, { requirements: 1, reponses: 1, completes: 1 });
});

test('requirement sans aucune reponse -> requirement_sans_reponse', () => {
  const gm = gmAvec([{ id: 'garden_visual', states_to_show: [] }, { id: 'shop_visual', states_to_show: [] }]);
  const doc = {
    schema_version: 1,
    responses: [{ requirement_id: 'garden_visual', asset_files: ['a.svg'], node_group: 'g', states_represented: [] }],
  };
  const r = checkArtResponseDoc(doc, gm, () => true);
  assert.equal(r.verdict, 'FAIL');
  assert.ok(r.problems.some((p) => /shop_visual/.test(p) && /requirement_sans_reponse/.test(p)));
});

test('reponse orpheline (requirement_id inconnu) -> finding, jamais couplee', () => {
  const gm = gmAvec([{ id: 'garden_visual', states_to_show: [] }]);
  const doc = {
    schema_version: 1,
    responses: [
      { requirement_id: 'garden_visual', asset_files: ['a.svg'], node_group: 'g', states_represented: [] },
      { requirement_id: 'fantome', asset_files: ['b.svg'], node_group: 'g2', states_represented: [] },
    ],
  };
  const r = checkArtResponseDoc(doc, gm, () => true);
  assert.equal(r.verdict, 'FAIL');
  assert.ok(r.problems.some((p) => /fantome/.test(p) && /orpheline/.test(p)));
});

test('deux reponses pour le meme requirement -> la seconde est refusee', () => {
  const gm = gmAvec([{ id: 'garden_visual', states_to_show: [] }]);
  const doc = {
    schema_version: 1,
    responses: [
      { requirement_id: 'garden_visual', asset_files: ['a.svg'], node_group: 'g', states_represented: [] },
      { requirement_id: 'garden_visual', asset_files: ['b.svg'], node_group: 'g2', states_represented: [] },
    ],
  };
  const r = checkArtResponseDoc(doc, gm, () => true);
  assert.equal(r.verdict, 'FAIL');
  assert.ok(r.problems.some((p) => /deja repondu/.test(p)));
});

test('asset_files[] pointe un fichier absent -> finding, fileExists est consulte', () => {
  const gm = gmAvec([{ id: 'garden_visual', states_to_show: [] }]);
  const doc = {
    schema_version: 1,
    responses: [{ requirement_id: 'garden_visual', asset_files: ['manquant.svg'], node_group: 'g', states_represented: [] }],
  };
  const seen = [];
  const r = checkArtResponseDoc(doc, gm, (f) => { seen.push(f); return false; });
  assert.equal(r.verdict, 'FAIL');
  assert.deepEqual(seen, ['manquant.svg']);
  assert.ok(r.problems.some((p) => /manquant\.svg/.test(p) && /n'existe pas/.test(p)));
});

test('node_group vide -> finding', () => {
  const gm = gmAvec([{ id: 'x', states_to_show: [] }]);
  const doc = { schema_version: 1, responses: [{ requirement_id: 'x', asset_files: ['a.svg'], node_group: '', states_represented: [] }] };
  const r = checkArtResponseDoc(doc, gm, () => true);
  assert.equal(r.verdict, 'FAIL');
  assert.ok(r.problems.some((p) => /node_group/.test(p)));
});

test('states_represented ne couvre pas states_to_show -> finding nommant les manquants', () => {
  const gm = gmAvec([{ id: 'x', states_to_show: ['LOCKED', 'AVAILABLE', 'OWNED'] }]);
  const doc = { schema_version: 1, responses: [{ requirement_id: 'x', asset_files: ['a.svg'], node_group: 'g', states_represented: ['LOCKED'] }] };
  const r = checkArtResponseDoc(doc, gm, () => true);
  assert.equal(r.verdict, 'FAIL');
  assert.ok(r.problems.some((p) => /AVAILABLE/.test(p) && /OWNED/.test(p)));
});

test('states_represented sur-couvre states_to_show -> accepte (surplus non refuse)', () => {
  const gm = gmAvec([{ id: 'x', states_to_show: ['LOCKED'] }]);
  const doc = { schema_version: 1, responses: [{ requirement_id: 'x', asset_files: ['a.svg'], node_group: 'g', states_represented: ['LOCKED', 'AVAILABLE'] }] };
  const r = checkArtResponseDoc(doc, gm, () => true);
  assert.equal(r.verdict, 'OK');
});

// --- checkArtResponse (I/O reel, dossier temporaire) ------------------------

function tmpGameDir() {
  const root = mkdtempSync(join(tmpdir(), 'forge-art-response-'));
  mkdirSync(join(root, '04_ASSETS'), { recursive: true });
  return root;
}

test('I/O: gm absent (gmPath=null) -> OK sans lire le disque du jeu', async () => {
  const dir = tmpGameDir();
  const r = await checkArtResponse(dir, null);
  assert.equal(r.verdict, 'OK');
  assert.deepEqual(r.stats, { requirements: 0, reponses: 0, completes: 0 });
});

test('I/O: gm avec artist_requirements, art_response.json absent -> FAIL nomme (baseline build run 9)', async () => {
  const dir = tmpGameDir();
  const gmPath = join(dir, 'gm_worldscan.json');
  writeFileSync(gmPath, JSON.stringify(gmAvec([{ id: 'garden_visual', states_to_show: [] }])), 'utf-8');
  const r = await checkArtResponse(dir, gmPath);
  assert.equal(r.verdict, 'FAIL');
  assert.ok(r.problems.some((p) => /absent/.test(p)));
});

test('I/O: art_response.json present, asset reellement sur disque -> OK', async () => {
  const dir = tmpGameDir();
  mkdirSync(join(dir, '04_ASSETS', 'sprites'), { recursive: true });
  writeFileSync(join(dir, '04_ASSETS', 'sprites', 'garden.svg'), '<svg/>', 'utf-8');
  writeFileSync(join(dir, '04_ASSETS', 'art_response.json'), JSON.stringify({
    schema_version: 1,
    responses: [{
      requirement_id: 'garden_visual', asset_files: ['04_ASSETS/sprites/garden.svg'],
      node_group: 'garden', states_represented: ['LOCKED'], affordance_visual: 'texte',
    }],
  }), 'utf-8');
  const gmPath = join(dir, 'gm_worldscan.json');
  writeFileSync(gmPath, JSON.stringify(gmAvec([{ id: 'garden_visual', states_to_show: ['LOCKED'] }])), 'utf-8');
  const r = await checkArtResponse(dir, gmPath);
  assert.equal(r.verdict, 'OK', JSON.stringify(r.problems));
  assert.equal(r.stats.completes, 1);
});

test('I/O: art_response.json present mais asset absent du disque -> FAIL', async () => {
  const dir = tmpGameDir();
  writeFileSync(join(dir, '04_ASSETS', 'art_response.json'), JSON.stringify({
    schema_version: 1,
    responses: [{
      requirement_id: 'garden_visual', asset_files: ['04_ASSETS/sprites/absent.svg'],
      node_group: 'garden', states_represented: [],
    }],
  }), 'utf-8');
  const gmPath = join(dir, 'gm_worldscan.json');
  writeFileSync(gmPath, JSON.stringify(gmAvec([{ id: 'garden_visual', states_to_show: [] }])), 'utf-8');
  const r = await checkArtResponse(dir, gmPath);
  assert.equal(r.verdict, 'FAIL');
  assert.ok(r.problems.some((p) => /absent\.svg/.test(p)));
});

test('I/O: gm illisible -> FAIL explicite, jamais une exception', async () => {
  const dir = tmpGameDir();
  const r = await checkArtResponse(dir, join(dir, 'inexistant.json'));
  assert.equal(r.verdict, 'FAIL');
});

// --- mesure REELLE run 9 (baseline figee, plan Lot B T3) --------------------

test('baseline run 9 : gm sans game_master -> 0 artist_requirements, OK sans art_response.json', async () => {
  const gmPath = resolve(REPO_ROOT, 'EVIDENCE/runs/kitten_clicker/_run9_20260823a/gm_worldscan.json');
  const gameDir = resolve(REPO_ROOT, 'EVIDENCE/runs/kitten_clicker/_run9_20260823a/game_build9');
  if (!existsSync(gmPath) || !existsSync(gameDir)) return; // fixture absente sur ce poste
  const r = await checkArtResponse(gameDir, gmPath);
  // gm_worldscan.json du run 9 ne porte pas encore de bloc `game_master`
  // (mesure Lot B T3, 2026-08-23) -> 0 artist_requirements, verdict OK.
  assert.equal(r.stats.requirements, 0);
  assert.equal(r.verdict, 'OK');
  assert.ok(!existsSync(join(gameDir, '04_ASSETS', 'art_response.json')), 'confirme : art_response.json absent du build run 9');
});

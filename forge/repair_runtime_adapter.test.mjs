// Tests de l'adaptateur de contrat du repair runtime.
// node --test forge/repair_runtime_adapter.test.mjs
//
// Le modèle est TOUJOURS injecté : aucun test n'appelle LM Studio. Les oracles sont les
// VRAIS oracles du dépôt sur de vrais fichiers temporaires — c'est la seule façon de
// prouver que l'adaptateur encapsule le réparateur réel, et pas une maquette.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, writeFile, readFile, readdir } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  CHAMPS_REQUETE, etapeDepuisArtefact, identifiantsFindings, validerRequete,
  versRepairStep, diffFeuilles, executerReparation,
} from './repair_runtime_adapter.mjs';
import { worldscanReference } from './upstream_fixtures.mjs';

const P0 = 'games[0].retention_answer';
const P1 = 'games[1].retention_answer';
const ID0 = `check_worldscan:${P0}`;
const ID1 = `check_worldscan:${P1}`;

/** Un run_dir avec un worldscan dégradé sur les deux `retention_answer`. */
async function runDegrade() {
  const dir = await mkdtemp(join(tmpdir(), 'adapter-'));
  const ws = worldscanReference();
  ws.games[0].retention_answer = '';
  ws.games[1].retention_answer = '';
  await writeFile(join(dir, 'worldscan.json'), JSON.stringify(ws, null, 1), 'utf-8');
  return { dir, artefact: join(dir, 'worldscan.json'), preuve: join(dir, 'evidence') };
}

/** Modèle injecté : rend une valeur DISTINCTE par chemin (deux valeurs identiques
 *  déclencheraient la couche qualité, ce qui n'est pas l'objet de ces tests). */
const modeleFidele = async (prompt) => {
  const m = prompt.match(/FIELD_TO_REPAIR:\n(.+)/);
  if (!m) return null; // prompt de la couche qualité : on ne répond pas
  const chemin = m[1].trim();
  const valeur = chemin === P0
    ? 'Les paliers rapproches ramenent le joueur chaque soir.'
    : 'La partie suivante demarre avant que la frustration ne retombe.';
  return `\`\`\`json\n{"path": "${chemin}", "value": "${valeur}"}\n\`\`\``;
};

const modeleInterdit = async () => { throw new Error('le modele ne doit pas etre appele'); };

const requete = (o) => ({
  finding_id: ID0,
  root_problem_id: 'REPAIR_NON_CONVERGENCE',
  artifact_ref: o.artefact,
  evidence_ref: o.preuve,
  allowed_fields: [P0],
  forbidden_fields: [],
  ...o.patch,
});

// --- contrat d'entrée ---

test('CHAMPS_REQUETE est exactement le contrat d entree (ni plus, ni moins)', () => {
  assert.deepEqual([...CHAMPS_REQUETE].sort(), [
    'allowed_fields', 'artifact_ref', 'evidence_ref', 'finding_id',
    'forbidden_fields', 'root_problem_id',
  ]);
});

test('validerRequete refuse un champ obligatoire manquant', () => {
  for (const champ of CHAMPS_REQUETE) {
    const req = {
      finding_id: ID0, root_problem_id: 'X', artifact_ref: 'a/worldscan.json',
      evidence_ref: 'e', allowed_fields: [P0], forbidden_fields: [],
    };
    delete req[champ];
    assert.throws(() => validerRequete(req), new RegExp(`manquant.*${champ}`), champ);
  }
});

test('validerRequete refuse un champ HORS contrat (pas de passager clandestin)', () => {
  assert.throws(() => validerRequete({
    finding_id: ID0, root_problem_id: 'X', artifact_ref: 'a/worldscan.json',
    evidence_ref: 'e', allowed_fields: [P0], forbidden_fields: [], model: 'opus',
  }), /hors contrat.*model/);
});

test('validerRequete refuse allowed_fields vide et une collision autorise/interdit', () => {
  const base = {
    finding_id: ID0, root_problem_id: 'X', artifact_ref: 'a/worldscan.json', evidence_ref: 'e',
  };
  assert.throws(() => validerRequete({ ...base, allowed_fields: [], forbidden_fields: [] }),
    /allowed_fields vide/);
  assert.throws(() => validerRequete({ ...base, allowed_fields: [P0], forbidden_fields: [P0] }),
    /à la fois autorisé et interdit/);
});

test('finding_id accepte une chaine ou un tableau non vide', () => {
  const base = {
    root_problem_id: 'X', artifact_ref: 'a/worldscan.json', evidence_ref: 'e',
    allowed_fields: [P0], forbidden_fields: [],
  };
  assert.deepEqual(validerRequete({ ...base, finding_id: ID0 }).finding_ids, [ID0]);
  assert.deepEqual(validerRequete({ ...base, finding_id: [ID0, ID1] }).finding_ids, [ID0, ID1]);
  assert.throws(() => validerRequete({ ...base, finding_id: [] }), /finding_id/);
});

// --- résolution de l'étape ---

test('etapeDepuisArtefact resout les 5 artefacts amont, et rien d autre', () => {
  assert.equal(etapeDepuisArtefact('run/worldscan.json'), 's2-worldscan');
  assert.equal(etapeDepuisArtefact('run/prisme.json'), 's1-prisme');
  assert.equal(etapeDepuisArtefact('run/featuremap.json'), 's3-decompo');
  assert.equal(etapeDepuisArtefact('run/blueprint.json'), 's4-archi-contract');
  assert.equal(etapeDepuisArtefact('run/wiremap.json'), 's5-wiremap-contract');
  assert.equal(etapeDepuisArtefact('run/inconnu.json'), null);
});

test('versRepairStep leve sur un artefact inconnu (jamais deviner l etape)', () => {
  assert.throws(() => versRepairStep({ artifact_ref: 'run/autre.json' }), /aucune étape connue/);
});

test('identifiantsFindings: id stable par chemin, id indexe pour un finding structurel', () => {
  const ids = identifiantsFindings('check_worldscan', [
    `${P0}: absent ou vide`, 'aucun jeu analyse',
  ]);
  assert.equal(ids[0].finding_id, ID0);
  assert.equal(ids[0].chemin, P0);
  assert.equal(ids[1].finding_id, 'check_worldscan:#1');
  assert.equal(ids[1].chemin, null);
});

test('diffFeuilles ne rend que les feuilles modifiees', () => {
  assert.deepEqual(diffFeuilles({ a: 1, b: 2 }, { a: 1, b: 3 }),
    [{ path: 'b', before: 2, after: 3 }]);
  assert.deepEqual(diffFeuilles({ a: 1 }, { a: 1 }), []);
});

// --- exécution sous contrat ---

test('FINDING_INCONNU: un defaut non signale par l oracle n est PAS reparable', async () => {
  const o = await runDegrade();
  const avant = await readFile(o.artefact, 'utf-8');
  const res = await executerReparation(
    requete({ ...o, patch: { finding_id: 'check_worldscan:games[0].inventé' } }),
    { appelerModele: modeleInterdit },
  );
  assert.equal(res.contract_status, 'FINDING_INCONNU');
  assert.deepEqual(res.patch, []);
  assert.deepEqual(res.evidence_created, []);
  assert.equal(await readFile(o.artefact, 'utf-8'), avant, 'artefact intact');
});

test('CONFORME: oracle FAIL -> OK, patch dans le perimetre, preuve materialisee', async () => {
  const o = await runDegrade();
  const res = await executerReparation(
    requete({ ...o, patch: { finding_id: [ID0, ID1], allowed_fields: [P0, P1] } }),
    { appelerModele: modeleFidele },
  );

  assert.equal(res.contract_status, 'CONFORME');
  assert.equal(res.oracle_before.ok, false);
  assert.equal(res.oracle_before.problems.length, 2);
  assert.equal(res.oracle_after.ok, true);
  assert.deepEqual(res.oracle_after.problems, []);
  assert.deepEqual(res.patch.map((p) => p.path).sort(), [P0, P1]);
  assert.equal(res.mutation_used, 'REPAIR-LOOP-V1');
  assert.equal(res.quality_not_proven, true);

  // sortie de contrat complete
  for (const champ of ['patch', 'before', 'after', 'oracle_before', 'oracle_after',
    'evidence_created', 'mutation_used']) {
    assert.ok(champ in res, `sortie de contrat: ${champ} manquant`);
  }
  // preuve reellement ecrite sur disque
  const fichiers = (await readdir(o.preuve)).sort();
  assert.deepEqual(fichiers, ['after.json', 'before.json', 'measured_metrics.json',
    'oracle_after.json', 'oracle_before.json', 'patch.json']);
  const metr = JSON.parse(await readFile(join(o.preuve, 'measured_metrics.json'), 'utf-8'));
  assert.equal(metr.problems_before, 2);
  assert.equal(metr.problems_after, 0);
  assert.equal(metr.oracle_pass, true);
  assert.equal(metr.quality_not_proven, true);
});

test('CONTRACT_VIOLATION: une ecriture hors perimetre RECU annule tout et restaure', async () => {
  const o = await runDegrade();
  const avant = await readFile(o.artefact, 'utf-8');
  // le reparateur va corriger les DEUX champs (sa liste blanche interne les autorise) ;
  // le contrat n en declare qu UN. C est le perimetre RECU qui gagne.
  const res = await executerReparation(
    requete({ ...o, patch: { finding_id: [ID0, ID1], allowed_fields: [P0] } }),
    { appelerModele: modeleFidele },
  );

  assert.equal(res.contract_status, 'CONTRACT_VIOLATION');
  assert.match(res.contract_detail, /games\[1\]\.retention_answer/);
  assert.deepEqual(res.patch, []);
  assert.equal(res.oracle_after.ok, false, 'l oracle repasse au rouge : rien n a ete garde');
  assert.equal(await readFile(o.artefact, 'utf-8'), avant, 'artefact restaure a l identique');
});

test('forbidden_fields est verifie meme si le chemin est aussi derive par l oracle', async () => {
  const o = await runDegrade();
  const res = await executerReparation(
    requete({ ...o, patch: { finding_id: [ID0, ID1], allowed_fields: [P0], forbidden_fields: [P1] } }),
    { appelerModele: modeleFidele },
  );
  assert.equal(res.contract_status, 'CONTRACT_VIOLATION');
});

test('quality_not_proven est CONSTANT: aucune execution ne peut le faire tomber', async () => {
  const o = await runDegrade();
  const res = await executerReparation(
    requete({ ...o, patch: { finding_id: [ID0, ID1], allowed_fields: [P0, P1] } }),
    { appelerModele: modeleFidele },
  );
  assert.equal(res.oracle_after.ok, true, 'oracle vert…');
  assert.equal(res.quality_not_proven, true, '…et la qualite reste NON prouvee');
});

// --- garde d'architecture ---

test('ADAPTATEUR SEUL: aucune logique de reparation n a migre dans ce fichier', async () => {
  const src = await readFile(fileURLToPath(new URL('./repair_runtime_adapter.mjs', import.meta.url)), 'utf-8');
  const code = src.split('\n').filter((l) => !l.trim().startsWith('//')).join('\n');
  for (const interdit of ['fetch(', 'localhost', 'temperature', 'max_tokens', 'FIELD_TO_REPAIR']) {
    assert.ok(!code.includes(interdit),
      `l adaptateur ne doit pas contenir « ${interdit} » — il encapsule, il ne repare pas`);
  }
});

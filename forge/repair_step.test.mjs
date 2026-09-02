// Tests du point d'entrée de réparation par étape.
// node --test forge/repair_step.test.mjs
//
// Le modèle réparateur est TOUJOURS injecté : aucun test n'appelle LM Studio. Les
// oracles, eux, sont les VRAIS oracles du dépôt sur de vrais fichiers temporaires —
// c'est la seule façon de prouver que le câblage étape -> oracle est correct.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, writeFile, readFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { ETAPES, reparerEtape } from './repair_step.mjs';
import {
  worldscanReference, prismeReference, featuremapReference,
  blueprintReference, wiremapReference,
} from './upstream_fixtures.mjs';

async function runDirComplet() {
  const dir = await mkdtemp(join(tmpdir(), 'repair-step-'));
  const w = (nom, obj) => writeFile(join(dir, nom), JSON.stringify(obj, null, 1), 'utf-8');
  await Promise.all([
    w('worldscan.json', worldscanReference()),
    w('prisme.json', prismeReference()),
    w('featuremap.json', featuremapReference()),
    w('blueprint.json', blueprintReference()),
    w('wiremap.json', wiremapReference()),
  ]);
  return dir;
}

const modeleInterdit = async () => { throw new Error('le modele ne doit pas etre appele'); };

test('les 5 etapes amont sont cablees, et AUCUNE etape post-build', () => {
  assert.deepEqual(Object.keys(ETAPES).sort(), [
    's1-prisme', 's2-worldscan', 's3-decompo', 's4-archi-contract', 's5-wiremap-contract',
  ]);
  // les oracles de preuve finale ne sont pas dans cette table, a dessein
  const oracles = Object.values(ETAPES).map((s) => s.oracle);
  assert.ok(!oracles.includes('check_architecture'));
  assert.ok(!oracles.includes('check_wiremap'));
});

test('VALIDITE: les 5 etapes acceptent les artefacts de reference, SANS appeler le modele', async () => {
  const dir = await runDirComplet();
  for (const etape of Object.keys(ETAPES)) {
    // eslint-disable-next-line no-await-in-loop -- sortie lisible, volume faible
    const m = await reparerEtape({ etape, runDir: dir, appelerModele: modeleInterdit });
    assert.equal(m.STATUS, 'OK_SANS_REPARATION', `${etape}: ${JSON.stringify(m)}`);
    assert.equal(m.PROBLEMS_BEFORE, 0);
    assert.equal(m.TOKENS, 0);
    assert.deepEqual(m.REGRESSION, []);
  }
});

test('une etape inconnue leve explicitement (jamais un vert silencieux)', async () => {
  const dir = await runDirComplet();
  await assert.rejects(
    () => reparerEtape({ etape: 's99-inexistante', runDir: dir, appelerModele: modeleInterdit }),
    /etape inconnue/,
  );
});

test('artefact illisible -> statut dedie, jamais une exception qui traverse', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'repair-vide-'));
  const m = await reparerEtape({ etape: 's2-worldscan', runDir: dir, appelerModele: modeleInterdit });
  assert.equal(m.STATUS, 'ARTEFACT_ILLISIBLE');
  assert.match(m.DETAIL, /worldscan\.json/);
});

test('--no-repair mesure l oracle SEUL (colonne « worker seul » d une comparaison)', async () => {
  const dir = await runDirComplet();
  const ws = worldscanReference();
  ws.games[0].retention_answer = '';
  await writeFile(join(dir, 'worldscan.json'), JSON.stringify(ws), 'utf-8');

  const m = await reparerEtape({
    etape: 's2-worldscan', runDir: dir, reparer: false, appelerModele: modeleInterdit,
  });
  assert.equal(m.STATUS, 'FAIL_SANS_REPARATION');
  assert.equal(m.PROBLEMS_BEFORE, 1);
  assert.equal(m.PROBLEMS_AFTER, 1);
  assert.equal(m.TOKENS, 0);
});

test('PREUVE: reparation automatique complete sur s2-worldscan (vrai oracle, modele injecte)', async () => {
  const dir = await runDirComplet();
  const ws = worldscanReference();
  ws.games[0].retention_answer = '';
  await writeFile(join(dir, 'worldscan.json'), JSON.stringify(ws), 'utf-8');

  const m = await reparerEtape({
    etape: 's2-worldscan', runDir: dir, worker: 'faux-modele',
    appelerModele: async (prompt) => {
      const chemin = prompt.match(/FIELD_TO_REPAIR:\n(.+)/)[1].trim();
      return `\`\`\`json\n{"path": "${chemin}", "value": "les paliers rapproches ramenent le joueur"}\n\`\`\``;
    },
  });

  assert.equal(m.STATUS, 'REPARE');
  assert.equal(m.PROBLEMS_BEFORE, 1);
  assert.equal(m.PROBLEMS_AFTER, 0);
  assert.equal(m.CYCLES, 1);
  assert.deepEqual(m.FIELDS_CHANGED, ['games[0].retention_answer']);
  assert.deepEqual(m.REGRESSION, []);

  // l artefact REPARE est bien celui qui reste sur disque
  const surDisque = JSON.parse(await readFile(join(dir, 'worldscan.json'), 'utf-8'));
  assert.match(surDisque.games[0].retention_answer, /paliers rapproches/);
  assert.equal(surDisque.games[1].retention_answer, worldscanReference().games[1].retention_answer,
    'le jeu deja valide n a pas bouge');
});

test('PREUVE: reparation sur s1-prisme (tache de TRANSFORMATION, pas de rappel)', async () => {
  const dir = await runDirComplet();
  const pr = prismeReference();
  // Defaut STRUCTUREL (niveau 1 : decide le verdict). Un `expected_proof.statement`
  // manquant ne conviendrait PAS ici : l'oracle Prisme le CLASSE non-actionnable
  // (niveau 2) sans faire echouer l'artefact tant qu'il reste une exigence
  // actionnable — la boucle ne repare que ce que l'oracle REJETTE.
  pr.exigences[0].claim = '';
  await writeFile(join(dir, 'prisme.json'), JSON.stringify(pr), 'utf-8');

  const avant = await reparerEtape({
    etape: 's1-prisme', runDir: dir, reparer: false, appelerModele: modeleInterdit,
  });
  assert.equal(avant.STATUS, 'FAIL_SANS_REPARATION');

  const m = await reparerEtape({
    etape: 's1-prisme', runDir: dir, worker: 'faux-modele',
    appelerModele: async (prompt) => {
      const chemin = prompt.match(/FIELD_TO_REPAIR:\n(.+)/)[1].trim();
      return `\`\`\`json\n{"path": "${chemin}", "value": "Le clic manuel est la seule source de progression a la premiere seconde."}\n\`\`\``;
    },
  });
  assert.equal(m.STATUS, 'REPARE');
  assert.equal(m.PROBLEMS_AFTER, 0);
  assert.deepEqual(m.FIELDS_CHANGED, ['exigences[0].claim']);
  assert.deepEqual(m.REGRESSION, []);
});

test('ESCALADE: un reparateur muet laisse l artefact intact et rend un statut d escalade', async () => {
  const dir = await runDirComplet();
  const ws = worldscanReference();
  ws.games[0].retention_answer = '';
  await writeFile(join(dir, 'worldscan.json'), JSON.stringify(ws), 'utf-8');

  const m = await reparerEtape({
    etape: 's2-worldscan', runDir: dir, appelerModele: async () => null,
  });
  assert.equal(m.STATUS, 'ESCALADE');
  assert.equal(m.PROBLEMS_AFTER, 1);
  assert.deepEqual(m.FIELDS_CHANGED, []);
  const surDisque = JSON.parse(await readFile(join(dir, 'worldscan.json'), 'utf-8'));
  assert.equal(surDisque.games[0].retention_answer, '');
});

test('un reparateur qui vise un AUTRE chemin ne peut rien ecrire', async () => {
  const dir = await runDirComplet();
  const ws = worldscanReference();
  ws.games[0].retention_answer = '';
  await writeFile(join(dir, 'worldscan.json'), JSON.stringify(ws), 'utf-8');

  const m = await reparerEtape({
    etape: 's2-worldscan', runDir: dir,
    appelerModele: async () => '```json\n{"path": "advisory", "value": false}\n```',
  });
  assert.equal(m.STATUS, 'ESCALADE');
  const surDisque = JSON.parse(await readFile(join(dir, 'worldscan.json'), 'utf-8'));
  assert.equal(surDisque.advisory, true, 'le champ vise hors cible n a pas ete touche');
});

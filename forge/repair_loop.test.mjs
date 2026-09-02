// Tests de REPAIR_LOOP_V1 — boucle de réparation locale sous liste blanche.
// node --test forge/repair_loop.test.mjs
//
// Tout est hors-ligne : `appelerModele` et `valider` sont des faux injectés. Aucun
// test n'appelle un modèle — une boucle dont la garantie dépend d'un appel réseau
// ne se teste pas, elle s'espère.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  segments, lire, ecrire, cheminsFeuilles, analyserFindings, classer, cheminDe,
  construirePromptReparation, construirePromptChamp, contexteVoisin,
  extrairePatch, appliquerReparation, boucleReparation,
} from './repair_loop.mjs';
import { checkWorldScanFile } from './check_worldscan.mjs';

const artefactType = () => ({
  games: [
    { game: 'A', retention_answer: '', sources: [{ url: 'https://a.test', type: 'wiki' }] },
    { game: 'B', retention_answer: 'ok', sources: [{ url: 'https://b.test', type: 'wiki' }] },
  ],
  advisory: true,
});

// --- chemins ---------------------------------------------------------------------

test('segments / cheminDe : aller-retour sur indices et champs imbriques', () => {
  assert.deepEqual(segments('games[0].retention_answer'), ['games', 0, 'retention_answer']);
  assert.deepEqual(segments('exigences[2].expected_proof.kind'), ['exigences', 2, 'expected_proof', 'kind']);
  assert.deepEqual(segments('advisory'), ['advisory']);
  assert.equal(cheminDe(['games', 0, 'retention_answer']), 'games[0].retention_answer');
});

test('lire : un chemin absent rend undefined, jamais une exception', () => {
  const a = artefactType();
  assert.equal(lire(a, 'games[1].game'), 'B');
  assert.equal(lire(a, 'games[9].game'), undefined);
  assert.equal(lire(a, 'inexistant.profond.chemin'), undefined);
  assert.equal(lire(null, 'x'), undefined);
});

test('ecrire : cree les champs manquants mais JAMAIS un index de tableau hors-borne', () => {
  const a = artefactType();
  assert.equal(ecrire(a, 'games[0].retention_answer', 'repare'), true);
  assert.equal(a.games[0].retention_answer, 'repare');
  // champ absent -> cree
  assert.equal(ecrire(a, 'games[0].nouveau', 'x'), true);
  // index hors-borne -> refuse (sinon on fabriquerait un jeu fantome plein de trous)
  assert.equal(ecrire(a, 'games[7].game', 'fantome'), false);
  assert.equal(a.games.length, 2);
  // ecraser une feuille par un conteneur -> refuse (perte de donnee)
  assert.equal(ecrire(a, 'advisory.sous_champ', 'x'), false);
});

// --- findings --------------------------------------------------------------------

test('analyserFindings : separe une ADRESSE d une phrase en prose', () => {
  const f = analyserFindings([
    'games[0].retention_answer: absent ou vide',
    'observation_manifest.json: 1 jeu(x) analyse(s), minimum 2 requis',
    'media local interdit trouve : x.png (URLs citees)',
  ]);
  assert.equal(f[0].classe, 'champ');
  assert.equal(f[0].chemin, 'games[0].retention_answer');
  assert.equal(f[0].raison, 'absent ou vide');
  // « observation_manifest.json » n'est pas une adresse de champ : il manque un OBJET
  assert.equal(f[1].classe, 'structurel');
  assert.equal(f[2].classe, 'structurel');
});

test('classer : un chemin dont le conteneur parent n existe pas n est pas reparable', () => {
  const a = artefactType();
  const { reparables, non_reparables } = classer(a, analyserFindings([
    'games[0].retention_answer: absent ou vide',
    'games[5].retention_answer: absent ou vide',
  ]));
  assert.equal(reparables.length, 1);
  assert.equal(non_reparables.length, 1);
  assert.match(non_reparables[0].motif_non_reparable, /conteneur parent/);
});

test('construirePromptReparation ne contient QUE les champs fautifs, pas l artefact', () => {
  const { reparables } = classer(artefactType(), analyserFindings(['games[0].retention_answer: absent ou vide']));
  const p = construirePromptReparation(reparables, { etape: 's2-worldscan', game_id: 'jeu' });
  assert.match(p, /games\[0\]\.retention_answer/);
  assert.ok(!p.includes('https://a.test'), 'le prompt ne doit pas embarquer l artefact');
  assert.ok(p.length < 700, `prompt trop long (${p.length}) — le gain de cout vient de sa brievete`);
});

test('extrairePatch : dernier bloc json fenced, JSON nu accepte, prose rejetee', () => {
  assert.deepEqual(extrairePatch('bla\n```json\n{"a":1}\n```'), { a: 1 });
  assert.deepEqual(extrairePatch('```json\n{"a":1}\n```\n```json\n{"b":2}\n```'), { b: 2 });
  assert.deepEqual(extrairePatch('{"a":1}'), { a: 1 });
  assert.equal(extrairePatch('je ne sais pas faire'), null);
  assert.equal(extrairePatch('```json\n[1,2]\n```'), null); // un tableau n est pas un patch
});

// --- LA garantie ------------------------------------------------------------------

test('GARANTIE: une cle hors liste blanche est REJETEE, pas appliquee', () => {
  const a = artefactType();
  const r = appliquerReparation(a, {
    'games[0].retention_answer': 'valeur reparee',
    'games[1].retention_answer': 'REECRITURE PIRATE',   // valide, hors cibles
    'advisory': false,                                   // hors cibles
  }, ['games[0].retention_answer']);

  assert.deepEqual(r.repaired_fields, ['games[0].retention_answer']);
  assert.deepEqual(r.rejected_keys.sort(), ['advisory', 'games[1].retention_answer']);
  assert.equal(r.artefact.games[1].retention_answer, 'ok', 'un champ deja valide ne bouge pas');
  assert.equal(r.artefact.advisory, true);
  assert.deepEqual(r.regressions, []);
});

test('GARANTIE: l artefact d origine n est jamais mute', () => {
  const a = artefactType();
  const avant = JSON.stringify(a);
  appliquerReparation(a, { 'games[0].retention_answer': 'x' }, ['games[0].retention_answer']);
  assert.equal(JSON.stringify(a), avant);
});

test('GARANTIE: la non-regression est CALCULEE, pas supposee', () => {
  const a = artefactType();
  const r = appliquerReparation(a, { 'games[0].retention_answer': 'x' }, ['games[0].retention_answer']);
  assert.deepEqual(r.regressions, []);
  // tous les autres chemins-feuilles sont preserves
  assert.ok(r.preserved_fields.includes('games[1].retention_answer'));
  assert.ok(r.preserved_fields.includes('games[0].sources[0].url'));
  assert.ok(!r.preserved_fields.includes('games[0].retention_answer'));
  // et le compte total est coherent
  assert.equal(cheminsFeuilles(r.artefact).size, cheminsFeuilles(a).size);
});

// --- boucle ------------------------------------------------------------------------

const validateurFactice = (art) => {
  const problems = [];
  (art.games || []).forEach((g, i) => {
    if (!g.retention_answer || !String(g.retention_answer).trim()) {
      problems.push(`games[${i}].retention_answer: absent ou vide`);
    }
  });
  return { ok: problems.length === 0, problems };
};

test('BOUCLE: un artefact deja valide ne declenche AUCUN appel modele', async () => {
  let appels = 0;
  const a = artefactType();
  a.games[0].retention_answer = 'deja bon';
  const r = await boucleReparation({
    artefact: a, valider: validateurFactice,
    appelerModele: async () => { appels += 1; return '{}'; },
  });
  assert.equal(r.ok, true);
  assert.equal(appels, 0);
  assert.deepEqual(r.cycles, []);
});

test('BOUCLE: repare le champ fautif en un cycle et passe l oracle', async () => {
  const r = await boucleReparation({
    artefact: artefactType(), valider: validateurFactice,
    appelerModele: async () => '```json\n{"path": "games[0].retention_answer", "value": "ce qui fait revenir le joueur"}\n```',
  });
  assert.equal(r.ok, true);
  assert.equal(r.resume.cycles_utilises, 1);
  assert.deepEqual(r.resume.champs_repares, ['games[0].retention_answer']);
  assert.deepEqual(r.resume.regressions, []);
  assert.equal(r.artefact.games[1].retention_answer, 'ok');
});

test('BOUCLE: un modele qui ne repare rien ARRETE la boucle (ne repaie pas le meme echec)', async () => {
  let appels = 0;
  const r = await boucleReparation({
    artefact: artefactType(), valider: validateurFactice,
    appelerModele: async () => { appels += 1; return '```json\n{"path": "un.autre.champ", "value": "hors cible"}\n```'; },
    maxCycles: 5,
  });
  assert.equal(r.ok, false);
  assert.equal(appels, 1, 'un cycle sans reparation doit stopper, pas boucler 5 fois');
  // La paire est bien formee mais MAL ADRESSEE : elle ne vise pas le chemin demande,
  // donc elle n'entre pas dans le patch — un reparateur ne choisit pas sa cible.
  assert.ok(r.cycles.some((c) => /aucune paire \{path, value\}/.test(c.arret || '')));
  assert.equal(r.artefact.games[0].retention_answer, '');
});

test('CONVERGENCE: un champ ecrit avec une valeur INVALIDE ne compte pas comme un progres', async () => {
  // Le cas reel du 2026-08-04 : le modele recopiait le gabarit vide, la boucle
  // « reparait » les deux champs, et l oracle restait a 2 problemes. Sans ce garde-fou
  // elle payait maxCycles appels pour rien.
  let appels = 0;
  const r = await boucleReparation({
    artefact: artefactType(), valider: validateurFactice, maxCycles: 3,
    appelerModele: async () => {
      appels += 1;
      return '```json\n{"path": "games[0].retention_answer", "value": ""}\n```'; // ecrit, mais toujours vide
    },
  });
  assert.equal(r.ok, false);
  assert.equal(appels, 1, 'un cycle sans decroissance du nombre de problemes doit stopper');
  assert.ok(r.cycles.some((c) => /aucun progres mesure/.test(c.arret || '')));
});

test('le prompt de reparation ne montre AUCUNE valeur copiable (chaine vide interdite)', () => {
  const { reparables } = classer(artefactType(), analyserFindings([
    'games[0].retention_answer: absent ou vide',
  ]));
  const p = construirePromptReparation(reparables);
  assert.ok(!/"\s*"/.test(p), 'aucune chaine vide ne doit apparaitre : le modele la recopie');
  assert.ok(!p.includes('"games[0].retention_answer": ""'), 'pas de gabarit pre-rempli');
  assert.match(p, /jamais une chaîne/);
});

test('BOUCLE: modele muet ou sans JSON -> arret propre, artefact intact', async () => {
  const r = await boucleReparation({
    artefact: artefactType(), valider: validateurFactice,
    appelerModele: async () => 'je ne sais pas',
  });
  assert.equal(r.ok, false);
  assert.equal(r.artefact.games[0].retention_answer, '');
  assert.ok(r.cycles.some((c) => /aucune paire \{path, value\}/.test(c.arret || '')));
});

test('BOUCLE: findings uniquement structurels -> aucun appel modele, arret motive', async () => {
  const r = await boucleReparation({
    artefact: artefactType(),
    valider: () => ({ ok: false, problems: ['observation_manifest.json: 1 jeu(x), minimum 2 requis'] }),
    appelerModele: async () => { throw new Error('ne doit jamais etre appele'); },
  });
  assert.equal(r.ok, false);
  assert.ok(r.cycles.some((c) => /aucun finding reparable/.test(c.arret || '')));
});

test('BOUCLE: maxCycles est respecte (un appel PAR CHAMP, pas par cycle)', async () => {
  // 3 champs vides -> 3 findings -> 3 appels dans le meme cycle. Le modele n en
  // repare qu un seul : les problemes decroissent (3 -> 2), la boucle continuerait,
  // mais maxCycles=1 l arrete. Sans borne elle tournerait sur les 2 restants.
  const art = { games: [{ retention_answer: '' }, { retention_answer: '' }, { retention_answer: '' }] };
  let appels = 0;
  const r = await boucleReparation({
    artefact: art, valider: validateurFactice, maxCycles: 1,
    appelerModele: async (prompt) => {
      appels += 1;
      const chemin = prompt.match(/FIELD_TO_REPAIR:\n(.+)/)[1].trim();
      if (chemin !== 'games[0].retention_answer') return null; // les autres restent vides
      return `\`\`\`json\n{"path": "${chemin}", "value": "une vraie valeur"}\n\`\`\``;
    },
  });
  assert.equal(appels, 3, 'un appel par champ fautif, dans le meme cycle');
  assert.equal(r.ok, false);
  assert.equal(r.resume.cycles_utilises, 1, 'maxCycles=1 : un seul cycle');
  assert.deepEqual(r.resume.champs_repares, ['games[0].retention_answer']);
  assert.equal(r.artefact.games[1].retention_answer, '');
});

test('le prompt d UN champ porte les 4 sections imposees et son VALID_CONTEXT', () => {
  const art = artefactType();
  const { reparables } = classer(art, analyserFindings(['games[0].retention_answer: absent ou vide']));
  const p = construirePromptChamp(reparables[0], art, { etape: 's2-worldscan', game_id: 'jeu' });
  for (const section of ['FIELD_TO_REPAIR:', 'FAILURE_REASON:', 'VALID_CONTEXT', 'FORBIDDEN:']) {
    assert.ok(p.includes(section), `section manquante : ${section}`);
  }
  assert.match(p, /"path"/);
  assert.match(p, /"value"/);
  // VALID_CONTEXT expose les voisins SCALAIRES du meme conteneur, pas l artefact
  assert.match(p, /"game": "A"/);
  assert.ok(!p.includes('https://b.test'), 'aucune donnee d un AUTRE jeu ne doit fuiter');
});

test('contexteVoisin : voisins scalaires seulement, tronques, sans la cible', () => {
  const art = artefactType();
  const v = contexteVoisin(art, 'games[0].retention_answer');
  assert.deepEqual(Object.keys(v), ['game']); // `sources` est un conteneur : exclu
  assert.equal(v.game, 'A');
  const long = { a: 'x'.repeat(500), cible: '' };
  assert.ok(contexteVoisin({ a: long }, 'a.cible', 50).a.length <= 51);
});

// --- intégration avec un VRAI oracle du dépôt --------------------------------------

test('INTEGRATION: la boucle repare un vrai worldscan.json rejete par le vrai oracle', async () => {
  const { writeFile, mkdtemp } = await import('node:fs/promises');
  const { tmpdir } = await import('node:os');
  const { join } = await import('node:path');

  const dir = await mkdtemp(join(tmpdir(), 'repair-'));
  const chemin = join(dir, 'worldscan.json');
  const jeu = (nom, retention) => ({
    game: nom,
    sources: [
      { url: 'https://exemple.test/wiki', type: 'wiki' },
      { url: 'https://exemple.test/article', type: 'article' },
      { url: 'https://exemple.test/video', type: 'video', timestamp: '00:01:00' },
    ],
    loops: { minute_1: 'a', minute_10: 'b', hour_5: 'c', endgame: 'd' },
    objectives: [{
      mode: 'solo', has_win_state: false, victory_condition: null,
      has_defeat_state: false, defeat_condition: null, player_goal: 'avancer',
    }],
    retention_answer: retention,
  });
  const artefact = { games: [jeu('A', ''), jeu('B', 'ok')], advisory: true };

  // Le VRAI oracle du dépôt, branché directement : la boucle `await` son résultat.
  const valider = async (art) => {
    await writeFile(chemin, JSON.stringify(art), 'utf-8');
    const r = await checkWorldScanFile(chemin);
    return { ok: r.ok, problems: r.problems };
  };

  const avant = await valider(artefact);
  assert.equal(avant.ok, false);
  assert.equal(avant.problems.length, 1);
  assert.match(avant.problems[0], /games\[0\]\.retention_answer/);

  const r = await boucleReparation({
    artefact, valider,
    appelerModele: async (prompt) => {
      assert.match(prompt, /games\[0\]\.retention_answer/);
      assert.ok(!prompt.includes('exemple.test'), 'le prompt ne doit pas embarquer l artefact');
      return '```json\n{"path": "games[0].retention_answer", "value": "les paliers rapproches font revenir le joueur"}\n```';
    },
    maxCycles: 1,
  });

  assert.equal(r.ok, true, 'le VRAI oracle doit passer apres reparation');
  assert.deepEqual(r.resume.regressions, []);
  assert.equal(r.artefact.games[1].retention_answer, 'ok');
  assert.equal(r.artefact.games[0].sources.length, 3, 'les sources sont preservees');
});

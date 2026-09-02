// Tests de l'ORACLE QUALITY LAYER V1.
// node --test forge/oracle_quality.test.mjs
//
// Aucun modèle n'est appelé : chaque signal est un prédicat déterministe. Le test le
// plus important du fichier est le premier — un signal qui crie sur les artefacts
// connus-bons est du bruit, et le bruit finit par être ignoré, donc par redevenir un
// angle mort.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  CHAMPS_DE_SENS, feuillesTexte, estChampDeSens, motifDeChemin, langueDe,
  verifierDiscriminance, verifierLangue, verifierRecopie,
  mesurerSignalSemantique, classeDeDefaut, ciblesDuSignal,
  promptReparationSignal, rapportQualite,
} from './oracle_quality.mjs';
import {
  worldscanReference, prismeReference, featuremapReference,
  blueprintReference, wiremapReference,
} from './upstream_fixtures.mjs';

// --- LE test de validite : zero fausse alerte sur les connus-bons -------------------

test('VALIDITE: 0 signal sur les 5 artefacts de reference', () => {
  const refs = {
    worldscan: worldscanReference(), prisme: prismeReference(),
    featuremap: featuremapReference(), blueprint: blueprintReference(),
    wiremap: wiremapReference(),
  };
  for (const [nom, doc] of Object.entries(refs)) {
    const r = mesurerSignalSemantique(doc);
    assert.deepEqual(r.signaux, [], `${nom} : ${JSON.stringify(r.signaux)}`);
    assert.equal(r.verdict, 'PASS');
  }
});

// --- Q1 discriminance --------------------------------------------------------------

test('DISCRIMINANCE: deux entrees decrites par la MEME phrase = information nulle', () => {
  const ws = worldscanReference();
  ws.games[1].retention_answer = ws.games[0].retention_answer;
  const r = mesurerSignalSemantique(ws);
  assert.equal(r.compte.DISCRIMINANCE, 1);
  const s = r.signaux[0];
  assert.deepEqual(s.chemins, ['games[0].retention_answer', 'games[1].retention_answer']);
  assert.equal(s.classe, 'C'); // oracle trop faible : la mesure etait loin du besoin
});

test('DISCRIMINANCE: insensible a la ponctuation et a la casse (meme phrase = meme phrase)', () => {
  const ws = worldscanReference();
  ws.games[1].retention_answer = `${ws.games[0].retention_answer.toUpperCase()} !!`;
  assert.equal(mesurerSignalSemantique(ws).compte.DISCRIMINANCE, 1);
});

test('DISCRIMINANCE: un champ present une seule fois n est jamais signale', () => {
  const doc = { games: [{ retention_answer: 'seul de son espece' }] };
  assert.deepEqual(verifierDiscriminance(feuillesTexte(doc)), []);
});

test('DISCRIMINANCE: ne regarde QUE les champs de sens (pas les ids ni les urls)', () => {
  const doc = {
    games: [
      { game: 'A', sources: [{ url: 'https://meme.test' }], retention_answer: 'x1' },
      { game: 'B', sources: [{ url: 'https://meme.test' }], retention_answer: 'x2' },
    ],
  };
  // deux jeux peuvent legitimement citer la MEME source
  assert.deepEqual(verifierDiscriminance(feuillesTexte(doc)), []);
});

// --- Q2 langue ---------------------------------------------------------------------

test('LANGUE: indecidable sous le seuil de mots -> aucun avis (jamais un faux positif)', () => {
  assert.equal(langueDe('trop court'), null);
  assert.equal(langueDe('Proceed with caution near ghosts.'), null);
  assert.equal(langueDe('le joueur doit manger tous les points du labyrinthe sans se faire attraper'), 'fr');
  assert.equal(langueDe('the player must eat all of the dots in the maze without being caught by a ghost'), 'en');
});

test('LANGUE: un champ dans une autre langue que l artefact est signale', () => {
  const ws = worldscanReference();
  ws.games[0].loops.minute_1 = 'The player clicks the cookie and the counter goes up with every single tap of the mouse';
  const r = mesurerSignalSemantique(ws);
  assert.equal(r.compte.LANGUE, 1);
  assert.equal(r.signaux.find((s) => s.signal === 'LANGUE').classe, 'B');
});

test('LANGUE: aucun avis si l artefact n a pas de langue dominante nette', () => {
  const doc = {
    games: [{
      loops: {
        minute_1: 'le joueur doit manger tous les points du labyrinthe sans etre attrape',
        minute_10: 'the player must clear the maze while the ghosts are getting much faster',
      },
    }],
  };
  assert.deepEqual(verifierLangue(feuillesTexte(doc)), []);
});

// --- Q3 recopie --------------------------------------------------------------------

test('RECOPIE: un champ qui recopie son voisin n ajoute rien', () => {
  const doc = {
    exigences: [{
      observation: 'le compteur monte a chaque clic du joueur sur le cookie',
      claim: 'le compteur monte a chaque clic du joueur sur le cookie affiche',
      enonce: 'tout autre chose sans aucun mot commun ici',
    }],
  };
  const r = verifierRecopie(feuillesTexte(doc));
  assert.equal(r.length, 1);
  assert.equal(classeDeDefaut(r[0].signal), 'B');
});

test('RECOPIE: deux champs voisins reellement distincts ne sont pas signales', () => {
  assert.deepEqual(verifierRecopie(feuillesTexte(prismeReference())), []);
});

// --- outils ------------------------------------------------------------------------

test('motifDeChemin regroupe les occurrences d un meme champ', () => {
  assert.equal(motifDeChemin('games[0].objectives[1].player_goal'), 'games[*].objectives[*].player_goal');
});

test('estChampDeSens ne retient que les champs porteurs d information', () => {
  assert.ok(estChampDeSens('games[0].retention_answer'));
  assert.ok(estChampDeSens('exigences[2].claim'));
  assert.ok(!estChampDeSens('games[0].sources[0].url'));
  assert.ok(!estChampDeSens('games[0].id'));
  assert.ok(CHAMPS_DE_SENS.includes('retention_answer'));
});

// --- reparation par classe ---------------------------------------------------------

test('ciblesDuSignal: une DISCRIMINANCE garde la 1re occurrence et differencie les autres', () => {
  assert.deepEqual(ciblesDuSignal({ signal: 'DISCRIMINANCE', chemins: ['a', 'b', 'c'] }), ['b', 'c']);
  assert.deepEqual(ciblesDuSignal({ signal: 'RECOPIE', chemins: ['a', 'b'] }), ['b']);
  assert.deepEqual(ciblesDuSignal({ signal: 'LANGUE', chemins: ['a'] }), ['a']);
});

test('le prompt DEPEND de la classe : une discriminance montre la phrase a ne pas repeter', () => {
  const s = { signal: 'DISCRIMINANCE', chemins: ['games[0].player_goal', 'games[1].player_goal'], detail: 'd' };
  const p = promptReparationSignal(s, 'games[1].player_goal', { game: 'Super Bomberman R' }, 'survivre et eliminer');
  assert.match(p, /NE PAS RÉPÉTER/);
  assert.match(p, /survivre et eliminer/);
  assert.match(p, /Super Bomberman R/);
  assert.match(p, /"path"/);

  const r = promptReparationSignal({ signal: 'RECOPIE', chemins: ['a', 'b'], detail: 'd' }, 'b', {}, 'v');
  assert.match(r, /AJOUTE par rapport à a/);
  assert.ok(!/NE PAS RÉPÉTER/.test(r), 'chaque classe a sa propre consigne, pas un texte generique');
});

// --- rapport -----------------------------------------------------------------------

test('rapport: 4 axes SEPARES, advisory, et AUCUN score global', () => {
  const r = rapportQualite({
    structure: true, provenance: true, nonRegression: true, artefact: worldscanReference(),
  });
  assert.equal(r.STRUCTURE, 'PASS');
  assert.equal(r.PROVENANCE, 'PASS');
  assert.equal(r.NON_REGRESSION, 'PASS');
  assert.equal(r.SEMANTIC_SIGNAL, 'PASS');
  assert.equal(r.advisory, true);
  assert.equal(r.score_global, null);
});

test('rapport: un axe FAIL n est jamais compense par les autres', () => {
  const ws = worldscanReference();
  ws.games[1].retention_answer = ws.games[0].retention_answer;
  const r = rapportQualite({ structure: true, provenance: true, nonRegression: true, artefact: ws });
  assert.equal(r.STRUCTURE, 'PASS');
  assert.equal(r.SEMANTIC_SIGNAL, 'FAIL'); // les deux coexistent, aucun ne masque l autre
  assert.equal(r.score_global, null);
});

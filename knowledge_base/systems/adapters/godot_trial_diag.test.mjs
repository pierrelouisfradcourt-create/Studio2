// CANAL DE DIAGNOSTIC `FORGE_DIAG` (GO Pierre 2026-08-18).
//
// DEFAUT MESURE. `games/bomberman_3d/solvability.gd` emet, a cote du recu, une ligne
// `FORGE_DIAG <json>` riche — statut, kills du bot, morts, destructibles restants,
// `budget_epuise`, positions — ecrite explicitement pour qu'« un essai perdu puisse etre
// DIAGNOSTIQUE ». Son commentaire precise qu'elle vit sur « un canal DISTINCT du recu
// (prefixe different, donc jamais confondu) ».
//
// ZERO ligne remonte. `parseReceipt` FILTRE la sortie sur le seul prefixe `FORGE_TRIAL `
// (l.23) : tout le reste est jete avec le stdout du sous-processus. L'intention du
// producteur est structurellement annulee par le consommateur, qui ne connait qu'un
// prefixe. Producteur sans consommateur — sur la SEULE information qui dirait POURQUOI
// bomberman_3d perd (mesure 2026-08-18 : 0/1 a 12000, 30000 et 60000 ticks, ~19 s/essai,
// la partie se termine naturellement bien avant le plafond).
//
// CE QUI NE DOIT PAS BOUGER : le contrat de sortie est STRICT PAR CONCEPTION. Un recu
// absent, illisible, ou EN DOUBLE reste une erreur — elargir ce que l'adaptateur RETIENT
// ne doit pas relacher ce qu'il VALIDE. La moitie de ces tests garde cette frontiere.
import assert from 'node:assert/strict';
import test from 'node:test';

import { parseReceipt } from './godot_trial.mjs';

const RECU = 'FORGE_TRIAL {"succeeded":false,"ticks":null}';
const DIAG = 'FORGE_DIAG {"statut":2,"gagne":false,"kills_du_bot":0,"morts":3}';

// --- ce que le lot AJOUTE --------------------------------------------------------------

test('le diagnostic REMONTE quand il est present', () => {
  const r = parseReceipt(['Godot Engine v4.6.3', DIAG, RECU, ''].join('\n'));
  assert.equal(r.succeeded, false);
  assert.deepEqual(r.diag, { statut: 2, gagne: false, kills_du_bot: 0, morts: 3 });
});

test('l ORDRE des deux lignes est indifferent', () => {
  // Le producteur ecrit DIAG puis TRIAL, mais rien ne l impose : l adaptateur filtre,
  // il ne suppose pas de sequence.
  const r = parseReceipt([RECU, DIAG].join('\n'));
  assert.deepEqual(r.diag, { statut: 2, gagne: false, kills_du_bot: 0, morts: 3 });
});

test('le bruit du moteur ne perturbe pas l extraction', () => {
  const bruit = ['Godot Engine v4.6.3.stable', 'WARNING: quelque chose', '', DIAG,
                 'core/os: info', RECU, 'Leaked instance'].join('\r\n');
  const r = parseReceipt(bruit);
  assert.equal(r.succeeded, false);
  assert.equal(r.diag.kills_du_bot, 0);
});

// --- ce que le lot NE change PAS : la validation reste STRICTE ---------------------------

test('SANS diagnostic, le recu reste valide et `diag` vaut null', () => {
  // Retrocompatibilite : snake, breakout_v2, tetris n emettent PAS ce canal. Leur
  // comportement doit etre STRICTEMENT inchange — `null`, jamais un objet vide qui
  // laisserait croire a un diagnostic vierge.
  const r = parseReceipt(['Godot Engine', 'FORGE_TRIAL {"succeeded":true,"ticks":42}'].join('\n'));
  assert.equal(r.succeeded, true);
  assert.equal(r.ticks, 42);
  assert.equal(r.diag, null);
});

test('un recu ABSENT reste une ERREUR, meme avec un diagnostic present', () => {
  // LE CAS QUI COMPTE : un diagnostic ne remplace JAMAIS un recu. Sans cette garde, une
  // sortie sans verdict pourrait passer pour exploitable.
  assert.throws(() => parseReceipt(DIAG), /aucun recu FORGE_TRIAL/);
});

test('DEUX recus restent ambigus, donc une ERREUR', () => {
  assert.throws(() => parseReceipt([RECU, RECU].join('\n')), /ambigu/);
});

test('un recu ILLISIBLE reste une ERREUR', () => {
  assert.throws(() => parseReceipt('FORGE_TRIAL {pas du json'), /illisible/);
});

test('un champ `succeeded` non booleen reste une ERREUR', () => {
  assert.throws(() => parseReceipt('FORGE_TRIAL {"succeeded":"oui","ticks":null}'),
                /succeeded/);
});

// --- robustesse du canal AJOUTE ----------------------------------------------------------

test('un diagnostic ILLISIBLE ne casse PAS le recu', () => {
  // Best-effort strict, meme discipline que `registryDivergences` : le diagnostic est un
  // CONFORT, jamais une condition. Un JSON casse cote diag ne doit pas perdre un verdict
  // valide — sinon on aurait rendu la preuve dependante de son commentaire.
  const r = parseReceipt(['FORGE_DIAG {ceci nest pas du json', RECU].join('\n'));
  assert.equal(r.succeeded, false);
  assert.equal(r.diag, null);
});

test('DEUX diagnostics : le premier gagne, sans erreur', () => {
  // Contrairement au recu, un diag en double n est pas AMBIGU au sens du verdict — il ne
  // decide de rien. On ne fabrique pas une erreur la ou il n y a pas d enjeu.
  const r = parseReceipt([DIAG, 'FORGE_DIAG {"statut":9}', RECU].join('\n'));
  assert.equal(r.diag.statut, 2);
});

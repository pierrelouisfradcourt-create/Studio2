// Tests deterministes de game_state (preuve `test` : core.game_state).
// Assertions AUX BORNES pour tuer les mutants (>=/<=/==, true/false).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  FIELD_H, PADDLE_H, WIN_SCORE, STATUS,
  initialState, readStatus, isValidStatus, isValidState,
  endStatus, isOver, restart, serveVx,
} from '../../05_SYSTEMS/game_state/state.mjs';

const MAXY = FIELD_H - PADDLE_H;

test('initialState : etat propre, observable, deterministe', () => {
  const s = initialState(1);
  assert.equal(s.status, STATUS.PLAYING);
  assert.equal(s.score.p1, 0);
  assert.equal(s.score.p2, 0);
  assert.equal(s.p1.y, MAXY / 2);
  assert.equal(s.p2.y, MAXY / 2);
  assert.equal(s.ball.x, 100);
  assert.equal(s.ball.y, 60);
  assert.equal(s.seed, 1);
  assert.deepEqual(initialState(1), initialState(1));   // reproductible
});

test('serveVx : signe pilote par seed et parite des points', () => {
  assert.ok(serveVx(1, 0) > 0);   // seed +1, 0 points joues -> vers la droite
  assert.ok(serveVx(1, 1) < 0);   // point suivant -> sens oppose
  assert.ok(serveVx(-1, 0) < 0);
});

test('isValidStatus : SEULES les 3 valeurs declarees', () => {
  assert.equal(isValidStatus(STATUS.PLAYING), true);
  assert.equal(isValidStatus(STATUS.P1_WIN), true);
  assert.equal(isValidStatus(STATUS.P2_WIN), true);
  assert.equal(isValidStatus('WIN'), false);
  assert.equal(isValidStatus(''), false);
  assert.equal(isValidStatus(undefined), false);
});

test('isValidState : vrai sur un etat sain', () => {
  assert.equal(isValidState(initialState(1)), true);
});

test('isValidState : raquette AUX BORNES valide, HORS bornes invalide', () => {
  const base = initialState(1);
  assert.equal(isValidState({ ...base, p1: { y: 0 } }), true);       // borne basse
  assert.equal(isValidState({ ...base, p1: { y: MAXY } }), true);    // borne haute
  assert.equal(isValidState({ ...base, p1: { y: -0.001 } }), false);
  assert.equal(isValidState({ ...base, p1: { y: MAXY + 0.001 } }), false);
});

test('isValidState : score entier >= 0 seulement', () => {
  const base = initialState(1);
  assert.equal(isValidState({ ...base, score: { p1: 0, p2: 5 } }), true);
  assert.equal(isValidState({ ...base, score: { p1: -1, p2: 0 } }), false);
  assert.equal(isValidState({ ...base, score: { p1: 1.5, p2: 0 } }), false);
});

test('isValidState : balle NaN / hors terrain invalide', () => {
  const base = initialState(1);
  assert.equal(isValidState({ ...base, ball: { ...base.ball, x: NaN } }), false);
  assert.equal(isValidState({ ...base, ball: { ...base.ball, y: -1 } }), false);
  assert.equal(isValidState({ ...base, ball: { ...base.ball, y: FIELD_H + 1 } }), false);
  assert.equal(isValidState({ ...base, ball: { ...base.ball, y: 0 } }), true);       // borne
  assert.equal(isValidState({ ...base, ball: { ...base.ball, y: FIELD_H } }), true); // borne
});

test('isValidState : statut non declare invalide', () => {
  assert.equal(isValidState({ ...initialState(1), status: 'BOOM' }), false);
});

test('endStatus : seuil de victoire exact (tue >=/>)', () => {
  assert.equal(endStatus({ p1: WIN_SCORE - 1, p2: 0 }), STATUS.PLAYING);
  assert.equal(endStatus({ p1: WIN_SCORE, p2: 0 }), STATUS.P1_WIN);
  assert.equal(endStatus({ p1: 0, p2: WIN_SCORE - 1 }), STATUS.PLAYING);
  assert.equal(endStatus({ p1: 0, p2: WIN_SCORE }), STATUS.P2_WIN);
  assert.equal(endStatus({ p1: 0, p2: 0 }), STATUS.PLAYING);
});

test('isOver : vrai SSI un camp a gagne', () => {
  assert.equal(isOver({ status: STATUS.PLAYING }), false);
  assert.equal(isOver({ status: STATUS.P1_WIN }), true);
  assert.equal(isOver({ status: STATUS.P2_WIN }), true);
});

test('readStatus : lit le statut courant', () => {
  assert.equal(readStatus(initialState(1)), STATUS.PLAYING);
});

test('restart : identique bit-a-bit au premier demarrage', () => {
  assert.deepEqual(restart(1), initialState(1));
  assert.deepEqual(restart(-1), initialState(-1));
});

// --- Renforcement mutation (gate) ---

// serveVx ligne 32 `dir >= 0 ? +BALL_VX : -BALL_VX` : seed neutre (0) sert vers la
// droite (tue ge->gt : `dir > 0` servirait a gauche pour dir=0).
test('serveVx : seed neutre (0) sert vers la droite (borne ge L32)', () => {
  assert.ok(serveVx(0, 0) > 0);
});

// initialState ligne 37 `seed >= 0 ? 1 : -1` : seed 0 -> seed normalise +1
// (tue ge->gt : `seed > 0` donnerait -1 pour seed=0).
test('initialState : seed 0 normalise a +1 (borne ge L37)', () => {
  assert.equal(initialState(0).seed, 1);
});

// isValidState ligne 60 `!state || typeof !== 'object'` : null rejete (tue or->and,
// qui laisserait passer null et dereferencerait state.status ; tue aussi false->true).
test('isValidState : null et non-objet rejetes (L60)', () => {
  assert.equal(isValidState(null), false);
  assert.equal(isValidState(42), false);
});

// isValidState ligne 64 `typeof y !== 'number' || Number.isNaN(y)` sur les raquettes.
test('isValidState : raquette y = NaN rejetee (or L64)', () => {
  const base = initialState(1);
  assert.equal(isValidState({ ...base, p1: { y: NaN } }), false);
});

// isValidState ligne 64 : raquette sans y numerique rejetee (tue false->true L64).
test('isValidState : raquette y non numerique rejetee (false->true L64)', () => {
  const base = initialState(1);
  assert.equal(isValidState({ ...base, p1: { y: 'x' } }), false);
  assert.equal(isValidState({ ...base, p2: { y: undefined } }), false);
});

// isValidState ligne 72 `!b || typeof b.x !== 'number' || typeof b.y !== 'number'` :
// balle nulle rejetee (tue or->and#1 qui dereferencerait b.x sur null ; tue false->true).
test('isValidState : balle nulle rejetee (or#1 + false->true L72)', () => {
  const base = initialState(1);
  assert.equal(isValidState({ ...base, ball: null }), false);
});

// isValidState ligne 72, 2e `||` : x non numerique alors que y valide -> rejete
// (tue or->and#2 : `&&` laisserait passer une balle a x invalide).
test('isValidState : balle x non numerique rejetee (or#2 L72)', () => {
  const base = initialState(1);
  assert.equal(isValidState({ ...base, ball: { x: undefined, y: 60 } }), false);
});

// Tests deterministes de game_loop (preuves `test` : core.main_loop, play.ball).
// Le no-tunnel (balle jamais traversante quelle que soit la vitesse) est LE point
// dur : teste a plusieurs vitesses, y compris tres grandes.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  FIELD_W, FIELD_H, BALL_R, P1_X, P2_X, PADDLE_H, STATUS, WIN_SCORE,
} from '../../05_SYSTEMS/game_state/state.mjs';
import { boot, step, movePaddle, MIN_PADDLE_Y, MAX_PADDLE_Y } from '../../05_SYSTEMS/game_loop/loop.mjs';
import { translate } from '../../05_SYSTEMS/input/input.mjs';

test('boot : etat initial jouable', () => {
  const s = boot(1);
  assert.equal(s.status, STATUS.PLAYING);
  assert.equal(s.ball.x, FIELD_W / 2);
});

test('movePaddle : borne bas/haut, exact', () => {
  assert.equal(movePaddle(MIN_PADDLE_Y, -1), MIN_PADDLE_Y);   // ne descend pas sous 0
  assert.equal(movePaddle(MAX_PADDLE_Y, 1), MAX_PADDLE_Y);    // ne monte pas au-dela
  assert.ok(movePaddle(50, 1) > 50);
  assert.ok(movePaddle(50, -1) < 50);
  assert.equal(movePaddle(50, 0), 50);
});

test('core.main_loop : meme etat + meme entree + meme seed -> meme suite sur N ticks', () => {
  const inputs = [
    { p1: 'up' }, { p1: 'down', p2: 'up' }, { p2: 'down' }, {}, { p1: 'up', p2: 'up' },
  ];
  function runN(n) {
    let s = boot(1);
    const trace = [];
    for (let i = 0; i < n; i += 1) {
      s = step(s, translate(inputs[i % inputs.length])).state;
      trace.push(JSON.parse(JSON.stringify(s)));
    }
    return trace;
  }
  assert.deepEqual(runN(300), runN(300));   // determinisme strict
});

test('play.ball : rebond bord HAUT (vy s inverse, event bounce)', () => {
  let s = boot(1);
  s = { ...s, ball: { x: 100, y: BALL_R + 1, vx: 0, vy: -3 } };
  const { state: ns, events } = step(s, translate({}));
  assert.ok(ns.ball.vy > 0, 'vy doit s inverser vers le bas');
  assert.ok(ns.ball.y >= BALL_R, 'balle repoussee dans le terrain');
  assert.ok(events.some((e) => e.type === 'bounce' && e.wall === 'top'));
});

test('play.ball : rebond bord BAS', () => {
  let s = boot(1);
  s = { ...s, ball: { x: 100, y: FIELD_H - BALL_R - 1, vx: 0, vy: 3 } };
  const { state: ns, events } = step(s, translate({}));
  assert.ok(ns.ball.vy < 0);
  assert.ok(events.some((e) => e.type === 'bounce' && e.wall === 'bottom'));
});

test('play.ball : rebond sur la raquette DROITE quand alignee', () => {
  let s = boot(1);
  // raquette droite centree sur y=60 ; balle arrive dessus
  s = { ...s, p2: { y: 60 - PADDLE_H / 2 }, ball: { x: P2_X - 3, y: 60, vx: 5, vy: 0 } };
  const { state: ns, events } = step(s, translate({}));
  assert.ok(ns.ball.vx < 0, 'la balle est renvoyee');
  assert.ok(ns.ball.x <= P2_X, 'jamais au-dela du plan de la raquette');
  assert.ok(events.some((e) => e.type === 'bounce' && e.paddle === 'p2'));
});

test('play.ball : PAS de rebond si la raquette droite est ailleurs (-> point)', () => {
  let s = boot(1);
  s = { ...s, p2: { y: 0 }, ball: { x: P2_X - 1, y: 110, vx: 6, vy: 0 } };
  const { state: ns, events } = step(s, translate({}));
  // la balle n a pas ete renvoyee : soit deja sortie (point), soit continue vers la droite
  assert.ok(ns.score.p1 === 1 || ns.ball.vx > 0);
  if (ns.score.p1 === 1) {
    assert.ok(events.some((e) => e.type === 'score' && e.who === 'p1'));
  }
});

test('play.ball : NO-TUNNEL a toute vitesse (jamais traversant une raquette)', () => {
  for (const speed of [10, 30, 50, 100, 300, 900]) {
    let s = boot(1);
    s = { ...s, p2: { y: 60 - PADDLE_H / 2 }, ball: { x: P2_X - 4, y: 60, vx: speed, vy: 0 } };
    const { state: ns } = step(s, translate({}));
    assert.ok(ns.ball.vx < 0, `vitesse ${speed} : la balle DOIT etre renvoyee`);
    assert.ok(ns.ball.x <= P2_X, `vitesse ${speed} : la balle a TRAVERSE la raquette (tunneling)`);
    assert.equal(ns.score.p1, 0, `vitesse ${speed} : aucun point ne doit etre marque`);
  }
});

test('play.score : sortie a droite -> EXACTEMENT un point p1, balle recentree', () => {
  let s = boot(1);
  s = { ...s, p2: { y: 0 }, ball: { x: FIELD_W - BALL_R, y: 110, vx: 5, vy: 0 } };
  const { state: ns, events } = step(s, translate({}));
  assert.equal(ns.score.p1, 1);
  assert.equal(ns.score.p2, 0);
  assert.equal(ns.ball.x, FIELD_W / 2, 'balle recentree apres le point');
  const scoreEvents = events.filter((e) => e.type === 'score');
  assert.equal(scoreEvents.length, 1);
  assert.equal(scoreEvents[0].who, 'p1');
});

test('play.score : sortie a gauche -> point p2', () => {
  let s = boot(1);
  s = { ...s, p1: { y: 0 }, ball: { x: BALL_R, y: 110, vx: -5, vy: 0 } };
  const { state: ns } = step(s, translate({}));
  assert.equal(ns.score.p2, 1);
  assert.equal(ns.score.p1, 0);
});

test('game.end : atteindre WIN_SCORE fige la partie et emet end', () => {
  let s = boot(1);
  s = { ...s, score: { p1: WIN_SCORE - 1, p2: 0 }, p2: { y: 0 },
        ball: { x: FIELD_W - BALL_R, y: 110, vx: 5, vy: 0 } };
  const { state: ns, events } = step(s, translate({}));
  assert.equal(ns.status, STATUS.P1_WIN);
  assert.ok(events.some((e) => e.type === 'end' && e.status === STATUS.P1_WIN));
});

test('game.loop : partie finie -> etat fige, aucun effet', () => {
  const over = { ...boot(1), status: STATUS.P1_WIN };
  const { state: ns, events } = step(over, translate({ p1: 'up' }));
  assert.deepEqual(ns, over);
  assert.equal(events.length, 0);
});

// --- Renforcement mutation (gate) : collisions raquettes AUX BORNES et cas-limites.
// La raquette GAUCHE (p1, plan P1_X) etait quasi non testee ; ces cas ferment les
// mutants survivants de hitsPaddle (ligne 29) et des gardes balayees (lignes 56/67).

// hitsPaddle ligne 29 `ballY >= paddleTopY` : contact EXACT sur le bord HAUT de la
// raquette gauche doit rebondir (tue ge->gt : `>` raterait l'egalite).
test('play.ball : contact exact bord HAUT raquette gauche -> rebond (ge)', () => {
  let s = boot(1);
  s = { ...s, p1: { y: 40 }, ball: { x: 12, y: 40, vx: -4, vy: 0 } }; // yHit = 40 = p1.y
  const { state: ns, events } = step(s, translate({}));
  assert.ok(ns.ball.vx > 0, 'contact au bord haut exact DOIT renvoyer la balle');
  assert.ok(events.some((e) => e.type === 'bounce' && e.paddle === 'p1'));
});

// hitsPaddle ligne 29 `ballY <= paddleTopY + PADDLE_H` : contact EXACT sur le bord
// BAS de la raquette gauche doit rebondir (tue le->lt : `<` raterait l'egalite).
test('play.ball : contact exact bord BAS raquette gauche -> rebond (le)', () => {
  let s = boot(1);
  s = { ...s, p1: { y: 40 }, ball: { x: 12, y: 64, vx: -4, vy: 0 } }; // yHit = 64 = p1.y+PADDLE_H
  const { state: ns } = step(s, translate({}));
  assert.ok(ns.ball.vx > 0, 'contact au bord bas exact DOIT renvoyer la balle');
});

// hitsPaddle ligne 29 `>= && <=` : une balle qui franchit le plan AU-DESSUS de la
// raquette ne doit PAS rebondir (tue and->or : `||` bouncerait a tort).
test('play.ball : balle au-dessus de la raquette gauche -> PAS de rebond (and)', () => {
  let s = boot(1);
  s = { ...s, p1: { y: 60 }, ball: { x: 12, y: 30, vx: -4, vy: 0 } }; // yHit=30 < p1.y=60
  const { state: ns } = step(s, translate({}));
  assert.ok(ns.ball.vx < 0, 'balle hors de la raquette ne doit pas etre renvoyee');
});

// Garde balayee gauche ligne 56 `x - BALL_R >= P1_X` : balle demarrant EXACTEMENT
// sur le plan doit etre prise en compte (tue ge->gt).
test('play.ball : depart exact sur le plan gauche -> rebond (ge L56)', () => {
  let s = boot(1);
  s = { ...s, p1: { y: 40 }, ball: { x: 8, y: 50, vx: -4, vy: 0 } }; // x-BALL_R = 6 = P1_X
  const { state: ns } = step(s, translate({}));
  assert.ok(ns.ball.vx > 0, 'franchissement demarrant sur le plan DOIT rebondir');
});

// Garde balayee gauche ligne 56 `nx - BALL_R <= P1_X` : balle finissant EXACTEMENT
// sur le plan doit etre prise en compte (tue le->lt) — deja frole par le cas ge.
test('play.ball : arrivee exacte sur le plan gauche -> rebond (le L56)', () => {
  let s = boot(1);
  s = { ...s, p1: { y: 40 }, ball: { x: 12, y: 50, vx: -4, vy: 0 } }; // nx-BALL_R = 6 = P1_X
  const { state: ns } = step(s, translate({}));
  assert.ok(ns.ball.vx > 0, 'franchissement finissant sur le plan DOIT rebondir');
});

// Garde balayee gauche ligne 56, 1er `&&` (vx<0 && cond) : une balle DEJA au-dela du
// plan (cond1 faux) ne doit pas rebondir (tue and->or#1 : `||` entrerait a tort).
test('play.ball : balle deja au-dela du plan gauche -> PAS de rebond (and#1 L56)', () => {
  let s = boot(1);
  s = { ...s, p1: { y: 40 }, ball: { x: 7, y: 50, vx: -4, vy: 0 } }; // x-BALL_R=5 < P1_X
  const { state: ns } = step(s, translate({}));
  assert.ok(ns.ball.vx < 0, 'balle passee : aucun rebond gauche');
});

// Garde balayee gauche ligne 56, 2e `&&` (... && cond2) : une balle allant a DROITE
// pres du mur gauche ne doit pas rebondir a gauche (tue and->or#2 : `||` entrerait).
test('play.ball : balle vers la droite pres du mur gauche -> PAS de rebond (and#2 L56)', () => {
  let s = boot(1);
  s = { ...s, p1: { y: 40 }, ball: { x: 5, y: 50, vx: 2, vy: 0 } }; // vx>0, nx-BALL_R=5<=P1_X
  const { state: ns } = step(s, translate({}));
  assert.ok(ns.ball.vx > 0, 'balle allant a droite : aucun rebond gauche');
});

// Garde balayee droite ligne 67 `nx + BALL_R >= P2_X` : arrivee EXACTE sur le plan
// droit doit rebondir (tue ge->gt).
test('play.ball : arrivee exacte sur le plan droit -> rebond (ge L67)', () => {
  let s = boot(1);
  s = { ...s, p2: { y: 40 }, ball: { x: 188, y: 50, vx: 4, vy: 0 } }; // nx+BALL_R = 194 = P2_X
  const { state: ns } = step(s, translate({}));
  assert.ok(ns.ball.vx < 0, 'franchissement finissant sur le plan droit DOIT rebondir');
});

// Garde balayee droite ligne 67 `x + BALL_R <= P2_X` : depart EXACT sur le plan droit
// doit rebondir (tue le->lt).
test('play.ball : depart exact sur le plan droit -> rebond (le L67)', () => {
  let s = boot(1);
  s = { ...s, p2: { y: 40 }, ball: { x: 192, y: 50, vx: 4, vy: 0 } }; // x+BALL_R = 194 = P2_X
  const { state: ns } = step(s, translate({}));
  assert.ok(ns.ball.vx < 0, 'franchissement demarrant sur le plan droit DOIT rebondir');
});

// Garde balayee droite ligne 67, 1er `&&` : balle DEJA au-dela du plan droit -> pas
// de rebond (tue and->or#1).
test('play.ball : balle deja au-dela du plan droit -> PAS de rebond (and#1 L67)', () => {
  let s = boot(1);
  s = { ...s, p2: { y: 40 }, ball: { x: 193, y: 50, vx: 4, vy: 0 } }; // x+BALL_R=195 > P2_X
  const { state: ns } = step(s, translate({}));
  assert.ok(ns.ball.vx > 0, 'balle passee : aucun rebond droit');
});

// Garde balayee droite ligne 67, 2e `&&` : balle allant a GAUCHE pres du mur droit ->
// pas de rebond droit (tue and->or#2).
test('play.ball : balle vers la gauche pres du mur droit -> PAS de rebond (and#2 L67)', () => {
  let s = boot(1);
  s = { ...s, p2: { y: 40 }, ball: { x: 197, y: 50, vx: -2, vy: 0 } }; // vx<0, nx+BALL_R>=P2_X
  const { state: ns } = step(s, translate({}));
  assert.ok(ns.ball.vx < 0, 'balle allant a gauche : aucun rebond droit');
});

// PONG — game_loop (LOGIQUE PURE).
// Fournit game.boot, game.loop, play.paddle, play.ball, play.score.
// GARDE-FOU (d) : fonction pure de (state, action) -> {state, events}. Aucun rendu,
// aucune I/O, aucun temps reel, aucun alea. allowed_deps=[game_state] : n'importe
// QUE game_state (les actions normalisees viennent du systeme input via l'appelant).

import {
  FIELD_W, FIELD_H, PADDLE_H, PADDLE_SPEED, BALL_R, BALL_VX,
  P1_X, P2_X, STATUS, WIN_SCORE,
  initialState, serveVx, endStatus,
} from '../game_state/state.mjs';
import { clampPaddle } from '../input/input.mjs';

// play.playable_speed — cadence NOMINALE de la boucle temps reel (le loop LOGIQUE est
// tick-a-tick ; TICK_HZ est le taux auquel l'adaptateur avance l'etat, cf. main.mjs
// requestAnimationFrame ~60 Hz). Constante PURE (un nombre), pas de l'I/O : elle sert
// a traduire des ticks en secondes pour verifier la bande de vitesse jouable.
export const TICK_HZ = 60;

// Distance horizontale que la balle parcourt du point de service (centre du terrain)
// jusqu'au plan d'une raquette. C'est la fenetre d'anticipation offerte au joueur au
// service. Symetrique gauche/droite : FIELD_W/2 - P1_X === P2_X - FIELD_W/2.
export const SERVE_CROSS_DIST = FIELD_W / 2 - P1_X;

// play.playable_speed — temps (en SECONDES) que met la balle de service a parcourir
// SERVE_CROSS_DIST a la vitesse BALL_VX, cadence TICK_HZ. Derive PUREMENT des
// constantes (aucune I/O, aucun etat). C'est la grandeur que la Genre Bible Pong
// contraint dans une bande jouable (genre.pong.playable_speed_range).
export function ballCrossingTimeSeconds(ballVx = BALL_VX, tickHz = TICK_HZ) {
  return SERVE_CROSS_DIST / (ballVx * tickHz);
}

// game.boot — amener le jeu de rien a un etat initial jouable et observable.
export function boot(seed = 1) {
  return initialState(seed);
}

const MIN_PADDLE_Y = 0;
const MAX_PADDLE_Y = FIELD_H - PADDLE_H;

// play.paddle — deplace une raquette selon la direction {-1,0,1} et BORNE au terrain.
function movePaddle(y, dir) {
  return clampPaddle(y + dir * PADDLE_SPEED, MIN_PADDLE_Y, MAX_PADDLE_Y);
}

// La balle touche-t-elle la raquette au plan `paddleX`, sachant sa portee verticale ?
function hitsPaddle(ballY, paddleTopY) {
  return ballY >= paddleTopY && ballY <= paddleTopY + PADDLE_H;
}

// play.ball — avance la balle avec collision BALAYEE (swept) : on teste le
// FRANCHISSEMENT du plan de la raquette entre l'ancienne et la nouvelle position,
// pas seulement la position finale. C'est ce qui empeche le tunneling a toute
// vitesse (play.ball : "ne traverse jamais une raquette, quelle que soit sa vitesse").
// Renvoie {ball, events, scored} ou scored ∈ {null,'p1','p2'}.
function stepBall(state) {
  const b = state.ball;
  const events = [];
  let { x, y, vx, vy } = b;
  let nx = x + vx;
  let ny = y + vy;

  // --- rebonds haut/bas (bords horizontaux) ---
  if (ny - BALL_R < 0) {
    ny = BALL_R + (BALL_R - ny);   // reflexion geometrique
    vy = -vy;
    events.push({ type: 'bounce', wall: 'top' });
  } else if (ny + BALL_R > FIELD_H) {
    ny = (FIELD_H - BALL_R) - (ny + BALL_R - FIELD_H);
    vy = -vy;
    events.push({ type: 'bounce', wall: 'bottom' });
  }

  // --- collision raquette gauche (plan P1_X), balle allant vers la gauche ---
  if (vx < 0 && x - BALL_R >= P1_X && nx - BALL_R <= P1_X) {
    // y interpole au moment du franchissement du plan
    const t = (x - BALL_R - P1_X) / (x - nx);   // 0..1
    const yHit = y + (ny - y) * t;
    if (hitsPaddle(yHit, state.p1.y)) {
      nx = P1_X + BALL_R + (P1_X + BALL_R - nx);   // renvoi
      vx = -vx;
      events.push({ type: 'bounce', paddle: 'p1' });
    }
  }
  // --- collision raquette droite (plan P2_X), balle allant vers la droite ---
  if (vx > 0 && x + BALL_R <= P2_X && nx + BALL_R >= P2_X) {
    const t = (P2_X - (x + BALL_R)) / (nx - x);
    const yHit = y + (ny - y) * t;
    if (hitsPaddle(yHit, state.p2.y)) {
      nx = P2_X - BALL_R - (nx + BALL_R - P2_X);
      vx = -vx;
      events.push({ type: 'bounce', paddle: 'p2' });
    }
  }

  // --- point marque : la balle a franchi un bord vertical sans etre renvoyee ---
  let scored = null;
  if (nx - BALL_R < 0) {
    scored = 'p2';   // sortie a gauche -> point pour la droite
  } else if (nx + BALL_R > FIELD_W) {
    scored = 'p1';   // sortie a droite -> point pour la gauche
  }

  return { ball: { x: nx, y: ny, vx, vy }, events, scored };
}

// game.loop — un tick DETERMINISTE. `action` = {p1,p2} directions normalisees
// (produites par le systeme input). Renvoie {state, events}. Ne mute pas l'entree.
export function step(state, action = { p1: 0, p2: 0 }) {
  if (state.status !== STATUS.PLAYING) {
    return { state, events: [] };   // partie finie : etat fige, aucun effet
  }
  const events = [];

  const p1y = movePaddle(state.p1.y, action.p1 | 0);
  const p2y = movePaddle(state.p2.y, action.p2 | 0);

  const { ball, events: ballEvents, scored } = stepBall({
    ...state, p1: { y: p1y }, p2: { y: p2y },
  });
  events.push(...ballEvents);

  let score = state.score;
  let nextBall = ball;
  if (scored) {
    score = { ...state.score, [scored]: state.score[scored] + 1 };
    events.push({ type: 'score', who: scored });
    // service redemarre au centre, vers le camp qui vient d'encaisser
    const pointsPlayed = score.p1 + score.p2;
    const towardLoser = scored === 'p1' ? 1 : -1;   // p1 marque -> sert vers la droite (p2)
    nextBall = {
      x: FIELD_W / 2, y: FIELD_H / 2,
      vx: towardLoser >= 0 ? Math.abs(serveVx(state.seed, pointsPlayed))
                           : -Math.abs(serveVx(state.seed, pointsPlayed)),
      vy: state.ball.vy > 0 ? state.ball.vy : -state.ball.vy,
    };
  }

  const status = endStatus(score);
  if (status !== STATUS.PLAYING) {
    events.push({ type: 'end', status });
  }

  return {
    state: { ...state, p1: { y: p1y }, p2: { y: p2y }, ball: nextBall, score, status },
    events,
  };
}

export { movePaddle, stepBall, hitsPaddle, MIN_PADDLE_Y, MAX_PADDLE_Y, WIN_SCORE };

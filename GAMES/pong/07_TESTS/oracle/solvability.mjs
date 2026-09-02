// PONG — harnais de SOLVABILITE (R9). Un BOT joue une partie complete de bout en
// bout ; l'issue est definie (quelqu'un gagne). Porte les preuves `bot_action` du
// squelette : core.boot, core.input, core.end_condition, core.restart, play.paddle,
// play.score. GARDE-FOU (d) respecte : ce harnais orchestre la logique pure, il ne
// rend rien et ne fait aucune I/O (hors le main CLI d'impression du recu).

import {
  FIELD_H, PADDLE_H, WIN_SCORE, STATUS,
  initialState, isValidState, isOver, restart,
} from '../../05_SYSTEMS/game_state/state.mjs';
import { translate } from '../../05_SYSTEMS/input/input.mjs';
import { boot, step, MIN_PADDLE_Y, MAX_PADDLE_Y } from '../../05_SYSTEMS/game_loop/loop.mjs';

const PADDLE_MID = PADDLE_H / 2;

// Bot "suiveur" : centre la raquette sur la balle. Bot "fuyard" : s'en eloigne
// (garantit des points encaisses -> la partie se termine deterministe).
function trackerDir(paddleY, ballY) {
  const center = paddleY + PADDLE_MID;
  if (ballY < center - 0.5) return 'up';
  if (ballY > center + 0.5) return 'down';
  return null;
}
function fleeDir(paddleY, ballY) {
  const center = paddleY + PADDLE_MID;
  return ballY > center ? 'up' : 'down';   // va a l'oppose de la balle
}

function paddlesBounded(s) {
  return s.p1.y >= MIN_PADDLE_Y && s.p1.y <= MAX_PADDLE_Y &&
         s.p2.y >= MIN_PADDLE_Y && s.p2.y <= MAX_PADDLE_Y;
}

// Joue une partie complete avec deux bots. Verifie a CHAQUE tick : etat valide,
// raquettes bornees, et que tout point marque incremente EXACTEMENT un camp de 1.
export function playFullGame(seed = 1, maxTicks = 200000) {
  let s = boot(seed);
  let ticks = 0;
  let allValid = isValidState(s);
  let allBounded = paddlesBounded(s);
  let exactlyOnePerPoint = true;
  let scoreEvents = 0;
  let prev = { p1: s.score.p1, p2: s.score.p2 };

  while (!isOver(s) && ticks < maxTicks) {
    const raw = { p1: trackerDir(s.p1.y, s.ball.y), p2: fleeDir(s.p2.y, s.ball.y) };
    const action = translate(raw);
    const { state: ns, events } = step(s, action);
    s = ns;
    ticks += 1;

    if (!isValidState(s)) allValid = false;
    if (!paddlesBounded(s)) allBounded = false;

    const dP1 = s.score.p1 - prev.p1;
    const dP2 = s.score.p2 - prev.p2;
    if (events.some((e) => e.type === 'score')) {
      scoreEvents += 1;
      // exactement un camp gagne exactement 1 point sur ce tick
      if (!((dP1 === 1 && dP2 === 0) || (dP1 === 0 && dP2 === 1))) {
        exactlyOnePerPoint = false;
      }
    } else if (dP1 !== 0 || dP2 !== 0) {
      exactlyOnePerPoint = false;   // score bouge sans evenement 'score'
    }
    prev = { p1: s.score.p1, p2: s.score.p2 };
  }

  const finished = isOver(s);
  const winner = s.status === STATUS.P1_WIN ? 'p1'
    : s.status === STATUS.P2_WIN ? 'p2' : null;
  return {
    finished, winner, ticks, status: s.status,
    finalScore: { ...s.score },
    allValid, allBounded, exactlyOnePerPoint, scoreEvents,
    reachedWinScore: s.score.p1 >= WIN_SCORE || s.score.p2 >= WIN_SCORE,
  };
}

// core.input + play.paddle : une action emise DEPLACE la raquette de facon
// observable, et la raquette reste bornee meme entree maintenue longtemps.
export function inputMovesPaddle(seed = 1, holdTicks = 100) {
  let s = boot(seed);
  const y0 = s.p1.y;
  let moved = false;
  let bounded = true;
  for (let i = 0; i < holdTicks; i += 1) {
    const action = translate({ p1: 'down', p2: null });
    s = step(s, action).state;
    if (s.p1.y !== y0) moved = true;
    if (!(s.p1.y >= MIN_PADDLE_Y && s.p1.y <= MAX_PADDLE_Y)) bounded = false;
  }
  return { moved, bounded, endedAtMax: s.p1.y === MAX_PADDLE_Y, y0, y1: s.p1.y };
}

// core.restart : apres une partie finie, un nouvel etat initial est IDENTIQUE au
// premier demarrage (aucun residu).
export function restartIsClean(seed = 1) {
  const first = boot(seed);
  const game = playFullGame(seed);
  const fresh = restart(seed);
  const equal = JSON.stringify(fresh) === JSON.stringify(first);
  return { finishedBeforeRestart: game.finished, restartEqualsFirstBoot: equal, fresh, first };
}

// core.boot : lancement -> etat initial atteint, observable, sans erreur.
export function bootReachesInitial(seed = 1) {
  const s = boot(seed);
  return {
    valid: isValidState(s),
    status: s.status,
    isPlaying: s.status === STATUS.PLAYING,
    scoreZero: s.score.p1 === 0 && s.score.p2 === 0,
    matchesInitial: JSON.stringify(s) === JSON.stringify(initialState(seed)),
  };
}

// Recu global : tous les volets bot_action verts ?
export function runSolvability(seed = 1) {
  const bootR = bootReachesInitial(seed);
  const inputR = inputMovesPaddle(seed);
  const gameR = playFullGame(seed);
  const restartR = restartIsClean(seed);

  const checks = {
    boot_reaches_initial: bootR.valid && bootR.isPlaying && bootR.scoreZero && bootR.matchesInitial,
    input_moves_paddle: inputR.moved && inputR.bounded,
    paddle_bounded_when_held: inputR.bounded && inputR.endedAtMax,
    game_finishes: gameR.finished,
    winner_defined: gameR.winner === 'p1' || gameR.winner === 'p2',
    end_never_undefined: gameR.status !== STATUS.PLAYING,
    score_exactly_one_per_point: gameR.exactlyOnePerPoint && gameR.scoreEvents > 0,
    state_always_valid: gameR.allValid,
    paddles_always_bounded: gameR.allBounded,
  };
  const passed = Object.values(checks).every(Boolean);
  return { passed, checks, boot: bootR, input: inputR, game: gameR, restart: restartR };
}

// CLI : imprime le recu JSON. Exit 0 si SOLVABLE, 1 sinon (garde e2e reelle).
if (import.meta.url === `file://${process.argv[1]}` ||
    process.argv[1]?.endsWith('solvability.mjs')) {
  const report = runSolvability(1);
  process.stdout.write(JSON.stringify(report, null, 1) + '\n');
  process.exit(report.passed ? 0 : 1);
}

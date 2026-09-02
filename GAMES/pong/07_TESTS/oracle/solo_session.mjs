// PONG — harnais bot_action SOLO (play.solo_opponent). Prouve qu'une partie SOLO
// complete se joue de bout en bout :
//   - camp DROIT (p2) tenu par l'IA de jeu (05_SYSTEMS/input/ai.mjs), DISTINCTE du bot
//     de solvabilite (celui-ci a une latence NULLE et sert d'outil de test) ;
//   - camp GAUCHE (p1) tenu par un PROXY joueur -- outil de test DETERMINISTE dont le
//     seul role est de faire TERMINER la partie (il joue "fuyard", encaisse) : ce n'est
//     PAS l'adversaire, c'est le stand-in du joueur humain ;
//   - la partie atteint un etat de fin defini (P1_WIN ou P2_WIN).
// GARDE-FOU (d) : orchestre la logique pure, aucun rendu, aucune I/O (hors main CLI).
import { boot, step } from '../../05_SYSTEMS/game_loop/loop.mjs';
import { translate } from '../../05_SYSTEMS/input/input.mjs';
import { isOver, isValidState, STATUS, PADDLE_H } from '../../05_SYSTEMS/game_state/state.mjs';
import { soloAiDir } from '../../05_SYSTEMS/input/ai.mjs';

const MID = PADDLE_H / 2;

// Proxy JOUEUR "fuyard" (outil de test) : s'eloigne de la balle -> encaisse -> la
// partie se termine deterministe (l'IA gagne). N'est PAS un adversaire jouable.
function humanProxyFleeDir(paddleY, ballY) {
  const c = paddleY + MID;
  return ballY > c ? 'up' : 'down';
}

export function playSoloGame(seed = 1, maxTicks = 200000) {
  let s = boot(seed);
  let ticks = 0;
  let allValid = isValidState(s);
  let aiMoved = false;
  const startP2 = s.p2.y;
  while (!isOver(s) && ticks < maxTicks) {
    const raw = {
      p1: humanProxyFleeDir(s.p1.y, s.ball.y),   // proxy joueur (gauche), encaisse
      p2: soloAiDir('p2', s.p2.y, s.ball),       // IA de jeu (droite)
    };
    s = step(s, translate(raw)).state;
    ticks += 1;
    if (!isValidState(s)) allValid = false;
    if (s.p2.y !== startP2) aiMoved = true;
  }
  const finished = isOver(s);
  const winner = s.status === STATUS.P1_WIN ? 'p1'
    : s.status === STATUS.P2_WIN ? 'p2' : null;
  return {
    finished, winner, ticks, status: s.status,
    finalScore: { ...s.score }, allValid, aiMoved,
  };
}

export function runSoloSession(seed = 1) {
  const g = playSoloGame(seed);
  const checks = {
    solo_game_finishes: g.finished,
    winner_defined: g.winner === 'p1' || g.winner === 'p2',
    end_never_undefined: g.status !== STATUS.PLAYING,
    ai_actually_plays: g.aiMoved,          // l'IA a bouge : adversaire actif, pas passif
    state_always_valid: g.allValid,
  };
  const passed = Object.values(checks).every(Boolean);
  return { passed, checks, game: g };
}

if (import.meta.url === `file://${process.argv[1]}` ||
    process.argv[1]?.endsWith('solo_session.mjs')) {
  const report = runSoloSession(1);
  process.stdout.write(JSON.stringify(report, null, 1) + '\n');
  process.exit(report.passed ? 0 : 1);
}

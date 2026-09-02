// PONG — IA SOLO (LOGIQUE PURE). Fournit game.solo_opponent.
// Un adversaire automatique JOUABLE pour le mode 1 joueur, EXPRESSEMENT DISTINCT du
// bot de solvabilite (07_TESTS/oracle/solvability.mjs) : celui-ci a une latence de
// reaction NULLE (suit toujours la balle, deadzone 0.5) et sert d'OUTIL DE TEST
// interne, jamais d'adversaire. Cette IA-ci a une latence de reaction NON NULLE :
//   - elle N'ANTICIPE PAS : elle ne suit la balle que lorsque celle-ci est lancee
//     VERS son camp (signe de ball.vx) ; tant que la balle s'eloigne, elle revient
//     au centre du terrain -> fenetre d'attaque exploitable par le joueur ;
//   - elle a une DEADZONE large (AI_DEADZONE) : elle tolere un desalignement, ce qui
//     la rend battable a l'angle.
// GARDE-FOU (d) : aucune I/O, aucun temps reel, aucun alea. allowed_deps=[game_state].
import { PADDLE_H, FIELD_H } from '../game_state/state.mjs';

const PADDLE_MID = PADDLE_H / 2;
const FIELD_MID = FIELD_H / 2;

// Deadzone de l'IA solo : bien plus large que celle du tracker de solvabilite (0.5).
// C'est l'imperfection qui rend l'adversaire battable (contrat play.solo_opponent).
export const AI_DEADZONE = 4;

// Direction ('up'|'down'|null) pour amener `center` vers `target` avec une deadzone.
// Vocabulaire d'entree identique a input.translate ('up' = vers le haut = y decroit).
function toward(center, target, deadzone) {
  if (target < center - deadzone) return 'up';
  if (target > center + deadzone) return 'down';
  return null;
}

// soloAiDir — direction voulue par l'IA pour la raquette `side` ('p1' gauche / 'p2'
// droite), au vu de sa position `paddleY` et de la balle `ball`.
// Distinct du tracker de solvabilite : reagit UNIQUEMENT quand la balle vient vers
// son camp, sinon recentre. (side === 'p2' : plan droit, la balle vient si vx > 0.)
export function soloAiDir(side, paddleY, ball) {
  const center = paddleY + PADDLE_MID;
  const approaching = side === 'p2' ? ball.vx > 0 : ball.vx < 0;
  if (approaching) {
    return toward(center, ball.y, AI_DEADZONE);   // suit la balle qui arrive
  }
  return toward(center, FIELD_MID, AI_DEADZONE);   // balle qui part : revient au centre
}

// soloAction — action brute {p1,p2} d'une partie SOLO : le joueur humain controle
// `humanSide` (son entree brute = `humanRaw`), l'IA controle l'autre camp. A passer a
// input.translate() comme n'importe quelle entree brute.
export function soloAction(humanSide, humanRaw, state) {
  const aiSide = humanSide === 'p1' ? 'p2' : 'p1';
  const aiDir = soloAiDir(aiSide, state[aiSide].y, state.ball);
  return { [humanSide]: humanRaw, [aiSide]: aiDir };
}

export { toward, PADDLE_MID, FIELD_MID };

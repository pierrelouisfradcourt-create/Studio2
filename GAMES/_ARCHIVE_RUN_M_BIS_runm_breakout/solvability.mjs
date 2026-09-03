// Solvabilité — un bot joue et doit atteindre la victoire
import { GameState } from './engine.mjs';
import { ProgressionState } from './progression.mjs';

const DT = 16;

function measureEnvelope(seed = 1) {
  const g = new GameState();
  const initialLives = g.lives;
  g.step(DT, { paddleLeft: false, paddleRight: false });

  return {
    width: g.width,
    height: g.height,
    paddleSpeed: 400,
    maxLives: initialLives,
    ballSpeed: Math.sqrt(g.ball.vx ** 2 + g.ball.vy ** 2),
  };
}

function unreachableObjectives(env, seed = 1) {
  const unreachable = [];
  const g = new GameState();

  // Vérifier que les briques sont atteignables
  const screen1Bricks = g.screen1.length;
  if (screen1Bricks === 0) {
    unreachable.push({ what: 'écran 1 vide', issue: 'pas de briques à casser' });
  }

  const screen2Bricks = g.screen2.length;
  if (screen2Bricks === 0) {
    unreachable.push({ what: 'écran 2 vide', issue: 'pas de briques à casser' });
  }

  return unreachable;
}

function playWithPolicy(seed, policy) {
  const g = new GameState();
  const prog = new ProgressionState();

  for (let step = 0; step < 10000 && !prog.isGameOver(); step++) {
    const view = g.view();
    const intents = decidePolicy(view, policy);
    g.step(DT, intents);
    prog.update(view);

    if (prog.isGameOver()) break;
  }

  return {
    won: prog.isWon(),
    lost: prog.isGameOver() && !prog.isWon(),
    score: g.score,
    bricesDestroyed: g.screen1.filter(b => !b.alive).length + g.screen2.filter(b => !b.alive).length,
  };
}

function decidePolicy(view, policy) {
  // Politique simple: paddle suit la balle horizontalement
  const paddleCenter = view.paddle.x + view.paddle.width / 2;
  const ballX = view.ball.x;

  const targetX = ballX + policy;

  return {
    paddleLeft: paddleCenter > targetX + 20,
    paddleRight: paddleCenter < targetX - 20,
  };
}

function searchWinningPlan(seed) {
  let best = { won: false, score: 0, bricesDestroyed: 0, policy: 0 };

  for (let p = -200; p <= 200; p += 20) {
    const r = playWithPolicy(seed, p);
    if (r.score > best.score) {
      best = { ...r, policy: p };
    }
    if (r.won) return { solvable: true, best: { ...r, policy: p } };
  }

  return { solvable: false, best };
}

export function runSolvabilityCheck() {
  const seed = 1;
  const env = measureEnvelope(seed);
  const unreachable = unreachableObjectives(env, seed);
  const plan = searchWinningPlan(seed);

  console.log('=== ORACLE DE SOLVABILITÉ ===');
  console.log('enveloppe:', JSON.stringify(env));
  if (unreachable.length > 0) {
    for (const u of unreachable) {
      console.log(`   ✗ ${u.what} : ${u.issue}`);
    }
  }
  console.log(`plan gagnant : ${plan.solvable ? 'TROUVÉ' : 'AUCUN'}`);
  if (plan.solvable) {
    console.log(`  politique: ${plan.best.policy}, score: ${plan.best.score}`);
  } else {
    console.log(`  meilleur score: ${plan.best.score}, briques cassées: ${plan.best.bricesDestroyed}`);
  }

  const ok = plan.solvable && unreachable.length === 0;
  console.log(`\nVERDICT SOLVABILITÉ : ${ok ? 'SOLVABLE (un bot gagne)' : 'INJOUABLE'}`);
  if (!ok) {
    const reasons = [];
    if (unreachable.length > 0) reasons.push(`${unreachable.length} objectif(s) hors d'atteinte`);
    if (!plan.solvable) reasons.push('aucune politique n\'atteint la victoire');
    console.log('RAISON : ' + reasons.join(' ; '));
  }

  return ok;
}

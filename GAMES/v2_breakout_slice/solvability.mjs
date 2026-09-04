#!/usr/bin/env node
// Oracle de SOLVABILITÉ — un bot JOUE et doit GAGNER réellement.
// Ne teste pas les mécaniques en isolation : il mesure l'enveloppe d'action du
// moteur (raquette pilotée au clavier, rien d'autre) et vérifie que l'objectif
// requis — mur entièrement détruit — y est atteignable, seed après seed.
//
// Usage : node solvability.mjs [max_ticks] [nb_essais]

import { Engine, STATE_WON, STATE_PLAYING, DIR_LEFT, DIR_RIGHT } from './engine.mjs';

const MAX_TICKS = Number.parseInt(process.argv[2] ?? '30000', 10);
const TRIALS = Number.parseInt(process.argv[3] ?? '10', 10);
// Marge morte du pilote : il ne recentre pas la raquette au pixel près, il joue
// avec la même imprécision qu'un joueur — l'enveloppe mesurée reste celle du jeu.
const DEAD_ZONE = 4;

/** Pilote : la seule action disponible est l'intention clavier gauche/droite. */
function botIntent(engine) {
  const paddleCenter = engine.paddle.x + engine.paddle.width / 2;
  if (engine.ball.x < paddleCenter - DEAD_ZONE) return DIR_LEFT;
  if (engine.ball.x > paddleCenter + DEAD_ZONE) return DIR_RIGHT;
  return null;
}

function playTrial(seed) {
  const engine = new Engine({ seed });
  let ticks = 0;
  while (ticks < MAX_TICKS && engine.state === STATE_PLAYING) {
    engine.tick(botIntent(engine));
    ticks++;
  }
  return {
    seed,
    ticks,
    state: engine.state,
    bricksRemaining: engine.bricksRemaining,
    won: engine.state === STATE_WON,
  };
}

function main() {
  const trials = [];
  for (let i = 0; i < TRIALS; i++) {
    trials.push(playTrial(i + 1));
  }

  const wins = trials.filter((trial) => trial.won).length;
  const timeouts = trials.filter((trial) => trial.state === STATE_PLAYING).length;
  const losses = trials.length - wins - timeouts;
  const worstTicks = trials.reduce((max, trial) => Math.max(max, trial.ticks), 0);
  const passRate = (wins / trials.length) * 100;

  const receipt = {
    wins,
    losses,
    timeouts,
    pass_rate: Number(passRate.toFixed(1)),
    total_trials: trials.length,
    worst_ticks: worstTicks,
    max_ticks: MAX_TICKS,
  };
  console.log(`FORGE_ORACLE solvability ${JSON.stringify(receipt, null, 2)}`);
  for (const trial of trials) {
    console.log(
      `  seed=${trial.seed} state=${trial.state} ticks=${trial.ticks} ` +
      `briques_restantes=${trial.bricksRemaining}`);
  }

  // Exigence : le bot gagne TOUTES les parties. Une seule défaite/timeout = rouge.
  const allWon = wins === trials.length;
  if (allWon) {
    console.log('SOLVABILITY: PASS');
    process.exit(0);
  }
  console.error('SOLVABILITY: FAIL');
  process.exit(1);
}

main();

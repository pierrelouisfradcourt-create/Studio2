// Oracle de solvabilité — peut-on gagner en jouant ?

import { Engine } from './engine.mjs';
import { pathToFileURL } from "node:url";

const MAX_STEPS = 50000;

export function runBot(seed = 1) {
  const engine = new Engine({ seed });
  let steps = 0;

  while (steps < MAX_STEPS && engine.state === 'playing') {
    steps++;

    const snapshot = engine.snapshot();
    const ballX = snapshot.ball.x;
    const paddleX = snapshot.paddle.x;
    const paddleWidth = 80;
    const paddleCenter = paddleX + paddleWidth / 2;

    let intent = null;
    if (ballX < paddleCenter - 30) {
      intent = 'left';
    } else if (ballX > paddleCenter + 30) {
      intent = 'right';
    }

    engine.tick(intent);
  }

  return {
    won: engine.state === 'won',
    steps,
    state: engine.state,
    bricksRemaining: engine.bricksRemaining,
  };
}

function main() {
  const seed = 1;
  console.log("--- ORACLE DE SOLVABILITÉ — runm_breakout ---\n");

  console.log("Lancement du bot joueur...");
  const result = runBot(seed);
  console.log(`Bot : ${result.steps} steps, state=${result.state}, briques restantes=${result.bricksRemaining}\n`);

  if (result.won) {
    console.log("✓ BOT A GAGNÉ — Jeu solvable");
    console.log("RESULT: PASS");
    process.exit(0);
  } else {
    console.log(`✗ BOT N'A PAS GAGNÉ — state=${result.state}`);
    console.log("RESULT: FAIL");
    process.exit(1);
  }
}

// CLI entrypoint guard: only run main() when this file is executed directly
// (`node solvability.mjs`), never when runBot() is imported for unit testing.
if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  main();
}

// Oracle de SOLVABILITÉ — Breakout peut-il être GAGNÉ en jouant ?
//
// Les logic tests vérifient des MÉCANIQUES en isolation (rebond raquette OK si on
// positionne la balle). Ils ne prouvent jamais qu'un joueur peut GAGNER en jouant.
// Cet oracle joue vraiment : il ne dit SOLVABLE que si un bot atteint la victoire.
//
// Pattern :
//   1. mesurer l'enveloppe d'action RÉELLE du moteur (vitesse paddle, portée)
//   2. vérifier que les briques requises sont atteignables (diagnostic)
//   3. lancer un bot déterministe qui pilote via applyInput et gagne
import { BreakoutGame } from "./game.mjs";
import { pathToFileURL } from "node:url";

const DT = 16; // ms/frame simulée

// (1) Mesure l'enveloppe de mouvement réelle du paddle
function measurePaddleEnvelope(seed = 1) {
  const g = new BreakoutGame({ seed });
  const paddleX0 = g.paddle.x;
  const paddleWidth = g.paddle.width;

  // Bouge complètement à gauche
  for (let i = 0; i < 500; i++) {
    g.applyInput({ left: true });
  }
  const leftBound = g.paddle.x;

  // Remet à droite
  g.paddle.x = paddleX0;
  for (let i = 0; i < 500; i++) {
    g.applyInput({ right: true });
  }
  const rightBound = g.paddle.x;

  return {
    leftBound,
    rightBound,
    center: (leftBound + rightBound) / 2,
    range: rightBound - leftBound,
  };
}

// (2) Bot déterministe qui essaie de casser toutes les briques (R20)
export function runBot(seed, strategy = 'follow') {
  const g = new BreakoutGame({ seed });
  const maxSteps = 30000; // Augmenté pour plus de temps
  let steps = 0;

  while (steps < maxSteps && g.status === 'ACTIVE') {
    steps++;

    const state = g.view();
    const ballX = state.ball.x;
    const ballY = state.ball.y;
    const paddleX = state.paddle.x;
    const paddleWidth = state.paddle.width;
    const paddleY = state.paddle.y;
    const paddleCenter = paddleX + paddleWidth / 2;

    let input = { left: false, right: false };

    if (strategy === 'follow') {
      // Stratégie agressive : suis la balle en X de manière plus réactive
      // Si la balle est en descente et proche, réagis rapidement
      const ballDescending = state.ball.vy > 0; // Descend
      const tolerance = ballDescending ? 20 : 60; // Plus strict quand la balle descend

      if (ballX < paddleCenter - tolerance) {
        input.left = true;
      } else if (ballX > paddleCenter + tolerance) {
        input.right = true;
      }
    }

    g.step(DT, input);
  }

  return {
    won: g.status === 'WON',
    steps,
    finalStatus: g.status,
    score: g.score,
    levelIndex: g.levelIndex,
    bricksRemaining: g.bricks.filter(b => b.health > 0).length,
  };
}

// (3) Diagnostic : quelles briques sont non-cassables ?
function diagnoseReachability(seed) {
  const g = new BreakoutGame({ seed });
  const breakableCount = g.bricks.filter(b => b.health > 0).length;
  const indestructibleCount = g.bricks.filter(b => b.health === 0).length;

  return {
    total: g.bricks.length,
    breakable: breakableCount,
    indestructible: indestructibleCount,
  };
}

// Main oracle entry point
function main() {
  const seed = 1;
  console.log("=== ORACLE DE SOLVABILITÉ — Breakout ===\n");

  const paddleEnv = measurePaddleEnvelope(seed);
  console.log(`Enveloppe paddle : gauche=${paddleEnv.leftBound.toFixed(1)}, droite=${paddleEnv.rightBound.toFixed(1)}, portée=${paddleEnv.range.toFixed(1)}px\n`);

  const reachability = diagnoseReachability(seed);
  console.log(`Niveau 1 : ${reachability.total} briques (${reachability.breakable} cassables, ${reachability.indestructible} indestructibles)\n`);

  console.log("Lancement du bot joueur...");
  const result = runBot(seed, 'follow');
  console.log(`Bot : ${result.steps} steps, status=${result.finalStatus}, score=${result.score}, briques restantes=${result.bricksRemaining}\n`);

  if (result.won) {
    console.log("✓ BOT A GAGNÉ — Jeu solvable");
    console.log("RESULT: PASS");
    process.exit(0);
  } else {
    console.log(`✗ BOT N'A PAS GAGNÉ — status=${result.finalStatus}, briques cassées=${reachability.breakable - result.bricksRemaining}/${reachability.breakable}`);
    console.log("RESULT: FAIL");
    process.exit(1);
  }
}

// N'exécute main() que si ce fichier est appelé directement
if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  main();
}

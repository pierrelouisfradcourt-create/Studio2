// solvability.mjs — proves the generated levels are actually playable, not just
// mechanically correct in isolation. Exit 0 only if a deterministic bot policy
// can WIN the full run (all 3 levels) using a jump range measured from the
// real engine (never hardcoded).
//
// Steps:
//  (a) measure the real jump envelope by making the engine jump and recording
//      how far the player travels while airborne.
//  (b) verify every coin placed by the generator is within reach of that
//      measured envelope (elevated coins reachable mid-air, ground coins
//      always reachable while running).
//  (c) run a deterministic bot across several seeds and require it to WIN.

import { CollectRunnerGame, TOTAL_LEVELS, PLAYER_WIDTH } from './game.mjs';

const DT_MS = 16;
const MAX_STEPS = 200000;

function measureJumpRange() {
  const probe = new CollectRunnerGame(0xC0FFEE);
  const startX = probe.x;
  probe.step(DT_MS, { jump: true });
  let steps = 1;
  while (!probe.onGround && !probe.over && steps < MAX_STEPS) {
    probe.step(DT_MS, {});
    steps++;
  }
  if (probe.over) {
    throw new Error('jump-range probe hit an obstacle before landing — cannot measure envelope');
  }
  const range = probe.x - startX;
  if (!(range > 0)) {
    throw new Error(`measured jump range is not positive (${range}) — jump physics broken`);
  }
  return range;
}

/**
 * (b) Every coin the generator places must be reachable given the measured
 * jump range: elevated coins must sit within one jump's horizontal reach of
 * some point on the ground before them; ground coins are always reachable
 * (the player runs through every x at ground level unless it lost already).
 */
function verifyCoinsReachable(game, jumpRange) {
  const problems = [];
  for (const coin of game.coinsOnLevel) {
    if (!coin.elevated) continue; // ground coins: reachable by construction (run passes every x)
    // The coin must be within jumpRange of *some* ground point the player
    // will actually pass through before the coin — i.e. it cannot require a
    // jump longer than what the engine can physically produce.
    const nearestObstacle = game.obstaclesOnLevel
      .filter((o) => o.x <= coin.x)
      .sort((a, b) => b.x - a.x)[0];
    const takeoffX = nearestObstacle ? nearestObstacle.x : coin.x - jumpRange / 2;
    const distance = coin.x - takeoffX;
    if (distance > jumpRange) {
      problems.push(
        `level ${game.level}: elevated coin at x=${coin.x} needs ${distance}u of reach but only ${jumpRange}u is available`
      );
    }
  }
  return problems;
}

/**
 * (c) Deterministic bot: runs straight (no left/right modulation) and jumps
 * whenever an obstacle ahead is within the measured jump range, with a
 * safety margin so the flight both clears the obstacle and lands afterward.
 */
function playWithBot(seed, jumpRange) {
  const game = new CollectRunnerGame(seed);
  const triggerDistance = jumpRange * 0.5;
  const reachabilityProblems = [];
  let steps = 0;

  while (!game.over && steps < MAX_STEPS) {
    reachabilityProblems.push(...verifyCoinsReachable(game, jumpRange).filter(
      (p) => !reachabilityProblems.includes(p)
    ));

    const upcoming = game.obstaclesOnLevel
      .filter((o) => o.x + o.width >= game.x)
      .sort((a, b) => a.x - b.x)[0];

    let jump = false;
    if (upcoming && game.onGround) {
      const distance = upcoming.x - game.x;
      if (distance <= triggerDistance) jump = true;
    }

    game.step(DT_MS, { jump });
    steps++;
  }

  return {
    won: game.won,
    over: game.over,
    level: game.level,
    coins: game.coins,
    steps,
    reachabilityProblems,
  };
}

function main() {
  const jumpRange = measureJumpRange();
  console.log(`[solvability] measured real jump range: ${jumpRange.toFixed(2)} units`);

  const seeds = [1, 2, 3, 7, 42, 1234, 999999, 0xC0FFEE, 77, 3141592];
  let allGood = true;

  for (const seed of seeds) {
    const result = playWithBot(seed, jumpRange);
    const pass = result.won === true && result.reachabilityProblems.length === 0;
    console.log(
      `[solvability] seed=${seed} won=${result.won} level=${result.level}/${TOTAL_LEVELS} coins=${result.coins} steps=${result.steps} unreachableCoins=${result.reachabilityProblems.length}`
    );
    if (result.reachabilityProblems.length > 0) {
      for (const p of result.reachabilityProblems) console.log(`  [solvability]   ${p}`);
    }
    if (!pass) {
      allGood = false;
      console.log(`[solvability] SEED ${seed} FAILED — bot did not win or a coin was unreachable`);
    }
  }

  if (PLAYER_WIDTH <= 0) {
    console.log('[solvability] PLAYER_WIDTH must be positive');
    allGood = false;
  }

  if (allGood) {
    console.log('[solvability] SOLVABLE — bot wins on all seeds, all coins reachable');
    process.exit(0);
  } else {
    console.log('[solvability] NOT SOLVABLE');
    process.exit(1);
  }
}

main();

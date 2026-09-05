// solvability.mjs — is the game actually WINNABLE, not just mechanically correct in isolation?
// Run: node solvability.mjs   (exit 0 = solvable, exit 1 = not)
//
// Three checks, in order:
//   (a) Measure the REAL jump envelope by making the live engine jump and recording the
//       resulting trajectory — never hardcode expected physics numbers.
//   (b) Static reach check: every coin's required clearance height must be within the
//       measured envelope, for all 3 levels, for a handful of seeds.
//   (c) Dynamic check: a deterministic bot actually PLAYS the game end-to-end and must WIN.
//       The bot sweeps a small set of jump-timing policies; at least one must win each seed.
import { CollectRunnerGame, generateLevels, BASE_SPEED, RIGHT_MULT } from './game.mjs';

const TICK_MS = 20;
const SEEDS_TO_CHECK = [1, 2, 42, 1234, 999999];
const JUMP_LEAD_CANDIDATES = [30, 45, 60, 80, 100, 120, 150]; // px before obstacle center to press jump
const MAX_SIM_MS = 60000; // hard safety cap per playthrough attempt

let failures = 0;
function check(label, ok) {
  if (ok) {
    console.log(`[PASS] ${label}`);
  } else {
    console.log(`[FAIL] ${label}`);
    failures += 1;
  }
}

// --- (a) Measure the real jump envelope ------------------------------------------------
function measureJumpEnvelope() {
  const g = new CollectRunnerGame({ seed: 987654321 }); // arbitrary seed, only used to isolate the jump
  const input = { left: false, right: true, jump: false };
  let maxAltitude = 0;
  let airborneStartX = null;
  let airborneEndX = null;
  let elapsed = 0;
  let jumped = false;

  while (elapsed < 3000 && !g.over) {
    const doJump = !jumped;
    if (doJump) jumped = true;
    g.step(TICK_MS, { ...input, jump: doJump });
    elapsed += TICK_MS;
    const altitude = -g.y;
    if (altitude > 0) {
      if (airborneStartX === null) airborneStartX = g.x;
      airborneEndX = g.x;
      if (altitude > maxAltitude) maxAltitude = altitude;
    } else if (airborneStartX !== null) {
      break; // landed — envelope for this single jump is complete
    }
  }

  return {
    maxAltitude,
    airDistancePx: airborneEndX !== null && airborneStartX !== null ? airborneEndX - airborneStartX : 0,
  };
}

const envelope = measureJumpEnvelope();
console.log(`Measured jump envelope: maxAltitude=${envelope.maxAltitude.toFixed(1)}px, airDistance=${envelope.airDistancePx.toFixed(1)}px (at right-held speed)`);
check('measured jump reaches a positive altitude', envelope.maxAltitude > 0);
check('measured jump covers a positive horizontal distance', envelope.airDistancePx > 0);

// --- (b) Static reach check: every coin's obstacle height must fit the measured envelope
let allObstaclesReachable = true;
for (const seed of SEEDS_TO_CHECK) {
  const levels = generateLevels(seed);
  for (const level of levels) {
    for (const obs of level.obstacles) {
      // Require margin: obstacle height must stay comfortably below the measured apex.
      if (!(obs.height < envelope.maxAltitude * 0.9)) {
        allObstaclesReachable = false;
        console.log(`  unreachable: seed=${seed} obstacle height=${obs.height.toFixed(1)} vs envelope=${envelope.maxAltitude.toFixed(1)}`);
      }
    }
  }
}
check('every obstacle height is within the measured jump envelope (with margin)', allObstaclesReachable);

// --- (c) Dynamic check: a deterministic bot must actually WIN by playing ---------------
function playWithLead(seed, lead) {
  const g = new CollectRunnerGame({ seed });
  let elapsed = 0;
  while (elapsed < MAX_SIM_MS && !g.over) {
    const level = g.levels[g.level];
    const upcoming = g.obstaclesOnLevel.find((o) => o.x + o.width / 2 >= g.x);
    const distanceToObstacle = upcoming ? upcoming.x - g.x : Infinity;
    const shouldJump = g.onGround && distanceToObstacle <= lead && distanceToObstacle > -10;
    g.step(TICK_MS, { left: false, right: true, jump: shouldJump });
    elapsed += TICK_MS;
    void level;
  }
  return g;
}

function totalCoins(seed) {
  return generateLevels(seed).reduce((sum, lvl) => sum + lvl.coins.length, 0);
}

let allSeedsSolvable = true;
for (const seed of SEEDS_TO_CHECK) {
  let bestResult = null;
  for (const lead of JUMP_LEAD_CANDIDATES) {
    const result = playWithLead(seed, lead);
    if (result.won) {
      bestResult = { lead, coins: result.coins };
      break;
    }
  }
  const expectedCoins = totalCoins(seed);
  if (bestResult) {
    const fullClear = bestResult.coins === expectedCoins;
    console.log(`  seed=${seed}: WON with jump-lead=${bestResult.lead}px, coins=${bestResult.coins}/${expectedCoins}${fullClear ? '' : ' (partial coin clear!)'}`);
    if (!fullClear) allSeedsSolvable = false;
  } else {
    console.log(`  seed=${seed}: NO policy in sweep [${JUMP_LEAD_CANDIDATES.join(',')}] won`);
    allSeedsSolvable = false;
  }
}
check('a deterministic bot wins (and collects every coin) on every tested seed', allSeedsSolvable);

console.log('');
if (failures === 0) {
  console.log('SOLVABLE: all checks passed.');
  process.exit(0);
} else {
  console.log(`NOT SOLVABLE: ${failures} check(s) failed.`);
  process.exit(1);
}

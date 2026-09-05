// Oracle de SOLVABILITÉ — le chaînon manquant de la Forge pour les jeux.
//
// Les logic tests vérifient des MÉCANIQUES en isolation (collectCoin marche SI on
// place le joueur sur la pièce). Ils ne prouvent JAMAIS qu'un joueur peut GAGNER
// en jouant. Cet oracle joue vraiment : il ne dit SOLVABLE que si un bot atteint
// la victoire. Il aurait attrapé le bug « pièces hors de portée de saut ».
//
// Pattern générique (réutilisable pour tout jeu à objectif) :
//   1. mesurer l'enveloppe d'action RÉELLE du moteur (ici : hauteur de saut),
//   2. vérifier que chaque objectif requis est DANS cette enveloppe (diagnostic),
//   3. rechercher un plan gagnant (balayage de politique) ; PASS ssi un bot gagne.
import { CollectRunnerGame } from "./game.mjs";

const DT = 16;                 // ms/frame simulée
const COLLECT_TOL = 14;        // marge verticale de collecte (rayon pièce + demi-joueur)

// (1) Mesure l'enveloppe de saut réelle du moteur (aucune constante hardcodée).
function measureJumpEnvelope(seed = 1) {
  const g = new CollectRunnerGame({ seed });
  const groundY = g.player.y;
  g.jump();
  let apexY = g.player.y;
  for (let i = 0; i < 600; i++) {
    g.applyGravity(DT);
    if (g.player.y < apexY) apexY = g.player.y;
    if (g.onGround && i > 0) break;
  }
  return { groundY, apexY, reach: groundY - apexY };
}

// (2) Diagnostic de portée : quelles pièces requises sont HORS enveloppe de saut ?
function reachabilityReport(env) {
  const g = new CollectRunnerGame({ seed: 1 });
  const coins = g.view().coinsOnLevel;
  // Une pièce est atteignable si son y est au niveau OU sous l'apex (plus le joueur
  // monte, plus y est petit). apexY = point le plus haut atteignable.
  const unreachable = coins
    .map((c) => ({ x: Math.round(c.x), y: Math.round(c.y), aboveGround: Math.round(env.groundY - c.y) }))
    .filter((c) => c.y < env.apexY - COLLECT_TOL); // pièce plus haute que l'apex
  return { total: coins.length, unreachable };
}

// (3) Bot déterministe : politique « viser la pièce, sauter à distance `lead` ».
function playWithPolicy(seed, lead) {
  const g = new CollectRunnerGame({ seed });
  for (let step = 0; step < 5000 && !g.over && !g.won; step++) {
    const v = g.view();
    const p = v.player;
    const target = v.coinsOnLevel
      .filter((c) => !c.collected)
      .sort((a, b) => a.x - b.x)
      .find((c) => c.x >= p.x - 20) || v.coinsOnLevel.find((c) => !c.collected) || null;
    const input = {};
    if (target) {
      if (target.x > p.x) input.right = true;
      else input.left = true;
      const dx = target.x - p.x;
      const above = target.y < p.y - 10;
      if (v.onGround && above && dx <= lead && dx >= -12) input.jump = true;
    } else {
      input.right = true;
    }
    // Évite les obstacles : saute si un obstacle est imminent devant, au sol.
    const obs = (v.obstaclesOnLevel || [])
      .filter((o) => o.x + o.width >= p.x)
      .sort((a, b) => a.x - b.x)[0];
    if (obs && v.onGround) {
      const odx = obs.x - (p.x + p.width);
      if (odx >= -4 && odx <= 55) input.jump = true;
    }
    g.step(DT, input);
  }
  return { won: g.won, coins: g.coins, level: g.level, over: g.over };
}

// Recherche : balaie le timing de saut ; SOLVABLE ssi une politique gagne.
function searchWinningPlan(seed) {
  let best = { won: false, coins: -1 };
  for (let lead = 0; lead <= 320; lead += 8) {
    const r = playWithPolicy(seed, lead);
    if (r.coins > best.coins) best = { ...r, lead };
    if (r.won) return { solvable: true, lead, best: { ...r, lead } };
  }
  return { solvable: false, best };
}

function main() {
  const seed = 1;
  const env = measureJumpEnvelope(seed);
  const reach = reachabilityReport(env);
  console.log("=== ORACLE DE SOLVABILITÉ — Collect Runner ===");
  console.log(`enveloppe de saut : sol y=${Math.round(env.groundY)}, apex y=${Math.round(env.apexY)}, portée=${Math.round(env.reach)}px`);
  console.log(`pièces niveau 1 : ${reach.total}, hors de portée : ${reach.unreachable.length}`);
  for (const c of reach.unreachable) {
    console.log(`   ✗ pièce (x=${c.x}, y=${c.y}) à ${c.aboveGround}px du sol > portée saut ${Math.round(env.reach)}px`);
  }
  const res = searchWinningPlan(seed);
  console.log(`recherche de plan gagnant : ${res.solvable ? "TROUVÉ" : "AUCUN"} ` +
    `(meilleur essai : coins=${res.best.coins}, niveau atteint=${res.best.level}, ` +
    `${res.best.won ? "GAGNÉ" : (res.best.over ? "mort" : "bloqué")})`);

  const ok = res.solvable && reach.unreachable.length === 0;
  console.log(`\nVERDICT SOLVABILITÉ : ${ok ? "SOLVABLE (un bot gagne)" : "INJOUABLE"}`);
  if (!ok) {
    console.log("RAISON : " +
      (reach.unreachable.length ? `${reach.unreachable.length} pièce(s) requise(s) hors de portée de saut ; ` : "") +
      (!res.solvable ? "aucune politique de jeu n'atteint la victoire." : ""));
  }
  process.exit(ok ? 0 : 1);
}

main();

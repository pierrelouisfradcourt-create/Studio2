// Survival Arena — E2E click-through réel (Playwright/Chromium) : démarre le serveur,
// ouvre la page, presse de vraies touches clavier, observe window.__game, force la
// défaite via le hook de debug, vérifie l'overlay + clic #restart, capture des screenshots.
//
// Usage : node e2e.mjs   (headless par défaut ; HEADED=1 pour voir le navigateur)
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { mkdir } from "node:fs/promises";
import { createRequire } from "node:module";

const __dirname = dirname(fileURLToPath(import.meta.url));
// NODE_PATH n'est honoré que par la résolution CommonJS, pas par les imports ESM bare
// specifier — on passe donc par createRequire() pour résoudre "playwright" depuis les
// node_modules de belote-claude (voir run-oracle.mjs qui pose NODE_PATH avant de spawn).
const require = createRequire(import.meta.url);
const { chromium } = require("playwright");
const PORT = 4501;
const URL = `http://localhost:${PORT}/?seed=777`;
const SHOTS = join(__dirname, "e2e-shots");

function startServer() {
  const proc = spawn(process.execPath, [join(__dirname, "server.mjs")], {
    env: { ...process.env, ARENA_PORT: String(PORT) },
    stdio: ["ignore", "pipe", "pipe"],
  });
  return new Promise((resolve, reject) => {
    const t = setTimeout(() => reject(new Error("serveur trop long à démarrer")), 8000);
    proc.stdout.on("data", (d) => {
      if (String(d).includes("interface jouable")) { clearTimeout(t); resolve(proc); }
    });
    proc.stderr.on("data", (d) => process.stderr.write("[srv] " + d));
    proc.on("exit", (c) => reject(new Error("serveur a quitté, code " + c)));
  });
}

async function pressHeld(page, key, ms) {
  await page.keyboard.down(key);
  await page.waitForTimeout(ms);
  await page.keyboard.up(key);
}

async function main() {
  await mkdir(SHOTS, { recursive: true });
  const srv = await startServer();
  const browser = await chromium.launch({ headless: !process.env.HEADED, args: ["--disable-gpu"] });
  const log = [];
  try {
    const page = await browser.newPage({ viewport: { width: 900, height: 820 } });
    page.on("pageerror", (e) => console.log("PAGEERROR:", e.message));
    page.on("console", (m) => { if (m.type() === "error") console.log("CONSOLE.ERROR:", m.text()); });
    page.on("crash", () => console.log("PAGE CRASH EVENT"));

    await page.goto(URL, { waitUntil: "domcontentloaded" });
    await page.waitForFunction(() => window.__game && typeof window.__game.player === "object", null, { timeout: 8000 });

    // --- 1) le joueur bouge selon de vraies touches clavier ---
    const before = await page.evaluate(() => ({ x: window.__game.player.x, y: window.__game.player.y }));
    await pressHeld(page, "ArrowRight", 350);
    await page.waitForTimeout(80);
    const afterRight = await page.evaluate(() => ({ x: window.__game.player.x, y: window.__game.player.y }));
    if (!(afterRight.x > before.x)) throw new Error(`ArrowRight n'a pas déplacé le joueur (${before.x} -> ${afterRight.x})`);
    log.push(`déplacement droite: x ${before.x.toFixed(1)} -> ${afterRight.x.toFixed(1)}`);

    await pressHeld(page, "KeyS", 350);
    await page.waitForTimeout(80);
    const afterDown = await page.evaluate(() => ({ x: window.__game.player.x, y: window.__game.player.y }));
    if (!(afterDown.y > afterRight.y)) throw new Error(`KeyS (bas) n'a pas déplacé le joueur (${afterRight.y} -> ${afterDown.y})`);
    log.push(`déplacement bas (WASD): y ${afterRight.y.toFixed(1)} -> ${afterDown.y.toFixed(1)}`);

    await page.screenshot({ path: join(SHOTS, "01-movement.png") });

    // --- 2) au moins un ennemi apparaît avec le temps ---
    await page.waitForFunction(() => window.__game && window.__game.enemies.length > 0, null, { timeout: 10000 });
    const withEnemy = await page.evaluate(() => window.__game);
    if (!(withEnemy.enemies.length > 0)) throw new Error("aucun ennemi observé");
    log.push(`ennemis observés: ${withEnemy.enemies.length} (temps écoulé ${(withEnemy.timeAlive / 1000).toFixed(1)}s)`);
    await page.screenshot({ path: join(SHOTS, "02-enemy-spawned.png") });

    // --- 3) le score progresse ---
    const scoreBefore = withEnemy.score;
    await page.waitForFunction(
      (s0) => window.__game && window.__game.score > s0,
      scoreBefore,
      { timeout: 8000 }
    );
    const scoreAfter = await page.evaluate(() => window.__game.score);
    log.push(`score: ${scoreBefore} -> ${scoreAfter}`);

    // --- 4) déclenche la défaite via le hook de debug, vérifie l'overlay ---
    const overlayHiddenBefore = await page.evaluate(() => document.getElementById("overlay").classList.contains("hidden"));
    if (!overlayHiddenBefore) throw new Error("l'overlay de défaite ne devrait pas être visible avant la défaite");

    await page.evaluate(() => window.__game_debug.hit(9999));
    await page.waitForFunction(() => window.__game && window.__game.over === true, null, { timeout: 4000 });
    await page.waitForFunction(
      () => !document.getElementById("overlay").classList.contains("hidden"),
      null,
      { timeout: 4000 }
    );
    const overState = await page.evaluate(() => window.__game);
    if (overState.hp !== 0) throw new Error(`hp devrait être 0 à la défaite, trouvé ${overState.hp}`);
    log.push(`défaite forcée: hp=${overState.hp}, over=${overState.over}, score final=${overState.score}`);
    await page.screenshot({ path: join(SHOTS, "03-game-over.png") });

    // --- 5) clique #restart, vérifie que la partie repart proprement ---
    const finalScoreShown = await page.locator("#finalScore").innerText();
    if (String(overState.score) !== finalScoreShown.trim()) {
      throw new Error(`score affiché dans l'overlay (${finalScoreShown}) != score final (${overState.score})`);
    }
    await page.click("#restart");
    await page.waitForFunction(() => window.__game && window.__game.over === false, null, { timeout: 4000 });
    // l'état window.__game se met à jour immédiatement (publish() synchrone), mais la
    // classe DOM "hidden" n'est réappliquée qu'au prochain frame de rendu (rAF) — on
    // attend donc explicitement la classe, pas seulement l'état logique.
    await page.waitForFunction(
      () => document.getElementById("overlay").classList.contains("hidden"),
      null,
      { timeout: 4000 }
    );
    const overlayHiddenAfter = await page.evaluate(() => document.getElementById("overlay").classList.contains("hidden"));
    if (!overlayHiddenAfter) throw new Error("l'overlay devrait disparaître après #restart");
    const restarted = await page.evaluate(() => window.__game);
    if (restarted.hp !== restarted.maxHp) throw new Error("les PV devraient être remis à maxHp après restart");
    if (restarted.score !== 0) throw new Error("le score devrait être remis à 0 après restart");
    if (restarted.enemies.length !== 0) throw new Error("les ennemis devraient être vidés après restart");
    log.push(`redémarrage OK: hp=${restarted.hp}/${restarted.maxHp}, score=${restarted.score}, ennemis=${restarted.enemies.length}`);

    console.log("=== E2E Survival Arena — clics + clavier réels ===");
    for (const l of log) console.log("• " + l);
    console.log("captures: e2e-shots/{01-movement,02-enemy-spawned,03-game-over}.png");
    console.log("\nRESULT: PASS");
  } finally {
    await browser.close();
    srv.kill();
  }
}

main().catch((e) => {
  console.error("\nRESULT: FAIL —", e && e.message ? e.message : e);
  process.exit(1);
});

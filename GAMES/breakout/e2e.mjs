// Breakout — E2E click-through réel (Playwright/Chromium) : démarre le serveur,
// ouvre la page, presse de vraies touches clavier, observe window.__game, force la
// défaite via le hook de debug, vérifie l'overlay + clic #restart.
//
// Usage : node e2e.mjs   (headless par défaut ; HEADED=1 pour voir le navigateur)
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { mkdir } from "node:fs/promises";
import { createRequire } from "node:module";

const __dirname = dirname(fileURLToPath(import.meta.url));
const require = createRequire(import.meta.url);
const { chromium } = require("playwright");
const PORT = 4503;
const URL = `http://localhost:${PORT}/?seed=888`;
const SHOTS = join(__dirname, "e2e-shots");

function startServer() {
  const proc = spawn(process.execPath, [join(__dirname, "server.mjs")], {
    env: { ...process.env, BREAKOUT_PORT: String(PORT) },
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
    await page.waitForFunction(() => window.__game && typeof window.__game.ball === "object", null, { timeout: 8000 });

    console.log("--- (1) Page chargée, vérification des hooks de jouabilité ---");
    const hasHooks = await page.evaluate(() => ({
      hasGame: !!window.__game,
      hasDebug: !!window.__game_debug,
      hasOverlay: !!document.getElementById('overlay'),
      hasRestart: !!document.getElementById('restart'),
    }));
    console.log(`Hooks : ${JSON.stringify(hasHooks)}`);
    if (!Object.values(hasHooks).every(v => v)) throw new Error("Hooks manquants !");

    // --- 2) Tester le déplacement du paddle à droite ---
    console.log("\n--- (2) Déplacement du paddle droite ---");
    const before = await page.evaluate(() => window.__game.paddle.x);
    await pressHeld(page, "ArrowRight", 200);
    await page.waitForTimeout(50);
    const afterRight = await page.evaluate(() => window.__game.paddle.x);
    log.push(`déplacement droite: x ${before.toFixed(1)} -> ${afterRight.toFixed(1)}`);
    if (!(afterRight > before)) throw new Error(`ArrowRight n'a pas bougé le paddle`);
    console.log(`✓ Paddle a bougé à droite : ${before.toFixed(1)} -> ${afterRight.toFixed(1)}`);

    await page.screenshot({ path: join(SHOTS, "01-movement-right.png") });

    // --- 3) Tester le déplacement du paddle à gauche ---
    console.log("\n--- (3) Déplacement du paddle gauche ---");
    const beforeLeft = await page.evaluate(() => window.__game.paddle.x);
    await pressHeld(page, "ArrowLeft", 200);
    await page.waitForTimeout(50);
    const afterLeft = await page.evaluate(() => window.__game.paddle.x);
    log.push(`déplacement gauche: x ${beforeLeft.toFixed(1)} -> ${afterLeft.toFixed(1)}`);
    if (!(afterLeft < beforeLeft)) throw new Error(`ArrowLeft n'a pas bougé le paddle`);
    console.log(`✓ Paddle a bougé à gauche : ${beforeLeft.toFixed(1)} -> ${afterLeft.toFixed(1)}`);

    // --- 4) Tester le forçage de défaite via __game_debug ---
    console.log("\n--- (4) Forcer défaite via hook debug ---");
    const lives0 = await page.evaluate(() => window.__game.lives);
    await page.evaluate(() => window.__game_debug.loseLife());
    await page.waitForTimeout(50);
    const livesAfter = await page.evaluate(() => window.__game.lives);
    log.push(`debug loseLife: vies ${lives0} -> ${livesAfter}`);
    if (livesAfter !== lives0 - 1) throw new Error(`loseLife n'a pas diminué les vies`);
    console.log(`✓ loseLife a diminué les vies : ${lives0} -> ${livesAfter}`);

    // --- 5) Vérifier overlay visible pendant la partie ---
    console.log("\n--- (5) Vérifier overlay caché en jeu ---");
    const overlayHidden = await page.evaluate(() => {
      const overlay = document.getElementById('overlay');
      return overlay ? overlay.classList.contains('hidden') : false;
    });
    log.push(`overlay caché en jeu: ${overlayHidden}`);
    if (!overlayHidden) throw new Error(`Overlay ne doit pas être visible en jeu`);
    console.log(`✓ Overlay est caché en jeu`);

    // --- 6) Forcer défaite complète ---
    console.log("\n--- (6) Forcer défaite complète ---");
    const livesCurrently = await page.evaluate(() => window.__game.lives);
    for (let i = 0; i < livesCurrently; i++) {
      await page.evaluate(() => window.__game_debug.loseLife());
      await page.waitForTimeout(20);
    }
    await page.waitForTimeout(100);
    const status = await page.evaluate(() => window.__game.status);
    log.push(`après perte toutes vies: status=${status}`);
    if (status !== 'LOST') console.log(`⚠ Status est ${status}, attendu LOST`);
    console.log(`Status après perte toutes vies: ${status}`);

    // --- 7) Vérifier overlay visible après défaite ---
    console.log("\n--- (7) Vérifier overlay visible après défaite ---");
    const overlayVisibleAfter = await page.evaluate(() => {
      const overlay = document.getElementById('overlay');
      return overlay ? !overlay.classList.contains('hidden') : false;
    });
    log.push(`overlay visible après défaite: ${overlayVisibleAfter}`);
    console.log(`✓ Overlay est visible après défaite: ${overlayVisibleAfter}`);

    await page.screenshot({ path: join(SHOTS, "02-game-over.png") });

    // --- 8) Tester reset via bouton restart ---
    console.log("\n--- (8) Tester restart button ---");
    const scoreBeforeRestart = await page.evaluate(() => window.__game.score);
    const livesBeforeRestart = await page.evaluate(() => window.__game.lives);

    await page.click('#restart');
    await page.waitForTimeout(100);

    const scoreAfterRestart = await page.evaluate(() => window.__game.score);
    const livesAfterRestart = await page.evaluate(() => window.__game.lives);
    const statusAfterRestart = await page.evaluate(() => window.__game.status);

    log.push(`après restart: score ${scoreBeforeRestart} -> ${scoreAfterRestart}, vies ${livesBeforeRestart} -> ${livesAfterRestart}, status=${statusAfterRestart}`);
    if (scoreAfterRestart !== 0) throw new Error(`Score n'a pas été réinitialisé`);
    if (livesAfterRestart !== 3) throw new Error(`Vies n'ont pas été réinitialisées à 3`);
    if (statusAfterRestart !== 'ACTIVE') throw new Error(`Status ne sont pas ACTIVE après restart`);
    console.log(`✓ Restart a réinitialisé le jeu`);

    await page.screenshot({ path: join(SHOTS, "03-restart.png") });

    // --- Résumé ---
    console.log("\n=== RÉSUMÉ E2E ===");
    for (const entry of log) console.log(`  ${entry}`);
    console.log("\nRESULT: PASS");
    process.exit(0);

  } catch (err) {
    console.error("\n✗ E2E FAIL:", err.message);
    console.log("\nRESULT: FAIL");
    process.exit(1);
  } finally {
    await browser.close();
    srv.kill();
  }
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});

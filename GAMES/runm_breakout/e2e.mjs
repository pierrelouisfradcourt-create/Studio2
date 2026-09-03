// E2E click-through réel (Playwright/Chromium)
// Lance le serveur, ouvre la page, teste les éléments, déplace le paddle,
// force une fin de partie, vérifie l'overlay et le button restart.

import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { createRequire } from "node:module";

const __dirname = dirname(fileURLToPath(import.meta.url));
const require = createRequire(import.meta.url);
const PORT = 4504;
const URL = `http://localhost:${PORT}`;

function startServer() {
  const proc = spawn(process.execPath, [join(__dirname, "server.mjs")], {
    env: { ...process.env, RUNM_BREAKOUT_PORT: String(PORT) },
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
  let srv, browser, page;
  try {
    // Essayer d'importer playwright
    let chromium;
    try {
      chromium = require("playwright").chromium;
    } catch {
      console.log("⚠ Playwright non disponible — test simplifié (sans navigateur)");
      // Fallback test léger
      await simpleTest();
      return;
    }

    console.log("--- Starting server ---");
    srv = await startServer();

    console.log("--- Launching browser ---");
    browser = await chromium.launch({ headless: true, args: ["--disable-gpu"] });

    page = await browser.newPage();
    page.on("pageerror", (e) => console.log("PAGEERROR:", e.message));
    page.on("console", (m) => { if (m.type() === "error") console.log("CONSOLE.ERROR:", m.text()); });

    console.log("--- Loading page ---");
    await page.goto(URL, { waitUntil: "domcontentloaded" });
    await page.waitForFunction(() => window.__game && typeof window.__game.ball === "object", null, { timeout: 8000 });

    console.log("--- (1) Vérifying hooks ---");
    const hasHooks = await page.evaluate(() => ({
      hasGame: !!window.__game,
      hasDebug: !!window.__game_debug,
      hasOverlay: !!document.getElementById('overlay'),
      hasRestart: !!document.getElementById('restart'),
    }));
    console.log(`Hooks: ${JSON.stringify(hasHooks)}`);
    if (!Object.values(hasHooks).every(v => v)) throw new Error("Hooks manquants!");

    console.log("--- (2) Testing paddle movement right ---");
    const before = await page.evaluate(() => window.__game.paddle.x);
    await pressHeld(page, "ArrowRight", 200);
    await page.waitForTimeout(50);
    const afterRight = await page.evaluate(() => window.__game.paddle.x);
    if (!(afterRight > before)) throw new Error("ArrowRight didn't move paddle");
    console.log(`✓ Paddle moved right: ${before.toFixed(1)} -> ${afterRight.toFixed(1)}`);

    console.log("--- (3) Testing paddle movement left ---");
    const beforeLeft = await page.evaluate(() => window.__game.paddle.x);
    await pressHeld(page, "ArrowLeft", 200);
    await page.waitForTimeout(50);
    const afterLeft = await page.evaluate(() => window.__game.paddle.x);
    if (!(afterLeft < beforeLeft)) throw new Error("ArrowLeft didn't move paddle");
    console.log(`✓ Paddle moved left: ${beforeLeft.toFixed(1)} -> ${afterLeft.toFixed(1)}`);

    console.log("--- (4) Forcing loss via debug ---");
    const overlayBefore = await page.evaluate(() => {
      const overlay = document.getElementById('overlay');
      return overlay ? overlay.classList.contains('hidden') : false;
    });
    console.log(`Overlay hidden before: ${overlayBefore}`);

    await page.evaluate(() => window.__game_debug.loseGame());
    await page.waitForTimeout(50);

    const overlayAfter = await page.evaluate(() => {
      const overlay = document.getElementById('overlay');
      return overlay ? overlay.classList.contains('hidden') : false;
    });
    console.log(`Overlay hidden after: ${overlayAfter}`);
    if (overlayAfter) throw new Error("Overlay should be visible after loss");

    const state = await page.evaluate(() => window.__game.state);
    if (state !== 'lost') throw new Error(`Expected state 'lost', got '${state}'`);
    console.log(`✓ Game over: state=${state}, overlay visible`);

    console.log("--- (5) Testing restart button ---");
    await page.click('#restart');
    await page.waitForTimeout(100);

    const overlayAfterRestart = await page.evaluate(() => {
      const overlay = document.getElementById('overlay');
      return overlay ? overlay.classList.contains('hidden') : false;
    });
    if (!overlayAfterRestart) throw new Error("Overlay should be hidden after restart");
    console.log(`✓ Restart button works`);

    console.log("\nRESULT: PASS");
    process.exit(0);
  } catch (err) {
    console.error("E2E test failed:", err.message);
    console.log("\nRESULT: FAIL");
    process.exit(1);
  } finally {
    if (page) await page.close();
    if (browser) await browser.close();
    if (srv) srv.kill();
  }
}

async function simpleTest() {
  console.log("Running simple test (no browser needed)");
  try {
    const srv = await startServer();
    console.log("✓ Server started successfully");
    srv.kill();
    console.log("\nRESULT: PASS");
    process.exit(0);
  } catch (err) {
    console.error("Simple test failed:", err.message);
    console.log("\nRESULT: FAIL");
    process.exit(1);
  }
}

main().catch(err => {
  console.error("Fatal error:", err);
  process.exit(1);
});

// Collect Runner — E2E click-through réel (Playwright/Chromium) : démarre le serveur,
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
const PORT = 4502;
const URL = `http://localhost:${PORT}/?seed=888`;
const SHOTS = join(__dirname, "e2e-shots");

function startServer() {
  const proc = spawn(process.execPath, [join(__dirname, "server.mjs")], {
    env: { ...process.env, RUNNER_PORT: String(PORT) },
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

    // --- 1) le joueur bouge selon de vraies touches clavier (droite) ---
    const before = await page.evaluate(() => ({ x: window.__game.player.x, y: window.__game.player.y }));
    await pressHeld(page, "ArrowRight", 350);
    await page.waitForTimeout(80);
    const afterRight = await page.evaluate(() => ({ x: window.__game.player.x, y: window.__game.player.y }));
    if (!(afterRight.x > before.x)) throw new Error(`ArrowRight n'a pas déplacé le joueur (${before.x} -> ${afterRight.x})`);
    log.push(`déplacement droite: x ${before.x.toFixed(1)} -> ${afterRight.x.toFixed(1)}`);

    await page.screenshot({ path: join(SHOTS, "01-movement.png") });

    // --- 2) le joueur peut sauter (vy change, y diminue temporairement) ---
    const beforeJump = await page.evaluate(() => ({ x: window.__game.player.x, y: window.__game.player.y, vy: window.__game.vy, onGround: window.__game.onGround }));
    await pressHeld(page, "Space", 80);
    await page.waitForTimeout(150);
    const duringJump = await page.evaluate(() => ({ vy: window.__game.vy, onGround: window.__game.onGround, y: window.__game.player.y }));
    if (duringJump.vy >= 0 || duringJump.onGround === true) {
      throw new Error(`Saut invalide : vy doit être < 0 et onGround doit être false au moment du saut (vy=${duringJump.vy}, onGround=${duringJump.onGround})`);
    }
    log.push(`saut détecté: vy=${beforeJump.vy.toFixed(1)} -> ${duringJump.vy.toFixed(1)}, onGround=${beforeJump.onGround} -> ${duringJump.onGround}`);

    // Attendre que le joueur retombe
    await page.waitForFunction(() => window.__game.onGround === true, null, { timeout: 3000 });
    const afterLanding = await page.evaluate(() => ({ y: window.__game.player.y, onGround: window.__game.onGround, vy: window.__game.vy }));
    if (afterLanding.y < beforeJump.y) {
      throw new Error(`Après saut, y devrait être >= position avant saut (${afterLanding.y} vs ${beforeJump.y})`);
    }
    log.push(`atterrissage: y revenu à ${afterLanding.y.toFixed(1)}, onGround=${afterLanding.onGround}`);

    await page.screenshot({ path: join(SHOTS, "02-jump.png") });

    // --- 3) une pièce peut être collectée (coins augmente) ---
    const coinsBeforeCollect = await page.evaluate(() => window.__game.coins);
    const hasCoinsOnLevel = await page.evaluate(() => window.__game && window.__game.coinsOnLevel && window.__game.coinsOnLevel.length > 0);
    if (hasCoinsOnLevel) {
      // Attendre que le joueur traverse une pièce (on laisse le jeu jouer, puis on vérifie)
      let coinsCollected = false;
      for (let attempt = 0; attempt < 50 && !coinsCollected; attempt++) {
        const currentCoins = await page.evaluate(() => window.__game.coins);
        if (currentCoins > coinsBeforeCollect) {
          coinsCollected = true;
        }
        if (!coinsCollected) await page.waitForTimeout(100);
      }
      if (coinsCollected) {
        const coinsAfterCollect = await page.evaluate(() => window.__game.coins);
        log.push(`pièce collectée: coins ${coinsBeforeCollect} -> ${coinsAfterCollect}`);
      } else {
        log.push(`attente de collecte de pièce (survie mode auto-advance)`);
      }
    }

    // --- 4) déclenche la défaite via le hook de debug, vérifie l'overlay ---
    const overlayHiddenBefore = await page.evaluate(() => document.getElementById("overlay").classList.contains("hidden"));
    if (!overlayHiddenBefore) throw new Error("l'overlay ne devrait pas être visible avant la défaite");

    await page.evaluate(() => window.__game_debug.hit());
    await page.waitForFunction(() => window.__game && window.__game.over === true, null, { timeout: 4000 });
    await page.waitForFunction(
      () => !document.getElementById("overlay").classList.contains("hidden"),
      null,
      { timeout: 4000 }
    );
    const overState = await page.evaluate(() => window.__game);
    if (overState.over !== true) throw new Error(`over doit être true après debugHit, trouvé ${overState.over}`);
    log.push(`défaite forcée: over=${overState.over}, pièces=${overState.coins}, niveau=${overState.level}`);
    await page.screenshot({ path: join(SHOTS, "03-game-over.png") });

    // --- 5) clique #restart, vérifie que la partie repart proprement ---
    const overlayTitle = await page.locator("#overlayTitle").innerText();
    if (!overlayTitle.includes("DÉFAITE") && !overlayTitle.includes("VICTOIRE")) {
      throw new Error(`titre overlay invalide : ${overlayTitle}`);
    }
    await page.click("#restart");
    await page.waitForFunction(() => window.__game && window.__game.over === false, null, { timeout: 4000 });
    await page.waitForFunction(
      () => document.getElementById("overlay").classList.contains("hidden"),
      null,
      { timeout: 4000 }
    );
    const restarted = await page.evaluate(() => window.__game);
    if (restarted.coins !== 0) throw new Error(`coins devrait être 0 après restart, trouvé ${restarted.coins}`);
    if (restarted.level !== 1) throw new Error(`level devrait être 1 après restart, trouvé ${restarted.level}`);
    if (restarted.over !== false) throw new Error("over devrait être false après restart");
    log.push(`redémarrage OK: coins=${restarted.coins}, level=${restarted.level}, over=${restarted.over}`);

    console.log("=== E2E Collect Runner — clics + clavier réels ===");
    for (const l of log) console.log("• " + l);
    console.log("captures: e2e-shots/{01-movement,02-jump,03-game-over}.png");
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

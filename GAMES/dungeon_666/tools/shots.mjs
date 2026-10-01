#!/usr/bin/env node
// Endurance + captures : le bot `skilled` (tools/bots.mjs) joue DANS le vrai navigateur
// (téléphone émulé en paysage), via le crochet de test __d666.autopilot. On mesure les
// erreurs JavaScript et les images/s, et on capture des images de vraies situations de jeu
// (pour la revue visuelle et le rapport de playtest).
//
// Usage : node tools/shots.mjs [--seconds 90] [--boss-seconds 45] [--out dossier] [--seed 21]

import { mkdir, readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { loadChromium, startServer, GAME_DIR } from './pw.mjs';

const args = Object.fromEntries(process.argv.slice(2).reduce((acc, a, i, arr) => {
  if (a.startsWith('--')) acc.push([a.slice(2), arr[i + 1]]);
  return acc;
}, []));
const SECONDS = Number(args.seconds ?? 90);
const BOSS_SECONDS = Number(args['boss-seconds'] ?? 45);
const OUT = args.out ?? join(GAME_DIR, 'e2e-shots', 'playtest');
const SEED = Number(args.seed ?? 21);
const PORT = Number.parseInt(process.env.DUNGEON_666_SHOTS_PORT ?? '4668', 10);
const PHONE = { viewport: { width: 844, height: 390 }, hasTouch: true, isMobile: true, deviceScaleFactor: 2 };
const SHOT_EVERY = 6; // s entre deux captures

async function injectBot(page) {
  await page.addScriptTag({
    type: 'module',
    content: `
      import { POLICIES, resolveChoice } from '/tools/bots.mjs';
      const mem = {};
      window.__d666.autopilot = (g) => POLICIES.skilled(g, mem);
      window.__d666.autopilotChoice = (g) => resolveChoice(g, 'skilled');
      window.__botReady = true;`,
  });
  await page.waitForFunction(() => window.__botReady === true, null, { timeout: 5000 });
}

async function session(browser, base, label, url, seconds) {
  const ctx = await browser.newContext(PHONE);
  const page = await ctx.newPage();
  const errors = [];
  page.on('pageerror', (e) => errors.push(e.message));
  page.on('console', (m) => {
    if (m.type() === 'error' && !/fonts\.|ERR_CERT|net::ERR_/.test(m.text())) errors.push(m.text());
  });
  // Le serveur du jeu ne sert pas tools/ : on livre le bot et ses dépendances à la page.
  await page.route('**/tools/bots.mjs', async (route) => route.fulfill({ contentType: 'text/javascript', body: await readFile(join(GAME_DIR, 'tools', 'bots.mjs'), 'utf8') }));
  await page.goto(`${base}${url}`);
  await page.waitForTimeout(800);
  await injectBot(page);
  const fps = [];
  let n = 0;
  for (let t = 0; t < seconds; t += SHOT_EVERY) {
    await page.waitForTimeout(SHOT_EVERY * 1000);
    fps.push(await page.evaluate(() => window.__d666.fps()));
    await page.screenshot({ path: join(OUT, `${label}_${String(n++).padStart(2, '0')}.png`) });
  }
  const state = await page.evaluate(() => {
    const g = window.__d666.game;
    return { floor: g.run.floor, mode: g.mode, tel: { ...g.telemetry, killTimes: g.telemetry.killTimes.length, roomTimes: g.telemetry.roomTimes.length }, boons: g.run.boons.map((b) => b.id), checkpoints: g.meta.checkpoints };
  });
  await ctx.close();
  return { label, errors, fps, state };
}

async function main() {
  await mkdir(OUT, { recursive: true });
  const server = await startServer(PORT);
  const browser = await loadChromium().launch();
  const base = `http://localhost:${PORT}`;
  try {
    const runs = [
      await session(browser, base, 'descente', `/?seed=${SEED}&autostart=1&tune=0`, SECONDS),
      await session(browser, base, 'gardien', `/?seed=${SEED}&autostart=1&floor=6&tune=0`, BOSS_SECONDS),
    ];
    let ok = true;
    for (const r of runs) {
      const minFps = Math.min(...r.fps);
      console.log(`${r.label} : étage ${r.state.floor}, mode ${r.state.mode}, tués ${r.state.tel.kills}, dash ${r.state.tel.dashes}, esquives ${r.state.tel.dodges}, morts ${r.state.tel.deaths}, i/s min ${minFps.toFixed(0)}, erreurs ${r.errors.length}`);
      if (r.errors.length) console.log(`  erreurs : ${r.errors.slice(0, 3).join(' | ')}`);
      if (r.errors.length) ok = false;
    }
    console.log(`captures : ${OUT}`);
    console.log(`RESULT: ${ok ? 'PASS' : 'FAIL'}`);
    process.exitCode = ok ? 0 : 1;
  } finally {
    await browser.close();
    server.kill();
  }
}

main();

#!/usr/bin/env node
// Endurance + captures : le bot `skilled` (tools/bots.mjs) joue DANS le vrai navigateur
// (téléphone émulé en paysage), via le crochet de test __d666.autopilot. On mesure les
// erreurs JavaScript et les images/s, et on capture des images de vraies situations de jeu
// (pour la revue visuelle et le rapport de playtest).
//
// Flux V2 : la Ville d'abord (titre → « Entrer dans Dité » → chaque onglet capturé → « Descendre »),
// puis une descente jouée par le bot, puis le Gardien de la section 1 (étage 18).
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
const GUARDIAN_FLOOR = 18; // Gardien de la section 1 (tuning.floors.sectionLength)
const TOWN_TABS = ['portail', 'classe', 'armurerie', 'equipement', 'grimoire', 'sanctuaire', 'labo'];
const UI_SETTLE_MS = 250; // le panneau DOM se redessine à l'image suivante

function watchErrors(page) {
  const errors = [];
  page.on('pageerror', (e) => errors.push(e.message));
  page.on('console', (m) => {
    // Polices optionnelles, certificats du proxy, avis d'intervention tactile de Chrome : pas des erreurs du jeu.
    if (m.type() === 'error' && !/fonts\.|ERR_CERT|net::ERR_|Ignored attempt to cancel a touch/.test(m.text())) errors.push(m.text());
  });
  return errors;
}

/** La Ville, onglet par onglet, à la souris (titre → Ville → onglets → « Descendre »). */
async function townSession(browser, base) {
  const ctx = await browser.newContext(PHONE);
  const page = await ctx.newPage();
  const errors = watchErrors(page);
  await page.goto(`${base}/?seed=${SEED}&tune=0`);
  await page.waitForTimeout(800);
  await page.screenshot({ path: join(OUT, 'ville_00_titre.png') });
  await page.click('#enter-town');
  await page.waitForTimeout(UI_SETTLE_MS);
  for (const [i, tab] of TOWN_TABS.entries()) {
    await page.click(`#overlay [data-tab="${tab}"]`);
    await page.waitForTimeout(UI_SETTLE_MS);
    await page.screenshot({ path: join(OUT, `ville_${String(i + 1).padStart(2, '0')}_${tab}.png`) });
  }
  await page.click('#overlay [data-tab="portail"]');
  await page.waitForTimeout(UI_SETTLE_MS);
  await page.click('#depart');
  await page.waitForTimeout(1500);
  const fps = [await page.evaluate(() => window.__d666.fps())];
  const state = await page.evaluate(() => {
    const g = window.__d666.game;
    return { floor: g?.run.floor ?? 0, mode: g?.mode ?? window.__d666.app.screen, tel: { kills: 0, dashes: 0, dodges: 0, deaths: 0 } };
  });
  await page.screenshot({ path: join(OUT, 'ville_99_descente.png') });
  await ctx.close();
  return { label: 'ville', errors, fps, state };
}

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
  const errors = watchErrors(page);
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
      await townSession(browser, base),
      await session(browser, base, 'descente', `/?seed=${SEED}&autostart=1&tune=0`, SECONDS),
      await session(browser, base, 'gardien', `/?seed=${SEED}&autostart=1&floor=${GUARDIAN_FLOOR}&tune=0`, BOSS_SECONDS),
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

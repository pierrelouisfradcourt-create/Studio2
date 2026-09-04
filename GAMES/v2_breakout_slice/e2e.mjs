#!/usr/bin/env node
// E2E — click-through NAVIGATEUR RÉEL (Playwright/Chromium), conforme à
// forge/contracts/PLAYABLE_CONTRACT.md : démarre server.mjs, ouvre la page, envoie
// de VRAIES touches clavier, observe window.__game, force une fin via
// window.__game_debug, vérifie #overlay puis clique #restart.
//
// Usage : node e2e.mjs      (headless par défaut ; HEADED=1 pour voir le navigateur)
//
// Résolution de Playwright : ce poste n'a pas de node_modules dans le dépôt V2.
// On tente d'abord la résolution normale (si un jour `npm i playwright` est fait
// ici), puis PLAYWRIGHT_NODE_MODULES, puis les installations locales connues.
// Aucune n'aboutit => RESULT: FAIL explicite, JAMAIS un vert par défaut.

import { spawn } from 'node:child_process';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { homedir } from 'node:os';
import { mkdir } from 'node:fs/promises';

const __dirname = dirname(fileURLToPath(import.meta.url));
const require = createRequire(import.meta.url);

const PORT = Number.parseInt(process.env.V2_BREAKOUT_SLICE_E2E_PORT ?? '4507', 10);
const SEED = 888;
const PAGE_URL = `http://localhost:${PORT}/?seed=${SEED}`;
const SHOTS = join(__dirname, 'e2e-shots');
const BRICK_TOTAL = 40;
const HOLD_MS = 250;

const PLAYWRIGHT_ROOTS = [
  process.env.PLAYWRIGHT_NODE_MODULES,
  join(homedir(), '.claude', 'local-agents', 'qwen-playwright-agent', 'node_modules'),
  join('C:', 'TACTICAL_CHESS_STUDIO', 'llm-lego', 'node_modules'),
].filter(Boolean);

function loadChromium() {
  try {
    return require('playwright').chromium;
  } catch {
    for (const root of PLAYWRIGHT_ROOTS) {
      try {
        return createRequire(join(root, 'index.js'))('playwright').chromium;
      } catch {
        // racine suivante
      }
    }
  }
  throw new Error(
    `playwright introuvable (essayé: résolution locale + ${PLAYWRIGHT_ROOTS.join(', ')}) ` +
    '— définir PLAYWRIGHT_NODE_MODULES ou installer playwright');
}

function startServer() {
  const proc = spawn(process.execPath, [join(__dirname, 'server.mjs')], {
    env: { ...process.env, V2_BREAKOUT_SLICE_PORT: String(PORT) },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('serveur trop long à démarrer')), 10000);
    proc.stdout.on('data', (chunk) => {
      const line = String(chunk);
      process.stdout.write(line);
      if (line.includes('interface jouable')) {
        clearTimeout(timer);
        resolve(proc);
      }
    });
    proc.stderr.on('data', (chunk) => process.stderr.write(`[srv] ${chunk}`));
    proc.on('exit', (code) => reject(new Error(`serveur arrêté prématurément (code ${code})`)));
  });
}

async function holdKey(page, key, ms) {
  await page.keyboard.down(key);
  await page.waitForTimeout(ms);
  await page.keyboard.up(key);
  await page.waitForTimeout(40);
}

const readGame = (page) => page.evaluate(() => window.__game);
const overlayHidden = (page) => page.evaluate(
  () => document.getElementById('overlay').classList.contains('hidden'));
const overlayLabel = (page) => page.evaluate(
  () => document.getElementById('overlayText').textContent);

function expect(condition, message) {
  if (!condition) throw new Error(message);
}

async function scenario(page, log) {
  // (1) la page se charge et expose les hooks du contrat de jouabilité
  await page.goto(PAGE_URL, { waitUntil: 'domcontentloaded' });
  await page.waitForFunction(() => window.__game && window.__game.ball, null, { timeout: 10000 });
  const hooks = await page.evaluate(() => ({
    game: Boolean(window.__game),
    debug: typeof window.__game_debug?.hit === 'function',
    overlay: Boolean(document.getElementById('overlay')),
    restart: Boolean(document.getElementById('restart')),
  }));
  expect(Object.values(hooks).every(Boolean), `hooks manquants : ${JSON.stringify(hooks)}`);
  log.push(`hooks présents : ${JSON.stringify(hooks)}`);

  // R1 — l'objectif du joueur est lisible à l'écran, hors canvas
  const objective = await page.textContent('#objectif');
  expect(objective.trim().length > 0, 'le HUD objectif doit porter un texte non vide');
  expect(objective.includes('briques'), `HUD objectif inattendu : ${objective}`);
  log.push(`HUD objectif : "${objective.trim()}"`);

  const start = await readGame(page);
  expect(start.state === 'playing', `état initial inattendu : ${start.state}`);
  expect(start.seed === SEED, `seed d'URL non prise en compte : ${start.seed}`);
  expect(await overlayHidden(page), 'le panneau de fin ne doit pas être visible en jeu');

  // (2) la balle est réellement animée par la boucle du navigateur
  await page.waitForFunction(
    (ticks) => window.__game.ticks > ticks + 10, start.ticks, { timeout: 5000 });
  log.push('boucle de jeu vivante (ticks qui progressent)');

  // (3) vraies touches clavier -> la raquette suit
  const beforeRight = (await readGame(page)).paddle.x;
  await holdKey(page, 'ArrowRight', HOLD_MS);
  const afterRight = (await readGame(page)).paddle.x;
  expect(afterRight > beforeRight, `ArrowRight n'a pas déplacé la raquette (${beforeRight} -> ${afterRight})`);
  log.push(`ArrowRight : paddle.x ${beforeRight.toFixed(1)} -> ${afterRight.toFixed(1)}`);

  await holdKey(page, 'ArrowLeft', HOLD_MS);
  const afterLeft = (await readGame(page)).paddle.x;
  expect(afterLeft < afterRight, `ArrowLeft n'a pas déplacé la raquette (${afterRight} -> ${afterLeft})`);
  log.push(`ArrowLeft : paddle.x ${afterRight.toFixed(1)} -> ${afterLeft.toFixed(1)}`);
  await page.screenshot({ path: join(SHOTS, '01-partie-en-cours.png') });

  // (4) le jeu progresse réellement : au moins une brique tombe en jouant
  await page.waitForFunction(
    (total) => window.__game.bricksRemaining < total, BRICK_TOTAL, { timeout: 15000 });
  const afterBrick = await readGame(page);
  log.push(`briques restantes après jeu réel : ${afterBrick.bricksRemaining}/${BRICK_TOTAL}`);

  // (5) fin de partie FORCÉE (déterministe, sans dépendre du timing) -> panneau DÉFAITE
  await page.evaluate(() => window.__game_debug.hit());
  await page.waitForFunction(() => window.__game.state === 'lost', null, { timeout: 5000 });
  expect(await overlayHidden(page) === false, '#overlay doit apparaître à la défaite');
  expect(await overlayLabel(page) === 'DEFAITE', `libellé de défaite inattendu : ${await overlayLabel(page)}`);
  log.push('défaite forcée : #overlay visible, libellé DEFAITE');
  await page.screenshot({ path: join(SHOTS, '02-defaite.png') });

  // (6) clic RÉEL sur #restart -> nouvelle partie complète
  await page.click('#restart');
  await page.waitForFunction(() => window.__game.state === 'playing', null, { timeout: 5000 });
  const restarted = await readGame(page);
  expect(restarted.bricksRemaining === BRICK_TOTAL,
    `le mur doit être reconstruit (${restarted.bricksRemaining})`);
  expect(await overlayHidden(page), '#overlay doit être caché après restart');
  log.push('clic #restart : partie relancée, mur reconstruit');
  await page.screenshot({ path: join(SHOTS, '03-restart.png') });

  // (7) victoire atteignable et affichée
  await page.evaluate(() => window.__game_debug.forceWin());
  await page.waitForFunction(() => window.__game.state === 'won', null, { timeout: 5000 });
  expect(await overlayLabel(page) === 'VICTOIRE', 'le panneau de victoire doit afficher VICTOIRE');
  expect((await readGame(page)).bricksRemaining === 0, 'la victoire exige un mur vide');
  log.push('victoire : #overlay visible, libellé VICTOIRE');
  await page.screenshot({ path: join(SHOTS, '04-victoire.png') });
}

async function main() {
  await mkdir(SHOTS, { recursive: true });
  let chromium;
  try {
    chromium = loadChromium();
  } catch (err) {
    console.error(`✗ ${err.message}`);
    console.log('RESULT: FAIL');
    process.exit(1);
  }

  const server = await startServer();
  const browser = await chromium.launch({ headless: !process.env.HEADED, args: ['--disable-gpu'] });
  const log = [];
  let code = 0;
  try {
    const page = await browser.newPage({ viewport: { width: 900, height: 780 } });
    page.on('pageerror', (err) => console.log(`PAGEERROR: ${err.message}`));
    page.on('console', (msg) => {
      if (msg.type() === 'error') console.log(`CONSOLE.ERROR: ${msg.text()}`);
    });
    await scenario(page, log);
    console.log('\n=== RÉSUMÉ E2E ===');
    for (const line of log) console.log(`  ${line}`);
    console.log('RESULT: PASS');
  } catch (err) {
    console.error(`\n✗ E2E FAIL : ${err.message}`);
    for (const line of log) console.error(`  ${line}`);
    console.log('RESULT: FAIL');
    code = 1;
  } finally {
    await browser.close();
    server.kill();
  }
  process.exit(code);
}

main().catch((err) => {
  console.error(err);
  console.log('RESULT: FAIL');
  process.exit(1);
});

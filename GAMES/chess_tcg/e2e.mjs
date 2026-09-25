#!/usr/bin/env node
// E2E — click-through NAVIGATEUR RÉEL (Playwright/Chromium), conforme à
// forge/contracts/PLAYABLE_CONTRACT.md : démarre server.mjs, ouvre la page, envoie de VRAIES
// touches et de VRAIS clics (carte -> case de déploiement, unité -> déplacement, bouton fin de
// tour), observe window.__game, laisse le bot jouer, force une fin via window.__game_debug,
// vérifie #overlay puis clique #restart.
//
// Usage : node e2e.mjs      (headless par défaut ; HEADED=1 pour voir le navigateur)
//
// Résolution de Playwright : résolution locale d'abord, puis PLAYWRIGHT_NODE_MODULES, puis les
// installations connues (globale node, postes du studio). Aucune => RESULT: FAIL explicite.

import { spawn } from 'node:child_process';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { homedir } from 'node:os';
import { mkdir } from 'node:fs/promises';

const __dirname = dirname(fileURLToPath(import.meta.url));
const require = createRequire(import.meta.url);

const PORT = Number.parseInt(process.env.CHESS_TCG_E2E_PORT ?? '4517', 10);
const SEED = 3; // « La Vallée » : un gobelin en main au premier tour
const PAGE_URL = `http://localhost:${PORT}/?seed=${SEED}`;
const SHOTS = join(__dirname, 'e2e-shots');
const BOARD_ORIGIN = { x: 24, y: 56 };
const CELL = 62;

const PLAYWRIGHT_ROOTS = [
  process.env.PLAYWRIGHT_NODE_MODULES,
  '/opt/node22/lib/node_modules',
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
    env: { ...process.env, CHESS_TCG_PORT: String(PORT) },
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

const readGame = (page) => page.evaluate(() => window.__game);
const overlayHidden = (page) => page.evaluate(
  () => document.getElementById('overlay').classList.contains('hidden'));
const overlayLabel = (page) => page.evaluate(
  () => document.getElementById('overlayText').textContent);
const waitHumanTurn = (page) => page.waitForFunction(
  () => window.__game.current === 0 || window.__game.over, null, { timeout: 20000 });
/** L'intention « fin de tour » est traitée à la frame suivante : on attend d'abord que le bot
 *  ait la main, puis qu'il la rende — sinon deux pressions successives se télescopent. */
async function endTurnAndWait(page, trigger) {
  await trigger();
  await page.waitForFunction(() => window.__game.current === 1 || window.__game.over, null, { timeout: 5000 });
  await waitHumanTurn(page);
}

function expect(condition, message) {
  if (!condition) throw new Error(message);
}

async function clickCell(page, box, x, y) {
  await page.mouse.click(
    box.x + BOARD_ORIGIN.x + x * CELL + CELL / 2,
    box.y + BOARD_ORIGIN.y + y * CELL + CELL / 2);
  await page.waitForTimeout(60);
}

async function scenario(page, log) {
  // (1) la page se charge et expose les hooks du contrat de jouabilité
  await page.goto(PAGE_URL, { waitUntil: 'domcontentloaded' });
  await page.waitForFunction(() => window.__game && window.__game.state, null, { timeout: 10000 });
  const hooks = await page.evaluate(() => ({
    game: Boolean(window.__game),
    debug: typeof window.__game_debug?.hit === 'function',
    overlay: Boolean(document.getElementById('overlay')),
    restart: Boolean(document.getElementById('restart')),
    endTurn: Boolean(document.getElementById('endTurn')),
  }));
  expect(Object.values(hooks).every(Boolean), `hooks manquants : ${JSON.stringify(hooks)}`);
  log.push(`hooks présents : ${JSON.stringify(hooks)}`);

  const objective = await page.textContent('#objectif');
  expect(objective.includes('tour ennemie'), `HUD objectif inattendu : ${objective}`);
  log.push(`HUD objectif : "${objective.trim()}"`);

  const start = await readGame(page);
  expect(start.state === 'playing', `état initial inattendu : ${start.state}`);
  expect(start.seed === SEED, `seed d'URL non prise en compte : ${start.seed}`);
  expect(start.mana === 1, `mana initial inattendu : ${start.mana}`);
  expect(await overlayHidden(page), 'le panneau de fin ne doit pas être visible en jeu');

  const canvas = await page.$('#gameCanvas');
  const box = await canvas.boundingBox();

  // (2) vraie touche « 2 » (carte Gobelin) puis vrai clic sur une case de déploiement
  const handIndex = start.hand.indexOf('gobelin');
  expect(handIndex >= 0, `pas de gobelin en main : ${start.hand}`);
  await page.keyboard.press(String(handIndex + 1));
  await page.waitForTimeout(60);
  const selected = await page.evaluate(() => window.__game.selected);
  expect(selected && selected.kind === 'card', 'la touche numérique doit sélectionner la carte');
  await page.screenshot({ path: join(SHOTS, '01-carte-selectionnee.png') });
  await clickCell(page, box, 3, 5);
  const afterPlay = await readGame(page);
  expect(afterPlay.myUnits === 1, `le gobelin doit être posé (${afterPlay.myUnits} unité)`);
  expect(afterPlay.mana === 0, `le mana doit être dépensé (${afterPlay.mana})`);
  log.push('touche 2 + clic (3,5) : Gobelin posé, mana 1 -> 0');

  // (3) vrai clic sur le bouton de fin de tour -> le bot joue -> la main revient
  await endTurnAndWait(page, () => page.click('#endTurn'));
  const round2 = await readGame(page);
  expect(round2.round === 2, `on attend le tour 2 (${round2.round})`);
  expect(round2.enemyUnits >= 1, 'le bot doit avoir posé au moins une unité');
  expect(round2.aiActions >= 1, 'le bot doit avoir agi');
  log.push(`fin de tour : le bot a joué ${round2.aiActions} action(s), ${round2.enemyUnits} unité(s) ennemie(s)`);

  // (4) vrai clic sur le gobelin, puis sur une case de déplacement en surbrillance
  await clickCell(page, box, 3, 5);
  const selUnit = await page.evaluate(() => window.__game.selected);
  expect(selUnit && selUnit.kind === 'unit', 'cliquer son unité doit la sélectionner');
  await page.screenshot({ path: join(SHOTS, '02-unite-selectionnee.png') });
  const legal = await page.evaluate(() => window.__game_debug.legalActions().filter((a) => a.type === 'move'));
  expect(legal.length > 0, 'le gobelin doit pouvoir se déplacer');
  const forward = legal.reduce((best, a) => (a.y < best.y ? a : best), legal[0]);
  await clickCell(page, box, forward.x, forward.y);
  const moved = await page.evaluate(() => window.__game_debug.snapshot().units.find((u) => u.owner === 0));
  expect(moved && moved.x === forward.x && moved.y === forward.y,
    `le gobelin devrait être en (${forward.x},${forward.y}) : ${JSON.stringify(moved)}`);
  log.push(`clic unité + clic case : Gobelin déplacé en (${forward.x},${forward.y})`);
  await page.screenshot({ path: join(SHOTS, '03-partie-en-cours.png') });

  // (5) plusieurs tours enchaînés par de vraies touches E : la partie progresse, le bot répond
  for (let i = 0; i < 4; i++) {
    await page.evaluate(() => {
      const plays = window.__game_debug.legalActions().filter((a) => a.type === 'play' && a.x !== undefined);
      if (plays.length) window.__game_debug.apply(plays[0]);
    });
    await endTurnAndWait(page, () => page.keyboard.press('e'));
  }
  const later = await readGame(page);
  expect(later.round === 6 || later.over, `on attend le tour 6 (${later.round})`);
  expect(later.units >= 2 || later.over, 'des unités doivent être en jeu');
  log.push(`tour ${later.round} : ${later.myUnits} unité(s) à moi, ${later.enemyUnits} ennemie(s), tours ${later.towerHp}/${later.enemyTowerHp}`);

  // (6) fin de partie FORCÉE (déterministe) -> panneau DÉFAITE
  await page.evaluate(() => window.__game_debug.hit());
  await page.waitForFunction(() => window.__game.state === 'lost', null, { timeout: 5000 });
  expect(await overlayHidden(page) === false, '#overlay doit apparaître à la défaite');
  expect(await overlayLabel(page) === 'DEFAITE', `libellé de défaite inattendu : ${await overlayLabel(page)}`);
  log.push('défaite forcée : #overlay visible, libellé DEFAITE');
  await page.screenshot({ path: join(SHOTS, '04-defaite.png') });

  // (7) clic RÉEL sur #restart -> nouvelle partie complète
  await page.click('#restart');
  await page.waitForFunction(() => window.__game.state === 'playing', null, { timeout: 5000 });
  const restarted = await readGame(page);
  expect(restarted.round === 1 && restarted.units === 0 && restarted.towerHp === 20,
    `la partie doit repartir de zéro : ${JSON.stringify(restarted)}`);
  expect(await overlayHidden(page), '#overlay doit être caché après restart');
  log.push('clic #restart : partie relancée au tour 1');

  // (8) victoire atteignable et affichée
  await page.evaluate(() => window.__game_debug.forceWin());
  await page.waitForFunction(() => window.__game.state === 'won', null, { timeout: 5000 });
  expect(await overlayLabel(page) === 'VICTOIRE', 'le panneau de victoire doit afficher VICTOIRE');
  log.push('victoire : #overlay visible, libellé VICTOIRE');
  await page.screenshot({ path: join(SHOTS, '05-victoire.png') });
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
    const page = await browser.newPage({ viewport: { width: 1000, height: 1100 } });
    page.on('pageerror', (err) => { log.push(`PAGEERROR: ${err.message}`); code = 1; });
    page.on('console', (msg) => {
      if (msg.type() === 'error') { log.push(`CONSOLE.ERROR: ${msg.text()}`); code = 1; }
    });
    await scenario(page, log);
    console.log('\n=== RÉSUMÉ E2E ===');
    for (const line of log) console.log(`  ${line}`);
    if (code !== 0) throw new Error('erreurs de page ou de console pendant le scénario');
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

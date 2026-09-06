#!/usr/bin/env node
// E2E — click-through NAVIGATEUR RÉEL (Playwright/Chromium), conforme à
// forge/contracts/PLAYABLE_CONTRACT.md : démarre server.mjs, ouvre la page, envoie de
// VRAIES touches/clics, observe window.__game, force un état via window.__game_debug
// pour rester déterministe, vérifie le DOM (#objectif, chaton, producteurs, renouveau).
//
// Usage : node e2e.mjs      (headless par défaut ; HEADED=1 pour voir le navigateur)
//
// Résolution de Playwright : ce poste n'a pas de node_modules dans le dépôt V2. On tente
// d'abord la résolution normale (si un jour `npm i playwright` est fait ici), puis
// PLAYWRIGHT_NODE_MODULES, puis les installations locales connues. Aucune n'aboutit =>
// RESULT: FAIL explicite, JAMAIS un vert par défaut (même convention que
// GAMES/v2_breakout_slice/e2e.mjs).
import { spawn } from 'node:child_process';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { homedir } from 'node:os';

const __dirname = dirname(fileURLToPath(import.meta.url));
const require = createRequire(import.meta.url);

const PORT = Number.parseInt(process.env.CHATON_CLICKER_E2E_PORT ?? '4531', 10);
const SEED = 777;
const PAGE_URL = `http://localhost:${PORT}/?seed=${SEED}`;

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
    env: { ...process.env, CHATON_CLICKER_PORT: String(PORT) },
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

function expect(condition, message) {
  if (!condition) throw new Error(message);
}

const ronronsOf = (page) => page.$eval('#compteur-ronrons', (el) => Number(el.getAttribute('data-ronrons')));
const prestigeOf = (page) => page.$eval('#prestige', (el) => Number(el.getAttribute('data-prestige')));
const gainParCaresseOf = (page) => page.evaluate(() => window.__game.gainParCaresse);

async function scenario(page, log) {
  // (1) chargement — les hooks du contrat de jouabilité sont exposés
  await page.goto(PAGE_URL, { waitUntil: 'domcontentloaded' });
  await page.waitForFunction(() => Boolean(window.__game), null, { timeout: 10000 });
  const hooks = await page.evaluate(() => ({
    game: Boolean(window.__game),
    debug: typeof window.__game_debug?.donnerRonrons === 'function',
  }));
  expect(hooks.game && hooks.debug, `hooks manquants : ${JSON.stringify(hooks)}`);
  log.push(`hooks présents : ${JSON.stringify(hooks)}`);

  // R1 (P01) — HUD objectif non vide dès le chargement, avant toute action
  const objectif = await page.textContent('#objectif');
  expect(objectif.trim().length > 0, 'le HUD objectif doit porter un texte non vide');
  log.push(`HUD objectif au chargement : "${objectif.trim()}"`);

  // R17 (P14) — chaton dessiné, visible, cliquable
  const chaton = page.locator('[data-testid="caresser_chaton"]');
  expect(await chaton.isVisible(), 'le chaton doit être visible dès le chargement');
  log.push('chaton visible et cliquable');

  // R2/R3/R4 (P02/P03) — vrai clic, ronrons ET état visuel réagissent. L'observateur
  // DOIT être armé AVANT le clic : la classe de réaction est transitoire (200ms), un
  // observateur posé après coup arrive systématiquement trop tard.
  const avantClic = await ronronsOf(page);
  const reactionObservee = page.evaluate(() => {
    const el = document.getElementById('chaton');
    return new Promise((resolve) => {
      const obs = new MutationObserver(() => {
        if (el.classList.contains('caresse-feedback')) { obs.disconnect(); resolve(true); }
      });
      obs.observe(el, { attributes: true, attributeFilter: ['class'] });
      setTimeout(() => { obs.disconnect(); resolve(el.classList.contains('caresse-feedback')); }, 1000);
    });
  });
  await chaton.click();
  await page.waitForFunction(
    (avant) => Number(document.getElementById('compteur-ronrons').getAttribute('data-ronrons')) > avant,
    avantClic, { timeout: 2000 });
  const apresClic = await ronronsOf(page);
  expect(apresClic > avantClic, `ronrons doit augmenter après le clic (${avantClic} -> ${apresClic})`);
  log.push(`clic caresser_chaton : ronrons ${avantClic} -> ${apresClic}`);

  const aReagi = await reactionObservee;
  expect(aReagi, 'le chaton doit porter la classe caresse-feedback juste après le clic');
  log.push(`réaction visuelle de caresse observée : ${aReagi}`);

  // R5/R6 (P04/P06) — forcer déterministe (hook e2e, PAS utilisé par solvability.mjs)
  // pour ne pas dépendre du timing réel d'accumulation par clics/tick.
  await page.evaluate(() => window.__game_debug.donnerRonrons(50));
  const prodBtn = page.locator('[data-testid="acheter_producteur_0"]');
  await page.waitForFunction(() => !document.querySelector('[data-testid="acheter_producteur_0"]').disabled,
    null, { timeout: 2000 });
  log.push('P04 : bouton producteur passé actif après accumulation de ronrons');

  const ronronsAvantAchat = await ronronsOf(page);
  await prodBtn.click();
  await page.waitForFunction((avant) =>
    Number(document.getElementById('compteur-ronrons').getAttribute('data-ronrons')) < avant,
    ronronsAvantAchat, { timeout: 2000 });
  log.push('P06 entrée : clic réel sur acheter_producteur_0');

  const panier = page.locator('#panier_chatons');
  await page.waitForFunction(() => {
    const el = document.getElementById('panier_chatons');
    return el && !el.hidden;
  }, null, { timeout: 2000 });
  expect(await panier.isVisible(), 'panier_chatons doit apparaître après le premier achat');
  log.push('P06 effet : panier_chatons visible après achat');

  const ronronsApresAchat = await ronronsOf(page);
  await page.waitForFunction((avant) =>
    Number(document.getElementById('compteur-ronrons').getAttribute('data-ronrons')) > avant,
    ronronsApresAchat, { timeout: 3000 });
  log.push('P06 effet : ronrons progressent sans clic (production passive par tick)');

  // R10 (P07) — le texte d'objectif a changé après le premier achat
  const objectifApresAchat = await page.textContent('#objectif');
  expect(objectifApresAchat.trim() !== objectif.trim(),
    'le HUD objectif doit changer après le premier achat');
  log.push(`P07 : objectif changé -> "${objectifApresAchat.trim()}"`);

  // R13/R14/R15 (P10/P11) — renouveau réel via clic, reset + avantage permanent
  await page.evaluate(() => window.__game_debug.donnerRonrons(500));
  const gainAvantRenouveau = await gainParCaresseOf(page);
  const renouveauBtn = page.locator('[data-testid="renouveau_portee"]');
  await page.waitForFunction(() => !document.getElementById('renouveau_portee').disabled,
    null, { timeout: 2000 });
  await renouveauBtn.click();
  await page.waitForFunction(() => Number(document.getElementById('prestige').getAttribute('data-prestige')) > 0,
    null, { timeout: 2000 });
  const ronronsApresRenouveau = await ronronsOf(page);
  const prestigeApresRenouveau = await prestigeOf(page);
  const gainApresRenouveau = await gainParCaresseOf(page);
  expect(ronronsApresRenouveau === 0, `ronrons doit retomber à 0 après renouveau (lu ${ronronsApresRenouveau})`);
  expect(prestigeApresRenouveau > 0, 'prestige doit être positif après renouveau');
  expect(gainApresRenouveau > gainAvantRenouveau,
    `gainParCaresse doit augmenter après renouveau (${gainAvantRenouveau} -> ${gainApresRenouveau})`);
  log.push(`P10/P11 : clic renouveau_portee -> ronrons=0, prestige=${prestigeApresRenouveau}, ` +
    `gainParCaresse ${gainAvantRenouveau} -> ${gainApresRenouveau}`);
}

async function main() {
  let chromium;
  try {
    chromium = loadChromium();
  } catch (err) {
    console.error(`✗ ${err.message}`);
    console.log('RESULT: FAIL');
    process.exit(1);
    return;
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

#!/usr/bin/env node
// Oracle de SOLVABILITÉ — bot-joueur DOM-ONLY : clics réels + lecture du DOM, dans un
// navigateur réel. JAMAIS un appel direct à l'économie interne (ni import de logic.mjs,
// ni window.__game/__game_debug) : c'est une exigence NON DÉLÉGUÉE du brief
// (EVIDENCE/briefs/chaton_clicker/project_brief.yaml, criteres_sortie), dérivée de la
// leçon V1 kitten_clicker (run 6, 2026-08-22) — un bot qui appelle l'API interne a déjà
// produit un jeu « solvable 20/20 » mais injouable. Le bot ne connaît que ce qu'un joueur
// humain verrait : le texte/les attributs du DOM, et les seules affordances cliquables.
//
// Usage : node solvability.mjs [budget_actions]
import { spawn } from 'node:child_process';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { homedir } from 'node:os';

const __dirname = dirname(fileURLToPath(import.meta.url));
const require = createRequire(import.meta.url);

const PORT = Number.parseInt(process.env.CHATON_CLICKER_SOLV_PORT ?? '4532', 10);
const SEED = 555;
const PAGE_URL = `http://localhost:${PORT}/?seed=${SEED}`;
const BUDGET = Number.parseInt(process.argv[2] ?? '400', 10);

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

// --- lecture DOM seule — jamais window.__game ------------------------------------------

async function lireEtat(page) {
  return page.evaluate(() => {
    const ronronsEl = document.getElementById('compteur-ronrons');
    const prestigeEl = document.getElementById('prestige');
    const renouveauEl = document.getElementById('renouveau_portee');
    const p0 = document.querySelector('[data-testid="acheter_producteur_0"]');
    return {
      ronrons: Number(ronronsEl?.getAttribute('data-ronrons') ?? '0'),
      prestige: Number(prestigeEl?.getAttribute('data-prestige') ?? '0'),
      renouveauAbordable: renouveauEl ? !renouveauEl.disabled : false,
      producteur0Abordable: p0 ? !p0.disabled : false,
      producteur0Possede: p0 ? Number(p0.getAttribute('data-count') ?? '0') > 0 : false,
      objectif: document.getElementById('objectif')?.textContent ?? '',
    };
  });
}

/** Politique DOM-only : achète dès que possible, renouvelle une fois un producteur acquis
 * et le renouveau redevenu abordable, caresse sinon. Aucune décision ne lit l'économie
 * interne — uniquement ce que `lireEtat` a lu dans le DOM. */
async function jouerUneAction(page, etat) {
  if (etat.producteur0Possede && etat.renouveauAbordable) {
    await page.click('[data-testid="renouveau_portee"]');
    return 'renouveau';
  }
  if (etat.producteur0Abordable) {
    await page.click('[data-testid="acheter_producteur_0"]');
    return 'achat';
  }
  await page.click('[data-testid="caresser_chaton"]');
  return 'caresse';
}

async function jouerPartie(page, log) {
  await page.goto(PAGE_URL, { waitUntil: 'domcontentloaded' });
  await page.waitForSelector('[data-testid="caresser_chaton"]', { timeout: 10000 });

  let actions = 0;
  let etat = await lireEtat(page);
  const objectifInitial = etat.objectif;
  log.push(`objectif initial (DOM) : "${objectifInitial.trim()}"`);

  while (actions < BUDGET && etat.prestige === 0) {
    const geste = await jouerUneAction(page, etat);
    actions += 1;
    await page.waitForTimeout(15); // laisse le tick déterministe (rAF) avancer
    etat = await lireEtat(page);
    if (geste === 'achat') log.push(`action ${actions} : achat producteur_0 (DOM), ronrons=${etat.ronrons}`);
    if (geste === 'renouveau') log.push(`action ${actions} : renouveau_portee (DOM), prestige=${etat.prestige}`);
  }

  return { actions, etatFinal: etat, budget: BUDGET };
}

async function main() {
  let chromium;
  try {
    chromium = loadChromium();
  } catch (err) {
    console.error(`✗ ${err.message}`);
    console.log('SOLVABILITY: FAIL');
    process.exit(1);
    return;
  }

  const server = await startServer();
  const browser = await chromium.launch({ headless: !process.env.HEADED, args: ['--disable-gpu'] });
  const log = [];
  let code = 0;
  try {
    const page = await browser.newPage({ viewport: { width: 900, height: 780 } });
    const { actions, etatFinal, budget } = await jouerPartie(page, log);
    const gagne = etatFinal.prestige > 0;

    const receipt = {
      canal: 'DOM-only (clics + lecture DOM, aucun appel interne)',
      actions_utilisees: actions,
      budget_actions: budget,
      prestige_final: etatFinal.prestige,
      ronrons_finaux: etatFinal.ronrons,
      gagne,
    };
    console.log(`FORGE_ORACLE solvability ${JSON.stringify(receipt, null, 2)}`);
    for (const line of log) console.log(`  ${line}`);

    if (gagne) {
      console.log('SOLVABILITY: PASS');
    } else {
      console.error(`SOLVABILITY: FAIL — budget de ${budget} actions épuisé sans prestige > 0`);
      code = 1;
    }
  } catch (err) {
    console.error(`✗ SOLVABILITY ERROR : ${err.message}`);
    console.log('SOLVABILITY: FAIL');
    code = 1;
  } finally {
    await browser.close();
    server.kill();
  }
  process.exit(code);
}

main().catch((err) => {
  console.error(err);
  console.log('SOLVABILITY: FAIL');
  process.exit(1);
});

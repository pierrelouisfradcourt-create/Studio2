// Outillage navigateur partagé par e2e.mjs et shots.mjs : résolution de Playwright,
// démarrage du serveur du jeu, et doigts tactiles multiples via CDP.
//
// Résolution de Playwright, dans l'ordre : dépendance locale, PLAYWRIGHT_NODE_MODULES,
// installation globale (`npm root -g`). Aucune ne répond -> erreur explicite.

import { spawn, execSync } from 'node:child_process';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

export const GAME_DIR = join(dirname(fileURLToPath(import.meta.url)), '..');
const require = createRequire(import.meta.url);

function globalRoot() {
  try {
    return execSync('npm root -g', { stdio: ['ignore', 'pipe', 'ignore'] }).toString().trim();
  } catch {
    return null;
  }
}

export function loadChromium() {
  try {
    return require('playwright').chromium;
  } catch {
    // racines suivantes
  }
  const roots = [process.env.PLAYWRIGHT_NODE_MODULES, globalRoot()].filter(Boolean);
  for (const root of roots) {
    try {
      return createRequire(join(root, 'index.js'))('playwright').chromium;
    } catch {
      // racine suivante
    }
  }
  throw new Error(`playwright introuvable (essayé : local, ${roots.join(', ')}) — définir PLAYWRIGHT_NODE_MODULES`);
}

/** Démarre server.mjs sur `port` ; rend le processus une fois l'écoute confirmée. */
export function startServer(port) {
  const proc = spawn(process.execPath, [join(GAME_DIR, 'server.mjs')], {
    env: { ...process.env, DUNGEON_666_PORT: String(port), DUNGEON_666_HOST: '127.0.0.1' },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('serveur trop long à démarrer')), 10000);
    proc.stdout.on('data', (chunk) => {
      if (String(chunk).includes('interface jouable')) {
        clearTimeout(timer);
        resolve(proc);
      }
    });
    proc.stderr.on('data', (chunk) => process.stderr.write(`[srv] ${chunk}`));
    proc.on('exit', (code) => {
      clearTimeout(timer);
      reject(new Error(`serveur arrêté prématurément (code ${code})`));
    });
  });
}

/**
 * Doigts tactiles réels (CDP Input.dispatchTouchEvent) : le navigateur génère de vrais
 * PointerEvents de type "touch", plusieurs doigts simultanés possibles.
 * `fingers` : Map id -> {x, y} des doigts actuellement posés.
 */
export async function createTouch(page) {
  const cdp = await page.context().newCDPSession(page);
  const fingers = new Map();
  const points = () => [...fingers.entries()].map(([id, p]) => ({ x: p.x, y: p.y, id, radiusX: 8, radiusY: 8, force: 1 }));
  return {
    async down(id, x, y) {
      fingers.set(id, { x, y });
      await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: points() });
    },
    async move(id, x, y) {
      fingers.set(id, { x, y });
      await cdp.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: points() });
    },
    async up(id) {
      const p = fingers.get(id);
      if (!p) return;
      fingers.delete(id);
      // Mesuré sur Chromium : touchEnd relâche les points LISTÉS (pas « tous »). On ne liste
      // donc que le doigt levé ; les autres restent posés.
      await cdp.send('Input.dispatchTouchEvent', {
        type: 'touchEnd',
        touchPoints: [{ x: p.x, y: p.y, id, radiusX: 8, radiusY: 8, force: 1 }],
      });
    },
    async tap(id, x, y, holdMs = 60) {
      await this.down(id, x, y);
      await page.waitForTimeout(holdMs);
      await this.up(id);
    },
  };
}

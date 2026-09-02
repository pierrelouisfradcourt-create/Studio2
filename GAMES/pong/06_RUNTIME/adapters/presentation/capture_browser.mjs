// PONG — capture PIXEL de l'adaptateur NAVIGATEUR, en mode headless (ADAPTATEUR).
// Rend DEUX etats differents via le meme drawState() que le <canvas> reel, sur la
// Surface logicielle, et ecrit deux PNG. Critere mecanique (core.render, volet
// navigateur) : les deux captures DIFFERENT et AUCUNE n'est monochrome.
// Note d'evidence : c'est la rasterisation logicielle du MEME code de dessin que
// l'index.html ; ce n'est pas une capture d'un Chrome reel (cf. fog du rapport).
import { writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { boot, step } from '../../../05_SYSTEMS/game_loop/loop.mjs';
import { translate } from '../../../05_SYSTEMS/input/input.mjs';
import { drawState, VIEW_W, VIEW_H } from './draw.mjs';
import { Surface } from './raster.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));

// Etat B : quelques ticks de jeu (balle deplacee, raquettes bougees, peut-etre un point).
function midGameState(seed = 1, ticks = 45) {
  let s = boot(seed);
  for (let i = 0; i < ticks; i += 1) {
    const raw = { p1: s.ball.y > s.p1.y + 12 ? 'down' : 'up', p2: 'up' };
    s = step(s, translate(raw)).state;
  }
  return s;
}

function render(state) {
  const surf = new Surface(VIEW_W, VIEW_H);
  drawState(state, surf);
  return surf;
}

export function capture(outDir = join(HERE, 'shots')) {
  mkdirSync(outDir, { recursive: true });
  const a = render(boot(1));
  const b = render(midGameState(1, 45));

  const pathA = join(outDir, 'browser_a.png');
  const pathB = join(outDir, 'browser_b.png');
  writeFileSync(pathA, a.toPNG());
  writeFileSync(pathB, b.toPNG());

  const differ = Buffer.compare(Buffer.from(a.buf), Buffer.from(b.buf)) !== 0;
  const colorsA = a.distinctColors();
  const colorsB = b.distinctColors();
  const monochromeA = colorsA < 2;
  const monochromeB = colorsB < 2;
  const passed = differ && !monochromeA && !monochromeB;

  return {
    adapter: 'browser', passed, differ,
    colorsA, colorsB, monochromeA, monochromeB,
    files: { a: pathA, b: pathB },
  };
}

if (process.argv[1]?.endsWith('capture_browser.mjs')) {
  const r = capture();
  process.stdout.write(JSON.stringify(r, null, 1) + '\n');
  process.exit(r.passed ? 0 : 1);
}

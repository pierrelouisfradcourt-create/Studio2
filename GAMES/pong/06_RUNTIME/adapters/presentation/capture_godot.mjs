// PONG — capture PIXEL de l'adaptateur GODOT (ADAPTATEUR). Ecrit deux etats
// (produits par la logique JS pure) en JSON, lance Godot en FENETRE GPU offscreen
// (--rendering-driver vulkan --position -3000,-3000 : --headless rendrait une
// texture NULLE, cf. regle du standard), capture deux PNG et verifie le critere
// mecanique de core.render cote Godot : les deux captures DIFFERENT et AUCUNE
// n'est monochrome (nombre de couleurs distinctes >= 2, lu sur stdout du script).
import { spawnSync } from 'node:child_process';
import { writeFileSync, mkdirSync, existsSync, readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { boot, step } from '../../../05_SYSTEMS/game_loop/loop.mjs';
import { translate } from '../../../05_SYSTEMS/input/input.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const GODOT_PROJECT = join(HERE, 'godot');

function midGameState(seed = 1, ticks = 45) {
  let s = boot(seed);
  for (let i = 0; i < ticks; i += 1) {
    const raw = { p1: s.ball.y > s.p1.y + 12 ? 'down' : 'up', p2: 'up' };
    s = step(s, translate(raw)).state;
  }
  return s;
}

function runGodot(godotBin, statePath, outPath) {
  const args = [
    '--path', GODOT_PROJECT,
    '--rendering-driver', 'vulkan',
    '--position', '-3000,-3000',
    '--', '--state', statePath, '--out', outPath,
  ];
  const res = spawnSync(godotBin, args, { encoding: 'utf-8', timeout: 60000 });
  const stdout = (res.stdout || '') + (res.stderr || '');
  const m = stdout.match(/PONG_CAPTURE out=(\S*) colors=(\d+) size=(\d+x\d+) err=(-?\d+)/);
  return {
    ran: res.status === 0 || m != null,
    status: res.status,
    colors: m ? parseInt(m[2], 10) : null,
    size: m ? m[3] : null,
    saveErr: m ? parseInt(m[4], 10) : null,
    stdout: stdout.slice(-600),
    error: res.error ? String(res.error) : null,
  };
}

export async function capture(outDir = join(HERE, 'shots')) {
  mkdirSync(outDir, { recursive: true });
  let resolveGodotBin;
  try {
    ({ resolveGodotBin } = await import(new URL('../../../../../scripts/forge/godot_bin.mjs', import.meta.url)));
  } catch (e) {
    return { adapter: 'godot', passed: false, blocked: true, reason: `godot_bin.mjs illisible: ${e.message}` };
  }
  let godotBin;
  try {
    godotBin = resolveGodotBin();
  } catch (e) {
    return { adapter: 'godot', passed: false, blocked: true, reason: e.message };
  }

  const stateA = join(outDir, 'godot_state_a.json');
  const stateB = join(outDir, 'godot_state_b.json');
  const pngA = resolve(join(outDir, 'godot_a.png'));
  const pngB = resolve(join(outDir, 'godot_b.png'));
  writeFileSync(stateA, JSON.stringify(boot(1)), 'utf-8');
  writeFileSync(stateB, JSON.stringify(midGameState(1, 45)), 'utf-8');

  const runA = runGodot(godotBin, resolve(stateA), pngA);
  const runB = runGodot(godotBin, resolve(stateB), pngB);

  const bothExist = existsSync(pngA) && existsSync(pngB);
  let differ = false;
  if (bothExist) {
    differ = Buffer.compare(readFileSync(pngA), readFileSync(pngB)) !== 0;
  }
  const colorsOk = (runA.colors ?? 0) >= 2 && (runB.colors ?? 0) >= 2;
  const savedOk = runA.saveErr === 0 && runB.saveErr === 0;
  const passed = bothExist && differ && colorsOk && savedOk;

  return {
    adapter: 'godot', passed, godotBin, bothExist, differ, colorsOk, savedOk,
    runA, runB, files: { a: pngA, b: pngB },
  };
}

if (process.argv[1]?.endsWith('capture_godot.mjs')) {
  const r = await capture();
  process.stdout.write(JSON.stringify(r, null, 1) + '\n');
  process.exit(r.passed ? 0 : 1);
}

#!/usr/bin/env node
// Passerelle vers la version Godot (GAMES/dungeon_666_godot) : la simulation web est la
// SPÉCIFICATION, ce script en tire tout ce dont le portage a besoin pour être comparé à elle.
//
//   node tools/export_godot.mjs [données] [vecteurs] [traces]      (rien = tout)
//   node tools/export_godot.mjs dense <nom de trace>               une empreinte PAR IMAGE, pour
//                                                                  localiser une divergence (dense_<nom>.json)
//
//   données  -> data/tuning.json, data/tables.json : tous les nombres et tables du jeu ;
//   vecteurs -> parite/vecteurs/<module>.json : entrées et sorties de fonctions pures ;
//   traces   -> parite/traces/<nom>.json : parties jouées par les bots (entrées image par image,
//               commandes de menu, empreintes d'état) que Godot rejoue et compare.
//
// NOMBRES EXACTS : mesuré le 2026-10-01, Godot ne lit pas les décimaux comme JavaScript (14 %
// des nombres diffèrent au dernier bit). Tout nombre non entier est donc écrit « ~ » + les 16
// chiffres hexadécimaux de ses 8 octets (double IEEE, petit-boutiste) ; Godot le reconstruit
// à l'identique (sim/js.gd, decode). Les entiers restent lisibles.

import { writeFileSync, mkdirSync, readdirSync } from 'node:fs';
import { dirname, resolve, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const GAME_DIR = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const OUT_DIR = resolve(GAME_DIR, '..', 'dungeon_666_godot');
const EXACT_PREFIX = '~';

/** Copie de `v` où chaque nombre non entier devient sa forme exacte. */
export function exact(v) {
  if (typeof v === 'number') {
    if (Number.isInteger(v) && Math.abs(v) <= Number.MAX_SAFE_INTEGER && !Object.is(v, -0)) return v;
    if (!Number.isFinite(v)) return `${EXACT_PREFIX}${v > 0 ? 'inf' : v < 0 ? '-inf' : 'nan'}`;
    const b = Buffer.alloc(8);
    b.writeDoubleLE(v);
    return EXACT_PREFIX + b.toString('hex');
  }
  if (typeof v === 'string') {
    if (v.startsWith(EXACT_PREFIX)) throw new Error(`chaîne réservée : ${v}`);
    return v;
  }
  if (v === undefined) return null;
  if (v === null || typeof v === 'boolean') return v;
  if (v instanceof Set) return [...v].map(exact);
  if (Array.isArray(v) || ArrayBuffer.isView(v)) return Array.from(v, exact);
  if (typeof v === 'object') return Object.fromEntries(Object.entries(v).filter(([, x]) => typeof x !== 'function').map(([k, x]) => [k, exact(x)]));
  throw new Error(`valeur non exportable : ${typeof v}`);
}

function isPureData(v, seen = new Set()) {
  if (v === null) return true;
  const t = typeof v;
  if (t === 'function' || t === 'undefined' || t === 'symbol') return false;
  if (t !== 'object') return true;
  if (v instanceof Map) return false;
  if (seen.has(v)) return true;
  seen.add(v);
  return Object.values(v instanceof Set ? [...v] : v).every((x) => isPureData(x, seen));
}

function write(rel, value) {
  const path = join(OUT_DIR, rel);
  mkdirSync(dirname(path), { recursive: true });
  const text = JSON.stringify(value);
  writeFileSync(path, text);
  console.log(`  ${rel} (${(text.length / 1024).toFixed(1)} Ko)`);
}

// ---------------------------------------------------------------- données

async function exportData() {
  const { DEFAULT_TUNING } = await import('../src/sim/config.mjs');
  write('data/tuning.json', exact(DEFAULT_TUNING));
  const tables = {};
  for (const f of readdirSync(join(GAME_DIR, 'src/sim')).sort()) {
    const mod = await import(pathToFileURL(join(GAME_DIR, 'src/sim', f)).href);
    const name = f.replace('.mjs', '');
    for (const [k, v] of Object.entries(mod)) {
      if (k === 'DEFAULT_TUNING' || typeof v === 'function' || !isPureData(v)) continue;
      (tables[name] ??= {})[k] = exact(v);
    }
  }
  write('data/tables.json', tables);
}

// ---------------------------------------------------------------- vecteurs

/**
 * Vecteurs : chaque fichier tools/vecteurs/<lot>.mjs exporte VECTORS = { module: async () =>
 * [{fn, cases: [{args, out}]}] }. Côté Godot, parite/adaptateurs/<module>.gd les rejoue.
 */
async function exportVectors() {
  const dir = join(GAME_DIR, 'tools/vecteurs');
  for (const f of readdirSync(dir).filter((x) => x.endsWith('.mjs') && !x.startsWith('_')).sort()) {
    const { VECTORS } = await import(pathToFileURL(join(dir, f)).href);
    for (const [name, build] of Object.entries(VECTORS)) write(`parite/vecteurs/${name}.json`, exact(await build()));
  }
}
// ---------------------------------------------------------------- traces

async function exportTraces() {
  const { TRACES, recordTrace } = await import('./traces.mjs');
  for (const spec of TRACES) write(`parite/traces/${spec.name}.json`, exact(recordTrace(spec)));
}

// ----------------------------------------------------------------

async function exportDense(name) {
  const { TRACES, recordTrace } = await import('./traces.mjs');
  const spec = TRACES.find((s) => s.name === name);
  if (!spec) throw new Error(`trace inconnue : ${name}`);
  write(`parite/traces_denses/dense_${name}.json`, exact({ ...recordTrace(spec, 1), name: `dense_${name}` }));
}

async function main() {
  const want = process.argv.slice(2);
  console.log(`export vers ${OUT_DIR}`);
  if (want[0] === 'dense') return exportDense(want[1]);
  const all = want.length === 0;
  if (all || want.includes('données') || want.includes('donnees')) await exportData();
  if (all || want.includes('vecteurs')) await exportVectors();
  if (all || want.includes('traces')) await exportTraces();
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) await main();

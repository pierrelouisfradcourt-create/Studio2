#!/usr/bin/env node
// Harnais d'oracles de Dungeon 666 — même forme que les jeux web du studio
// (GAMES/v2_breakout_slice/run-oracle.mjs). Code de sortie 1 si un volet BLOQUANT échoue.
//
//   (a) règles         tests/logic.test.mjs        une règle, un test (dash, combo, i-frames, 666…)
//   (b) propriétés     tests/properties*.test.mjs  déterminisme et invariants sur longues parties
//   (c) audio          tests/audio.test.mjs        sons procéduraux sans erreur, polyphonie bornée
//   (d) fichier unique tools/bundle.mjs      dist/dungeon_666.html se construit
//   (e) solvabilité    solvability.mjs       un bot bat la section 1 ; le dash compte
//   (f) e2e            e2e.mjs               navigateur réel, doigts tactiles, clavier, clics
//   (g) mesure         tools/playtest.mjs    rapport de feel des bots (non bloquant)
//
// Les tests vivent sous tests/ : surface protégée du studio (forge/test_surfaces.yaml) — les
// créer est permis, les modifier après coup demande une gate Pierre.
//
// Usage : node run-oracle.mjs

import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname } from 'node:path';

const GAME_DIR = dirname(fileURLToPath(import.meta.url));

const STEPS = [
  { label: 'règles (tests unitaires)', argv: ['node', '--test', 'tests/logic.test.mjs', 'tests/feel_review.test.mjs'], gating: true },
  { label: 'propriétés', argv: ['node', '--test', 'tests/properties.test.mjs', 'tests/properties_strict.test.mjs'], gating: true },
  { label: 'audio', argv: ['node', '--test', 'tests/audio.test.mjs'], gating: true },
  { label: 'fichier unique jouable', argv: ['node', 'tools/bundle.mjs'], gating: true },
  { label: 'solvabilité (un bot bat la section 1)', argv: ['node', 'solvability.mjs', '20'], gating: true },
  { label: 'e2e navigateur réel', argv: ['node', 'e2e.mjs'], gating: true },
  { label: 'rapport de playtest des bots', argv: ['node', 'tools/playtest.mjs', '--seeds', '20'], gating: false },
];

function run(argv) {
  return new Promise((accept) => {
    const child = spawn(argv[0], argv.slice(1), { cwd: GAME_DIR, stdio: 'inherit' });
    child.on('close', (code) => accept(code));
    child.on('error', () => accept(127));
  });
}

async function main() {
  console.log('=== Dungeon 666 — suite d\'oracles ===\n');
  const failures = [];
  for (let i = 0; i < STEPS.length; i++) {
    const step = STEPS[i];
    console.log(`[${i + 1}/${STEPS.length}] ${step.label}${step.gating ? '' : ' (mesure, non bloquant)'}...`);
    const code = await run(step.argv);
    if (code === 0) {
      console.log(`OK — ${step.label}\n`);
    } else if (step.gating) {
      failures.push(`${step.label} (code ${code})`);
      console.error(`ECHEC — ${step.label} (code ${code})\n`);
    } else {
      console.warn(`MESURE NON ABOUTIE — ${step.label} (code ${code}) — ne bloque pas\n`);
    }
  }
  console.log('=== fin de la suite ===');
  if (failures.length > 0) {
    console.error(`volets rouges : ${failures.join(' | ')}`);
    process.exit(1);
  }
  console.log('tous les volets bloquants sont verts');
  process.exit(0);
}

main();

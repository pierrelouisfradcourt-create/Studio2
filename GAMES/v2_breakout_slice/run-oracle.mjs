#!/usr/bin/env node
// Harnais d'oracle du jeu — c'est CE fichier que forge_gate exécute (oracles.json).
// Quatre volets qui GATENT (exit != 0 si l'un échoue) :
//   (a) tests unitaires   — une règle, un test, hors navigateur
//   (b) tests de propriétés — invariants sur de longues séquences et plusieurs seeds
//   (c) solvabilité       — solvability.mjs : un bot JOUE et doit GAGNER
//   (d) e2e               — e2e.mjs : click-through navigateur RÉEL (PLAYABLE_CONTRACT)
// Un volet de MESURE, non bloquant et déclaré comme tel :
//   (e) reuse_ratio.mjs   — mesure de réutilisation de la bibliothèque (ne prouve rien)

import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname, join, resolve } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(__dirname, '..', '..');

function run(argv) {
  return new Promise((accept) => {
    const child = spawn(argv[0], argv.slice(1), { cwd: __dirname, stdio: 'inherit' });
    child.on('close', (code) => accept(code));
    child.on('error', () => accept(127));
  });
}

const STEPS = [
  { label: 'tests unitaires', argv: ['node', '--test', 'logic.test.mjs'], gating: true },
  { label: 'tests de propriétés', argv: ['node', '--test', 'properties.test.mjs'], gating: true },
  { label: 'solvabilité (un bot joue et gagne)', argv: ['node', 'solvability.mjs', '30000', '10'], gating: true },
  { label: 'e2e navigateur réel', argv: ['node', 'e2e.mjs'], gating: true },
  { label: 'mesure de réutilisation', argv: ['node', join(REPO_ROOT, 'forge', 'reuse_ratio.mjs'), __dirname], gating: false },
];

async function main() {
  console.log('=== v2_breakout_slice — suite d\'oracles ===\n');
  const failures = [];

  for (let i = 0; i < STEPS.length; i++) {
    const step = STEPS[i];
    console.log(`[${i + 1}/${STEPS.length}] ${step.label}${step.gating ? '' : ' (mesure, non bloquant)'}...`);
    const code = await run(step.argv);
    if (code === 0) {
      console.log(`OK — ${step.label}\n`);
      continue;
    }
    if (step.gating) {
      failures.push(`${step.label} (code ${code})`);
      console.error(`ECHEC — ${step.label} (code ${code})\n`);
    } else {
      console.warn(`MESURE NON ABOUTIE — ${step.label} (code ${code}) — ne bloque pas le gate\n`);
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

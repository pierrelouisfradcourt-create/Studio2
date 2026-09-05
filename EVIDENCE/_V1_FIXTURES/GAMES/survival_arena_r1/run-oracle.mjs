#!/usr/bin/env node
// run-oracle.mjs -- single entry point for the Survival Arena oracle.
// Runs, in order: logic.test.mjs (strict unit tests), properties.test.mjs
// (invariants across ~40 seeds), solvability.mjs (black-box playability).
// Exit 0 ONLY if all three pass. No e2e/browser step here by design.

import { spawnSync } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const STEPS = [
  { name: 'logic.test.mjs', cmd: process.execPath, args: ['--test', 'logic.test.mjs'] },
  { name: 'properties.test.mjs', cmd: process.execPath, args: ['--test', 'properties.test.mjs'] },
  { name: 'solvability.mjs', cmd: process.execPath, args: ['solvability.mjs'] },
];

let allOk = true;
const summary = [];

for (const step of STEPS) {
  console.log(`\n=== ${step.name} ===`);
  const result = spawnSync(step.cmd, step.args, { cwd: __dirname, stdio: 'inherit' });
  const ok = result.status === 0;
  allOk = allOk && ok;
  summary.push({ name: step.name, ok, status: result.status });
}

console.log('\n=== ORACLE SUMMARY ===');
for (const s of summary) {
  console.log(`[${s.ok ? 'PASS' : 'FAIL'}] ${s.name} (exit ${s.status})`);
}
console.log(allOk ? '\nORACLE: GREEN (0)' : '\nORACLE: RED (1)');

process.exit(allOk ? 0 : 1);

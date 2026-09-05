// run-oracle.mjs — single gate: logic + properties + solvability. Exit 0 only if ALL pass.
// No e2e/browser step here by design (see FORGE_DISPATCH spec).
// Run: node run-oracle.mjs
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const dir = path.dirname(fileURLToPath(import.meta.url));

function run(label, cmd, args) {
  console.log(`\n=== ${label} ===`);
  const result = spawnSync(cmd, args, { cwd: dir, stdio: 'inherit', encoding: 'utf-8' });
  const ok = result.status === 0;
  console.log(`--- ${label}: ${ok ? 'PASS' : 'FAIL'} (exit ${result.status}) ---`);
  return ok;
}

const results = [
  run('logic.test.mjs', process.execPath, ['--test', 'logic.test.mjs']),
  run('properties.test.mjs', process.execPath, ['--test', 'properties.test.mjs']),
  run('solvability.mjs', process.execPath, ['solvability.mjs']),
];

const allPass = results.every(Boolean);
console.log(`\n=== ORACLE SUMMARY ===`);
console.log(`logic:        ${results[0] ? 'PASS' : 'FAIL'}`);
console.log(`properties:   ${results[1] ? 'PASS' : 'FAIL'}`);
console.log(`solvability:  ${results[2] ? 'PASS' : 'FAIL'}`);
console.log(allPass ? 'GLOBAL: PASS (exit 0)' : 'GLOBAL: FAIL (exit 1)');

process.exit(allPass ? 0 : 1);

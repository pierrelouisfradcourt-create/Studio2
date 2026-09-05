// run-oracle.mjs — Collect Runner oracle gate.
// Runs logic tests, property tests, and the solvability harness as separate
// child processes (so a crash in one never masks the others). Exit code 0
// only if all three pass.

import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

function run(label, args) {
  return new Promise((resolve) => {
    const child = spawn(process.execPath, args, {
      cwd: __dirname,
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    let stdout = '';
    let stderr = '';
    child.stdout.on('data', (d) => { stdout += d; });
    child.stderr.on('data', (d) => { stderr += d; });
    child.on('close', (code) => {
      resolve({ label, code, stdout, stderr });
    });
    child.on('error', (err) => {
      resolve({ label, code: 1, stdout, stderr: stderr + '\n' + String(err) });
    });
  });
}

async function main() {
  const steps = [
    { label: 'logic', args: ['--test', 'logic.test.mjs'] },
    { label: 'properties', args: ['--test', 'properties.test.mjs'] },
    { label: 'solvability', args: ['solvability.mjs'] },
  ];

  let allPass = true;

  for (const step of steps) {
    console.log(`\n=== [run-oracle] ${step.label} ===`);
    const result = await run(step.label, step.args);
    if (result.stdout) process.stdout.write(result.stdout);
    if (result.stderr) process.stderr.write(result.stderr);
    const pass = result.code === 0;
    console.log(`=== [run-oracle] ${step.label}: ${pass ? 'PASS' : 'FAIL'} (exit ${result.code}) ===`);
    if (!pass) allPass = false;
  }

  console.log(`\n[run-oracle] GLOBAL VERDICT: ${allPass ? 'PASS' : 'FAIL'}`);
  process.exit(allPass ? 0 : 1);
}

main();

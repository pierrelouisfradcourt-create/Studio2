// Oracle déterministe — point d'entrée.
// Exécute les tests et oracles: logique, solvabilité, e2e (+ mesure de réutilisation).

import { spawn } from "node:child_process";
import { fileURLToPath, pathToFileURL } from "node:url";
import { dirname, join, resolve } from "node:path";
import { existsSync } from "node:fs";

const __dirname = dirname(fileURLToPath(import.meta.url));

function run(label, fileOrArgs, extraEnv = {}) {
  return new Promise((resolvePromise) => {
    const chunks = [];
    // Support both single file and array of args
    const args = Array.isArray(fileOrArgs) ? fileOrArgs : [fileOrArgs];
    const proc = spawn(process.execPath, args, {
      cwd: __dirname,
      env: { ...process.env, ...extraEnv },
      stdio: ["ignore", "pipe", "pipe"],
    });
    proc.stdout.on("data", (d) => { chunks.push(d); process.stdout.write(d); });
    proc.stderr.on("data", (d) => { chunks.push(d); process.stderr.write(d); });
    proc.on("error", (err) => {
      resolvePromise(resultFromError(label, err));
    });
    proc.on("exit", (code) => {
      resolvePromise(resultFromExit(label, code, chunks.map(String).join("")));
    });
  });
}

// --- Pièces pures, testables hors subprocess (node --test importe ce module) ---

export function resultFromExit(label, code, output) {
  return { label, ok: code === 0, code, output };
}

export function resultFromError(label, err) {
  return { label, ok: false, code: -1, output: String(err), launchFailure: true };
}

export function allPassed(logicResult, solvResult, e2eResult) {
  return logicResult.ok && solvResult.ok && e2eResult.ok;
}

async function main() {
  console.log("--- ORACLE runm_breakout ---\n");

  console.log("--- (a) logique: node --test logic.test.mjs properties.test.mjs ---");
  const logicResult = await run("logique", ["--test", "logic.test.mjs", "properties.test.mjs"]);
  console.log(`\n[logique] exit code = ${logicResult.code}\n`);

  console.log("--- (b) solvabilité: solvability.mjs ---");
  const solvResult = await run("solvabilité", "solvability.mjs");
  console.log(`\n[solvabilité] exit code = ${solvResult.code}\n`);

  console.log("--- (c) e2e: e2e.mjs ---");
  const e2eResult = await run("e2e", "e2e.mjs");
  console.log(`\n[e2e] exit code = ${e2eResult.code}\n`);

  console.log("--- (d) reuse_ratio: mesure de réutilisation (advisory, ne bloque pas le verdict) ---");
  const forgeDir = resolve(__dirname, "..", "..", "forge");
  if (existsSync(join(forgeDir, "reuse_ratio.mjs"))) {
    const reuseResult = await run("reuse_ratio", [join(forgeDir, "reuse_ratio.mjs"), __dirname]);
    console.log(`[reuse_ratio] exit code = ${reuseResult.code}\n`);
  } else {
    console.log("[reuse_ratio] forge/reuse_ratio.mjs introuvable — mesure sautée\n");
  }

  const allOk = allPassed(logicResult, solvResult, e2eResult);

  console.log("--- RÉSUMÉ ORACLE ---");
  console.log(`logique : ${logicResult.ok ? "PASS" : "FAIL"} (code ${logicResult.code})`);
  console.log(`solvabilité : ${solvResult.ok ? "PASS (bot gagne)" : "FAIL"} (code ${solvResult.code})`);
  console.log(`e2e : ${e2eResult.ok ? "PASS" : "FAIL"} (code ${e2eResult.code})`);
  console.log(`\nVERDICT ORACLE: ${allOk ? "PASS" : "FAIL"}`);

  process.exit(allOk ? 0 : 1);
}

if (import.meta.url === pathToFileURL(process.argv[1] || "").href) {
  main();
}

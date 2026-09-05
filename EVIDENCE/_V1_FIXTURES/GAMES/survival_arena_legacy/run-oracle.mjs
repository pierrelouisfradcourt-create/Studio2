// Survival Arena — POINT D'ENTRÉE de l'oracle déterministe.
// (a) exécute les tests de logique pure (node --test logic.test.mjs)
// (b) exécute l'e2e Playwright (e2e.mjs), avec NODE_PATH pointé vers les node_modules
//     de belote-claude pour résoudre "playwright" sans dépendance locale dupliquée.
// Exit code 0 SEULEMENT si les deux volets passent. Sinon non-zéro, résumé lisible.
// L'oracle ne doit jamais mentir vert : une indisponibilité d'environnement (navigateur
// introuvable, etc.) est un échec explicite, pas un succès déguisé.
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, join, resolve } from "node:path";
import { existsSync } from "node:fs";

const __dirname = dirname(fileURLToPath(import.meta.url));
const BELOTE_NODE_MODULES = resolve(
  __dirname,
  "..",
  "..",
  "llm-lego",
  "experiments",
  "belote-claude",
  "node_modules"
);

function run(label, file, extraEnv = {}) {
  return new Promise((resolvePromise) => {
    const chunks = [];
    const proc = spawn(process.execPath, [file], {
      cwd: __dirname,
      env: { ...process.env, ...extraEnv },
      stdio: ["ignore", "pipe", "pipe"],
    });
    proc.stdout.on("data", (d) => { chunks.push(d); process.stdout.write(d); });
    proc.stderr.on("data", (d) => { chunks.push(d); process.stderr.write(d); });
    proc.on("error", (err) => {
      resolvePromise({ label, ok: false, code: -1, output: String(err), launchFailure: true });
    });
    proc.on("exit", (code) => {
      resolvePromise({ label, ok: code === 0, code, output: chunks.map(String).join("") });
    });
  });
}

async function main() {
  console.log("=== ORACLE Survival Arena ===\n");

  console.log("--- (a) logic tests: node --test logic.test.mjs ---");
  const logicResult = await run("logic tests", "logic.test.mjs");
  console.log(`\n[logic tests] exit code = ${logicResult.code}\n`);

  console.log("--- (b) e2e Playwright: e2e.mjs ---");
  if (!existsSync(BELOTE_NODE_MODULES)) {
    console.log(
      `AVERTISSEMENT : node_modules introuvable à ${BELOTE_NODE_MODULES} — playwright ne pourra probablement pas se résoudre.`
    );
  }
  const e2eResult = await run("e2e Playwright", "e2e.mjs", { NODE_PATH: BELOTE_NODE_MODULES });
  console.log(`\n[e2e Playwright] exit code = ${e2eResult.code}\n`);

  const allOk = logicResult.ok && e2eResult.ok;

  console.log("=== RÉSUMÉ ORACLE ===");
  console.log(`logic tests : ${logicResult.ok ? "PASS" : "FAIL"} (code ${logicResult.code})`);
  console.log(
    `e2e Playwright : ${e2eResult.ok ? "PASS" : e2eResult.launchFailure ? "FAIL (lancement navigateur impossible — environnement indisponible)" : "FAIL"} (code ${e2eResult.code})`
  );
  console.log(`\nVERDICT ORACLE: ${allOk ? "PASS" : "FAIL"}`);

  process.exit(allOk ? 0 : 1);
}

main();

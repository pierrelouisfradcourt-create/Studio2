#!/usr/bin/env node
// Bundler maison, sans dépendance : rassemble src/main.mjs et ses imports relatifs dans
// UN SEUL fichier HTML, jouable par double-clic (file://) et publiable tel quel.
//
// Pourquoi : les modules ES ne se chargent pas depuis file:// (CORS), et un téléphone
// ouvre plus volontiers un seul fichier qu'un serveur. Le code source reste en modules.
//
// Sous-ensemble ES accepté (refus explicite sinon, jamais un bundle faux en silence) :
//   import { a, b as c } from './x.mjs';   import * as X from './x.mjs';
//   export function|async function|const|let|class nom ;   export { a, b as c };
// Refusés : export default, import dynamique, import de paquet (non relatif).
//
// Usage : node tools/bundle.mjs                     -> dist/dungeon_666.html (document complet)
//         node tools/bundle.mjs --artifact <fichier> -> en plus, le fragment sans <html>/<head>/<body>
//                                                      pour une page hôte (publication), hors dépôt

import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { dirname, join, relative, resolve, posix } from 'node:path';

const GAME_DIR = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const ENTRY = 'src/main.mjs';
const SCRIPT_TAG = /<script type="module" src="\.\/src\/main\.mjs"><\/script>/;

const IMPORT_RE = /^\s*import\s+(?:(\{[\s\S]*?\})|\*\s+as\s+(\w+))\s+from\s+['"]([^'"]+)['"];?/gm;
const BARE_IMPORT_RE = /^\s*import\s+['"]([^'"]+)['"];?/gm;
const EXPORT_DECL_RE = /^export\s+(async\s+function\*?|function\*?|const|let|class)\s+([A-Za-z_$][\w$]*)/gm;
const EXPORT_LIST_RE = /^export\s*\{([^}]*)\};?/gm;

function fail(msg) {
  throw new Error(`[bundle] ${msg}`);
}

function toKey(absPath) {
  return relative(GAME_DIR, absPath).split('\\').join('/');
}

function parseSpecifiers(braced) {
  return braced
    .replace(/[{}]/g, '')
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean)
    .map((s) => {
      const m = s.match(/^([\w$]+)(?:\s+as\s+([\w$]+))?$/);
      if (!m) fail(`spécificateur d'import illisible : "${s}"`);
      return { imported: m[1], local: m[2] ?? m[1] };
    });
}

async function loadModule(key, modules, order, stack) {
  if (modules.has(key)) return;
  if (stack.includes(key)) fail(`import circulaire : ${[...stack, key].join(' -> ')}`);
  const src = await readFile(join(GAME_DIR, key), 'utf8');

  if (/^export\s+default\b/m.test(src)) fail(`${key} : export default non supporté`);
  if (/\bimport\s*\(/.test(src)) fail(`${key} : import dynamique non supporté`);

  const deps = [];
  let body = src.replace(IMPORT_RE, (_all, braced, star, spec) => {
    if (!spec.startsWith('.')) fail(`${key} : import non relatif "${spec}"`);
    const depKey = posix.normalize(posix.join(posix.dirname(key), spec));
    deps.push(depKey);
    if (star) return `const ${star} = __mod[${JSON.stringify(depKey)}];`;
    const specs = parseSpecifiers(braced)
      .map(({ imported, local }) => (imported === local ? imported : `${imported}: ${local}`));
    return `const { ${specs.join(', ')} } = __mod[${JSON.stringify(depKey)}];`;
  });
  body = body.replace(BARE_IMPORT_RE, (_all, spec) => {
    if (!spec.startsWith('.')) fail(`${key} : import non relatif "${spec}"`);
    deps.push(posix.normalize(posix.join(posix.dirname(key), spec)));
    return '';
  });
  if (/^\s*import\s/m.test(body)) fail(`${key} : forme d'import non supportée`);

  const exported = [];
  body = body.replace(EXPORT_DECL_RE, (_all, kind, name) => {
    exported.push({ local: name, name });
    return `${kind} ${name}`;
  });
  body = body.replace(EXPORT_LIST_RE, (_all, inner) => {
    for (const part of inner.split(',').map((s) => s.trim()).filter(Boolean)) {
      const m = part.match(/^([\w$]+)(?:\s+as\s+([\w$]+))?$/);
      if (!m) fail(`${key} : export illisible "${part}"`);
      exported.push({ local: m[1], name: m[2] ?? m[1] });
    }
    return '';
  });
  if (/^\s*export\s/m.test(body)) fail(`${key} : forme d'export non supportée`);

  stack.push(key);
  for (const dep of deps) await loadModule(dep, modules, order, stack);
  stack.pop();

  modules.set(key, { body, exported });
  order.push(key);
}

export async function buildBundleScript() {
  const modules = new Map();
  const order = [];
  await loadModule(ENTRY, modules, order, []);
  const parts = ['"use strict";', 'const __mod = Object.create(null);'];
  for (const key of order) {
    const { body, exported } = modules.get(key);
    const ret = exported.map(({ local, name }) => (local === name ? name : `${name}: ${local}`));
    parts.push(`// ---- ${key}`);
    parts.push(`__mod[${JSON.stringify(key)}] = (() => {\n${body}\nreturn { ${ret.join(', ')} };\n})();`);
  }
  return { code: parts.join('\n'), modules: order };
}

async function main() {
  const { code, modules } = await buildBundleScript();
  if (code.includes('</script')) fail('le code contient "</script" — il casserait le HTML');
  const html = await readFile(join(GAME_DIR, 'index.html'), 'utf8');
  if (!SCRIPT_TAG.test(html)) fail('index.html ne contient pas la balise <script type="module" src="./src/main.mjs">');
  const inline = `<script type="module">\n${code}\n</script>`;
  const full = html.replace(SCRIPT_TAG, () => inline);

  // Fragment pour une page hôte qui fournit déjà doctype/html/head/body (publication).
  const fragment = full
    .replace(/<!doctype html>\s*/i, '')
    .replace(/<\/?html[^>]*>\s*/gi, '')
    .replace(/<\/?head>\s*/gi, '')
    .replace(/<\/?body[^>]*>\s*/gi, '')
    .replace(/<meta charset[^>]*>\s*/i, '')
    .replace(/<meta name="viewport"[^>]*>\s*/i, '');

  const outDir = join(GAME_DIR, 'dist');
  await mkdir(outDir, { recursive: true });
  await writeFile(join(outDir, 'dungeon_666.html'), full);
  const flag = process.argv.indexOf('--artifact');
  if (flag > 0 && process.argv[flag + 1]) {
    const target = resolve(process.argv[flag + 1]);
    await mkdir(dirname(target), { recursive: true });
    await writeFile(target, fragment);
    console.log(`[bundle] fragment publiable -> ${target}`);
  }
  console.log(`[bundle] ${modules.length} modules -> dist/dungeon_666.html (${(full.length / 1024).toFixed(1)} Ko)`);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch((err) => {
    console.error(err.message);
    process.exit(1);
  });
}

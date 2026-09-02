#!/usr/bin/env node
// agent_context_map.mjs — CARTE DE CONTEXTE DES AGENTS Forge + validateur de cohérence.
//
// Jumeau de studio_selfaudit.mjs (même patron : Node .mjs déterministe, non-LLM, read-only,
// fonctions pures exportées, sortie Markdown SANS horodatage → zéro bruit git, exit 0/1).
// Là où studio_selfaudit audite la dérive doc<->réalité du STUDIO, ce capteur cartographie
// les CONTRATS D'AGENT (forge/contracts/<etape>.yaml) : qui lit quoi, écrit quoi,
// avec quels droits et quels garde-fous. Puis il vérifie MÉCANIQUEMENT deux choses seulement :
//   1. tout `capability_role` déclaré dans un contrat est résolvable par roles.yaml ;
//   2. aucun champ Critique (règle des 3 états, SCHEMA.md) n'est vide ou absent.
//
// Limite honnête : aucun parseur YAML n'est disponible dans ce repo (pas de js-yaml). On
// n'implémente PAS un parseur YAML complet — juste une extraction line-based robuste des
// champs scalaires (inline + blocs `>-`/`>`/`|`) et des listes (`- item`) dont on a besoin.
// Suffisant pour les contrats Forge (clés au niveau racine) ; ne gère pas le YAML arbitraire.
//
// Usage : node forge/agent_context_map.mjs [--write] [<repoRoot>]
// Sortie : JSON (rows + findings) sur stdout ; résumé lisible sur stderr.
// Exit 0 = aucune incohérence ; exit 1 = au moins un finding (rôle non résolu ou champ Critique manquant).
import { existsSync, readFileSync, readdirSync, writeFileSync, mkdirSync } from 'node:fs';
import { join, dirname, resolve, basename } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const CONTRACTS_REL = 'forge/contracts';
const ROLES_REL = 'forge/contracts/roles.yaml';
const OUTPUT_REL = 'docs/forge/AGENT_CONTEXT_MAP.generated.md';

// Fichiers du dossier contracts qui NE sont PAS des contrats d'agent (à exclure de la carte).
// roles.yaml = registry de résolution (pas un agent) ; les .md = doc/schéma.
const NON_CONTRACT = new Set(['roles.yaml']);

// Champs Critique minimaux vérifiés par le validateur (sous-ensemble du SCHEMA.md — on ne
// vérifie QUE ce qu'on sait prouver mécaniquement, jamais l'intégralité des 17 champs).
const CRITICAL_FIELDS = ['role', 'capability_role', 'objectif', 'mandatory_read', 'output_contract'];

/**
 * Retire les guillemets encadrants (simples ou doubles) d'un scalaire.
 * @param {string} s
 * @returns {string}
 */
function stripQuotes(s) {
  const t = s.trim();
  if ((t.startsWith('"') && t.endsWith('"')) || (t.startsWith("'") && t.endsWith("'"))) {
    return t.slice(1, -1);
  }
  return t;
}

/**
 * Extraction line-based des champs racine d'un contrat YAML (PAS un parseur YAML complet).
 * Gère : scalaire inline (`k: v`), bloc scalaire (`k: >-` / `>` / `|` / `|-` ...) plié en une
 * ligne, et liste (`k:` suivi de lignes `  - item`). Les commentaires en colonne 0 (`# ...`)
 * et les lignes vides sont ignorés. Une valeur absente => champ absent de l'objet retourné.
 * @param {string} text
 * @returns {Record<string, string|string[]>}
 */
export function parseContractFields(text) {
  const lines = text.split(/\r?\n/);
  const obj = {};
  let i = 0;
  while (i < lines.length) {
    const line = lines[i];
    // Seules les clés en colonne 0 nous intéressent (les contrats Forge n'imbriquent pas).
    const m = line.match(/^([A-Za-z_][A-Za-z0-9_]*):(.*)$/);
    if (!m) { i++; continue; }
    const key = m[1];
    const rest = m[2].trim();

    // Cas bloc scalaire : `>-`, `>`, `|`, `|-`, `|+`, `>+`
    if (/^[|>][+-]?$/.test(rest)) {
      i++;
      const buf = [];
      while (i < lines.length && (lines[i].trim() === '' || /^\s/.test(lines[i]))) {
        buf.push(lines[i].trim());
        i++;
      }
      // Pliage simple : on colle les lignes en un seul champ de tableau (espaces collapsés).
      obj[key] = buf.join(' ').replace(/\s+/g, ' ').trim();
      continue;
    }

    // Cas valeur vide : soit une liste (`- item`), soit rien.
    if (rest === '') {
      i++;
      const items = [];
      while (i < lines.length && (lines[i].trim() === '' || /^\s/.test(lines[i]))) {
        const l = lines[i];
        const li = l.match(/^\s+-\s+(.*)$/);
        if (li) items.push(stripQuotes(li[1].trim()));
        // (une ligne indentée non-liste appartiendrait à un map imbriqué : ignorée ici)
        i++;
      }
      obj[key] = items;
      continue;
    }

    // Cas scalaire inline.
    obj[key] = stripQuotes(rest);
    i++;
  }
  return obj;
}

/**
 * Liste les fichiers de contrat (*.yaml hors registry) d'un dossier, triés par nom.
 * @param {string} contractsDir
 * @returns {string[]} noms de fichiers (basename)
 */
export function listContractFiles(contractsDir) {
  return readdirSync(contractsDir)
    .filter((f) => f.endsWith('.yaml') && !NON_CONTRACT.has(f))
    .sort();
}

/**
 * Extrait l'ensemble des noms de rôles déclarés dans roles.yaml (tous les `- <role>` sous
 * une clé `roles:`). Extraction line-based ciblée, pas un parseur YAML complet.
 * @param {string} rolesPath
 * @returns {Set<string>}
 */
export function parseRoleNames(rolesPath) {
  const roles = new Set();
  if (!existsSync(rolesPath)) return roles;
  const lines = readFileSync(rolesPath, 'utf-8').split(/\r?\n/);
  let inRoles = false;
  let rolesIndent = -1;
  for (const raw of lines) {
    const line = raw.replace(/\t/g, '  ');
    if (line.trim() === '' || /^\s*#/.test(line)) continue;
    const keyM = line.match(/^(\s*)([A-Za-z_][\w-]*):\s*(.*)$/);
    const listM = line.match(/^(\s*)-\s+(.*)$/);
    if (keyM && keyM[2] === 'roles' && keyM[3].trim() === '') {
      inRoles = true;
      rolesIndent = keyM[1].length;
      continue;
    }
    if (inRoles && listM && listM[1].length > rolesIndent) {
      // Retire un éventuel commentaire de fin de ligne (`- role   # étape 0`).
      const token = listM[2].replace(/\s+#.*$/, '').trim();
      if (token) roles.add(stripQuotes(token));
      continue;
    }
    // Toute autre ligne significative ferme le bloc roles courant.
    inRoles = false;
  }
  return roles;
}

/**
 * Rend une valeur (scalaire ou liste) sûre pour une cellule de tableau Markdown.
 * @param {string|string[]|undefined} v
 * @returns {string}
 */
function cell(v) {
  let s;
  if (Array.isArray(v)) s = v.join(' ; ');
  else if (v == null) s = '—';
  else s = String(v);
  s = s.replace(/\s+/g, ' ').trim();
  if (s === '') s = '—';
  // Échappe les pipes (sinon cassent la table) et les retours (déjà collapsés).
  return s.replace(/\|/g, '\\|');
}

/**
 * Fonction pure : construit la carte de contexte des agents à partir des contrats.
 * @param {string} contractsDir
 * @returns {Array<{etape:string, capability_role:string, lit:string, ecrit:string, droits:string, gardeFou:string}>}
 */
export function buildAgentContextMap(contractsDir) {
  const rows = [];
  for (const file of listContractFiles(contractsDir)) {
    const fields = parseContractFields(readFileSync(join(contractsDir, file), 'utf-8'));
    rows.push({
      etape: basename(file, '.yaml'),
      capability_role: typeof fields.capability_role === 'string' ? fields.capability_role : '',
      lit: Array.isArray(fields.mandatory_read) ? fields.mandatory_read.join(' ; ') : (fields.mandatory_read || ''),
      ecrit: typeof fields.output_contract === 'string' ? fields.output_contract : '',
      droits: typeof fields.permissions === 'string' ? fields.permissions : '',
      gardeFou: typeof fields.gardeFou === 'string' ? fields.gardeFou : '',
    });
  }
  // Tri déterministe par nom d'étape.
  rows.sort((a, b) => a.etape.localeCompare(b.etape));
  return rows;
}

/**
 * Fonction pure : génère le tableau Markdown de la carte de contexte. Déterministe, SANS
 * horodatage (relu du disque à chaque appel → change seulement si un contrat change).
 * @param {string} contractsDir
 * @returns {string} markdown
 */
export function generateContextMapTable(contractsDir) {
  const rows = buildAgentContextMap(contractsDir);
  const lines = [];
  lines.push('# AGENT CONTEXT MAP — Forge (auto-généré, ne pas éditer à la main)');
  lines.push('');
  lines.push('> ⚠ Fichier **AUTO-GÉNÉRÉ** par `node forge/agent_context_map.mjs --write`.');
  lines.push('> Relu des contrats `forge/contracts/*.yaml`, jamais écrit à la main → il ne peut');
  lines.push('> PAS se périmer. Une ligne par contrat d\'agent (registry `roles.yaml` exclu). La colonne');
  lines.push('> « Lit » = `mandatory_read` (mémoire reçue) ; « Écrit » = `output_contract` (mémoire produite).');
  lines.push('> Extraction YAML simplifiée (pas de parseur complet). `claim_verdict: NO_CLAIM_ALLOWED`.');
  lines.push('');
  lines.push('| Étape/Agent | capability_role | Lit (mémoire reçue) | Écrit (mémoire produite) | Droits | Garde-fou |');
  lines.push('|---|---|---|---|---|---|');
  for (const r of rows) {
    lines.push(`| \`${r.etape}\` | ${cell(r.capability_role)} | ${cell(r.lit)} | ${cell(r.ecrit)} | ${cell(r.droits)} | ${cell(r.gardeFou)} |`);
  }
  lines.push('');
  return lines.join('\n');
}

/**
 * Un champ Critique est « manquant » s'il est absent, vide, ou déclaré `aucun` (règle des 3
 * états : pour un champ Critique, « déclaré vide » = refus, cf. SCHEMA.md).
 * @param {string|string[]|undefined} v
 * @returns {boolean}
 */
function isCriticalMissing(v) {
  if (v == null) return true;
  if (Array.isArray(v)) return v.length === 0;
  const t = String(v).trim().toLowerCase();
  return t === '' || t === 'aucun';
}

/**
 * Fonction pure : validateur de cohérence. Ne remonte QUE ce qui est mécaniquement prouvable —
 *   (a) un `capability_role` de contrat absent de roles.yaml (rôle non résolvable) ;
 *   (b) un champ Critique minimal vide/absent (agent non activable, règle des 3 états).
 * Findings honnêtes, jamais inventés.
 * @param {string} contractsDir
 * @param {string} rolesPath
 * @returns {Array<{type:string, etape:string, field?:string, capability_role?:string, detail:string}>}
 */
export function validateAgentContext(contractsDir, rolesPath) {
  const findings = [];
  const roles = parseRoleNames(rolesPath);
  for (const file of listContractFiles(contractsDir)) {
    const etape = basename(file, '.yaml');
    const fields = parseContractFields(readFileSync(join(contractsDir, file), 'utf-8'));

    // (b) Champs Critique minimaux.
    for (const field of CRITICAL_FIELDS) {
      if (isCriticalMissing(fields[field])) {
        findings.push({
          type: 'critical_field_missing',
          etape,
          field,
          detail: `champ Critique « ${field} » vide ou absent — agent non activable (SCHEMA.md, règle des 3 états)`,
        });
      }
    }

    // (a) Résolution du capability_role (seulement s'il est présent — sinon déjà signalé en (b)).
    const cap = fields.capability_role;
    if (typeof cap === 'string' && cap.trim() !== '' && cap.trim().toLowerCase() !== 'aucun') {
      if (!roles.has(cap.trim())) {
        findings.push({
          type: 'capability_role_unresolved',
          etape,
          capability_role: cap.trim(),
          detail: `capability_role « ${cap.trim()} » absent de roles.yaml — rôle non résolvable par le registry (ADR-002 gate 1)`,
        });
      }
    }
  }
  return findings;
}

function main() {
  const here = dirname(fileURLToPath(import.meta.url));
  const args = process.argv.slice(2);
  const write = args.includes('--write');
  const positional = args.find((a) => !a.startsWith('--'));
  const repoRoot = positional ? resolve(positional) : resolve(here, '..');
  const contractsDir = join(repoRoot, CONTRACTS_REL);
  const rolesPath = join(repoRoot, ROLES_REL);

  const rows = buildAgentContextMap(contractsDir);
  const findings = validateAgentContext(contractsDir, rolesPath);
  const ok = findings.length === 0;

  console.error(`=== AGENT CONTEXT MAP — ${repoRoot} ===\n`);
  console.error(`Contrats cartographiés : ${rows.length}`);
  for (const r of rows) console.error(`  · ${r.etape} → capability_role=${r.capability_role || '(absent)'}`);
  console.error(`\nValidateur de cohérence : ${findings.length} finding(s)`);
  for (const f of findings) console.error(`  ⚠ [${f.etape}] ${f.detail}`);
  console.error(`\nVERDICT : ${ok ? 'COHÉRENT ✅ (rien de prouvable en défaut)' : 'INCOHÉRENCE(S) DÉTECTÉE(S) ⚠'}`);

  if (write) {
    const md = generateContextMapTable(contractsDir);
    const outPath = join(repoRoot, OUTPUT_REL);
    mkdirSync(dirname(outPath), { recursive: true });
    writeFileSync(outPath, md + '\n', 'utf-8');
    console.error(`\n📝 carte régénérée → ${OUTPUT_REL}`);
  }

  console.log(JSON.stringify({ contractsDir: CONTRACTS_REL, rows, findings, ok }, null, 2));
  process.exit(ok ? 0 : 1);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main();
}

#!/usr/bin/env node
// check_amont_traversal.mjs — SONDE déterministe non-LLM (décision Pierre 2026-08-21,
// choix (b)) : jusqu'où les faits produits EN AMONT (World Scan, Story Bible, GM World
// Scan) traversent-ils RÉELLEMENT la chaîne Prisme -> Grey Blocks (featuremap) ->
// WireMap -> Build ? Elle suit la provenance DÉJÀ présente dans les artefacts :
//   prisme.exigences[].reference (adresse amont)  ->  featuremap.leaf.source_ref (id
//   d'exigence)  ->  wiremap.lines[].couvre (ids de capacités)  ->  fichiers sur disque.
//
// ADVISORY, JAMAIS UN VERDICT : règle de variance (ratifiée 2026-07-21) — une métrique
// prouve d'abord qu'elle porte une information variable. Ce fichier MESURE et REPORTE ;
// il ne bloque rien. Un fait absent en amont est NOT_PRODUCED (pas un FAIL) ; un build
// non fourni est files_present=null (NOT_MEASURED), jamais inventé.
//
// Usage : node check_amont_traversal.mjs <run_dir> [--game-dir <dir>] [--json]
// Exit 0 toujours (2 = usage) — une sonde advisory ne fait échouer aucun appelant.
import { readFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { collectLeaves } from './upstream_schema.mjs';

export const PREFIXES = ['worldscan', 'story_bible', 'gm_worldscan'];
export const STAGES = ['NOT_PRODUCED', 'PRODUCED', 'PRISME', 'GREY_BLOCKS', 'WIREMAP', 'BUILD'];
export const FACTS = [
  'conditions_victoire', 'conditions_defaite', 'objectifs_joueur',
  'progression', 'boucles_recompense', 'contraintes_narratives',
];
// Dimensions GM qui portent une boucle de récompense (en plus des loops du World Scan).
const GM_REWARD_DIMENSIONS = new Set(['bonus', 'economy', 'rarity']);

function nonEmpty(v) {
  if (v === null || v === undefined) return false;
  if (typeof v === 'string') return v.trim() !== '';
  if (Array.isArray(v)) return v.length > 0;
  return true;
}

/** Résout `a.b[0].c` dans un objet ; undefined si un maillon manque ou vaut null. */
export function resolvePath(root, path) {
  if (typeof path !== 'string' || !path) return undefined;
  const tokens = path.match(/[^.[\]]+|\[\d+\]/g);
  if (!tokens) return undefined;
  let cur = root;
  for (const t of tokens) {
    if (cur === null || cur === undefined) return undefined;
    const key = t.startsWith('[') ? Number(t.slice(1, -1)) : t;
    cur = cur[key];
  }
  return nonEmpty(cur) ? cur : undefined;
}

/** Adresses concrètes (préfixées) portant chacun des 6 faits, depuis les artefacts amont. */
export function factAddresses(artifacts) {
  const out = Object.fromEntries(FACTS.map((f) => [f, []]));
  const games = Array.isArray(artifacts?.worldscan?.games) ? artifacts.worldscan.games : [];
  games.forEach((g, i) => {
    const objectives = Array.isArray(g?.objectives) ? g.objectives : [];
    objectives.forEach((o, j) => {
      const base = `worldscan:games[${i}].objectives[${j}]`;
      if (nonEmpty(o?.victory_condition)) out.conditions_victoire.push(`${base}.victory_condition`);
      if (nonEmpty(o?.defeat_condition)) out.conditions_defaite.push(`${base}.defeat_condition`);
      if (nonEmpty(o?.player_goal)) out.objectifs_joueur.push(`${base}.player_goal`);
    });
    const loops = g?.loops && typeof g.loops === 'object' ? g.loops : {};
    for (const k of Object.keys(loops)) {
      if (nonEmpty(loops[k])) out.boucles_recompense.push(`worldscan:games[${i}].loops.${k}`);
    }
  });
  const dims = Array.isArray(artifacts?.gm_worldscan?.dimensions) ? artifacts.gm_worldscan.dimensions : [];
  dims.forEach((d, k) => {
    if (d?.status !== 'MEASURED') return;
    const addr = `gm_worldscan:dimensions[${k}]`;
    if (d.id === 'progression') out.progression.push(addr);
    if (GM_REWARD_DIMENSIONS.has(d.id)) out.boucles_recompense.push(addr);
  });
  const sections = Array.isArray(artifacts?.story_bible?.sections) ? artifacts.story_bible.sections : [];
  sections.forEach((s, k) => {
    if (s?.status === 'GROUNDED' && Array.isArray(s.elements) && s.elements.length > 0) {
      out.contraintes_narratives.push(`story_bible:sections[${k}]`);
    }
  });
  return out;
}

/** Forme canonique `prefixe:chemin` d'une `reference` d'exigence, ou null si elle
 *  n'est pas adressable / ne résout rien dans l'artefact (prose, adresse fantôme,
 *  valeur null). Raccourcis : `gm_worldscan:<id dimension>`, `story_bible:<id section>`. */
export function canonicalize(reference, artifacts) {
  if (typeof reference !== 'string') return null;
  const m = reference.trim().match(/^([a-z_]+):(.+)$/);
  if (!m || !PREFIXES.includes(m[1])) return null;
  const [, prefix, rest0] = m;
  const rest = rest0.trim();
  const root = artifacts?.[prefix];
  if (!root || typeof root !== 'object') return null;
  if (prefix === 'gm_worldscan') {
    const k = (Array.isArray(root.dimensions) ? root.dimensions : []).findIndex((d) => d?.id === rest);
    if (k >= 0) return `gm_worldscan:dimensions[${k}]`;
  }
  if (prefix === 'story_bible') {
    const head = rest.split('/')[0];
    const k = (Array.isArray(root.sections) ? root.sections : []).findIndex((s) => s?.id === head);
    if (k >= 0) return `story_bible:sections[${k}]`;
  }
  return resolvePath(root, rest) !== undefined ? `${prefix}:${rest}` : null;
}

/** `addr` porte le fait situé à `factAddr` si elle lui est égale ou plus profonde. */
function covers(addr, factAddr) {
  return addr === factAddr || addr.startsWith(`${factAddr}.`) || addr.startsWith(`${factAddr}[`);
}

/** Lignes d'une WireMap v1 (`features[]`) ou v2 (`lines[]`) sous une forme unique. */
export function wiremapLines(wiremap) {
  const files = (arr) => (Array.isArray(arr) ? arr : [])
    .map((f) => (typeof f === 'string' ? f : f?.path)).filter((p) => typeof p === 'string' && p);
  if (wiremap?.schema_version === 2) {
    return (Array.isArray(wiremap.lines) ? wiremap.lines : []).filter((l) => l && typeof l === 'object')
      .map((l) => ({ id: String(l.id ?? ''), couvre: Array.isArray(l.couvre) ? l.couvre : [], fichiers: files(l.fichiers) }));
  }
  return (Array.isArray(wiremap?.features) ? wiremap.features : []).filter((f) => f && typeof f === 'object')
    .map((f) => ({ id: String(f.feature ?? ''), couvre: Array.isArray(f.couvre) ? f.couvre : [], fichiers: files(f.fichiers) }));
}

/** La mesure. `gameDir` null => étage BUILD non mesuré (files_present: null). */
export function traverse(artifacts, gameDir) {
  const facts = factAddresses(artifacts);
  const exigences = Array.isArray(artifacts?.prisme?.exigences) ? artifacts.prisme.exigences : [];
  const references = { expected: 0, adressables: 0, resolues: 0, non_resolues: [] };
  const exByAddr = [];
  for (const ex of exigences) {
    if (!ex || ex.source !== 'EXPECTED') continue;
    references.expected += 1;
    if (typeof ex.reference === 'string' && /^[a-z_]+:/.test(ex.reference.trim())) references.adressables += 1;
    const addr = canonicalize(ex.reference, artifacts);
    if (addr) { references.resolues += 1; exByAddr.push({ id: ex.id, addr }); }
    else references.non_resolues.push({ id: ex.id, reference: ex.reference ?? null });
  }
  const leaves = collectLeaves(artifacts?.featuremap ?? {});
  const lines = wiremapLines(artifacts?.wiremap);
  const out = {};
  for (const fact of FACTS) {
    const addrs = facts[fact];
    const r = { produced: addrs.length > 0, addresses: addrs, exigences: [], leaves: [], lines: [], files_present: null, reached: 'NOT_PRODUCED' };
    if (r.produced) {
      r.reached = 'PRODUCED';
      r.exigences = exByAddr.filter((e) => addrs.some((f) => covers(e.addr, f))).map((e) => e.id);
      if (r.exigences.length) {
        r.reached = 'PRISME';
        const exSet = new Set(r.exigences);
        r.leaves = leaves.filter((l) => exSet.has(l.leaf?.source_ref)).map((l) => l.leaf.id);
        if (r.leaves.length) {
          r.reached = 'GREY_BLOCKS';
          const leafSet = new Set(r.leaves);
          const hit = lines.filter((l) => l.couvre.some((c) => leafSet.has(c)));
          r.lines = hit.map((l) => l.id);
          if (hit.length) {
            r.reached = 'WIREMAP';
            if (gameDir) {
              const fichiers = hit.flatMap((l) => l.fichiers);
              r.files_present = fichiers.length > 0 && fichiers.every((f) => existsSync(join(gameDir, f)));
              if (r.files_present) r.reached = 'BUILD';
            }
          }
        }
      }
    }
    out[fact] = r;
  }
  return { facts: out, references, stages: STAGES, verdict: 'ADVISORY', claim_verdict: 'NO_CLAIM_ALLOWED' };
}

async function readJsonOrNull(path) {
  try { return JSON.parse(await readFile(path, 'utf8')); } catch { return null; }
}

/** Charge les 6 artefacts d'un run_dir ; chacun vaut null s'il est absent/illisible. */
export async function loadRunDir(runDir) {
  const names = ['worldscan', 'story_bible', 'gm_worldscan', 'prisme', 'featuremap', 'wiremap'];
  const entries = await Promise.all(names.map(async (n) => [n, await readJsonOrNull(join(runDir, `${n}.json`))]));
  return Object.fromEntries(entries);
}

async function main(argv) {
  const args = argv.slice(2);
  const runDir = args.find((a) => !a.startsWith('--'));
  if (!runDir) {
    process.stderr.write('usage: node check_amont_traversal.mjs <run_dir> [--game-dir <dir>] [--json]\n');
    return 2;
  }
  const gi = args.indexOf('--game-dir');
  const gameDir = gi >= 0 && args[gi + 1] ? resolve(args[gi + 1]) : null;
  const result = traverse(await loadRunDir(resolve(runDir)), gameDir);
  if (args.includes('--json')) {
    process.stdout.write(`${JSON.stringify(result, null, 1)}\n`);
  } else {
    for (const [fact, r] of Object.entries(result.facts)) {
      process.stdout.write(`${fact.padEnd(24)} ${r.reached.padEnd(12)} exigences=${r.exigences.length} feuilles=${r.leaves.length} lignes=${r.lines.length}\n`);
    }
    const { expected, adressables, resolues, non_resolues } = result.references;
    process.stdout.write(`references EXPECTED=${expected} adressables=${adressables} resolues=${resolues} non_resolues=${non_resolues.length}\n`);
    process.stdout.write('verdict: ADVISORY · claim_verdict: NO_CLAIM_ALLOWED\n');
  }
  return 0;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main(process.argv).then((code) => process.exit(code));
}

#!/usr/bin/env node
// master_index.mjs — MASTER INDEX des sources de verite de la MEMOIRE du studio (lane FORGE).
//
// Probleme : « qui fait foi sur quoi, qui ecrit, qui lit » est decrit dans la prose du
// STUDIO_AGENT_ATLAS (§3 « PROPRIETE MEMOIRE »). Cette prose peut se perimer en silence
// (un fichier de reference supprime/deplace sans que la carte le sache). Ce capteur est le
// meme patron que `studio_selfaudit.mjs` : deterministe, non-LLM, read-only. Il ne fait
// AUCUNE analyse fragile de prose libre — il parse UNE table markdown deja ecrite (la table
// §3, source faisant autorite) et confronte chaque chemin cite a `fs.existsSync`.
//
// La table §3 est la SOURCE : on ne re-declare rien, on ne devine rien. On lit ses 4 colonnes
// (« Memoire/fichier | Qui ecrit | Nature | Regle ») et on ajoute une colonne factuelle
// « Existe » relue du disque. Le fichier genere ne porte AUCUN horodatage → il ne change que
// si la REALITE change (zero bruit git).
//
// Usage : node forge/master_index.mjs [--write] [<repoRoot>]
// Sortie : rapport JSON sur stdout + resume lisible sur stderr.
// Exit 0 = toutes les sources citees existent ; exit 1 = au moins une source ABSENTE
//          (derive doc<->realite, a corriger ou ratifier par Pierre).
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { join, dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const ATLAS_FILE = 'docs/forge/STUDIO_AGENT_ATLAS.md';
const GENERATED_FILE = 'docs/forge/MASTER_INDEX.generated.md';
// Caracteres qui marquent la fin de la partie « litterale » d'un chemin (glob / placeholder / set).
const PATH_META = /[{}*<>]/;

/**
 * Nettoie le contenu d'une cellule markdown : retire le gras `**...**`, les backticks,
 * et normalise les espaces. Ne touche pas au sens, juste au balisage.
 * @param {string} cell
 * @returns {string}
 */
export function cleanCell(cell) {
  return cell
    .replace(/\*\*(.*?)\*\*/g, '$1') // gras -> texte
    .replace(/`/g, '')               // backticks -> rien
    .replace(/\s+/g, ' ')
    .trim();
}

/**
 * Extrait le chemin « source » d'une cellule (le PREMIER token entre backticks ; a defaut,
 * la cellule nettoyee entiere). Ex. "`memory/` (+ `MEMORY.md`)" -> "memory/".
 * @param {string} cell
 * @returns {string}
 */
export function extractSourcePath(cell) {
  const m = cell.match(/`([^`]+)`/);
  return m ? m[1].trim() : cleanCell(cell);
}

/**
 * Reduit un chemin cite (qui peut contenir globs/placeholders `{..}`, `*`, `<projet>`) au
 * prefixe LITTERAL verifiable sur disque. Ex. `EVIDENCE/runs/<projet>/{state.json,...}`
 * -> `EVIDENCE/runs`. On garde les segments jusqu'au premier segment meta (exclu).
 * @param {string} rawPath
 * @returns {string}
 */
export function resolveCheckPath(rawPath) {
  const segments = rawPath.split('/');
  const kept = [];
  for (const seg of segments) {
    if (seg === '') continue;      // ignore le '/' final (ex. "memory/")
    if (PATH_META.test(seg)) break; // segment glob/placeholder -> on s'arrete
    kept.push(seg);
  }
  return kept.join('/');
}

/**
 * Parse la table §3 « PROPRIETE MEMOIRE » du markdown de l'ATLAS. Detection robuste :
 * la ligne d'en-tete est celle qui contient les 4 libelles de colonne. On saute la ligne
 * de separation `|---|` puis on lit les lignes `|` jusqu'a la fin de la table.
 * @param {string} atlasText
 * @returns {Array<{source:string, ecrit_par:string, nature:string, regle:string}>}
 */
export function parseAtlasMemoryTable(atlasText) {
  const lines = atlasText.split(/\r?\n/);
  const isHeader = (l) =>
    l.trim().startsWith('|') &&
    l.includes('Mémoire') && l.includes('Qui écrit') &&
    l.includes('Nature') && l.includes('Règle');

  let i = lines.findIndex(isHeader);
  if (i === -1) return [];
  i += 1;
  // Ligne de separation optionnelle (|---|---|...).
  if (i < lines.length && /^\s*\|[\s:|-]+\|\s*$/.test(lines[i])) i += 1;

  const rows = [];
  for (; i < lines.length; i++) {
    const line = lines[i];
    if (!line.trim().startsWith('|')) break; // fin de la table
    // Cellules : on retire les bornes | puis on split. (Les chemins de la table §3 ne
    // contiennent pas de '|', donc un split simple est suffisant et deterministe.)
    const cells = line.trim().replace(/^\|/, '').replace(/\|$/, '').split('|');
    if (cells.length < 4) continue;
    const source = extractSourcePath(cells[0]);
    rows.push({
      source,
      ecrit_par: cleanCell(cells[1]),
      nature: cleanCell(cells[2]),
      regle: cleanCell(cells[3]),
    });
  }
  return rows;
}

/**
 * Construit le MASTER INDEX : parse la table §3 de l'ATLAS + verifie l'existence disque de
 * chaque source citee. Fonction pure (aucune ecriture).
 * @param {string} repoRoot
 * @returns {Array<{source:string, ecrit_par:string, nature:string, regle:string, check_path:string, existe:boolean}>}
 */
export function buildMasterIndex(repoRoot) {
  const atlasPath = join(repoRoot, ATLAS_FILE);
  const atlasText = readFileSync(atlasPath, 'utf-8');
  const rows = parseAtlasMemoryTable(atlasText);
  const entries = rows.map((r) => {
    const checkPath = resolveCheckPath(r.source);
    const existe = checkPath !== '' && existsSync(join(repoRoot, checkPath));
    return { ...r, check_path: checkPath, existe };
  });
  // Tri deterministe par source (zero bruit git).
  entries.sort((a, b) => (a.source < b.source ? -1 : a.source > b.source ? 1 : 0));
  return entries;
}

/**
 * Genere le MASTER INDEX en markdown deterministe (SANS horodatage). Colonnes :
 * Source de verite | Qui ecrit | Nature | Existe | Regle.
 * @param {string} repoRoot
 * @returns {string} markdown
 */
export function generateMasterIndexTable(repoRoot) {
  const entries = buildMasterIndex(repoRoot);
  const missing = entries.filter((e) => !e.existe);

  const lines = [];
  lines.push('# MASTER INDEX — sources de vérité de la mémoire du studio (auto-généré)');
  lines.push('');
  lines.push('> ⚠ Fichier **AUTO-GÉNÉRÉ depuis `STUDIO_AGENT_ATLAS.md` §3, ne pas éditer.**');
  lines.push('> Produit par `node forge/master_index.mjs --write`. La colonne « Existe »');
  lines.push('> est relue du disque (`fs.existsSync`) → ce tableau ne peut PAS se périmer en silence.');
  lines.push('> Chemins réduits au préfixe littéral (globs/placeholders `{..}` `<projet>` `*` ignorés).');
  lines.push('> Déterministe, non-LLM, sans horodatage. `claim_verdict: NO_CLAIM_ALLOWED`.');
  lines.push('');
  lines.push('| Source de vérité | Qui écrit | Nature | Existe | Règle |');
  lines.push('|---|---|---|---|---|');
  for (const e of entries) {
    const existe = e.existe ? '✅ présent' : '⬜ absent';
    lines.push(`| \`${e.source}\` | ${e.ecrit_par} | ${e.nature} | ${existe} | ${e.regle} |`);
  }
  lines.push('');
  lines.push(`**Sources suivies** : ${entries.length} · **absentes du disque** : ${missing.length}`
    + `${missing.length ? ' ⚠ (dérive doc↔réalité — corriger la carte ou ratifier)' : ' ✅'}`);
  if (missing.length) {
    lines.push('');
    for (const m of missing) {
      lines.push(`- ⚠ \`${m.source}\` (préfixe testé : \`${m.check_path || '—'}\`) — cité par l'ATLAS §3 mais ABSENT du disque.`);
    }
  }
  lines.push('');
  return lines.join('\n');
}

function main() {
  const here = dirname(fileURLToPath(import.meta.url));
  const args = process.argv.slice(2);
  const write = args.includes('--write');
  const positional = args.find((a) => !a.startsWith('--'));
  const repoRoot = positional ? resolve(positional) : resolve(here, '..');

  const entries = buildMasterIndex(repoRoot);
  const missing = entries.filter((e) => !e.existe);
  const ok = missing.length === 0;

  console.error(`=== MASTER INDEX — ${repoRoot} ===\n`);
  console.error(`Sources de vérité citées par l'ATLAS §3 : ${entries.length}`);
  for (const e of entries) {
    console.error(`  ${e.existe ? '✅' : '⚠'} ${e.source}  [${e.ecrit_par}]`);
  }
  console.error(`\nSources ABSENTES du disque : ${missing.length}`);
  for (const m of missing) {
    console.error(`  ⚠ ${m.source} (préfixe testé : ${m.check_path || '—'}) — dérive doc↔réalité`);
  }
  console.error(`\nVERDICT : ${ok ? 'MASTER INDEX ALIGNÉ ✅' : 'DÉRIVE DÉTECTÉE ⚠ (corriger la carte ou ratifier)'}`);

  if (write) {
    const md = generateMasterIndexTable(repoRoot);
    writeFileSync(join(repoRoot, GENERATED_FILE), md + '\n', 'utf-8');
    console.error(`\n📝 master index régénéré → ${GENERATED_FILE}`);
  }

  console.log(JSON.stringify({ repoRoot, atlas: ATLAS_FILE, entries, missing, ok }, null, 2));
  process.exit(ok ? 0 : 1);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main();
}

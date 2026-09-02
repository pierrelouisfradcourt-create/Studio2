#!/usr/bin/env node
// declaration_readers.mjs — CAPTEUR « déclaration lue ou lettre morte ».
//
// Question UNIQUE : un fichier qui DÉCLARE une règle (rôle, permission, politique)
// est-il réellement LU par du code de ce repo ? Trois dérives réelles trouvées le
// 2026-07-19 qu'aucun outil existant n'attrapait :
//   1. `.claude/agents/*.md` — des rôles déclarés qu'AUCUN code ne lit, et sans
//      `description:` ils ne sont même pas invocables par le runtime Claude Code.
//   2. `lab/agent_policy/tool_permission_matrix.json` — 62 règles `agent_id × tool ×
//      effect` ; le seul lecteur (autopilot.py `_check_tool_permission`) ne référence
//      JAMAIS `agent_id` : la granularité déclarée n'est pas appliquée.
//   3. champs custom (`role:`, `domain:`, `escalates_to:`, `forbidden_paths:`) hors
//      du schéma de tout runtime, dont des `domain:` pointant vers des dossiers absents.
//
// Pourquoi un fichier NEUF plutôt qu'une extension de `studio_selfaudit.mjs` :
// selfaudit compare ce que les CARTES AFFIRMENT à `fs.existsSync` et sort en exit 1
// sur dérive (c'est une garde). Ici l'entrée est le CODE (qui lit quoi), la sortie est
// une MESURE, et l'exit est toujours 0 — même philosophie que `reuse_ratio.mjs`.
// Mélanger les deux aurait donné un outil à deux verdicts contradictoires.
//
// Déterministe, non-LLM, zéro réseau, lecture seule. Recherche TEXTUELLE (pas d'AST) :
// même limite déclarée que kb-validate.mjs R10 / reuse_ratio.mjs — suffisant pour ce
// besoin, ce n'est pas un compilateur. Voir `out_of_scope` dans la sortie.
//
// Doctrine ZÉRO FAUX POSITIF : en cas de doute, le capteur SE TAIT et documente la
// limite. La détection de lecteur est volontairement LARGE (toute mention textuelle du
// chemin ou du nom de fichier compte) — plus on trouve de lecteurs, moins on signale.
//
// Usage : node forge/declaration_readers.mjs [<repoRoot>] [--json]
// Sortie : rapport JSON sur stdout + résumé lisible sur stderr. Exit 0 = le capteur a
// tourné ; exit 2 = erreur interne / manifeste illisible.
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { join, resolve, dirname, extname } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const WATCHLIST = 'forge/declaration_watchlist.json';
const MAX_LINES_PER_READER = 3;

// Limites ASSUMÉES — imprimées dans le rapport pour qu'aucun lecteur humain ne
// surinterprète un « AUCUN LECTEUR CODE ».
export const OUT_OF_SCOPE = [
  "une MENTION de code n'est pas forcément une LECTURE : un script qui ÉCRIT le fichier, ou un simple COMMENTAIRE qui le cite, mentionne sans lire. Le capteur ne distingue pas écriture et lecture ; il garantit seulement l'implication sûre « aucune mention » ⇒ « aucune lecture ». Le verdict positif se lit donc « MENTIONNÉ PAR DU CODE », pas « lu ». Cas réel : `deploy_studio.sh` a généré les .claude/agents/*.md par heredoc jusqu'au 2026-07-19 ; depuis le retrait du bloc, il ne reste qu'un commentaire — d'où l'exclusion explicite `non_reader_mentions` dans le manifeste (jamais silencieuse : la mention reste imprimée avec sa raison).",
  "`external_consumer` (manifeste) : certains fichiers déclaratifs sont consommés par un runtime HORS de ce repo (le binaire Claude Code lit .claude/agents/*.md). Pour ceux-là D1 (« lettre morte ») serait FAUX, donc D1 n'est pas émis — le verdict factuel AUCUN_LECTEUR_CODE reste affiché avec le nom du consommateur externe. Le capteur ne VÉRIFIE pas cette consommation externe : c'est une donnée du manifeste, pas une mesure.",
  "recherche textuelle, pas d'AST : un chemin construit dynamiquement (join(a, b + '.json'), f-string, variable) n'est PAS détecté comme lecteur — le capteur dirait « aucun lecteur » à tort. C'est le seul faux positif structurel possible ; il se vérifie à la main en 30 s sur les chemins signalés.",
  "champ « jamais référencé » ≠ champ mort à 100 % : un lecteur qui itère les clés dynamiquement (for k in rule, **rule, rule[var], serialisation JSON complète vers un autre composant) consomme le champ sans jamais écrire son nom. Le capteur ne peut pas le voir et NE prétend PAS que le champ est mort — il dit « aucun lecteur ne le nomme ».",
  "l'analyse de champs ne tourne QUE sur les fichiers ayant au moins un lecteur code (sinon le constat est déjà porté au niveau fichier) et uniquement sur les scopes déclarés dans le manifeste — aucune inférence de schéma.",
  "les mentions dans des fichiers .md (docs) ne comptent JAMAIS comme lecteur : documenter n'est pas lire. Les mentions dans des fichiers de données (.json/.yaml) sont rapportées séparément en `other_mentions`, jamais comptées comme lecteur.",
  "le capteur ne surveille QUE les entrées listées dans forge/declaration_watchlist.json — il ne découvre pas tout seul les fichiers de déclaration du repo.",
];

/**
 * Charge le manifeste des déclarations surveillées.
 * @param {string} repoRoot
 * @returns {{scan:object, declarations:Array<object>}}
 */
export function loadWatchlist(repoRoot) {
  return JSON.parse(readFileSync(join(repoRoot, WATCHLIST), 'utf-8'));
}

/**
 * Un répertoire doit-il être exclu de tout scan ?
 * @param {string} relDir chemin repo-relatif, séparateurs '/'
 * @param {{exclude_dirs?:string[], exclude_dir_patterns?:string[]}} cfg
 * @returns {boolean}
 */
export function isExcludedDir(relDir, cfg) {
  const name = relDir.split('/').pop();
  for (const ex of cfg.exclude_dirs || []) {
    if (ex.includes('/') ? relDir === ex || relDir.startsWith(ex + '/') : name === ex) return true;
  }
  for (const pat of cfg.exclude_dir_patterns || []) {
    if (new RegExp(pat).test(name)) return true;
  }
  return false;
}

/**
 * Liste les fichiers scannables du repo, classés code / données.
 * @param {string} repoRoot
 * @param {object} cfg section `scan` du manifeste
 * @returns {{code:string[], data:string[]}} chemins repo-relatifs ('/' comme séparateur)
 */
export function listCorpus(repoRoot, cfg) {
  const codeExt = new Set(cfg.code_extensions || []);
  const dataExt = new Set(cfg.data_extensions || []);
  const selfFiles = new Set(cfg.self_files || []);
  const code = [];
  const data = [];

  const walk = (absDir, relDir) => {
    let entries;
    try {
      entries = readdirSync(absDir, { withFileTypes: true });
    } catch {
      return; // dossier illisible (permissions, lien cassé) — on n'invente pas
    }
    for (const e of entries) {
      const rel = relDir ? `${relDir}/${e.name}` : e.name;
      if (e.isSymbolicLink()) continue; // pas de traversée de lien — confinement
      if (e.isDirectory()) {
        if (isExcludedDir(rel, cfg)) continue;
        walk(join(absDir, e.name), rel);
      } else if (e.isFile()) {
        if (selfFiles.has(rel)) continue; // le capteur ne se compte pas lui-même
        const ext = extname(e.name);
        if (codeExt.has(ext)) code.push(rel);
        else if (dataExt.has(ext)) data.push(rel);
      }
    }
  };
  walk(repoRoot, '');
  return { code: code.sort(), data: data.sort() };
}

/**
 * Aiguilles de recherche pour une déclaration : chemin repo-relatif + nom de fichier,
 * dans les trois écritures de séparateur qu'on trouve réellement dans du code
 * (posix, Windows échappé, Windows brut).
 *
 * `includeBasename` est FAUX pour un RÉPERTOIRE : le nom nu d'un dossier (« agents »)
 * est un mot courant qui matcherait la moitié du repo — faux lecteurs garantis. Pour un
 * FICHIER le basename porte l'extension (« qa-lead.md »), il est discriminant.
 * @param {string} relPath
 * @param {{includeBasename?:boolean}} [opts]
 * @returns {string[]}
 */
export function needlesFor(relPath, opts = {}) {
  const includeBasename = opts.includeBasename !== false;
  const set = new Set([relPath, relPath.replace(/\//g, '\\\\'), relPath.replace(/\//g, '\\')]);
  if (includeBasename) set.add(relPath.split('/').pop());
  return [...set];
}

/**
 * Cherche les fichiers du corpus qui MENTIONNENT une des aiguilles.
 * Large volontairement : toute mention compte comme lecteur potentiel (doctrine
 * zéro faux positif — on préfère rater une dérive que crier au loup).
 * @param {string} repoRoot
 * @param {string[]} needles
 * @param {string[]} files chemins repo-relatifs
 * @returns {Array<{path:string, lines:number[]}>}
 */
export function findMentions(repoRoot, needles, files) {
  const hits = [];
  for (const rel of files) {
    let text;
    try {
      text = readFileSync(join(repoRoot, rel), 'utf-8');
    } catch {
      continue;
    }
    if (!needles.some((n) => text.includes(n))) continue;
    const lines = [];
    const split = text.split(/\r?\n/);
    for (let i = 0; i < split.length && lines.length < MAX_LINES_PER_READER; i++) {
      if (needles.some((n) => split[i].includes(n))) lines.push(i + 1);
    }
    hits.push({ path: rel, lines });
  }
  return hits;
}

/**
 * Parse le frontmatter YAML plat d'un .md (clés de colonne 0 uniquement). Pas de parser
 * YAML complet : on n'a besoin que des clés de premier niveau et de leur valeur brute.
 * @param {string} text
 * @returns {{present:boolean, keys:Array<{key:string, value:string, line:number}>}}
 */
export function parseFrontmatter(text) {
  const lines = text.split(/\r?\n/);
  if (lines[0]?.trim() !== '---') return { present: false, keys: [] };
  const keys = [];
  for (let i = 1; i < lines.length; i++) {
    if (lines[i].trim() === '---') return { present: true, keys };
    const m = /^([A-Za-z_][A-Za-z0-9_-]*)\s*:\s*(.*)$/.exec(lines[i]);
    if (m) keys.push({ key: m[1], value: m[2].trim(), line: i + 1 });
  }
  return { present: false, keys: [] }; // frontmatter non fermé -> on ne conclut rien
}

/**
 * Extrait d'une valeur de frontmatter les jetons qui SONT des chemins (contiennent '/').
 * Conservateur : un mot sans '/' n'est jamais interprété comme un chemin.
 * @param {string} value
 * @returns {string[]}
 */
export function extractPathTokens(value) {
  const cleaned = value.replace(/^\[|\]$/g, '');
  return cleaned
    .split(/[\s,]+/)
    .map((t) => t.replace(/^["']|["'],?$/g, '').replace(/,$/, ''))
    .filter((t) => t.includes('/'))
    .map((t) => t.replace(/\/+$/, ''))
    .filter(Boolean);
}

/**
 * Audit d'un fichier d'agent .md : `description:` manquante, clés hors-schéma,
 * chemins déclarés inexistants.
 * @param {string} repoRoot
 * @param {string} relPath
 * @param {object} decl entrée du manifeste (kind agent_md)
 * @returns {Array<{rule:string, detail:string}>}
 */
export function auditAgentFile(repoRoot, relPath, decl) {
  const findings = [];
  const text = readFileSync(join(repoRoot, relPath), 'utf-8');
  const fm = parseFrontmatter(text);
  if (!fm.present) {
    findings.push({ rule: 'D3', detail: 'aucun frontmatter YAML fermé — fichier non exploitable par un runtime' });
    return findings;
  }
  const declared = fm.keys.map((k) => k.key);
  for (const req of decl.required_keys || []) {
    if (!declared.includes(req)) {
      findings.push({ rule: 'D4', detail: `champ requis « ${req}: » ABSENT — l'agent n'est pas invocable par le runtime` });
    }
  }
  const schema = new Set(decl.schema_keys || []);
  for (const k of fm.keys) {
    if (!schema.has(k.key)) {
      findings.push({ rule: 'D5', detail: `champ « ${k.key}: » hors-schéma (ligne ${k.line}) — dans le schéma d'aucun runtime, lu par aucun code` });
    }
  }
  for (const k of fm.keys) {
    if (!(decl.path_valued_keys || []).includes(k.key)) continue;
    for (const tok of extractPathTokens(k.value)) {
      if (!existsSync(join(repoRoot, tok))) {
        findings.push({ rule: 'D6', detail: `« ${k.key}: ${tok} » pointe vers un chemin INEXISTANT` });
      }
    }
  }
  return findings;
}

/**
 * Collecte les noms de champs déclarés d'un JSON selon des scopes explicites
 * ("$", "$.obj", "$.arr[*]"). Aucune inférence hors des scopes du manifeste.
 * @param {object} doc
 * @param {string[]} scopes
 * @param {string[]} ignore
 * @returns {Array<{field:string, scope:string}>}
 */
export function collectDeclaredFields(doc, scopes, ignore = []) {
  const skip = new Set(ignore);
  const out = new Map();
  const add = (field, scope) => {
    if (skip.has(field) || field.length < 3) return;
    if (!out.has(field)) out.set(field, scope);
  };
  for (const scope of scopes || []) {
    if (scope === '$') {
      if (doc && typeof doc === 'object' && !Array.isArray(doc)) for (const k of Object.keys(doc)) add(k, scope);
      continue;
    }
    const m = /^\$\.([A-Za-z0-9_$-]+)(\[\*\])?$/.exec(scope);
    if (!m) continue;
    const target = doc?.[m[1]];
    if (m[2]) {
      if (Array.isArray(target)) {
        for (const item of target) {
          if (item && typeof item === 'object' && !Array.isArray(item)) for (const k of Object.keys(item)) add(k, scope);
        }
      }
    } else if (target && typeof target === 'object' && !Array.isArray(target)) {
      for (const k of Object.keys(target)) add(k, scope);
    }
  }
  return [...out.entries()].map(([field, scope]) => ({ field, scope })).sort((a, b) => a.field.localeCompare(b.field));
}

/**
 * Un champ est-il NOMMÉ par au moins un lecteur ? (mot entier, toutes syntaxes :
 * "x", 'x', .x, [x], rule.get("x")…)
 * @param {string} repoRoot
 * @param {string} field
 * @param {string[]} readerPaths
 * @returns {string[]} lecteurs qui nomment le champ
 */
export function readersNamingField(repoRoot, field, readerPaths) {
  const re = new RegExp(`(^|[^A-Za-z0-9_])${field.replace(/[.*+?^${}()|[\]\\-]/g, '\\$&')}([^A-Za-z0-9_]|$)`);
  const found = [];
  for (const rel of readerPaths) {
    let text;
    try {
      text = readFileSync(join(repoRoot, rel), 'utf-8');
    } catch {
      continue;
    }
    if (re.test(text)) found.push(rel);
  }
  return found;
}

/**
 * Audit complet d'une entrée du manifeste.
 * @param {string} repoRoot
 * @param {object} decl
 * @param {{code:string[], data:string[]}} corpus
 * @returns {Array<object>} un résultat par FICHIER déclarant
 */
export function auditDeclaration(repoRoot, decl, corpus) {
  const targets = [];
  if (decl.kind === 'agent_md') {
    const absDir = join(repoRoot, decl.dir);
    if (existsSync(absDir) && statSync(absDir).isDirectory()) {
      for (const f of readdirSync(absDir).sort()) {
        if (extname(f) === (decl.extension || '.md')) targets.push(`${decl.dir}/${f}`);
      }
    }
  } else if (decl.path) {
    if (existsSync(join(repoRoot, decl.path))) targets.push(decl.path);
  }

  const results = [];
  for (const relPath of targets) {
    // Le répertoire lui-même est une aiguille valable : un lecteur peut faire un
    // listdir sans jamais nommer un fichier précis.
    const needles = [...needlesFor(relPath), ...(decl.dir ? needlesFor(decl.dir, { includeBasename: false }) : [])];
    const codeHits = findMentions(repoRoot, needles, corpus.code);
    const dataHits = findMentions(repoRoot, needles, corpus.data);
    // Mentions PROUVÉES non-lisantes (commentaire, écriture) : écartées des lecteurs mais
    // JAMAIS masquées — elles ressortent en `non_reader_mentions` avec leur raison, pour
    // qu'une exclusion abusive se voie dans le rapport.
    const nonReaderReasons = new Map((decl.non_reader_mentions || []).map((x) => [x.path, x.reason || 'raison non renseignée']));
    const readers = codeHits.filter((h) => !nonReaderReasons.has(h.path)).map((h) => ({ path: h.path, lines: h.lines }));
    const nonReaderMentions = codeHits
      .filter((h) => nonReaderReasons.has(h.path))
      .map((h) => ({ path: h.path, lines: h.lines, reason: nonReaderReasons.get(h.path) }));

    const findings = [];
    // D1 n'a de sens que si PERSONNE ne consomme le fichier. Un consommateur EXTERNE au repo
    // (runtime Claude Code pour .claude/agents/*.md) rendrait « lettre morte » factuellement
    // faux : on affiche le fait brut, on n'émet pas le constat.
    if (readers.length === 0 && !decl.external_consumer) {
      findings.push({ rule: 'D1', detail: `aucun fichier de code du repo ne mentionne « ${relPath} » — déclaration lettre morte côté runtime` });
    }
    if (decl.kind === 'agent_md') findings.push(...auditAgentFile(repoRoot, relPath, decl));

    let unreadFields = [];
    let readerFieldCoverage = [];
    let fieldAnalysis = 'non_applicable';
    if (decl.kind === 'policy_json') {
      if (readers.length === 0) {
        fieldAnalysis = 'ignoree_aucun_lecteur';
      } else {
        let doc = null;
        try {
          doc = JSON.parse(readFileSync(join(repoRoot, relPath), 'utf-8'));
        } catch {
          doc = null;
        }
        if (doc === null) {
          fieldAnalysis = 'ignoree_json_illisible';
        } else {
          fieldAnalysis = 'effectuee';
          const readerPaths = readers.map((r) => r.path);
          const declaredFields = collectDeclaredFields(doc, decl.field_scopes, decl.ignore_fields);
          const namedBy = new Map();
          for (const { field, scope } of declaredFields) {
            const naming = readersNamingField(repoRoot, field, readerPaths);
            namedBy.set(field, naming);
            if (naming.length === 0) unreadFields.push({ field, scope });
          }
          // Couverture PAR LECTEUR : c'est là qu'apparaît la dérive « le fichier est bien
          // lu, mais CE lecteur n'utilise pas la granularité déclarée » (cas agent_id).
          readerFieldCoverage = readerPaths.map((rp) => ({
            reader: rp,
            named: declaredFields.filter((f) => namedBy.get(f.field).includes(rp)).map((f) => f.field),
            not_named: declaredFields.filter((f) => !namedBy.get(f.field).includes(rp)).map((f) => f.field),
          }));
        }
      }
      for (const uf of unreadFields) {
        findings.push({
          rule: 'D2',
          detail: `champ « ${uf.field} » (scope ${uf.scope}) déclaré mais NOMMÉ par aucun lecteur — la granularité déclarée n'est pas appliquée`,
        });
      }
      for (const cov of readerFieldCoverage) {
        // Fait brut, aucun jugement : un lecteur qui nomme une partie seulement des champs
        // déclarés consomme moins que ce que le fichier déclare. Émis uniquement pour un
        // lecteur qui nomme AU MOINS un champ (donc consommateur avéré, pas une mention).
        if (cov.named.length > 0 && cov.not_named.length > 0) {
          findings.push({
            rule: 'D7',
            detail: `lecteur ${cov.reader} nomme ${cov.named.length}/${cov.named.length + cov.not_named.length} champs déclarés — ne nomme PAS : ${cov.not_named.join(', ')}`,
          });
        }
      }
    }

    results.push({
      declaration_id: decl.id,
      file: relPath,
      declares: decl.declares || null,
      reader_verdict: readers.length > 0 ? 'MENTIONNE_PAR_CODE' : 'AUCUN_LECTEUR_CODE',
      external_consumer: decl.external_consumer || null,
      readers,
      non_reader_mentions: nonReaderMentions,
      other_mentions: dataHits.map((h) => ({ path: h.path, lines: h.lines })),
      field_analysis: fieldAnalysis,
      unread_fields: unreadFields,
      reader_field_coverage: readerFieldCoverage,
      findings,
    });
  }
  return results;
}

/**
 * Lance le capteur sur tout le manifeste.
 * @param {string} repoRoot
 * @returns {{repoRoot:string, corpus_size:{code:number,data:number}, entries:Array<object>, summary:object, out_of_scope:string[]}}
 */
export function runDeclarationAudit(repoRoot) {
  const wl = loadWatchlist(repoRoot);
  const corpus = listCorpus(repoRoot, wl.scan || {});
  const entries = [];
  for (const decl of wl.declarations || []) entries.push(...auditDeclaration(repoRoot, decl, corpus));

  const summary = {
    files_watched: entries.length,
    without_code_reader: entries.filter((e) => e.reader_verdict === 'AUCUN_LECTEUR_CODE').length,
    external_consumer_declared: entries.filter((e) => e.external_consumer).length,
    with_findings: entries.filter((e) => e.findings.length > 0).length,
    unread_field_count: entries.reduce((n, e) => n + e.unread_fields.length, 0),
    findings_by_rule: {},
  };
  for (const e of entries) {
    for (const f of e.findings) summary.findings_by_rule[f.rule] = (summary.findings_by_rule[f.rule] || 0) + 1;
  }
  return { repoRoot: '.', corpus_size: { code: corpus.code.length, data: corpus.data.length }, entries, summary, out_of_scope: OUT_OF_SCOPE };
}

const RULES = {
  D1: 'déclaration sans aucun lecteur code',
  D2: 'champ déclaré nommé par aucun lecteur',
  D3: 'frontmatter absent ou non fermé',
  D4: 'champ requis absent (description)',
  D5: 'champ hors-schéma',
  D6: 'chemin déclaré inexistant',
  D7: 'lecteur ne nommant qu\'une partie des champs déclarés',
};

function main() {
  const here = dirname(fileURLToPath(import.meta.url));
  const args = process.argv.slice(2);
  const positional = args.find((a) => !a.startsWith('--'));
  const repoRoot = positional ? resolve(positional) : resolve(here, '..');

  let r;
  try {
    r = runDeclarationAudit(repoRoot);
  } catch (err) {
    console.error(`[declaration_readers] ERREUR INTERNE : ${err.message}`);
    process.exit(2);
  }

  console.error('=== CAPTEUR DÉCLARATION↔LECTEUR ===');
  console.error(`corpus scanné : ${r.corpus_size.code} fichiers code · ${r.corpus_size.data} fichiers données\n`);
  const short = (s, n = 90) => (s.length > n ? `${s.slice(0, n)}…` : s);
  for (const e of r.entries) {
    const mark = e.reader_verdict !== 'AUCUN_LECTEUR_CODE' ? '·' : e.external_consumer ? '~' : '⚠';
    console.error(`${mark} ${e.file}`);
    if (e.readers.length === 0) {
      console.error(e.external_consumer
        ? `    lecteurs : AUCUN LECTEUR CODE — consommateur externe déclaré : ${short(e.external_consumer)} (D1 non émis)`
        : '    lecteurs : AUCUN LECTEUR CODE (D1)');
      if (e.other_mentions.length) {
        console.error(`    mentions non-code (informatif, PAS des lecteurs) : ${e.other_mentions.slice(0, 3).map((m) => `${m.path}:${m.lines[0]}`).join(', ')}`);
      }
    } else {
      console.error(`    lecteurs : ${e.readers.map((x) => `${x.path}:${x.lines.join(',')}`).join(' · ')}`);
    }
    for (const nr of e.non_reader_mentions) {
      console.error(`    mention ÉCARTÉE (pas un lecteur) : ${nr.path}:${nr.lines.join(',')} — ${short(nr.reason, 110)}`);
    }
    if (e.field_analysis === 'effectuee') {
      console.error(`    champs déclarés non nommés par un lecteur : ${e.unread_fields.length ? e.unread_fields.map((u) => u.field).join(', ') : 'aucun ✅'}`);
    }
    for (const f of e.findings) console.error(`    [${f.rule}] ${f.detail}`);
  }
  console.error('\n--- RÉSUMÉ ---');
  console.error(`fichiers surveillés : ${r.summary.files_watched}`);
  console.error(`sans lecteur code   : ${r.summary.without_code_reader} (dont ${r.summary.external_consumer_declared} à consommateur externe déclaré — D1 non émis)`);
  console.error(`champs non nommés   : ${r.summary.unread_field_count}`);
  for (const [rule, n] of Object.entries(r.summary.findings_by_rule).sort()) {
    console.error(`  ${rule} (${RULES[rule]}) : ${n}`);
  }
  console.error('\nCe capteur MESURE — il ne juge pas. exit 0 même en présence de constats.');
  console.error('Limites assumées :');
  for (const l of r.out_of_scope) console.error(`  - ${l}`);

  console.log(JSON.stringify(r, null, 2));
  process.exit(0);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main();
}

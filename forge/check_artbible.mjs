#!/usr/bin/env node
// check_artbible.mjs — oracle de CONFORMITÉ STRUCTURELLE non-LLM pour l'Art Director
// (contrat s2.5-artbible.yaml). Ne juge JAMAIS "est-ce que c'est beau" — vérifie la
// FORME de art_bible.md (frontmatter + sections non triviales, même famille de check
// que check_prisme.mjs pour product_snapshot.md) et la VALIDITÉ STRUCTURELLE de chaque
// asset_request produit, en délégant à asset_request.mjs::validateRequestShape (zéro
// duplication de la règle des 3 états). Le taux de resolution OK/BLOCKED contre le
// catalogue réel est rapporté en statistique advisory — jamais un critère pass/fail
// (cf. docs/forge/ASSET_CONTRACT_V0.md "BLOCKED vs FAIL").
//
// v0.1 (2026-07-14) — ferme le vecteur trouvé par la sonde adversariale "deceptive
// builder" (docs/forge/S2_5_ARTBIBLE_DECEPTIVE_PROBE_NOTE.md) : une bible pouvait
// affirmer en prose "personnage/obstacles/décor couverts" avec 2 requêtes génériques
// seulement, sans qu'aucun mécanisme ne vérifie la COUVERTURE besoin<->requête. La
// section BESOINS VISUELS (JSON embarqué) + `checkCoverage` ferment ce vecteur : un
// besoin `required:true` sans requête au même `entity_role` => verdict BLOCKED (pas
// FAIL — l'artefact est bien formé, seule une couverture manque, cf. `verdict`
// ci-dessous). Le verdict de RESOLUTION contre le catalogue (déjà existant, advisory,
// `resolution_stats`) reste totalement INCHANGÉ et distinct de cette nouvelle
// vérification (un asset non résolu dans le catalogue n'est jamais une erreur de
// contrat — seule l'ABSENCE de toute requête pour un besoin requis l'est).
//
// Usage :
//   node check_artbible.mjs <art_bible.md> <asset_requests.json> [--catalog <path>] [--json]
// Exit 0 = OK · 1 = BLOCKED (couverture manquante) · 2 = FAIL (forme) / usage/illisible.
import { readFile } from 'node:fs/promises';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { validateRequestShape, evaluateAssetRequest, ENTITY_ROLES } from './asset_request.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const DEFAULT_CATALOG_PATH = resolve(__dirname, '..', 'knowledge_base', 'catalog.json');

const REQUIRED_SECTIONS = [
  { key: 'identite_visuelle', pattern: /IDENTIT[ÉE] VISUELLE/i },
  { key: 'rationale', pattern: /RATIONALE/i },
  { key: 'besoins_visuels', pattern: /BESOINS VISUELS/i },
];
const PLACEHOLDER_MARKERS = [/à\s*d[ée]finir/i, /\bTBD\b/i, /\?\?\?/, /\bTODO\b/i, /\bXXX\b/];
const MIN_SECTION_CHARS = 40;
const JSON_FENCE = /```json\s*([\s\S]*?)```/i;

/**
 * Extrait le frontmatter YAML minimal (--- ... ---) sans dépendance externe : ne
 * supporte que les listes inline `cle: [a, b, c]` et chaînes simples — suffisant pour
 * les 2 champs attendus (styles, mood_keywords). Un frontmatter absent/malformé
 * retourne null (traité comme un finding, pas une exception).
 * @param {string} content
 * @returns {{styles: string[], mood_keywords: string[]}|null}
 */
export function parseFrontmatter(content) {
  const m = content.match(/^---\r?\n([\s\S]*?)\r?\n---/);
  if (!m) return null;
  const body = m[1];
  const out = {};
  for (const line of body.split(/\r?\n/)) {
    const kv = line.match(/^(\w+):\s*\[(.*)\]\s*$/);
    if (!kv) continue;
    const [, key, listBody] = kv;
    out[key] = listBody
      .split(',')
      .map((s) => s.trim().replace(/^['"]|['"]$/g, ''))
      .filter((s) => s.length > 0);
  }
  return out;
}

/**
 * Découpe le markdown en sections par en-têtes `## N. TITRE`, même convention que
 * check_prisme.mjs::splitSections.
 * @param {string} content
 * @returns {Map<string,string>}
 */
export function splitSections(content) {
  const headingRegex = /^##\s+\d+\.\s+(.+)$/gm;
  const matches = [...content.matchAll(headingRegex)];
  const sections = new Map();
  for (let i = 0; i < matches.length; i += 1) {
    const heading = matches[i][1];
    const start = matches[i].index + matches[i][0].length;
    const end = i + 1 < matches.length ? matches[i + 1].index : content.length;
    const body = content.slice(start, end).trim();
    const found = REQUIRED_SECTIONS.find((s) => s.pattern.test(heading));
    if (found) sections.set(found.key, body);
  }
  return sections;
}

/**
 * Valide la forme d'UNE entrée de `visual_requirements` (v0.1). Règle des 3 états :
 * `id`/`entity_role`/`description` Critiques (jamais absents) ; `required` doit être
 * un booléen explicite (pas de défaut silencieux — un besoin dont on ne sait pas
 * s'il est requis n'est pas la même chose qu'un besoin déclaré optionnel).
 * @param {object} vr
 * @param {number} i index (pour le message d'erreur)
 * @returns {string[]} findings (vide = conforme)
 */
export function validateVisualRequirement(vr, i) {
  const findings = [];
  if (vr === null || typeof vr !== 'object' || Array.isArray(vr)) {
    return [`visual_requirements[${i}]: doit etre un objet`];
  }
  if (!('id' in vr) || typeof vr.id !== 'string' || vr.id.trim().length === 0) {
    findings.push(`visual_requirements[${i}]: id absent ou vide`);
  }
  if (!('entity_role' in vr) || !ENTITY_ROLES.includes(vr.entity_role)) {
    findings.push(`visual_requirements[${i}]: entity_role invalide (attendu: ${ENTITY_ROLES.join('|')})`);
  }
  if (!('required' in vr) || typeof vr.required !== 'boolean') {
    findings.push(`visual_requirements[${i}]: required doit etre un booleen explicite (true/false, jamais absent)`);
  }
  if (!('description' in vr) || typeof vr.description !== 'string' || vr.description.trim().length === 0) {
    findings.push(`visual_requirements[${i}]: description absente ou vide`);
  }
  return findings;
}

/**
 * Extrait `visual_requirements` du bloc ```json embarqué dans la section BESOINS
 * VISUELS (pas de dépendance YAML — ce studio n'utilise que JSON.parse pour les
 * artefacts structurés, cf. asset_requests.json). Format attendu :
 * ```json
 * { "visual_requirements": [ {id, entity_role, required, description}, ... ] }
 * ```
 * @param {string} sectionBody texte de la section (déjà extrait par splitSections)
 * @returns {{findings: string[], visualRequirements: object[]}}
 */
export function extractVisualRequirements(sectionBody) {
  const m = sectionBody.match(JSON_FENCE);
  if (!m) {
    return { findings: ['section besoins_visuels : bloc ```json absent'], visualRequirements: [] };
  }
  let doc;
  try {
    doc = JSON.parse(m[1]);
  } catch (err) {
    return { findings: [`section besoins_visuels : JSON invalide (${err.message})`], visualRequirements: [] };
  }
  if (doc === null || typeof doc !== 'object' || !Array.isArray(doc.visual_requirements)) {
    return { findings: ['section besoins_visuels : attendu {visual_requirements: [...]}'], visualRequirements: [] };
  }
  const findings = doc.visual_requirements.flatMap((vr, i) => validateVisualRequirement(vr, i));
  return { findings, visualRequirements: findings.length === 0 ? doc.visual_requirements : [] };
}

/**
 * Vérifie la COUVERTURE besoin<->requête (v0.1) : chaque `visual_requirements` marqué
 * `required:true` doit avoir au moins une `asset_request` du même `entity_role`.
 * Ne juge JAMAIS le contenu (aucune lecture de la prose du rationale) — un besoin
 * déclaré "couvert" en texte libre qui n'a pas de requête correspondante reste
 * `missing`, quoi que dise la prose (ferme exactement le vecteur de la sonde
 * "deceptive builder"). `noAssetsNeeded=true` court-circuite la vérification (aucune
 * couverture n'est attendue, cf. Asset Contract V0 "cas à préserver").
 * @param {object[]} visualRequirements
 * @param {object[]} requests
 * @param {boolean} noAssetsNeeded
 * @returns {{checked: boolean, missing: {id:string, entity_role:string}[], satisfied: string[]}}
 */
export function checkCoverage(visualRequirements, requests, noAssetsNeeded) {
  if (noAssetsNeeded) {
    return { checked: false, missing: [], satisfied: [] };
  }
  const requestRoles = new Set(requests.map((r) => r.entity_role));
  const missing = [];
  const satisfied = [];
  for (const vr of visualRequirements) {
    if (vr.required !== true) continue;
    if (requestRoles.has(vr.entity_role)) satisfied.push(vr.id);
    else missing.push({ id: vr.id, entity_role: vr.entity_role });
  }
  return { checked: true, missing, satisfied };
}

/**
 * Vérifie la forme de art_bible.md : frontmatter {styles[], mood_keywords[]} non
 * vides + les 3 sections requises (dont BESOINS VISUELS, v0.1), non triviales, sans
 * placeholder, et extrait/valide `visual_requirements`.
 * @param {string} content
 * @returns {{findings: string[], styles: string[], visualRequirements: object[]}}
 */
export function checkArtBibleMarkdown(content) {
  const findings = [];
  const fm = parseFrontmatter(content);
  if (!fm) {
    findings.push('frontmatter YAML absent ou illisible (attendu: --- styles: [...] mood_keywords: [...] ---)');
  } else {
    if (!Array.isArray(fm.styles) || fm.styles.length === 0) findings.push('frontmatter.styles absent ou vide');
    if (!Array.isArray(fm.mood_keywords) || fm.mood_keywords.length === 0) findings.push('frontmatter.mood_keywords absent ou vide');
  }

  const sections = splitSections(content);
  let visualRequirements = [];
  for (const { key } of REQUIRED_SECTIONS) {
    if (!sections.has(key)) {
      findings.push(`section manquante : ${key}`);
      continue;
    }
    const body = sections.get(key);
    if (body.length < MIN_SECTION_CHARS) findings.push(`section trop courte / probablement vide : ${key} (${body.length} caractères)`);
    for (const marker of PLACEHOLDER_MARKERS) {
      if (marker.test(body)) findings.push(`placeholder non résolu détecté dans ${key} : ${marker}`);
    }
    if (key === 'besoins_visuels') {
      const extracted = extractVisualRequirements(body);
      findings.push(...extracted.findings);
      visualRequirements = extracted.visualRequirements;
    }
  }

  return { findings, styles: fm && Array.isArray(fm.styles) ? fm.styles : [], visualRequirements };
}

/**
 * Vérifie asset_requests.json : forme {requests[], no_assets_needed, reason},
 * cohérence declared-empty (no_assets_needed=true <=> requests=[] et reason rempli),
 * puis chaque request via validateRequestShape (délégué, zéro duplication) et la
 * cohérence request.style ∈ styles déclarés par la bible.
 * @param {object} doc
 * @param {string[]} bibleStyles
 * @returns {string[]} findings (vide = conforme)
 */
export function checkAssetRequestsShape(doc, bibleStyles) {
  const findings = [];
  if (doc === null || typeof doc !== 'object' || Array.isArray(doc)) {
    return ['asset_requests.json doit etre un objet {requests, no_assets_needed, reason}'];
  }
  if (!('requests' in doc) || !Array.isArray(doc.requests)) findings.push('champ manquant ou invalide: requests (tableau)');
  if (!('no_assets_needed' in doc) || typeof doc.no_assets_needed !== 'boolean') findings.push('champ manquant ou invalide: no_assets_needed (bool)');
  if (!('reason' in doc) || !(doc.reason === null || (typeof doc.reason === 'string' && doc.reason.length > 0))) {
    findings.push('champ manquant ou invalide: reason (null ou chaine non vide)');
  }
  if (findings.length > 0) return findings;

  if (doc.no_assets_needed === true) {
    if (doc.requests.length !== 0) findings.push('no_assets_needed=true exige requests=[] (decision assumee incoherente)');
    if (doc.reason === null) findings.push('no_assets_needed=true exige reason rempli (decision expliquee, pas un oubli)');
    return findings;
  }

  if (doc.requests.length === 0) {
    findings.push('requests vide sans no_assets_needed=true — declarez explicitement la decision (jamais un oubli silencieux)');
    return findings;
  }

  doc.requests.forEach((req, i) => {
    const shapeErrors = validateRequestShape(req);
    if (shapeErrors.length > 0) {
      shapeErrors.forEach((e) => findings.push(`requests[${i}]: ${e}`));
      return;
    }
    if (!bibleStyles.map((s) => s.toLowerCase()).includes(String(req.style).toLowerCase())) {
      findings.push(`requests[${i}]: style '${req.style}' non declare dans le frontmatter.styles de l'art_bible (coherence bible<->requetes)`);
    }
  });

  return findings;
}

const EMPTY_COVERAGE = { checked: false, missing: [], satisfied: [] };
const EMPTY_STATS = { ok: 0, blocked: 0, total: 0 };

/**
 * Point d'entrée complet : lit les deux fichiers, vérifie la forme, vérifie la
 * COUVERTURE besoin<->requête (v0.1), et calcule les statistiques de resolution
 * ADVISORY (jamais gating) contre le catalogue.
 *
 * Vocabulaire de verdict unique du studio (jamais PASS/CONCERNS) :
 * - `FAIL`    : l'artefact est malformé (frontmatter/section/JSON/schéma invalide).
 * - `BLOCKED` : l'artefact est bien formé mais un besoin visuel `required:true` n'a
 *   aucune `asset_request` de même `entity_role` (couverture manquante — distinct de
 *   la resolution contre le catalogue, qui reste ADVISORY, cf. `resolution_stats`).
 * - `OK`      : bien formé et entièrement couvert.
 * `pass` (booléen, conservé pour compat CLI/appelants existants) = `verdict === 'OK'`.
 *
 * @param {string} artBiblePath
 * @param {string} assetRequestsPath
 * @param {object} [catalog] catalogue déjà chargé (optionnel, sinon lu depuis DEFAULT_CATALOG_PATH)
 * @returns {Promise<{pass: boolean, verdict: 'OK'|'FAIL'|'BLOCKED', findings: string[],
 *   coverage: {checked:boolean, missing:object[], satisfied:string[]},
 *   resolution_stats: {ok:number, blocked:number, total:number}}>}
 */
export async function checkArtBible(artBiblePath, assetRequestsPath, catalog) {
  let bibleContent;
  let requestsRaw;
  try {
    bibleContent = await readFile(artBiblePath, 'utf-8');
  } catch (err) {
    return { pass: false, verdict: 'FAIL', findings: [`art_bible.md illisible : ${err.message}`], coverage: EMPTY_COVERAGE, resolution_stats: EMPTY_STATS };
  }
  try {
    requestsRaw = await readFile(assetRequestsPath, 'utf-8');
  } catch (err) {
    return { pass: false, verdict: 'FAIL', findings: [`asset_requests.json illisible : ${err.message}`], coverage: EMPTY_COVERAGE, resolution_stats: EMPTY_STATS };
  }

  const { findings: bibleFindings, styles, visualRequirements } = checkArtBibleMarkdown(bibleContent);
  let doc;
  try {
    doc = JSON.parse(requestsRaw);
  } catch (err) {
    return { pass: false, verdict: 'FAIL', findings: [...bibleFindings, `asset_requests.json: JSON invalide (${err.message})`], coverage: EMPTY_COVERAGE, resolution_stats: EMPTY_STATS };
  }
  const requestFindings = checkAssetRequestsShape(doc, styles);
  const findings = [...bibleFindings, ...requestFindings];

  if (findings.length > 0) {
    return { pass: false, verdict: 'FAIL', findings, coverage: EMPTY_COVERAGE, resolution_stats: EMPTY_STATS };
  }

  const coverage = checkCoverage(visualRequirements, doc.requests, doc.no_assets_needed);

  // Statistiques de resolution — ADVISORY, ne participe jamais au verdict (cf.
  // doctrine BLOCKED vs FAIL : un asset qui n'existe pas encore dans le catalogue est
  // un fait légitime, pas un défaut de l'Art Director). Totalement indépendant de
  // `coverage` : la couverture porte sur la PRÉSENCE d'une requête, la resolution sur
  // sa SATISFACTION contre le catalogue réel — deux questions distinctes.
  let ok = 0;
  let blocked = 0;
  if (doc.no_assets_needed === false && catalog) {
    for (const req of doc.requests) {
      const result = evaluateAssetRequest(req, catalog);
      if (result.verdict === 'OK') ok += 1;
      else if (result.verdict === 'BLOCKED') blocked += 1;
    }
  }
  const resolution_stats = { ok, blocked, total: ok + blocked };

  if (coverage.checked && coverage.missing.length > 0) {
    return { pass: false, verdict: 'BLOCKED', findings: [], coverage, resolution_stats };
  }
  return { pass: true, verdict: 'OK', findings: [], coverage, resolution_stats };
}

// ---- CLI ----
const isMain = process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isMain) {
  const argv = process.argv.slice(2);
  const positional = argv.filter((a) => !a.startsWith('--'));
  const asJson = argv.includes('--json');
  const catalogFlagIdx = argv.indexOf('--catalog');
  const catalogPath = catalogFlagIdx !== -1 ? resolve(argv[catalogFlagIdx + 1]) : DEFAULT_CATALOG_PATH;

  if (positional.length < 2) {
    console.error('usage: node check_artbible.mjs <art_bible.md> <asset_requests.json> [--catalog <path>] [--json]');
    process.exit(2);
  }

  (async () => {
    let catalog = null;
    try {
      catalog = JSON.parse(await readFile(catalogPath, 'utf-8'));
    } catch {
      // Catalogue illisible : les stats de resolution seront omises (0/0/0), la
      // vérification de FORME reste inchangée (elle ne dépend pas du catalogue).
    }
    const result = await checkArtBible(positional[0], positional[1], catalog);
    if (asJson) {
      console.log(JSON.stringify(result, null, 2));
    } else {
      console.log(`VERDICT ART_BIBLE: ${result.verdict}`);
      result.findings.forEach((f) => console.error(`  FAIL: ${f}`));
      if (result.coverage.checked) {
        result.coverage.missing.forEach((m) => console.error(`  BLOCKED: MISSING_ASSET_COVERAGE ${m.id} (entity_role=${m.entity_role})`));
      }
      console.error(`  resolution (advisory): ${result.resolution_stats.ok} OK / ${result.resolution_stats.blocked} BLOCKED / ${result.resolution_stats.total} total`);
    }
    process.exit(result.verdict === 'OK' ? 0 : result.verdict === 'BLOCKED' ? 1 : 2);
  })();
}

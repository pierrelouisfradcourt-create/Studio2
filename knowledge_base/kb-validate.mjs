// kb-validate.mjs — validateur NON-LLM du catalogue knowledge_base/catalog.json.
// Implémente R1..R12 de docs/forge/KB_INGESTION_CONTRACT.md. Zéro réseau, zéro LLM.
// Exit 0 = conforme · 1 = violations · 2 = catalogue illisible / erreur interne.
//
// v3 (2026-07-13, Tier 1 #3) : entry_type "role" — les rôles (knowledge_base/roles/*.yaml)
// entrent RÉELLEMENT dans le catalogue (indexables, cherchables) au lieu de vivre en
// prose à côté. `requires` (rôle) et `affordances` (brick, mandatoire, `{}` par défaut)
// partagent la même forme machine-lisible {capacité: {type, description}}. R13 : le pont
// `fulfilled_by` -> catalogue est désormais VÉRIFIÉ (brique référencée doit exister) —
// jusqu'ici une simple citation en prose, jamais contrôlée.
//
// v4 (2026-07-13, Tier 1 #4) : R14 -- le pont SEARCH<->ROLE devient une comparaison
// REELLE, pas une declaration crue sur parole : fulfilled_by n'est valide que si
// affordances(piece) recouvre requires(role) (comparaison par nom de capacite,
// exportee via missingCapabilities pour reutilisation par search.mjs --fulfills).
//
// v2 (2026-07-12) : durci après red-team claude-blind (LM Studio down). Corrections
// confirmées par exécution — voir docs/forge/KB_REDTEAM_ADJUDICATION.md :
//   - toute preuve de chemin (path, proof_of_use, usage_examples, tests) passe par la
//     MÊME garde : repo-relatif + sous-dossier attendu + pas de '..'/absolu + fichier réel
//     (pas un dossier) + refus des liens symboliques + confinement realpath.
//   - R10 pureté : préfixe node: optionnel, spécificateurs nus, import()/require/eval/
//     Function, Math["random"], fetch/globalThis, après stripping commentaires+chaînes.
//   - I/O disque encapsulées (plus de crash EISDIR ; toujours un verdict).
//   - contenu inspecté : marqueur GPL dans du code déclaré permissif -> REJET ; octets d'un
//     asset 2D ingéré doivent être un raster connu (anti « 3D déclaré 2D »).
//   - schéma fermé : clé inconnue -> REJET. Casse de fichier vérifiée (portabilité CI).
import { readFileSync, existsSync, lstatSync, realpathSync, readdirSync } from "node:fs";
import { createHash } from "node:crypto";
import { resolve, dirname, isAbsolute, basename, sep } from "node:path";
import { fileURLToPath } from "node:url";

// ---- listes fermées (le contrat est la spec ; toute extension = amendement ratifié) ----
const CODE_LICENSES = ["MIT", "CC0-1.0", "Apache-2.0", "BSD-2-Clause", "BSD-3-Clause"];
const GPL_LICENSES = ["GPL-2.0-only", "GPL-2.0-or-later", "GPL-3.0-only", "GPL-3.0-or-later"];
const ASSET_LICENSES = ["CC0-1.0", "MIT", "CC-BY-4.0", "CC-BY-3.0"];
const PATTERN_LICENSES = [...CODE_LICENSES, ...GPL_LICENSES];
const KNOWN_SPDX = [...new Set([...CODE_LICENSES, ...GPL_LICENSES, ...ASSET_LICENSES])];

// v3 (2026-07-13) — amendement R3 (non red-teamé externellement, auto-revue de session
// seule) : le code purement ORIGINAL, sans inspiration externe citable, n'avait aucun
// chemin de provenance valide (ni provenance_url, ni dependance pat-*). Marqueur FERMÉ,
// exact, auditable — pas une auto-déclaration libre : `source` doit commencer PAR CETTE
// CHAINE EXACTE pour être reconnue comme provenance originale valide (R3).
const ORIGINAL_MARKER = "ORIGINAL — aucune inspiration externe citee";

const HEX64 = /^[0-9a-f]{64}$/;
const URL_RE = /^https?:\/\/.+/;

// v4 (2026-08-02) — amendement R3 RATIFIE PIERRE (option 1 de
// knowledge_base/proposals/_TAXONOMY_AMENDMENT_PROPOSAL.md) : la KB accepte la
// connaissance PRODUITE par la Forge (lecon validee) en plus de la connaissance
// importee. Schema FERME de la provenance interne — toute cle inconnue = REJET,
// meme regime que le reste du validateur. La validation humaine reste
// obligatoire (validation.status === "validated" exige, decideur nomme).
function isProvenanceInternal(v) {
  if (v === null || typeof v !== "object" || Array.isArray(v)) return false;
  const keys = Object.keys(v).sort();
  if (keys.join(",") !== "lesson_id,lessons_source,supporting_runs,validation") return false;
  if (!isStr(v.lessons_source) || !isStr(v.lesson_id)) return false;
  if (!Array.isArray(v.supporting_runs) || v.supporting_runs.length === 0
      || !v.supporting_runs.every((r) => typeof r === "string" && r.length > 0)) return false;
  const val = v.validation;
  if (val === null || typeof val !== "object" || Array.isArray(val)) return false;
  const vkeys = Object.keys(val).sort();
  if (vkeys.join(",") !== "status,validated_at,validated_by") return false;
  if (val.status !== "validated") return false;
  if (!isStr(val.validated_by) || !isStr(val.validated_at)) return false;
  return true;
}
const ID_PREFIX = { asset: "asset-", system: "sys-", pattern: "pat-", template: "tpl-", role: "role-" };
// Sous-dossier attendu par type (confinement — R7/§5).
const SUBDIR = { asset: "knowledge_base/assets/", system: "knowledge_base/systems/",
  template: "knowledge_base/templates/", pattern: "knowledge_base/patterns/",
  proof: "knowledge_base/proofs/", role: "knowledge_base/roles/" };

// Magic bytes des rasters 2D admis (anti « 3D/godot déclaré 2D », red-team F8).
const RASTER_MAGICS = [
  [0x89, 0x50, 0x4e, 0x47],       // PNG
  [0xff, 0xd8, 0xff],             // JPEG
  [0x47, 0x49, 0x46, 0x38],       // GIF8
  [0x42, 0x4d],                   // BMP
];
function isRaster(buf) {
  if (buf.length >= 12 && buf.slice(0, 4).toString("latin1") === "RIFF" && buf.slice(8, 12).toString("latin1") === "WEBP") return true;
  return RASTER_MAGICS.some((sig) => sig.every((b, i) => buf[i] === b));
}

// GLB binaire : entete 12 octets, magic "glTF" + version (spec glTF 2.0 §4.4.1).
// Meme garde d'octets que isRaster cote 2D : un fichier renomme .glb ne passe pas.
function isGLB(buf) {
  return buf.length >= 12 && buf.slice(0, 4).toString("latin1") === "glTF";
}

// R10 — motifs d'impureté. Deux passes distinctes (limite intrinsèque de l'analyse textuelle,
// cf. §7 : l'AST est le vrai correctif d'un futur incrément) :
//  - RAW : les motifs qui dépendent d'un LITTÉRAL de chaîne (spécificateur d'import,
//    notation crochet Math['random']) — scannés sur le texte brut, sinon le stripping les efface.
//  - STRIPPED : les accès globaux / appels — scannés après retrait commentaires+chaînes,
//    pour éliminer les faux positifs (window. en commentaire, red-team F5).
const NODE_MODS = "fs|fs/promises|http|http2|https|net|dns|tls|os|vm|worker_threads|dgram|process|cluster|inspector|repl|readline|child_process";
const IMPURITY_RAW = [
  [new RegExp(`\\bfrom\\s*["'](?:node:)?(?:${NODE_MODS})["']`), "import de module Node (fs/http/child_process/…)"],
  [new RegExp(`\\brequire\\s*\\(\\s*["'](?:node:)?(?:${NODE_MODS})["']`), "require de module Node"],
  [/\bMath\s*\[\s*["']random["']\s*\]/, "Math['random']"],
  [/\bglobalThis\s*\[\s*["'](?:fetch|process|require)["']\s*\]/, "globalThis['fetch'|…]"],
];
const IMPURITY_STRIPPED = [
  [/\bimport\s*\(/, "import() dynamique"],
  [/\beval\s*\(/, "eval("],
  [/\bnew\s+Function\s*\(/, "new Function("],
  [/\bfetch\s*\(/, "fetch("],
  [/\bglobalThis\s*\./, "globalThis (accès global)"],
  [/\bMath\s*\.\s*random\b/, "Math.random"],
  [/\bDate\s*\.\s*now\b/, "Date.now (non déterministe)"],
  [/\bnew\s+Date\b/, "new Date (non déterministe)"],
  [/\bwindow\s*[.[]/, "window (DOM)"],
  [/\bdocument\s*[.[]/, "document (DOM)"],
  [/\bprocess\s*\.\s*(env|exit|argv|binding|cwd)\b/, "process.* (environnement)"],
];
// R10 — motifs d'impureté GDScript. Symétrique d'IMPURITY_STRIPPED (JS), appliqué aux
// seuls fichiers .gd : les motifs JS n'ont aucun équivalent lexical en GDScript, donc
// sans cette liste une brique Godot non déterministe passait la garde sans être vue
// (amendement étape 0, spec 2026-07-21 §8b). Scanné APRÈS retrait des commentaires
// (`#` en GDScript) et des chaînes, comme pour le JS.
export const IMPURITY_GDSCRIPT = [
  [/\brand[if]\b/, "randi/randf (aleatoire non seede)"],
  [/\brandi_range\b/, "randi_range"],
  [/\brandf_range\b/, "randf_range"],
  [/\brandomize\b/, "randomize"],
  [/\brand_from_seed\b/, "rand_from_seed"],
  [/\bRandomNumberGenerator\b/, "RandomNumberGenerator"],
  [/\bOS\s*\./, "OS.* (environnement)"],
  [/\bTime\s*\./, "Time.* (non deterministe)"],
  [/\bFileAccess\b/, "FileAccess (I/O)"],
  [/\bDirAccess\b/, "DirAccess (I/O)"],
  [/\bHTTPRequest\b/, "HTTPRequest (reseau)"],
  [/\bHTTPClient\b/, "HTTPClient (reseau)"],
  [/\bEngine\s*\./, "Engine.* (etat moteur)"],
  [/\bInput\s*\./, "Input.* (etat externe)"],
];

// Retire commentaires `#` et littéraux de chaîne d'une source GDScript.
//
// Correctif de revue (Important, contre-vérifié) : l'ancienne version enchaînait des
// .replace() — commentaires RETIRÉS AVANT les chaînes. Un '#' à l'INTÉRIEUR d'une chaîne
// ("#%d" % randi(), idiomatique en GDScript) était donc pris pour un début de commentaire,
// effaçant tout le reste de la ligne — y compris du code impur réel (randi() invisible).
// Aucun ordre de .replace() ne peut résoudre ça : commentaires et chaînes s'imbriquent
// mutuellement (un '#' en chaîne n'est pas un commentaire ; un guillemet en commentaire
// n'ouvre pas une chaîne). Seul un balayage caractère par caractère en une seule passe,
// qui suit l'état courant du texte, tranche correctement les deux cas à la fois.
function stripGdscriptCommentsAndStrings(src) {
  let out = "";
  const n = src.length;
  let i = 0;
  while (i < n) {
    const c = src[i];
    // Chaîne triple-guillemets (multi-lignes) : le contenu est du texte, jamais du code —
    // neutralisé en bloc, mais les sauts de ligne internes sont préservés (pas de fusion
    // de lignes voisines).
    if (c === '"' && src[i + 1] === '"' && src[i + 2] === '"') {
      i += 3;
      while (i < n && !(src[i] === '"' && src[i + 1] === '"' && src[i + 2] === '"')) {
        if (src[i] === "\n") out += "\n";
        i++;
      }
      if (i < n) i += 3; // consomme le """ fermant (fin de fichier = triple-chaine non fermee tolerable)
      out += '""';
      continue;
    }
    // Commentaire `#` HORS chaîne : court jusqu'à la fin de ligne (le \n lui-même n'est
    // pas consommé ici, l'itération suivante le traite normalement — saut de ligne préservé).
    // Un guillemet dans ce commentaire n'ouvre PAS de chaîne : on saute les caractères bruts.
    if (c === "#") {
      while (i < n && src[i] !== "\n") i++;
      continue;
    }
    // Chaîne `"..."` ou `'...'` : le `#` à l'intérieur n'est PAS un commentaire (on avance
    // caractère par caractère sans jamais retester le cas '#'). Échappements \" et \'
    // gérés. Une chaîne non fermée avant fin de ligne est traitée en dégradé (borne à la
    // ligne courante) plutôt que d'avaler le reste du fichier.
    if (c === '"' || c === "'") {
      const quote = c;
      i++;
      while (i < n && src[i] !== quote && src[i] !== "\n") {
        i += src[i] === "\\" && i + 1 < n ? 2 : 1;
      }
      if (i < n && src[i] === quote) i++;
      out += quote === '"' ? '""' : "''";
      continue;
    }
    out += c;
    i++;
  }
  return out;
}

// R11 — patterns jamais injectés comme code (scanné sur le texte BRUT : chemins = littéraux).
const PATTERN_IMPORT = [
  /\bfrom\s*["'][^"']*patterns\//,
  /\bimport\s*\(\s*["'][^"']*patterns\//,
  /\brequire\s*\(\s*["'][^"']*patterns\//,
];

// Retire commentaires et littéraux de chaîne (réduit les faux positifs R10, red-team F5).
function stripCommentsAndStrings(src) {
  return src
    .replace(/\/\*[\s\S]*?\*\//g, " ")
    .replace(/\/\/[^\n]*/g, " ")
    .replace(/"(?:\\.|[^"\\])*"/g, '""')
    .replace(/'(?:\\.|[^'\\])*'/g, "''")
    .replace(/`(?:\\.|[^`\\])*`/g, "``");
}

// ---- helpers de typage ----
function isStr(v) { return typeof v === "string" && v.length > 0; }
function isStrArr(v) { return Array.isArray(v) && v.every((x) => typeof x === "string"); }
function isNonEmptyStrArr(v) { return isStrArr(v) && v.length > 0; }
function isPlainObj(v) { return v !== null && typeof v === "object" && !Array.isArray(v); }
// Forme partagée par `requires` (rôle) et `affordances` (brick) — Tier 1 #3 : un ROLE
// se lie à une pièce ssi affordances(piece) ⊇ requires(role) (pont vérifiable, pas un
// jugement — cf. knowledge_base/roles/SCHEMA.md §"Un ROLE se lie..."). Cette fonction ne
// fait QUE valider la FORME ; la comparaison affordances ⊇ requires reste hors scope ici
// (prochain incrément — le pont SEARCH↔ROLE).
function isCapabilityMap(v) {
  if (!isPlainObj(v)) return false;
  return Object.entries(v).every(
    ([, c]) => isPlainObj(c) && isStr(c.type) && isStr(c.description) && Object.keys(c).length === 2
  );
}
function isNonEmptyCapabilityMap(v) { return isCapabilityMap(v) && Object.keys(v).length > 0; }

// Provenance d'apprentissage (spec etape 0 §9) : de quel jeu du curriculum et de
// quelle reference commerciale la mecanique est issue. Schema ferme a 2 cles.
function isLearnedFrom(v) {
  return isPlainObj(v) && isStr(v.game) && isStr(v.reference) && Object.keys(v).length === 2;
}

// Champ FACULTATIF d'un schéma par ailleurs fermé (checkSpec ci-dessous) : la clé peut être
// ABSENTE (aucune erreur R1 "champ manquant") ; SI PRÉSENTE, elle est type-vérifiée normalement
// par `check`. Générique et réutilisable — n'affecte que les specs qui l'utilisent explicitement
// (ex. BRICK_SPEC::usage_examples) ; ASSET_SPEC::usage_examples reste un champ ordinaire
// (obligatoire, comme avant).
function optional(check) {
  const wrapped = (v) => v === undefined || check(v);
  wrapped.__optional = true;
  return wrapped;
}

// Tier 1 #4 — le pont SEARCH↔ROLE : « affordances(piece) ⊇ requires(role) » devient une
// comparaison réelle, pas une lecture de prose. Comparaison par NOM de capacité seulement
// (pas de vérification de signature/type — un futur incrément pourrait durcir ça) : un rôle
// est couvert par une pièce ssi chaque clé de `requires` existe aussi dans `affordances`.
export function missingCapabilities(requires, affordances) {
  const have = affordances || {};
  return Object.keys(requires || {}).filter((cap) => !(cap in have));
}

function sha256File(abs) {
  return createHash("sha256").update(readFileSync(abs)).digest("hex");
}

// Garde de chemin UNIFIÉE : tout chemin déclaré (path, proof, usage, tests) y passe.
// Retourne { abs } si OK, sinon { err: "raison" }. NE JETTE JAMAIS.
function guardedPath(root, p, { subdir, mustBeFile = true }) {
  if (typeof p !== "string" || p.length === 0) return { err: "chemin vide" };
  if (p.includes("\\")) return { err: "antislash interdit (chemins portables '/')" };
  if (isAbsolute(p)) return { err: "chemin absolu interdit" };
  if (p.split("/").includes("..")) return { err: "'..' interdit" };
  if (!p.startsWith("knowledge_base/")) return { err: "doit etre sous knowledge_base/" };
  if (subdir && !p.startsWith(subdir)) return { err: `doit etre sous ${subdir}` };
  const abs = resolve(root, p);
  let st;
  try { st = lstatSync(abs); }
  catch { return { err: `absent du disque: ${p}` }; }
  if (st.isSymbolicLink()) return { err: `lien symbolique interdit (confinement): ${p}` };
  if (mustBeFile && !st.isFile()) return { err: `n'est pas un fichier: ${p}` };
  // confinement realpath : la cible réelle doit rester sous knowledge_base/
  try {
    const realRoot = realpathSync(resolve(root, "knowledge_base"));
    const real = realpathSync(abs);
    if (real !== realRoot && !real.startsWith(realRoot + sep)) return { err: `sort de knowledge_base/ (realpath): ${p}` };
  } catch { return { err: `resolution realpath impossible: ${p}` }; }
  // casse exacte (portabilité CI sensible à la casse, red-team F4)
  try {
    const parent = dirname(abs);
    if (!readdirSync(parent).includes(basename(abs))) return { err: `casse du nom de fichier non exacte: ${p}` };
  } catch { /* parent illisible : déjà couvert par lstat plus haut */ }
  return { abs };
}

// v4 (2026-08-06, Asset Library V1) — taxonomie de bibliothèque. Enumération FERMÉE :
// une catégorie hors liste est un rejet, pas une étiquette libre (sans quoi la
// bibliothèque redevient un sac de fichiers non navigable).
const ASSET_CATEGORIES = [
  // RPG médiéval
  "character", "monster", "weapon", "armor", "building", "tree", "rock", "prop",
  // Cyberpunk
  "robot", "cyborg", "drone", "vehicle", "machine", "neon",
  // Générique gameplay
  "door", "chest", "button", "platform", "trap", "decoration",
  // Expérimental
  "creature", "animal", "absurd",
];
// Statut géométrique = verdict de scripts/forge/asset_geometry/oracle.py, recopié ici.
// "NOT_MEASURED" est explicite : un asset non mesuré ne se fait jamais passer pour valide.
const GEOMETRY_STATUS = ["OK", "BLOCKED", "FAIL", "NOT_MEASURED"];

const ASSET_SPEC = {
  asset_id: isStr, source: isStr, license: isStr,
  // null autorise UNIQUEMENT pour un asset declare ORIGINAL — la garde est portee par
  // R3 dans validateAsset, pas par ce type (qui ne sait rien de `source`).
  provenance_url: (v) => v === null || isStr(v),
  style: isStr,
  genre: isNonEmptyStrArr, biome: (v) => v === null || isStr(v),
  format: (v) => v === "2D" || v === "3D",
  size_kb: (v) => v === null || (typeof v === "number" && v > 0),
  sha256: (v) => v === null || (typeof v === "string" && HEX64.test(v)),
  runtime: (v) => v === "html" || v === "godot",
  ingested: (v) => typeof v === "boolean",
  path: (v) => v === null || isStr(v),
  usage_examples: isStrArr,
  tier: (v) => v === "candidate" || v === "validated",
  // --- v4, tous OPTIONNELS : les 19 entrées existantes restent valides sans les porter.
  category: optional((v) => ASSET_CATEGORIES.includes(v)),
  geometry_status: optional((v) => GEOMETRY_STATUS.includes(v)),
  geometry_manifest: optional((v) => v === null || isStr(v)),
  consumer: optional(isStrArr),
  variants: optional(isStrArr),
};
const BRICK_SPEC = {
  brick_id: isStr,
  kind: (v) => ["system", "pattern", "template"].includes(v),
  function: isStr, source: isStr,
  provenance_url: (v) => v === null || isStr(v),
  // v4 : provenance INTERNE (lecon Forge validee) — cle OPTIONNELLE pour que
  // les entrees historiques restent valides sans retouche (historique intact,
  // regle de ratification). Si presente : schema ferme isProvenanceInternal.
  provenance_internal: optional((v) => v === null || isProvenanceInternal(v)),
  license: isStr,
  runtime: (v) => ["agnostic", "html", "godot"].includes(v),
  dependencies: isStrArr, parameters: isPlainObj,
  genre_compatible: isNonEmptyStrArr, invariants: isNonEmptyStrArr,
  proof_of_use: (v) => v === null || isStr(v),
  tier: (v) => v === "candidate" || v === "validated",
  path: (v) => v === null || isStr(v),
  sha256: (v) => v === null || (typeof v === "string" && HEX64.test(v)),
  tests: (v) => v === null || isStr(v),
  advisory_only: (v) => typeof v === "boolean",
  // Tier 1 #3 : ce que la pièce EXPOSE réellement — {} pour une brique qui ne remplit
  // aucun rôle. Mandatoire (schéma fermé) : jamais absent, `{}` = décision explicite.
  affordances: isCapabilityMap,
  // R8 (Forge V2 §4-A, arbitrage Pierre) : miroir FACULTATIF d'ASSET_SPEC::usage_examples —
  // même forme (tableau de chaînes), mais optionnel (une brick pré-existante sans ce champ
  // reste valide ; proof_of_use ci-dessus reste SA preuve d'usage réelle, requise si validated).
  usage_examples: optional(isStrArr),
  // Provenance d'apprentissage (spec etape 0 §9) : de quel jeu du curriculum et de quelle
  // reference commerciale la mecanique est issue. Facultatif — les 9 briques existantes sans
  // ce champ restent valides. Schema ferme : exactement {game: string, reference: string}.
  learned_from: optional(isLearnedFrom),
};
// Un ROLE catalogué : métadonnées d'index + pont vers le catalogue (fulfilled_by,
// vérifié réellement — R13) et vers le contrat détaillé sur disque (path -> le YAML
// complet de knowledge_base/roles/, qui porte simulation_module/difficulty_target/etc,
// non dupliqués ici). `requires` est la contrepartie machine-lisible de affordances.
const ROLE_SPEC = {
  role_id: isStr,
  archetype: isStr,
  requires: isNonEmptyCapabilityMap,
  fulfilled_by: isStrArr,
  tier: (v) => v === "candidate" || v === "validated",
  license: isStr,
  path: (v) => v === null || isStr(v),
  proof_of_use: (v) => v === null || isStr(v),
};

export function validateCatalog(catalog, { root }) {
  const errors = [];
  const err = (id, rule, msg) => errors.push({ id, rule, msg });
  try {
    _validate(catalog, root, err);
  } catch (e) {
    // Aucune faille d'implémentation ne doit transformer un rejet en crash (red-team F1).
    err("<interne>", "R0", `erreur interne du validateur: ${String(e && e.message || e)}`);
  }
  return { ok: errors.length === 0, errors };
}

function _validate(catalog, root, err) {
  if (!isPlainObj(catalog) || catalog.catalog_version !== 1 || !Array.isArray(catalog.entries)) {
    err("<catalog>", "R1", "en-tete invalide (catalog_version doit etre 1, entries un tableau)");
    return;
  }
  const seen = new Map();
  for (const e of catalog.entries) {
    const id = e?.asset_id ?? e?.brick_id ?? e?.role_id ?? "<sans-id>";
    seen.set(id, (seen.get(id) ?? 0) + 1);
  }
  for (const [id, n] of seen) if (n > 1) err(id, "R1", `id duplique (${n} occurrences)`);

  const bricks = catalog.entries.filter((e) => e?.entry_type === "brick");
  const brickIds = new Set(bricks.map((e) => e.brick_id));
  const bricksById = new Map(bricks.map((e) => [e.brick_id, e]));
  for (const e of catalog.entries) {
    if (!isPlainObj(e) || !["asset", "brick", "role"].includes(e.entry_type)) {
      err("<entree>", "R1", "entry_type doit etre 'asset', 'brick' ou 'role'");
      continue;
    }
    if (e.entry_type === "asset") validateAsset(e, root, err);
    else if (e.entry_type === "brick") validateBrick(e, root, err, brickIds);
    else validateRole(e, root, err, brickIds, bricksById);
  }
  detectCycles(catalog.entries.filter((e) => e?.entry_type === "brick"), err);
}

// Schéma fermé (red-team F6) : chaque champ attendu bien typé + aucune clé inconnue.
function checkSpec(e, spec, id, err) {
  let ok = true;
  for (const [field, check] of Object.entries(spec)) {
    if (!(field in e)) {
      if (!check.__optional) { err(id, "R1", `champ manquant: ${field}`); ok = false; }
      continue;
    }
    if (!check(e[field])) { err(id, "R1", `champ mal type: ${field}`); ok = false; }
  }
  for (const k of Object.keys(e)) {
    if (k === "entry_type") continue;
    if (!(k in spec)) { err(id, "R1", `champ inconnu (schema ferme): ${k}`); ok = false; }
  }
  return ok;
}

// Vérif disque d'un fichier ingéré : garde de chemin + sha + (asset) magic bytes + size.
function checkIngestedFile(id, p, declaredSha, root, subdir, err) {
  const g = guardedPath(root, p, { subdir, mustBeFile: true });
  if (g.err) { err(id, "R7", `path: ${g.err}`); return null; }
  if (declaredSha === null) { err(id, "R7", "sha256 manquant pour un fichier ingere"); return g.abs; }
  const real = sha256File(g.abs);
  if (real !== declaredSha) err(id, "R7", `sha256 declare != reel (${declaredSha.slice(0, 12)}… vs ${real.slice(0, 12)}…)`);
  return g.abs;
}

function validateAsset(e, root, err) {
  const id = e.asset_id ?? "<asset-sans-id>";
  if (!checkSpec(e, ASSET_SPEC, id, err)) return;

  if (!id.startsWith(ID_PREFIX.asset)) err(id, "R1", `asset_id doit commencer par '${ID_PREFIX.asset}'`);
  if (!KNOWN_SPDX.includes(e.license)) err(id, "R2", `licence hors liste fermee SPDX: ${e.license}`);
  else if (!ASSET_LICENSES.includes(e.license)) err(id, "R4", `licence non autorisee pour un asset: ${e.license}`);
  // R3 v4 — un asset PRODUIT par le studio n'a pas d'URL de provenance externe. Meme
  // convention que le code original (cf. ORIGINAL_MARKER cote brick) : la provenance
  // est alors la declaration explicite d'originalite, pas un champ laisse vide.
  const assetOriginal = typeof e.source === "string" && e.source.startsWith(ORIGINAL_MARKER);
  if (assetOriginal) {
    if (e.provenance_url !== null) err(id, "R3", `asset declare ORIGINAL : provenance_url doit etre null (recu: ${e.provenance_url})`);
  } else if (!URL_RE.test(e.provenance_url)) {
    err(id, "R3", `asset sans provenance : exige provenance_url http(s) OU source commencant par "${ORIGINAL_MARKER}"`);
  }

  const is3D = e.runtime === "godot" || e.format === "3D";

  // R6 v4 (2026-08-06) — l'ingestion 3D cesse d'etre interdite, mais elle est
  // CONDITIONNEE A UNE PREUVE. Avant : « godot/3D = manifest-only » interdisait
  // structurellement toute bibliotheque 3D. Desserrer sans contrepartie aurait laisse
  // entrer n'importe quel .glb ; la contrepartie est le verdict de l'Asset Geometry
  // Oracle (docs/forge/ASSET_GEOMETRY_ORACLE_V1_DESIGN.md), recopie dans l'entree et
  // adosse a un manifeste de recensement. Un .glb present n'est JAMAIS une preuve.
  if (is3D && e.ingested === true) {
    if (e.geometry_status === undefined) {
      err(id, "R6", "3D ingere exige geometry_status (verdict de l'asset geometry oracle) — un .glb present n'est pas une preuve");
      return;
    }
    if (e.geometry_status !== "OK") {
      err(id, "R6", `3D ingere exige geometry_status="OK", declare: ${e.geometry_status}`);
      return;
    }
    if (!Array.isArray(e.consumer) || e.consumer.length === 0) {
      err(id, "R6", "3D ingere exige au moins un consumer — pas d'asset sans consommateur");
      return;
    }
    // Le manifeste de recensement n'est exige QUE si l'asset porte des variantes :
    // un prop propre a mesh unique n'a rien a expliquer, et l'exiger quand meme
    // rendrait BLOCKED a vie tout asset genere sain (meme raison que
    // `manifest_present` cote oracle — les deux regles doivent rester coherentes).
    const aDesVariantes = Array.isArray(e.variants) && e.variants.length > 0;
    if (aDesVariantes && !e.geometry_manifest) {
      err(id, "R6", "3D ingere AVEC variantes exige geometry_manifest (sidecar <asset>.glb.geometry.json) — une variante exclusive doit etre declaree");
      return;
    }
    if (e.geometry_manifest) {
      const gm = guardedPath(root, e.geometry_manifest, { subdir: SUBDIR.asset, mustBeFile: true });
      if (gm.err) err(id, "R6", `geometry_manifest: ${gm.err}`);
    }
  } else if (is3D && e.path !== null) {
    err(id, "R6", "godot/3D non ingere = manifest-only : path doit etre null");
    return;
  }

  if (e.ingested === true) {
    if (e.path === null) { err(id, "R7", "ingested=true exige un path"); return; }
    const abs = checkIngestedFile(id, e.path, e.sha256, root, SUBDIR.asset, err);
    if (abs) {
      let buf = null;
      try { buf = readFileSync(abs); } catch { /* déjà géré par la garde */ }
      if (buf) {
        if (is3D && !isGLB(buf)) err(id, "R6", "octets ne correspondent pas a un GLB (magic 'glTF') — 3D declare mais fichier autre");
        else if (!is3D && !isRaster(buf)) err(id, "R6", "octets ne correspondent pas a un raster 2D connu (PNG/JPEG/GIF/BMP/WEBP) — 3D declare 2D ?");
        if (e.size_kb === null) err(id, "R7", "size_kb manquant pour un asset ingere");
        else {
          const realKb = Math.max(1, Math.round(buf.length / 1024));
          const tol = Math.max(1, 0.1 * realKb);
          if (Math.abs(e.size_kb - realKb) > tol) err(id, "R7", `size_kb incoherent (declare ${e.size_kb}, reel ~${realKb})`);
        }
      }
    }
  } else {
    if (e.path !== null) err(id, "R7", "ingested=false exige path null (manifest-only)");
    if (e.sha256 !== null || e.size_kb !== null) err(id, "R7", "manifest-only : sha256 et size_kb doivent etre null");
  }

  if (e.tier === "validated") {
    if (e.usage_examples.length === 0) err(id, "R8", "tier validated exige usage_examples non vide");
    for (const u of e.usage_examples) {
      const g = guardedPath(root, u, { mustBeFile: true });
      if (g.err) err(id, "R8", `usage_example invalide: ${g.err}`);
    }
  }
}

function validateBrick(e, root, err, brickIds) {
  const id = e.brick_id ?? "<brick-sans-id>";
  if (!checkSpec(e, BRICK_SPEC, id, err)) return;

  const prefix = ID_PREFIX[e.kind];
  if (!id.startsWith(prefix)) err(id, "R1", `brick_id de kind '${e.kind}' doit commencer par '${prefix}'`);
  if (!KNOWN_SPDX.includes(e.license)) err(id, "R2", `licence hors liste fermee SPDX: ${e.license}`);

  const isCode = e.kind === "system" || e.kind === "template";
  if (isCode && !CODE_LICENSES.includes(e.license) && KNOWN_SPDX.includes(e.license)) {
    err(id, "R4", `licence interdite pour du CODE (${e.kind}): ${e.license} — GPL contamine un jeu distribue`);
  }
  if (e.kind === "pattern") {
    if (KNOWN_SPDX.includes(e.license) && !PATTERN_LICENSES.includes(e.license)) err(id, "R5", `licence non autorisee pour un pattern: ${e.license}`);
    if (e.advisory_only !== true) err(id, "R5", "un pattern est advisory_only: true (cite, jamais injecte)");
    // v4 ratifie : un pattern porte EXACTEMENT UNE provenance — externe
    // (provenance_url, connaissance importee) OU interne (provenance_internal,
    // lecon Forge validee par un humain). Jamais les deux, jamais aucune.
    const hasExterne = e.provenance_url !== null;
    const hasInterne = e.provenance_internal !== undefined && e.provenance_internal !== null;
    if (hasExterne && hasInterne) {
      err(id, "R3", "exactement une provenance : provenance_url ET provenance_internal presentes — jamais les deux");
    }
    if (!hasExterne && !hasInterne) {
      err(id, "R3", "exactement une provenance : provenance_url (citation externe) OU provenance_internal (lecon Forge validee)");
    }
    if (e.path !== null && !e.path.endsWith(".md")) err(id, "R5", "le path d'un pattern est une fiche .md, jamais un module de code");
  }
  if (e.provenance_url !== null && !URL_RE.test(e.provenance_url)) err(id, "R3", "provenance_url doit etre http(s)");

  // Provenance du CODE (red-team F11) : URL OU citation d'un pattern en dépendance.
  if (isCode) {
    const citesPattern = e.dependencies.some((d) => typeof d === "string" && d.startsWith("pat-"));
    const declaredOriginal = e.source.startsWith(ORIGINAL_MARKER);
    if (e.provenance_url === null && !citesPattern && !declaredOriginal) {
      err(id, "R3", `code sans provenance : exige provenance_url OU une dependance pat-* (reecriture propre citee) OU source commencant par "${ORIGINAL_MARKER}" (code original declare)`);
    }
  }

  // R6 — « manifest-only » s'applique aux ASSETS godot/3D (modèles non ingérés),
  // PAS au code GDScript, qui doit être prouvable comme n'importe quel autre code.
  // Amendement étape 0 (spec 2026-07-21 §8a) : un system/template Godot suit
  // exactement le même régime de preuve qu'un module non-godot — path + sha256
  // + tests. Aucune garde existante n'est desserrée : le cas asset reste traité
  // par validateAsset (R6, inchangé), et l'exigence de path ci-dessous devient
  // universelle pour le code au lieu d'exempter Godot.
  if (isCode && e.path === null) {
    err(id, "R7", `${e.kind} exige un path (module) — path null esquive purete/tests`);
  }

  // R7 — réalité disque du module/fiche
  let abs = null;
  if (e.path !== null) {
    const subdir = SUBDIR[e.kind];
    const g = guardedPath(root, e.path, { subdir, mustBeFile: true });
    if (g.err) err(id, "R7", `path: ${g.err}`);
    else {
      abs = g.abs;
      if (e.sha256 === null) err(id, "R7", "sha256 manquant pour un fichier a path non-null");
      else if (sha256File(abs) !== e.sha256) err(id, "R7", "sha256 declare != reel");
    }
  }

  // R8 — tier validated exige une VRAIE preuve confinée (red-team F1/F3)
  if (e.tier === "validated") {
    if (e.proof_of_use === null) err(id, "R8", "tier validated exige proof_of_use non-null");
    else {
      const g = guardedPath(root, e.proof_of_use, { subdir: SUBDIR.proof, mustBeFile: true });
      if (g.err) err(id, "R8", `proof_of_use invalide: ${g.err}`);
    }
  }

  // R9 — dépendances existantes
  for (const d of e.dependencies) {
    if (!brickIds.has(d)) err(id, "R9", `dependance inconnue: ${d}`);
  }

  // R10/R11/R4-contenu — inspection du contenu des modules code. Aiguillage par extension
  // (amendement étape 0, spec 2026-07-21 §8b) : les motifs JS n'ont aucun équivalent
  // lexical en GDScript, donc un fichier .gd suit sa PROPRE liste de motifs d'impureté ;
  // tout le reste (JS/.mjs) suit exactement les deux passes RAW/STRIPPED existantes,
  // inchangées. R11 (import patterns/) et le marqueur GPL restent appliqués aux DEUX
  // langages, sur le texte brut — hors de la branche par langage.
  if (isCode && abs !== null) {
    let raw = "";
    try { raw = readFileSync(abs, "utf-8"); } catch { /* déjà couvert */ }
    const isGd = e.path.endsWith(".gd");
    if (isGd) {
      const code = stripGdscriptCommentsAndStrings(raw);
      for (const [re, label] of IMPURITY_GDSCRIPT) {
        if (re.test(code)) err(id, "R10", `motif d'impurete GDScript: ${label}`);
      }
    } else {
      const code = stripCommentsAndStrings(raw);
      for (const [re, label] of IMPURITY_RAW) {
        if (re.test(raw)) err(id, "R10", `motif d'impurete: ${label}`);
      }
      for (const [re, label] of IMPURITY_STRIPPED) {
        if (re.test(code)) err(id, "R10", `motif d'impurete: ${label}`);
      }
    }
    for (const re of PATTERN_IMPORT) {
      if (re.test(raw)) { err(id, "R11", "import depuis patterns/ interdit (cites, jamais injectes)"); break; }
    }
    // Marqueur GPL dans du code déclaré permissif (red-team F8) — sur le texte BRUT.
    if (/GNU (Lesser |Affero )?General Public License/i.test(raw) || /SPDX-License-Identifier:\s*(?:LGPL|GPL|AGPL)/i.test(raw)) {
      err(id, "R4", "marqueur GPL/LGPL/AGPL dans un module declare permissif — contamination");
    }
  }

  // R12 — tests des systems (les systems sont des unités testées ; les templates = squelettes)
  if (e.kind === "system") {
    if (e.tests === null) err(id, "R12", "kind system exige un fichier de tests");
    else {
      const g = guardedPath(root, e.tests, { subdir: SUBDIR.system, mustBeFile: true });
      if (g.err) err(id, "R12", `tests: ${g.err}`);
    }
  }
}

// Tier 1 #3 : un rôle catalogué — index + pont VÉRIFIÉ vers le catalogue (R13). Ne
// vérifie PAS encore affordances(piece) ⊇ requires(role) : c'est le pont SEARCH↔ROLE,
// prochain incrément (Tier 1 #4). R13 vérifie seulement que le pont EXISTE réellement
// (fulfilled_by pointe une brique réelle du catalogue) — jusqu'ici non vérifié du tout.
function validateRole(e, root, err, brickIds, bricksById) {
  const id = e.role_id ?? "<role-sans-id>";
  if (!checkSpec(e, ROLE_SPEC, id, err)) return;

  if (!id.startsWith(ID_PREFIX.role)) err(id, "R1", `role_id doit commencer par '${ID_PREFIX.role}'`);
  if (!KNOWN_SPDX.includes(e.license)) err(id, "R2", `licence hors liste fermee SPDX: ${e.license}`);

  // R13 — le pont ROLE -> catalogue existe reellement (fulfilled_by n'est plus une
  // simple citation en prose : chaque brick_id cite doit exister dans le catalogue).
  // R14 — le pont est VRAI, pas juste déclaré : la brique référencée doit réellement
  // couvrir chaque capacité de `requires` (affordances ⊇ requires, comparaison par
  // nom de capacité — Tier 1 #4, cf. knowledge_base/roles/SCHEMA.md).
  for (const b of e.fulfilled_by) {
    if (!brickIds.has(b)) { err(id, "R13", `fulfilled_by reference une brique inconnue: ${b}`); continue; }
    const missing = missingCapabilities(e.requires, bricksById.get(b).affordances);
    if (missing.length > 0) {
      err(id, "R14", `${b} ne couvre pas les capacites requises: ${missing.join(", ")} `
        + `(affordances(${b}) doit contenir toutes les cles de requires(${id}))`);
    }
  }

  // R7 — réalité disque du contrat détaillé (le YAML complet vit sous roles/, non
  // dupliqué dans le catalogue : simulation_module/difficulty_target/etc y restent).
  if (e.path === null) {
    err(id, "R7", "path obligatoire pour un role (le contrat detaille sur disque)");
  } else {
    const g = guardedPath(root, e.path, { subdir: SUBDIR.role, mustBeFile: true });
    if (g.err) err(id, "R7", `path: ${g.err}`);
    else if (!e.path.endsWith(".yaml")) err(id, "R1", "le path d'un role est un fichier .yaml");
  }

  // R8 — tier validated exige une preuve confinee (meme garde que les bricks/assets).
  if (e.tier === "validated") {
    if (e.proof_of_use === null) err(id, "R8", "tier validated exige proof_of_use non-null");
    else {
      const g = guardedPath(root, e.proof_of_use, { subdir: SUBDIR.proof, mustBeFile: true });
      if (g.err) err(id, "R8", `proof_of_use invalide: ${g.err}`);
    }
  }
}

function detectCycles(bricks, err) {
  const deps = new Map(bricks.map((b) => [b.brick_id, (b.dependencies ?? []).filter((d) => typeof d === "string")]));
  const state = new Map();
  const visit = (id, trail) => {
    if (!deps.has(id)) return;
    const s = state.get(id) ?? 0;
    if (s === 1) { err(id, "R9", `cycle de dependances: ${[...trail, id].join(" -> ")}`); return; }
    if (s === 2) return;
    state.set(id, 1);
    for (const d of deps.get(id)) visit(d, [...trail, id]);
    state.set(id, 2);
  };
  for (const id of deps.keys()) visit(id, []);
}

export function loadCatalog(catalogPath) {
  try {
    return { catalog: JSON.parse(readFileSync(catalogPath, "utf-8")) };
  } catch (e) {
    return { error: String(e) };
  }
}

// ---- CLI ----
const isMain = process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isMain) {
  try {
    const catalogPath = resolve(process.argv[2] ?? resolve(dirname(fileURLToPath(import.meta.url)), "catalog.json"));
    const root = resolve(dirname(catalogPath), "..");
    const { catalog, error } = loadCatalog(catalogPath);
    if (error) {
      console.error(`ILLISIBLE: ${catalogPath}\n${error}`);
      process.exit(2);
    }
    const { ok, errors } = validateCatalog(catalog, { root });
    if (!ok) {
      for (const e of errors) console.error(`REJECT ${e.id} [${e.rule}] ${e.msg}`);
      console.error(`\nVERDICT CATALOGUE: FAIL (${errors.length} violation(s), ${catalog.entries?.length ?? 0} entree(s))`);
      process.exit(1);
    }
    console.log(`VERDICT CATALOGUE: PASS (${catalog.entries.length} entree(s) conformes, 0 violation)`);
    process.exit(0);
  } catch (e) {
    console.error(`ERREUR INTERNE: ${String(e && e.stack || e)}`);
    process.exit(2);
  }
}

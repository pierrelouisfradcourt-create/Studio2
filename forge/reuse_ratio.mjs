#!/usr/bin/env node
// reuse_ratio.mjs — mesure la RÉUTILISATION d'un jeu forgé (docs/forge/STUDIO_AGENT_ATLAS.md
// §2.4 : « s9 Builder MODIFIÉ — consulte SEARCH d'abord ... reuse-ratio.mjs mesuré »).
// Déterministe, non-LLM, zéro réseau. Ne juge rien — compte des imports.
//
// Périmètre déclaré (choix de conception) : seuls les fichiers de LOGIQUE PRODUIT sont
// scannés (game/level/render/input — les modules que WFL-01/WFL-02 ont établis comme la
// convention de ce studio pour un jeu HTML). Les fichiers de harnais (main.mjs, server.mjs,
// e2e.mjs, run-oracle.mjs, solvability.mjs) et les tests (*.test.mjs) sont EXCLUS : la
// question posée est « combien du LOGICIEL DU JEU vient de la bibliothèque », pas combien
// l'infrastructure de preuve importe.
//
// Usage : node reuse_ratio.mjs <GAMES/nom-du-jeu/>
// Sortie : reçu JSON sur stdout + résumé lisible sur stderr. Exit 0 toujours (mesure, pas
// un oracle pass/fail — reuse_ratio bas n'est pas une erreur, c'est un FAIT à rapporter).
//
// Correction 2026-07-23 (boucle bibliothèque, chantier `studio_link.py`/`pending_review.mjs`/
// `reuse_ratio.mjs`) : deux défauts mesurés rendaient ce script à variance nulle en pratique
// (0.000 sur 9/9 jeux, y compris shmup_slice qui réutilise RÉELLEMENT une brique) —
//   (a) `readdirSync` n'était PAS récursif : un fichier de logique en sous-dossier (ex.
//       `GAMES/shmup_slice/logic/collisions.mjs`, ou tout jeu STANDARD dont la logique vit
//       sous `05_SYSTEMS/...`) n'était jamais vu ;
//   (b) `isLogicFile` n'acceptait que `.mjs` : tout jeu Godot (`.gd`) était rejeté d'office.
// Fixé ici : parcours récursif du dossier de jeu (l'exclusion harnais/tests reste appliquée
// par NOM DE FICHIER, pas par profondeur) + extension `.gd` acceptée en plus de `.mjs`.
import { readFileSync, readdirSync } from 'node:fs';
import { join, extname, relative, sep, dirname, resolve, basename, isAbsolute } from 'node:path';
import { pathToFileURL } from 'node:url';

const HARNESS_FILES = new Set(['main.mjs', 'server.mjs', 'e2e.mjs', 'run-oracle.mjs', 'solvability.mjs']);
const LOGIC_EXTENSIONS = new Set(['.mjs', '.gd']);
// Dossiers jamais descendus pendant le scan récursif — pas de logique produit à y trouver,
// seulement du bruit (dépendances, VCS) qui ralentirait/polluerait le parcours.
const SKIP_DIRS = new Set(['node_modules', '.git']);

/**
 * Un fichier compte-t-il comme « logique produit » pour cette mesure ?
 * @param {string} fileName nom de fichier SEUL (pas le chemin) — l'exclusion harnais/tests
 *   est par nom, indépendante du sous-dossier où le fichier vit.
 * @returns {boolean}
 */
function isLogicFile(fileName) {
  if (!LOGIC_EXTENSIONS.has(extname(fileName))) return false;
  if (fileName.endsWith('.test.mjs')) return false;
  if (HARNESS_FILES.has(fileName)) return false;
  return true;
}

/**
 * Parcourt récursivement `gameDir` et renvoie les chemins (relatifs à `gameDir`, séparateur
 * `/` normalisé quel que soit l'OS) des fichiers de logique produit trouvés, en profondeur
 * quelconque. Tri alphabétique déterministe.
 * @param {string} gameDir
 * @returns {string[]}
 */
function collectLogicFiles(gameDir) {
  const out = [];
  const walk = (dir) => {
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
      if (entry.isDirectory()) {
        if (SKIP_DIRS.has(entry.name)) continue;
        walk(join(dir, entry.name));
        continue;
      }
      if (entry.isFile() && isLogicFile(entry.name)) {
        out.push(relative(gameDir, join(dir, entry.name)).split(sep).join('/'));
      }
    }
  };
  walk(gameDir);
  return out.sort();
}

/**
 * Extrait les specifiers d'import ES d'un fichier source (texte brut — pas d'AST, même
 * limite déclarée que kb-validate.mjs R10 : suffisant pour ce besoin, pas un compilateur).
 * @param {string} source
 * @returns {string[]}
 */
function extractImportSpecifiers(source) {
  const specs = [];
  const re = /\bfrom\s+["']([^"']+)["']/g;
  let m;
  while ((m = re.exec(source)) !== null) specs.push(m[1]);
  return specs;
}

// --- Extension GDScript preload/load (2026-07-28) --------------------------------
// Correctif mesuré : extractImportSpecifiers ne matche que `from "..."` (imports ES) —
// jamais `preload("...")`/`load("...")` GDScript, alors que `.gd` est dans
// LOGIC_EXTENSIONS. Résultat en pratique : reuse_ratio = 0 par construction sur tout
// jeu Godot, y compris GAMES/grid_nav_probe qui contient 3 preload() réels. Patron
// aligné sur `_GD_LOAD` de forge/static_oracles.py (même regex, même intention).

/**
 * Extrait les specifiers `preload("...")` / `load("...")` d'un fichier GDScript (texte
 * brut, même limite que extractImportSpecifiers). Patron identique à `_GD_LOAD` de
 * forge/static_oracles.py.
 * @param {string} source
 * @returns {string[]}
 */
function extractGdLoadSpecifiers(source) {
  const specs = [];
  const re = /(?:preload|load)\(\s*["']([^"']+)["']/g;
  let m;
  while ((m = re.exec(source)) !== null) specs.push(m[1]);
  return specs;
}

/**
 * Trouve la racine du projet Godot du jeu analysé : le dossier contenant `project.godot`
 * sous `gameDir` (recherche récursive, le premier trouvé — un jeu forgé n'a qu'un seul
 * `project.godot`). Fallback = `gameDir` lui-même si aucun `project.godot` n'existe (jeu
 * non-Godot ou fixture de test minimale). C'est la racine depuis laquelle `res://` se
 * résout mécaniquement (convention Godot : res:// == racine du projet).
 * @param {string} gameDir
 * @returns {string} chemin absolu
 */
function findGodotProjectRoot(gameDir) {
  const gameDirAbs = resolve(gameDir);
  let found = null;
  const walk = (dir) => {
    if (found) return;
    let entries;
    try {
      entries = readdirSync(dir, { withFileTypes: true });
    } catch {
      return;
    }
    for (const entry of entries) {
      if (entry.isFile() && entry.name === 'project.godot') {
        found = dir;
        return;
      }
    }
    for (const entry of entries) {
      if (found) return;
      if (entry.isDirectory() && !SKIP_DIRS.has(entry.name)) walk(join(dir, entry.name));
    }
  };
  walk(gameDirAbs);
  return found || gameDirAbs;
}

/**
 * Classe un specifier `preload`/`load` GDScript EN CONTEXTE, résolution mécanique
 * (jamais une regex sur le texte du chemin) :
 *   - `res://<chemin>` se résout depuis `godotRoot` (racine du projet Godot détectée par
 *     `findGodotProjectRoot`) — convention Godot, pas depuis `gameDir` si celui-ci diffère.
 *   - un chemin relatif (`./...`/`../...`) se résout depuis le dossier du fichier
 *     importeur, comme pour un import JS.
 *   - tout le reste (specifier nu, forme non reconnue) n'est PAS résoluble
 *     mécaniquement ⇒ 'external', resolved:null (jamais un crash, jamais un faux 'reuse').
 * Une fois résolu : dans knowledge_base/ → 'knowledge_base' ; dans GAMES/<autre>/ (jeu
 * différent) → 'cross_game' ; sinon dans gameDir → 'local' ; sinon (résolu mais hors de
 * toute catégorie reconnue) → 'local', même philosophie défensive que
 * classifyImportInContext.
 * @param {string} gameDir dossier du jeu analysé
 * @param {string} godotRoot racine du projet Godot (résultat de findGodotProjectRoot)
 * @param {string} file chemin du fichier importeur, relatif à gameDir
 * @param {string} specifier specifier brut trouvé dans preload()/load()
 * @returns {{classification:'knowledge_base'|'local'|'external'|'cross_game', resolved:string|null}}
 */
function classifyGdSpecifierInContext(gameDir, godotRoot, file, specifier) {
  const gameDirAbs = resolve(gameDir);

  let resolved;
  if (specifier.startsWith('res://')) {
    resolved = resolve(godotRoot, specifier.slice('res://'.length));
  } else if (specifier.startsWith('./') || specifier.startsWith('../')) {
    const fileDirAbs = dirname(resolve(gameDir, file));
    resolved = resolve(fileDirAbs, specifier);
  } else {
    // Ni res://, ni chemin relatif reconnu (specifier nu, user://, etc.) : pas de
    // résolution mécanique possible sans deviner — external, jamais un faux reuse.
    return { classification: 'external', resolved: null };
  }

  const segments = resolved.split(sep);

  if (segments.includes('knowledge_base')) {
    return { classification: 'knowledge_base', resolved };
  }

  if (resolved === gameDirAbs || resolved.startsWith(gameDirAbs + sep)) {
    return { classification: 'local', resolved };
  }

  const gamesIdx = segments.lastIndexOf('games');
  if (gamesIdx !== -1 && gamesIdx + 1 < segments.length) {
    const otherGameName = segments[gamesIdx + 1];
    const thisGameName = basename(gameDirAbs);
    if (otherGameName && otherGameName !== thisGameName) {
      return { classification: 'cross_game', resolved };
    }
  }

  return { classification: 'local', resolved };
}

/**
 * Classe un specifier d'import : 'knowledge_base' (réutilisation prouvée) ou 'local'
 * (module écrit pour ce jeu — inclut les imports relatifs vers un AUTRE fichier du même
 * dossier de jeu) ou 'external' (ni l'un ni l'autre — ex. un module npm, non compté).
 * @param {string} specifier
 * @returns {'knowledge_base'|'local'|'external'}
 */
function classifySpecifier(specifier) {
  if (specifier.includes('knowledge_base/')) return 'knowledge_base';
  if (specifier.startsWith('./') || specifier.startsWith('../')) return 'local';
  return 'external';
}

// --- Extension cross_game (2026-07-28) --------------------------------------------
// Mesure demandée séparément : « ce qui est importé depuis un AUTRE jeu déjà forgé »
// (condition Pierre du cycle Snake). N'existait pas : classifySpecifier ne voit QUE le
// texte du specifier, jamais où il pointe une fois résolu — un import relatif est
// TOUJOURS 'local' avec ce texte seul, même s'il traverse en réalité vers GAMES/autre/.
// Résolution MÉCANIQUE (path.resolve depuis le fichier importeur), pas une regex sur le
// texte brut — condition explicite de la commande de fabrication.
//
// Périmètre de résolution : seuls les specifiers path-like (relatifs './'/'../' ou
// absolus, y compris chemin Windows) sont résolus. Un specifier nu ('chalk', 'node:fs')
// n'est PAS un chemin de fichier réel du disque — il reste 'external', inchangé.

/**
 * Un specifier ressemble-t-il à un chemin de fichier résolvable (par opposition à un
 * specifier de module « nu », ex. un paquet npm ou un import 'node:...') ?
 * @param {string} specifier
 * @returns {boolean}
 */
function isPathLikeSpecifier(specifier) {
  return specifier.startsWith('./') || specifier.startsWith('../') || isAbsolute(specifier);
}

/**
 * Classe un import EN CONTEXTE (fichier + dossier de jeu analysé) : ajoute la catégorie
 * 'cross_game' à classifySpecifier — un specifier path-like qui, une fois résolu depuis
 * le fichier importeur, pointe dans l'arbre `GAMES/<autre-jeu>/` d'un jeu DIFFÉRENT de
 * celui qu'on analyse. knowledge_base garde la priorité (inchangé) ; un import path-like
 * qui reste À L'INTÉRIEUR du dossier du jeu analysé reste 'local' (inchangé) ; un
 * specifier nu reste 'external' (inchangé).
 * @param {string} gameDir dossier du jeu analysé (racine du scan)
 * @param {string} file chemin du fichier importeur, relatif à gameDir (comme dans entries)
 * @param {string} specifier specifier d'import brut trouvé dans le fichier
 * @returns {{classification:'knowledge_base'|'local'|'external'|'cross_game', resolved:string|null}}
 */
function classifyImportInContext(gameDir, file, specifier) {
  const base = classifySpecifier(specifier);
  if (base !== 'local') {
    // knowledge_base et external ne dépendent pas de la résolution disque.
    return { classification: base, resolved: null };
  }
  if (!isPathLikeSpecifier(specifier)) {
    // Défensif : classifySpecifier ne renvoie 'local' que pour du path-like aujourd'hui,
    // mais on ne veut pas résoudre un specifier qui n'en serait pas un.
    return { classification: 'local', resolved: null };
  }

  const gameDirAbs = resolve(gameDir);
  const fileDirAbs = dirname(resolve(gameDir, file));
  const resolved = resolve(fileDirAbs, specifier);

  if (resolved === gameDirAbs || resolved.startsWith(gameDirAbs + sep)) {
    return { classification: 'local', resolved };
  }

  // Résolu HORS du dossier du jeu analysé : cross_game seulement si ça pointe dans
  // l'arbre GAMES/<autre-jeu>/ d'un jeu DIFFÉRENT (pas n'importe quel chemin externe).
  const segments = resolved.split(sep);
  const gamesIdx = segments.lastIndexOf('games');
  if (gamesIdx !== -1 && gamesIdx + 1 < segments.length) {
    const otherGameName = segments[gamesIdx + 1];
    const thisGameName = basename(gameDirAbs);
    if (otherGameName && otherGameName !== thisGameName) {
      return { classification: 'cross_game', resolved };
    }
  }

  // Résolu hors du jeu mais hors de tout autre GAMES/<x>/ reconnaissable (ex. sort du
  // repo, ou dans knowledge_base sans le mot dans le specifier) : reste 'local' — ce
  // script ne juge pas cette forme, il ne classe que ce que la commande de fabrication
  // demande explicitement (reuse existant + cross_game nouveau).
  return { classification: 'local', resolved };
}

/**
 * Mesure le taux de réutilisation d'un répertoire de jeu.
 *
 * Deux mesures INDÉPENDANTES et coexistantes (chaque nom de preuve = exactement ce
 * qu'il mesure, pas plus) :
 *   - reuseRatio        : réutilisation depuis knowledge_base/ (INCHANGÉ — même formule,
 *                         même champs `reusedModules`/`imports[].classification` qu'avant
 *                         l'extension 2026-07-28).
 *   - crossGameReuse    : réutilisation depuis l'arbre d'un AUTRE jeu (GAMES/<autre>/**),
 *                         résolution mécanique (path.resolve), NOUVEAU.
 * @param {string} gameDir chemin (absolu ou relatif au cwd) du dossier du jeu
 * @returns {{gameDir:string, logicFiles:string[], reusedModules:string[], reuseRatio:number,
 *   crossGameModules:string[], crossGameReuse:number,
 *   imports:Array<{file:string, specifier:string, classification:string, resolved:string|null}>}}
 */
export function measureReuseRatio(gameDir) {
  const entries = collectLogicFiles(gameDir);
  const godotRoot = findGodotProjectRoot(gameDir);

  const imports = [];
  const reusedModules = new Set();
  const crossGameModules = new Set();

  for (const file of entries) {
    const source = readFileSync(join(gameDir, file), 'utf-8');
    const isGd = extname(file) === '.gd';
    const specifiers = isGd ? extractGdLoadSpecifiers(source) : extractImportSpecifiers(source);
    for (const specifier of specifiers) {
      const { classification, resolved } = isGd
        ? classifyGdSpecifierInContext(gameDir, godotRoot, file, specifier)
        : classifyImportInContext(gameDir, file, specifier);
      imports.push({ file, specifier, classification, resolved });
      if (classification === 'knowledge_base') reusedModules.add(specifier);
      if (classification === 'cross_game') crossGameModules.add(resolved);
    }
  }

  const logicFileCount = entries.length;
  const reusedModuleCount = reusedModules.size;
  // Dénominateur : fichiers de logique écrits POUR ce jeu + modules importés de la
  // bibliothèque — reflète « sur combien de briques ce jeu s'appuie au total, combien
  // viennent d'ailleurs ». Ratio 0 si aucune brique (jeu tout neuf, rien à réutiliser).
  const denominator = logicFileCount + reusedModuleCount;
  const reuseRatio = denominator === 0 ? 0 : reusedModuleCount / denominator;

  // cross_game_reuse : même forme de formule (imports cross_game distincts / total),
  // mais dénominateur propre à SA question — « sur tous les imports résolus de ce jeu
  // (fichiers de logique + imports cross_game distincts), combien viennent d'un AUTRE
  // jeu déjà forgé ». Catégorie séparée, jamais mélangée à reuseRatio (knowledge_base).
  const crossGameModuleCount = crossGameModules.size;
  const crossGameDenominator = logicFileCount + crossGameModuleCount;
  const crossGameReuse = crossGameDenominator === 0 ? 0 : crossGameModuleCount / crossGameDenominator;

  return {
    gameDir,
    logicFiles: entries.sort(),
    reusedModules: [...reusedModules].sort(),
    reuseRatio,
    crossGameModules: [...crossGameModules].sort(),
    crossGameReuse,
    imports,
  };
}

function main() {
  const gameDir = process.argv[2];
  if (!gameDir) {
    console.error('Usage: node reuse_ratio.mjs <GAMES/nom-du-jeu/>');
    process.exit(2);
  }

  const result = measureReuseRatio(gameDir);

  console.error(`=== REUSE RATIO — ${gameDir} ===\n`);
  console.error(`Fichiers de logique produit scannés (${result.logicFiles.length}) : ${result.logicFiles.join(', ')}`);
  console.error(`Modules bibliothèque réutilisés (${result.reusedModules.length}) :`);
  for (const m of result.reusedModules) console.error(`  - ${m}`);
  console.error(`\nreuse_ratio = ${result.reusedModules.length} / (${result.logicFiles.length} + ${result.reusedModules.length}) = ${result.reuseRatio.toFixed(3)}`);

  console.error(`\nModules d'un AUTRE jeu réutilisés (${result.crossGameModules.length}) :`);
  for (const m of result.crossGameModules) console.error(`  - ${m}`);
  console.error(`\ncross_game_reuse = ${result.crossGameModules.length} / (${result.logicFiles.length} + ${result.crossGameModules.length}) = ${result.crossGameReuse.toFixed(3)}`);

  console.log(JSON.stringify(result, null, 2));
  process.exit(0);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main();
}

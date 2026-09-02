#!/usr/bin/env node
// check_blueprint_contract.mjs — oracle d'AVANT-BUILD de l'étape s4-archi.
//
// ┌──────────────────────────────────────────────────────────────────────────────┐
// │ DEUX QUESTIONS DIFFÉRENTES, DEUX ORACLES (arbitrage Pierre, 2026-08-04)      │
// │  AVANT build : « l'architecture proposée répond-elle au besoin ? »  <- ICI   │
// │  APRÈS build : « le code respecte-t-il l'architecture ? »                    │
// │                -> forge.static_oracles.check_architecture, INTOUCHÉ.         │
// └──────────────────────────────────────────────────────────────────────────────┘
//
// `check_architecture` compare `deps_interdites` aux imports RÉELS du code. Appelé
// en amont, sur un `src_root` vide, il ne trouve aucun import : 0 violation, vert
// vacant. Ce n'est pas un bug de cet oracle — c'est le mauvais moment. Le blueprint
// de 82 octets qui passait 34 runs sur 34 échoue ici, parce qu'ici on lui demande
// ce qu'il COUVRE, pas ce que le code respecte.
//
// CE QU'IL VALIDE (spec Pierre) : présence minimale de modules · responsabilités ·
// couverture de la featuremap · dépendances (+ consommateurs DÉRIVÉS des
// dépendances, jamais saisis deux fois) · preuves associées.
//
// CHAMP ADDITIF `responsabilites[]` — `modules` reste une liste de chaînes, exactement
// comme aujourd'hui : forge.static_oracles.check_architecture fait `set(blueprint["modules"])`
// et exploserait sur une liste d'objets (dict non hashable). L'enrichissement passe
// donc par un champ SÉPARÉ, jamais par une mutation de la forme existante.
//
// Usage :
//   node check_blueprint_contract.mjs <blueprint.json> --featuremap <featuremap.json> [--json]
// Exit 0 = OK · 1 = FAIL · 2 = usage.
import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  isNonEmptyString,
  validateExpectedProof,
  featureIds,
  duplicateIds,
} from './upstream_schema.mjs';

const EMPTY_STATS = {
  modules: 0, responsabilites: 0, features: 0, features_couvertes: 0,
  deps_interdites: 0, aretes_dependance: 0,
};

/**
 * Détecte les cycles d'un graphe orienté module -> dépendances, par parcours en
 * profondeur avec pile d'exploration. Retourne les cycles trouvés (chemins), pas
 * un simple booléen : « il y a un cycle » n'est pas actionnable, « game_loop ->
 * render -> game_loop » l'est.
 * @param {Map<string,string[]>} graph
 * @returns {string[][]}
 */
export function detecterCycles(graph) {
  const EN_COURS = 1;
  const FINI = 2;
  const etat = new Map();
  const cycles = [];
  const pile = [];

  const visiter = (n) => {
    etat.set(n, EN_COURS);
    pile.push(n);
    for (const voisin of graph.get(n) || []) {
      if (!graph.has(voisin)) continue; // cible inconnue : remontée ailleurs
      if (etat.get(voisin) === EN_COURS) {
        const debut = pile.indexOf(voisin);
        cycles.push([...pile.slice(debut), voisin]);
      } else if (etat.get(voisin) !== FINI) {
        visiter(voisin);
      }
    }
    pile.pop();
    etat.set(n, FINI);
  };

  for (const n of graph.keys()) if (!etat.has(n)) visiter(n);
  return cycles;
}

/**
 * Dérive les consommateurs (arêtes inverses) du graphe de dépendances. Reporté
 * pour la lecture humaine — jamais un champ à saisir : une donnée saisie deux fois
 * finit par diverger.
 * @param {Map<string,string[]>} graph
 * @returns {Record<string,string[]>}
 */
export function consommateursDerives(graph) {
  const out = {};
  for (const m of graph.keys()) out[m] = [];
  for (const [m, deps] of graph.entries()) {
    for (const d of deps) {
      if (!(d in out)) out[d] = [];
      out[d].push(m);
    }
  }
  return out;
}

/**
 * Oracle complet sur un blueprint déjà parsé, confronté à la featuremap qu'il doit
 * couvrir.
 * @param {unknown} doc blueprint.json
 * @param {unknown} featuremap featuremap.json
 * @returns {object}
 */
export function checkBlueprintDoc(doc, featuremap) {
  const problems = [];
  const features_non_couvertes = [];
  const couverture_fantome = [];

  if (doc === null || typeof doc !== 'object' || Array.isArray(doc)) {
    return {
      ok: false, verdict: 'FAIL',
      problems: ['blueprint.json: doit etre un objet'],
      features_non_couvertes, couverture_fantome, consommateurs: {}, stats: EMPTY_STATS,
    };
  }

  // --- modules (forme historique, inchangée) ---
  const modules = Array.isArray(doc.modules) ? doc.modules : null;
  if (modules === null || modules.length === 0 || !modules.every((m) => isNonEmptyString(m))) {
    problems.push("blueprint.json.modules: liste NON VIDE de chaines requise (forme consommee telle quelle par check_architecture)");
  }
  const moduleSet = new Set((modules || []).filter(isNonEmptyString));
  problems.push(...duplicateIds([...(modules || [])].filter(isNonEmptyString), 'blueprint.json.modules'));

  // --- deps_interdites (règle anti-vacuité déjà posée côté matérialisation) ---
  const depsInterdites = Array.isArray(doc.deps_interdites) ? doc.deps_interdites : [];
  if (depsInterdites.length === 0) {
    problems.push('blueprint.json.deps_interdites: obligatoire et NON VIDE — sans paire interdite, check_architecture est vacuement vert apres build');
  }
  const paires = [];
  depsInterdites.forEach((p, i) => {
    if (!Array.isArray(p) || p.length !== 2 || !p.every((x) => isNonEmptyString(x))) {
      problems.push(`blueprint.json.deps_interdites[${i}]: paire [source, cible] de chaines non vides attendue`);
      return;
    }
    paires.push([p[0], p[1]]);
    if (moduleSet.size > 0) {
      if (!moduleSet.has(p[0])) problems.push(`blueprint.json.deps_interdites[${i}][0]: module inconnu '${p[0]}'`);
      if (!moduleSet.has(p[1])) problems.push(`blueprint.json.deps_interdites[${i}][1]: module inconnu '${p[1]}'`);
    }
  });

  // --- responsabilites[] : le contenu qui manquait ---
  const resp = Array.isArray(doc.responsabilites) ? doc.responsabilites : null;
  if (resp === null || resp.length === 0) {
    problems.push(
      "blueprint.json.responsabilites: tableau NON VIDE requis — "
      + '{module, responsabilite, couvre[], dependances[], preuve_attendue{kind,statement}}. '
      + "Sans lui, un blueprint de 2 modules inventes ne se distingue pas d'une architecture reelle",
    );
  }

  const graph = new Map();
  const couverts = new Set();
  const declares = new Set();
  const fmFeatures = new Set(featureIds(featuremap));

  (resp || []).forEach((r, i) => {
    const loc = `responsabilites[${i}]`;
    if (r === null || typeof r !== 'object' || Array.isArray(r)) {
      problems.push(`${loc}: doit etre un objet`);
      return;
    }
    if (!isNonEmptyString(r.module)) {
      problems.push(`${loc}.module: absent ou vide`);
    } else {
      if (moduleSet.size > 0 && !moduleSet.has(r.module)) {
        problems.push(`${loc}.module: '${r.module}' absent de blueprint.modules (responsabilite orpheline)`);
      }
      declares.add(r.module);
      graph.set(r.module, []);
    }
    if (!isNonEmptyString(r.responsabilite)) {
      problems.push(`${loc}.responsabilite: absente ou vide (un module sans responsabilite declaree ne se distingue d'aucun autre)`);
    }
    if (!Array.isArray(r.couvre) || r.couvre.length === 0) {
      problems.push(`${loc}.couvre: tableau NON VIDE d'ids de features requis (un module qui ne couvre rien ne repond a aucun besoin)`);
    } else {
      for (const f of r.couvre) {
        if (!isNonEmptyString(f)) {
          problems.push(`${loc}.couvre: entree vide`);
        } else if (!fmFeatures.has(f)) {
          couverture_fantome.push(`${loc}.couvre: '${f}' ne resout aucune feature de la featuremap`);
        } else {
          couverts.add(f);
        }
      }
    }
    if (!Array.isArray(r.dependances)) {
      problems.push(`${loc}.dependances: tableau requis (vide autorise = module feuille, mais JAMAIS absent)`);
    } else {
      for (const d of r.dependances) {
        if (!isNonEmptyString(d)) {
          problems.push(`${loc}.dependances: entree vide`);
        } else if (moduleSet.size > 0 && !moduleSet.has(d)) {
          problems.push(`${loc}.dependances: module inconnu '${d}'`);
        } else if (isNonEmptyString(r.module)) {
          graph.get(r.module).push(d);
        }
      }
    }
    problems.push(...validateExpectedProof(r.preuve_attendue, loc, 'preuve_attendue'));
  });

  // Un module declaré sans responsabilité = trou de couverture.
  for (const m of moduleSet) {
    if (!declares.has(m)) problems.push(`blueprint.json.modules: '${m}' n'a aucune entree dans responsabilites[]`);
  }

  // Toute feature de la featuremap doit être couverte par >=1 module.
  for (const f of fmFeatures) {
    if (!couverts.has(f)) {
      features_non_couvertes.push(`feature '${f}' de la featuremap n'est couverte par aucun module (l'architecture ne repond pas au besoin)`);
    }
  }
  if (fmFeatures.size === 0) {
    problems.push('featuremap: aucune feature identifiee — la couverture ne peut pas etre verifiee (ni sautee en silence)');
  }

  // Contradiction interne : une dépendance à la fois déclarée et interdite.
  for (const [src, cibles] of graph.entries()) {
    for (const cible of cibles) {
      if (paires.some(([a, b]) => a === src && b === cible)) {
        problems.push(`blueprint.json: '${src}' declare dependre de '${cible}' alors que la paire est dans deps_interdites (blueprint auto-contradictoire)`);
      }
    }
  }

  const cycles = detecterCycles(graph);
  for (const c of cycles) {
    problems.push(`blueprint.json: cycle de dependances ${c.join(' -> ')}`);
  }

  const stats = {
    modules: moduleSet.size,
    responsabilites: (resp || []).length,
    features: fmFeatures.size,
    features_couvertes: couverts.size,
    deps_interdites: paires.length,
    aretes_dependance: [...graph.values()].reduce((a, v) => a + v.length, 0),
  };

  const all = [...problems, ...features_non_couvertes, ...couverture_fantome];
  const ok = all.length === 0;
  return {
    ok, verdict: ok ? 'OK' : 'FAIL',
    problems, features_non_couvertes, couverture_fantome,
    consommateurs: consommateursDerives(graph), stats,
  };
}

/**
 * Lit blueprint + featuremap sur disque et applique l'oracle. Ne lève jamais.
 * @param {string} blueprintPath
 * @param {string} featuremapPath
 * @returns {Promise<object>}
 */
export async function checkBlueprintFiles(blueprintPath, featuremapPath) {
  const fail = (msg) => ({
    ok: false, verdict: 'FAIL', problems: [msg],
    features_non_couvertes: [], couverture_fantome: [], consommateurs: {}, stats: EMPTY_STATS,
  });
  const load = async (p, label) => {
    let raw;
    try {
      raw = await readFile(p, 'utf-8');
    } catch (err) {
      return { err: `${label} ${p}: absent ou illisible (${err.message})` };
    }
    if (raw.trim().length === 0) return { err: `${label} ${p}: present mais vide` };
    try {
      return { doc: JSON.parse(raw) };
    } catch (err) {
      return { err: `${label} ${p}: JSON invalide (${err.message})` };
    }
  };
  const bp = await load(blueprintPath, 'blueprint');
  if (bp.err) return fail(bp.err);
  const fm = await load(featuremapPath, 'featuremap');
  if (fm.err) return fail(fm.err);
  return checkBlueprintDoc(bp.doc, fm.doc);
}

// ---- CLI ----
const isMain = process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isMain) {
  const argv = process.argv.slice(2);
  const fmIdx = argv.indexOf('--featuremap');
  const fmPath = fmIdx >= 0 ? argv[fmIdx + 1] : null;
  const target = argv.filter((a) => !a.startsWith('--') && a !== fmPath)[0];

  if (!target || !fmPath) {
    console.error('usage: node check_blueprint_contract.mjs <blueprint.json> --featuremap <featuremap.json> [--json]');
    process.exit(2);
  }

  (async () => {
    const r = await checkBlueprintFiles(target, fmPath);
    console.log(`VERDICT BLUEPRINT (avant build): ${r.verdict}`);
    r.problems.forEach((p) => console.error(`  FAIL: ${p}`));
    r.features_non_couvertes.forEach((p) => console.error(`  FAIL couverture: ${p}`));
    r.couverture_fantome.forEach((p) => console.error(`  FAIL couverture fantome: ${p}`));
    console.error(`  stats: ${r.stats.modules} module(s) / ${r.stats.responsabilites} responsabilite(s) / ${r.stats.features_couvertes} sur ${r.stats.features} feature(s) couverte(s) / ${r.stats.deps_interdites} paire(s) interdite(s) / ${r.stats.aretes_dependance} arete(s)`);
    console.log(JSON.stringify({
      ok: r.ok,
      problems: r.problems,
      features_non_couvertes: r.features_non_couvertes,
      couverture_fantome: r.couverture_fantome,
      consommateurs: r.consommateurs,
      stats: r.stats,
    }, null, 2));
    process.exit(r.ok ? 0 : 1);
  })();
}

#!/usr/bin/env node
// check_art_response.mjs — oracle déterministe non-LLM du contrat de retour
// GM ↔ Artiste (Lot B, T3, plan `2026-08-23-forge-lot-b-game-master.md`, contrat
// s9 règle (15)).
//
// CE QU'IL MESURE : le Builder (s9) dépose `<game_dir>/04_ASSETS/art_response.json`,
// une entrée PAR `artist_requirements[]` du Game Master (s2.7, `gm_worldscan.json`
// bloc `game_master`) : l'asset réellement réalisé, son nœud/groupe, les états
// représentés, l'affordance visuelle. Complétude 1:1, fichiers réellement présents
// sur disque, états couverts — jamais un LLM-as-judge sur la qualité visuelle.
//
// Sans `artist_requirements` déclarés (gm absent, sans bloc `game_master`, ou
// `artist_requirements` vide) : RIEN n'est requis, verdict OK sans lire le disque
// — comportement neutre, même discipline que `check_decompo.checkGreyBlockCoverage`.
//
// Usage :
//   node check_art_response.mjs <game_dir> --gm <gm_worldscan.json> [--json]
// Exit 0 = OK · 1 = FAIL · 2 = usage.
import { readFile, access } from 'node:fs/promises';
import { resolve, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { isNonEmptyString } from './upstream_schema.mjs';

const EMPTY_STATS = { requirements: 0, reponses: 0, completes: 0 };

/**
 * Liste les `artist_requirements[]` valides déclarées par le GM (Lot B, s2.7).
 * Forme absente/invalide -> tableau vide, jamais une exception.
 * @param {unknown} gm gm_worldscan.json parsé (peut être `null`)
 * @returns {Array<{id:string, states_to_show:string[]}>}
 */
export function artistRequirements(gm) {
  const list = gm?.game_master?.artist_requirements;
  if (!Array.isArray(list)) return [];
  return list
    .filter((r) => r && typeof r === 'object' && isNonEmptyString(r.id))
    .map((r) => ({
      id: r.id,
      states_to_show: Array.isArray(r.states_to_show)
        ? r.states_to_show.filter((s) => typeof s === 'string')
        : [],
    }));
}

/**
 * Oracle complet sur un `art_response.json` déjà parsé (ou `null` si absent du
 * disque), confronté aux `artist_requirements[]` du GM.
 * @param {unknown} doc art_response.json parsé, ou `null` si le fichier est absent
 * @param {unknown} gm gm_worldscan.json parsé (peut être `null`)
 * @param {(rel:string) => boolean} fileExists prédicat d'existence d'un chemin
 *   RELATIF au `game_dir` (injectable pour les tests — jamais d'accès disque direct
 *   dans l'oracle pur)
 * @returns {{ok:boolean, verdict:'OK'|'FAIL', problems:string[], stats:object}}
 */
export function checkArtResponseDoc(doc, gm, fileExists) {
  const requirements = artistRequirements(gm);
  if (requirements.length === 0) {
    return { ok: true, verdict: 'OK', problems: [], stats: { ...EMPTY_STATS } };
  }

  const problems = [];
  if (doc === null || doc === undefined) {
    return {
      ok: false, verdict: 'FAIL',
      problems: [
        '04_ASSETS/art_response.json: absent alors que le Game Master declare '
        + `${requirements.length} artist_requirements[] (contrat s9 regle (15))`,
      ],
      stats: { requirements: requirements.length, reponses: 0, completes: 0 },
    };
  }
  if (doc === null || typeof doc !== 'object' || Array.isArray(doc)) {
    return {
      ok: false, verdict: 'FAIL',
      problems: ['04_ASSETS/art_response.json: doit etre un objet {schema_version, responses}'],
      stats: { requirements: requirements.length, reponses: 0, completes: 0 },
    };
  }
  if (doc.schema_version !== 1) {
    problems.push(`04_ASSETS/art_response.json.schema_version: attendu 1, recu ${JSON.stringify(doc.schema_version)}`);
  }
  const responses = Array.isArray(doc.responses) ? doc.responses : null;
  if (responses === null) {
    problems.push('04_ASSETS/art_response.json.responses: doit etre un tableau');
    return {
      ok: false, verdict: 'FAIL', problems,
      stats: { requirements: requirements.length, reponses: 0, completes: 0 },
    };
  }

  const requirementIds = new Set(requirements.map((r) => r.id));
  const requirementById = new Map(requirements.map((r) => [r.id, r]));
  const answered = new Set();
  let completes = 0;

  responses.forEach((resp, i) => {
    const loc = `responses[${i}]`;
    if (resp === null || typeof resp !== 'object' || Array.isArray(resp)) {
      problems.push(`${loc}: doit etre un objet {requirement_id, asset_files, node_group, states_represented, affordance_visual}`);
      return;
    }
    const reqId = resp.requirement_id;
    if (!isNonEmptyString(reqId) || !requirementIds.has(reqId)) {
      problems.push(`${loc}.requirement_id: '${reqId}' ne resout aucun artist_requirements[].id du Game Master (reponse orpheline)`);
      return;
    }
    if (answered.has(reqId)) {
      problems.push(`${loc}.requirement_id: '${reqId}' deja repondu par une autre entree (une seule reponse par requirement)`);
      return;
    }
    answered.add(reqId);

    let entryOk = true;
    if (!isNonEmptyString(resp.node_group)) {
      problems.push(`${loc}.node_group: absent ou vide`);
      entryOk = false;
    }
    const assetFiles = Array.isArray(resp.asset_files) ? resp.asset_files : null;
    if (assetFiles === null || assetFiles.length === 0) {
      problems.push(`${loc}.asset_files: doit etre un tableau non vide`);
      entryOk = false;
    } else {
      assetFiles.forEach((f, fi) => {
        if (!isNonEmptyString(f)) {
          problems.push(`${loc}.asset_files[${fi}]: absent ou vide`);
          entryOk = false;
          return;
        }
        if (!fileExists(f)) {
          problems.push(`${loc}.asset_files[${fi}]: '${f}' n'existe pas sous le jeu`);
          entryOk = false;
        }
      });
    }
    const statesRepresented = Array.isArray(resp.states_represented)
      ? resp.states_represented.filter((s) => typeof s === 'string')
      : [];
    const requirement = requirementById.get(reqId);
    const manquants = requirement.states_to_show.filter((s) => !statesRepresented.includes(s));
    if (manquants.length > 0) {
      problems.push(`${loc}.states_represented: manque ${JSON.stringify(manquants)} (requis par ${reqId}.states_to_show)`);
      entryOk = false;
    }
    if (entryOk) completes += 1;
  });

  for (const req of requirements) {
    if (!answered.has(req.id)) {
      problems.push(`artist_requirements '${req.id}': aucune reponse dans art_response.json (requirement_sans_reponse)`);
    }
  }

  const stats = { requirements: requirements.length, reponses: responses.length, completes };
  const ok = problems.length === 0;
  return { ok, verdict: ok ? 'OK' : 'FAIL', problems, stats };
}

/**
 * Lit `<game_dir>/04_ASSETS/art_response.json` et le GM sur disque, applique
 * l'oracle. Ne lève jamais : fichier absent/illisible/JSON invalide sont des
 * FAILs explicites (ou OK sans lecture si 0 artist_requirements).
 * @param {string} gameDir
 * @param {string|null} gmPath
 * @returns {Promise<object>}
 */
export async function checkArtResponse(gameDir, gmPath = null) {
  const fail = (msg) => ({
    ok: false, verdict: 'FAIL', problems: [msg], stats: { ...EMPTY_STATS },
  });

  let gm = null;
  if (gmPath) {
    let raw;
    try {
      raw = await readFile(gmPath, 'utf-8');
    } catch (err) {
      return fail(`${gmPath}: absent ou illisible (${err.message})`);
    }
    try {
      gm = JSON.parse(raw);
    } catch (err) {
      return fail(`${gmPath}: JSON invalide (${err.message})`);
    }
  }

  const requirements = artistRequirements(gm);
  if (requirements.length === 0) {
    return { ok: true, verdict: 'OK', problems: [], stats: { ...EMPTY_STATS } };
  }

  const artPath = join(gameDir, '04_ASSETS', 'art_response.json');
  let doc = null;
  try {
    const raw = await readFile(artPath, 'utf-8');
    if (raw.trim().length === 0) {
      return fail(`${artPath}: present mais vide`);
    }
    try {
      doc = JSON.parse(raw);
    } catch (err) {
      return fail(`${artPath}: JSON invalide (${err.message})`);
    }
  } catch {
    doc = null; // absent -> checkArtResponseDoc rend le FAIL nomme (requis: N)
  }

  const fileExists = (rel) => {
    const target = resolve(gameDir, rel);
    return access(target).then(() => true).catch(() => false);
  };
  // access() est async : on résout toutes les vérifications de fichiers AVANT
  // d'appeler l'oracle pur (synchrone) — on pré-calcule un Set des chemins
  // référencés par les réponses puis on injecte un prédicat synchrone.
  const referenced = new Set();
  if (doc && typeof doc === 'object' && Array.isArray(doc.responses)) {
    for (const r of doc.responses) {
      if (r && Array.isArray(r.asset_files)) {
        for (const f of r.asset_files) if (typeof f === 'string') referenced.add(f);
      }
    }
  }
  const existsMap = new Map();
  for (const rel of referenced) {
    // eslint-disable-next-line no-await-in-loop -- ensemble petit (fichiers d'assets déclarés), clarté > micro-parallélisme
    existsMap.set(rel, await fileExists(rel));
  }
  const syncFileExists = (rel) => existsMap.get(rel) === true;

  return checkArtResponseDoc(doc, gm, syncFileExists);
}

// ---- CLI ----
const isMain = process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isMain) {
  const argv = process.argv.slice(2);
  const gmIdx = argv.indexOf('--gm');
  const gmPath = gmIdx >= 0 ? argv[gmIdx + 1] : null;
  const target = argv.filter((a) => !a.startsWith('--') && a !== gmPath)[0];

  if (!target) {
    console.error('usage: node check_art_response.mjs <game_dir> --gm <gm_worldscan.json> [--json]');
    process.exit(2);
  }

  (async () => {
    const r = await checkArtResponse(target, gmPath);
    // Convention (cf. check_amont_traversal.mjs) : stdout ne porte QUE le JSON
    // — oracle.py::run_art_response_check parse `cp.stdout` directement, sans
    // fouiller une ligne "VERDICT" avant. Tout le reste va sur stderr.
    console.error(`VERDICT ART_RESPONSE: ${r.verdict}`);
    r.problems.forEach((p) => console.error(`  FAIL: ${p}`));
    console.error(`  stats: ${r.stats.completes} sur ${r.stats.requirements} requirement(s) completes / ${r.stats.reponses} reponse(s)`);
    console.log(JSON.stringify({ ok: r.ok, problems: r.problems, stats: r.stats }));
    process.exit(r.ok ? 0 : 1);
  })();
}

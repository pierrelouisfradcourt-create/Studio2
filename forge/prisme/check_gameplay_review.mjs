#!/usr/bin/env node
// check_gameplay_review.mjs — oracle de COMPLÉTUDE STRUCTURELLE non-LLM pour l'artefact
// « Gameplay Review » du Prisme (design_review.md). L'élément qui manquait à la matrice
// studio : la checklist Pierre×GPT (forge/prisme/design_review_checklist.yaml)
// devient EXPLOITABLE — le silence sur un item est un échec explicite, jamais un vert
// silencieux.
//
// Ne juge JAMAIS le contenu (aucun LLM-as-judge) : vérifie uniquement que chaque item de
// la checklist a reçu une réponse structurée, que les decisions sont complètes et
// justifiées, et qu'aucun placeholder non résolu ne traîne dans le document.
//
// Patron de style : check_prisme.mjs (findings, splitSections) + check_worldscan.mjs
// (résumé lisible + bloc JSON stable {ok, problems, stats}, vocabulaire de verdict
// unique OK|FAIL).
//
// LIMITE DOCUMENTÉE (pas de dépendance externe type js-yaml) : parseChecklistItemIds
// n'est PAS un parseur YAML général. Il cible uniquement la structure connue de
// design_review_checklist.yaml (`categories: - id: ... / items: - id: ...`) : il
// détecte toutes les lignes `- id: <valeur>` puis distingue les ids de catégorie
// (indentation minimale trouvée) des ids d'item (indentation strictement supérieure).
// Toute checklist qui s'écarterait de ce gabarit (item imbriqué plus profond, structure
// multi-niveaux) romprait cette heuristique — documenté ici plutôt que découvert en
// silence.
//
// Usage :
//   node check_gameplay_review.mjs <design_review.md> [--checklist <chemin.yaml>]
// Exit 0 = OK · 1 = FAIL (document/checklist illisible, bloc json absent/invalide, item
// manquant, id inconnu, statut/raison invalide, decisions incomplètes ou sans rejet
// justifié, placeholder non résolu).
import { readFile } from 'node:fs/promises';
import { resolve, join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

export const STATUTS = ['oui', 'non', 'na'];
export const DECISIONS_VALEURS = ['necessaire', 'rejete'];

const PLACEHOLDER_MARKERS = [/à\s*d[ée]finir/i, /\bTBD\b/i, /\?\?\?/, /\bTODO\b/i];

const DEFAULT_CHECKLIST_PATH = join(
  dirname(fileURLToPath(import.meta.url)),
  'design_review_checklist.yaml'
);

const EMPTY_STATS = {
  items_attendus: 0,
  items_repondus: 0,
  oui: 0,
  non: 0,
  na: 0,
  decisions: 0,
  rejets: 0,
};

/**
 * Extrait les ids d'item `- id: xxx` de design_review_checklist.yaml. Voir la LIMITE
 * DOCUMENTÉE en tête de fichier : heuristique d'indentation, pas un parseur YAML général.
 * @param {string} content
 * @returns {string[]} ids d'item (les ids de catégorie, à l'indentation minimale, sont exclus)
 */
export function parseChecklistItemIds(content) {
  const idLineRe = /^(\s*)-\s*id:\s*(\S+)/;
  const matches = [];
  for (const line of content.split(/\r?\n/)) {
    const m = line.match(idLineRe);
    if (m) matches.push({ indent: m[1].length, id: m[2] });
  }
  if (matches.length === 0) return [];
  const minIndent = Math.min(...matches.map((m) => m.indent));
  return matches.filter((m) => m.indent > minIndent).map((m) => m.id);
}

/**
 * Extrait le contenu du premier bloc ```json ... ``` d'un document markdown.
 * @param {string} content
 * @returns {string|null} contenu brut du bloc (sans les fences), ou null si absent
 */
export function extractJsonBlock(content) {
  const m = content.match(/```json\s*([\s\S]*?)```/);
  return m ? m[1] : null;
}

/**
 * Vérifie mécaniquement un artefact design_review.md contre la checklist YAML : chaque
 * item de la checklist doit recevoir une réponse {statut, raison}, aucun id inconnu,
 * les decisions doivent être complètes (4 champs) et compter au moins un rejet — sinon
 * une justification explicite de « zéro rejet » est exigée — et aucun placeholder non
 * résolu ne doit traîner dans le document entier.
 *
 * Vocabulaire de verdict unique du studio (jamais PASS/CONCERNS) :
 * - `FAIL` : checklist illisible, document illisible, bloc json absent/invalide, item
 *   manquant, id inconnu, statut/raison invalide, decisions incomplètes/absentes,
 *   aucun rejet sans justification, ou placeholder non résolu.
 * - `OK`   : document structurellement complet.
 * `ok` (booléen) = `verdict === 'OK'`.
 *
 * @param {string} reviewPath chemin vers design_review.md
 * @param {string} [checklistPath] chemin vers design_review_checklist.yaml (défaut : fichier voisin de ce module)
 * @returns {Promise<{ok: boolean, verdict: 'OK'|'FAIL', problems: string[], stats: object}>}
 */
export async function checkGameplayReview(reviewPath, checklistPath = DEFAULT_CHECKLIST_PATH) {
  const problems = [];
  const stats = { ...EMPTY_STATS };

  // 1. Checklist — introuvable = échec explicite (jamais un skip silencieux).
  let checklistContent;
  try {
    checklistContent = await readFile(checklistPath, 'utf-8');
  } catch (err) {
    return {
      ok: false,
      verdict: 'FAIL',
      problems: [`checklist introuvable ou illisible : ${checklistPath} (${err.message})`],
      stats,
    };
  }

  const expectedIds = parseChecklistItemIds(checklistContent);
  stats.items_attendus = expectedIds.length;
  if (expectedIds.length === 0) {
    problems.push(`checklist vide ou structure non reconnue : aucun item id trouvé dans ${checklistPath}`);
  }

  // 2. Document de review.
  let content;
  try {
    content = await readFile(reviewPath, 'utf-8');
  } catch (err) {
    problems.push(`document illisible : ${reviewPath} (${err.message})`);
    return { ok: false, verdict: 'FAIL', problems, stats };
  }

  // 3. Placeholders — scan du document ENTIER (règle plus stricte que check_prisme.mjs :
  // ici tout le document engage la review, pas seulement des sections délimitées).
  for (const marker of PLACEHOLDER_MARKERS) {
    if (marker.test(content)) {
      problems.push(`marqueur de placeholder non résolu trouvé dans le document (${marker})`);
    }
  }

  // 4. Bloc JSON.
  const jsonBlock = extractJsonBlock(content);
  if (jsonBlock === null) {
    problems.push('bloc ```json absent du document design_review.md');
    return { ok: false, verdict: 'FAIL', problems, stats };
  }

  let doc;
  try {
    doc = JSON.parse(jsonBlock);
  } catch (err) {
    problems.push(`bloc json invalide : ${err.message}`);
    return { ok: false, verdict: 'FAIL', problems, stats };
  }

  if (doc === null || typeof doc !== 'object' || Array.isArray(doc)) {
    problems.push('bloc json : doit être un objet racine');
    return { ok: false, verdict: 'FAIL', problems, stats };
  }

  // 5. checklist_answers.
  const answers = doc.checklist_answers;
  if (answers === null || typeof answers !== 'object' || Array.isArray(answers)) {
    problems.push('checklist_answers manquant ou invalide (objet attendu)');
  } else {
    const expectedSet = new Set(expectedIds);
    for (const id of expectedIds) {
      if (!(id in answers)) {
        problems.push(`item manquant : ${id} (aucune réponse dans checklist_answers)`);
      }
    }
    for (const id of Object.keys(answers)) {
      if (!expectedSet.has(id)) {
        problems.push(`id inconnu (absent de la checklist) : ${id}`);
      }
    }
    for (const [id, ans] of Object.entries(answers)) {
      if (ans === null || typeof ans !== 'object' || Array.isArray(ans)) {
        problems.push(`checklist_answers.${id} : doit être un objet {statut, raison}`);
        continue;
      }
      const { statut, raison } = ans;
      if (!STATUTS.includes(statut)) {
        problems.push(`checklist_answers.${id}.statut invalide (${JSON.stringify(statut)}), attendu ${STATUTS.join('|')}`);
      } else {
        stats.items_repondus += 1;
        if (statut === 'oui') stats.oui += 1;
        else if (statut === 'non') stats.non += 1;
        else stats.na += 1;
      }
      if (typeof raison !== 'string' || raison.trim().length === 0) {
        problems.push(`checklist_answers.${id}.raison manquante ou vide`);
      }
    }
  }

  // 6. decisions.
  const decisions = doc.decisions;
  if (!Array.isArray(decisions) || decisions.length === 0) {
    problems.push('decisions : au moins une entrée requise');
  } else {
    stats.decisions = decisions.length;
    let rejets = 0;
    decisions.forEach((d, i) => {
      if (d === null || typeof d !== 'object' || Array.isArray(d)) {
        problems.push(`decisions[${i}] : doit être un objet {sujet, decision, pourquoi, impact_architecture}`);
        return;
      }
      const { sujet, decision, pourquoi, impact_architecture: impactArchi } = d;
      if (typeof sujet !== 'string' || sujet.trim().length === 0) {
        problems.push(`decisions[${i}].sujet manquant ou vide`);
      }
      if (!DECISIONS_VALEURS.includes(decision)) {
        problems.push(`decisions[${i}].decision invalide (${JSON.stringify(decision)}), attendu ${DECISIONS_VALEURS.join('|')}`);
      } else if (decision === 'rejete') {
        rejets += 1;
      }
      if (typeof pourquoi !== 'string' || pourquoi.trim().length === 0) {
        problems.push(`decisions[${i}].pourquoi manquant ou vide`);
      }
      if (typeof impactArchi !== 'string' || impactArchi.trim().length === 0) {
        problems.push(`decisions[${i}].impact_architecture manquant ou vide`);
      }
    });
    stats.rejets = rejets;
    if (rejets === 0) {
      const justif = doc.aucun_rejet_justification;
      if (typeof justif !== 'string' || justif.trim().length === 0) {
        problems.push(
          'aucune decision "rejete" trouvée : champ racine aucun_rejet_justification requis (non vide) pour justifier une review qui ne rejette rien'
        );
      }
    }
  }

  const ok = problems.length === 0;
  return { ok, verdict: ok ? 'OK' : 'FAIL', problems, stats };
}

// ---- CLI ----
const isMain = process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isMain) {
  const argv = process.argv.slice(2);
  const positional = [];
  let checklistPath = DEFAULT_CHECKLIST_PATH;
  for (let i = 0; i < argv.length; i += 1) {
    if (argv[i] === '--checklist') {
      checklistPath = argv[i + 1];
      i += 1;
    } else {
      positional.push(argv[i]);
    }
  }

  if (positional.length < 1) {
    console.error('usage: node check_gameplay_review.mjs <design_review.md> [--checklist <chemin.yaml>]');
    process.exit(1);
  }

  (async () => {
    const result = await checkGameplayReview(positional[0], checklistPath);
    // Toujours les deux : un résumé lisible pour un humain, puis un bloc JSON stable
    // pour un appelant mécanique (driver/gate) — jamais un vert silencieux.
    console.log(`VERDICT GAMEPLAY REVIEW: ${result.verdict}`);
    result.problems.forEach((p) => console.error(`  FAIL: ${p}`));
    console.error(
      `  stats: ${result.stats.items_repondus}/${result.stats.items_attendus} item(s) repondu(s)` +
        ` — oui:${result.stats.oui} non:${result.stats.non} na:${result.stats.na}` +
        ` — decisions:${result.stats.decisions} (rejets:${result.stats.rejets})`
    );
    console.log(JSON.stringify({ ok: result.ok, problems: result.problems, stats: result.stats }, null, 2));
    process.exit(result.ok ? 0 : 1);
  })();
}

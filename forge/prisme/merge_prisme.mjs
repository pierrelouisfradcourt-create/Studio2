#!/usr/bin/env node
// merge_prisme.mjs — RECOMBINAISON MÉCANIQUE des N sorties du panel Prisme (s1) contre
// le contrôle (artefact s1 déjà produit par le builder). Aucun LLM-arbitre, aucun jugement
// de "quelle vision est la meilleure" — c'est exactement le risque qu'un LLM-arbitre non
// outillé recréerait (docs/forge/PRISM_SCOPING.md §2).
//
// Promu depuis lab/workflow_lab/WFL-02/shared/merge_prisme.mjs (Tier 2 #6, WFL-02).
//
// Principe : le CHARTER (étape 0) est la seule source de vérité déjà validée. Chaque
// lens du panel cite, quelque part dans son texte, le(s) critère(s) charter
// (`criteres_succes[]`) qu'il couvre — extraction par correspondance EXACTE de texte,
// jamais par interprétation sémantique. La recombinaison =
//   1. UNION des règles par critère charter cité (aucune sélection, aucune fusion de
//      texte — tout ce qui a été écrit est conservé, groupé par critère).
//   2. GAP = tout critère "en périmètre du Prisme" (défini comme : cité par le CONTRÔLE,
//      le seul artefact déjà réel) qu'AUCUN lens du panel ne cite -> remonté tel quel
//      depuis le charter, marqué explicitement comme non couvert, PAS deviné.
//   3. Aucune tentative de détecter/trancher une contradiction de valeur entre lenses
//      (hors scope v0 -- nécessiterait un jugement sémantique, donc une gate humaine).
//
// LIMITE CONNUE (documentée, pas corrigée ici) : l'extraction ne scanne que les tags
// STRUCTURÉS de `criteres_succes:` -- une exigence qui ne vit QUE dans la prose libre
// (`objectif:`, `hors_scope:`) n'a pas de tag et ne peut pas être détectée comme gap.
//
// Usage : node merge_prisme.mjs <charter.yaml> <control.md> <lens1.md> [<lensN.md> ...]
import { readFile } from 'node:fs/promises';

/**
 * Extrait les tags de critères (le libellé MAJUSCULE avant les ":") depuis
 * `criteres_succes:` dans un charter.yaml — lecture texte, pas de parseur YAML (évite
 * une dépendance ; le format `- "TAG : texte"` est une convention stable du studio).
 * @param {string} charterText
 * @returns {string[]} tags dans l'ordre du charter
 */
export function extractCharterCriteria(charterText) {
  const criteriaBlockMatch = charterText.match(/criteres_succes:\n([\s\S]*?)\n\w/);
  const block = criteriaBlockMatch ? criteriaBlockMatch[1] : charterText;
  const tagPattern = /- "([A-ZÀ-Ÿ][A-ZÀ-Ÿ '-]+?)\s*:/g;
  const tags = [];
  let match;
  while ((match = tagPattern.exec(block)) !== null) {
    tags.push(match[1].trim());
  }
  return [...new Set(tags)];
}

/**
 * Découpe la section "RÈGLES OBSERVABLES" (## 4.) d'un artefact product_snapshot.
 * @param {string} content
 * @returns {string} texte brut de la section, ou '' si absente
 */
export function extractRulesSection(content) {
  // (?![\s\S]) = fin de chaîne RÉELLE, pas fin de ligne — sinon en mode /m (nécessaire
  // pour ^) un simple `$` matcherait après CHAQUE ligne et tronquerait la capture
  // paresseuse au premier saut de ligne.
  const match = content.match(
    /^##\s+4\.\s+R[EÈ]GLES OBSERVABLES.*$\n([\s\S]*?)(?=\n##\s+Tra[cç]abilit|\n```|(?![\s\S]))/m
  );
  return match ? match[1].trim() : '';
}

/**
 * Détermine quels tags de critère charter sont cités dans le texte fourni (correspondance
 * de sous-chaîne insensible à la casse — pas d'interprétation, juste une citation).
 * @param {string} text
 * @param {string[]} allTags
 * @returns {string[]}
 */
export function citedTags(text, allTags) {
  return allTags.filter((tag) => text.toLowerCase().includes(tag.toLowerCase()));
}

/**
 * Résout mécaniquement le `source_role` d'un chemin de lens — AUCUNE inférence
 * sémantique, seulement le nom de fichier (mission N2-0 2026-07-28, prérequis gratuit
 * pour l'expérience « diversité des rôles du Prisme » et la wiremap M-G). Convention
 * réelle observée : `product_snapshot_<role>.md` -> `<role>`. Le contrôle (2e argument
 * CLI, `<control.md>`) n'a pas ce préfixe -> rôle fixe `control`. Tout autre nom ->
 * basename sans extension, jamais un échec silencieux (pas de rôle "unknown" opaque,
 * le nom réel reste lisible pour investigation).
 * @param {string} lensPath
 * @param {boolean} [isControl]
 * @returns {string}
 */
export function resolveSourceRole(lensPath, isControl = false) {
  if (isControl) return 'control';
  const base = lensPath.replace(/\\/g, '/').split('/').pop() || lensPath;
  const stem = base.replace(/\.[^.]+$/, '');
  const match = stem.match(/^product_snapshot_(.+)$/);
  return match ? match[1] : stem;
}

/**
 * Recombine mécaniquement le contrôle + le panel de lenses contre le charter.
 * @param {{charterText:string, controlContent:string, lenses:Array<{path:string, content:string}>}} input
 * @returns {{output:string, controlScopeTags:string[], gaps:string[]}}
 */
export function mergePrisme({ charterText, controlContent, lenses }) {
  const allTags = extractCharterCriteria(charterText);
  const controlScopeTags = citedTags(controlContent, allTags);

  const scored = lenses.map(({ path, content }) => ({
    path,
    role: resolveSourceRole(path),
    tags: citedTags(content, allTags),
    rules: extractRulesSection(content),
  }));

  const coveredByPanel = new Set(scored.flatMap((l) => l.tags));
  const gaps = controlScopeTags.filter((tag) => !coveredByPanel.has(tag));

  const lines = [];
  lines.push('# Prisme — sortie RECOMBINÉE mécaniquement');
  lines.push('');
  lines.push(
    '> Généré par `merge_prisme.mjs` — UNION par critère charter cité, AUCUN arbitrage sémantique.'
  );
  lines.push('> `claim_verdict` : NO_CLAIM_ALLOWED — recombinaison mécanique, pas un jugement de qualité.');
  lines.push('');
  lines.push('## Périmètre produit (dérivé du contrôle réel, pas deviné)');
  lines.push('');
  lines.push(
    `Le contrôle (artefact s1 réel déjà produit) cite ${controlScopeTags.length}/${allTags.length} critères charter : ` +
      controlScopeTags.map((t) => `\`${t}\``).join(', ') +
      '.'
  );
  lines.push('');
  lines.push(`## Couverture par critère (union du panel ×${lenses.length})`);
  lines.push('');
  for (const tag of controlScopeTags) {
    const citingLenses = scored.filter((l) => l.tags.includes(tag));
    lines.push(`### ${tag}`);
    lines.push('');
    if (citingLenses.length === 0) {
      lines.push(
        `**⚠ GAP — aucun lens du panel ne couvre ce critère.** Repris tel quel depuis le charter ` +
          `(non deviné, non reformulé) :`
      );
      const criterionMatch = charterText.match(new RegExp(`- "${tag}[^\n]*"`, 'i'));
      lines.push('');
      lines.push('```');
      lines.push(criterionMatch ? criterionMatch[0] : `(texte du critère "${tag}" non retrouvé littéralement)`);
      lines.push('```');
    } else {
      lines.push(
        `Couvert par ${citingLenses.length}/${lenses.length} lens : ` +
          citingLenses.map((l) => `${l.path} (${l.role})`).join(', ') +
          '.'
      );
    }
    lines.push('');
  }

  lines.push('## Règles observables — union brute, groupée par lens (rien fusionné, rien tranché)');
  lines.push('');
  lines.push(
    'Chaque bloc ci-dessous est le texte VERBATIM de la section « Règles observables » d\'un lens. ' +
      "Aucune reformulation, aucune sélection d'une version « meilleure » qu'une autre — la fusion " +
      'de texte ou l\'arbitrage entre versions divergentes reste une décision HumanGate (hors scope v0).'
  );
  lines.push('');
  for (const lens of scored) {
    lines.push(`### Source : ${lens.path} (source_role: ${lens.role})`);
    lines.push('');
    lines.push(lens.rules || '(section vide ou introuvable)');
    lines.push('');
  }

  // Bloc machine-lisible en fin de sortie — consommé par la wiremap M-G pour peupler
  // `source_role` et par l'expérience « diversité des rôles » (prérequis gratuit posé
  // ici, mission N2-0 2026-07-28). AUCUN jugement de qualité, juste une redite
  // mécanique de la table déjà calculée ci-dessus.
  const roles = [...new Set(scored.map((l) => l.role))];
  const coverageByRole = {};
  for (const tag of allTags) {
    const citingRoles = scored.filter((l) => l.tags.includes(tag)).map((l) => l.role);
    coverageByRole[tag] = [...new Set(citingRoles)];
  }
  lines.push('## Bloc machine-lisible (source_role)');
  lines.push('');
  lines.push('```json');
  lines.push(JSON.stringify({ coverage_by_role: coverageByRole, roles }, null, 2));
  lines.push('```');
  lines.push('');

  return { output: lines.join('\n'), controlScopeTags, gaps };
}

async function main() {
  const [charterPath, controlPath, ...lensPaths] = process.argv.slice(2);
  if (!charterPath || !controlPath || lensPaths.length === 0) {
    console.error('Usage: node merge_prisme.mjs <charter.yaml> <control.md> <lens1.md> [<lensN.md> ...]');
    process.exit(2);
  }

  const charterText = await readFile(charterPath, 'utf-8');
  const controlContent = await readFile(controlPath, 'utf-8');
  const lenses = [];
  for (const lensPath of lensPaths) {
    // eslint-disable-next-line no-await-in-loop -- volume faible, ordre stable voulu
    const content = await readFile(lensPath, 'utf-8');
    lenses.push({ path: lensPath, content });
  }

  const { output, controlScopeTags, gaps } = mergePrisme({ charterText, controlContent, lenses });
  console.log(output);

  console.error('\n=== RÉCAPITULATIF MÉCANIQUE (stderr) ===');
  console.error(`Critères en périmètre (issus du contrôle) : ${controlScopeTags.length}`);
  console.error(`Critères couverts par au moins 1 lens : ${controlScopeTags.length - gaps.length}`);
  console.error(`Critères NON couverts (gap, remonté fog) : ${gaps.length}${gaps.length ? ' -> ' + gaps.join(', ') : ''}`);
  console.error(gaps.length === 0 ? 'RESULT: FULL_COVERAGE' : 'RESULT: GAPS_PRESENT (attendu — voir fog)');
}

if (import.meta.url === `file://${process.argv[1]}` || import.meta.url === `file:///${(process.argv[1] || '').replace(/\\/g, '/')}`) {
  main();
}

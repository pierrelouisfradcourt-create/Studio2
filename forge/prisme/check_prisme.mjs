#!/usr/bin/env node
// check_prisme.mjs — oracle de CONFORMITÉ STRUCTURELLE non-LLM pour un artefact
// product_snapshot.md (contrat s1-prisme.yaml : {voit, fait, ressent,
// regles_observables[]}, aucun champ vide/absent, aucun placeholder non résolu).
//
// Promu depuis lab/workflow_lab/WFL-02/shared/check_prisme.mjs (Tier 2 #6) : ne juge
// JAMAIS le contenu (aucun LLM-as-judge), seulement la forme — mêmes règles pour le
// contrôle (1 agent) et chaque lens du panel.
//
// Usage : node check_prisme.mjs <fichier1.md> [<fichier2.md> ...]
// Exit 0 si TOUS les fichiers passent ; exit 1 si au moins un échoue ; exit 2 = usage.
import { readFile } from 'node:fs/promises';

const REQUIRED_SECTIONS = [
  { key: 'voit', pattern: /CE QUE LE JOUEUR VOIT/i },
  { key: 'fait', pattern: /CE QUE LE JOUEUR FAIT/i },
  { key: 'ressent', pattern: /CE QUE LE JOUEUR RESSENT/i },
  { key: 'regles_observables', pattern: /R[EÈ]GLES OBSERVABLES/i },
];

const PLACEHOLDER_MARKERS = [/à\s*d[ée]finir/i, /\bTBD\b/i, /\?\?\?/, /\bTODO\b/i, /\bXXX\b/];

const MIN_SECTION_CHARS = 40; // contenu non trivial — pas juste un titre suivi de rien
const RULE_PATTERN = /^-\s*\*\*R\d+/m; // au moins une règle numérotée "- **Rn"

/**
 * Découpe le markdown en sections par les 4 en-têtes attendus (## N. TITRE), dans
 * l'ordre où ils apparaissent, en capturant le texte jusqu'au prochain en-tête `## `.
 * @param {string} content
 * @returns {Map<string,string>} clé de section -> texte brut de la section
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
 * Vérifie un artefact product_snapshot contre le contrat s1-prisme.yaml (forme
 * uniquement — aucun jugement de contenu).
 * @param {string} filePath
 * @returns {Promise<{filePath:string, pass:boolean, findings:string[]}>}
 */
export async function checkFile(filePath) {
  const findings = [];
  let content;
  try {
    content = await readFile(filePath, 'utf-8');
  } catch (err) {
    return { filePath, pass: false, findings: [`fichier illisible : ${err.message}`] };
  }

  const sections = splitSections(content);

  for (const { key } of REQUIRED_SECTIONS) {
    if (!sections.has(key)) {
      findings.push(`section manquante : ${key}`);
      continue;
    }
    const body = sections.get(key);
    if (body.length < MIN_SECTION_CHARS) {
      findings.push(`section trop courte / probablement vide : ${key} (${body.length} caractères)`);
    }
  }

  // Le scan de placeholder ne porte QUE sur le corps des 4 sections requises — pas sur
  // tout le document. Sinon une phrase du préambule qui AFFIRME l'absence d'un
  // placeholder (ex. « Aucun champ « à définir ». ») se ferait flaguer comme si elle EN
  // était un — faux positif réel trouvé en exécutant cet oracle sur le contrôle (WFL-01
  // product_snapshot.md), même famille de bug que le faux positif de scan de commentaire
  // trouvé dans l'oracle WFL-01 (cf. results.md §3).
  const sectionsText = [...sections.values()].join('\n');
  for (const marker of PLACEHOLDER_MARKERS) {
    if (marker.test(sectionsText)) {
      findings.push(`marqueur de placeholder non résolu trouvé dans une section (${marker})`);
    }
  }

  const rulesBody = sections.get('regles_observables') || '';
  if (rulesBody && !RULE_PATTERN.test(rulesBody)) {
    findings.push('aucune règle numérotée "- **Rn" détectée dans regles_observables');
  }

  return { filePath, pass: findings.length === 0, findings };
}

async function main() {
  const files = process.argv.slice(2);
  if (files.length === 0) {
    console.error('Usage: node check_prisme.mjs <fichier1.md> [<fichier2.md> ...]');
    process.exit(2);
  }

  console.log('=== ORACLE DE CONFORMITÉ STRUCTURELLE — s1 Prisme ===\n');

  const results = [];
  for (const file of files) {
    // eslint-disable-next-line no-await-in-loop -- ordre de sortie stable, volume faible
    const result = await checkFile(file);
    results.push(result);
    if (result.pass) {
      console.log(`✓ PASS  ${file}`);
    } else {
      console.log(`✗ FAIL  ${file}`);
      for (const finding of result.findings) console.log(`    - ${finding}`);
    }
  }

  const passCount = results.filter((r) => r.pass).length;
  console.log(`\n${passCount}/${results.length} artefacts conformes structurellement.`);

  if (passCount === results.length) {
    console.log('RESULT: PASS');
    process.exit(0);
  } else {
    console.log('RESULT: FAIL');
    process.exit(1);
  }
}

if (import.meta.url === `file://${process.argv[1]}` || import.meta.url === `file:///${(process.argv[1] || '').replace(/\\/g, '/')}`) {
  main();
}

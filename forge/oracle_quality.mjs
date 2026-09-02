#!/usr/bin/env node
// oracle_quality.mjs — ORACLE QUALITY LAYER V1.
//
// LE PROBLÈME QU'IL ADRESSE (mesuré le 2026-08-04) : la boucle de réparation converge
// vers ce que l'oracle mesure. Un oracle qui vérifie la NON-VACUITÉ fait écrire des
// valeurs non vides — pas des valeurs justes. Preuve réelle : `retention_answer` de
// Pac-Man réparée en « Proceed with caution near ghosts. » (hors sujet, et en anglais
// dans un artefact français), acceptée par `check_worldscan`.
//
// CE QUE CETTE COUCHE N'EST PAS :
//   - PAS un juge LLM. Aucun modèle n'est appelé ici, jamais. Chaque signal est un
//     prédicat déterministe qu'un humain peut recalculer à la main.
//   - PAS un score global. Quatre axes rendus SÉPARÉMENT ; agréger reviendrait à
//     pouvoir « compenser » une provenance inventée par une belle structure.
//   - PAS un remplaçant des oracles mécaniques. Elle s'ajoute, ils décident encore.
//
// RÉGIME V1 : ADVISORY. `SEMANTIC_SIGNAL` est MESURÉ et REMONTÉ, il ne fait basculer
// aucun verdict existant. Même prudence que les étages `lifecycle` et `reused_from`
// du standard : on mesure le taux de faux positifs sur des artefacts connus-bons
// AVANT de durcir. Durcir un signal dont on ignore le taux de fausse alerte, c'est
// échanger un angle mort contre un bruit — et le bruit finit toujours par être ignoré,
// donc par redevenir un angle mort.
//
// Usage : node oracle_quality.mjs <artefact.json> [--json]

import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { normalizeText, jaccard } from './upstream_schema.mjs';

// Champs qui portent du SENS (par suffixe de chemin) : ceux dont un lecteur humain
// attend une information, pas un identifiant. Liste explicite plutôt qu'heuristique
// sur la longueur : un oracle doit pouvoir dire POURQUOI il regarde un champ.
export const CHAMPS_DE_SENS = [
  'retention_answer', 'player_goal', 'victory_condition', 'defeat_condition',
  'minute_1', 'minute_10', 'hour_5', 'endgame',
  'observation', 'claim', 'enonce', 'statement',
  'capacite', 'responsabilite',
];

// Mots-outils très fréquents, servant UNIQUEMENT à trancher la langue d'un champ.
// Ce ne sont pas des mots-clés de contenu : leur présence ne « valide » rien, leur
// répartition indique seulement dans quelle langue la phrase est écrite.
const OUTILS_FR = new Set(['le', 'la', 'les', 'des', 'du', 'de', 'un', 'une', 'et', 'est',
  'pour', 'avec', 'dans', 'que', 'qui', 'sur', 'par', 'au', 'aux', 'ce', 'se', 'sans', 'plus', 'ne', 'pas']);
const OUTILS_EN = new Set(['the', 'and', 'with', 'for', 'of', 'to', 'in', 'is', 'are', 'that',
  'this', 'from', 'by', 'on', 'as', 'it', 'or', 'be', 'has', 'have', 'their', 'they']);

// En dessous de ce nombre de mots, la langue d'une phrase n'est pas décidable de
// façon fiable : on ne prononce alors AUCUN avis (jamais un faux positif de plus).
const MIN_MOTS_LANGUE = 6;
// Seuil de quasi-recopie entre deux champs voisins. Calibré sur mesure réelle :
// 14 exigences sur 15 sont sous 0,30 et la seule quasi-recopie observée est à 0,526.
const SEUIL_RECOPIE = 0.45;

/**
 * Tous les chemins-feuilles de type chaîne, avec leur valeur.
 * @param {unknown} obj
 * @returns {Array<{chemin:string, valeur:string}>}
 */
export function feuillesTexte(obj) {
  const out = [];
  const visiter = (v, p) => {
    if (Array.isArray(v)) v.forEach((el, i) => visiter(el, `${p}[${i}]`));
    else if (v !== null && typeof v === 'object') {
      for (const [k, val] of Object.entries(v)) visiter(val, p ? `${p}.${k}` : k);
    } else if (typeof v === 'string' && v.trim()) out.push({ chemin: p, valeur: v });
  };
  visiter(obj, '');
  return out;
}

/**
 * Vrai si le chemin désigne un champ porteur de sens.
 * @param {string} chemin
 * @returns {boolean}
 */
export function estChampDeSens(chemin) {
  const dernier = chemin.split('.').pop().replace(/\[\d+\]$/, '');
  return CHAMPS_DE_SENS.includes(dernier);
}

/**
 * Remplace les indices par `*` : `games[0].retention_answer` -> `games[*].retention_answer`.
 * Sert à regrouper les occurrences d'un MÊME champ sur des entrées différentes.
 * @param {string} chemin
 * @returns {string}
 */
export function motifDeChemin(chemin) {
  return chemin.replace(/\[\d+\]/g, '[*]');
}

/**
 * Langue dominante d'une phrase, par répartition des mots-outils. Rend `null` quand
 * c'est indécidable (phrase trop courte, ou aucune préférence nette) — un oracle qui
 * ne sait pas doit le dire, pas trancher au hasard.
 * @param {string} texte
 * @returns {'fr'|'en'|null}
 */
export function langueDe(texte) {
  const mots = normalizeText(texte).split(' ').filter(Boolean);
  if (mots.length < MIN_MOTS_LANGUE) return null;
  let fr = 0;
  let en = 0;
  for (const m of mots) {
    if (OUTILS_FR.has(m)) fr += 1;
    if (OUTILS_EN.has(m)) en += 1;
  }
  if (fr === en) return null;
  return fr > en ? 'fr' : 'en';
}

/**
 * Q1 — DISCRIMINANCE. Deux entrées DIFFÉRENTES (deux jeux, deux exigences) décrites
 * par la MÊME phrase portent zéro information : le champ ne distingue plus rien de ce
 * qu'il prétend décrire.
 *
 * C'est la règle de variance des métriques (ratifiée 2026-07-21) appliquée au contenu
 * d'un artefact et non plus à une métrique : une valeur constante là où on attend une
 * description valide le format, pas le propos.
 * @param {Array} feuilles
 * @returns {Array<{signal:string, chemins:string[], detail:string}>}
 */
export function verifierDiscriminance(feuilles) {
  const parMotif = new Map();
  for (const f of feuilles) {
    if (!estChampDeSens(f.chemin)) continue;
    const motif = motifDeChemin(f.chemin);
    if (!parMotif.has(motif)) parMotif.set(motif, []);
    parMotif.get(motif).push(f);
  }
  const out = [];
  for (const [motif, groupe] of parMotif.entries()) {
    if (groupe.length < 2) continue;
    const parValeur = new Map();
    for (const f of groupe) {
      const cle = normalizeText(f.valeur);
      if (!parValeur.has(cle)) parValeur.set(cle, []);
      parValeur.get(cle).push(f.chemin);
    }
    for (const [, chemins] of parValeur.entries()) {
      if (chemins.length > 1) {
        out.push({
          signal: 'DISCRIMINANCE',
          chemins,
          detail: `${chemins.length} entrees distinctes decrites par la MEME phrase sur ${motif} `
            + '— le champ ne distingue plus ce qu il pretend decrire (information nulle)',
        });
      }
    }
  }
  return out;
}

/**
 * Q2 — COHÉRENCE DE LANGUE. Un champ rédigé dans une autre langue que le reste de
 * l'artefact signale un contenu venu d'ailleurs : recopie, réparation hors contexte,
 * ou remplissage. Cas réel : une réparation anglaise insérée dans un artefact français.
 *
 * Ne se prononce QUE sur les champs assez longs pour que la langue soit décidable, et
 * seulement si l'artefact a lui-même une langue dominante nette.
 * @param {Array} feuilles
 * @returns {Array}
 */
export function verifierLangue(feuilles) {
  const sens = feuilles.filter((f) => estChampDeSens(f.chemin));
  const langues = sens.map((f) => ({ ...f, langue: langueDe(f.valeur) })).filter((f) => f.langue);
  if (langues.length < 3) return [];
  const compte = langues.reduce((a, f) => { a[f.langue] = (a[f.langue] || 0) + 1; return a; }, {});
  const dominante = Object.entries(compte).sort((a, b) => b[1] - a[1])[0];
  // Pas de langue nettement dominante (artefact bilingue assumé) : aucun avis.
  if (dominante[1] <= langues.length / 2) return [];
  return langues
    .filter((f) => f.langue !== dominante[0])
    .map((f) => ({
      signal: 'LANGUE',
      chemins: [f.chemin],
      detail: `redige en '${f.langue}' alors que l artefact est majoritairement en `
        + `'${dominante[0]}' (${dominante[1]}/${langues.length} champs) — contenu venu d ailleurs`,
    }));
}

/**
 * Q3 — QUASI-RECOPIE. Deux champs de sens VOISINS (même conteneur) dont les textes se
 * recouvrent au-delà du seuil : l'un n'apporte rien de plus que l'autre. Cas typique,
 * un `claim` qui reformule l'`observation` sans rien en déduire.
 * @param {Array} feuilles
 * @returns {Array}
 */
export function verifierRecopie(feuilles) {
  const sens = feuilles.filter((f) => estChampDeSens(f.chemin));
  const parParent = new Map();
  for (const f of sens) {
    const parent = f.chemin.slice(0, f.chemin.lastIndexOf('.'));
    if (!parParent.has(parent)) parParent.set(parent, []);
    parParent.get(parent).push(f);
  }
  const out = [];
  for (const groupe of parParent.values()) {
    for (let i = 0; i < groupe.length; i += 1) {
      for (let j = i + 1; j < groupe.length; j += 1) {
        const s = jaccard(groupe[i].valeur, groupe[j].valeur);
        if (s >= SEUIL_RECOPIE) {
          out.push({
            signal: 'RECOPIE',
            chemins: [groupe[i].chemin, groupe[j].chemin],
            detail: `recouvrement lexical ${s.toFixed(3)} >= ${SEUIL_RECOPIE} — `
              + 'le second champ ne dit rien de plus que le premier',
          });
        }
      }
    }
  }
  return out;
}

/**
 * Classe un signal selon la taxonomie de défauts (audit 2026-08-04) :
 *   A — manque structurel (champ absent/vide)        -> corriger schema/oracle
 *   B — faux positif semantique (forme OK, sens faux) -> contrainte observable
 *   C — oracle trop faible (mesure eloignee du besoin) -> mesure plus proche
 * @param {string} signal
 * @returns {'A'|'B'|'C'}
 */
export function classeDeDefaut(signal) {
  if (signal === 'STRUCTURE' || signal === 'PROVENANCE') return 'A';
  if (signal === 'DISCRIMINANCE') return 'C';
  return 'B';
}

/**
 * Mesure complète du signal sémantique d'un artefact. Ne rend JAMAIS un score :
 * une liste de signaux nommés, chacun rattaché à des chemins précis et à une classe
 * de défaut — donc directement exploitable par la boucle de réparation.
 * @param {object} artefact
 * @returns {{verdict:'PASS'|'FAIL', signaux:Array, compte:object}}
 */
export function mesurerSignalSemantique(artefact) {
  const feuilles = feuillesTexte(artefact);
  const signaux = [
    ...verifierDiscriminance(feuilles),
    ...verifierLangue(feuilles),
    ...verifierRecopie(feuilles),
  ].map((s) => ({ ...s, classe: classeDeDefaut(s.signal) }));

  const compte = signaux.reduce((a, s) => { a[s.signal] = (a[s.signal] || 0) + 1; return a; }, {});
  return { verdict: signaux.length === 0 ? 'PASS' : 'FAIL', signaux, compte };
}

/**
 * Cibles réparables d'un signal. Pour une DISCRIMINANCE, on garde la PREMIÈRE
 * occurrence et on demande de différencier les suivantes : la valeur partagée n'est
 * pas fausse en soi, c'est sa répétition qui annule l'information. Réécrire les deux
 * perdrait ce qui était peut-être juste.
 * @param {object} signal
 * @returns {string[]}
 */
export function ciblesDuSignal(signal) {
  if (signal.signal === 'DISCRIMINANCE') return signal.chemins.slice(1);
  if (signal.signal === 'RECOPIE') return [signal.chemins[1]];
  return signal.chemins;
}

/**
 * Prompt de réparation SPÉCIFIQUE À LA CLASSE du défaut — c'est le cœur de la
 * boucle V2 : « classe d'erreur -> mutation efficace », et non « erreur -> changer
 * de modèle ».
 *
 * Un défaut de discriminance ne se répare pas comme un champ vide : le champ EST
 * rempli, et le lui redemander produirait la même phrase. Il faut lui montrer la
 * phrase à ne pas répéter et l'entité à décrire à la place.
 *
 * @param {object} signal
 * @param {string} chemin cible précise
 * @param {object} voisins valeurs scalaires voisines (contexteVoisin de repair_loop)
 * @param {unknown} valeurActuelle
 * @returns {string}
 */
export function promptReparationSignal(signal, chemin, voisins, valeurActuelle) {
  const commun = [
    `FIELD_TO_REPAIR:\n${chemin}`,
    `VALID_CONTEXT (ce que ce champ doit décrire) :\n${JSON.stringify(voisins, null, 1)}`,
  ];
  const sortie = [
    '\nRends EXACTEMENT cet objet, et rien d\'autre :',
    '```json',
    '{ "path": "<le chemin ci-dessus, à l\'identique>", "value": "<la nouvelle valeur>" }',
    '```',
  ];

  if (signal.signal === 'DISCRIMINANCE') {
    return [
      'Un contrôle mécanique a détecté que ce champ répète MOT POUR MOT la description',
      'd\'une AUTRE entrée. Deux choses différentes décrites par la même phrase, c\'est',
      'zéro information : le champ ne distingue plus rien.',
      ...commun,
      `\nPHRASE À NE PAS RÉPÉTER (elle décrit déjà ${signal.chemins[0]}) :\n"${valeurActuelle}"`,
      '\nFORBIDDEN:\n- ne reprends pas la phrase ci-dessus, même reformulée',
      '- ne touche à aucun autre chemin',
      '- écris ce qui est PROPRE à cette entrée-ci, pas ce qui vaut pour les deux',
      ...sortie,
    ].join('\n');
  }

  if (signal.signal === 'RECOPIE') {
    return [
      'Un contrôle mécanique a détecté que ce champ recopie largement un champ voisin.',
      'Il n\'ajoute donc rien à ce qui est déjà dit.',
      ...commun,
      `\nVALEUR ACTUELLE (trop proche de ${signal.chemins[0]}) :\n"${valeurActuelle}"`,
      '\nFORBIDDEN:\n- ne reformule pas le champ voisin',
      '- ne touche à aucun autre chemin',
      `- écris ce que ce champ AJOUTE par rapport à ${signal.chemins[0]}`,
      ...sortie,
    ].join('\n');
  }

  // LANGUE
  return [
    'Un contrôle mécanique a détecté que ce champ est rédigé dans une autre langue que',
    'le reste de l\'artefact.',
    ...commun,
    `\nVALEUR ACTUELLE :\n"${valeurActuelle}"`,
    `\nDÉTAIL DU CONTRÔLE :\n${signal.detail}`,
    '\nFORBIDDEN:\n- ne traduis pas mot à mot : réécris dans la langue du reste de l\'artefact',
    '- ne touche à aucun autre chemin',
    ...sortie,
  ].join('\n');
}

/**
 * Bloc de mesure à 4 axes SÉPARÉS. `semantic` est ADVISORY en V1 : il est rendu tel
 * quel, et `bloquant` reste faux tant que son taux de fausse alerte n'a pas été
 * ratifié. C'est l'appelant qui décide quoi en faire — jamais cette fonction.
 * @param {object} opts {structure, provenance, nonRegression, artefact}
 * @returns {object}
 */
export function rapportQualite({ structure, provenance, nonRegression, artefact }) {
  const sem = mesurerSignalSemantique(artefact);
  return {
    STRUCTURE: structure ? 'PASS' : 'FAIL',
    PROVENANCE: provenance ? 'PASS' : 'FAIL',
    NON_REGRESSION: nonRegression ? 'PASS' : 'FAIL',
    SEMANTIC_SIGNAL: sem.verdict,
    semantic_signaux: sem.signaux,
    semantic_compte: sem.compte,
    advisory: true, // V1 : mesuré, jamais bloquant — cf. en-tête
    score_global: null, // volontairement absent
  };
}

// ---- CLI ----
const isMain = process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isMain) {
  const cible = process.argv.slice(2).find((a) => !a.startsWith('--'));
  if (!cible) {
    console.error('usage: node oracle_quality.mjs <artefact.json> [--json]');
    process.exitCode = 2;
  } else {
    (async () => {
      let doc;
      try {
        doc = JSON.parse(await readFile(cible, 'utf-8'));
      } catch (err) {
        console.error(`FAIL: ${cible} illisible ou invalide (${err.message})`);
        process.exitCode = 1;
        return;
      }
      const sem = mesurerSignalSemantique(doc);
      console.log(`SEMANTIC_SIGNAL: ${sem.verdict}  (ADVISORY — ne fait basculer aucun verdict)`);
      for (const s of sem.signaux) {
        console.error(`  [${s.classe}] ${s.signal} ${s.chemins.join(' + ')}\n      ${s.detail}`);
      }
      console.log(JSON.stringify({ verdict: sem.verdict, signaux: sem.signaux, compte: sem.compte }, null, 1));
      process.exitCode = 0; // advisory : jamais un code d'echec en V1
    })();
  }
}

#!/usr/bin/env node
// repair_loop.mjs — REPAIR_LOOP_V1 : boucle générique
//     GENERATE -> VALIDATE -> CLASSIFY -> REPAIR (champs fautifs SEULS) -> VALIDATE
//
// Pourquoi cette boucle plutôt qu'un meilleur prompt (mesuré le 2026-08-04) :
//   - 4 mutations de prompt sur s2-worldscan plafonnent à 2 jeux valides sur 3, et le
//     jeu qui échoue CHANGE d'une mutation à l'autre : durcir un champ déplace le
//     silence sur un autre.
//   - Rejouer le MÊME prompt ne converge pas : à température 0 la panne est
//     déterministe (M-ws3/pacman redonne exactement le même échec).
//   - Redemander UNIQUEMENT le champ manquant converge, pour ~12 % du coût d'une
//     régénération (86 tokens contre ~700) — et la régénération, elle, échouait encore.
//
// LA GARANTIE EST DANS LE CODE, PAS DANS LE PROMPT.
// « Ne touche pas aux champs valides » demandé à un modèle est un vœu. Ici, le patch
// rendu par le modèle est filtré par une LISTE BLANCHE de chemins dérivée des findings
// de l'oracle : toute clé hors de cette liste est REJETÉE et rapportée. Un modèle qui
// tenterait de réécrire l'artefact entier ne pourrait pas — structurellement.
//
// Ce module ne connaît NI un modèle NI un oracle particulier : `appelerModele` et
// `valider` sont injectés (même patron que forge.panel.panel_prisme_executor). C'est ce
// qui le rend testable hors-ligne, avec un faux modèle, sans jamais rien appeler.

// --- chemins ---------------------------------------------------------------------

/**
 * Découpe un chemin de finding en segments adressables.
 * "games[0].retention_answer" -> ['games', 0, 'retention_answer']
 * @param {string} chemin
 * @returns {Array<string|number>}
 */
export function segments(chemin) {
  const out = [];
  for (const part of String(chemin).split('.')) {
    const m = part.match(/^([^[\]]*)((\[\d+\])*)$/);
    if (!m) return [];
    if (m[1]) out.push(m[1]);
    for (const idx of (m[2] || '').match(/\d+/g) || []) out.push(Number(idx));
  }
  return out;
}

/**
 * Lit une valeur à un chemin. Rend `undefined` si le chemin ne mène nulle part —
 * jamais d'exception : un chemin absent est le cas NORMAL (c'est souvent
 * précisément ce que l'oracle reproche).
 * @param {unknown} obj
 * @param {string} chemin
 * @returns {unknown}
 */
export function lire(obj, chemin) {
  let cur = obj;
  for (const s of segments(chemin)) {
    if (cur === null || typeof cur !== 'object') return undefined;
    cur = cur[s];
  }
  return cur;
}

/**
 * Écrit une valeur à un chemin, en créant les conteneurs intermédiaires manquants
 * (objet ou tableau selon le type du segment suivant). Rend `true` si l'écriture a
 * eu lieu.
 *
 * NE crée PAS un index de tableau hors-borne : réparer `games[7].x` sur un tableau
 * de 2 éléments fabriquerait un jeu fantôme rempli de trous. Un chemin qui ne
 * désigne aucun emplacement réel n'est pas réparable, il est refusé.
 * @param {object} obj
 * @param {string} chemin
 * @param {unknown} valeur
 * @returns {boolean}
 */
export function ecrire(obj, chemin, valeur) {
  const segs = segments(chemin);
  if (segs.length === 0) return false;
  let cur = obj;
  for (let i = 0; i < segs.length - 1; i += 1) {
    const s = segs[i];
    const suivant = segs[i + 1];
    if (typeof s === 'number' && (!Array.isArray(cur) || s >= cur.length)) return false;
    if (cur[s] === null || typeof cur[s] !== 'object') {
      if (cur[s] !== undefined) return false; // écraser une feuille par un conteneur = perte
      cur[s] = typeof suivant === 'number' ? [] : {};
    }
    cur = cur[s];
  }
  const dernier = segs[segs.length - 1];
  if (typeof dernier === 'number' && (!Array.isArray(cur) || dernier >= cur.length)) return false;
  if (cur === null || typeof cur !== 'object') return false;
  cur[dernier] = valeur;
  return true;
}

/**
 * Liste tous les chemins-feuilles d'un artefact, avec leur valeur sérialisée. Sert
 * la PREUVE de non-régression : après réparation, tout chemin dont la valeur a
 * changé sans être dans la liste blanche est une régression, et doit être visible.
 * @param {unknown} obj
 * @param {string} prefixe
 * @returns {Map<string,string>}
 */
export function cheminsFeuilles(obj, prefixe = '') {
  const out = new Map();
  const visiter = (v, p) => {
    if (Array.isArray(v)) {
      v.forEach((el, i) => visiter(el, `${p}[${i}]`));
    } else if (v !== null && typeof v === 'object') {
      for (const [k, val] of Object.entries(v)) visiter(val, p ? `${p}.${k}` : k);
    } else {
      out.set(p, JSON.stringify(v));
    }
  };
  visiter(obj, prefixe);
  return out;
}

// --- findings --------------------------------------------------------------------

// Un finding d'oracle a la forme « <chemin>: <raison> ». Le chemin doit ressembler à
// une adresse (segments alphanumériques, indices entre crochets) — sinon la partie
// avant le « : » est de la prose, pas une adresse, et le finding n'est pas réparable
// localement. Exemples NON réparables, à dessein : « observation_manifest.json: 1
// jeu(x) analyse(s), minimum 2 requis » (il manque un OBJET entier, pas un champ)
// ou « prisme.json: AUCUNE exigence actionnable ».
const _CHEMIN = /^[A-Za-z_][A-Za-z0-9_]*(\[\d+\])*(\.[A-Za-z_][A-Za-z0-9_]*(\[\d+\])*)*$/;

// Un NOM DE FICHIER est syntaxiquement indiscernable d'un chemin pointé :
// `observation_manifest.json` se découpe en ['observation_manifest', 'json'] comme
// n'importe quelle adresse. Or les oracles préfixent volontiers leurs findings de
// portée globale par le nom du fichier (« prisme.json: AUCUNE exigence actionnable »).
// Sans cette garde, on tenterait de réparer un champ `json` : `classer` le refuserait
// (aucun conteneur parent), donc rien de dangereux — mais la CLASSIFICATION serait
// fausse, et c'est elle qu'on lit pour décider s'il faut régénérer. Un diagnostic faux
// coûte plus cher qu'une réparation refusée.
const _EXTENSION_FICHIER = /\.(json|mjs|cjs|js|ts|py|ya?ml|md|txt|gd|rs|jsonl)$/i;

/**
 * Transforme les findings texte d'un oracle en findings structurés.
 * @param {string[]} problems
 * @returns {Array<{brut:string, chemin:string|null, raison:string, classe:'champ'|'structurel'}>}
 */
export function analyserFindings(problems) {
  return (problems || []).map((brut) => {
    const i = String(brut).indexOf(':');
    if (i < 0) return { brut, chemin: null, raison: String(brut), classe: 'structurel' };
    const chemin = String(brut).slice(0, i).trim();
    const raison = String(brut).slice(i + 1).trim();
    const estChemin = _CHEMIN.test(chemin) && !_EXTENSION_FICHIER.test(chemin)
      && segments(chemin).length > 0;
    return {
      brut,
      chemin: estChemin ? chemin : null,
      raison,
      classe: estChemin ? 'champ' : 'structurel',
    };
  });
}

/**
 * Liste blanche des chemins réparables : findings de classe « champ » dont
 * l'emplacement existe réellement dans l'artefact (le conteneur parent est là).
 * Un chemin qui désigne un élément de tableau inexistant n'est pas réparable.
 * @param {object} artefact
 * @param {Array} findings sortie d'analyserFindings
 * @returns {{reparables:Array, non_reparables:Array}}
 */
export function classer(artefact, findings) {
  const reparables = [];
  const non_reparables = [];
  for (const f of findings) {
    if (f.classe !== 'champ') { non_reparables.push(f); continue; }
    const segs = segments(f.chemin);
    const parent = segs.slice(0, -1);
    const conteneur = parent.length === 0 ? artefact : lire(artefact, cheminDe(parent));
    if (conteneur === null || typeof conteneur !== 'object') {
      non_reparables.push({ ...f, motif_non_reparable: 'le conteneur parent n\'existe pas' });
    } else {
      reparables.push(f);
    }
  }
  return { reparables, non_reparables };
}

/**
 * Recompose un chemin depuis ses segments (inverse de `segments`).
 * @param {Array<string|number>} segs
 * @returns {string}
 */
export function cheminDe(segs) {
  let out = '';
  for (const s of segs) {
    if (typeof s === 'number') out += `[${s}]`;
    else out += out ? `.${s}` : s;
  }
  return out;
}

// --- réparation ------------------------------------------------------------------

/**
 * Valeurs SCALAIRES voisines d'un champ (mêmes frères et sœurs dans le conteneur
 * parent), tronquées. C'est le `VALID_CONTEXT` du prompt de réparation : assez pour
 * écrire une valeur cohérente avec ce qui l'entoure, jamais l'artefact entier — c'est
 * ce qui garde l'appel au coût d'un correctif et non d'une régénération.
 * @param {object} artefact
 * @param {string} chemin
 * @param {number} maxCar troncature par valeur
 * @returns {Record<string, unknown>}
 */
export function contexteVoisin(artefact, chemin, maxCar = 160) {
  const segs = segments(chemin);
  const parent = segs.slice(0, -1);
  const conteneur = parent.length === 0 ? artefact : lire(artefact, cheminDe(parent));
  if (conteneur === null || typeof conteneur !== 'object') return {};
  const cible = segs[segs.length - 1];
  const out = {};
  for (const [k, v] of Object.entries(conteneur)) {
    if (String(k) === String(cible)) continue;
    if (v === null || typeof v !== 'object') {
      out[k] = typeof v === 'string' && v.length > maxCar ? `${v.slice(0, maxCar)}…` : v;
    }
  }
  return out;
}

/**
 * Prompt de réparation d'UN SEUL champ (format imposé) : FIELD_TO_REPAIR /
 * FAILURE_REASON / VALID_CONTEXT / FORBIDDEN, sortie `{"path", "value"}`.
 *
 * Un champ par appel, et non un lot : la sortie attendue est alors une paire, pas un
 * document. Un modèle à qui on demande un document rend un document — et un document
 * peut contenir n'importe quoi d'autre. Le format le plus étroit est la contrainte la
 * plus solide.
 *
 * `VALID_CONTEXT` ne donne que les valeurs SCALAIRES voisines (mêmes frère et sœurs
 * dans le conteneur parent), tronquées : de quoi écrire une valeur cohérente, jamais
 * l'artefact entier — c'est ce qui garde le coût de l'appel au niveau d'un correctif.
 *
 * @param {object} finding {chemin, raison}
 * @param {object} artefact
 * @param {object} contexte {etape, game_id}
 * @returns {string}
 */
export function construirePromptChamp(finding, artefact, contexte = {}) {
  const voisins = contexteVoisin(artefact, finding.chemin);
  return [
    'Un contrôle mécanique a rejeté UN champ de ton artefact. Tu répares CE champ, rien d\'autre.',
    contexte.etape ? `\nSTEP: ${contexte.etape}` : '',
    contexte.game_id ? `GAME: ${contexte.game_id}` : '',
    `\nFIELD_TO_REPAIR:\n${finding.chemin}`,
    `\nFAILURE_REASON:\n${finding.raison}`,
    `\nVALID_CONTEXT (valeurs voisines déjà valides, pour rester cohérent) :\n${JSON.stringify(voisins, null, 1)}`,
    '\nFORBIDDEN:\n- ne touche à AUCUN autre chemin que celui ci-dessus',
    '- ne rends pas l\'artefact complet',
    '- pas de chaîne vide, pas de « ??? », pas le nom du champ recopié',
    '\nRends EXACTEMENT cet objet, et rien d\'autre :',
    '```json',
    '{ "path": "<le chemin ci-dessus, à l\'identique>", "value": <la valeur corrigée> }',
    '```',
  ].filter(Boolean).join('\n');
}

/**
 * (Conservée pour les appels groupés hors driver.) Prompt de réparation d'un LOT de
 * champs. Le driver utilise `construirePromptChamp` — un champ par appel.
 * @param {Array} reparables
 * @param {object} contexte
 * @returns {string}
 */
export function construirePromptReparation(reparables, contexte = {}) {
  const lignes = reparables.map((f) => `- ${f.chemin}\n    motif du rejet : ${f.raison}`);
  return [
    'Un contrôle mécanique a rejeté certains champs de ton artefact.',
    contexte.etape ? `\nÉTAPE : ${contexte.etape}` : '',
    contexte.game_id ? `JEU : ${contexte.game_id}` : '',
    '\nCHAMPS REJETÉS (et uniquement ceux-là) :',
    ...lignes,
    // JAMAIS de gabarit pré-rempli de chaînes vides ici. Mesuré le 2026-08-04 : à
    // qui on montre {"champ": ""}, Qwen renvoie {"champ": ""} — il recopie l'exemple
    // (comportement déjà observé sur la mutation M-ws2 du World Scan). Le gabarit
    // rendait la boucle bavarde ET inutile : 3 cycles, 81 tokens, 0 problème résolu.
    // On décrit donc la FORME sans jamais montrer une valeur copiable.
    '\nRends un objet JSON dont les clés sont EXACTEMENT les chemins ci-dessus, et dont',
    'chaque valeur est la valeur CORRIGÉE du champ — du contenu réel, jamais une chaîne',
    'vide, jamais un point d\'interrogation, jamais le nom du champ recopié.',
    '\nExemple de FORME (les clés et valeurs ci-dessous sont fictives, ne les reprends pas) :',
    '```json',
    '{ "un.chemin[0].quelconque": "une phrase de contenu reel" }',
    '```',
    '\nNe renvoie aucun autre champ : tout ce qui n\'est pas dans la liste sera ignoré.',
  ].filter(Boolean).join('\n');
}

/**
 * Extrait le dernier bloc ```json``` d'une sortie modèle (même règle déterministe que
 * run_real.extract_json_payload : jamais un LLM pour relire un LLM).
 * @param {string} texte
 * @returns {object|null}
 */
export function extrairePatch(texte) {
  const blocs = [...String(texte || '').matchAll(/```json\s*([\s\S]*?)```/g)];
  const candidats = blocs.length > 0 ? blocs.map((m) => m[1]) : [String(texte || '')];
  for (let i = candidats.length - 1; i >= 0; i -= 1) {
    try {
      const d = JSON.parse(candidats[i]);
      if (d !== null && typeof d === 'object' && !Array.isArray(d)) return d;
    } catch { /* candidat suivant */ }
  }
  return null;
}

/**
 * Applique un patch à l'artefact, SOUS LISTE BLANCHE. Retourne l'artefact réparé
 * (copie — l'original n'est jamais muté) et la comptabilité complète.
 *
 * `regressions` doit TOUJOURS être vide : la liste blanche l'empêche par construction.
 * Il est calculé quand même, par diff des chemins-feuilles avant/après — un invariant
 * qu'on se contente de supposer n'est pas un invariant.
 *
 * @param {object} artefact
 * @param {object} patch {chemin: valeur}
 * @param {string[]} cheminsAutorises
 * @returns {{artefact:object, repaired_fields:string[], preserved_fields:string[],
 *            rejected_keys:string[], echecs:string[], regressions:string[]}}
 */
export function appliquerReparation(artefact, patch, cheminsAutorises) {
  const avant = cheminsFeuilles(artefact);
  const copie = structuredClone(artefact);
  const autorises = new Set(cheminsAutorises);
  const repaired_fields = [];
  const rejected_keys = [];
  const echecs = [];

  for (const [cle, valeur] of Object.entries(patch || {})) {
    if (!autorises.has(cle)) { rejected_keys.push(cle); continue; }
    if (ecrire(copie, cle, valeur)) repaired_fields.push(cle);
    else echecs.push(cle);
  }

  const apres = cheminsFeuilles(copie);
  const regressions = [];
  for (const [chemin, val] of avant.entries()) {
    if (!apres.has(chemin) || apres.get(chemin) !== val) {
      if (!autorises.has(chemin)) regressions.push(chemin);
    }
  }
  const preserved_fields = [...avant.keys()].filter((p) => !repaired_fields.includes(p));

  return { artefact: copie, repaired_fields, preserved_fields, rejected_keys, echecs, regressions };
}

// --- boucle ----------------------------------------------------------------------

/**
 * REPAIR_LOOP_V1. `valider(artefact) -> {ok, problems[]}` (synchrone OU asynchrone —
 * son résultat est toujours `await`é, ce qui permet de brancher directement les
 * oracles du dépôt, qui lisent des fichiers) et
 * `appelerModele(prompt) -> string|null` sont INJECTÉS : ce module n'appelle jamais
 * ni oracle ni modèle de lui-même.
 *
 * S'arrête dès que l'oracle passe, ou quand plus aucun finding n'est réparable
 * localement, ou au bout de `maxCycles`. Ne boucle JAMAIS sans borne : un cycle qui
 * ne répare rien met fin à la boucle (sinon on paierait indéfiniment le même échec).
 *
 * @param {object} opts {artefact, valider, appelerModele, maxCycles, contexte}
 * @returns {Promise<{ok:boolean, artefact:object, cycles:Array, resume:object}>}
 */
export async function boucleReparation({
  artefact, valider, appelerModele, maxCycles = 3, contexte = {},
}) {
  let courant = structuredClone(artefact);
  const cycles = [];
  let resultat = await valider(courant);

  for (let n = 1; resultat.ok !== true && n <= maxCycles; n += 1) {
    const findings = analyserFindings(resultat.problems);
    const { reparables, non_reparables } = classer(courant, findings);

    if (reparables.length === 0) {
      cycles.push({ cycle: n, arret: 'aucun finding reparable localement', non_reparables: non_reparables.map((f) => f.brut) });
      break;
    }

    // UN APPEL PAR CHAMP. Un modèle à qui on demande un document rend un document, et
    // un document peut contenir n'importe quoi d'autre ; à qui on demande une paire
    // {path, value}, il rend une paire. Le format le plus étroit est la contrainte la
    // plus solide — et le `path` rendu est re-vérifié contre le chemin demandé, donc
    // même une paire mal adressée n'entre pas dans le patch.
    const patch = {};
    let promptCars = 0;
    for (const f of reparables) {
      const prompt = construirePromptChamp(f, courant, contexte);
      promptCars += prompt.length;
      // eslint-disable-next-line no-await-in-loop -- séquentiel à dessein : chaque
      // champ est réparé avec le contexte des voisins, dont ceux déjà réparés.
      const paire = extrairePatch(await appelerModele(prompt));
      if (paire === null) continue;
      if (paire.path !== f.chemin) continue;      // paire mal adressée : ignorée
      if (!('value' in paire)) continue;
      patch[f.chemin] = paire.value;
    }

    if (Object.keys(patch).length === 0) {
      cycles.push({ cycle: n, arret: 'le modele n\'a rendu aucune paire {path, value} exploitable', prompt_chars: promptCars });
      break;
    }

    const app = appliquerReparation(courant, patch, reparables.map((f) => f.chemin));
    const avantOk = resultat.problems.length;

    // REJET SI RÉGRESSION. La liste blanche l'empêche par construction, mais si elle
    // devait un jour laisser passer quelque chose, on ne garde PAS l'artefact : on
    // revient au snapshot. Une garantie qui se contente de signaler sa propre
    // violation n'est pas une garantie.
    if (app.regressions.length > 0) {
      cycles.push({
        cycle: n,
        regressions: app.regressions,
        arret: `REGRESSION detectee sur ${app.regressions.length} chemin(s) hors liste blanche — `
          + 'artefact restaure a son etat d\'avant reparation, aucune ecriture conservee',
      });
      break; // `courant` reste l'artefact d'avant : app.artefact est jeté
    }

    courant = app.artefact;
    resultat = await valider(courant);

    cycles.push({
      cycle: n,
      cibles: reparables.map((f) => f.chemin),
      repaired_fields: app.repaired_fields,
      rejected_keys: app.rejected_keys,
      echecs: app.echecs,
      regressions: app.regressions,
      non_reparables: non_reparables.map((f) => f.brut),
      problems_avant: avantOk,
      problems_apres: resultat.problems.length,
      prompt_chars: promptCars,
      appels_modele: reparables.length,
    });

    if (app.repaired_fields.length === 0) {
      cycles.push({ cycle: n, arret: 'aucun champ effectivement repare — arret pour ne pas repayer le meme echec' });
      break;
    }

    // CRITÈRE DE CONVERGENCE. « Des champs ont été écrits » ne veut pas dire « ça
    // s'améliore » : un champ réparé avec une valeur elle-même invalide compte comme
    // écrit et ne résout rien. Mesuré le 2026-08-04 : la boucle a payé 3 cycles et
    // 81 tokens pour un compte de problèmes rigoureusement identique (2 -> 2 -> 2).
    // Le seul signal honnête de progrès est la DÉCROISSANCE STRICTE du nombre de
    // problèmes remontés par l'oracle.
    if (resultat.ok !== true && resultat.problems.length >= avantOk) {
      cycles.push({
        cycle: n,
        arret: `aucun progres mesure (${avantOk} -> ${resultat.problems.length} problemes) — `
          + 'des champs ont ete ecrits mais l\'oracle n\'en accepte pas davantage ; '
          + 'la reparation locale ne converge pas sur ce cas, il faut regenerer ou revoir le contrat',
      });
      break;
    }
  }

  return {
    ok: resultat.ok === true,
    artefact: courant,
    cycles,
    resume: {
      cycles_utilises: cycles.filter((c) => c.repaired_fields).length,
      champs_repares: cycles.flatMap((c) => c.repaired_fields || []),
      regressions: cycles.flatMap((c) => c.regressions || []),
      problems_restants: resultat.problems ? resultat.problems.length : 0,
    },
  };
}

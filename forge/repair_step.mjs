#!/usr/bin/env node
// repair_step.mjs — POINT D'ENTRÉE UNIQUE de la boucle de réparation pour une étape
// amont de la Forge :  oracle → problems[] → réparation ciblée → oracle → mesure.
//
// Pourquoi une CLI Node et pas un portage Python : les 5 oracles amont SONT en Node.
// Réécrire la boucle côté Python créerait deux implémentations de la même règle, donc
// deux vérités qui divergeront. Le driver Python appelle ce point d'entrée en
// sous-processus, exactement comme il appelle déjà `godot_oracle.mjs` ou
// `check_worldscan.mjs` — et la logique reste à un seul endroit.
//
// PÉRIMÈTRE : uniquement les oracles d'AVANT-BUILD. `check_architecture` et
// `check_wiremap` (post-build, static_oracles.py) ne sont PAS touchés : ce sont les
// oracles de preuve finale, on ne « répare » pas un artefact pour leur plaire, on
// corrige le code.
//
// Usage :
//   node repair_step.mjs <etape> <run_dir> [--model <id>] [--max-cycles N] [--no-repair]
// Étapes : s2-worldscan · s1-prisme · s3-decompo · s4-archi-contract · s5-wiremap-contract
// Exit 0 = oracle OK (avec ou sans réparation) · 1 = oracle toujours FAIL (escalade)
//        · 2 = usage / étape inconnue.
import { readFile, writeFile } from 'node:fs/promises';
import { resolve, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  boucleReparation, contexteVoisin, extrairePatch, appliquerReparation, lire, tousLesFindings,
} from './repair_loop.mjs';
import {
  mesurerSignalSemantique, ciblesDuSignal, promptReparationSignal,
} from './oracle_quality.mjs';
import {
  mesurerCroise, STRATEGIES_ACTIVES, cibleEtSource, promptReparationCroisee,
} from './cross_field_quality.mjs';
import { checkWorldScanFile } from './check_worldscan.mjs';
import { checkPrismeFile } from './check_prisme_manifest.mjs';
import { checkDecompoFiles } from './check_decompo.mjs';
import { checkBlueprintFiles } from './check_blueprint_contract.mjs';
import { checkWiremapContractFiles } from './check_wiremap_contract.mjs';

const LM_URL = process.env.FORGE_REPAIR_URL || 'http://localhost:1234/v1/chat/completions';
const LM_MODELE = process.env.FORGE_REPAIR_MODEL || 'qwen2.5-14b-instruct';

/**
 * Table étape -> {artefact, oracle}. `artefact` est le fichier RÉPARABLE (celui que
 * l'étape produit) ; les autres fichiers cités sont des entrées amont déjà validées,
 * jamais modifiées ici.
 */
export const ETAPES = {
  's2-worldscan': {
    artefact: 'worldscan.json',
    oracle: 'check_worldscan',
    valider: (dir) => checkWorldScanFile(join(dir, 'worldscan.json')),
  },
  's1-prisme': {
    artefact: 'prisme.json',
    oracle: 'check_prisme_manifest',
    valider: (dir) => checkPrismeFile(join(dir, 'prisme.json'), join(dir, 'worldscan.json')),
  },
  's3-decompo': {
    artefact: 'featuremap.json',
    oracle: 'check_decompo',
    valider: (dir) => checkDecompoFiles(join(dir, 'featuremap.json'), join(dir, 'prisme.json')),
  },
  's4-archi-contract': {
    artefact: 'blueprint.json',
    oracle: 'check_blueprint_contract',
    valider: (dir) => checkBlueprintFiles(join(dir, 'blueprint.json'), join(dir, 'featuremap.json')),
  },
  's5-wiremap-contract': {
    artefact: 'wiremap.json',
    oracle: 'check_wiremap_contract',
    valider: (dir) => checkWiremapContractFiles(join(dir, 'wiremap.json'), join(dir, 'featuremap.json')),
  },
};

/**
 * Appelle le modèle réparateur (API OpenAI-compatible locale). Rend `null` sur toute
 * anomalie — jamais d'exception : un réparateur injoignable doit dégrader en « pas de
 * réparation », pas faire tomber l'étape.
 * @param {string} prompt
 * @param {{tokens:number, appels:number}} compteur muté sur place
 * @returns {Promise<string|null>}
 */
export function faireAppelModele(compteur) {
  return async (prompt) => {
    compteur.appels += 1;
    try {
      const r = await fetch(LM_URL, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          model: LM_MODELE,
          temperature: 0,
          max_tokens: 400,
          messages: [
            { role: 'system', content: 'Tu répares UN champ. Tu réponds UNIQUEMENT par un bloc ```json``` contenant {"path", "value"}.' },
            { role: 'user', content: prompt },
          ],
        }),
      });
      if (!r.ok) return null;
      const d = await r.json();
      compteur.tokens += d.usage?.completion_tokens ?? 0;
      return d.choices?.[0]?.message?.content ?? null;
    } catch {
      return null;
    }
  };
}

/**
 * PHASE 2 — signal sémantique (ORACLE QUALITY LAYER, advisory).
 *
 * Ne tourne QUE si la phase structurelle a réussi : réparer le sens d'un artefact
 * structurellement invalide reviendrait à peindre un mur qui n'est pas monté.
 *
 * INVARIANT DUR : la réparation sémantique ne doit JAMAIS casser la structure. Après
 * chaque écriture, l'oracle mécanique est rejoué ; s'il tombe, on revient à l'artefact
 * d'avant. Le signal sémantique est un signal EN PLUS — il n'a pas le droit de coûter
 * ce qui était déjà acquis.
 *
 * @param {object} opts
 * @returns {Promise<object>}
 */
export async function phaseQualite({ runDir, cheminArtefact, spec, appelerModele, actif }) {
  const avant = JSON.parse(await readFile(cheminArtefact, 'utf-8'));
  const mesureAvant = mesurerSignalSemantique(avant);
  let courant = structuredClone(avant);
  const changes = [];
  let rollback = false;
  let motifRollback = null;

  // Écrit l'artefact, rejoue l'oracle MÉCANIQUE, et annule si la structure tombe.
  // Le signal de qualité est un signal EN PLUS : il n'a jamais le droit de coûter ce
  // qui était déjà acquis.
  const appliquerSousGardeStructurelle = async (chemin, valeur) => {
    const essai = appliquerReparation(courant, { [chemin]: valeur }, [chemin]);
    if (essai.regressions.length > 0 || essai.repaired_fields.length === 0) return false;
    await writeFile(cheminArtefact, JSON.stringify(essai.artefact, null, 1), 'utf-8');
    const structure = await spec.valider(runDir);
    if (!structure.ok) {
      await writeFile(cheminArtefact, JSON.stringify(courant, null, 1), 'utf-8');
      rollback = true;
      motifRollback = `la reparation de ${chemin} a casse l oracle mecanique`;
      return false;
    }
    courant = essai.artefact;
    changes.push(chemin);
    return true;
  };

  // --- V1 : signaux internes (discriminance, langue, recopie) ---
  if (actif && mesureAvant.verdict !== 'PASS') {
    for (const signal of mesureAvant.signaux) {
      if (rollback) break;
      for (const chemin of ciblesDuSignal(signal)) {
        if (rollback) break;
        const prompt = promptReparationSignal(
          signal, chemin, contexteVoisin(courant, chemin), lire(courant, chemin),
        );
        // eslint-disable-next-line no-await-in-loop -- séquentiel : chaque réparation
        // change le contexte de la suivante (deux champs ne doivent pas converger).
        const paire = extrairePatch(await appelerModele(prompt));
        if (paire === null || paire.path !== chemin || !('value' in paire)) continue;
        // eslint-disable-next-line no-await-in-loop
        await appliquerSousGardeStructurelle(chemin, paire.value);
      }
    }
  }

  // --- V2 : DÉPLACEMENTS de défaut ---
  // Mesurés APRÈS les réparations V1, parce que c'est la réparation qui les crée :
  // chercher une trace avant le passage n'a pas de sens. Et mesurés MÊME quand V1 n'a
  // rien signalé — une contamination inter-champs peut exister sans aucun signal V1,
  // c'est précisément le cas qui a motivé cette couche.
  const croiseAvant = mesurerCroise(courant, STRATEGIES_ACTIVES);
  if (actif && !rollback) {
    for (const sig of croiseAvant.signaux) {
      if (rollback) break;
      const roles = cibleEtSource(sig);
      const prompt = promptReparationCroisee(
        sig, roles, lire(courant, roles.source), contexteVoisin(courant, roles.target),
      );
      // eslint-disable-next-line no-await-in-loop
      const paire = extrairePatch(await appelerModele(prompt));
      if (paire === null || paire.path !== roles.target || !('value' in paire)) continue;
      // eslint-disable-next-line no-await-in-loop
      await appliquerSousGardeStructurelle(roles.target, paire.value);
    }
  }

  await writeFile(cheminArtefact, JSON.stringify(courant, null, 1), 'utf-8');
  const mesureApres = mesurerSignalSemantique(courant);
  const croiseApres = mesurerCroise(courant, STRATEGIES_ACTIVES);
  return {
    SEMANTIC_SIGNAL_BEFORE: mesureAvant.verdict,
    SEMANTIC_SIGNAL_AFTER: mesureApres.verdict,
    SIGNAUX_AVANT: mesureAvant.compte,
    SIGNAUX_APRES: mesureApres.compte,
    CROSS_FIELD_BEFORE: croiseAvant.verdict,
    CROSS_FIELD_AFTER: croiseApres.verdict,
    CROSS_FIELD_SIGNAUX: croiseAvant.signaux.map((x) => ({ ...cibleEtSource(x), detail: x.detail })),
    FIELDS_CHANGED: changes,
    CLASSES: [...new Set([...mesureAvant.signaux.map((x) => x.classe),
      ...(croiseAvant.signaux.length ? ['cross_field_copy'] : [])])],
    ROLLBACK: rollback,
    ROLLBACK_MOTIF: motifRollback,
    REPARE: changes.length > 0,
  };
}

/**
 * Exécute oracle → (réparation) → oracle pour une étape, et rend le bloc de mesure.
 * `appelerModele` est injecté (testable hors-ligne) ; `reparer:false` mesure l'oracle
 * seul, ce qui donne la colonne « worker seul » d'une comparaison.
 * @param {object} opts {etape, runDir, appelerModele, maxCycles, reparer}
 * @returns {Promise<object>} bloc de mesure
 */
export async function reparerEtape({
  etape, runDir, appelerModele, maxCycles = 3, reparer = true, worker = LM_MODELE,
  qualiteActive = true,
}) {
  const spec = ETAPES[etape];
  if (!spec) throw new Error(`etape inconnue: ${etape} (attendu: ${Object.keys(ETAPES).join(' | ')})`);

  const cheminArtefact = join(runDir, spec.artefact);
  const t0 = Date.now();
  const compteur = { tokens: 0, appels: 0 };
  const appel = appelerModele || faireAppelModele(compteur);

  // Le validateur écrit l'artefact courant AVANT de lancer l'oracle : les oracles du
  // dépôt lisent des FICHIERS, pas des objets. C'est aussi ce qui fait que l'artefact
  // sur disque reflète toujours ce qui a été jugé — jamais un état intermédiaire
  // invisible.
  const valider = async (art) => {
    await writeFile(cheminArtefact, JSON.stringify(art, null, 1), 'utf-8');
    const r = await spec.valider(runDir);
    // D-1-tuyau (GO Pierre 2026-09-03) — DEFAUT MESURE sur RUN M et M ter.
    // Cette enveloppe rendait `{ ok, problems }` et JETAIT les trois autres listes de
    // `check_wiremap_contract` (`capacites_non_couvertes`, `couverture_fantome`,
    // `maillon_non_lie`) AVANT que `repair_loop` ne les voie. Consequence : la boucle
    // remplissait les `couvre` manquants, `problems` tombait de 9 a 0 — recu
    // « PROBLEMS_BEFORE 9 -> AFTER 0 » — pendant que `couverture_fantome` montait de 0 a 9,
    // hors de son champ de vision. Le defaut n'etait pas repare, il etait DEPLACE.
    //
    // Le correctif D-1 (`tousLesFindings`, 2026-09-02) portait sur le COLLECTEUR et
    // s'appliquait donc a un objet DEJA AMPUTE : il n'a rien protege, et M ter l'a montre.
    // On repare ici le TUYAU. Ce qui suit passe le resultat COMPLET ; `problems` reste
    // garanti present pour les appelants qui ne lisent que lui.
    return { ...r, ok: r.ok, problems: r.problems || [] };
  };

  let artefact;
  try {
    artefact = JSON.parse(await readFile(cheminArtefact, 'utf-8'));
  } catch (err) {
    return {
      STATUS: 'ARTEFACT_ILLISIBLE', WORKER: worker, STEP: etape, ORACLE: spec.oracle,
      PROBLEMS_BEFORE: null, PROBLEMS_AFTER: null, TOKENS: 0, TIME_MS: Date.now() - t0,
      FIELDS_CHANGED: [], FIELDS_PRESERVED: 0, REGRESSION: [],
      DETAIL: `${cheminArtefact} : ${err.message}`,
    };
  }

  const avant = await valider(artefact);
  if (avant.ok) {
    return {
      QUALITE: await phaseQualite({ runDir, cheminArtefact, spec, appelerModele: appel, actif: qualiteActive }),
      STATUS: 'OK_SANS_REPARATION', WORKER: worker, STEP: etape, ORACLE: spec.oracle,
      PROBLEMS_BEFORE: 0, PROBLEMS_AFTER: 0, TOKENS: 0, TIME_MS: Date.now() - t0,
      FIELDS_CHANGED: [], FIELDS_PRESERVED: null, REGRESSION: [], CYCLES: 0,
    };
  }
  if (!reparer) {
    return {
      STATUS: 'FAIL_SANS_REPARATION', WORKER: worker, STEP: etape, ORACLE: spec.oracle,
      PROBLEMS_BEFORE: avant.problems.length, PROBLEMS_AFTER: avant.problems.length,
      TOKENS: 0, TIME_MS: Date.now() - t0, FIELDS_CHANGED: [], FIELDS_PRESERVED: null,
      REGRESSION: [], CYCLES: 0, PROBLEMS: avant.problems,
    };
  }

  const r = await boucleReparation({
    artefact, valider, appelerModele: appel, maxCycles,
    contexte: { etape, game_id: artefact.game_id || runDir.split(/[\\/]/).pop() },
  });

  // L'artefact retenu est réécrit une dernière fois : si la boucle a annulé une
  // réparation (régression), c'est l'état d'AVANT qui doit se retrouver sur disque.
  await writeFile(cheminArtefact, JSON.stringify(r.artefact, null, 1), 'utf-8');
  const apres = await spec.valider(runDir);

  const dernier = r.cycles[r.cycles.length - 1] || {};
  const qualite = await phaseQualite({
    runDir, cheminArtefact, spec, appelerModele: appel, actif: qualiteActive && r.ok,
  });

  return {
    QUALITE: qualite,
    STATUS: r.ok ? 'REPARE' : 'ESCALADE',
    WORKER: worker,
    STEP: etape,
    ORACLE: spec.oracle,
    // D-1-tuyau : compter la MEME chose que la boucle. Avant, le recu annoncait un
    // progres (9 -> 0) mesure sur la seule liste `problems`, alors que le total des
    // findings de l'oracle etait inchange. Un recu qui compte autrement que le mecanisme
    // qu'il decrit est un recu qui ment sans mentir.
    PROBLEMS_BEFORE: tousLesFindings(avant).length,
    PROBLEMS_AFTER: tousLesFindings(apres).length,
    TOKENS: compteur.tokens,
    APPELS_MODELE: compteur.appels,
    TIME_MS: Date.now() - t0,
    FIELDS_CHANGED: r.resume.champs_repares,
    // Périmètre RÉELLEMENT autorisé par la liste blanche interne, union des cycles.
    // Champ ADDITIF (2026-08-04) : rien ne le lisait, aucune métrique n'en dépend. Il
    // existe parce que la trace `repair.result` doit pouvoir dire ce qui était
    // autorisé, pas seulement ce qui a été écrit — sinon « 2 champs modifiés » ne se
    // distingue pas de « 2 champs modifiés sur 7 permis ».
    ALLOWED_FIELDS: [...new Set(r.cycles.flatMap((c) => c.cibles || []))],
    FIELDS_PRESERVED: null,
    REGRESSION: r.resume.regressions,
    CYCLES: r.resume.cycles_utilises,
    ARRET: dernier.arret || null,
    PROBLEMS: r.ok ? [] : (apres.problems || []),
  };
}

// ---- CLI ----
const isMain = process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isMain) {
  const argv = process.argv.slice(2);
  const opt = (nom, def) => {
    const i = argv.indexOf(nom);
    return i >= 0 ? argv[i + 1] : def;
  };
  const pos = argv.filter((a, i) => !a.startsWith('--') && argv[i - 1] !== '--model' && argv[i - 1] !== '--max-cycles');

  if (pos.length < 2 || !ETAPES[pos[0]]) {
    console.error('usage: node repair_step.mjs <etape> <run_dir> [--model <id>] [--max-cycles N] [--no-repair]');
    console.error(`etapes: ${Object.keys(ETAPES).join(' | ')}`);
    process.exit(2);
  }

  (async () => {
    const mesure = await reparerEtape({
      etape: pos[0],
      runDir: pos[1],
      maxCycles: Number(opt('--max-cycles', 3)),
      reparer: !argv.includes('--no-repair'),
      worker: opt('--model', LM_MODELE),
    });
    // Bloc de mesure lisible puis JSON stable pour l'appelant mécanique (driver).
    for (const cle of ['STATUS', 'WORKER', 'STEP', 'ORACLE', 'PROBLEMS_BEFORE', 'PROBLEMS_AFTER',
      'TOKENS', 'TIME_MS', 'CYCLES', 'FIELDS_CHANGED', 'REGRESSION']) {
      console.error(`${cle}: ${JSON.stringify(mesure[cle])}`);
    }
    console.log(JSON.stringify(mesure, null, 1));
    // `process.exitCode` et NON `process.exit()` : la boucle a fait des `fetch`, et
    // tuer le process pendant qu'une socket keep-alive est encore ouverte fait
    // planter libuv à la sortie (« Assertion failed: !(handle->flags &
    // UV_HANDLE_CLOSING) », observé le 2026-08-04). Le code de sortie est le même,
    // mais Node ferme proprement ses poignées avant de rendre la main — un composant
    // appelé par le driver ne doit pas se terminer sur un crash, même après avoir
    // écrit un résultat correct : l'appelant ne peut plus distinguer les deux.
    process.exitCode = (mesure.STATUS === 'OK_SANS_REPARATION' || mesure.STATUS === 'REPARE') ? 0 : 1;
  })();
}

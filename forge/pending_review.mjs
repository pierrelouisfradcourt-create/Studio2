#!/usr/bin/env node
// pending_review.mjs — Knowledge Resolver V1, pièce 2/2 (contrat :
// docs/forge/KNOWLEDGE_RESOLVER_V1_PROTOCOL.md, statut PROPOSED en attente gate Pierre).
//
// Rôle : lecteur READ-ONLY qui agrège les 3 files de propositions dormantes existantes
// (aucune n'a de lecteur aujourd'hui — 0 % lues) et calcule des FEATURES DÉTERMINISTES
// BRUTES : fichier source, sujet d'origine, âge en jours, nombre d'occurrences du même
// sujet, champs de reproduction si présents. AUCUN score pondéré, AUCUN pourcentage de
// confiance — interdit par le cadre ratifié (le score advisory viendra plus tard, jamais
// juge de promotion). Les colonnes Accept/Reject/Postpone sont des colonnes VIDES pour
// Pierre en session ; cet outil ne stocke ni ne calcule aucune décision.
//
// Fichiers agrégés (chemins réels, schémas DIFFÉRENTS — voir plus bas) :
//   EVIDENCE/reports/forge_ledger_proposals.jsonl   — clé sujet: "project"     · horodatage: "ts" (epoch s)
//   EVIDENCE/reports/forge_project_proposals.jsonl  — clé sujet: "project"     · horodatage: "ts" (epoch s)
//   EVIDENCE/reports/error_proposals.jsonl          — clé sujet: "error_signature" · horodatage: "created_ts" (epoch s)
//   EVIDENCE/reports/forge_bible_proposals.jsonl    — clé sujet: "project"     · horodatage: "ts" (epoch s)
//     (4e file, `studio_link.propose_bible_entry` — PROPOSE-ONLY, promotion 100% humaine
//     vers EVIDENCE/runs/<projet>/PROJECT_BIBLE.md ; record réel : project/kind/decision/
//     rationale/status/ts — voir PASSTHROUGH_FIELDS ci-dessous pour kind/rationale)
//   EVIDENCE/reports/forge_brick_proposals.jsonl    — clé sujet: "brick_id"    · horodatage: "ts" (epoch s)
//     (5e file, `studio_link.propose_brick` — le dépositaire, PROPOSE-ONLY, ratification
//     Pierre 2026-07-23 ; promotion 100% humaine vers knowledge_base/catalog.json ; record
//     réel : type("brick")/brick_id/run_id/project/kind/function/path/status/ts — clé sujet
//     "brick_id" (pas "project") car deux propositions du MÊME projet peuvent porter des
//     briques DIFFÉRENTES — voir PASSTHROUGH_FIELDS ci-dessous pour brick_id/kind/function/path)
//   Un fichier absent est signalé ABSENT — jamais une erreur fatale.
//
// Dédoublonnage ("occurrences du même sujet") : DOCUMENTÉ ainsi — deux items du MÊME
// fichier source partageant la même clé sujet (project, ou error_signature) sont considérés
// comme le même sujet. On ne dédoublonne PAS across les fichiers de file (leurs clés ne sont pas
// comparables : un "project" de forge_ledger_proposals et un "error_signature" ne désignent
// pas la même notion). Si le champ clé est absent sur un item, une clé de repli est utilisée
// (voir KEY_FALLBACK_PREFIX) et l'item est marqué `key_fallback: true` — jamais un crash.
//
// Tri déterministe (documenté, proposé) : occurrences décroissantes, puis âge décroissant
// (le plus ancien remonte), puis fichier source (ordre alphabétique), puis ordre de lecture
// original — stable, reproductible à froid.
//
// Affichage : table lisible humain (stderr) plafonnée aux 5 premiers items + JSON complet
// (stdout) avec le compte total TOUJOURS présent (aucun volume caché derrière le plafond).
//
// Usage : node forge/pending_review.mjs [--repo-root <path>] [--top N]
// Exit codes : 0 = agrégation exécutée (y compris 0 item, y compris fichiers absents) ·
//              2 = erreur interne inattendue.
import { existsSync, readFileSync } from 'node:fs';
import { join, dirname, resolve, relative } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

// `match_fields` — SOURCE UNIQUE de la regle de rapprochement decision->proposition.
// Avant le 2026-08-10 cette regle vivait UNIQUEMENT dans apply_decisions.MATCH_FIELDS, qui ne
// couvrait que 3 des 6 queues : une decision visant bible/brick/capability_gap tombait en
// `orphaned` par le garde-fou apply_decisions.mjs:251-255, quel que soit son contenu — donc
// STRUCTURELLEMENT indecidable (audit boucle de revue 2026-08-10). La regle est desormais
// portee par la queue elle-meme et apply_decisions la DERIVE : une queue ajoutee ici ne peut
// plus naitre sans regle de rapprochement. Champs choisis UNIQUEMENT parmi ceux reellement
// ecrits par le producteur correspondant dans studio_link.py — jamais un champ suppose.
// Egalite stricte, essayes dans l'ordre, aucun fuzzy-match (cf. matchLines).
export const QUEUE_FILES = [
  { id: 'forge_ledger_proposals', path: 'EVIDENCE/reports/forge_ledger_proposals.jsonl', subject_field: 'project', ts_field: 'ts', match_fields: ['run_id', 'project'] },
  { id: 'forge_project_proposals', path: 'EVIDENCE/reports/forge_project_proposals.jsonl', subject_field: 'project', ts_field: 'ts', match_fields: ['project', 'folder'] },
  { id: 'error_proposals', path: 'EVIDENCE/reports/error_proposals.jsonl', subject_field: 'error_signature', ts_field: 'created_ts', match_fields: ['error_signature', 'proposal_id', 'title'] },
  // 4e file (studio_link.propose_bible_entry) : même clé sujet que ledger/project
  // ("project" — record réel écrit par la fonction), même champ d'horodatage epoch
  // secondes ("ts", via studio_link.time.time()). Un fichier absent reste ABSENT,
  // jamais une erreur.
  // match_fields : le record reel de `propose_bible_entry` (studio_link.py:591-596) ne porte
  // AUCUN identifiant de ligne — {project, kind, decision, rationale, status, ts}. `project`
  // est donc le SEUL champ de rapprochement possible, et il est GROSSIER : une decision visant
  // un projet marque TOUTES ses entrees de bible. Limite assumee et signalee, pas un champ
  // invente. NON VERIFIE PAR DONNEES : ce fichier n'existe pas sur disque au 2026-08-10.
  { id: 'forge_bible_proposals', path: 'EVIDENCE/reports/forge_bible_proposals.jsonl', subject_field: 'project', ts_field: 'ts', match_fields: ['project'] },
  // 5e file (studio_link.propose_brick — le dépositaire). Clé sujet "brick_id" (PAS
  // "project" comme les 4 files ci-dessus) : le sujet examiné par Pierre est LA BRIQUE,
  // pas le projet qui l'a produite — deux propositions du même projet peuvent porter des
  // briques distinctes et ne doivent pas être comptées comme « le même sujet ». Même champ
  // d'horodatage epoch secondes ("ts"). Un fichier absent reste ABSENT, jamais une erreur.
  // match_fields : `brick_id` est l'identifiant propre du record (studio_link.py:639), `path`
  // la preuve disque du meme objet — les deux sont ecrits par le producteur. NON VERIFIE PAR
  // DONNEES : ce fichier n'existe pas sur disque au 2026-08-10.
  { id: 'forge_brick_proposals', path: 'EVIDENCE/reports/forge_brick_proposals.jsonl', subject_field: 'brick_id', ts_field: 'ts', match_fields: ['brick_id', 'path'] },
  // 6e file (studio_link.propose_capability_gap — mission repair-boucle-cassee
  // 2026-08-03, FORGE_AUTONOMY_V1). Clé sujet "capability_id" (PAS "project" ni
  // "brick_id") : le sujet examiné par Pierre est LA CAPACITÉ candidate au registre
  // fermé `forge/standard/capabilities.yaml` — deux runs différents (ou le
  // même run rejoué) peuvent redéclarer le même `capability_id` manquant, qui doit
  // compter comme UN SEUL sujet récurrent, pas deux sujets distincts. Même champ
  // d'horodatage epoch secondes ("ts"). Un fichier absent reste ABSENT, jamais une
  // erreur — ferme le cul-de-sac `identifiants_inconnus` (check_collisions) qui
  // n'avait aucun consommateur avant ce correctif.
  // match_fields : `capability_id` est le sujet decide (une capacite tranchee l'est pour toutes
  // ses occurrences, c'est l'intention), `source_line_id` permet un rapprochement plus fin sur
  // UNE ligne de wiremap precise. Les deux sont ecrits par le producteur (studio_link.py:684-685).
  // VERIFIE PAR DONNEES : 42 lignes reelles au 2026-08-10, 6 capability_id distincts.
  // `registry` (2026-08-10) : le registre que la RATIFICATION de ce sujet alimente. Sert
  // UNIQUEMENT a la reconciliation d'apply_decisions (`reconcileRegistries`) — jamais a
  // ecrire le registre, qui reste un acte humain (un `statement` ne se fabrique pas).
  // Porte ICI, sur la queue, pour la meme raison que `match_fields` : une table parallele
  // finit toujours par diverger (defaut MATCH_FIELDS repare le 2026-08-10).
  // Une queue SANS `registry` est simplement hors reconciliation, jamais une erreur.
  { id: 'forge_capability_gap_proposals', path: 'EVIDENCE/reports/forge_capability_gap_proposals.jsonl', subject_field: 'capability_id', ts_field: 'ts', match_fields: ['capability_id', 'source_line_id'], registry: { path: 'forge/standard/capabilities.yaml', key: 'capabilities' } },
  // 7e file (studio_link.propose_capability_gap, branche USINE — decision Pierre
  // 2026-08-10, option b). JUMELLE EXACTE de la 6e : meme producteur, meme schema de
  // record, memes cles. Ce qui change est la DESTINATION, decidee par l'espace de noms
  // de l'identifiant (`namespaces` de forge/standard/factory_capabilities.yaml).
  //
  // Pourquoi deux files et pas un champ `namespace` dans une seule : Pierre arbitre des
  // capacites de JEU dans la file produit, et le plafond d'affichage est un tour de role
  // ENTRE FILES. Une file distincte garantit qu'un identifiant d'usine ne prend jamais la
  // place d'un identifiant de jeu a l'ecran — mesure pacman v2 : 8 d'usine pour 67 de jeu,
  // soit 11 % des sujets qui auraient squatte la rotation.
  //
  // NON VERIFIE PAR DONNEES : ce fichier n'existe pas sur disque au 2026-08-10 (aucun run
  // n'a encore emis d'identifiant d'usine). Un fichier absent reste ABSENT, jamais une
  // erreur — meme regime que forge_bible_proposals / forge_brick_proposals.
  { id: 'forge_factory_capability_gap_proposals', path: 'EVIDENCE/reports/forge_factory_capability_gap_proposals.jsonl', subject_field: 'capability_id', ts_field: 'ts', match_fields: ['capability_id', 'source_line_id'], registry: { path: 'forge/standard/factory_capabilities.yaml', key: 'factory_capabilities' } },
];

const KEY_FALLBACK_PREFIX = '__no_subject_field__:';
const DEFAULT_TOP = 5;

// Champs "de reproduction" optionnels rencontrés dans les schémas réels — passés tels
// quels s'ils sont présents. AUCUN champ nommé "reproduction" n'existe dans les données
// réelles actuelles (2026-07-20) : ceci est un écart signalé, pas résolu en silence — voir
// le rapport de livraison.
const PASSTHROUGH_FIELDS = [
  'run_id', 'project', 'folder', 'stage', 'software_verdict', 'decision', 'clean_pass',
  'lane', 'status', 'error_excerpt', 'title', 'oracle_type', 'source', 'proposal_id',
  'error_signature', 'closed', 'ecg_state',
  // forge_bible_proposals (studio_link.propose_bible_entry) : 'decision' est déjà
  // couvert ci-dessus (même nom de champ que ledger) ; 'kind' et 'rationale' sont
  // spécifiques à ce record réel (kind ∈ {"validated","abandoned"}, rationale =
  // le pourquoi, la mémoire la plus précieuse pour un "abandoned").
  'kind', 'rationale',
  // forge_brick_proposals (studio_link.propose_brick, le dépositaire) : 'kind' est déjà
  // couvert ci-dessus (même nom de champ, sens différent ici : BRICK_SPEC::kind ∈
  // {"system","pattern","template"}) ; 'brick_id', 'function' et 'path' sont spécifiques —
  // 'path' est la preuve que le code existe déjà sur disque (pas une intention), 'function'
  // la description courte que Pierre relit pour décider de la promotion.
  'brick_id', 'function', 'path',
  // forge_capability_gap_proposals (studio_link.propose_capability_gap) : 'status'
  // déjà couvert ci-dessus ; 'capability_id'/'source_line_id'/'note' sont spécifiques —
  // 'source_line_id' trace la ligne de wiremap qui a déclaré l'identifiant, 'note'
  // porte le contexte lisible (registre + run) que Pierre relit pour rédiger le
  // `statement` au moment de la promotion.
  'capability_id', 'source_line_id', 'note',
  // --- LE POINT DE RUPTURE DE LA BOUCLE DE REVUE (repare 2026-08-10) -------------------
  // `apply_decisions.mjs:285-291` ecrit review_status/review_ts/review_source sur la
  // proposition tranchee. Ces trois champs n'etaient PAS dans cette liste blanche : la boucle
  // l.171-173 les jetait sur chacun des 62 items, AVANT tout filtre, tri ou affichage. Effet
  // mesure : les 10 propositions tranchees le 2026-07-20 remontaient encore le 2026-08-10
  // comme a trancher, colonnes vides, indistinguables d'une proposition jamais vue — trancher
  // ne retirait rien de la file et ne produisait aucun accuse de reception.
  // Ce n'est PAS une consequence de la doctrine read-only : interdire d'ECRIRE une decision
  // (spec §3, respectee) n'a jamais interdit de LIRE un statut ecrit par un autre outil.
  'review_status', 'review_ts', 'review_source',
  // Enrichissement optionnel de decision (apply_decisions.buildEnrichmentFields, primitive 2
  // ratifiee 2026-07-26) : present sur 0 proposition reelle au 2026-08-10, expose ici pour que
  // la premiere decision enrichie soit visible du lecteur au lieu d'etre silencieusement jetee.
  'review_allowed_future_patch_scope', 'review_future_validation_required', 'review_risks',
];

export const OUT_OF_SCOPE = [
  'aucune donnée "reproduction" dédiée n\'existe dans les fichiers de file actuels — le '
    + 'passthrough expose les champs optionnels disponibles (voir PASSTHROUGH_FIELDS), pas un '
    + 'champ "reproduction" formel qui n\'existe simplement pas encore.',
  'la logique "anti-postpone" du protocole (§5 : un Postpone revient en tête de file à '
    + 'échéance) N\'EST PAS implémentée ici : cet outil ne stocke aucune décision (spec §3), donc '
    + 'il n\'a pas la mémoire d\'un Postpone antérieur. Cette mémoire vit dans l\'enregistrement de '
    + 'gate de session (mécanisme existant), pas dans cet outil — c\'est l\'orchestrateur qui '
    + 'devra réinjecter les Postpone échus s\'il veut ce comportement. La colonne "Postpone" a '
    + 'été RETIRÉE de la table le 2026-08-10 : elle proposait à Pierre un verbe que '
    + 'apply_decisions.isActionableDecision n\'accepte pas — une ligne {"decision":"POSTPONE"} '
    + 'était silencieusement rangée en skipped_meta, indistinguable d\'une ligne narrative '
    + 'légitime. Un écran ne doit pas proposer un choix que la chaîne aval ne sait pas recevoir.',
  'dédoublonnage strictement intra-fichier (voir commentaire d\'en-tête) : un même sujet logique '
    + 'répété dans 2 fichiers différents (ex. un projet à la fois dans forge_ledger_proposals et '
    + 'forge_project_proposals) compte comme 2 sujets distincts, pas 1.',
];

/**
 * Charge et parse une file JSONL, tolérante aux lignes corrompues.
 * @param {string} repoRoot
 * @param {{id:string, path:string, subject_field:string, ts_field:string}} fileCfg
 * @returns {{id:string, path:string, status:'OK'|'ABSENT', raw_items:object[], ignored_lines:number, total_lines:number}}
 */
export function loadQueueFile(repoRoot, fileCfg) {
  const full = join(repoRoot, fileCfg.path);
  if (!existsSync(full)) {
    return { id: fileCfg.id, path: fileCfg.path, status: 'ABSENT', raw_items: [], ignored_lines: 0, total_lines: 0 };
  }
  const text = readFileSync(full, 'utf-8');
  const lines = text.split(/\r?\n/).filter((l) => l.trim() !== '');
  const rawItems = [];
  let ignored = 0;
  for (const line of lines) {
    try {
      const parsed = JSON.parse(line);
      if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) {
        ignored += 1;
        continue;
      }
      rawItems.push(parsed);
    } catch {
      ignored += 1;
    }
  }
  return { id: fileCfg.id, path: fileCfg.path, status: 'OK', raw_items: rawItems, ignored_lines: ignored, total_lines: lines.length };
}

/**
 * Normalise un item brut en record avec features déterministes brutes.
 * @param {{id:string, subject_field:string, ts_field:string}} fileCfg
 * @param {object} rawItem
 * @param {number} nowEpochS
 * @returns {object}
 */
export function normalizeItem(fileCfg, rawItem, nowEpochS) {
  const subjectRaw = rawItem[fileCfg.subject_field];
  const hasSubject = subjectRaw !== undefined && subjectRaw !== null && String(subjectRaw).trim() !== '';
  const subjectKey = hasSubject ? String(subjectRaw) : `${KEY_FALLBACK_PREFIX}${JSON.stringify(rawItem)}`;

  const tsRaw = rawItem[fileCfg.ts_field];
  const tsValid = typeof tsRaw === 'number' && Number.isFinite(tsRaw);
  const ageDays = tsValid ? (nowEpochS - tsRaw) / 86400 : null;

  const origin = rawItem.run_id || rawItem.project || rawItem.folder || rawItem.proposal_id || null;
  const label = rawItem.title || rawItem.run_id || rawItem.project || rawItem.error_signature || rawItem.proposal_id || '(sans titre)';

  // `subject_label` — CE QUE L'ITEM EST, pour la colonne "sujet" de la table. `label` restait
  // aveugle a `capability_id` et `brick_id`, qui sont pourtant les subject_field declares de
  // 2 des 6 queues : le 2026-08-10 l'ecran affichait 5 lignes portant le MEME run_id tetris
  // pour 5 capacites DIFFERENTES (game.gravity, game.input, ...). Un humain ne pouvait pas
  // savoir ce qu'il etait cense trancher. `label` est conserve tel quel (contrat inchange).
  const subjectLabel = hasSubject ? String(subjectRaw) : '(sujet absent)';

  // `decision_item` — CE QU'IL FAUT RECOPIER dans le champ "item" d'une ligne de
  // pending_review_decisions.jsonl pour que apply_decisions retrouve cette proposition.
  // Premier `match_fields` reellement present sur le record. Sans ce champ, la procedure
  // /gate demandait a l'humain de deviner quelle colonne de l'ecran recopier — pour
  // forge_ledger_proposals `label` valait `run_id` et coincidait par chance, pour
  // capability_gap il valait `run_id` alors que la cle est `capability_id` : item faux a coup sur.
  const matchFields = Array.isArray(fileCfg.match_fields) ? fileCfg.match_fields : [];
  let decisionItem = null;
  for (const f of matchFields) {
    if (rawItem[f] !== undefined && String(rawItem[f]).trim() !== '') { decisionItem = String(rawItem[f]); break; }
  }

  const passthrough = {};
  for (const f of PASSTHROUGH_FIELDS) {
    if (rawItem[f] !== undefined) passthrough[f] = rawItem[f];
  }

  // Etat de revue LU (jamais ecrit ici — read-only strict preserve). Une valeur non-chaine ou
  // vide est traitee comme "pas de statut" : on ne devine jamais qu'un item est tranche.
  const rawStatus = rawItem.review_status;
  const reviewStatus = typeof rawStatus === 'string' && rawStatus.trim() !== '' ? rawStatus : null;

  return {
    source_file: fileCfg.id,
    subject_key: subjectKey,
    key_fallback: !hasSubject,
    origin,
    label,
    subject_label: subjectLabel,
    decision_item: decisionItem,
    match_fields: matchFields,
    age_days: ageDays === null ? null : Math.round(ageDays * 100) / 100,
    ts_field_present: tsValid,
    review_status: reviewStatus,
    reviewed: reviewStatus !== null,
    review_ts: rawItem.review_ts !== undefined ? rawItem.review_ts : null,
    fields: passthrough,
    decision: null, // colonne vide — Pierre décide en session, jamais stockée par cet outil
  };
}

/**
 * Agrège les 3 files, calcule occurrences, trie de façon déterministe.
 * @param {string} repoRoot
 * @param {number} [nowEpochS]
 * @returns {{sources:object[], total_items:number, ranked:object[]}}
 */
export function aggregate(repoRoot, nowEpochS = Date.now() / 1000, opts = {}) {
  const includeReviewed = opts.includeReviewed === true;
  const sources = [];
  const normalized = [];
  for (const cfg of QUEUE_FILES) {
    const loaded = loadQueueFile(repoRoot, cfg);
    const items = loaded.raw_items.map((raw, idx) => ({ ...normalizeItem(cfg, raw, nowEpochS), _fileIndex: idx }));
    const reviewedCount = items.filter((it) => it.reviewed).length;
    sources.push({
      id: loaded.id,
      path: loaded.path,
      status: loaded.status,
      item_count: loaded.raw_items.length,
      reviewed_count: reviewedCount,
      pending_count: loaded.raw_items.length - reviewedCount,
      ignored_lines: loaded.ignored_lines,
    });
    for (const it of items) normalized.push({ ...it, _origIndex: normalized.length });
  }

  // Les items DEJA TRANCHES sortent de la file par defaut : c'est ce qui donne a une decision
  // humaine un effet visible (critere de sortie de la reparation du 2026-08-10). Le volume
  // total reste annonce (total_items) — rien n'est cache, seulement retire de ce qui RESTE A
  // FAIRE. `--include-reviewed` les reaffiche pour audit.
  const pending = includeReviewed ? normalized : normalized.filter((it) => !it.reviewed);

  // Occurrences comptees SUR LA FILE RETENUE, jamais sur le total : un item tranche ne doit
  // plus gonfler le rang de ses jumeaux non tranches (contamination du score de priorite).
  const occCounts = new Map();
  for (const it of pending) {
    const k = `${it.source_file}::${it.subject_key}`;
    occCounts.set(k, (occCounts.get(k) || 0) + 1);
  }
  for (const it of pending) {
    it.occurrences = occCounts.get(`${it.source_file}::${it.subject_key}`);
  }

  const ranked = [...pending].sort((a, b) => {
    if (b.occurrences !== a.occurrences) return b.occurrences - a.occurrences;
    const ageA = a.age_days === null ? -Infinity : a.age_days;
    const ageB = b.age_days === null ? -Infinity : b.age_days;
    if (ageB !== ageA) return ageB - ageA;
    if (a.source_file !== b.source_file) return a.source_file < b.source_file ? -1 : 1;
    return a._origIndex - b._origIndex;
  }).map(({ _origIndex, _fileIndex, ...rest }) => rest);

  const reviewedItems = normalized.length - normalized.filter((it) => !it.reviewed).length;
  return {
    sources,
    total_items: normalized.length,
    pending_items: normalized.length - reviewedItems,
    reviewed_items: reviewedItems,
    reviewed_included: includeReviewed,
    ranked,
  };
}

/**
 * Selectionne les items affiches sous le plafond, en TOUR DE ROLE entre files sources.
 *
 * Le classement `ranked` est conserve INTACT (regle de tri inchangee) : seule la SELECTION
 * change. Motif mesure le 2026-08-10 : `forge_capability_gap_proposals` portait 42 des 62
 * items, tous issus d'UN SEUL run, avec 6 occurrences chacun — le tri par occurrences
 * decroissantes leur donnait mecaniquement les rangs 1 a 42 et les 5 places du plafond. Les
 * deux plus vieilles propositions du depot (34,9 j et 30,0 j) etaient invisibles sans `--top 52`.
 * Une file bruyante ne doit pas pouvoir masquer les autres.
 *
 * Ordre des files = ordre de leur premier item dans `ranked` (donc pilote par le classement),
 * puis un item par file a chaque tour. Deterministe, reproductible a froid.
 * @param {object[]} ranked
 * @param {number} top
 * @returns {object[]}
 */
export function selectDisplayed(ranked, top) {
  if (!Number.isFinite(top) || top <= 0) return [];
  const bySource = new Map();
  for (const it of ranked) {
    if (!bySource.has(it.source_file)) bySource.set(it.source_file, []);
    bySource.get(it.source_file).push(it);
  }
  const queues = [...bySource.values()];
  const cursors = queues.map(() => 0);
  const out = [];
  let progressed = true;
  while (out.length < top && progressed) {
    progressed = false;
    for (let q = 0; q < queues.length && out.length < top; q += 1) {
      if (cursors[q] < queues[q].length) {
        out.push(queues[q][cursors[q]]);
        cursors[q] += 1;
        progressed = true;
      }
    }
  }
  return out;
}

function formatTable(shown) {
  const lines = [];
  lines.push('#  | source                    | sujet                          | item (à recopier en décision)  | occ | âge(j) | revue    | Accept | Reject');
  lines.push('---+---------------------------+--------------------------------+--------------------------------+-----+--------+----------+--------+--------');
  shown.forEach((it, i) => {
    const subject = String(it.subject_label).slice(0, 30).padEnd(30);
    const src = it.source_file.padEnd(25);
    const item = String(it.decision_item === null ? '(AUCUNE CLÉ)' : it.decision_item).slice(0, 30).padEnd(30);
    const age = it.age_days === null ? '  ?   ' : String(it.age_days).padEnd(6);
    const rev = String(it.review_status === null ? '·' : it.review_status).padEnd(8);
    lines.push(`${String(i + 1).padEnd(2)} | ${src} | ${subject} | ${item} | ${String(it.occurrences).padEnd(3)} | ${age} | ${rev} |   ·    |   ·`);
  });
  return lines.join('\n');
}

function main() {
  const here = dirname(fileURLToPath(import.meta.url));
  const args = process.argv.slice(2);
  const repoRootFlagIdx = args.indexOf('--repo-root');
  const repoRoot = repoRootFlagIdx !== -1 ? resolve(args[repoRootFlagIdx + 1]) : resolve(here, '..');
  const topFlagIdx = args.indexOf('--top');
  const top = topFlagIdx !== -1 ? Number(args[topFlagIdx + 1]) || DEFAULT_TOP : DEFAULT_TOP;
  const includeReviewed = args.includes('--include-reviewed');

  let result;
  try {
    result = aggregate(repoRoot, Date.now() / 1000, { includeReviewed });
  } catch (err) {
    console.error(`[pending_review] ERREUR INTERNE : ${err.message}`);
    process.exit(2);
  }

  const displayed = selectDisplayed(result.ranked, top);

  console.error('=== pending_review — file de propositions dormantes (READ-ONLY) ===\n');
  for (const s of result.sources) {
    if (s.status === 'ABSENT') {
      console.error(`  ABSENT   ${s.path}`);
    } else {
      console.error(`  OK       ${s.path} — ${s.item_count} item(s), ${s.reviewed_count} tranché(s), ${s.pending_count} en attente${s.ignored_lines ? `, ${s.ignored_lines} ligne(s) ignorée(s) (corrompues)` : ''}`);
    }
  }
  console.error(`\nTotal items agrégés (toutes files) : ${result.total_items}`);
  console.error(`Déjà tranchés (review_status posé) : ${result.reviewed_items}${includeReviewed ? ' — RÉAFFICHÉS (--include-reviewed)' : ' — retirés de la file'}`);
  console.error(`Restant à trancher : ${result.ranked.length}`);
  console.error(`Affichés (plafond ${top}, tour de rôle entre files) : ${displayed.length}\n`);
  console.error(formatTable(displayed));
  console.error('\nAccept / Reject : colonnes vides à remplir par Pierre en session.');
  console.error('Colonne "item" = la valeur EXACTE à recopier dans le champ "item" d\'une ligne de');
  console.error('EVIDENCE/reports/pending_review_decisions.jsonl — c\'est elle que apply_decisions rapproche,');
  console.error('jamais le sujet ni le libellé. "(AUCUNE CLÉ)" = proposition non rapprochable en l\'état.');
  console.error('Cet outil n\'écrit et ne stocke AUCUNE décision — read-only strict.');

  const payload = {
    generated_at: new Date().toISOString(),
    sources: result.sources,
    total_items: result.total_items,
    reviewed_items: result.reviewed_items,
    pending_items: result.ranked.length,
    reviewed_included: result.reviewed_included,
    displayed_count: displayed.length,
    ranking_rule: 'occurrences desc, puis age_days desc (plus ancien en tête), puis source_file asc, puis ordre de lecture original',
    selection_rule: 'tour de rôle entre files sources sous le plafond — une file volumineuse ne peut pas masquer les autres',
    displayed,
    out_of_scope: OUT_OF_SCOPE,
  };
  console.log(JSON.stringify(payload, null, 2));
  process.exit(0);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main();
}

#!/usr/bin/env node
// apply_decisions.mjs — R4 (audit docs/audit/FORGE_AUDIT_BRANCHEMENTS_2026-07-24.md).
//
// CONSTAT REPARE : EVIDENCE/reports/pending_review_decisions.jsonl contient les decisions
// HumanGate (Pierre) du 2026-07-20 ({ts, queue, item, decision, motif}), ecrites A LA MAIN
// apres lecture de pending_review.mjs. AUCUN code ne les appliquait aux propositions
// sources : le fichier de decisions etait une note morte, jamais reliee mecaniquement aux
// 3 files lues par pending_review.mjs (regle memoire "structured_field_not_comment" —
// une intention non reliee mecaniquement finit par diverger). Ce script ferme CE maillon
// precis, rien de plus.
//
// CHAINE COMPLETE (R5 — documentee ici, jamais dans un nouveau fichier de doc) :
//   1. proposals.jsonl (forge_ledger_proposals / forge_project_proposals / error_proposals)
//      — EXISTE, ecrit par le pipeline Forge (driver/error_journal).
//   2. pending_review.mjs — EXISTE, lecteur READ-ONLY qui agrege les 3 files (aucune
//      decision stockee, colonnes Accept/Reject/Postpone vides pour Pierre en session).
//   3. decision Pierre (pending_review_decisions.jsonl) — EXISTE mais MANUEL : Pierre note
//      sa decision en session, aucun outil ne l'ecrit pour lui (c'est voulu, HumanGate).
//   4. statut final sur la proposition — MANQUAIT avant ce script. CE fichier (apply_decisions.mjs)
//      ferme ce maillon : il appose un champ structure (review_status/review_ts/review_source)
//      sur la proposition correspondante. Idempotent, jamais destructif, jamais un juge.
//   5. promotion vers EVIDENCE/chains/IMPROVEMENT_LEDGER.yaml — reste VOLONTAIREMENT MANUEL.
//      Doctrine HumanGate (CLAUDE.md) : Pierre decide merge/reject/freeze, jamais un script.
//      Ce script N'ECRIT JAMAIS dans le ledger canonique et ne le lira meme pas. La promotion
//      materielle est une etape 3 separee et ratifiee ailleurs (Resolver V1, note du
//      2026-07-20 dans pending_review_decisions.jsonl) — pas le role de ce fichier.
//
// REGLE DE RAPPROCHEMENT (reverse-engineree sur les decisions REELLES du 2026-07-20, car
// aucun schema formel ne lie decision.item a un champ de proposition) : pour chaque queue,
// une liste de champs candidats est essayee dans l'ordre, EGALITE STRICTE UNIQUEMENT (jamais
// de sous-chaine, jamais de fuzzy-match — "jamais inventee") :
//   - forge_ledger_proposals  : ['run_id', 'project']   (les decisions du 20/07 visent le run_id)
//   - forge_project_proposals : ['project', 'folder']   (ce fichier n'a pas de run_id)
//   - error_proposals         : ['error_signature', 'proposal_id', 'title']
// Si aucun champ candidat n'egale item -> la decision est ORPHELINE (jamais une proposition
// inventee). Exemple reel observe : la decision error_proposals du 20/07 ("council contract
// write-path interdit") ne correspond A AUCUN champ exact de l'unique ligne error_proposals.jsonl
// reelle (ni error_signature, ni title) -> orpheline, signalee, PAS forcee.
//
// Lignes de pending_review_decisions.jsonl SANS {queue, item, decision} (ex. la ligne meta
// de synthese du 20/07, ou la note de fin de session) sont des entrees narratives, pas des
// decisions item-par-item : elles sont comptees en `skipped_meta`, jamais en orpheline.
//
// Mode par defaut = --dry-run (aucune ecriture). --apply seul declenche l'ecriture reelle,
// avec backup .bak du fichier de propositions AVANT toute reecriture. Idempotent : rejouer
// --apply sur un etat deja applique => 0 changement (already_up_to_date).
//
// Usage : node forge/apply_decisions.mjs [--repo-root <path>] [--apply]
//         [--decisions-file <path relatif au repo-root>]
// Exit codes : 0 = execution normale (y compris orphelines/conflits, qui sont des rapports,
//              pas des echecs) ; 2 = erreur interne inattendue (ex. decisions-file illisible).
//
// claim_verdict: NO_CLAIM_ALLOWED — ce script ne juge rien, il rapporte l'etat mecanique.
import { existsSync, readFileSync, writeFileSync, copyFileSync } from 'node:fs';
import { join, dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { QUEUE_FILES } from './pending_review.mjs';

export const DEFAULT_DECISIONS_FILE = 'EVIDENCE/reports/pending_review_decisions.jsonl';

// Champs candidats essayes dans l'ordre, egalite stricte uniquement, PAR queue id.
//
// DERIVE de QUEUE_FILES depuis le 2026-08-10 — plus jamais une liste parallele. Avant cette
// date cette table etait ecrite EN DUR ici avec 3 entrees pour 6 queues : toute decision visant
// forge_bible_proposals / forge_brick_proposals / forge_capability_gap_proposals tombait en
// `orphaned` par le garde-fou de planDecisions, quel que soit son contenu, meme parfaitement
// formee. Les 42 items de capability_gap etaient donc STRUCTURELLEMENT indecidables — et
// c'etaient justement les seuls que l'ecran affichait sous son plafond. Deux listes qui ne se
// connaissent pas : c'est exactement le defaut repare ici, il ne doit pas etre recree.
export const MATCH_FIELDS = Object.fromEntries(
  QUEUE_FILES.filter((q) => Array.isArray(q.match_fields) && q.match_fields.length > 0)
    .map((q) => [q.id, q.match_fields]),
);

const DECISION_TO_STATUS = { ACCEPT: 'ACCEPTED', REJECT: 'REJECTED' };

// --- reconciliation registre <-> etat de proposition (2026-08-10) ---------------------
//
// DEFAUT MESURE ce jour-la : 7 capacites Tetris etaient PRESENTES dans capabilities.yaml
// (ratifiees par Pierre) alors que leurs 39 occurrences de proposition portaient toujours
// PROPOSED, et remontaient donc dans pending_review comme « a trancher ». Cause racine : la
// ratification a DEUX points d'entree independants pour un SEUL acte humain — ecrire le
// registre, ou ecrire une ligne de decision — et RIEN ne verifiait qu'ils s'accordent.
//
// Ce que ce volet fait : il RAPPORTE la divergence. Ce qu'il ne fait PAS, et ne doit jamais
// faire : apposer review_status parce qu'une capacite est au registre. Ce serait une
// ratification automatique — exactement l'inverse de la doctrine (`propose_capability_gap` :
// « depose une proposition que Pierre promeut »). Un capteur, pas un juge.
//
// Limite honnete, meme precedent qu'agent_context_map.mjs : aucun parseur YAML n'existe dans
// ce depot. On n'en ecrit pas un — extraction line-based des seuls `- id: <valeur>` sous la
// cle de liste attendue. Suffisant pour ces deux registres (liste plate d'objets a `id`),
// ne gere pas le YAML arbitraire. Registre absent ou illisible => aucune divergence
// rapportee, jamais une exception : un capteur muet vaut mieux qu'un faux positif.

/**
 * Identifiants d'un registre de capacites. Extraction line-based volontairement etroite.
 * @param {string} repoRoot
 * @param {{path:string, key:string}} registryCfg
 * @returns {{status:'OK'|'ABSENT', ids:Set<string>}}
 */
export function readRegistryIds(repoRoot, registryCfg) {
  const abs = join(repoRoot, registryCfg.path);
  if (!existsSync(abs)) return { status: 'ABSENT', ids: new Set() };
  let text;
  try {
    text = readFileSync(abs, 'utf-8');
  } catch {
    return { status: 'ABSENT', ids: new Set() };
  }
  const ids = new Set();
  let inList = false;
  for (const rawLine of text.split(/\r?\n/)) {
    const line = rawLine.replace(/\t/g, '  ');
    if (/^\s*#/.test(line) || line.trim() === '') continue;
    // Entree dans la liste voulue : cle a la colonne 0, ex. "capabilities:".
    if (new RegExp(`^${registryCfg.key}\\s*:`).test(line)) { inList = true; continue; }
    // Toute autre cle de premier niveau termine la liste (ex. "namespaces:").
    if (/^[A-Za-z_][\w.-]*\s*:/.test(line)) { inList = false; continue; }
    if (!inList) continue;
    const m = line.match(/^\s*-\s*id\s*:\s*(.+?)\s*$/);
    if (m) ids.add(m[1].replace(/^["']|["']$/g, ''));
  }
  return { status: 'OK', ids };
}

/**
 * Propositions dont le sujet est DEJA au registre mais dont l'etat reste non tranche.
 * Pur rapport : aucune ecriture, aucune decision deduite.
 * @param {string} repoRoot
 * @returns {{divergences:Array<object>, registries:Array<object>}}
 */
export function reconcileRegistries(repoRoot) {
  const divergences = [];
  const registries = [];
  for (const q of QUEUE_FILES) {
    if (!q.registry || !q.subject_field) continue;
    const reg = readRegistryIds(repoRoot, q.registry);
    const loaded = loadProposalLines(repoRoot, q.path);
    registries.push({
      queue: q.id, registry: q.registry.path, registry_status: reg.status,
      registry_ids: reg.ids.size, proposals_status: loaded.status,
    });
    if (reg.status !== 'OK' || loaded.status === 'ABSENT') continue;
    const bySubject = new Map();
    loaded.lines.forEach((l) => {
      if (!l.parsed) return;
      const subject = l.parsed[q.subject_field];
      if (typeof subject !== 'string' || !reg.ids.has(subject)) return;
      if (l.parsed.review_status !== undefined) return; // deja tranchee : coherent
      bySubject.set(subject, (bySubject.get(subject) || 0) + 1);
    });
    for (const [subject, occurrences] of [...bySubject].sort()) {
      divergences.push({
        queue: q.id,
        subject,
        occurrences,
        registry: q.registry.path,
        reason: 'present au registre mais aucune decision appliquee (review_status absent)',
        required_action: `ligne de decision Pierre : {"queue":"${q.id}","item":"${subject}","decision":"ACCEPT"}`,
      });
    }
  }
  return { divergences, registries };
}

/**
 * Charge et parse pending_review_decisions.jsonl. Lignes corrompues -> ignorees, jamais fatal.
 * @param {string} repoRoot
 * @param {string} relPath
 * @returns {{status:'OK'|'ABSENT', raw:object[], ignored_lines:number}}
 */
export function loadDecisions(repoRoot, relPath) {
  const full = join(repoRoot, relPath);
  if (!existsSync(full)) return { status: 'ABSENT', raw: [], ignored_lines: 0 };
  const text = readFileSync(full, 'utf-8');
  const lines = text.split(/\r?\n/).filter((l) => l.trim() !== '');
  const raw = [];
  let ignored = 0;
  for (const line of lines) {
    try {
      const parsed = JSON.parse(line);
      if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) { ignored += 1; continue; }
      raw.push(parsed);
    } catch { ignored += 1; }
  }
  return { status: 'OK', raw, ignored_lines: ignored };
}

/**
 * Une decision est "actionnable" (item-par-item) si elle porte queue+item+decision valide.
 * Tout le reste (notes, synthese de session) est narratif -> skipped_meta.
 * @param {object} d
 * @returns {boolean}
 */
export function isActionableDecision(d) {
  return typeof d.queue === 'string' && d.queue.trim() !== ''
    && typeof d.item === 'string' && d.item.trim() !== ''
    && (d.decision === 'ACCEPT' || d.decision === 'REJECT');
}

/** Verbes de decision acceptes. Toute autre valeur est INVALIDE, jamais narrative. */
export const VALID_DECISIONS = ['ACCEPT', 'REJECT'];

/**
 * Classe une ligne du fichier de decisions en `actionable` | `narrative` | `invalid`.
 *
 * REPARATION 2026-08-10 : avant, TOUT ce qui n'etait pas actionnable etait compte dans un
 * unique compteur `skipped_meta`, sans etre ni liste ni distingue. Consequence mesuree : une
 * ligne {"decision":"POSTPONE"} (verbe propose par la table de pending_review mais absent de
 * DECISION_TO_STATUS), un "Accept" en minuscules, ou une faute de frappe sur `queue`
 * disparaissaient EXACTEMENT comme les 2 lignes narratives legitimes du 2026-07-20. C'etait le
 * mode de defaillance le plus probable de la procedure /gate, et il etait muet.
 *
 * Distinction retenue : une ligne qui ne porte AUCUNE des 3 cles de decision est une note de
 * session (narrative, legitime). Une ligne qui en porte au moins une mais echoue la validation
 * est une decision RATEE — elle est desormais rapportee avec son motif exact.
 * @param {object} d
 * @returns {{kind:'actionable'|'narrative'|'invalid', reason:string|null}}
 */
export function classifyDecision(d) {
  if (isActionableDecision(d)) return { kind: 'actionable', reason: null };

  const hasAnyDecisionKey = ['queue', 'item', 'decision']
    .some((k) => Object.prototype.hasOwnProperty.call(d, k));
  if (!hasAnyDecisionKey) return { kind: 'narrative', reason: null };

  const problems = [];
  if (typeof d.queue !== 'string' || d.queue.trim() === '') problems.push('champ "queue" absent ou vide');
  if (typeof d.item !== 'string' || d.item.trim() === '') problems.push('champ "item" absent ou vide');
  if (!VALID_DECISIONS.includes(d.decision)) {
    problems.push(`verbe de decision "${d.decision}" non reconnu (attendu : ${VALID_DECISIONS.join(' | ')})`);
  }
  return { kind: 'invalid', reason: problems.join(' ; ') };
}

// --- Enrichissement optionnel de decision (primitive 2, ratification Pierre 2026-07-26,
// studio_brain/decisions/PROPOSED_2026-07-26_ratifications.md) --------------------------------
// 3 champs ADDITIONNELS et OPTIONNELS sur une ligne de pending_review_decisions.jsonl :
//   - allowed_future_patch_scope : portee autorisee pour la suite (liste de chemins/globs)
//   - future_validation_required : commandes de validation qui devront etre vertes (liste
//     de commandes executables)
//   - risks : risques identifies (liste structuree, un objet libre par risque)
// RETRO-COMPATIBILITE TOTALE : ces champs ne deviennent JAMAIS obligatoires. Une ligne a 5
// champs (ancienne, sans ces cles) continue d'etre traitee a l'identique — aucun de ces champs
// n'est ajoute au changement ni a la proposition ecrite si la cle est absente de la decision.
// Aucun blocage : ce module expose/valide la donnee (normalise absent/null/malforme en liste
// vide), il ne fait jamais echouer une etape ni un run.

/**
 * Extrait une liste de chaines optionnelle d'un objet decision. Absent, null, ou type non-array
 * -> liste vide (jamais de crash). Elements non-string a l'interieur -> filtres silencieusement.
 * @param {object} d
 * @param {string} key
 * @returns {string[]}
 */
function extractStringList(d, key) {
  if (!Array.isArray(d[key])) return [];
  return d[key].filter((x) => typeof x === 'string');
}

/**
 * Portee autorisee pour la suite (chemins/globs). Champ optionnel `allowed_future_patch_scope`.
 * @param {object} d
 * @returns {string[]}
 */
export function extractFutureScope(d) {
  return extractStringList(d, 'allowed_future_patch_scope');
}

/**
 * Commandes de validation qui devront etre vertes. Champ optionnel `future_validation_required`.
 * @param {object} d
 * @returns {string[]}
 */
export function extractFutureValidation(d) {
  return extractStringList(d, 'future_validation_required');
}

/**
 * Risques identifies (liste structuree, objets libres). Champ optionnel `risks`. Absent, null,
 * type non-array, ou elements non-objet -> filtres/normalises en liste vide (jamais de crash).
 * @param {object} d
 * @returns {object[]}
 */
export function extractRisks(d) {
  if (!Array.isArray(d.risks)) return [];
  return d.risks.filter((x) => x !== null && typeof x === 'object' && !Array.isArray(x));
}

/**
 * Construit les champs d'enrichissement a attacher a un changement/proposition, UNIQUEMENT
 * pour les cles reellement presentes sur la decision source (retro-compat : une decision sans
 * ces cles ne genere AUCUN champ, meme vide).
 * @param {object} d
 * @returns {object} sous-ensemble de {allowed_future_patch_scope, future_validation_required, risks}
 */
export function buildEnrichmentFields(d) {
  const out = {};
  if (Object.prototype.hasOwnProperty.call(d, 'allowed_future_patch_scope')) {
    out.allowed_future_patch_scope = extractFutureScope(d);
  }
  if (Object.prototype.hasOwnProperty.call(d, 'future_validation_required')) {
    out.future_validation_required = extractFutureValidation(d);
  }
  if (Object.prototype.hasOwnProperty.call(d, 'risks')) {
    out.risks = extractRisks(d);
  }
  return out;
}

/**
 * Charge une file JSONL de propositions en conservant les lignes brutes (pour reecriture
 * fidele) ET le parse (pour matching). Ligne corrompue -> conservee telle quelle, jamais touchee.
 * @param {string} repoRoot
 * @param {string} relPath
 * @returns {{status:'OK'|'ABSENT', lines:Array<{raw:string, parsed:object|null}>}}
 */
export function loadProposalLines(repoRoot, relPath) {
  const full = join(repoRoot, relPath);
  if (!existsSync(full)) return { status: 'ABSENT', lines: [] };
  const text = readFileSync(full, 'utf-8');
  const rawLines = text.split(/\r?\n/).filter((l) => l.trim() !== '');
  const lines = rawLines.map((raw) => {
    try {
      const parsed = JSON.parse(raw);
      if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) return { raw, parsed: null };
      return { raw, parsed };
    } catch { return { raw, parsed: null }; }
  });
  return { status: 'OK', lines };
}

/**
 * Trouve les indices de lignes dont un champ candidat egale item (egalite stricte).
 * @param {Array<{raw:string, parsed:object|null}>} lines
 * @param {string[]} candidateFields
 * @param {string} item
 * @returns {number[]}
 */
export function matchLines(lines, candidateFields, item) {
  const idx = [];
  lines.forEach((l, i) => {
    if (!l.parsed) return;
    for (const f of candidateFields) {
      if (Object.prototype.hasOwnProperty.call(l.parsed, f) && String(l.parsed[f]) === item) {
        idx.push(i);
        return;
      }
    }
  });
  return idx;
}

/**
 * Coeur de la logique : applique (ou simule) toutes les decisions actionnables sur les
 * files de propositions QUEUE_FILES. N'ecrit RIEN sur disque ici (le caller decide, voir main()).
 * @param {string} repoRoot
 * @param {string} decisionsFile
 * @returns {object} recap complet + etat des fichiers en memoire (pour ecriture eventuelle)
 */
export function planDecisions(repoRoot, decisionsFile) {
  const decisionsLoad = loadDecisions(repoRoot, decisionsFile);
  const queueById = new Map(QUEUE_FILES.map((q) => [q.id, q]));

  // Etat en memoire des fichiers de propositions touches, cle = queue id.
  const fileState = new Map(); // id -> { path, status, lines }

  const changes = [];
  const already_up_to_date = [];
  const conflicts = [];
  const orphaned = [];
  const invalid = [];
  let skipped_meta = 0;

  for (const d of decisionsLoad.raw) {
    const cls = classifyDecision(d);
    if (cls.kind === 'invalid') {
      invalid.push({ queue: d.queue ?? null, item: d.item ?? null, decision: d.decision ?? null, reason: cls.reason });
      continue;
    }
    if (cls.kind === 'narrative') { skipped_meta += 1; continue; }

    const queueCfg = queueById.get(d.queue);
    if (!queueCfg) {
      orphaned.push({ queue: d.queue, item: d.item, decision: d.decision, reason: `queue inconnue (pas dans QUEUE_FILES) : "${d.queue}"` });
      continue;
    }
    const candidateFields = MATCH_FIELDS[d.queue];
    if (!candidateFields) {
      orphaned.push({ queue: d.queue, item: d.item, decision: d.decision, reason: `aucune regle de rapprochement definie pour la queue "${d.queue}"` });
      continue;
    }

    if (!fileState.has(d.queue)) {
      const loaded = loadProposalLines(repoRoot, queueCfg.path);
      fileState.set(d.queue, { path: queueCfg.path, status: loaded.status, lines: loaded.lines });
    }
    const state = fileState.get(d.queue);
    if (state.status === 'ABSENT') {
      orphaned.push({ queue: d.queue, item: d.item, decision: d.decision, reason: `fichier de propositions absent : ${state.path}` });
      continue;
    }

    const matchIdx = matchLines(state.lines, candidateFields, d.item);
    if (matchIdx.length === 0) {
      orphaned.push({ queue: d.queue, item: d.item, decision: d.decision, reason: `aucune proposition dans ${state.path} ne correspond a "${d.item}" sur les champs ${JSON.stringify(candidateFields)}` });
      continue;
    }

    const requestedStatus = DECISION_TO_STATUS[d.decision];
    for (const i of matchIdx) {
      const entry = state.lines[i];
      const existing = entry.parsed.review_status;
      if (existing === undefined) {
        const enrichment = buildEnrichmentFields(d);
        changes.push({ queue: d.queue, item: d.item, path: state.path, line_index: i, requested_status: requestedStatus, decision_ts: d.ts, motif: d.motif || null, ...enrichment });
        // Marque en memoire — reecriture reelle geree par le caller (mode apply).
        const reviewEnrichment = {};
        if ('allowed_future_patch_scope' in enrichment) reviewEnrichment.review_allowed_future_patch_scope = enrichment.allowed_future_patch_scope;
        if ('future_validation_required' in enrichment) reviewEnrichment.review_future_validation_required = enrichment.future_validation_required;
        if ('risks' in enrichment) reviewEnrichment.review_risks = enrichment.risks;
        entry.parsed = {
          ...entry.parsed,
          review_status: requestedStatus,
          review_ts: d.ts,
          review_source: decisionsFile,
          ...reviewEnrichment,
        };
        entry.pending_write = true;
      } else if (existing === requestedStatus) {
        already_up_to_date.push({ queue: d.queue, item: d.item, path: state.path, line_index: i, status: existing });
      } else {
        conflicts.push({ queue: d.queue, item: d.item, path: state.path, line_index: i, existing_status: existing, requested_status: requestedStatus });
      }
    }
  }

  // Reconciliation registre<->proposition : calculee sur l'etat DISQUE, independamment des
  // decisions de ce run. Une divergence n'est ni un changement ni une orpheline — c'est un
  // ecart de gouvernance a trancher par Pierre, rapporte sans etre agi.
  const { divergences, registries } = reconcileRegistries(repoRoot);

  return {
    decisions_file_status: decisionsLoad.status,
    decisions_ignored_lines: decisionsLoad.ignored_lines,
    fileState,
    changes,
    already_up_to_date,
    conflicts,
    orphaned,
    invalid,
    skipped_meta,
    registry_divergences: divergences,
    registries,
  };
}

/**
 * Ecrit reellement sur disque les fichiers de propositions modifies (mode --apply). Backup
 * .bak AVANT toute reecriture. N'ecrit QUE les fichiers ayant au moins une ligne pending_write.
 * @param {string} repoRoot
 * @param {Map<string, {path:string, status:string, lines:Array}>} fileState
 * @returns {string[]} chemins ecrits
 */
export function writeChanges(repoRoot, fileState) {
  const written = [];
  for (const [, state] of fileState) {
    const hasChange = state.lines.some((l) => l.pending_write);
    if (!hasChange) continue;
    const full = join(repoRoot, state.path);
    copyFileSync(full, `${full}.bak`);
    const outLines = state.lines.map((l) => (l.pending_write ? JSON.stringify(l.parsed) : l.raw));
    writeFileSync(full, outLines.join('\n') + '\n', 'utf-8');
    written.push(state.path);
  }
  return written;
}

function main() {
  const here = dirname(fileURLToPath(import.meta.url));
  const args = process.argv.slice(2);
  const repoRootFlagIdx = args.indexOf('--repo-root');
  const repoRoot = repoRootFlagIdx !== -1 ? resolve(args[repoRootFlagIdx + 1]) : resolve(here, '..');
  const decisionsFlagIdx = args.indexOf('--decisions-file');
  const decisionsFile = decisionsFlagIdx !== -1 ? args[decisionsFlagIdx + 1] : DEFAULT_DECISIONS_FILE;
  const apply = args.includes('--apply');

  let plan;
  try {
    plan = planDecisions(repoRoot, decisionsFile);
  } catch (err) {
    console.error(`[apply_decisions] ERREUR INTERNE : ${err.message}`);
    process.exit(2);
  }

  let written = [];
  if (apply) {
    written = writeChanges(repoRoot, plan.fileState);
    // Le rapport de divergence est calcule DANS planDecisions, donc AVANT l'ecriture.
    // En mode --apply il serait perime : il annoncerait encore les divergences que
    // l'ecriture vient precisement de fermer (mesure du 2026-08-10 : 7 divergences
    // affichees alors que les 39 occurrences venaient de passer a ACCEPTED). Un rapport
    // qui decrit l'etat d'avant l'action qu'il rapporte est un rapport qui ment.
    // On le RECALCULE sur le disque reecrit — jamais on ne le corrige a la main.
    const after = reconcileRegistries(repoRoot);
    plan.registry_divergences = after.divergences;
    plan.registries = after.registries;
  }

  console.error(`=== apply_decisions — ${apply ? 'APPLY (ecriture reelle)' : 'DRY-RUN (aucune ecriture)'} ===\n`);
  console.error(`Fichier decisions : ${decisionsFile} (${plan.decisions_file_status}${plan.decisions_ignored_lines ? `, ${plan.decisions_ignored_lines} ligne(s) ignoree(s)` : ''})`);
  console.error(`Entrees narratives ignorees (aucune cle de decision — skipped_meta) : ${plan.skipped_meta}`);
  console.error(`\nDecisions INVALIDES (portent une cle de decision mais echouent la validation) : ${plan.invalid.length}`);
  for (const iv of plan.invalid) {
    console.error(`  ⚠ queue=${JSON.stringify(iv.queue)} item=${JSON.stringify(iv.item)} decision=${JSON.stringify(iv.decision)} — ${iv.reason}`);
  }
  console.error(`\n${apply ? 'Appliquees' : 'A appliquer (simulees)'} : ${plan.changes.length}`);
  for (const c of plan.changes) {
    console.error(`  · ${c.queue} / "${c.item}" -> ${c.requested_status} (${c.path}#${c.line_index})`);
    if ('allowed_future_patch_scope' in c) console.error(`      portee future autorisee : ${JSON.stringify(c.allowed_future_patch_scope)}`);
    if ('future_validation_required' in c) console.error(`      validation future requise : ${JSON.stringify(c.future_validation_required)}`);
    if ('risks' in c) console.error(`      risques identifies : ${c.risks.length}`);
  }
  console.error(`\nDeja a jour : ${plan.already_up_to_date.length}`);
  console.error(`\nConflits (non ecrases) : ${plan.conflicts.length}`);
  for (const c of plan.conflicts) console.error(`  ⚠ ${c.queue} / "${c.item}" : statut existant "${c.existing_status}" != demande "${c.requested_status}" (${c.path}#${c.line_index})`);
  console.error(`\nOrphelines (aucune proposition correspondante — jamais inventee) : ${plan.orphaned.length}`);
  for (const o of plan.orphaned) console.error(`  ⚠ ${o.queue} / "${o.item}" — ${o.reason}`);
  console.error(`\nDivergences registre<->proposition (RAPPORT, jamais applique) : ${plan.registry_divergences.length}`);
  for (const r of plan.registries) {
    console.error(`  registre ${r.registry} (${r.registry_status}, ${r.registry_ids} id) <- ${r.queue} (${r.proposals_status})`);
  }
  for (const d of plan.registry_divergences) {
    console.error(`  ⚠ "${d.subject}" x${d.occurrences} — ${d.reason}`);
    console.error(`      action : ${d.required_action}`);
  }
  if (plan.registry_divergences.length) {
    console.error(`  -> une capacite au registre dont la proposition n'est pas tranchee reste`);
    console.error(`     affichee comme « a trancher ». AUCUN statut n'est appose ici : ratifier`);
    console.error(`     est un acte humain, ce volet ne fait que le rendre visible.`);
  }
  if (apply) {
    console.error(`\nFichiers reecrits (backup .bak cree avant) : ${written.length ? written.join(', ') : '(aucun)'}`);
  } else {
    console.error(`\n(dry-run : aucun fichier touche — relancer avec --apply pour ecrire reellement)`);
  }
  console.error(`\nclaim_verdict: NO_CLAIM_ALLOWED`);

  const payload = {
    mode: apply ? 'apply' : 'dry-run',
    decisions_file: decisionsFile,
    decisions_file_status: plan.decisions_file_status,
    skipped_meta: plan.skipped_meta,
    invalid: plan.invalid,
    changes: plan.changes,
    already_up_to_date: plan.already_up_to_date,
    conflicts: plan.conflicts,
    orphaned: plan.orphaned,
    registry_divergences: plan.registry_divergences,
    registries: plan.registries,
    written_files: written,
    claim_verdict: 'NO_CLAIM_ALLOWED',
  };
  console.log(JSON.stringify(payload, null, 2));
  process.exit(0);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main();
}

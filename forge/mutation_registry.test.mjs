// Tests du MUTATION_REGISTRY_V1 : API de lecture, validateur, dérivation de confidence.
// node --test forge/mutation_registry.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  loadRegistry, loadMutation, findMutation, findAccepted, findProductionReady,
  findRejected, findByLayer, findByWorker, findByTarget, findByClass, loadLayers,
} from './mutation_registry.mjs';
import { checkRegistry, deriverConfidence, referencesFichiers, ECHANTILLON_DE_REFERENCE } from './check_mutation_registry.mjs';

const REGISTRE = async () => {
  const { ok, registre, erreur } = await loadRegistry();
  assert.equal(ok, true, `registre illisible : ${erreur}`);
  return registre;
};

const mutationValide = (over = {}) => ({
  id: 'M-test', title: 't', mutation_class: 'ORACLE', layer: 'quality', worker: 'aucun',
  target: 'x', hypothesis: 'h', implementation: 'i', expected_gain: 'g', expected_risk: 'r',
  measured_gain: 'm',
  measured_cost: { token_cost: 0, runtime_cost: 0, complexity_cost: 'LOW', maintenance_cost: 'LOW' },
  false_positive: 0, true_positive: 1, sample_size: 12, confidence: 'AUTO',
  known_side_effects: [], known_blind_spots: [],
  accepted: true, production_ready: false, rejected_reason: null,
  evidence_refs: { artifacts: [], tests: ['forge/mutation_registry.test.mjs'], reports: [], telemetry: [], commits: [] },
  evidence_status: 'VERSIONED',
  reproducibility: { command: null, inputs: [], expected_outputs: [], deterministic: true },
  requires: [], conflicts: [], timestamp: '2026-08-04',
  ...over,
});

// --- LE test : le registre REEL est mecaniquement valide ----------------------------

test('VALIDITE: le registre reel passe son propre validateur', async () => {
  const r = await checkRegistry(await REGISTRE());
  assert.deepEqual(r.problems, []);
  assert.equal(r.ok, true);
  assert.ok(r.stats.mutations > 0);
});

test('toutes les preuves citees existent PHYSIQUEMENT sur disque', async () => {
  // C est la garde qui empeche le registre de vieillir en mentant : deplacer un
  // fichier de preuve doit faire echouer le checker, pas passer inapercu.
  const r = await checkRegistry(await REGISTRE());
  assert.ok(!r.problems.some((p) => /introuvable/.test(p)), r.problems.join(' | '));
});

// --- gardes de Pierre ---------------------------------------------------------------

test('GARDE 1: ACCEPTED sans aucune evidence_ref -> FAIL', async () => {
  const r = await checkRegistry({
    schema_version: 1,
    mutations: [mutationValide({
      evidence_refs: { artifacts: [], tests: [], reports: [], telemetry: [], commits: [] },
    })],
  });
  assert.ok(r.problems.some((p) => /ACCEPTED sans aucune evidence_ref/.test(p)));
});

test('GARDE 2: une reference qui n existe pas sur disque -> FAIL', async () => {
  const r = await checkRegistry({
    schema_version: 1,
    mutations: [mutationValide({
      evidence_refs: { artifacts: ['EVIDENCE/bundles/JAMAIS/rien.json'], tests: [], reports: [], telemetry: [], commits: [] },
    })],
  });
  assert.ok(r.problems.some((p) => /introuvable sur disque/.test(p)));
});

test('une mutation dont la seule preuve serait une conversation ne peut pas etre ACCEPTED', async () => {
  // evidence_status UNKNOWN = rien de versionne = acceptation interdite
  const r = await checkRegistry({
    schema_version: 1,
    mutations: [mutationValide({
      evidence_status: 'UNKNOWN',
      evidence_refs: { artifacts: [], tests: [], reports: [], telemetry: [], commits: [] },
    })],
  });
  assert.ok(r.problems.some((p) => /seule une preuve VERSIONED autorise l acceptation/.test(p)));
});

// --- les 6 regles -------------------------------------------------------------------

test('id duplique -> FAIL', async () => {
  const r = await checkRegistry({ schema_version: 1, mutations: [mutationValide(), mutationValide()] });
  assert.ok(r.problems.some((p) => /id duplique/.test(p)));
});

test('REJECTED sans justification -> FAIL, code inconnu -> FAIL, note vide -> FAIL', async () => {
  const sans = await checkRegistry({ schema_version: 1, mutations: [mutationValide({ accepted: false, rejected_reason: null })] });
  assert.ok(sans.problems.some((p) => /sans rejected_reason/.test(p)));

  const codeKo = await checkRegistry({ schema_version: 1, mutations: [mutationValide({ accepted: false, rejected_reason: { code: 'PARCE_QUE', note: 'n' } })] });
  assert.ok(codeKo.problems.some((p) => /code inconnu/.test(p)));

  const noteKo = await checkRegistry({ schema_version: 1, mutations: [mutationValide({ accepted: false, rejected_reason: { code: 'NO_MEASURED_GAIN', note: '  ' } })] });
  assert.ok(noteKo.problems.some((p) => /note vide/.test(p)));
});

test('confidence saisie a la main -> FAIL (elle est DERIVEE)', async () => {
  const r = await checkRegistry({ schema_version: 1, mutations: [mutationValide({ confidence: 0.95 })] });
  assert.ok(r.problems.some((p) => /doit valoir exactement 'AUTO'/.test(p)));
});

test('sample_size negatif -> FAIL', async () => {
  const r = await checkRegistry({ schema_version: 1, mutations: [mutationValide({ sample_size: -1 })] });
  assert.ok(r.problems.some((p) => /sample_size/.test(p)));
});

test('production_ready sans accepted -> FAIL', async () => {
  const r = await checkRegistry({
    schema_version: 1,
    mutations: [mutationValide({ accepted: false, production_ready: true, rejected_reason: { code: 'NO_MEASURED_GAIN', note: 'n' } })],
  });
  assert.ok(r.problems.some((p) => /production_ready sans accepted/.test(p)));
});

test('requires/conflicts pointant une mutation inexistante -> FAIL', async () => {
  const r = await checkRegistry({ schema_version: 1, mutations: [mutationValide({ requires: ['M-fantome'] })] });
  assert.ok(r.problems.some((p) => /pointe une mutation inexistante/.test(p)));
});

// --- derivation de la confidence ----------------------------------------------------

test('CONFIDENCE: derivee de precision x couverture, jamais saisie', () => {
  // precision 1, couverture pleine
  assert.equal(deriverConfidence({ sample_size: ECHANTILLON_DE_REFERENCE, false_positive: 0, true_positive: 1 }), 1);
  // meme precision, echantillon 4x plus petit -> confiance divisee
  assert.equal(deriverConfidence({ sample_size: 3, false_positive: 0, true_positive: 1 }), 0.25);
  // un faux positif fait chuter la precision
  assert.equal(deriverConfidence({ sample_size: 12, false_positive: 1, true_positive: 1 }), 0.5);
});

test('CONFIDENCE: ZERO detection ne vaut PAS 1 — un detecteur muet n a pas de precision', () => {
  // Defaut trouve en executant le checker sur le registre reel : M-Q5-C et M-Q5-D,
  // qui n ont rien detecte, ressortaient a 1,00. La formule recompensait le silence.
  assert.equal(deriverConfidence({ sample_size: 12, false_positive: 0, true_positive: 0 }), null);
});

test('CONFIDENCE: UNKNOWN des qu un compteur manque — on ne derive rien d une inconnue', () => {
  assert.equal(deriverConfidence({ sample_size: 'UNKNOWN', false_positive: 0, true_positive: 1 }), null);
  assert.equal(deriverConfidence({ sample_size: 3, false_positive: 'UNKNOWN', true_positive: 1 }), null);
  assert.equal(deriverConfidence({ sample_size: 0, false_positive: 0, true_positive: 0 }), 0);
});

// --- API de lecture -----------------------------------------------------------------

test('API: findMutation / findAccepted / findProductionReady / findRejected', async () => {
  const reg = await REGISTRE();
  assert.equal(findMutation(reg, 'M-Q5-A').mutation_class, 'ORACLE');
  assert.equal(findMutation(reg, 'M-inexistante'), null);

  const acc = findAccepted(reg);
  assert.ok(acc.length > 0);
  assert.ok(acc.every((m) => m.accepted === true));

  // production_ready est un SOUS-ENSEMBLE STRICT d accepted
  const prod = findProductionReady(reg);
  assert.ok(prod.every((m) => m.accepted === true));
  assert.ok(prod.length <= acc.length);

  const refutes = findRejected(reg, 'REFUTED_FALSE_POSITIVE');
  assert.ok(refutes.some((m) => m.id === 'M-Q4-ANCRAGE'));
  const nonPayees = findRejected(reg, 'NO_MEASURED_GAIN');
  assert.ok(nonPayees.some((m) => m.id === 'M-Q5-B'));
});

test('API: filtres par layer / worker / target / classe', async () => {
  const reg = await REGISTRE();
  assert.ok(findByLayer(reg, 'quality').length > 0);
  assert.ok(findByWorker(reg, 'qwen2.5-14b-instruct').length > 0);
  assert.ok(findByTarget(reg, 'forge/cross_field_quality.mjs').length > 0);
  assert.ok(findByClass(reg, 'ORACLE').length > 0);
  assert.deepEqual(findByLayer(reg, 'inexistant'), []);
});

test('API: lecture seule — loadMutation ne rend jamais autre chose qu un tableau', () => {
  assert.deepEqual(loadMutation(null), []);
  assert.deepEqual(loadMutation({}), []);
  assert.deepEqual(loadMutation({ mutations: 'pas un tableau' }), []);
});

test('referencesFichiers ignore les commits (un sha n est pas un fichier)', () => {
  const m = mutationValide({
    evidence_refs: { artifacts: ['a'], tests: ['b'], reports: ['c'], telemetry: ['d'], commits: ['deadbeef'] },
  });
  assert.deepEqual(referencesFichiers(m), ['a', 'b', 'c', 'd']);
});

// --- coherence registre <-> depot ----------------------------------------------------

test('COHERENCE: chaque mutation ACCEPTED a une confidence DERIVABLE ou des compteurs UNKNOWN assumes', async () => {
  const reg = await REGISTRE();
  const r = await checkRegistry(reg);
  for (const m of findAccepted(reg)) {
    const c = r.confidences[m.id];
    assert.ok(c === null || (c >= 0 && c <= 1), `${m.id}: confidence ${c}`);
  }
});

// --- V2 : graphe, contrats, et readiness ---------------------------------------------

test("GRAPHE: aucune notion de preference ne peut y entrer", async () => {
  const { readFile } = await import("node:fs/promises");
  const g = JSON.parse(await readFile("forge/mutation_graph.json", "utf-8"));
  const interdits = ["score", "reward", "rank", "weight", "fitness", "preference", "better"];
  const brut = JSON.stringify(g).toLowerCase();
  for (const mot of interdits) {
    assert.ok(!brut.includes(`"${mot}`), `le graphe ne doit porter aucun champ ${mot}`);
  }
  // toute arete pointe des mutations reelles du registre
  const reg = await REGISTRE();
  const ids = new Set(loadMutation(reg).map((m) => m.id));
  for (const e of g.edges) {
    assert.ok(ids.has(e.parent), `arete parent inconnu: ${e.parent}`);
    assert.ok(ids.has(e.child), `arete enfant inconnu: ${e.child}`);
    assert.ok(["derived_from", "replaces", "contradicts"].includes(e.relation));
  }
});

test("CONTRATS: chaque metrique citee par un reward_contract est DECLAREE", async () => {
  const { readFile } = await import("node:fs/promises");
  const rps = JSON.parse(await readFile("forge/root_problems.json", "utf-8"));
  for (const rp of rps.root_problems) {
    const connues = new Set(rp.metrics.map((x) => x.name));
    assert.ok(connues.has(rp.reward_contract.objective.metric),
      `${rp.id}: objectif sur une metrique non declaree`);
    for (const c of rp.reward_contract.constraints) {
      assert.ok(connues.has(c.metric), `${rp.id}: contrainte sur une metrique non declaree`);
    }
    // aucun score global, jamais
    for (const nom of ["mutation_score", "quality_score", "global_score"]) {
      assert.ok(rp.forbidden_aggregation.includes(nom), `${rp.id}: ${nom} doit etre interdit`);
      assert.ok(!connues.has(nom), `${rp.id}: ${nom} ne peut pas etre une metrique`);
    }
  }
});

test("READINESS: une mutation ordonnable porte la metrique OBJECTIF de son contrat", async () => {
  const { readFile } = await import("node:fs/promises");
  const rps = JSON.parse(await readFile("forge/root_problems.json", "utf-8"));
  const parId = Object.fromEntries(rps.root_problems.map((r) => [r.id, r]));
  const reg = await REGISTRE();
  for (const m of loadMutation(reg)) {
    if (!m.root_problem_id) {
      assert.equal(m.status, "OBSERVED", `${m.id}: sans probleme racine => OBSERVED`);
      continue;
    }
    const obj = parId[m.root_problem_id].reward_contract.objective.metric;
    // porter la metrique n est PAS obligatoire — son absence est precisement ce que
    // le rapport de readiness compte. On verifie seulement la coherence des types.
    if (obj in m.measured_metrics) {
      assert.equal(typeof m.measured_metrics[obj], "number", `${m.id}.${obj}`);
    }
  }
});

// --- VOCABULAIRE DES LAYERS (2026-08-04) ------------------------------------------
// Une layer est une ZONE OU UNE BOUCLE PEUT CASSER. Le vocabulaire a UNE source
// (layers.json) et elle est LUE par du code — plus jamais un enum decoratif.

test('layers.json : 13 zones, chacune avec la boucle qui casse', async () => {
  const layers = await loadLayers();
  assert.equal(layers.size, 13);
  for (const [id, l] of layers) {
    assert.ok(l.broken_loop && l.broken_loop.length > 10,
      `${id} : une layer sans boucle nommee n est pas une layer`);
    assert.ok(['amont', 'aval', 'transverse'].includes(l.chain), `${id} : chain inconnue`);
  }
  // les 5 ajouts du 2026-08-04 portent la ou les lecons qui les ont fait apparaitre
  for (const id of ['preflight', 'build', 'oracle-produit', 'knowledge', 'feedback-loop']) {
    assert.ok((layers.get(id).introduced_by || []).length > 0,
      `${id} : ajoutee sans lecon justificative`);
  }
});

test('layers.json : aucune valeur qui soit un role, un fichier ou une capacite', async () => {
  const layers = await loadLayers();
  const roles = ['orchestrator', 'run_orchestrator', 'builder', 'architect', 'worldscan',
    'repair_runtime', 'deterministic', 'prisme', 'wiremap'];
  for (const id of layers.keys()) {
    assert.ok(!roles.includes(id), `« ${id} » est un ROLE de roles.yaml, pas une zone`);
    assert.ok(!id.includes('.mjs') && !id.includes('.py'), `« ${id} » est un fichier`);
  }
  // le piege evite : la layer du retour diagnostic->correction ne porte PAS un nom de role
  assert.ok(layers.has('feedback-loop'));
  assert.ok(!layers.has('orchestration'));
});

test('le vocabulaire est LU : une layer inconnue est un probleme du registre', async () => {
  const layers = await loadLayers();
  const faux = {
    schema_version: 2,
    mutations: [{ ...ECHANTILLON_DE_REFERENCE, layer: 'zone_inventee' }],
  };
  const r = await checkRegistry(faux);
  assert.ok(r.problems.some((p) => /layer 'zone_inventee' hors vocabulaire/.test(p)),
    'un enum non lu ne protege rien — celui-ci est lu');
  assert.ok([...layers.keys()].every((k) => typeof k === 'string'));
});

test('les deux schemas portent la MEME enum que la source — aucune divergence', async () => {
  const { readFile } = await import('node:fs/promises');
  const { fileURLToPath } = await import('node:url');
  const { dirname, join } = await import('node:path');
  const ici = dirname(fileURLToPath(import.meta.url));
  const source = [...(await loadLayers()).keys()];
  for (const [f, cle] of [['mutation_registry.schema.json', 'mutation'],
    ['root_problem.schema.json', 'root_problem']]) {
    const d = JSON.parse(await readFile(join(ici, f), 'utf-8'));
    assert.deepEqual(d.definitions[cle].properties.layer.enum, source,
      `${f} a diverge de layers.json`);
  }
});

test('DEPOT REEL : toutes les layers employees sont dans le vocabulaire', async () => {
  const { registre } = await loadRegistry();
  const layers = await loadLayers();
  const employees = new Set(loadMutation(registre).map((m) => m.layer).filter(Boolean));
  for (const l of employees) assert.ok(layers.has(l), `layer employee hors vocabulaire : ${l}`);
  const rp = JSON.parse(await (await import('node:fs/promises'))
    .readFile(new URL('./root_problems.json', import.meta.url), 'utf-8'));
  for (const p of rp.root_problems) {
    assert.ok(layers.has(p.layer), `root_problem ${p.id} : layer ${p.layer} hors vocabulaire`);
  }
});

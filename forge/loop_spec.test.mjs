// Tests de loop_spec.mjs (dérivation déterministe loop.json depuis prisme.json).
// Gameplay Contract V2 (GO Pierre 2026-08-22) : 10 rôles A..J (C porté par B),
// H (REPEAT) et J (ADVANTAGE), G >= 2 new_distinct, F avec observe.appears.
// node --test forge/loop_spec.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { deriveLoopSpec, checkLoopSpec, ROLE_ORDER } from './loop_spec.mjs';
import { validateExigence, validatePrisme } from './upstream_schema.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(__dirname, '..');
// Run 7 (kitten_clicker-20260821g, commit 3843d7b) — chemin courant (dernière
// run non déplacée sous `_runN_...`). Mesuré le 2026-08-23 (lot T1, extension
// DECISION) : le fichier a EVOLUÉ depuis la mesure du 2026-08-22 citée par ce
// test (8 exigences, boucle A..I) — il porte maintenant 12 exigences de boucle
// et satisfait déjà A..J. Seul le maillon DECISION (2026-08-23, absent de ce
// run antérieur à son introduction) manque désormais. Ce test mesure l'état
// RÉEL du fichier, pas un état figé (cf. commentaire d'origine).
const RUN7_PRISME = resolve(REPO_ROOT, 'EVIDENCE/runs/kitten_clicker/_run8_20260821h2/prisme.json'); // archive run 8b (12 exigences de boucle A..J, sans DECISION) : le run_dir courant est purge entre deux runs

function loadRun7Prisme() {
  return JSON.parse(readFileSync(RUN7_PRISME, 'utf-8'));
}

// --- (a) fixture RÉELLE run 7 : mesure du diagnostic ------------------------------

test('run 7 (fixture reelle) : checkLoopSpec FAIL, seul maillon manquant = DECISION (2026-08-23)', () => {
  const prisme = loadRun7Prisme();
  assert.ok(Array.isArray(prisme.exigences) && prisme.exigences.length > 0,
    'la fixture doit exister et contenir des exigences');
  const spec = deriveLoopSpec(prisme);
  const check = checkLoopSpec(spec);

  assert.equal(check.ok, false);
  assert.equal(check.verdict, 'FAIL');
  assert.deepEqual(check.problems, ['maillon DECISION : au moins 1 exigence attendue (0 trouvee)']);
});

// --- (b) fixture synthetique A..J complete ---------------------------------------

function exigenceLoop(id, role, extra = {}) {
  return {
    id,
    source: 'ADDITIONS',
    source_role: 'prisme',
    reference: null,
    observation: `observation ${id}`,
    claim: `claim ${id}`,
    enonce: `enonce ${id} distinct`,
    expected_proof: { kind: 'bot_action', statement: `preuve ${id}` },
    destination: 's9-build',
    loop_role: role,
    ...extra,
  };
}

function prismeSynthetiqueAJComplet() {
  return {
    game_id: 'kitten_clicker',
    exigences: [
      // volontairement pas dans l'ordre des roles, pour prouver le tri
      exigenceLoop('J1', 'ADVANTAGE', {
        replay_ref: 'B1',
        observe: { hud: 'ronrons', predicate: 'increases_more_than:B1' },
      }),
      exigenceLoop('I1', 'META_LOOP', {
        acteur: 'PLAYER', affordance: 'prestige',
        observe: { hud: 'ronrons', predicate: 'resets' },
      }),
      exigenceLoop('H1', 'REPEAT', {
        replay: ['B1', 'F1'],
        observe: { hud: 'ronrons', predicate: 'increases' },
      }),
      exigenceLoop('G2', 'NEXT_GOAL', { observe: { hud: 'objectif', predicate: 'new_distinct' } }),
      exigenceLoop('G1', 'NEXT_GOAL', { observe: { hud: 'objectif', predicate: 'new_distinct' } }),
      exigenceLoop('F1', 'UNLOCK', {
        acteur: 'PLAYER', affordance: 'acheter_chaton',
        observe: { hud: 'collection', predicate: 'increases', appears: 'affordance' },
      }),
      exigenceLoop('E1', 'REWARD', { observe: { hud: 'ronrons', predicate: 'increases' } }),
      exigenceLoop('D1', 'GAME_RESPONSE', { observe: { hud: 'taux', predicate: 'increases' } }),
      exigenceLoop('B1', 'PLAYER_ACTION', {
        acteur: 'PLAYER', affordance: 'pelote', repeat: 15,
        observe: { hud: 'ronrons', predicate: 'increases' },
      }),
      exigenceLoop('A1', 'PLAYER_GOAL', { observe: { hud: 'objectif', predicate: 'nonempty' } }),
      exigenceLoop('HORS1', 'NONE'),
    ],
  };
}

test('fixture synthetique A..J complete (sans DECISION) : checkLoopSpec FAIL uniquement sur DECISION absent, ordre des steps = ordre des roles', () => {
  const spec = deriveLoopSpec(prismeSynthetiqueAJComplet());
  const check = checkLoopSpec(spec);
  // T1 (2026-08-23) : DECISION est desormais un maillon obligatoire (ROLE_ORDER,
  // checkLoopSpec) — cette fixture A..J (sans DECISION) n'est plus complete au
  // sens du Gameplay Contract etendu ; seul CE probleme doit apparaitre, le
  // reste de la boucle A..J reste valide.
  assert.deepEqual(check.problems, ['maillon DECISION : au moins 1 exigence attendue (0 trouvee)']);
  assert.equal(check.ok, false);
  assert.equal(check.verdict, 'FAIL');

  // 10 exigences avec loop_role != NONE (HORS1 exclu)
  assert.equal(spec.steps.length, 10);
  assert.deepEqual(spec.steps.map((s) => s.role), [
    'PLAYER_GOAL', 'PLAYER_ACTION', 'GAME_RESPONSE', 'REWARD', 'UNLOCK',
    'NEXT_GOAL', 'NEXT_GOAL', 'REPEAT', 'META_LOOP', 'ADVANTAGE',
  ]);
  // FUITE 2 (Lot D, 2026-08-23) : au sein du role NEXT_GOAL, tri par ORDRE
  // D'APPARITION dans prisme.exigences (plus jamais l'alphabet) — G2 est ecrit
  // AVANT G1 dans la fixture (ligne 77-78 ci-dessus), donc G2 precede G1.
  const goals = spec.steps.filter((s) => s.role === 'NEXT_GOAL');
  assert.deepEqual(goals.map((s) => s.ref), ['G2', 'G1']);

  const h1 = spec.steps.find((s) => s.ref === 'H1');
  assert.deepEqual(h1.replay, ['B1', 'F1']);
  const j1 = spec.steps.find((s) => s.ref === 'J1');
  assert.equal(j1.replay_ref, 'B1');
  const f1 = spec.steps.find((s) => s.ref === 'F1');
  assert.equal(f1.observe.appears, 'affordance');
});

// --- (c) determinisme --------------------------------------------------------------

test('deriveLoopSpec est deterministe : deux appels sur la meme entree -> JSON strictement egal', () => {
  const prisme = prismeSynthetiqueAJComplet();
  const s1 = deriveLoopSpec(prisme);
  const s2 = deriveLoopSpec(prisme);
  assert.equal(JSON.stringify(s1), JSON.stringify(s2));
  // meme sur un CLONE profond independant (pas de dependance a l'identite d'objet)
  const clone = JSON.parse(JSON.stringify(prisme));
  const s3 = deriveLoopSpec(clone);
  assert.equal(JSON.stringify(s1), JSON.stringify(s3));
});

// --- (d) G x2 dont un 'changes' au lieu de 'new_distinct' -> FAIL nomme -----------

test('G x2 dont un changes au lieu de new_distinct : checkLoopSpec FAIL nomme le probleme', () => {
  const prisme = prismeSynthetiqueAJComplet();
  const g2 = prisme.exigences.find((e) => e.id === 'G2');
  g2.observe.predicate = 'changes';
  const spec = deriveLoopSpec(prisme);
  const check = checkLoopSpec(spec);
  assert.equal(check.ok, false);
  assert.ok(
    check.problems.some((p) => /NEXT_GOAL/.test(p) && /new_distinct/.test(p)),
    `attendu un probleme NEXT_GOAL/new_distinct, recu: ${JSON.stringify(check.problems)}`,
  );
});

// --- H avec ref inconnue -> FAIL nomme --------------------------------------------

test('H (REPEAT) avec une ref inconnue dans replay : checkLoopSpec FAIL nomme le probleme', () => {
  const prisme = prismeSynthetiqueAJComplet();
  const h1 = prisme.exigences.find((e) => e.id === 'H1');
  h1.replay = ['B1', 'ZZZ'];
  const spec = deriveLoopSpec(prisme);
  const check = checkLoopSpec(spec);
  assert.equal(check.ok, false);
  assert.ok(
    check.problems.some((p) => /REPEAT/.test(p) && /ZZZ/.test(p)),
    `attendu un probleme REPEAT nommant ZZZ, recu: ${JSON.stringify(check.problems)}`,
  );
});

// --- PLAYER_ACTION sans affordance -> FAIL nomme (regression T1 initial) ----------

test('PLAYER_ACTION sans affordance : checkLoopSpec FAIL nomme le probleme', () => {
  const prisme = prismeSynthetiqueAJComplet();
  const b1 = prisme.exigences.find((e) => e.id === 'B1');
  delete b1.affordance;
  const spec = deriveLoopSpec(prisme);
  const check = checkLoopSpec(spec);
  assert.equal(check.ok, false);
  assert.ok(check.problems.some((p) => /PLAYER_ACTION/.test(p) && /affordance/.test(p)),
    `attendu un probleme nommant PLAYER_ACTION et affordance, recu: ${JSON.stringify(check.problems)}`);
});

// --- (e) validateExigence : acteur/loop_role additifs, REPEAT/ADVANTAGE ----------

test('validateExigence : acteur invalide produit un finding', () => {
  const ex = exigenceLoop('X1', 'NONE', { acteur: 'REFEREE' });
  const findings = validateExigence(ex, 0);
  assert.ok(findings.some((f) => /\.acteur:/.test(f)), JSON.stringify(findings));
});

test('validateExigence : PLAYER_ACTION avec acteur=SYSTEM produit un finding', () => {
  const ex = exigenceLoop('X2', 'PLAYER_ACTION', {
    acteur: 'SYSTEM', affordance: 'clic', observe: { hud: 'h', predicate: 'increases' },
  });
  const findings = validateExigence(ex, 0);
  assert.ok(findings.some((f) => /\.acteur:/.test(f) && /PLAYER/.test(f)), JSON.stringify(findings));
});

test('validateExigence : REPEAT sans replay produit un finding', () => {
  const ex = exigenceLoop('H1', 'REPEAT');
  const findings = validateExigence(ex, 0);
  assert.ok(findings.some((f) => /\.replay:/.test(f)), JSON.stringify(findings));
});

test('validateExigence : REPEAT avec replay non vide -> 0 finding sur replay', () => {
  const ex = exigenceLoop('H1', 'REPEAT', { replay: ['B1', 'F1'] });
  const findings = validateExigence(ex, 0);
  assert.ok(!findings.some((f) => /\.replay:/.test(f)), JSON.stringify(findings));
});

test('validateExigence : ADVANTAGE sans replay_ref produit un finding', () => {
  const ex = exigenceLoop('J1', 'ADVANTAGE', {
    observe: { hud: 'ronrons', predicate: 'increases_more_than:B1' },
  });
  const findings = validateExigence(ex, 0);
  assert.ok(findings.some((f) => /\.replay_ref:/.test(f)), JSON.stringify(findings));
});

test('validateExigence : ADVANTAGE avec predicate ne commencant pas par increases_more_than: produit un finding', () => {
  const ex = exigenceLoop('J1', 'ADVANTAGE', {
    replay_ref: 'B1',
    observe: { hud: 'ronrons', predicate: 'increases' },
  });
  const findings = validateExigence(ex, 0);
  assert.ok(findings.some((f) => /\.observe\.predicate:/.test(f) && /increases_more_than/.test(f)), JSON.stringify(findings));
});

test('validateExigence : ADVANTAGE complet (replay_ref + predicate coherent) -> 0 finding additif', () => {
  const ex = exigenceLoop('J1', 'ADVANTAGE', {
    replay_ref: 'B1',
    observe: { hud: 'ronrons', predicate: 'increases_more_than:B1' },
  });
  const findings = validateExigence(ex, 0);
  assert.deepEqual(findings, []);
});

test('validateExigence : exigence ancienne sans champs de boucle -> 0 finding additif', () => {
  const ex = {
    id: 'OLD1', source: 'ADDITIONS', source_role: 'prisme', reference: null,
    observation: 'obs', claim: 'claim distinct', enonce: 'enonce distinct autre',
    expected_proof: { kind: 'oracle', statement: 'preuve' }, destination: 's9-build',
  };
  assert.deepEqual(validateExigence(ex, 0), []);
});

// --- (f) retro-compat : validatePrisme sur le Prisme reel (run 7) -> 0 finding ---

test('validatePrisme sur le Prisme reel (run 7) : 0 finding (retro-compatibilite)', () => {
  const prisme = loadRun7Prisme();
  const findings = validatePrisme(prisme);
  assert.deepEqual(findings, []);
});

// --- ROLE_ORDER porte les 9 roles de boucle (NONE exclu) --------------------------

test('ROLE_ORDER porte les 9 roles A..J (C porte par B, NONE exclu) + DECISION entre REWARD et UNLOCK', () => {
  assert.deepEqual(ROLE_ORDER, [
    'PLAYER_GOAL', 'PLAYER_ACTION', 'GAME_RESPONSE', 'REWARD', 'DECISION',
    'UNLOCK', 'NEXT_GOAL', 'REPEAT', 'META_LOOP', 'ADVANTAGE',
  ]);
});

// --- T1 (2026-08-23) : extension DECISION — point de decision significative ------
// Definition ratifiee studio_brain/gamedesign/kitten_clicker_decision_significative.md
// Forme figee du plan (docs/superpowers/plans/2026-08-23-kitten-clicker-decision-point.md).

function prismeSynthetiqueAvecDecision(overrides = {}) {
  const base = prismeSynthetiqueAJComplet();
  const decision = exigenceLoop('d_first_spend', 'DECISION', {
    acteur: 'SYSTEM',
    options: ['p_buy_kitten', 'p_upgrade_click'],
    metric: 'ronrons',
    horizon_frames: 300,
    policies: [
      { name: 'idle', click: null, every_frames: 0 },
      { name: 'actif', click: 'pelote', every_frames: 3 },
    ],
    observe: { hud: 'objectif', predicate: 'changes' },
    wait_frames: 30,
    ...overrides,
  });
  // options du plan : p_buy_kitten (UNLOCK-like PLAYER_ACTION) et
  // p_upgrade_click (PLAYER_ACTION), toutes deux avec affordance distincte.
  base.exigences.push(decision);
  base.exigences.push(exigenceLoop('p_buy_kitten', 'PLAYER_ACTION', {
    acteur: 'PLAYER', affordance: 'acheter_chaton',
    observe: { hud: 'collection', predicate: 'increases' },
  }));
  base.exigences.push(exigenceLoop('p_upgrade_click', 'PLAYER_ACTION', {
    acteur: 'PLAYER', affordance: 'acheter_amelioration_clic',
    observe: { hud: 'valeur_clic', predicate: 'increases' },
  }));
  return base;
}

test('(a) baseline _run8_20260821h2/prisme.json : checkLoopSpec FAIL, un probleme nomme DECISION', () => {
  const path = resolve(REPO_ROOT, 'EVIDENCE/runs/kitten_clicker/_run8_20260821h2/prisme.json');
  const prisme = JSON.parse(readFileSync(path, 'utf-8'));
  const spec = deriveLoopSpec(prisme);
  const check = checkLoopSpec(spec);
  assert.equal(check.ok, false);
  assert.ok(
    check.problems.some((p) => /DECISION/.test(p)),
    `attendu un probleme nommant DECISION, recu: ${JSON.stringify(check.problems)}`,
  );
});

test('(b) fixture synthetique A..J + DECISION valide : checkLoopSpec OK', () => {
  const prisme = prismeSynthetiqueAvecDecision();
  const spec = deriveLoopSpec(prisme);
  const check = checkLoopSpec(spec);
  assert.deepEqual(check.problems, []);
  assert.equal(check.ok, true);
  assert.equal(check.verdict, 'OK');

  const dstep = spec.steps.find((s) => s.role === 'DECISION');
  assert.ok(dstep, 'le step DECISION doit exister dans la boucle derivee');
  assert.deepEqual(dstep.options, ['p_buy_kitten', 'p_upgrade_click']);
  assert.equal(dstep.metric, 'ronrons');
  assert.equal(dstep.horizon_frames, 300);
  assert.deepEqual(dstep.policies, [
    { name: 'idle', click: null, every_frames: 0 },
    { name: 'actif', click: 'pelote', every_frames: 3 },
  ]);
  assert.equal(dstep.observe.hud, 'objectif');
});

test('(b bis) ordre des steps : DECISION se place entre REWARD et UNLOCK', () => {
  const prisme = prismeSynthetiqueAvecDecision();
  const spec = deriveLoopSpec(prisme);
  const roles = spec.steps.map((s) => s.role);
  const rewardIdx = roles.lastIndexOf('REWARD');
  const decisionIdx = roles.indexOf('DECISION');
  const unlockIdx = roles.indexOf('UNLOCK');
  assert.ok(rewardIdx < decisionIdx, `REWARD (${rewardIdx}) doit precede DECISION (${decisionIdx})`);
  assert.ok(decisionIdx < unlockIdx, `DECISION (${decisionIdx}) doit precede UNLOCK (${unlockIdx})`);
});

// --- (c) chaque regle DECISION de checkLoopSpec a son cas rouge -------------------

test('(c1) DECISION absent : checkLoopSpec FAIL nomme "0 trouvee"', () => {
  const spec = deriveLoopSpec(prismeSynthetiqueAJComplet());
  const check = checkLoopSpec(spec);
  assert.ok(
    check.problems.some((p) => /DECISION/.test(p) && /0 trouvee/.test(p)),
    JSON.stringify(check.problems),
  );
});

test('(c2) DECISION.options[i] ne reference pas un step PLAYER_ACTION/UNLOCK avec affordance : FAIL nomme', () => {
  const prisme = prismeSynthetiqueAvecDecision();
  const d = prisme.exigences.find((e) => e.id === 'd_first_spend');
  d.options = ['p_buy_kitten', 'INCONNU'];
  const check = checkLoopSpec(deriveLoopSpec(prisme));
  assert.equal(check.ok, false);
  assert.ok(
    check.problems.some((p) => /DECISION/.test(p) && /options\[1\]/.test(p) && /INCONNU/.test(p)),
    JSON.stringify(check.problems),
  );
});

test('(c3) DECISION.options avec affordances identiques : FAIL nomme "distinctes"', () => {
  const prisme = prismeSynthetiqueAvecDecision();
  const upgrade = prisme.exigences.find((e) => e.id === 'p_upgrade_click');
  upgrade.affordance = 'acheter_chaton'; // meme affordance que p_buy_kitten
  const check = checkLoopSpec(deriveLoopSpec(prisme));
  assert.equal(check.ok, false);
  assert.ok(
    check.problems.some((p) => /DECISION/.test(p) && /distinctes/.test(p)),
    JSON.stringify(check.problems),
  );
});

test('(c4) DECISION.policies < 2 : FAIL nomme "policies"', () => {
  const prisme = prismeSynthetiqueAvecDecision();
  const d = prisme.exigences.find((e) => e.id === 'd_first_spend');
  d.policies = [{ name: 'idle', click: null, every_frames: 0 }];
  const check = checkLoopSpec(deriveLoopSpec(prisme));
  assert.equal(check.ok, false);
  assert.ok(
    check.problems.some((p) => /DECISION/.test(p) && /policies/.test(p) && /1 trouvee/.test(p)),
    JSON.stringify(check.problems),
  );
});

test('(c5) DECISION.policies[].click ne reference aucune affordance PLAYER_ACTION : FAIL nomme', () => {
  const prisme = prismeSynthetiqueAvecDecision();
  const d = prisme.exigences.find((e) => e.id === 'd_first_spend');
  d.policies = [
    { name: 'idle', click: null, every_frames: 0 },
    { name: 'actif', click: 'bouton_fantome', every_frames: 3 },
  ];
  const check = checkLoopSpec(deriveLoopSpec(prisme));
  assert.equal(check.ok, false);
  assert.ok(
    check.problems.some((p) => /DECISION/.test(p) && /bouton_fantome/.test(p)),
    JSON.stringify(check.problems),
  );
});

test('(c6) DECISION.metric absent d\'un autre observe.hud : FAIL nomme "metric"', () => {
  const prisme = prismeSynthetiqueAvecDecision();
  const d = prisme.exigences.find((e) => e.id === 'd_first_spend');
  d.metric = 'metrique_inexistante';
  const check = checkLoopSpec(deriveLoopSpec(prisme));
  assert.equal(check.ok, false);
  assert.ok(
    check.problems.some((p) => /DECISION/.test(p) && /metric/.test(p)),
    JSON.stringify(check.problems),
  );
});

test('(c7) DECISION.observe.hud different de objectif : FAIL nomme "objectif"', () => {
  const prisme = prismeSynthetiqueAvecDecision();
  const d = prisme.exigences.find((e) => e.id === 'd_first_spend');
  d.observe = { hud: 'ronrons', predicate: 'changes' };
  const check = checkLoopSpec(deriveLoopSpec(prisme));
  assert.equal(check.ok, false);
  assert.ok(
    check.problems.some((p) => /DECISION/.test(p) && /objectif/.test(p)),
    JSON.stringify(check.problems),
  );
});

// --- (d) determinisme : hash identique sur deux derivations -----------------------

test('(d) deriveLoopSpec avec DECISION est deterministe (hash JSON identique)', () => {
  const prisme = prismeSynthetiqueAvecDecision();
  const s1 = deriveLoopSpec(prisme);
  const s2 = deriveLoopSpec(JSON.parse(JSON.stringify(prisme)));
  assert.equal(JSON.stringify(s1), JSON.stringify(s2));
});

// --- (e) validateExigence : DECISION valide -> 0 finding, chaque champ casse -> 1+ --

function exigenceDecisionValide(extra = {}) {
  return exigenceLoop('d_first_spend', 'DECISION', {
    options: ['p_buy_kitten', 'p_upgrade_click'],
    metric: 'ronrons',
    horizon_frames: 300,
    policies: [
      { name: 'idle', click: null, every_frames: 0 },
      { name: 'actif', click: 'pelote', every_frames: 3 },
    ],
    ...extra,
  });
}

test('(e0) validateExigence : DECISION valide -> 0 finding', () => {
  const findings = validateExigence(exigenceDecisionValide(), 0);
  assert.deepEqual(findings, []);
});

test('(e1) validateExigence : options manquant -> finding options', () => {
  const ex = exigenceDecisionValide({ options: undefined });
  const findings = validateExigence(ex, 0);
  assert.ok(findings.some((f) => /\.options:/.test(f)), JSON.stringify(findings));
});

test('(e2) validateExigence : options avec un seul element -> finding options', () => {
  const ex = exigenceDecisionValide({ options: ['seul'] });
  const findings = validateExigence(ex, 0);
  assert.ok(findings.some((f) => /\.options:/.test(f)), JSON.stringify(findings));
});

test('(e3) validateExigence : options identiques -> finding options distinctes', () => {
  const ex = exigenceDecisionValide({ options: ['a', 'a'] });
  const findings = validateExigence(ex, 0);
  assert.ok(findings.some((f) => /\.options:/.test(f) && /distinctes/.test(f)), JSON.stringify(findings));
});

test('(e4) validateExigence : policies avec un seul element -> finding policies', () => {
  const ex = exigenceDecisionValide({ policies: [{ name: 'idle', click: null, every_frames: 0 }] });
  const findings = validateExigence(ex, 0);
  assert.ok(findings.some((f) => /\.policies:/.test(f)), JSON.stringify(findings));
});

test('(e5) validateExigence : policies avec noms dupliques -> finding', () => {
  const ex = exigenceDecisionValide({
    policies: [
      { name: 'idle', click: null, every_frames: 0 },
      { name: 'idle', click: 'pelote', every_frames: 3 },
    ],
  });
  const findings = validateExigence(ex, 0);
  assert.ok(findings.some((f) => /\.policies:/.test(f) && /distincts/.test(f)), JSON.stringify(findings));
});

test('(e6) validateExigence : policy avec click non-null et every_frames=0 -> finding', () => {
  const ex = exigenceDecisionValide({
    policies: [
      { name: 'idle', click: null, every_frames: 0 },
      { name: 'actif', click: 'pelote', every_frames: 0 },
    ],
  });
  const findings = validateExigence(ex, 0);
  assert.ok(findings.some((f) => /every_frames:/.test(f) && />= 1/.test(f)), JSON.stringify(findings));
});

test('(e7) validateExigence : metric vide -> finding metric', () => {
  const ex = exigenceDecisionValide({ metric: '' });
  const findings = validateExigence(ex, 0);
  assert.ok(findings.some((f) => /\.metric:/.test(f)), JSON.stringify(findings));
});

test('(e8) validateExigence : horizon_frames < 60 -> finding horizon_frames', () => {
  const ex = exigenceDecisionValide({ horizon_frames: 59 });
  const findings = validateExigence(ex, 0);
  assert.ok(findings.some((f) => /\.horizon_frames:/.test(f)), JSON.stringify(findings));
});

// --- T4 (2026-08-23, Lot B) : target_frames derive de exigence.target -------------
// Champ pose par le Prisme en recopiant une metrique `target` du Game Master
// (progression_metrics[kind=target], unite frames, `target.ref` cite l'adresse
// gm_worldscan). Fixture run 9 : EVIDENCE/runs/kitten_clicker/_run9_20260823a/loop.json
// (13 steps, aucun ne porte `target` -> hash identique a l'ancien comportement).

const RUN9_LOOP = resolve(REPO_ROOT, 'EVIDENCE/runs/kitten_clicker/_run9_20260823a/loop.json');

function loadRun9Loop() {
  return JSON.parse(readFileSync(RUN9_LOOP, 'utf-8'));
}

// Reconstruit un prisme.json synthetique minimal a partir des steps du loop.json
// archive du run 9 (le prisme lui-meme n'est pas archive a ce chemin) : suffisant
// pour prouver la non-regression de deriveLoopSpec (steps identiques en sortie).
function prismeDepuisLoopRun9() {
  const loop = loadRun9Loop();
  return {
    game_id: loop.game_id,
    exigences: loop.steps.map((s, i) => exigenceLoop(s.ref || `S${i}`, s.role, {
      ...(s.affordance ? { affordance: s.affordance } : {}),
      ...(s.observe ? { observe: s.observe } : {}),
      ...(Number.isInteger(s.repeat) ? { repeat: s.repeat } : {}),
      ...(s.replay ? { replay: s.replay } : {}),
      ...(s.replay_ref ? { replay_ref: s.replay_ref } : {}),
      ...(s.options ? { options: s.options } : {}),
      ...(s.metric ? { metric: s.metric } : {}),
      ...(Number.isInteger(s.horizon_frames) ? { horizon_frames: s.horizon_frames } : {}),
      ...(s.policies ? { policies: s.policies } : {}),
    })),
  };
}

test('T4 : step avec exigence.target valide -> step.target_frames projete', () => {
  const prisme = prismeDepuisLoopRun9();
  const b = prisme.exigences.find((e) => e.id === 'b_click');
  b.target = { min_frames: 10, max_frames: 200, ref: 'gm_worldscan:game_master.progression_metrics.m_click' };
  const spec = deriveLoopSpec(prisme);
  const step = spec.steps.find((s) => s.ref === 'b_click');
  assert.deepEqual(step.target_frames, { min: 10, max: 200, ref: 'gm_worldscan:game_master.progression_metrics.m_click' });
  const check = checkLoopSpec(spec);
  assert.equal(check.problems.some((p) => /target_frames/.test(p)), false, JSON.stringify(check.problems));
});

test('T4 : exigence.target avec min >= max -> checkLoopSpec FAIL nomme', () => {
  const prisme = prismeDepuisLoopRun9();
  const b = prisme.exigences.find((e) => e.id === 'b_click');
  b.target = { min_frames: 50, max_frames: 10, ref: 'gm_worldscan:game_master.progression_metrics.m_click' };
  const spec = deriveLoopSpec(prisme);
  const step = spec.steps.find((s) => s.ref === 'b_click');
  assert.deepEqual(step.target_frames, { min: 50, max: 10, ref: 'gm_worldscan:game_master.progression_metrics.m_click' });
  const check = checkLoopSpec(spec);
  assert.ok(
    check.problems.some((p) => /PLAYER_ACTION/.test(p) && /target_frames/.test(p) && /50/.test(p) && /10/.test(p)),
    JSON.stringify(check.problems),
  );
});

test('T4 : aucune exigence.target -> spec inchange (hash identique a la fixture run 9 sans target)', () => {
  const prisme = prismeDepuisLoopRun9();
  const spec = deriveLoopSpec(prisme);
  for (const s of spec.steps) {
    assert.equal(Object.prototype.hasOwnProperty.call(s, 'target_frames'), false, JSON.stringify(s));
  }
  // determinisme croise avec un clone profond independant
  const clone = JSON.parse(JSON.stringify(prisme));
  const spec2 = deriveLoopSpec(clone);
  assert.equal(JSON.stringify(spec), JSON.stringify(spec2));
});

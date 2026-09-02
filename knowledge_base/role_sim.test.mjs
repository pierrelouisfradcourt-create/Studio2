// role_sim.test.mjs — tests du ROLE-SIM Oracle (GÉNÉRIQUE depuis le 2e rôle). node --test,
// zéro réseau, zéro LLM. measureDifficultyBand est maintenant agnostique à la mécanique de
// jeu — testé ici avec le scénario réel pursuer_scenario.mjs (même comportement que
// l'ancien role_sim.mjs monolithique, vérifié par extraction inchangée) ET un scénario
// factice minimal (pour prouver la généricité elle-même, pas seulement rejouer pursuer).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { measureDifficultyBand, checkSimulationRuntime, checkSimulationRuntimePresence, loadRole } from './role_sim.mjs';
import { runTrial as pursuerRunTrial } from './systems/ai/pursuer_scenario.mjs';

const PURSUER_CFG = { trials: 50, seed_start: 1, max_ticks: 60, arena_half_size: 20, catch_radius: 1, pursuer_speed: 2, evader_speed: 1 };

test('measureDifficultyBand : déterministe — deux appels identiques donnent le même résultat exact', () => {
  const a = measureDifficultyBand(PURSUER_CFG, pursuerRunTrial);
  const b = measureDifficultyBand(PURSUER_CFG, pursuerRunTrial);
  assert.deepEqual(a, b);
});

test('measureDifficultyBand : un poursuivant plus rapide (speed=2) capture presque toujours un fuyard plus lent (speed=1)', () => {
  const cfg = { ...PURSUER_CFG, trials: 100 };
  const result = measureDifficultyBand(cfg, pursuerRunTrial);
  assert.ok(result.successRate > 0.9, `success_rate doit être élevé quand pursuer_speed > evader_speed, got ${result.successRate}`);
});

test('measureDifficultyBand : un poursuivant à la MÊME vitesse que le fuyard ne le rattrape jamais en terrain ouvert', () => {
  const cfg = { ...PURSUER_CFG, trials: 30, pursuer_speed: 1, evader_speed: 1 };
  const result = measureDifficultyBand(cfg, pursuerRunTrial);
  assert.equal(result.successRate, 0, `à vitesse égale, le fuyard maintient toujours la distance, got successRate=${result.successRate}`);
});

test('measureDifficultyBand : ticksToSucceed est trié croissant et de longueur == succeeded', () => {
  const cfg = { ...PURSUER_CFG, trials: 80, seed_start: 5 };
  const result = measureDifficultyBand(cfg, pursuerRunTrial);
  assert.equal(result.ticksToSucceed.length, result.succeeded);
  for (let i = 1; i < result.ticksToSucceed.length; i += 1) {
    assert.ok(result.ticksToSucceed[i] >= result.ticksToSucceed[i - 1], 'ticksToSucceed doit être trié croissant');
  }
});

test('measureDifficultyBand : changer seed_start change l\'échantillon (pas les mêmes essais)', () => {
  const cfgA = { ...PURSUER_CFG, trials: 50, seed_start: 1 };
  const cfgB = { ...PURSUER_CFG, trials: 50, seed_start: 1000 };
  const a = measureDifficultyBand(cfgA, pursuerRunTrial);
  const b = measureDifficultyBand(cfgB, pursuerRunTrial);
  assert.notDeepEqual(a.ticksToSucceed, b.ticksToSucceed, 'deux plages de seeds disjointes ne doivent pas produire exactement la même trace');
});

// ---- Preuve de GÉNÉRICITÉ : un scénario factice, sans rapport avec la poursuite ----
test('measureDifficultyBand : est réellement agnostique au scénario — un runTrial factice fonctionne sans modification', () => {
  // Scénario trivial : "succès" ssi seed est pair, ticks = seed % 10.
  function toyRunTrial(seed) {
    return seed % 2 === 0 ? { succeeded: true, ticks: seed % 10 } : { succeeded: false, ticks: null };
  }
  const cfg = { trials: 20, seed_start: 1 };
  const result = measureDifficultyBand(cfg, toyRunTrial);
  assert.equal(result.succeeded, 10, '10 seeds pairs sur 20 essais consécutifs à partir de 1');
  assert.equal(result.successRate, 0.5);
});

// ---- Garde fail-closed sur simulation_runtime (spec étape 0 §5) ----
test('simulation_runtime absent -> defaut node, aucun finding (retrocompatible)', () => {
  assert.deepEqual(checkSimulationRuntime(null), []);
});

test('simulation_runtime: godot -> implemente, aucun finding', () => {
  assert.deepEqual(checkSimulationRuntime('godot'), []);
});

test('simulation_runtime: node -> implemente, aucun finding', () => {
  assert.deepEqual(checkSimulationRuntime('node'), []);
});

test('simulation_runtime: unity -> RESERVE mais non implemente -> finding explicite', () => {
  const f = checkSimulationRuntime('unity');
  assert.equal(f.length, 1);
  assert.match(f[0], /reconnu par le schema, non implemente/);
});

test('simulation_runtime: unreal -> reserve, meme traitement', () => {
  assert.equal(checkSimulationRuntime('unreal').length, 1);
});

test('simulation_runtime inconnu -> finding, jamais un silence', () => {
  const f = checkSimulationRuntime('bricolage');
  assert.equal(f.length, 1);
  assert.match(f[0], /inconnu/);
});

// ---- Finding revue 1 : la garde est contournable en changeant la mise en forme YAML ----
// checkSimulationRuntime(null) est délibérément silencieux (rétrocompatibilité champ absent).
// Mais une clé PRÉSENTE dont la valeur n'est pas un scalaire exploitable (liste, bloc, vide)
// est actuellement extraite comme `null` par extractScalar — indiscernable d'un champ absent.
// checkSimulationRuntimePresence(text) doit distinguer les deux à partir du TEXTE du contrat,
// pas de la valeur déjà extraite (c'est justement la valeur extraite qui ment).

test('simulation_runtime absent du texte -> checkSimulationRuntimePresence ne trouve rien (recontrôle du cas rétrocompatible)', () => {
  const text = 'role_id: role-x\narchetype: >-\n  une description suffisamment longue\n';
  assert.deepEqual(checkSimulationRuntimePresence(text).findings, []);
});

test('simulation_runtime en LISTE YAML (contournement rapporté) -> finding explicite, jamais un silence', () => {
  const text = 'role_id: role-x\nsimulation_runtime:\n  - unity\n  - unreal\n';
  const { findings } = checkSimulationRuntimePresence(text);
  assert.equal(findings.length, 1, 'une liste ne doit plus se comporter comme un champ absent');
  assert.match(findings[0], /illisible/i);
});

test('simulation_runtime present sans aucune valeur -> finding explicite', () => {
  const text = 'role_id: role-x\nsimulation_runtime:\nlicense: MIT\n';
  const { findings } = checkSimulationRuntimePresence(text);
  assert.equal(findings.length, 1);
  assert.match(findings[0], /illisible/i);
});

test('simulation_runtime: unity  # commentaire -> finding RESERVE (pas INCONNU), commentaire ignoré', () => {
  const text = 'role_id: role-x\nsimulation_runtime: unity  # todo verifier plus tard\nlicense: MIT\n';
  const { findings } = checkSimulationRuntimePresence(text);
  assert.equal(findings.length, 1);
  assert.match(findings[0], /reconnu par le schema, non implemente/, 'doit tomber dans le seau RESERVE, pas INCONNU');
  assert.doesNotMatch(findings[0], /inconnu/);
});

test('simulation_runtime: Godot (mauvaise casse) -> finding qui nomme explicitement la casse et l\'orthographe attendue', () => {
  const { findings } = checkSimulationRuntimePresence('simulation_runtime: Godot\n');
  assert.equal(findings.length, 1);
  assert.match(findings[0], /casse/i);
  assert.match(findings[0], /godot/, "doit citer l'orthographe attendue en minuscules");
});

test('simulation_runtime: godot (bonne casse) -> toujours accepte via checkSimulationRuntimePresence', () => {
  assert.deepEqual(checkSimulationRuntimePresence('simulation_runtime: godot\n').findings, []);
});

// ---- Reproduction fidèle du contournement rapporté, au niveau loadRole (fichier réel) ----

function makeMinimalRoleFixture(simulationRuntimeLine) {
  const root = mkdtempSync(join(tmpdir(), 'role-sim-guard-'));
  const filePath = join(root, 'role-fixture.yaml');
  const text = `role_id: role-test-fixture
archetype: >-
  description suffisamment longue pour depasser vingt caracteres, exigee par loadRole.
requires:
  dummy: fn() -> void
simulation_module: knowledge_base/systems/ai/pursuer_scenario.mjs
simulation_config:
  trials: 5
  seed_start: 1
difficulty_target:
  metric: success_rate
  min: 0
  max: 1
tier: candidate
license: MIT
path: ${filePath}
${simulationRuntimeLine}
`;
  writeFileSync(filePath, text);
  return { root, filePath };
}

test('loadRole : simulation_runtime en liste YAML (contournement reel rapporte par le controleur) -> contrat INVALIDE', () => {
  const { root, filePath } = makeMinimalRoleFixture('simulation_runtime:\n  - unity\n  - unreal');
  try {
    const { findings } = loadRole(filePath);
    const hit = findings.filter((f) => /simulation_runtime/.test(f));
    assert.equal(hit.length, 1, `attendu exactement 1 finding simulation_runtime, trouve: ${JSON.stringify(findings)}`);
    assert.match(hit[0], /illisible/i);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('loadRole : simulation_runtime absent du contrat (retrocompatibilite) -> aucun finding lie a simulation_runtime', () => {
  const { root, filePath } = makeMinimalRoleFixture('');
  try {
    const { findings } = loadRole(filePath);
    const hit = findings.filter((f) => /simulation_runtime/.test(f));
    assert.deepEqual(hit, []);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

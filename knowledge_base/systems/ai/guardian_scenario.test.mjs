// guardian_scenario.test.mjs — tests du scénario role-guardian-static, dont la preuve
// que l'effet mesuré vient bien de la zone de contrôle (pas d'un artefact du chemin).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { runTrial, runTrialWithoutZone } from './guardian_scenario.mjs';

const CFG = { arena_half_size: 20, zoc_radius: 4, attacker_speed: 2, crossing_half_distance: 11, max_ticks: 60 };

test('déterminisme : même seed -> même résultat exact', () => {
  const a = runTrial(1, CFG);
  const b = runTrial(1, CFG);
  assert.deepEqual(a, b);
});

test('toujours succeeded=true dans le budget de ticks (la zone ralentit, elle ne bloque jamais)', () => {
  for (let seed = 1; seed <= 50; seed += 1) {
    const r = runTrial(seed, CFG);
    assert.equal(r.succeeded, true, `seed=${seed} doit toujours atteindre l'objectif`);
  }
});

test('preuve que l\'effet mesuré vient bien de la zone (pas un artefact du chemin) : jamais d\'accélération, au moins un délai réel sur 300 essais', () => {
  let anyDelay = false;
  for (let seed = 1; seed <= 300; seed += 1) {
    const withZone = runTrial(seed, CFG);
    const withoutZone = runTrialWithoutZone(seed, CFG);
    assert.ok(withZone.ticks >= withoutZone.ticks, `seed=${seed}: la zone ne doit jamais accélérer (with=${withZone.ticks} < without=${withoutZone.ticks})`);
    if (withZone.ticks > withoutZone.ticks) anyDelay = true;
  }
  assert.ok(anyDelay, 'au moins un essai sur 300 doit montrer un délai réel dû à la zone (sinon le scénario ne teste rien)');
});

test('le délai mesuré est TOUJOURS de 1 tick exactement (jamais plus, jamais accumulé) — cf. contrat "la zone surprend, n\'emprisonne pas"', () => {
  for (let seed = 1; seed <= 300; seed += 1) {
    const withZone = runTrial(seed, CFG);
    const withoutZone = runTrialWithoutZone(seed, CFG);
    const delta = withZone.ticks - withoutZone.ticks;
    assert.ok(delta === 0 || delta === 1, `seed=${seed}: delta doit être 0 ou 1, got ${delta}`);
  }
});

test('changer seed_start (implicite via seed) change l\'échantillon des hauteurs', () => {
  const a = [];
  const b = [];
  for (let i = 0; i < 20; i += 1) a.push(runTrial(1 + i, CFG).ticks);
  for (let i = 0; i < 20; i += 1) b.push(runTrial(1000 + i, CFG).ticks);
  assert.notDeepEqual(a, b);
});

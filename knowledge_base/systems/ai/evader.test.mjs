// Property-tests pour sys-evader-basic (stepAway).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { stepAway } from './evader.mjs';
import { chebyshevDistance } from './pursuer.mjs';

test('invariant : jamais plus de `speed` pas (Chebyshev) parcourus en un tick', () => {
  const pos = { x: 0, y: 0 };
  const threat = { x: 5, y: 5 };
  for (const speed of [0, 1, 2, 5, 10]) {
    const next = stepAway(pos, threat, speed);
    assert.ok(chebyshevDistance(pos, next) <= speed);
  }
});

test('speed=0 : la position ne bouge jamais', () => {
  const pos = { x: 5, y: 5 };
  const next = stepAway(pos, { x: 0, y: 0 }, 0);
  assert.deepEqual(next, pos);
});

test('la distance à la menace ne peut jamais diminuer après un pas (fuite pure)', () => {
  const pos = { x: 10, y: 10 };
  const threat = { x: 0, y: 0 };
  const before = chebyshevDistance(pos, threat);
  const next = stepAway(pos, threat, 2);
  const after = chebyshevDistance(next, threat);
  assert.ok(after >= before, `distance après (${after}) doit être >= distance avant (${before})`);
});

test('cas dégénéré (menace exactement sur la même case) : ne reste jamais bloqué', () => {
  const next = stepAway({ x: 3, y: 3 }, { x: 3, y: 3 }, 1);
  assert.notDeepEqual(next, { x: 3, y: 3 });
});

test('déterminisme : mêmes entrées -> même sortie, sur 200 configurations', () => {
  for (let i = 0; i < 200; i += 1) {
    const pos = { x: i - 50, y: (i * 5) % 30 };
    const threat = { x: (i * 2) % 40, y: i - 20 };
    const speed = i % 4;
    const a = stepAway(pos, threat, speed);
    const b = stepAway(pos, threat, speed);
    assert.deepEqual(a, b);
  }
});

test('speed non fini ou négatif -> RangeError', () => {
  assert.throws(() => stepAway({ x: 0, y: 0 }, { x: 1, y: 1 }, -1), RangeError);
  assert.throws(() => stepAway({ x: 0, y: 0 }, { x: 1, y: 1 }, NaN), RangeError);
});

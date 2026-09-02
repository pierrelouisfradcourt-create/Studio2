// Property-tests pour sys-pursuer-mobile (stepToward, chebyshevDistance).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { stepToward, chebyshevDistance } from './pursuer.mjs';

test('invariant : jamais plus de `speed` pas (Chebyshev) parcourus en un tick', () => {
  const pos = { x: 0, y: 0 };
  const target = { x: 100, y: 100 };
  for (const speed of [0, 1, 2, 5, 10]) {
    const next = stepToward(pos, target, speed);
    const moved = chebyshevDistance(pos, next);
    assert.ok(moved <= speed, `speed=${speed} : déplacement Chebyshev ${moved} doit être <= ${speed}`);
  }
});

test('speed=0 : la position ne bouge jamais', () => {
  const pos = { x: 5, y: 5 };
  const next = stepToward(pos, { x: 20, y: 20 }, 0);
  assert.deepEqual(next, pos);
});

test('atteint exactement la cible sans la dépasser quand speed >= distance', () => {
  const next = stepToward({ x: 0, y: 0 }, { x: 3, y: 1 }, 10);
  assert.deepEqual(next, { x: 3, y: 1 });
});

test('la distance à la cible ne peut jamais augmenter après un pas (poursuite pure)', () => {
  const pos = { x: -5, y: 12 };
  const target = { x: 8, y: -3 };
  const before = chebyshevDistance(pos, target);
  const next = stepToward(pos, target, 3);
  const after = chebyshevDistance(next, target);
  assert.ok(after <= before, `distance après (${after}) doit être <= distance avant (${before})`);
});

test('déterminisme : mêmes entrées -> même sortie, sur 200 configurations', () => {
  for (let i = 0; i < 200; i += 1) {
    const pos = { x: i - 100, y: (i * 7) % 50 };
    const target = { x: (i * 3) % 80, y: i - 40 };
    const speed = i % 5;
    const a = stepToward(pos, target, speed);
    const b = stepToward(pos, target, speed);
    assert.deepEqual(a, b);
  }
});

test('chebyshevDistance : cas connus', () => {
  assert.equal(chebyshevDistance({ x: 0, y: 0 }, { x: 3, y: 4 }), 4);
  assert.equal(chebyshevDistance({ x: 0, y: 0 }, { x: 0, y: 0 }), 0);
  assert.equal(chebyshevDistance({ x: -2, y: -2 }, { x: 2, y: 2 }), 4);
});

test('speed non fini ou négatif -> RangeError (pas un NaN silencieux)', () => {
  assert.throws(() => stepToward({ x: 0, y: 0 }, { x: 1, y: 1 }, -1), RangeError);
  assert.throws(() => stepToward({ x: 0, y: 0 }, { x: 1, y: 1 }, NaN), RangeError);
});

// Property-tests pour sys-pursuer-continuous (seekToward, euclideanDistance).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { seekToward, euclideanDistance } from './pursuer_continuous.mjs';

test('avance vers la cible en ligne droite : les DEUX axes bougent simultanément (pas de dogleg en L)', () => {
  const pos = { x: 0, y: 0 };
  const target = { x: 100, y: 100 };
  const next = seekToward(pos, target, 10, 1);
  assert.ok(next.x > 0 && next.y > 0, `les deux axes doivent bouger ensemble, got ${JSON.stringify(next)}`);
  assert.ok(Math.abs(next.x - next.y) < 1e-9, 'sur une diagonale à 45°, x et y doivent avancer à parts égales');
});

test('ne dépasse jamais la cible : si speed*dt >= distance, atterrit EXACTEMENT sur la cible', () => {
  const next = seekToward({ x: 0, y: 0 }, { x: 3, y: 4 }, 100, 1); // distance=5, budget=100
  assert.equal(next.x, 3);
  assert.equal(next.y, 4);
});

test('la distance à la cible ne peut jamais augmenter après un pas', () => {
  const pos = { x: -5, y: 12 };
  const target = { x: 8, y: -3 };
  const before = euclideanDistance(pos, target);
  const next = seekToward(pos, target, 3, 1);
  const after = euclideanDistance(next, target);
  assert.ok(after <= before + 1e-9, `distance après (${after}) doit être <= distance avant (${before})`);
});

test('speed=0, dt=0, ou déjà sur la cible : aucun mouvement, pas de NaN', () => {
  assert.deepEqual(seekToward({ x: 1, y: 1 }, { x: 9, y: 9 }, 0, 1), { x: 1, y: 1 });
  assert.deepEqual(seekToward({ x: 1, y: 1 }, { x: 9, y: 9 }, 5, 0), { x: 1, y: 1 });
  const same = seekToward({ x: 4, y: 4 }, { x: 4, y: 4 }, 5, 1);
  assert.deepEqual(same, { x: 4, y: 4 });
  assert.ok(Number.isFinite(same.x) && Number.isFinite(same.y), 'jamais NaN, même à distance nulle');
});

test('déterminisme : mêmes entrées -> même sortie, sur 200 configurations', () => {
  for (let i = 0; i < 200; i += 1) {
    const pos = { x: i - 100, y: (i * 1.3) % 50 };
    const target = { x: (i * 2.7) % 80, y: i - 40 };
    const speed = i % 10;
    const dt = (i % 5) * 0.1;
    const a = seekToward(pos, target, speed, dt);
    const b = seekToward(pos, target, speed, dt);
    assert.deepEqual(a, b);
  }
});

test('vitesse effective observée == speed déclaré (unités/seconde), tant que la cible est loin', () => {
  const pos = { x: 0, y: 0 };
  const target = { x: 1000, y: 0 }; // très loin, jamais atteint sur ce pas
  const next = seekToward(pos, target, 25, 2); // 25 unites/s * 2s = 50
  assert.ok(Math.abs(euclideanDistance(pos, next) - 50) < 1e-9);
});

test('speed ou dt négatif/non fini -> RangeError', () => {
  assert.throws(() => seekToward({ x: 0, y: 0 }, { x: 1, y: 1 }, -1, 1), RangeError);
  assert.throws(() => seekToward({ x: 0, y: 0 }, { x: 1, y: 1 }, 1, -1), RangeError);
  assert.throws(() => seekToward({ x: 0, y: 0 }, { x: 1, y: 1 }, NaN, 1), RangeError);
});

test('euclideanDistance : cas connus (triangle 3-4-5)', () => {
  assert.equal(euclideanDistance({ x: 0, y: 0 }, { x: 3, y: 4 }), 5);
  assert.equal(euclideanDistance({ x: 0, y: 0 }, { x: 0, y: 0 }), 0);
});

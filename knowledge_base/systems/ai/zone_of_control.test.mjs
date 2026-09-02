// Property-tests pour sys-guardian-zoc (isInZone, stepTowardWithZoC).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { isInZone, stepTowardWithZoC } from './zone_of_control.mjs';

test('isInZone : cas connus (Chebyshev, radius=1)', () => {
  assert.equal(isInZone({ x: 0, y: 0 }, { x: 0, y: 0 }, 1), true);
  assert.equal(isInZone({ x: 1, y: 1 }, { x: 0, y: 0 }, 1), true);
  assert.equal(isInZone({ x: 2, y: 0 }, { x: 0, y: 0 }, 1), false);
});

test('un mouvement qui n\'entre jamais dans la zone n\'est jamais tronqué', () => {
  const pos = { x: -20, y: 20 };
  const target = { x: -10, y: 20 };
  const guardian = { x: 0, y: 0 };
  const next = stepTowardWithZoC(pos, target, 5, guardian, 1);
  assert.deepEqual(next, { x: -15, y: 20 }, 'aucune ZoC sur ce chemin : mouvement complet, non tronqué');
});

test('une entrée FRAÎCHE dans la zone tronque le mouvement à la case d\'entrée', () => {
  // Départ à distance 3 du gardien (hors zone, radius=1), vise à traverser tout droit.
  const pos = { x: -3, y: 0 };
  const target = { x: 3, y: 0 };
  const guardian = { x: 0, y: 0 };
  const next = stepTowardWithZoC(pos, target, 5, guardian, 1);
  // Sans ZoC, 5 pas emmèneraient à x=2. Avec ZoC (radius=1), le mouvement doit s'arrêter
  // dès l'entrée en zone, soit à x=-1 (première case avec |x|<=1).
  assert.deepEqual(next, { x: -1, y: 0 });
  assert.ok(isInZone(next, guardian, 1), 'la position finale doit être DANS la zone (entrée, pas évitement)');
});

test('si on est DÉJÀ dans la zone au début du tick, pas de troncature ce tick (la ZoC ne piège pas)', () => {
  const pos = { x: 0, y: 0 }; // déjà dans la zone (radius=1, distance 0)
  const target = { x: 10, y: 0 };
  const guardian = { x: 0, y: 0 };
  const next = stepTowardWithZoC(pos, target, 5, guardian, 1);
  assert.deepEqual(next, { x: 5, y: 0 }, 'mouvement complet — déjà dans la zone, pas une entrée fraîche');
});

test('speed=0 : la position ne bouge jamais, avec ou sans zone', () => {
  const pos = { x: 5, y: 5 };
  const next = stepTowardWithZoC(pos, { x: 20, y: 20 }, 0, { x: 0, y: 0 }, 10);
  assert.deepEqual(next, pos);
});

test('déterminisme : mêmes entrées -> même sortie, sur 100 configurations', () => {
  for (let i = 0; i < 100; i += 1) {
    const pos = { x: i - 50, y: (i * 3) % 40 };
    const target = { x: (i * 7) % 60 - 30, y: i - 25 };
    const guardian = { x: 0, y: 0 };
    const speed = i % 4;
    const radius = i % 5;
    const a = stepTowardWithZoC(pos, target, speed, guardian, radius);
    const b = stepTowardWithZoC(pos, target, speed, guardian, radius);
    assert.deepEqual(a, b);
  }
});

test('speed non fini ou négatif -> RangeError', () => {
  assert.throws(() => stepTowardWithZoC({ x: 0, y: 0 }, { x: 1, y: 1 }, -1, { x: 0, y: 0 }, 1), RangeError);
  assert.throws(() => stepTowardWithZoC({ x: 0, y: 0 }, { x: 1, y: 1 }, NaN, { x: 0, y: 0 }, 1), RangeError);
});

// Vecteurs du socle : générateur aléatoire (src/core/rng.mjs) et géométrie (src/core/math.mjs).
// Un fichier de vecteurs exporte VECTORS : { module: async () => [{fn, cases: [{args, out}]}] }.

import { makeRng } from './_outils.mjs';

export const VECTORS = {
  async rng() {
    const R = await import('../../src/core/rng.mjs');
    const rnd = makeRng(1);
    const seeds = [0, 1, 2, 42, 0x7fffffff, 0x80000000, 0xffffffff, ...Array.from({ length: 20 }, () => Math.floor(rnd() * 4294967296))];
    const seq = (seed, f, n = 8) => {
      const r = R.createRng(seed);
      return Array.from({ length: n }, () => f(r));
    };
    return [
      { fn: 'nextU32', cases: seeds.map((s) => ({ args: [s], out: seq(s, R.nextU32) })) },
      { fn: 'rand', cases: seeds.map((s) => ({ args: [s], out: seq(s, R.rand) })) },
      { fn: 'randRange', cases: seeds.map((s) => ({ args: [s, -3.5, 12.25], out: seq(s, (r) => R.randRange(r, -3.5, 12.25)) })) },
      { fn: 'randInt', cases: seeds.map((s) => ({ args: [s, 3, 9], out: seq(s, (r) => R.randInt(r, 3, 9)) })) },
      { fn: 'pick', cases: seeds.map((s) => ({ args: [s, ['a', 'b', 'c', 'd', 'e']], out: seq(s, (r) => R.pick(r, ['a', 'b', 'c', 'd', 'e'])) })) },
      { fn: 'shuffle', cases: seeds.map((s) => ({ args: [s, [1, 2, 3, 4, 5, 6, 7, 8, 9]], out: R.shuffle(R.createRng(s), [1, 2, 3, 4, 5, 6, 7, 8, 9]) })) },
      {
        fn: 'weightedPick',
        cases: seeds.map((s) => {
          const items = [{ id: 'a', w: 1 }, { id: 'b', w: 0 }, { id: 'c', w: 2.5 }, { id: 'd', w: 0.25 }];
          return { args: [s, items], out: seq(s, (r) => R.weightedPick(r, items, (it) => it.w).id) };
        }),
      },
      { fn: 'hashSeed', cases: seeds.map((s, i) => ({ args: [s, i, 1 + (i * 7919) % 666], out: R.hashSeed(s, i, 1 + (i * 7919) % 666) })) },
    ];
  },

  async geo() {
    const M = await import('../../src/core/math.mjs');
    const rnd = makeRng(2);
    const u = (a, b) => a + (b - a) * rnd();
    const many = (n, make) => Array.from({ length: n }, make);
    const N = 200;
    const call = (fn, argsOf) => ({ fn, cases: many(N, () => { const args = argsOf(); return { args, out: M[fn](...args) }; }) });
    const outFn = (fn, argsOf) => ({
      fn,
      cases: many(N, () => {
        const args = argsOf();
        const out = { x: 0, y: 0, nx: 0, ny: 0 };
        const ret = M[fn](out, ...args);
        return { args, out: { ret, x: out.x, y: out.y, nx: out.nx, ny: out.ny } };
      }),
    });
    return [
      call('clamp', () => [u(-10, 10), -3, 4]),
      call('lerp', () => [u(-10, 10), u(-10, 10), u(0, 1)]),
      call('len', () => [u(-500, 500), u(-500, 500)]),
      call('dist', () => [u(0, 1400), u(0, 880), u(0, 1400), u(0, 880)]),
      call('dist2', () => [u(0, 1400), u(0, 880), u(0, 1400), u(0, 880)]),
      call('approach', () => [u(-10, 10), u(-10, 10), u(0, 3)]),
      call('angleDiff', () => [u(-12, 12), u(-12, 12)]),
      call('inSector', () => [u(0, 400), u(0, 400), 200, 200, u(40, 220), u(-4, 4), u(0.2, 6.5), u(0, 30)]),
      call('circlesOverlap', () => [u(0, 100), u(0, 100), u(5, 40), u(0, 100), u(0, 100), u(5, 40)]),
      call('pointSegDist2', () => [u(0, 400), u(0, 400), u(0, 400), u(0, 400), u(0, 400), u(0, 400)]),
      call('pointBandDist2', () => [u(0, 400), u(0, 400), u(0, 400), u(0, 400), u(-4, 4), u(50, 600), u(10, 90)]),
      call('easeOutCubic', () => [u(0, 1)]),
      call('easeInQuad', () => [u(0, 1)]),
      outFn('normalizeInto', () => (rnd() < 0.1 ? [0, 0] : [u(-300, 300), u(-300, 300)])),
      outFn('closestOnRect', () => [u(0, 400), u(0, 400), 100, 120, 260, 300]),
      outFn('pushCircleOutOfRect', () => [u(60, 300), u(80, 340), u(8, 40), 100, 120, 260, 300]),
      outFn('pushCircleOutOfCircle', () => [u(0, 200), u(0, 200), u(8, 40), 100, 100, u(10, 60)]),
    ];
  },
};

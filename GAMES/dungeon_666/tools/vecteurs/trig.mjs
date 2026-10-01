// Vecteurs de la bibliothèque mathématique déterministe (src/core/trig.mjs) : Godot doit rendre
// EXACTEMENT les mêmes bits. Un fichier de vecteurs exporte VECTORS (voir socle.mjs).

import { makeRng } from './_outils.mjs';

export const VECTORS = {
  async trig() {
    const T = await import('../../src/core/trig.mjs');
    const rnd = makeRng(3);
    const u = (a, b) => a + (b - a) * rnd();
    const N = 3000;
    const one = (fn, gen) => ({ fn, cases: Array.from({ length: N }, () => { const args = gen(); return { args, out: T[fn](...args) }; }) });
    const edges = [0, 1, -1, 0.5, -0.5, Math.PI, -Math.PI, Math.PI / 2, Math.PI / 4, 1e-9, -1e-9, 100, -100, 1e4];
    return [
      one('sin', () => [u(-2000, 2000)]),
      one('cos', () => [u(-2000, 2000)]),
      { fn: 'sin', cases: edges.map((x) => ({ args: [x], out: T.sin(x) })) },
      { fn: 'cos', cases: edges.map((x) => ({ args: [x], out: T.cos(x) })) },
      one('atan', () => [u(-50, 50)]),
      one('atan2', () => [u(-1400, 1400), u(-1400, 1400)]),
      { fn: 'atan2', cases: [[0, 0], [0, 1], [0, -1], [1, 0], [-1, 0], [1, 1], [-1, -1], [1e-9, -1], [-1e-9, -1]].map((a) => ({ args: a, out: T.atan2(...a) })) },
      one('asin', () => [u(-1.2, 1.2)]),
      one('exp', () => [u(-40, 40)]),
      one('log', () => [u(0.001, 5000)]),
      one('pow', () => [u(0.05, 60), u(-4, 4)]),
      { fn: 'constants', cases: [{ args: [], out: T.TRIG_CONSTANTS }] },
    ];
  },
};

// RNG déterministe (mulberry32). L'état tient dans un entier 32 bits : sérialisable,
// clonable, et identique sous node et dans le navigateur. La simulation n'appelle
// JAMAIS Math.random — c'est ce qui rend une partie rejouable à l'identique.

const GOLDEN = 0x6d2b79f5;
const U32 = 4294967296;

export function createRng(seed) {
  return { s: seed >>> 0 };
}

export function cloneRng(r) {
  return { s: r.s };
}

export function nextU32(r) {
  r.s = (r.s + GOLDEN) >>> 0;
  let t = r.s;
  t = Math.imul(t ^ (t >>> 15), t | 1);
  t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
  return (t ^ (t >>> 14)) >>> 0;
}

/** Flottant uniforme dans [0, 1). */
export function rand(r) {
  return nextU32(r) / U32;
}

/** Flottant uniforme dans [a, b). */
export function randRange(r, a, b) {
  return a + (b - a) * rand(r);
}

/** Entier uniforme dans [a, b] (bornes incluses). */
export function randInt(r, a, b) {
  return a + Math.floor(rand(r) * (b - a + 1));
}

export function chance(r, p) {
  return rand(r) < p;
}

export function pick(r, arr) {
  return arr[Math.floor(rand(r) * arr.length)];
}

/** Tirage pondéré : `weightOf(item)` rend un poids >= 0. Rend null si tout est nul. */
export function weightedPick(r, items, weightOf) {
  let total = 0;
  for (const it of items) total += Math.max(0, weightOf(it));
  if (total <= 0) return null;
  let x = rand(r) * total;
  for (const it of items) {
    x -= Math.max(0, weightOf(it));
    if (x < 0) return it;
  }
  return items[items.length - 1];
}

/** Mélange de Fisher-Yates, en place. */
export function shuffle(r, arr) {
  for (let i = arr.length - 1; i > 0; i--) {
    const j = Math.floor(rand(r) * (i + 1));
    const t = arr[i];
    arr[i] = arr[j];
    arr[j] = t;
  }
  return arr;
}

/** Dérive une graine stable à partir d'une graine et de sels (étage, salle…). */
export function hashSeed(seed, ...salts) {
  let h = (seed >>> 0) ^ 0x9e3779b9;
  for (const s of salts) {
    h = Math.imul(h ^ (s >>> 0), 0x85ebca6b) >>> 0;
    h ^= h >>> 13;
    h = Math.imul(h, 0xc2b2ae35) >>> 0;
    h ^= h >>> 16;
  }
  return h >>> 0;
}

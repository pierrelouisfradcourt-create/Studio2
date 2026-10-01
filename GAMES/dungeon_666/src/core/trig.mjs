// Fonctions transcendantes DÉTERMINISTES : sinus, cosinus, arc tangente, exponentielle,
// logarithme, puissance — écrites avec les seules opérations que tous les moteurs calculent à
// l'identique (+, −, ×, ÷, racine carrée, partie entière).
//
// Pourquoi : Math.sin, Math.cos, Math.atan2, Math.exp… ne sont PAS tenues au même dernier bit
// d'un moteur à l'autre (mesuré le 2026-10-01 entre V8 et Godot : 9 % des sinus diffèrent), et
// dans un combat dense cet écart s'amplifie jusqu'à faire diverger deux parties rejouées. La
// simulation n'appelle donc JAMAIS Math.sin & co : elle passe par ce module, que la version
// Godot porte ligne à ligne (sim/trig.gd). Même graine + mêmes entrées = même partie, au bit
// près, quel que soit le moteur.
//
// Précision : erreur relative de l'ordre de 1e-15 (largement sous ce que le jeu peut voir).
// AUCUN nombre décimal écrit en dur ne sert de coefficient : les lecteurs de décimaux diffèrent
// aussi d'un moteur à l'autre. Les coefficients sont des quotients d'entiers, calculés.

const PI = Math.PI;
const HALF_PI = PI / 2;
// π/2 en deux morceaux (Cody-Waite) : le premier a ses 27 bits bas à zéro, k × HI est exact.
const PIO2_HI = Math.floor(HALF_PI * 67108864) / 67108864; // 2^26
const PIO2_LO = HALF_PI - PIO2_HI;
const LN2 = ln2Series();
const SIN_TERMS = 10; // jusqu'à r^21 / 21!
const EXP_TERMS = 16;
const ATAN_TERMS = 14; // jusqu'à z^29 / 29, |z| <= tan(π/16)
const LOG_TERMS = 16;

/** ln 2 = 2·atanh(1/3), sommé du plus petit terme au plus grand : aucun décimal écrit en dur. */
function ln2Series() {
  let s = 0;
  for (let i = 20; i >= 0; i--) s = 1 / (2 * i + 1) + s / 9;
  return (2 * s) / 3;
}

function jround(x) {
  return Math.floor(x + 0.5);
}

/** Réduit x à r dans [-π/4, π/4] ; rend le quadrant (0..3) dans out.q et r dans out.r. */
const red = { q: 0, r: 0 };
function reduce(x) {
  const k = jround(x / HALF_PI);
  red.r = x - k * PIO2_HI - k * PIO2_LO;
  red.q = ((k % 4) + 4) % 4;
}

function sinKernel(r) {
  // r − r³/3! + r⁵/5! − … (Horner sur r²)
  const r2 = r * r;
  let s = 0;
  for (let i = SIN_TERMS; i >= 1; i--) s = (1 - s) * r2 / ((2 * i) * (2 * i + 1));
  return r * (1 - s);
}

function cosKernel(r) {
  // 1 − r²/2! + r⁴/4! − …
  const r2 = r * r;
  let s = 0;
  for (let i = SIN_TERMS; i >= 1; i--) s = (1 - s) * r2 / ((2 * i - 1) * (2 * i));
  return 1 - s;
}

export function sin(x) {
  reduce(x);
  switch (red.q) {
    case 0: return sinKernel(red.r);
    case 1: return cosKernel(red.r);
    case 2: return -sinKernel(red.r);
    default: return -cosKernel(red.r);
  }
}

export function cos(x) {
  reduce(x);
  switch (red.q) {
    case 0: return cosKernel(red.r);
    case 1: return -sinKernel(red.r);
    case 2: return -cosKernel(red.r);
    default: return sinKernel(red.r);
  }
}

/** Arc tangente de z >= 0. Deux demi-angles ramènent z sous tan(π/16), puis la série. */
function atanPos(z) {
  if (z > 1) return HALF_PI - atanPos(1 / z);
  let w = z / (1 + Math.sqrt(1 + z * z));
  w = w / (1 + Math.sqrt(1 + w * w));
  const w2 = w * w;
  let s = 0;
  for (let i = ATAN_TERMS; i >= 0; i--) s = 1 / (2 * i + 1) - w2 * s;
  return 4 * w * s;
}

export function atan(z) {
  return z < 0 ? -atanPos(-z) : atanPos(z);
}

/** Angle du vecteur (x, y) dans (-π, π], mêmes conventions que Math.atan2 (hors zéros signés). */
export function atan2(y, x) {
  if (x > 0) return atan(y / x);
  if (x < 0) return y >= 0 ? atan(y / x) + PI : atan(y / x) - PI;
  if (y > 0) return HALF_PI;
  if (y < 0) return -HALF_PI;
  return 0;
}

export function asin(v) {
  if (v >= 1) return HALF_PI;
  if (v <= -1) return -HALF_PI;
  return atan(v / Math.sqrt(1 - v * v));
}

export function exp(x) {
  const k = jround(x / LN2);
  const r = x - k * LN2;
  let s = 1;
  for (let i = EXP_TERMS; i >= 1; i--) s = 1 + (r / i) * s;
  // × 2^k par doublements (exacts).
  if (k > 0) for (let i = 0; i < k; i++) s *= 2;
  else for (let i = 0; i < -k; i++) s /= 2;
  return s;
}

/** Logarithme naturel (x > 0) : x = m × 2^e avec m dans [0,75 ; 1,5), puis 2·atanh((m−1)/(m+1)). */
export function log(x) {
  let m = x;
  let e = 0;
  while (m >= 1.5) { m /= 2; e++; }
  while (m < 0.75) { m *= 2; e--; }
  const u = (m - 1) / (m + 1);
  const u2 = u * u;
  let s = 0;
  for (let i = LOG_TERMS; i >= 0; i--) s = 1 / (2 * i + 1) + u2 * s;
  return 2 * u * s + e * LN2;
}

/** a^b pour a > 0 (le seul usage de la simulation : un poids). */
export function pow(a, b) {
  if (b === 0) return 1;
  if (a === 1) return 1;
  return exp(b * log(a));
}

export const TRIG_CONSTANTS = { PIO2_HI, PIO2_LO, LN2 };

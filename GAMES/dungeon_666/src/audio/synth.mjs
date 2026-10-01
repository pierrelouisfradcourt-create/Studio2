// Briques de synthèse WebAudio — AUCUNE ressource audio : tout naît d'oscillateurs et d'un
// bruit blanc pré-généré une seule fois.
//
// Vocabulaire :
//   moteur (engine) : { ctx, bus, noiseBuffer, clipCurve, maxFreq, random } — créé par sfx.mjs.
//   voix (voice)    : une instance de son = un gain de sortie (+ panoramique) branché sur le
//                     bus. Ses sources s'y raccordent ; la voix se débranche d'elle-même
//                     quand sa dernière source s'arrête (aucune fuite de nœuds).
//   couche (layer)  : une source enveloppée décrite par des DONNÉES (voir recipes.mjs) :
//     { src: 'tone' | 'noise', type (forme d'onde ou filtre du bruit), freq, to (fréquence
//       d'arrivée ; null : fixe), glide (durée du glissando), q, env, gain, at (décalage, s),
//       filter {type, freq, to, q} (tons), detune, drive (distorsion douce),
//       vibrato {rate, cents}, tremolo {rate, depth} }
//
// Ce module ne connaît ni le jeu ni ses événements : il ne fait que jouer des couches.

import { clamp } from '../core/math.mjs';

/** Plancher des rampes exponentielles (WebAudio interdit d'y viser 0). */
export const SILENCE = 0.0001;
const MIN_ATTACK = 0.001; // s : une attaque nulle claque
const MIN_RELEASE = 0.005; // s
const STOP_MARGIN = 0.03; // s entre la fin de l'enveloppe et stop() : la queue reste muette
const MIN_FREQ = 20; // Hz
const NYQUIST_SAFETY = 0.45; // fraction de la fréquence d'échantillonnage tolérée
const NOISE_SECONDS = 2; // durée du bruit blanc partagé (lu en boucle, départ aléatoire)
const NOISE_OFFSET_SPAN = 0.5; // fraction du tampon où tirer le point de départ
const SOFT_CLIP_SAMPLES = 1024;
const SOFT_CLIP_AMOUNT = 3; // dureté de la distorsion douce (0 = transparente)

// ---------------------------------------------------------------- enveloppes

/** Enveloppe percussive : attaque `a` puis extinction `r` (secondes). */
export function perc(a, r) {
  return { a, d: 0, s: 1, h: 0, r };
}

/** Enveloppe ADSR : attaque, déclin vers `s` (fraction du pic), tenue `h`, relâche `r`. */
export function adsr(a, d, s, h, r) {
  return { a, d, s, h, r };
}

export function envLength(env) {
  return Math.max(MIN_ATTACK, env.a) + env.d + env.h + Math.max(MIN_RELEASE, env.r);
}

/** Programme l'enveloppe sur un AudioParam de gain ; rend l'instant où elle s'éteint. */
export function applyEnvelope(param, t, env, peak) {
  const top = Math.max(SILENCE * 2, finite(peak, 0));
  const sustain = Math.max(SILENCE, top * clamp(finite(env.s, 1), 0, 1));
  const tA = t + Math.max(MIN_ATTACK, env.a);
  const tD = tA + env.d;
  const tH = tD + env.h;
  const tR = tH + Math.max(MIN_RELEASE, env.r);
  param.setValueAtTime(SILENCE, t);
  param.linearRampToValueAtTime(top, tA);
  if (env.d > 0) param.exponentialRampToValueAtTime(sustain, tD);
  if (env.h > 0) param.setValueAtTime(env.d > 0 ? sustain : top, tH);
  param.exponentialRampToValueAtTime(SILENCE, tR);
  return tR;
}

// ---------------------------------------------------------------- ressources partagées

/**
 * Moteur de synthèse autour d'un contexte et d'un bus d'entrée déjà câblé : bruit et courbe de
 * saturation pré-calculés une fois, fréquence maximale sûre sous Nyquist.
 */
export function createEngine(ctx, bus, random = Math.random) {
  return {
    ctx,
    bus,
    random,
    noiseBuffer: createNoiseBuffer(ctx, random),
    clipCurve: createSoftClipCurve(),
    maxFreq: ctx.sampleRate * NYQUIST_SAFETY,
  };
}

/** Bruit blanc mono, généré UNE fois par contexte (Math.random : présentation, pas la sim). */
export function createNoiseBuffer(ctx, random = Math.random) {
  const length = Math.max(1, Math.floor(ctx.sampleRate * NOISE_SECONDS));
  const buffer = ctx.createBuffer(1, length, ctx.sampleRate);
  const data = buffer.getChannelData(0);
  for (let i = 0; i < length; i++) data[i] = random() * 2 - 1;
  return buffer;
}

/**
 * Courbe de saturation douce (WaveShaper) : pente 1 près de zéro (un signal faible garde son
 * niveau), crêtes arrondies d'autant plus que le signal est fort — grain, pas de gain caché.
 */
export function createSoftClipCurve() {
  const curve = new Float32Array(SOFT_CLIP_SAMPLES);
  const k = SOFT_CLIP_AMOUNT;
  for (let i = 0; i < SOFT_CLIP_SAMPLES; i++) {
    const x = (i / (SOFT_CLIP_SAMPLES - 1)) * 2 - 1;
    curve[i] = x / (1 + k * Math.abs(x));
  }
  return curve;
}

// ---------------------------------------------------------------- voix

/** Ouvre une voix démarrant à `t` : gain de sortie + panoramique optionnel, vers le bus. */
export function openVoice(eng, t, gain, pan) {
  const ctx = eng.ctx;
  const out = ctx.createGain();
  out.gain.value = Math.max(0, finite(gain, 0));
  const voice = { eng, ctx, t, out, end: t, pending: 0, nodes: [out], shaper: null };
  const p = clamp(finite(pan, 0), -1, 1);
  if (p !== 0 && typeof ctx.createStereoPanner === 'function') {
    const panner = ctx.createStereoPanner();
    panner.pan.value = p;
    out.connect(panner);
    panner.connect(eng.bus);
    voice.nodes.push(panner);
  } else {
    out.connect(eng.bus);
  }
  return voice;
}

/** Joue une liste de couches dans la voix. `pitch` multiplie les fréquences, `gain` les gains. */
export function playLayers(voice, layers, pitch = 1, gain = 1) {
  for (const layer of layers) playLayer(voice, layer, pitch, gain);
}

export function playLayer(voice, L, pitch = 1, gain = 1) {
  const t = voice.t + (L.at ?? 0);
  const len = envLength(L.env);
  const src = L.src === 'noise' ? makeNoise(voice, L, t, len, pitch) : makeTone(voice, L, t, len, pitch);
  const env = voice.ctx.createGain();
  const end = applyEnvelope(env.gain, t, L.env, (L.gain ?? 1) * gain);
  let head = src.out;
  if (L.tremolo) head = addTremolo(voice, head, L.tremolo, t, end);
  head.connect(env);
  env.connect(L.drive ? driveOf(voice) : voice.out);
  startSource(voice, src.node, t, end, src.offset);
}

function makeTone(voice, L, t, len, k) {
  const osc = voice.ctx.createOscillator();
  osc.type = L.type ?? 'sine';
  sweep(voice, osc.frequency, t, L.freq * k, L.to == null ? null : L.to * k, L.glide ?? len);
  if (L.detune) osc.detune.value = L.detune;
  if (L.vibrato) startLfo(voice, L.vibrato.rate, L.vibrato.cents, osc.detune, t, t + len);
  if (!L.filter) return { node: osc, out: osc };
  const f = L.filter;
  const filter = makeFilter(voice, f.type, t, f.freq, f.to, f.q, L.glide ?? len);
  osc.connect(filter);
  return { node: osc, out: filter };
}

function makeNoise(voice, L, t, len, k) {
  const src = voice.ctx.createBufferSource();
  src.buffer = voice.eng.noiseBuffer;
  src.loop = true;
  const to = L.to == null ? null : L.to * k;
  const filter = makeFilter(voice, L.type ?? 'bandpass', t, L.freq * k, to, L.q, L.glide ?? len);
  src.connect(filter);
  const offset = voice.eng.random() * src.buffer.duration * NOISE_OFFSET_SPAN;
  return { node: src, out: filter, offset };
}

function makeFilter(voice, type, t, freq, to, q, glide) {
  const filter = voice.ctx.createBiquadFilter();
  filter.type = type;
  sweep(voice, filter.frequency, t, freq, to, glide);
  if (q !== undefined) filter.Q.setValueAtTime(q, t);
  return filter;
}

/** Fréquence de départ, puis glissando exponentiel vers `to` (null : fixe), bornés. */
function sweep(voice, param, t, from, to, glide) {
  const hi = voice.eng.maxFreq;
  const f0 = clamp(finite(from, MIN_FREQ), MIN_FREQ, hi);
  param.setValueAtTime(f0, t);
  if (to == null) return;
  const f1 = clamp(finite(to, f0), MIN_FREQ, hi);
  if (f1 !== f0) param.exponentialRampToValueAtTime(f1, t + Math.max(MIN_ATTACK, glide));
}

/** Modulation d'amplitude multiplicative : le gain oscille entre 1 - 2·depth et 1. */
function addTremolo(voice, head, trem, t, end) {
  const am = voice.ctx.createGain();
  const depth = clamp(trem.depth, 0, 0.5);
  am.gain.value = 1 - depth;
  startLfo(voice, trem.rate, depth, am.gain, t, end);
  head.connect(am);
  return am;
}

function startLfo(voice, rate, depth, target, t, end) {
  const lfo = voice.ctx.createOscillator();
  lfo.frequency.value = rate;
  const amount = voice.ctx.createGain();
  amount.gain.value = depth;
  lfo.connect(amount);
  amount.connect(target);
  startSource(voice, lfo, t, end);
}

/** Distorsion douce partagée par les couches `drive` d'une même voix. */
function driveOf(voice) {
  if (voice.shaper) return voice.shaper;
  const shaper = voice.ctx.createWaveShaper();
  shaper.curve = voice.eng.clipCurve;
  shaper.oversample = '2x';
  shaper.connect(voice.out);
  voice.nodes.push(shaper);
  voice.shaper = shaper;
  return shaper;
}

/**
 * Démarre une source et ne la compte dans la voix qu'une fois start() ET stop() acceptés :
 * une source refusée ne bloque jamais la libération de la voix (sinon la voix restait
 * branchée sur le bus pour toujours), et une source démarrée a toujours une fin programmée.
 */
function startSource(voice, node, t, end, offset) {
  if (offset === undefined) node.start(t);
  else node.start(t, offset);
  try {
    node.stop(end + STOP_MARGIN);
  } catch (err) {
    node.stop(); // jamais d'oscillateur sans fin
    throw err;
  }
  voice.pending++;
  voice.end = Math.max(voice.end, end);
  node.onended = () => releaseSource(voice);
}

function releaseSource(voice) {
  voice.pending--;
  if (voice.pending <= 0) closeVoice(voice);
}

/**
 * Débranche la voix (sortie, panoramique, saturation). Appelée d'elle-même à la fin de la
 * dernière source ; sfx.mjs l'appelle aussi pour une voix restée sans aucune source (recette
 * en erreur). Idempotente.
 */
export function closeVoice(voice) {
  for (const n of voice.nodes) {
    try {
      n.disconnect();
    } catch {
      // déjà débranché : rien à faire
    }
  }
}

/** Nombre fini, sinon valeur de repli (un événement mal formé ne casse jamais l'audio). */
export function finite(v, fallback) {
  return Number.isFinite(v) ? v : fallback;
}

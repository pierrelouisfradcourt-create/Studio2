// Audio de Dungeon 666 : sons 100 % procéduraux (WebAudio, aucun fichier) pilotés par les
// événements de simulation, et retour haptique (navigator.vibrate, Android).
//
//   const audio = createAudio();
//   addEventListener('pointerdown', () => audio.unlock());   // geste utilisateur requis
//   addEventListener('keydown', () => audio.unlock());
//   // à chaque image rendue, AVANT de vider game.events :
//   audio.handleEvents(game.events, game);
//
// Contrat de robustesse : sans AudioContext (node, vieux navigateur) tout devient no-op, et
// aucune méthode ne lève jamais d'exception (une erreur WebAudio imprévue est comptée dans
// getStats(), jamais propagée à la boucle de jeu). Un événement inconnu, quel que soit son
// nom (même 'constructor' ou '__proto__'), est simplement ignoré. Le module ne touche ni window ni navigator
// à l'import : il s'importe tel quel sous node.
//
// Aucun import de la simulation : on lit seulement les champs des événements et
// game.player.x/y (panoramique stéréo léger relatif au héros).
//
// Chaîne : voix -> bus -> compresseur -> volume maître -> sortie.
// Une image = des événements GROUPÉS par son : 6 coups dans la même image donnent 1-2 sons
// plus forts, pas 6. Chaque son a un plafond de voix simultanées, et le mixage un plafond global.

import { clamp, lerp } from '../core/math.mjs';
import { createEngine, openVoice, closeVoice, finite } from './synth.mjs';
import { RECIPES } from './recipes.mjs';

const DEFAULT_VOLUME = 0.6;
const PITCH_JITTER = 0.05; // ±5 % de hauteur à chaque son (Math.random : présentation, pas la sim)
const SCHEDULE_LEAD = 0.005; // s : programmer un poil dans le futur évite les clics
const VOLUME_SMOOTHING = 0.02; // s : constante de temps des changements de volume / sourdine
// Pendant un resume() en cours, on programme quand même (le contexte démarre en quelques ms)…
// mais pas indéfiniment : un resume() refusé (pas d'activation) ou bloqué (iOS « interrupted »)
// reste en attente, et tout ce qui serait programmé à l'horloge figée sortirait d'un bloc,
// en retard, au déblocage.
const RESUME_GRACE_MS = 250;
const MAX_VOICES = 24; // plafond global (dur) de voix simultanées
const CRITICAL_PRIORITY = 9; // sons vitaux (coup reçu, esquive, Super, boss…)
const CRITICAL_RESERVE = 6; // voix réservées aux sons vitaux : le reste plafonne à 24 - 6
const GROUP_BOOST_PER_DOUBLING = 0.22; // gain ajouté chaque fois qu'un groupe double
const MAX_GROUP_BOOST = 1.6;
// Spatialisation légère (unités de sim) : panoramique selon l'écart horizontal au héros,
// atténuation douce des sons lointains.
const PAN_DISTANCE = 520;
const PAN_MAX = 0.5;
const FAR_DISTANCE = 900;
const FAR_GAIN = 0.6;
const CENTER = { pan: 0, gain: 1 };
// Compresseur du bus maître (dB, ratio, s) : évite la saturation quand tout frappe ensemble.
const COMPRESSOR = { threshold: -18, knee: 12, ratio: 6, attack: 0.003, release: 0.15 };
// Haptique (ms).
const HAPTIC_MS = { hurt: 40, heavyHit: 12, boss: 80, dodge: 8 };
const HAPTIC_GAP_MS = 40; // une vibration plus faible n'interrompt pas la précédente
const FINAL_COMBO_INDEX = 2; // 3e coup du combo : coup lourd
const CRIT_WEIGHT = 25; // un critique passe devant un coup normal pour représenter le groupe

/**
 * Table de correspondance SANS prototype : un type d'événement 'constructor', 'valueOf',
 * '__proto__'… n'y trouve rien (sinon : TypeError -> tous les sons et la vibration de
 * l'image perdus, et une erreur comptée).
 */
function table(entries) {
  return Object.freeze(Object.assign(Object.create(null), entries));
}

/**
 * Sons : voices = voix simultanées max, perFrame = sons max par image (le reste du groupe
 * renforce leur gain), priority = ordre de passage (et accès à la réserve de voix vitales),
 * gain = niveau de mixage, weight(entry) = choix du représentant (le plus fort d'abord).
 */
const SOUNDS = table({
  swing: { voices: 3, perFrame: 1, priority: 5, gain: 0.9 },
  hit: { voices: 4, perFrame: 2, priority: 6, gain: 1, weight: (e) => finite(e.ev.amount, 0) + (e.ev.crit ? CRIT_WEIGHT : 0) },
  burn: { voices: 2, perFrame: 1, priority: 1, gain: 0.15 },
  kill: { voices: 4, perFrame: 2, priority: 7, gain: 0.55, weight: (e) => (e.ev.boss ? 2 : 0) + (e.ev.elite ? 1 : 0) },
  chain: { voices: 3, perFrame: 2, priority: 4, gain: 0.35 },
  dash: { voices: 2, perFrame: 1, priority: 7, gain: 0.5 },
  dodge: { voices: 2, perFrame: 1, priority: 9, gain: 0.55 },
  dashNova: { voices: 2, perFrame: 1, priority: 5, gain: 0.5 },
  dashReady: { voices: 1, perFrame: 1, priority: 1, gain: 0.12 },
  deflect: { voices: 3, perFrame: 2, priority: 6, gain: 1 },
  skill: { voices: 2, perFrame: 1, priority: 7, gain: 0.55 },
  gadget: { voices: 2, perFrame: 1, priority: 8, gain: 0.65 },
  super: { voices: 1, perFrame: 1, priority: 9, gain: 0.7 },
  superTick: { voices: 2, perFrame: 1, priority: 3, gain: 0.45 },
  superEnd: { voices: 1, perFrame: 1, priority: 3, gain: 0.35 },
  superReady: { voices: 1, perFrame: 1, priority: 8, gain: 0.45 },
  playerHurt: { voices: 2, perFrame: 1, priority: 10, gain: 0.75, weight: (e) => finite(e.ev.amount, 0) },
  playerDeath: { voices: 1, perFrame: 1, priority: 10, gain: 0.85 },
  enemyAttack: { voices: 3, perFrame: 2, priority: 4, gain: 0.3, weight: (e) => (e.ev.enemy === 'boss' || e.ev.enemy === 'bossRing' ? 1 : 0) },
  boom: { voices: 3, perFrame: 2, priority: 6, gain: 0.6, weight: (e) => finite(e.ev.r, 0) },
  hazardCancel: { voices: 2, perFrame: 1, priority: 3, gain: 0.5 },
  slam: { voices: 3, perFrame: 2, priority: 6, gain: 0.6, weight: (e) => (e.ev.boss ? 1 : 0) },
  spawnWarn: { voices: 2, perFrame: 1, priority: 1, gain: 0.05, weight: (e) => (e.ev.elite ? 1 : 0) },
  bossPhase: { voices: 1, perFrame: 1, priority: 10, gain: 0.8 },
  bossSummon: { voices: 1, perFrame: 1, priority: 6, gain: 0.5 },
  coin: { voices: 3, perFrame: 1, priority: 4, gain: 0.35, weight: (e) => (e.ev.type === 'buy' ? 1 : 0) },
  heal: { voices: 2, perFrame: 1, priority: 5, gain: 0.45 },
  boonGain: { voices: 1, perFrame: 1, priority: 8, gain: 0.55 },
  equip: { voices: 1, perFrame: 1, priority: 8, gain: 0.55 },
  roomClear: { voices: 1, perFrame: 1, priority: 8, gain: 0.55 },
  doorsOpen: { voices: 1, perFrame: 1, priority: 4, gain: 0.3 },
  floorEnter: { voices: 1, perFrame: 1, priority: 7, gain: 0.5 },
  checkpoint: { voices: 1, perFrame: 1, priority: 8, gain: 0.55 },
  choiceOpen: { voices: 1, perFrame: 1, priority: 3, gain: 0.35 },
  victory: { voices: 1, perFrame: 1, priority: 10, gain: 0.7 },
  gameOver: { voices: 1, perFrame: 1, priority: 9, gain: 0.6 },
});

// Coups dont le son est déjà porté par un autre événement de la même image.
const HIT_COVERED = new Set(['chain', 'wall']);

/** Événement de sim -> clé de son, ou fonction (ev) -> clé | null (null : silencieux). */
const ROUTES = table({
  swing: 'swing', kill: 'kill', chain: 'chain',
  hit: (ev) => (ev.kind === 'burn' ? 'burn' : HIT_COVERED.has(ev.kind) ? null : 'hit'),
  dash: 'dash', dodge: 'dodge', dashNova: 'dashNova', dashReady: 'dashReady',
  deflect: 'deflect', skill: 'skill', gadget: 'gadget',
  super: 'super', superTick: 'superTick', superEnd: 'superEnd', superReady: 'superReady',
  playerHurt: 'playerHurt', playerDeath: 'playerDeath',
  enemyAttack: 'enemyAttack', explode: 'boom', hazardCancel: 'hazardCancel',
  // L'explosion d'un possédé émet `explode` ET `hazardFire` (kind exploder) : un seul boum.
  hazardFire: (ev) => (ev.kind === 'exploder' ? null : 'boom'),
  wallSlam: 'slam', chargerWall: 'slam', spawnWarn: 'spawnWarn',
  bossPhase: 'bossPhase', bossSummon: 'bossSummon',
  pickup: (ev) => (ev.kind === 'heal' ? 'heal' : 'coin'),
  gold: 'coin', buy: 'coin', heal: 'heal',
  boonGain: 'boonGain', equip: 'equip', roomClear: 'roomClear', doorsOpen: 'doorsOpen',
  floorEnter: 'floorEnter', checkpoint: 'checkpoint', respawn: 'checkpoint',
  choiceOpen: 'choiceOpen', victory: 'victory', gameOver: 'gameOver',
  // Charge de gadget rendue par un élite abattu : même accord bref que « Super prêt ».
  gadgetCharge: 'superReady',
});

/**
 * Silencieux À DESSEIN : spawn (couvert par spawnWarn), attackStart / castStart (couverts par
 * swing / skill), cancel, dashEnd, projectileEnd, hazard (télégraphe visuel ; enemyAttack porte
 * l'audio), choiceClose, wave. Tout événement de sim est soit routé, soit listé ici (testé).
 */
export const SILENT_EVENTS = Object.freeze([
  'spawn', 'attackStart', 'castStart', 'cancel', 'dashEnd', 'projectileEnd', 'hazard', 'choiceClose', 'wave',
]);

/** Vibration (ms) demandée par une entrée annotée ; 0 = aucune. */
const HAPTICS = table({
  playerHurt: () => HAPTIC_MS.hurt,
  hit: (e) => (e.heavy ? HAPTIC_MS.heavyHit : 0),
  kill: (e) => (e.ev.boss ? HAPTIC_MS.boss : 0),
  bossPhase: () => HAPTIC_MS.boss,
  dodge: () => HAPTIC_MS.dodge,
});

// ---------------------------------------------------------------- API

/**
 * options (toutes facultatives, pour les tests) : { AudioContext, navigator, random, now }.
 * Rend { unlock, handleEvents, setMuted, isMuted, setVolume, getVolume, setHaptics,
 * isHapticsEnabled, getStats }.
 */
export function createAudio(options = {}) {
  const s = createState(options);
  return {
    unlock: () => unlock(s),
    handleEvents: (events, game) => handleEvents(s, events, game),
    setMuted: (muted) => setMuted(s, muted),
    isMuted: () => s.muted,
    setVolume: (volume) => setVolume(s, volume),
    getVolume: () => s.volume,
    setHaptics: (enabled) => setHaptics(s, enabled),
    isHapticsEnabled: () => s.haptics,
    getStats: () => statsOf(s),
  };
}

function createState(options) {
  return {
    Ctor: 'AudioContext' in options ? options.AudioContext : findAudioContext(),
    nav: 'navigator' in options ? options.navigator : globalThis.navigator,
    random: options.random ?? Math.random,
    now: options.now ?? defaultNow,
    ctx: null,
    eng: null,
    master: null,
    failed: false,
    unlocked: false,
    resuming: false,
    resumeDeadline: 0, // s.now() au-delà duquel un resume() encore en attente ne joue plus
    muted: false,
    volume: DEFAULT_VOLUME,
    haptics: true,
    voices: {}, // clé de son -> instants de fin (temps du contexte) des voix en cours
    lastSwingIndex: -1,
    hapticUntil: 0,
    hapticMs: 0,
    stats: { played: 0, dropped: 0, merged: 0, errors: 0, lastError: null },
  };
}

function findAudioContext() {
  return globalThis.AudioContext ?? globalThis.webkitAudioContext ?? null;
}

function defaultNow() {
  return globalThis.performance?.now?.() ?? Date.now();
}

function noteError(s, err) {
  s.stats.errors++;
  s.stats.lastError = String(err?.message ?? err);
}

// ---------------------------------------------------------------- contexte et bus maître

function unlock(s) {
  s.unlocked = true; // geste reçu : l'haptique devient permise (sous réserve d'activation, voir mayVibrate)
  try {
    if (!s.ctx && !createContext(s)) return;
    const state = s.ctx.state;
    if (state !== 'running' && state !== 'closed') resume(s);
  } catch (err) {
    noteError(s, err);
  }
}

function resume(s) {
  s.resuming = true;
  s.resumeDeadline = s.now() + RESUME_GRACE_MS;
  const done = () => {
    s.resuming = false;
  };
  try {
    const pending = s.ctx.resume();
    if (pending && typeof pending.then === 'function') pending.then(done, done);
    else done();
  } catch (err) {
    done();
    noteError(s, err);
  }
}

function createContext(s) {
  if (s.failed || !s.Ctor) return false;
  let ctx = null;
  try {
    ctx = new s.Ctor({ latencyHint: 'interactive' });
    const { bus, master } = buildMasterBus(ctx, s);
    s.eng = createEngine(ctx, bus, s.random);
    s.ctx = ctx;
    s.master = master;
    primeOutput(ctx);
    return true;
  } catch (err) {
    s.failed = true;
    s.ctx = null;
    s.master = null;
    noteError(s, err);
    closeQuietly(ctx); // un contexte à moitié câblé ne doit pas rester ouvert (ressource système)
    return false;
  }
}

function closeQuietly(ctx) {
  try {
    ctx?.close?.()?.catch?.(() => {});
  } catch {
    // fermeture refusée : sans conséquence
  }
}

function buildMasterBus(ctx, s) {
  const bus = ctx.createGain();
  const master = ctx.createGain();
  master.gain.value = s.muted ? 0 : s.volume;
  let tail = bus;
  if (typeof ctx.createDynamicsCompressor === 'function') {
    const comp = ctx.createDynamicsCompressor();
    for (const [param, value] of Object.entries(COMPRESSOR)) comp[param].value = value;
    bus.connect(comp);
    tail = comp;
  }
  tail.connect(master);
  master.connect(ctx.destination);
  return { bus, master };
}

/** iOS : un échantillon muet joué pendant le geste déverrouille la sortie audio. */
function primeOutput(ctx) {
  const src = ctx.createBufferSource();
  src.buffer = ctx.createBuffer(1, 1, ctx.sampleRate);
  src.connect(ctx.destination);
  src.start(0);
}

function setMuted(s, muted) {
  s.muted = !!muted;
  applyMasterGain(s);
}

function setVolume(s, volume) {
  s.volume = clamp(finite(Number(volume), s.volume), 0, 1);
  applyMasterGain(s);
}

function applyMasterGain(s) {
  if (!s.master) return;
  try {
    const g = s.master.gain;
    const t = s.ctx.currentTime;
    g.cancelScheduledValues(t);
    g.setValueAtTime(g.value, t);
    g.setTargetAtTime(s.muted ? 0 : s.volume, t, VOLUME_SMOOTHING);
  } catch (err) {
    noteError(s, err);
  }
}

// ---------------------------------------------------------------- événements d'une image

function handleEvents(s, events, game) {
  if (!Array.isArray(events) || events.length === 0) return;
  try {
    const entries = annotate(s, events);
    pulseHaptics(s, entries);
    if (!canPlay(s)) return;
    const now = s.ctx.currentTime;
    pruneVoices(s, now);
    for (const [key, list] of byPriority(groupByKey(entries))) playGroup(s, key, list, game, now);
  } catch (err) {
    noteError(s, err);
  }
}

function canPlay(s) {
  if (!s.ctx || s.muted) return false;
  return s.ctx.state === 'running' || (s.resuming && s.now() < s.resumeDeadline);
}

/** Entrées { ev, key, heavy } ; suit l'index du dernier coup pour reconnaître le 3e coup. */
function annotate(s, events) {
  const out = [];
  for (const ev of events) {
    if (!ev || typeof ev.type !== 'string') continue;
    if (ev.type === 'swing') s.lastSwingIndex = ev.strike ? -1 : finite(ev.index, -1);
    const route = ROUTES[ev.type];
    const key = typeof route === 'function' ? route(ev) : route ?? null;
    const heavy = ev.type === 'hit' && isHeavyHit(ev, s.lastSwingIndex);
    out.push({ ev, key, heavy });
  }
  return out;
}

function isHeavyHit(ev, lastSwingIndex) {
  return ev.kind === 'strike' || (ev.kind === 'melee' && lastSwingIndex === FINAL_COMBO_INDEX);
}

function groupByKey(entries) {
  const groups = new Map();
  for (const entry of entries) {
    if (!entry.key || !SOUNDS[entry.key]) continue;
    const list = groups.get(entry.key);
    if (list) list.push(entry);
    else groups.set(entry.key, [entry]);
  }
  return groups;
}

function byPriority(groups) {
  return [...groups.entries()].sort((a, b) => SOUNDS[b[0]].priority - SOUNDS[a[0]].priority);
}

// ---------------------------------------------------------------- voix et polyphonie

function playGroup(s, key, list, game, now) {
  const def = SOUNDS[key];
  const reps = representatives(list, def);
  const boost = Math.min(MAX_GROUP_BOOST, 1 + GROUP_BOOST_PER_DOUBLING * Math.log2(list.length / reps.length));
  s.stats.merged += list.length - reps.length;
  for (const entry of reps) {
    if (!hasRoom(s, key, def)) {
      s.stats.dropped++;
      continue;
    }
    try {
      playEntry(s, key, def, entry, boost, game, now);
    } catch (err) {
      noteError(s, err);
    }
  }
}

/** Les `perFrame` entrées les plus fortes du groupe (ordre d'arrivée sans critère de poids). */
function representatives(list, def) {
  if (list.length <= def.perFrame) return list;
  if (!def.weight) return list.slice(0, def.perFrame);
  return [...list].sort((a, b) => def.weight(b) - def.weight(a)).slice(0, def.perFrame);
}

/**
 * Une voix = une entrée jouée. Si la recette lève en route, les sources déjà parties se
 * libèrent seules à leur fin (et comptent dans la polyphonie) ; une voix restée sans aucune
 * source est débranchée tout de suite — sinon elle restait branchée sur le bus pour toujours.
 */
function playEntry(s, key, def, entry, boost, game, now) {
  const place = placement(entry.ev, game);
  const voice = openVoice(s.eng, now + SCHEDULE_LEAD, def.gain * place.gain, place.pan);
  const pitch = 1 + (s.random() * 2 - 1) * PITCH_JITTER;
  try {
    RECIPES[key](voice, { ev: entry.ev, pitch, gain: boost, heavy: entry.heavy });
  } finally {
    if (voice.pending > 0) (s.voices[key] ??= []).push(voice.end);
    else closeVoice(voice);
  }
  s.stats.played++;
}

/** Panoramique et atténuation relatifs au héros ; centré si l'événement n'a pas de position. */
function placement(ev, game) {
  const p = game?.player;
  const x = finite(ev.x, finite(ev.x0, NaN));
  if (!p || !Number.isFinite(x) || !Number.isFinite(p.x)) return CENTER;
  const dx = x - p.x;
  const dy = finite(ev.y, finite(ev.y0, p.y)) - finite(p.y, 0);
  const far = clamp(Math.hypot(dx, dy) / FAR_DISTANCE, 0, 1);
  return { pan: clamp(dx / PAN_DISTANCE, -1, 1) * PAN_MAX, gain: lerp(1, FAR_GAIN, far) };
}

function hasRoom(s, key, def) {
  if ((s.voices[key]?.length ?? 0) >= def.voices) return false;
  const ceiling = def.priority >= CRITICAL_PRIORITY ? MAX_VOICES : MAX_VOICES - CRITICAL_RESERVE;
  return activeVoices(s) < ceiling;
}

/** Retire les voix éteintes, en place (aucune allocation par image). */
function pruneVoices(s, now) {
  for (const key in s.voices) {
    const ends = s.voices[key];
    let n = 0;
    for (let i = 0; i < ends.length; i++) if (ends[i] > now) ends[n++] = ends[i];
    ends.length = n;
  }
}

function activeVoices(s) {
  let n = 0;
  for (const key in s.voices) n += s.voices[key].length;
  return n;
}

// ---------------------------------------------------------------- haptique

function setHaptics(s, enabled) {
  s.haptics = !!enabled;
  // Coupe une vibration en cours (seulement après un geste : sinon le navigateur proteste).
  if (!s.haptics && mayVibrate(s)) vibrate(s, 0, true);
}

/**
 * Vibration permise : unlock() reçu ET activation utilisateur réelle. Les deux diffèrent au
 * tactile : Chrome n'active la page qu'au RELÂCHEMENT du doigt (pointerup / touchend), pas à
 * pointerdown — or le premier doigt posé sur le joystick reste appuyé. Sans ce garde, chaque
 * vibration écrit « Blocked call to navigator.vibrate… » en ERREUR console (mesuré, Chromium).
 */
function mayVibrate(s) {
  if (!s.unlocked) return false;
  const activation = s.nav?.userActivation;
  return !activation || activation.hasBeenActive === true;
}

/** Une seule vibration par image : la plus longue demandée. */
function pulseHaptics(s, entries) {
  if (!s.haptics || !mayVibrate(s)) return;
  let ms = 0;
  for (const entry of entries) ms = Math.max(ms, HAPTICS[entry.ev.type]?.(entry) ?? 0);
  if (ms > 0) vibrate(s, ms, false);
}

function vibrate(s, ms, force) {
  const nav = s.nav;
  if (!nav || typeof nav.vibrate !== 'function') return;
  const t = s.now();
  if (!force && t < s.hapticUntil && ms <= s.hapticMs) return;
  try {
    nav.vibrate(ms);
  } catch {
    // vibration refusée par le navigateur : sans conséquence
  }
  s.hapticUntil = t + ms + HAPTIC_GAP_MS;
  s.hapticMs = ms;
}

// ---------------------------------------------------------------- diagnostic

function statsOf(s) {
  if (s.ctx) pruneVoices(s, s.ctx.currentTime);
  const state = s.ctx ? s.ctx.state : s.failed ? 'failed' : 'none';
  return { supported: !!s.Ctor, state, voices: activeVoices(s), ...s.stats };
}

/** Clés de son connues et événements routés (outillage, tests). */
export const SOUND_KEYS = Object.keys(SOUNDS);
export const ROUTED_EVENTS = Object.keys(ROUTES);

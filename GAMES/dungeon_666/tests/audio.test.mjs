// Tests de src/audio/sfx.mjs sous node, avec un faux AudioContext STRICT : il lève là où
// WebAudio lèverait (rampe exponentielle vers 0, temps non fini, type inconnu…), compte les
// nœuds et simule la fin des sources pour vérifier qu'aucune voix ne fuit.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createAudio, ROUTED_EVENTS, SILENT_EVENTS } from '../src/audio/sfx.mjs';

// ---------------------------------------------------------------- faux WebAudio strict

const OSC_TYPES = new Set(['sine', 'square', 'sawtooth', 'triangle']);
const FILTER_TYPES = new Set(['lowpass', 'highpass', 'bandpass', 'lowshelf', 'highshelf', 'peaking', 'notch', 'allpass']);
const SAMPLE_RATE = 48000;

function checkTime(t) {
  if (!Number.isFinite(t) || t < 0) throw new RangeError(`temps invalide ${t}`);
}

class FakeParam {
  constructor(value) {
    this._v = value;
    this.events = [];
  }
  get value() {
    return this._v;
  }
  set value(v) {
    if (!Number.isFinite(v)) throw new TypeError(`valeur non finie ${v}`);
    this._v = v;
  }
  setValueAtTime(v, t) {
    checkTime(t);
    this.value = v;
    this.events.push(['set', v, t]);
  }
  linearRampToValueAtTime(v, t) {
    checkTime(t);
    this.value = v;
    this.events.push(['lin', v, t]);
  }
  exponentialRampToValueAtTime(v, t) {
    checkTime(t);
    if (!(v > 0) || !Number.isFinite(v)) throw new RangeError(`rampe exponentielle vers ${v}`);
    this.events.push(['exp', v, t]);
  }
  setTargetAtTime(v, t, tc) {
    checkTime(t);
    if (!Number.isFinite(v) || !(tc >= 0)) throw new RangeError('setTargetAtTime invalide');
    this.events.push(['target', v, t]);
  }
  cancelScheduledValues(t) {
    checkTime(t);
  }
}

class FakeNode {
  constructor(ctx, kind) {
    this.ctx = ctx;
    this.kind = kind;
    this.outputs = new Set();
    this.history = []; // toutes les cibles jamais connectées (diagnostic de fuite)
    this.disconnected = false;
    ctx.nodes.push(this);
  }
  connect(target) {
    if (!(target instanceof FakeNode || target instanceof FakeParam)) throw new TypeError('cible de connexion invalide');
    if (target instanceof FakeNode && target.ctx !== this.ctx) throw new Error('autre contexte');
    this.outputs.add(target);
    this.history.push(target);
    return target;
  }
  disconnect() {
    this.outputs.clear();
    this.disconnected = true;
  }
}

class FakeSource extends FakeNode {
  start(t = 0, offset = 0) {
    checkTime(t);
    if (this.startedAt !== undefined) throw new Error('start() appelé deux fois');
    if (!(offset >= 0)) throw new RangeError('offset invalide');
    this.startedAt = t;
    this.ctx.sources.push(this);
  }
  stop(t = 0) {
    checkTime(t);
    if (this.startedAt === undefined) throw new Error('stop() avant start()');
    this.stopAt = t;
  }
}

class FakeOscillator extends FakeSource {
  constructor(ctx) {
    super(ctx, 'osc');
    this.frequency = new FakeParam(440);
    this.detune = new FakeParam(0);
    this._type = 'sine';
  }
  set type(v) {
    if (!OSC_TYPES.has(v)) throw new TypeError(`type d'oscillateur ${v}`);
    this._type = v;
  }
  get type() {
    return this._type;
  }
}

class FakeFilter extends FakeNode {
  constructor(ctx) {
    super(ctx, 'filter');
    this.frequency = new FakeParam(350);
    this.Q = new FakeParam(1);
    this._type = 'lowpass';
  }
  set type(v) {
    if (!FILTER_TYPES.has(v)) throw new TypeError(`type de filtre ${v}`);
    this._type = v;
  }
  get type() {
    return this._type;
  }
}

function makeFakeContextClass() {
  const created = [];
  class FakeAudioContext {
    constructor() {
      this.sampleRate = SAMPLE_RATE;
      this.currentTime = 0;
      this.state = 'suspended';
      this.nodes = [];
      this.sources = [];
      this.destination = new FakeNode(this, 'destination');
      created.push(this);
    }
    resume() {
      this.state = 'running';
      return Promise.resolve();
    }
    createGain() {
      const n = new FakeNode(this, 'gain');
      n.gain = new FakeParam(1);
      return n;
    }
    createStereoPanner() {
      const n = new FakeNode(this, 'panner');
      n.pan = new FakeParam(0);
      return n;
    }
    createDynamicsCompressor() {
      const n = new FakeNode(this, 'compressor');
      for (const p of ['threshold', 'knee', 'ratio', 'attack', 'release']) n[p] = new FakeParam(0);
      return n;
    }
    createWaveShaper() {
      const n = new FakeNode(this, 'shaper');
      n.curve = null;
      n.oversample = 'none';
      return n;
    }
    createOscillator() {
      return new FakeOscillator(this);
    }
    createBiquadFilter() {
      return new FakeFilter(this);
    }
    createBufferSource() {
      const n = new FakeSource(this, 'buffer');
      n.buffer = null;
      n.loop = false;
      return n;
    }
    createBuffer(channels, length, rate) {
      if (!(length >= 1) || !(rate >= 3000)) throw new RangeError('createBuffer invalide');
      const data = new Float32Array(length);
      return { duration: length / rate, length, sampleRate: rate, getChannelData: () => data };
    }
    /** Avance l'horloge et déclenche onended des sources arrêtées. */
    advance(dt) {
      this.currentTime += dt;
      for (const src of this.sources) {
        // Un tampon joué sans boucle s'arrête seul à sa fin, comme dans WebAudio.
        const natural = src.buffer && !src.loop ? src.startedAt + src.buffer.duration : Infinity;
        const end = Math.min(src.stopAt ?? Infinity, natural);
        if (!src.ended && end <= this.currentTime) {
          src.ended = true;
          src.onended?.();
        }
      }
    }
  }
  return { FakeAudioContext, created };
}

function setup(extra = {}) {
  const { FakeAudioContext, created } = makeFakeContextClass();
  const vibrations = [];
  let clock = 0;
  const audio = createAudio({
    AudioContext: FakeAudioContext,
    navigator: { vibrate: (ms) => vibrations.push(ms) },
    now: () => clock,
    ...extra,
  });
  return {
    audio,
    vibrations,
    ctx: () => created[0],
    tick: (ms) => {
      clock += ms;
    },
  };
}

const GAME = { player: { x: 500, y: 400 } };

/** Un événement plausible par type routé (champs tels que la sim les émet). */
const SAMPLE_EVENTS = [
  { type: 'swing', x: 500, y: 400, angle: 0, arc: 2, range: 84, index: 0, strike: false },
  { type: 'swing', x: 500, y: 400, angle: 0, arc: 2, range: 84, index: 2, strike: false },
  { type: 'swing', x: 500, y: 400, angle: 0, arc: 2, range: 96, index: 0, strike: true },
  { type: 'hit', id: 3, x: 560, y: 400, amount: 10, crit: false, kind: 'melee', enemy: 'imp', shake: 0.12 },
  { type: 'hit', id: 3, x: 560, y: 400, amount: 38, crit: true, kind: 'strike', enemy: 'brute', shake: 0.22 },
  { type: 'hit', id: 3, x: 560, y: 400, amount: 3, crit: false, kind: 'burn', enemy: 'imp', shake: 0 },
  { type: 'kill', id: 3, x: 560, y: 400, enemy: 'imp', elite: false, boss: false, kind: 'melee' },
  { type: 'kill', id: 4, x: 560, y: 400, enemy: 'brute', elite: true, boss: false, kind: 'melee' },
  { type: 'kill', id: 5, x: 560, y: 400, enemy: 'boss', elite: false, boss: true, kind: 'skill' },
  { type: 'chain', x0: 560, y0: 400, x1: 620, y1: 420 },
  { type: 'dash', x: 500, y: 400, dirX: 1, dirY: 0, charges: 1 },
  { type: 'dodge', x: 500, y: 400 },
  { type: 'dashNova', x: 500, y: 400, r: 90 },
  { type: 'dashReady', charges: 2 },
  { type: 'deflect', x: 540, y: 380 },
  { type: 'skill', x: 500, y: 400, angle: 0 },
  { type: 'gadget', x: 500, y: 400, r: 150, charges: 2 },
  { type: 'super', x: 500, y: 400, r: 130 },
  { type: 'superTick', x: 500, y: 400, r: 130 },
  { type: 'superEnd', x: 500, y: 400 },
  { type: 'superReady' },
  { type: 'gadgetCharge', x: 0, y: 0, charges: 2 },
  { type: 'playerHurt', x: 500, y: 400, amount: 14, source: 'imp', srcX: 520, srcY: 400 },
  { type: 'playerDeath', x: 500, y: 400, source: 'arrow' },
  ...['imp', 'archer', 'brute', 'charger', 'boss', 'bossRing', 'inconnu'].map((enemy) => ({ type: 'enemyAttack', id: 9, x: 700, y: 300, enemy })),
  { type: 'explode', id: 9, x: 600, y: 400, r: 90 },
  ...['brute', 'bossSlam', 'fireBlast', 'sinBlast'].map((kind) => ({ type: 'hazardFire', id: 9, kind, shape: 'circle', x: 600, y: 400, r: 120, angle: 0, length: 0, width: 0 })),
  { type: 'hazardCancel', id: 9, x: 600, y: 400 },
  { type: 'wallSlam', id: 9, x: 100, y: 400 },
  { type: 'chargerWall', id: 9, x: 100, y: 400, boss: true },
  { type: 'spawnWarn', id: 9, x: 900, y: 600, enemy: 'imp', elite: true },
  { type: 'bossPhase', id: 9, x: 700, y: 300, phase: 2 },
  { type: 'bossSummon', id: 9, x: 700, y: 300 },
  { type: 'pickup', kind: 'gold', x: 500, y: 400, amount: 3 },
  { type: 'pickup', kind: 'heal', x: 500, y: 400, amount: 12 },
  { type: 'gold', x: 500, y: 400, amount: 25 },
  { type: 'buy', kind: 'heal' },
  { type: 'heal', x: 500, y: 400, amount: 12 },
  ...['commun', 'rare', 'epique'].map((rarity) => ({ type: 'boonGain', id: 'b', rarity })),
  ...['commun', 'magique', 'rare', 'legendaire'].map((rarity) => ({ type: 'equip', slot: 'arme', rarity })),
  { type: 'roomClear', floor: 3, kind: 'combat', boss: false },
  { type: 'roomClear', floor: 6, kind: 'boss', boss: true },
  { type: 'doorsOpen', count: 2 },
  { type: 'floorEnter', floor: 2, circle: 1, isBoss: false },
  { type: 'floorEnter', floor: 6, circle: 1, isBoss: true },
  { type: 'checkpoint', floor: 7 },
  { type: 'respawn', floor: 7 },
  { type: 'choiceOpen', kind: 'boon' },
  { type: 'victory', floor: 666 },
  { type: 'gameOver', floor: 12 },
];

// ---------------------------------------------------------------- tests

test('sans AudioContext : import et toutes les méthodes sont des no-op sans exception', () => {
  const audio = createAudio({ AudioContext: null, navigator: undefined });
  audio.unlock();
  audio.handleEvents(SAMPLE_EVENTS, GAME);
  audio.handleEvents(null, null);
  audio.handleEvents([null, 42, { type: 'hit', amount: NaN, x: 'a' }], {});
  audio.setVolume(0.3);
  audio.setMuted(true);
  audio.setHaptics(false);
  assert.equal(audio.isMuted(), true);
  assert.equal(audio.getVolume(), 0.3);
  assert.equal(audio.isHapticsEnabled(), false);
  const st = audio.getStats();
  assert.equal(st.supported, false);
  assert.equal(st.played, 0);
  assert.equal(st.errors, 0);
});

test('createAudio() sans option fonctionne sous node (pas d\'AudioContext global)', () => {
  const audio = createAudio();
  audio.handleEvents([{ type: 'hit', amount: 10, crit: true, x: 0, y: 0 }], { player: { x: 0, y: 0 } });
  assert.equal(audio.getStats().errors, 0);
});

test('aucun contexte créé ni son joué avant unlock()', () => {
  const t = setup();
  t.audio.handleEvents(SAMPLE_EVENTS, GAME);
  assert.equal(t.ctx(), undefined);
  assert.equal(t.audio.getStats().played, 0);
  assert.deepEqual(t.vibrations, [], 'pas de vibration sans geste utilisateur');
});

test('chaque type d\'événement routé joue sans erreur WebAudio, puis toutes les voix se libèrent', async () => {
  const t = setup();
  t.audio.unlock();
  await Promise.resolve();
  const ctx = t.ctx();
  assert.equal(ctx.state, 'running');
  for (const ev of SAMPLE_EVENTS) {
    t.audio.handleEvents([ev], GAME);
    ctx.advance(5); // laisse s'éteindre : la polyphonie ne doit pas masquer un son
  }
  const st = t.audio.getStats();
  assert.equal(st.errors, 0, st.lastError);
  assert.equal(st.played, SAMPLE_EVENTS.length, 'chaque événement échantillon produit un son');
  assert.equal(st.voices, 0);
  const covered = new Set(SAMPLE_EVENTS.map((e) => e.type));
  for (const type of ROUTED_EVENTS) assert.ok(covered.has(type), `événement routé non testé : ${type}`);
  assert.equal(ctx.sources.filter((src) => !src.ended).length, 0, 'toutes les sources se sont arrêtées');
  // Fuite : chaque sortie de voix (gain branché sur le bus ou sur un panoramique) est débranchée.
  const comp = ctx.nodes.find((n) => n.kind === 'compressor');
  const bus = ctx.nodes.find((n) => n.kind === 'gain' && n.history.includes(comp));
  const isVoiceOut = (n) => n.kind === 'gain' && n.history.some((h) => h === bus || h.kind === 'panner');
  const outs = ctx.nodes.filter(isVoiceOut);
  assert.ok(outs.length >= SAMPLE_EVENTS.length);
  assert.ok(outs.every((n) => n.disconnected), 'une voix terminée est restée branchée');
  assert.ok(ctx.nodes.filter((n) => n.kind === 'panner').every((n) => n.disconnected));
});

test('regroupement : 6 coups dans la même image donnent au plus 2 sons, plus forts', async () => {
  const t = setup();
  t.audio.unlock();
  await Promise.resolve();
  const hits = Array.from({ length: 6 }, (_, i) => ({ type: 'hit', x: 520, y: 400, amount: 10 + i, crit: i === 1, kind: 'melee', enemy: 'imp' }));
  t.audio.handleEvents(hits, GAME);
  const st = t.audio.getStats();
  assert.equal(st.played, 2);
  assert.equal(st.merged, 4);
});

test('polyphonie : plafond par type (4 coups) et plafond global', async () => {
  const t = setup();
  t.audio.unlock();
  await Promise.resolve();
  for (let i = 0; i < 10; i++) t.audio.handleEvents([{ type: 'hit', x: 520, y: 400, amount: 10, kind: 'melee', enemy: 'imp' }], GAME);
  assert.equal(t.audio.getStats().voices, 4);
  for (let i = 0; i < 10; i++) t.audio.handleEvents(SAMPLE_EVENTS.filter((e) => e.type !== 'hit'), GAME);
  const st = t.audio.getStats();
  assert.ok(st.dropped > 0);
  assert.equal(st.errors, 0, st.lastError);
  // Plafond global dur : 24 voix, réserve vitale comprise.
  assert.ok(st.voices <= 24, `voix actives : ${st.voices}`);
  assert.ok(st.voices >= 18, `la réserve vitale reste utilisable : ${st.voices}`);
});

test('explosion de possédé : explode + hazardFire(exploder) = un seul boum', async () => {
  const t = setup();
  t.audio.unlock();
  await Promise.resolve();
  t.audio.handleEvents([
    { type: 'hazard', id: 7, kind: 'exploder', x: 600, y: 400 },
    { type: 'explode', id: 7, x: 600, y: 400, r: 90 },
    { type: 'hazardFire', id: 7, kind: 'exploder', shape: 'circle', x: 600, y: 400, r: 90 },
  ], GAME);
  assert.equal(t.audio.getStats().played, 1);
});

test('sourdine et volume : rien ne joue en sourdine ; volume borné à [0, 1]', async () => {
  const t = setup();
  t.audio.unlock();
  await Promise.resolve();
  t.audio.setMuted(true);
  t.audio.handleEvents([{ type: 'dash', x: 500, y: 400 }], GAME);
  assert.equal(t.audio.getStats().played, 0);
  t.audio.setMuted(false);
  t.audio.handleEvents([{ type: 'dash', x: 500, y: 400 }], GAME);
  assert.equal(t.audio.getStats().played, 1);
  t.audio.setVolume(3);
  assert.equal(t.audio.getVolume(), 1);
  t.audio.setVolume(-1);
  assert.equal(t.audio.getVolume(), 0);
  t.audio.setVolume('n\'importe quoi');
  assert.equal(t.audio.getVolume(), 0);
  assert.equal(t.audio.getStats().errors, 0);
});

test('volume par défaut 0.6 appliqué au gain maître', async () => {
  const t = setup();
  assert.equal(t.audio.getVolume(), 0.6);
  t.audio.unlock();
  const master = t.ctx().nodes.find((n) => n.kind === 'gain' && n.outputs.has(t.ctx().destination));
  assert.equal(master.gain.value, 0.6);
});

test('panoramique léger : un son loin à droite du héros est panoramiqué à droite (≤ 0.5)', async () => {
  const t = setup();
  t.audio.unlock();
  await Promise.resolve();
  t.audio.handleEvents([{ type: 'deflect', x: 5000, y: 400 }], GAME);
  const panners = t.ctx().nodes.filter((n) => n.kind === 'panner');
  assert.equal(panners.length, 1);
  assert.equal(panners[0].pan.value, 0.5);
});

test('haptique : durées par événement, une vibration par image, réglage respecté', async () => {
  const t = setup();
  t.audio.unlock();
  const frame = (events) => {
    t.audio.handleEvents(events, GAME);
    t.tick(1000);
  };
  frame([{ type: 'playerHurt', x: 500, y: 400, amount: 10 }, { type: 'dodge', x: 500, y: 400 }]);
  frame([{ type: 'dodge', x: 500, y: 400 }]);
  frame([{ type: 'swing', index: 2, x: 500, y: 400 }, { type: 'hit', kind: 'melee', amount: 22, x: 520, y: 400 }]);
  frame([{ type: 'swing', index: 0, x: 500, y: 400 }, { type: 'hit', kind: 'melee', amount: 10, x: 520, y: 400 }]);
  frame([{ type: 'hit', kind: 'strike', amount: 18, x: 520, y: 400 }]);
  frame([{ type: 'kill', boss: true, x: 520, y: 400 }]);
  frame([{ type: 'bossPhase', x: 520, y: 400 }]);
  assert.deepEqual(t.vibrations, [40, 8, 12, 12, 80, 80]);
  t.audio.setHaptics(false);
  t.vibrations.length = 0;
  frame([{ type: 'playerHurt', x: 500, y: 400, amount: 10 }]);
  assert.deepEqual(t.vibrations, [], 'haptique désactivée');
});

test('haptique : une vibration faible n\'interrompt pas une plus forte en cours', async () => {
  const t = setup();
  t.audio.unlock();
  t.audio.handleEvents([{ type: 'bossPhase', x: 0, y: 0 }], GAME);
  t.tick(10);
  t.audio.handleEvents([{ type: 'dodge', x: 0, y: 0 }], GAME);
  t.tick(10);
  t.audio.handleEvents([{ type: 'kill', boss: true, x: 0, y: 0 }], GAME);
  assert.deepEqual(t.vibrations, [80], 'esquive et 2e vibration égale absorbées pendant la 1re');
  t.tick(200);
  t.audio.handleEvents([{ type: 'kill', boss: true, x: 0, y: 0 }], GAME);
  assert.deepEqual(t.vibrations, [80, 80]);
});

test('événements mal formés : jamais d\'exception, jamais d\'erreur WebAudio', async () => {
  const t = setup();
  t.audio.unlock();
  await Promise.resolve();
  t.audio.handleEvents([
    null,
    { type: 'hit', amount: NaN, x: 'a', crit: 'oui' },
    { type: 'swing', index: 7.4, strike: false },
    { type: 'hazardFire', kind: 'mystère', r: -50 },
    { type: 'equip', rarity: undefined },
    { type: 'boonGain' },
    { type: 'inconnu' },
  ], undefined);
  const st = t.audio.getStats();
  assert.equal(st.errors, 0, st.lastError);
  assert.ok(st.played >= 5);
});

test('regroupement : le son du groupe est plus fort que celui d\'un coup isolé', async () => {
  const peakOf = async (count) => {
    const t = setup({ random: () => 0.5 });
    t.audio.unlock();
    await Promise.resolve();
    const hits = Array.from({ length: count }, () => ({ type: 'hit', x: 500, y: 400, amount: 10, kind: 'melee', enemy: 'imp' }));
    t.audio.handleEvents(hits, GAME);
    let peak = 0;
    for (const n of t.ctx().nodes) {
      for (const [op, v] of n.gain?.events ?? []) if (op === 'lin') peak = Math.max(peak, v);
    }
    return peak;
  };
  const single = await peakOf(1);
  const grouped = await peakOf(6);
  assert.ok(grouped > single * 1.2, `groupe ${grouped} vs isolé ${single}`);
});

test('chaque événement émis par la sim est routé vers un son ou déclaré silencieux', async () => {
  const { readdir, readFile } = await import('node:fs/promises');
  const simDir = new URL('../src/sim/', import.meta.url);
  const types = new Set();
  for (const file of await readdir(simDir)) {
    const src = await readFile(new URL(file, simDir), 'utf8');
    for (const m of src.matchAll(/emit\(game, '([A-Za-z]+)'/g)) types.add(m[1]);
  }
  assert.ok(types.size > 30, `types trouvés : ${types.size}`);
  const known = new Set([...ROUTED_EVENTS, ...SILENT_EVENTS]);
  const missing = [...types].filter((t) => !known.has(t));
  assert.deepEqual(missing, [], 'événements de sim sans décision audio');
});

test('partie réelle : 30 s de combat scripté alimentent l\'audio sans aucune erreur', async () => {
  const { createGame, stepGame, emptyInput } = await import('../src/sim/game.mjs');
  const t = setup();
  t.audio.unlock();
  await Promise.resolve();
  const game = createGame({ seed: 666 });
  const seen = new Set();
  for (let tick = 0; tick < 1800 && game.mode === 'play'; tick++) {
    const input = scriptedInput(emptyInput(), tick);
    stepGame(game, input);
    for (const ev of game.events) seen.add(ev.type);
    t.audio.handleEvents(game.events, game);
    game.events.length = 0;
    t.ctx().advance(1 / 60);
  }
  const st = t.audio.getStats();
  assert.equal(st.errors, 0, st.lastError);
  assert.ok(st.played > 20, `sons joués : ${st.played}`);
  for (const type of ['swing', 'hit', 'dash']) assert.ok(seen.has(type), `événement attendu : ${type}`);
});

/** Pression continue d'attaque, dash / compétence / gadget / Super périodiques, cercle de marche. */
function scriptedInput(input, tick) {
  const a = tick / 90;
  input.moveX = Math.cos(a);
  input.moveY = Math.sin(a);
  input.attack = true;
  input.attackPressed = tick % 12 === 0;
  input.dashPressed = tick % 50 === 25;
  input.skillPressed = tick % 240 === 100;
  input.gadgetPressed = tick % 400 === 200;
  input.superPressed = tick % 60 === 30;
  return input;
}

// Vecteurs du lot « physique et combat » : collisions (src/sim/physics.mjs), champ de navigation
// (nav.mjs), visée assistée (aim.mjs), placement des apparitions (spawns.mjs), combat (combat.mjs) et
// projectiles (projectiles.mjs) — ces deux-là surtout par des SCÉNARIOS sur une partie synthétique.
// Salles SYNTHÉTIQUES (obstacles tirés au sort) : on éprouve la géométrie, pas le contenu du jeu.
// Un fichier de vecteurs exporte VECTORS : { module: async () => [{fn, cases: [{args, out}]}] }.

import { makeRng } from './_outils.mjs';

const many = (n, make) => Array.from({ length: n }, (_, i) => make(i));

/** Outils de tirage d'un générateur de vecteurs : u(a, b) uniforme, salle(), point(). */
function outils(seed) {
  const rnd = makeRng(seed);
  const u = (a, b) => a + (b - a) * rnd();
  const salle = () => {
    const obstacles = many(Math.floor(u(0, 6)), () => {
      const cx = u(160, 1240);
      const cy = u(140, 740);
      const w = u(40, 280);
      const h = u(40, 240);
      return { x0: cx - w / 2, y0: cy - h / 2, x1: cx + w / 2, y1: cy + h / 2 };
    });
    return { w: 1400, h: 880, pad: 40, obstacles };
  };
  const salles = many(10, salle);
  return { rnd, u, salle: () => salles[Math.floor(rnd() * salles.length)], point: () => [u(-20, 1420), u(-20, 900)] };
}

const clone = (v) => structuredClone(v);

// ---------------------------------------------------------------- scénarios
// combat.mjs et projectiles.mjs ne sont pas purs : ils écrivent dans la partie (événements,
// identifiants, tirages). Un SCÉNARIO est une partie synthétique minimale (héros de state.mjs,
// ennemis à la forme de enemies.mjs createEnemy, réglages par défaut) + une suite d'opérations ;
// la sortie est la partie entière après coup. Les réglages ne sont pas écrits dans le vecteur :
// l'adaptateur Godot prend les siens (data/tuning.json) et y pose `hitstopMode`.

const DT_SIM = 1 / 60;

// Procs à la forme produite par stats.mjs (chance: 1 par défaut, value résolue).
const PROCS = [
  { chance: 1, on: 'hit', sources: ['melee', 'strike'], effect: 'burn', duration: 3, value: 6 },
  { chance: 1, on: 'hit', sources: ['melee', 'strike'], effect: 'chill', duration: 2, value: 0.3 },
  { chance: 1, on: 'hit', sources: ['melee', 'strike'], effect: 'chill', duration: 2, value: 0.9 },
  { chance: 0.4, on: 'hit', sources: ['melee', 'strike'], effect: 'gold', valueFixed: 1, value: 1 },
  { chance: 1, on: 'kill', effect: 'heal', value: 2 },
  { chance: 1, on: 'kill', effect: 'blast', radius: 120, value: 15 },
  { chance: 1, on: 'hit', sources: ['skill'], effect: 'vuln', duration: 4, value: 0.3 },
  { chance: 0.5, on: 'hit', sources: ['melee', 'strike'], effect: 'chain', bounces: 2, range: 220, value: 10 },
  { chance: 1, on: 'hit', sources: ['skill'], effect: 'chain', bounces: 3, range: 240, value: 14 },
  { chance: 1, on: 'passive', effect: 'fullHpBonus', value: 0.3 },
  { chance: 1, on: 'passive', effect: 'execute', threshold: 0.3, value: 0.5 },
  { chance: 1, on: 'passive', effect: 'execute', threshold: 1.01, needsBurnChill: true, value: 0.4 },
  { chance: 1, on: 'hit', sources: ['chainHit'], effect: 'burn', duration: 3, value: 8 },
  { chance: 1, on: 'dash', effect: 'nova', radius: 80, value: 12 },
  // Contenu 2026-10-01 : chaque déclencheur, chaque condition, chaque effet nouveau.
  { chance: 1, on: 'dodge', effect: 'surge', duration: 3, value: 0.4 },
  { chance: 1, on: 'dodge', effect: 'nova', radius: 150, chill: 3, value: 8 },
  { chance: 1, on: 'dodge', effect: 'superCharge', value: 0.08 },
  { chance: 1, on: 'dodge', effect: 'dashCharge', value: 1 },
  { chance: 1, on: 'hit', sources: ['melee'], when: 'finisher', effect: 'blast', radius: 70, value: 12 },
  { chance: 1, on: 'hit', sources: ['melee'], when: 'finisher', effect: 'heal', value: 1.5 },
  { chance: 1, on: 'hit', sources: ['melee'], when: 'finisher', effect: 'stun', value: 0.6 },
  { chance: 1, on: 'hit', sources: ['strike'], effect: 'vuln', duration: 4, value: 0.25 },
  { chance: 1, on: 'hit', sources: ['chainHit'], effect: 'cull', value: 0.15 },
  { chance: 1, on: 'wallSlam', effect: 'stun', value: 1.2 },
  { chance: 1, on: 'wallSlam', effect: 'gold', value: 2 },
  { chance: 1, on: 'wallSlam', effect: 'blast', radius: 90, value: 20 },
  { chance: 1, on: 'roomClear', when: 'untouched', effect: 'gold', value: 14 },
  { chance: 1, on: 'roomClear', when: 'untouched', effect: 'gadgetCharge', value: 1 },
  { chance: 1, on: 'super', effect: 'heal', value: 15 },
  { chance: 1, on: 'super', effect: 'around', apply: 'burn', radius: 220, duration: 4, value: 10 },
  { chance: 1, on: 'overheal', effect: 'superCharge', perUnit: true, value: 0.01 },
  { chance: 1, on: 'dash', effect: 'chain', bounces: 3, range: 200, value: 9 },
  { chance: 1, on: 'kill', effect: 'chain', bounces: 2, range: 200, value: 8 },
  { chance: 0.5, on: 'kill', effect: 'gold', value: 3 },
  { chance: 1, on: 'passive', effect: 'goldPower', per: 25, cap: 5, value: 0.04 },
  { chance: 1, on: 'passive', effect: 'streakBonus', cap: 5, value: 0.06 },
  { chance: 1, on: 'passive', effect: 'stunnedCrit', value: 0.5 },
];
// Moments déclenchés à la main dans un scénario (opération fireProcs) et leurs contextes.
const PROC_MOMENTS = ['dodge', 'wallSlam', 'super', 'roomClear', 'dash', 'kill', 'overheal'];

async function scenarios(seed) {
  const { createTuning } = await import('../../src/sim/config.mjs');
  const { createPlayer, createTelemetry } = await import('../../src/sim/state.mjs');
  const R = await import('../../src/core/rng.mjs');
  const C = await import('../../src/sim/combat.mjs');
  const PJ = await import('../../src/sim/projectiles.mjs');
  const { rnd, u } = outils(seed);
  const pick = (arr) => arr[Math.floor(rnd() * arr.length)];
  const maybe = (p, v, otherwise = 0) => (rnd() < p ? v : otherwise);

  const foe = (tuning, id) => {
    const boss = rnd() < 0.12;
    const kind = pick(Object.keys(boss ? tuning.boss : tuning.enemies));
    const def = boss ? tuning.boss[kind] : tuning.enemies[kind];
    const maxHp = 20 + Math.floor(u(0, 100));
    const e = {
      id, kind, boss, x: 700 + u(-180, 180), y: 440 + u(-180, 180), vx: 0, vy: 0, kvx: maybe(0.3, u(-200, 200)), kvy: maybe(0.3, u(-200, 200)),
      r: def.radius, hp: rnd() < 0.4 ? maxHp : 1 + Math.floor(u(0, maxHp)), maxHp, mass: def.mass, dmgScale: u(1, 2),
      eliteMod: boss ? null : pick([null, null, null, 'blinde', 'ardent', 'vampirique', 'rapide']),
      state: 'chase', stateTime: 0.5, cooldown: 0.5, dirX: 0, dirY: 1, tele: maybe(0.2, { kind: 'swing' }, null), flash: 0,
      stun: maybe(0.2, 0.8), guard: maybe(0.2, 1), burn: maybe(0.3, 2), burnDps: maybe(0.3, 6), burnAcc: 0, chill: maybe(0.3, 1.5),
      chillMult: pick([1, 1, 0.7, 0]), vuln: maybe(0.2, 2), vulnMult: 0.3, spawnT: maybe(0.08, 0.2), bornAt: u(0, 2), dead: false,
      strafe: 1, flank: 0, hitPlayer: false, atkId: 0, summoned: rnd() < 0.15, lastHitAt: -1, freeze: 0,
      phase: 1, pattern: null, patternStep: 0, patternT: 0,
    };
    if (rnd() < 0.1) e.invuln = 0.5;
    if (boss && rnd() < 0.5) Object.assign(e, { exposed: 1, exposedMult: 0.5 });
    return e;
  };

  const world = () => {
    const tuning = createTuning();
    tuning.hitstopMode = pick(['global', 'local']);
    const player = createPlayer(tuning, 700, 440);
    Object.assign(player.stats, {
      superDamageMult: u(1, 1.5), superDurationBonus: 0, extraGoldOnKill: maybe(0.3, 2), weaponDamage: tuning.weaponBase * u(1, 3),
      critChance: u(0, 0.5), critMult: u(0, 0.5), lifesteal: maybe(0.3, 0.1), healOnKill: maybe(0.3, 2), knockbackMult: u(1, 1.5),
      armor: u(0, 0.8), goldFindMult: u(1, 2), damageMult: u(1, 2), skillDamageMult: u(1, 1.5), superChargeMult: u(1, 2), gadgetChargesBonus: maybe(0.3, 1),
    });
    player.maxHp = 120;
    player.hp = rnd() < 0.3 ? 120 : u(5, 120);
    player.procs = PROCS.filter(() => rnd() < 0.35).map(clone);
    player.superCharge = rnd() < 0.2 ? 0.995 : u(0, 1);
    player.state = pick(['free', 'free', 'free', 'attack', 'super']);
    player.iframes = maybe(0.2, 0.1);
    player.dodgeIframes = player.iframes > 0 ? maybe(0.6, 0.1) : 0;
    player.gadgetCharges = maybe(0.5, tuning.gadget.chargesPerSection);
    player.dashCharges = pick([0, 1, tuning.dash.charges]);
    if (rnd() < 0.25) Object.assign(player, { surge: u(0.1, 3), surgeMult: 0.4 });
    // Bourse et série sans blessure : lues par les procs passifs (la série peut manquer : ?? 0).
    const run = { gold: rnd() < 0.5 ? 0 : Math.floor(u(0, 220)), floor: 3 };
    if (rnd() < 0.6) run.streak = Math.floor(u(0, 8));
    return {
      tick: 120, time: 2, nextId: 100, events: [], rng: { combat: R.createRng(Math.floor(rnd() * 4294967296)), gen: R.createRng(Math.floor(rnd() * 4294967296)) },
      tuning, player, enemies: many(2 + Math.floor(u(0, 4)), (k) => foe(tuning, k + 1)), hazards: [], pickups: [], projectiles: [], spawns: [],
      telemetry: createTelemetry(), run, meta: { souls: 0, stats: { kills: 0 } }, hitstop: 0, hitstopBank: u(0, 0.12),
      sandbox: rnd() < 0.1, practice: rnd() < 0.1, godMode: rnd() < 0.05, room: { w: 1400, h: 880, pad: 40, obstacles: [], cleared: false },
    };
  };

  const dir = () => { const a = u(-Math.PI, Math.PI); return { dirX: Math.cos(a), dirY: Math.sin(a) }; };
  const idx = (game) => Math.floor(rnd() * game.enemies.length);
  const hazardOf = (game) => {
    const e = game.enemies[idx(game)];
    const at = rnd() < 0.5 ? game.player : e;
    const h = { kind: pick(['slam', 'fireBlast', 'exploder']), x: at.x + u(-30, 30), y: at.y + u(-30, 30), delay: u(0, 0.2), damage: u(4, 30) };
    const shape = pick(['circle', 'circle', 'line', 'ring']);
    if (shape === 'circle') Object.assign(h, { shape, r: u(40, 160) });
    if (shape === 'line') Object.assign(h, { shape, angle: u(-Math.PI, Math.PI), length: u(100, 400), width: u(30, 150) });
    if (shape === 'ring') Object.assign(h, { shape, r: u(80, 220), inner: u(0, 80) });
    if (rnd() < 0.4) h.sourceId = e.id;
    if (rnd() < 0.4) Object.assign(h, { hitsEnemies: true, hitsPlayer: rnd() < 0.5 });
    if (h.hitsEnemies && rnd() < 0.5) h.ownerId = e.id;
    if (rnd() < 0.3) Object.assign(h, { linger: u(0.1, 0.4), tickEvery: 0.05, tickDamage: 3 });
    return h;
  };
  const projectileOf = (game) => {
    const p = game.player;
    const e = game.enemies[idx(game)];
    const d = Math.max(1, Math.hypot(e.x - p.x, e.y - p.y));
    const [ux, uy] = [(e.x - p.x) / d + u(-0.15, 0.15), (e.y - p.y) / d + u(-0.15, 0.15)];
    if (rnd() < 0.5) return { owner: 'player', kind: 'lance', x: p.x, y: p.y, vx: ux * 700, vy: uy * 700, r: 8, damage: u(5, 40), range: u(100, 400), pierce: Math.floor(u(0, 3)), knockback: 200, hitstop: 0.03 };
    return { owner: 'enemy', kind: 'arrow', x: e.x, y: e.y, vx: -ux * 400, vy: -uy * 400, r: 6, damage: u(4, 20), range: 600, sourceId: e.id };
  };
  const srcOf = () => {
    const src = { kind: pick(['melee', 'melee', 'strike', 'skill', 'gadget', 'super', 'burn', 'blast', 'chain', 'enemyBlast', 'wall']), amount: u(1, 60), canCrit: rnd() < 0.6 };
    if (rnd() < 0.8) Object.assign(src, dir());
    if (rnd() < 0.5) src.knockback = u(100, 500);
    if (rnd() < 0.5) src.hitstop = u(0.02, 0.1);
    if (rnd() < 0.3) src.stun = u(0.3, 1.2);
    if (rnd() < 0.2) src.shake = 4;
    if (rnd() < 0.3) src.finisher = true;
    return src;
  };

  // Générateurs d'opérations : [nom, ...arguments]. Tirés AVANT d'être joués, puis copiés.
  const OPS = {
    damageEnemy: (g) => ['damageEnemy', idx(g), srcOf()],
    killEnemy: (g) => ['killEnemy', idx(g), rnd() < 0.3 ? null : { kind: 'melee' }],
    damagePlayer: (g) => ['damagePlayer', u(1, 50), rnd() < 0.5 ? { kind: 'arrow', id: 500 + Math.floor(u(0, 3)), x: u(600, 800), y: u(340, 540) } : { kind: 'slam', id: 500 + Math.floor(u(0, 3)) }],
    healPlayer: () => ['healPlayer', u(0, 30), true],
    spawnPickup: (g) => (rnd() < 0.5 ? ['spawnPickup', 'gold', g.player.x, g.player.y, 3] : ['spawnPickup', 'heal', u(100, 1300), u(100, 780), 10, { heal: 5, r: 12 }]),
    spawnHazard: (g) => ['spawnHazard', hazardOf(g)],
    spawnProjectile: (g) => ['spawnProjectile', projectileOf(g)],
    destroy: (g) => ['destroy', g.player.x, g.player.y, u(40, 260)],
    tick: () => ['tick', 1 + Math.floor(u(0, 20)), DT_SIM],
    iframes: () => ['iframes', maybe(0.4, 0.2), maybe(0.5, 0.1)],
    stun: (g) => ['stun', idx(g), u(0.1, 1)],
    cleared: () => ['cleared'],
    fireProcs: (g) => ['fireProcs', pick(PROC_MOMENTS), rnd() < 0.6 ? idx(g) : null, pick([null, { untouched: true }, { untouched: false }, { amount: u(0, 20) }])],
  };
  const play = (game, op) => {
    const [name, a, b, c, d, e] = op;
    switch (name) {
      case 'damageEnemy': return C.damageEnemy(game, game.enemies[a], b);
      case 'killEnemy': C.killEnemy(game, game.enemies[a], b); return null;
      case 'damagePlayer': return C.damagePlayer(game, a, b);
      case 'healPlayer': C.healPlayer(game, a, b); return null;
      case 'spawnPickup': C.spawnPickup(game, a, b, c, d, e); return null;
      case 'spawnHazard': C.spawnHazard(game, a); return null;
      case 'spawnProjectile': PJ.spawnProjectile(game, a); return null;
      case 'destroy': return PJ.destroyEnemyProjectilesInCircle(game, a, b, c);
      case 'tick':
        for (let i = 0; i < a; i++) {
          game.tick++;
          game.time += b;
          PJ.updateProjectiles(game, b);
          PJ.updateHazards(game, b);
        }
        return null;
      case 'iframes': game.player.iframes = a; game.player.dodgeIframes = b; return null;
      case 'stun': game.enemies[a].stun = b; return null;
      case 'cleared': game.room.cleared = true; return null;
      case 'fireProcs': C.fireProcs(game, a, b === null ? null : game.enemies[b], c); return null;
      default: throw new Error(`opération inconnue : ${name}`);
    }
  };

  /** Un cas : `names` = les opérations permises (tirées au sort, répétitions = poids). */
  return (names, count) => {
    const game = world();
    const { tuning, ...bare } = game;
    const start = clone(bare);
    const ops = [];
    const ret = [];
    for (let i = 0; i < count; i++) {
      const op = clone(OPS[pick(names)](game));
      ops.push(op);
      ret.push(play(game, clone(op)) ?? null);
    }
    const { tuning: _t, ...after } = game;
    return { args: [start, tuning.hitstopMode, ops], out: { game: after, ret } };
  };
}

export const VECTORS = {
  async physics() {
    const P = await import('../../src/sim/physics.mjs');
    const { rnd, u, salle, point } = outils(11);
    const N = 150;
    return [
      { fn: 'roomBounds', cases: many(20, () => { const room = { w: u(600, 1800), h: u(400, 1200), pad: u(0, 80), obstacles: [] }; return { args: [room], out: P.roomBounds(room) }; }) },
      {
        fn: 'moveCircle',
        cases: many(N * 2, (i) => {
          const room = salle();
          const [x, y] = point();
          const ent = { x, y, r: u(6, 44) };
          // Un tiers de pas d'une image, un tiers de dash, un tiers de traversée de salle.
          const reach = i % 3 === 0 ? 8 : i % 3 === 1 ? 90 : 700;
          const dx = i % 7 === 0 ? 0 : u(-reach, reach);
          const dy = i % 11 === 0 ? 0 : u(-reach, reach);
          const args = [room, clone(ent), dx, dy];
          const res = P.moveCircle(room, ent, dx, dy);
          return { args, out: { hitWall: res.hitWall, nx: res.nx, ny: res.ny, x: ent.x, y: ent.y } };
        }),
      },
      { fn: 'pointBlocked', cases: many(N, () => { const args = [salle(), ...point(), rnd() < 0.3 ? 0 : u(0, 40)]; return { args, out: P.pointBlocked(...args) }; }) },
      { fn: 'lineOfSight', cases: many(N, () => { const args = [salle(), ...point(), ...point()]; return { args, out: P.lineOfSight(...args) }; }) },
    ];
  },

  async nav() {
    const NV = await import('../../src/sim/nav.mjs');
    const { u, salle, point } = outils(12);
    const field = (room, px, py) => {
      const game = { room: { ...room, nav: NV.buildNav(room) }, tick: 0, player: { x: px, y: py } };
      NV.updateNav(game);
      return game;
    };
    return [
      {
        fn: 'buildNav',
        cases: many(20, () => {
          const room = salle();
          const nav = NV.buildNav(room);
          return { args: [room], out: { cols: nav.cols, rows: nav.rows, blocked: Array.from(nav.blocked), dist: Array.from(nav.dist), lastTick: nav.lastTick } };
        }),
      },
      {
        fn: 'updateNav',
        cases: many(30, () => {
          const room = salle();
          const [px, py] = point();
          const game = field(room, px, py);
          const first = Array.from(game.room.nav.dist);
          // Trop tôt (moins de 15 ticks) : le champ n'est pas recalculé, même si le héros a bougé.
          game.tick = 14;
          game.player.x = u(60, 1340);
          game.player.y = u(60, 820);
          const moved = [game.player.x, game.player.y];
          NV.updateNav(game);
          const early = Array.from(game.room.nav.dist);
          game.tick = 15;
          NV.updateNav(game);
          return { args: [room, px, py, ...moved], out: { first, early, late: Array.from(game.room.nav.dist), lastTick: game.room.nav.lastTick } };
        }),
      },
      {
        fn: 'navDirection',
        cases: many(300, () => {
          const room = salle();
          const [px, py] = [u(60, 1340), u(60, 820)];
          const [x, y] = point();
          const out = { x: 0, y: 0 };
          const ret = NV.navDirection(field(room, px, py), x, y, out);
          return { args: [room, px, py, x, y], out: { ret, x: out.x, y: out.y } };
        }),
      },
    ];
  },

  async aim() {
    const A = await import('../../src/sim/aim.mjs');
    const { DEFAULT_TUNING } = await import('../../src/sim/config.mjs');
    const { rnd, u, salle } = outils(13);
    return [
      {
        fn: 'computeAim',
        cases: many(300, (i) => {
          const moving = rnd() < 0.6;
          const player = {
            x: u(60, 1340), y: u(60, 820), moveX: moving ? u(-1, 1) : 0, moveY: moving ? u(-1, 1) : 0, facing: u(-Math.PI, Math.PI),
            lastTargetId: 1 + Math.floor(u(0, 6)), lastTargetAt: rnd() < 0.5 ? 10 - u(0, 0.8) : -99,
          };
          if (i % 25 === 0) delete player.lastTargetAt;
          const enemies = many(Math.floor(u(0, 7)), (k) => ({
            id: k + 1, x: player.x + u(-260, 260), y: player.y + u(-260, 260), r: u(12, 40), dead: rnd() < 0.1, spawnT: rnd() < 0.1 ? 0.2 : 0,
            state: rnd() < 0.3 ? 'windup' : 'chase', eliteMod: rnd() < 0.2 ? 'blinde' : null,
          }));
          const game = { time: 10, player, enemies, room: salle(), tuning: { autoAim: clone(DEFAULT_TUNING.autoAim) } };
          const manual = rnd() < 0.15 ? [u(-1, 1), u(-1, 1)] : rnd() < 0.2 ? [u(-0.1, 0.1), u(-0.1, 0.1)] : [0, 0];
          const range = rnd() < 0.4 ? undefined : u(80, 520);
          const args = [clone(game), ...manual, range];
          const o = A.computeAim(game, ...manual, range);
          return { args, out: { x: o.x, y: o.y, targetId: o.targetId, targetDist: o.targetDist } };
        }),
      },
    ];
  },

  async spawns() {
    const S = await import('../../src/sim/spawns.mjs');
    const R = await import('../../src/core/rng.mjs');
    const { rnd, u, salle } = outils(14);
    return [
      {
        // out.s : état du générateur après la recherche — l'ordre et le NOMBRE des tirages comptent.
        fn: 'findSpawnPoint',
        cases: many(300, (i) => {
          const seed = Math.floor(rnd() * 4294967296);
          const room = salle();
          const player = { x: u(60, 1340), y: u(60, 820) };
          const spawns = many(Math.floor(u(0, 5)), () => ({ x: u(60, 1340), y: u(60, 820) }));
          const near = i % 2 === 0 ? null : { x: u(100, 1300), y: u(100, 780), minR: u(30, 100), maxR: u(100, 320) };
          const r = u(10, 34);
          const minPlayerDist = i % 9 === 0 ? 3000 : u(0, 420);
          const game = { room, player, spawns, rng: { gen: R.createRng(seed) } };
          const pt = S.findSpawnPoint(game, r, minPlayerDist, near);
          return { args: [seed, room, player, spawns, r, minPlayerDist, near], out: { pt, s: game.rng.gen.s } };
        }),
      },
    ];
  },

  async combat() {
    const C = await import('../../src/sim/combat.mjs');
    const { rnd, u } = outils(15);
    const scenario = await scenarios(17);
    const hitstopGame = () => ({ hitstop: rnd() < 0.5 ? 0 : u(0, 0.1), hitstopBank: u(0, 0.12), tuning: { hitstopMode: rnd() < 0.5 ? 'local' : 'global' }, player: { freeze: rnd() < 0.5 ? 0 : u(0, 0.1) } });
    const snap = (game, target) => ({ hitstop: game.hitstop, hitstopBank: game.hitstopBank, playerFreeze: game.player.freeze, targetFreeze: target?.freeze ?? null });
    return [
      { fn: 'isPlayerSource', cases: ['melee', 'strike', 'skill', 'gadget', 'super', 'burn', 'blast', 'chain', 'enemyBlast', 'wall'].map((k) => ({ args: [k], out: C.isPlayerSource(k) })) },
      {
        fn: 'applyHitstop',
        cases: many(120, (i) => {
          const game = hitstopGame();
          const target = i % 3 === 0 ? null : i % 3 === 1 ? {} : { freeze: u(0, 0.1) };
          const args = [clone(game), u(0, 0.12), clone(target)];
          C.applyHitstop(game, args[1], target);
          return { args, out: snap(game, target) };
        }),
      },
      {
        fn: 'forceHitstop',
        cases: many(60, () => {
          const game = hitstopGame();
          const args = [clone(game), u(0, 0.2)];
          C.forceHitstop(game, args[1]);
          return { args, out: snap(game, null) };
        }),
      },
      {
        // show = false : le soin silencieux (vol de vie) n'émet aucun événement.
        fn: 'healPlayer',
        cases: many(60, (i) => {
          const maxHp = 100 + Math.floor(u(0, 80));
          const game = { player: { state: i % 10 === 0 ? 'dead' : 'free', hp: u(1, maxHp), maxHp } };
          const args = [clone(game), i % 7 === 0 ? -u(0, 5) : u(0, 60), false];
          C.healPlayer(game, args[1], false);
          return { args, out: game.player.hp };
        }),
      },
      // Le chemin entier : dégâts, critiques, procs, éclairs en chaîne, morts, butin, héros touché.
      { fn: 'scenario', cases: many(140, () => scenario(['damageEnemy', 'damageEnemy', 'damageEnemy', 'damageEnemy', 'killEnemy', 'damagePlayer', 'damagePlayer', 'healPlayer', 'spawnPickup', 'spawnHazard', 'iframes', 'fireProcs', 'fireProcs', 'stun'], 8)) },
    ];
  },

  async projectiles() {
    const PJ = await import('../../src/sim/projectiles.mjs');
    const { rnd, u } = outils(16);
    const scenario = await scenarios(18);
    return [
      // Projectiles et zones de danger sur plusieurs images : touches, perforation, annulation
      // d'un télégraphe (source morte ou étourdie), zones persistantes, explosions en chaîne.
      { fn: 'scenario', cases: many(140, () => scenario(['spawnProjectile', 'spawnProjectile', 'spawnHazard', 'spawnHazard', 'tick', 'tick', 'tick', 'tick', 'damageEnemy', 'destroy', 'iframes', 'stun', 'cleared'], 12)) },
      {
        fn: 'hazardProgress',
        cases: many(80, (i) => {
          const h = { t: u(0, 1.5), delay: i % 8 === 0 ? 0 : u(0.05, 1.2) };
          return { args: [h], out: PJ.hazardProgress(h) };
        }),
      },
      {
        fn: 'lingerLeft',
        cases: many(80, (i) => {
          const h = i % 5 === 0 ? { t: 0.2, delay: 0.5 } : { burning: i % 5 !== 1, linger: i % 6 === 0 ? 0 : u(0.5, 4), burnT: u(0, i % 4 === 0 ? 4.5 : 0.5) };
          return { args: [h], out: PJ.lingerLeft(h) };
        }),
      },
      {
        fn: 'compact',
        cases: many(80, () => {
          const arr = many(Math.floor(u(0, 14)), (k) => (rnd() < 0.4 ? { id: k, dead: true } : rnd() < 0.5 ? { id: k, dead: false } : { id: k }));
          const args = [clone(arr)];
          PJ.compact(arr);
          return { args, out: arr };
        }),
      },
    ];
  },
};

// Vecteurs du lot « socle de partie » : state, floors, lab, loadout, profile, boons, loot, stats,
// sections (src/sim/<module>.mjs). Même forme que socle.mjs :
// VECTORS = { module: async () => [{fn, cases: [{args, out}]}] }.
//
// Quand une fonction prend un `game`, l'argument est une FICHE de partie (spec) : graine, surcharge
// de tuning, meta, run, héros. Les deux côtés reconstruisent la même partie minimale à partir
// de la fiche (ici gameMaker, côté Godot parite/adaptateurs/state.gd make_game). Quand une
// fonction modifie son argument, la sortie comparée contient l'état APRÈS l'appel.

import { makeRng } from './_outils.mjs';

const SIM = '../../src/sim/';
const clone = (v) => structuredClone(v);
const many = (n, make) => Array.from({ length: n }, (_, i) => make(i));

/** Tirages de l'exporteur (jamais ceux d'une partie). */
function tools(seed) {
  const rnd = makeRng(seed);
  return {
    rnd,
    int: (a, b) => a + Math.floor(rnd() * (b - a + 1)),
    of: (arr) => arr[Math.floor(rnd() * arr.length)],
    chance: (p) => rnd() < p,
    seed32: () => Math.floor(rnd() * 4294967296),
  };
}

/** Fiche de partie complète (aucun champ implicite : Godot lit les mêmes clés). */
function spec(o = {}) {
  return { seed: 1, tuning: null, nextId: 1, tick: 0, meta: {}, run: { floor: 1, items: {}, boons: [] }, player: null, ...o };
}

async function gameMaker() {
  const { createTuning } = await import(`${SIM}config.mjs`);
  const { createRng } = await import('../../src/core/rng.mjs');
  return (s) => ({
    tuning: createTuning(s.tuning),
    rng: { gen: createRng(s.seed) },
    nextId: s.nextId,
    tick: s.tick,
    events: [],
    meta: clone(s.meta),
    run: clone(s.run),
    player: clone(s.player),
  });
}

const CLASSES = ['revenant', 'bourreau', 'chasseresse'];
const WEAPONS = ['lame', 'dagues', 'hache', 'marteau', 'arc', 'arbalete'];
const SKILLS = ['lance', 'chaine', 'bond', 'brasier', 'volee'];
const GADGETS = ['nova', 'bombe', 'piege', 'cri', 'totem'];
const ITEM_RARITIES = ['commun', 'magique', 'rare', 'legendaire'];
const SEEDS = [0, 1, 2, 42, 0x7fffffff, 0x80000000, 0xffffffff, -1, 3.7, 2 ** 40 + 5];

/** Bénédictions d'un run tirées par des addBoon successifs (état toujours atteignable). */
function randomBoons(T, B, n) {
  const ids = [...B.BOONS, ...B.DUOS].map((b) => b.id);
  const run = { boons: [] };
  for (let i = 0; i < n; i++) B.addBoon(run, { id: T.of(ids), rarity: T.of(['commun', 'rare', 'epique']), level: 1 });
  return run.boons;
}

/** Objets tirés par generateItem sur des parties jetables (classe, étage, rareté variés). */
async function randomItems(T, n) {
  const L = await import(`${SIM}loot.mjs`);
  const mk = await gameMaker();
  return many(n, () => {
    const g = mk(spec({ seed: T.seed32(), nextId: T.int(1, 500), meta: { loadout: { classId: T.of(CLASSES) }, unlocked: { weapons: WEAPONS } } }));
    return L.generateItem(g, { slot: T.of(L.SLOTS), rarity: T.of(ITEM_RARITIES), floor: T.of([1, 2, 7, 18, 60, 200, 666]), weaponType: T.of(WEAPONS) });
  });
}

export const VECTORS = {
  async state() {
    const S = await import(`${SIM}state.mjs`);
    const { createTuning } = await import(`${SIM}config.mjs`);
    const T = tools(11);
    const overrides = [null, { player: { radius: 20, maxHp: 140 } }, { dash: { charges: 3 } }, { gadget: { chargesPerSection: 5 } }, { super: { startCharge: null } }, { super: { startCharge: 0.9 } }];
    const datas = [null, {}, { x: 1.5, y: -2 }, { type: 'écrasé', tick: 99 }, { id: 7, kind: 'imp', crit: true }, { list: [1, 2], o: { a: 1 } }];
    return [
      {
        fn: 'newId',
        cases: many(10, (i) => {
          const start = i === 0 ? 1 : T.int(1, 100000);
          const g = { nextId: start };
          const ids = many(5, () => S.newId(g));
          return { args: [start, 5], out: { ids, next: g.nextId } };
        }),
      },
      {
        fn: 'emit',
        cases: many(12, (i) => {
          const g = { tick: T.int(0, 5000), events: [{ type: 'avant', tick: 0 }] };
          const data = datas[i % datas.length];
          const args = [g.tick, T.of(['hit', 'kill', 'dash']), clone(data)];
          const ev = S.emit(g, args[1], data === null ? undefined : clone(data));
          return { args, out: { ev, count: g.events.length, last: g.events[g.events.length - 1] } };
        }),
      },
      { fn: 'baseStats', cases: [{ args: [], out: S.baseStats() }] },
      {
        fn: 'createPlayer',
        cases: many(40, (i) => {
          const args = [overrides[i % overrides.length], (T.rnd() - 0.5) * 2800, (T.rnd() - 0.5) * 1760];
          return { args, out: S.createPlayer(createTuning(args[0]), args[1], args[2]) };
        }),
      },
      { fn: 'createTelemetry', cases: [{ args: [], out: S.createTelemetry() }] },
    ];
  },

  async floors() {
    const F = await import(`${SIM}floors.mjs`);
    const { createTuning } = await import(`${SIM}config.mjs`);
    const T = tools(12);
    const others = [
      { floors: { sectionLength: 6, total: 100, circleLength: 24 } },
      { floors: { total: 650 } },
      { player: { innateHp: null } },
      { armorBase: null },
      { floors: { itemGrowth: 0.1, permBuildCap: 0.9, dmgScale: 10, sectionBuildCap: 0.5 } },
    ];
    const odd = [0, -5, 667, 1000, 3.7, 18.999, NaN, Infinity, -Infinity, 'abc', '12', ' 40 ', '', null, true, false];
    const call = (fn, over, ...rest) => ({ args: [over, ...rest], out: F[fn](createTuning(over), ...rest) });
    const allFloors = many(666, (i) => i + 1);
    const allSections = many(37, (i) => i + 1);
    const guardianTunings = [null, { guardians: { rotation: ['minos', 'inconnu', 'gardien'] } }, { guardians: { rotation: [] } }, { guardians: { rotation: ['x'] } }, { boss: { cerbere: null } }];
    return [
      {
        fn: 'floorInfo',
        cases: [
          ...allFloors.map((n) => call('floorInfo', null, n)),
          ...odd.map((n) => call('floorInfo', null, n)),
          ...others.flatMap((o) => many(60, () => call('floorInfo', o, T.int(-3, 700)))),
        ],
      },
      { fn: 'checkpointAfterBoss', cases: [...allSections.map((s) => call('checkpointAfterBoss', null, s * 18)), ...many(20, () => call('checkpointAfterBoss', T.of([null, ...others]), T.int(1, 666)))] },
      {
        fn: 'floorScaling',
        cases: [
          ...allFloors.map((n) => call('floorScaling', null, n)),
          ...odd.map((n) => call('floorScaling', null, n)),
          ...others.flatMap((o) => many(60, () => call('floorScaling', o, T.int(-3, 700)))),
        ],
      },
      { fn: 'playerHpGrowth', cases: [null, ...others].flatMap((o) => many(20, () => call('playerHpGrowth', o, 1 + T.rnd() * 40))) },
      { fn: 'sectionStartDifficulty', cases: [...allSections.map((s) => call('sectionStartDifficulty', null, s)), ...many(16, (i) => call('sectionStartDifficulty', others[0], i + 1)), ...allSections.map((s) => call('sectionStartDifficulty', others[4], s))] },
      { fn: 'guardianFor', cases: guardianTunings.flatMap((o) => many(42, (i) => call('guardianFor', o, i - 2))) },
      { fn: 'sectionBounds', cases: [...many(40, (i) => call('sectionBounds', null, i)), ...many(18, (i) => call('sectionBounds', others[0], i + 1)), ...many(38, (i) => call('sectionBounds', others[1], i + 1))] },
    ];
  },

  async lab() {
    const Lab = await import(`${SIM}lab.mjs`);
    const { createTuning } = await import(`${SIM}config.mjs`);
    const T = tools(13);
    const view = (t) => ({ strikeCancelFrom: t.dash.strikeCancelFrom, strikeWindow: t.dash.strikeWindow, hitstopMode: t.hitstopMode, attackMoveMult: t.player.attackMoveMult, cancelMult: t.player.cancelMult, lab: t.lab });
    const axes = Object.keys(Lab.LAB_AXES);
    const choices = { dashStrike: ['fin', 'toutDash', 'apresDash'], hitstop: ['global', 'local'], comboMobility: ['ancre', 'mobile', 'fluide'] };
    const combos = [];
    for (const a of choices.dashStrike) for (const b of choices.hitstop) for (const c of choices.comboMobility) combos.push({ lab: { dashStrike: a, hitstop: b, comboMobility: c } });
    const broken = [
      { lab: null }, { lab: 'texte' }, { lab: 5 }, { lab: { dashStrike: 'inconnue' } }, { lab: { dashStrike: null, hitstop: 7, comboMobility: 'fluide' } },
      { lab: { hitstop: 'local' }, dash: { strikeCancelFrom: 0.9, strikeWindow: 0.11 }, player: { attackMoveMult: 0.99, cancelMult: 3 }, hitstopMode: 'autre' },
      { lab: { comboMobility: 'ancre', dashStrike: 'toutDash', hitstop: 'global', enTrop: 'x' } }, null,
    ];
    const all = [...combos, ...broken];
    const anyChoice = () => T.of([...choices.dashStrike, ...choices.hitstop, ...choices.comboMobility, 'inconnue', null, 3]);
    return [
      {
        fn: 'applyLab',
        cases: all.map((o) => {
          const t = createTuning(o);
          const ret = Lab.applyLab(t);
          return { args: [o], out: { same: ret === t, view: view(t) } };
        }),
      },
      {
        fn: 'setLab',
        cases: many(60, (i) => {
          const o = all[i % all.length];
          const ops = many(T.int(1, 4), () => [T.of([...axes, 'inconnu', null]), anyChoice()]);
          const t = createTuning(o);
          const rets = ops.map(([axis, choice]) => Lab.setLab(t, axis, choice));
          return { args: [o, ops], out: { rets, view: view(t) } };
        }),
      },
      { fn: 'labSummary', cases: all.map((o) => ({ args: [o], out: Lab.labSummary(createTuning(o)) })) },
    ];
  },

  async loadout() {
    const Lo = await import(`${SIM}loadout.mjs`);
    const mk = await gameMaker();
    const T = tools(14);
    const tunings = [null, null, null, { skills: { chaine: null } }, { supers: { sentence: null } }, { classes: { revenant: { weapons: [] } } }, { gadgets: { totem: null, bombe: null } }];
    const makeSpec = () => {
      const meta = {};
      if (T.chance(0.9)) {
        meta.loadout = {};
        if (T.chance(0.9)) meta.loadout.classId = T.of([...CLASSES, 'inconnue', null]);
        if (T.chance(0.8)) meta.loadout.skillId = T.of([...SKILLS, 'inconnue']);
        if (T.chance(0.8)) meta.loadout.gadgetId = T.of([...GADGETS, 'inconnu']);
      }
      const items = {};
      const r = T.rnd();
      if (r < 0.2) items.arme = null;
      else if (r < 0.3) items.arme = { name: 'sans type' };
      else if (r < 0.9) items.arme = { weaponType: T.of([...WEAPONS, 'inconnu', '']) };
      return spec({ tuning: T.of(tunings), meta, run: { floor: 1, items, boons: [] } });
    };
    const specs = many(160, makeSpec);
    const kitView = (g, ret) => {
      const t = g.tuning;
      return {
        kit: g.kit,
        retIsKit: ret === g.kit,
        weapon: t.weapon.name,
        comboSame: t.combo === t.weapons[g.kit.weaponType].combo,
        dashStrikeSame: t.dashStrike === t.weapons[g.kit.weaponType].dashStrike,
        skillSame: t.skill === t.skills[g.kit.skillId],
        gadgetSame: t.gadget === t.gadgets[g.kit.gadgetId],
        skill: t.skill.name,
        gadget: t.gadget.name,
        super: t.super.name,
      };
    };
    return [
      { fn: 'classOf', cases: specs.map((s) => ({ args: [s], out: Lo.classOf(mk(s)).name })) },
      { fn: 'classIdOf', cases: specs.map((s) => ({ args: [s], out: Lo.classIdOf(mk(s)) })) },
      { fn: 'weaponTypeOf', cases: specs.map((s) => ({ args: [s], out: Lo.weaponTypeOf(mk(s)) })) },
      {
        fn: 'resolveKit',
        cases: specs.map((s) => {
          const g = mk(s);
          const ret = Lo.resolveKit(g);
          return { args: [s], out: kitView(g, ret) };
        }),
      },
    ];
  },

  async boons() {
    const B = await import(`${SIM}boons.mjs`);
    const mk = await gameMaker();
    const T = tools(15);
    const defs = [...B.BOONS, ...B.DUOS];
    const ids = defs.map((b) => b.id);
    const rarities = ['commun', 'rare', 'epique', 'mythique', null];
    const families = [...Object.keys(B.FAMILIES), 'inconnue'];
    const addCases = [];
    for (let w = 0; w < 30; w++) {
      const run = { boons: [] };
      for (let i = 0; i < 12; i++) {
        const offer = { id: T.of([...ids, 'inconnue']), rarity: T.of(['commun', 'rare', 'epique', 'mythique']), level: 1 };
        const before = clone(run.boons);
        B.addBoon(run, offer);
        addCases.push({ args: [before, offer], out: clone(run.boons) });
      }
    }
    return [
      { fn: 'boonDef', cases: [...ids, 'inconnue', null].map((id) => ({ args: [id], out: B.boonDef(id) })) },
      { fn: 'boonValue', cases: defs.flatMap((d) => rarities.map((r) => ({ args: [d.id, r], out: B.boonValue(d, r) }))) },
      { fn: 'boonText', cases: defs.flatMap((d) => rarities.map((r) => ({ args: [d.id, r], out: B.boonText(d, r) }))) },
      {
        fn: 'rollBoonOffer',
        cases: many(280, (i) => {
          const boons = randomBoons(T, B, T.int(0, 9));
          const s = spec({ seed: T.seed32(), run: { floor: 1, items: {}, boons } });
          const family = families[i % families.length];
          const g = mk(s);
          const offer = B.rollBoonOffer(g, family);
          return { args: [s, family], out: { offer, s: g.rng.gen.s } };
        }),
      },
      { fn: 'addBoon', cases: addCases },
      {
        fn: 'randomFamily',
        cases: many(40, () => {
          const s = spec({ seed: T.seed32() });
          const g = mk(s);
          return { args: [s], out: many(8, () => B.randomFamily(g)) };
        }),
      },
    ];
  },

  async loot() {
    const L = await import(`${SIM}loot.mjs`);
    const mk = await gameMaker();
    const T = tools(16);
    const tunings = [null, null, null, { weapons: { lame: { bases: null }, hache: { baseMult: 1.3 }, arc: { starterName: null } }, loot: { rarityWeights: { legendaire: 40 } } }];
    const metaOf = () => {
      const m = { loadout: { classId: T.of([...CLASSES, 'inconnue']) } };
      if (T.chance(0.85)) m.unlocked = { weapons: WEAPONS.filter(() => T.chance(0.5)) };
      return m;
    };
    const runOf = () => ({
      floor: T.of([1, 1, 2, 5, 18, 19, 100, 333, 666]),
      items: T.chance(0.5) ? { arme: T.chance(0.3) ? null : { weaponType: T.of([...WEAPONS, 'inconnu']) } } : {},
      boons: [],
    });
    const gameSpec = () => spec({ seed: T.seed32(), tuning: T.of(tunings), nextId: T.int(1, 900), meta: metaOf(), run: runOf() });
    const optsOf = () => {
      const o = {};
      if (T.chance(0.5)) o.slot = T.of(L.SLOTS);
      if (T.chance(0.5)) o.rarity = T.of(ITEM_RARITIES);
      if (T.chance(0.3)) o.floor = T.int(1, 666);
      if (T.chance(0.2)) o.weaponType = T.of(WEAPONS);
      return o;
    };
    const generated = many(500, (i) => {
      const s = gameSpec();
      const opts = i < 40 ? null : optsOf();
      const g = mk(s);
      const item = opts === null ? L.generateItem(g) : L.generateItem(g, clone(opts));
      return { args: [s, opts], out: { item, s: g.rng.gen.s, nextId: g.nextId } };
    });
    const items = [
      ...generated.slice(0, 220).map((c) => c.out.item),
      { slot: 'talisman', rarity: 'inconnue', level: 7, affixes: [], power: null },
      { slot: 'arme', rarity: 'rare', level: 0, affixes: [], power: 'lame_azazel', base: {} },
      { slot: 'armure', rarity: 'commun', level: 44, affixes: [{ stat: 'maxHpBonus', value: 31, format: 'flat' }], power: null, base: { hp: 0, damage: 0 } },
      { slot: 'arme', rarity: 'magique', level: 3, affixes: [{ stat: 'damageMult', value: -0.0004, format: 'pct' }], power: '', base: { damage: 10.8, hp: 12 } },
    ];
    const affixes = [
      ...items.flatMap((it) => it.affixes),
      { stat: 'inconnue', value: 3, format: 'flat' },
      { stat: 'dashRechargeMult', value: -0.004, format: 'pctNeg' },
      { stat: 'dashRechargeMult', value: -0.125, format: 'pctNeg' },
      { stat: 'critChance', value: 0.0005, format: 'pct' },
      { stat: 'armor', value: 0.123, format: 'pct' },
      { stat: 'maxHpBonus', value: 12.5, format: 'flat' },
    ];
    return [
      {
        fn: 'rollRarity',
        cases: many(60, (i) => {
          const s = spec({ seed: T.seed32(), tuning: T.of(tunings) });
          const bonus = i % 4 === 0 ? null : T.of([1, 1.8, 2, 3.6, 0, 10]);
          const g = mk(s);
          return { args: [s, bonus], out: many(8, () => (bonus === null ? L.rollRarity(g) : L.rollRarity(g, bonus))) };
        }),
      },
      { fn: 'generateItem', cases: generated },
      {
        fn: 'starterItems',
        cases: many(24, () => {
          const s = gameSpec();
          const g = mk(s);
          return { args: [s], out: { items: L.starterItems(g), nextId: g.nextId } };
        }),
      },
      { fn: 'itemScore', cases: items.map((it) => ({ args: [it], out: L.itemScore(it) })) },
      { fn: 'salvageValue', cases: items.map((it) => ({ args: [it], out: L.salvageValue(it) })) },
      { fn: 'baseText', cases: items.map((it) => ({ args: [it], out: L.baseText(it) })) },
      { fn: 'affixText', cases: affixes.map((a) => ({ args: [a], out: L.affixText(a) })) },
      {
        fn: 'randomShopItem',
        cases: many(120, () => {
          const s = gameSpec();
          const g = mk(s);
          const item = L.randomShopItem(g);
          return { args: [s], out: { item, s: g.rng.gen.s, nextId: g.nextId } };
        }),
      },
      {
        fn: 'priceOf',
        cases: many(80, (i) => {
          const s = spec({ seed: T.seed32(), tuning: i % 5 === 0 ? { economy: { shopItemPrice: [35, 215] } } : null });
          const item = { rarity: T.of([...ITEM_RARITIES, 'inconnue']) };
          const g = mk(s);
          return { args: [s, item], out: { price: L.priceOf(g, item), s: g.rng.gen.s } };
        }),
      },
    ];
  },

  async stats() {
    const St = await import(`${SIM}stats.mjs`);
    const S = await import(`${SIM}state.mjs`);
    const B = await import(`${SIM}boons.mjs`);
    const { createTuning } = await import(`${SIM}config.mjs`);
    const mk = await gameMaker();
    const T = tools(17);
    const pool = await randomItems(T, 400);
    const bySlot = (slot) => pool.filter((it) => it.slot === slot);
    const slots = { arme: bySlot('arme'), armure: bySlot('armure'), talisman: bySlot('talisman') };
    const upgradeIds = ['vitalite', 'celerite', 'ferocite', 'arsenal', 'fortune', 'avidite', 'inconnue'];
    const tunings = [null, null, null, { town: null }, { classes: { bourreau: { stats: null } } }, { dash: { charges: 1 }, player: { innateHp: 30 } }];
    const makeSpec = (i) => {
      const tuning = T.of(tunings);
      const meta = { loadout: { classId: T.of(CLASSES), skillId: T.of(SKILLS), gadgetId: T.of(GADGETS) } };
      if (T.chance(0.8)) {
        meta.upgrades = {};
        for (const id of upgradeIds) if (T.chance(0.5)) meta.upgrades[id] = T.int(0, 5);
      }
      const items = {};
      for (const slot of ['arme', 'armure', 'talisman']) {
        const r = T.rnd();
        if (r < 0.15) items[slot] = null;
        else if (r < 0.2 && slot !== 'talisman') items[slot] = { slot, rarity: 'commun', name: 'sans base', level: 1, affixes: [], power: null };
        else items[slot] = clone(T.of(slots[slot]));
      }
      const boons = randomBoons(T, B, i % 7 === 0 ? 0 : T.int(1, 14));
      if (T.chance(0.15)) boons.push({ id: 'inconnue', rarity: 'rare', level: 2 });
      if (T.chance(0.15) && boons.length) boons[0].rarity = 'mythique';
      const player = S.createPlayer(createTuning(tuning), 0, 0);
      player.maxHp = T.of([100, 100, 60, 250]);
      player.hp = Math.max(1, Math.round(player.maxHp * T.rnd()));
      player.dashCharges = T.int(0, 4);
      player.gadgetCharges = T.int(0, 6);
      return spec({ tuning, meta, run: { floor: T.int(1, 666), items, boons }, player });
    };
    return [
      {
        fn: 'recomputeStats',
        cases: many(260, (i) => {
          const s = makeSpec(i);
          const g = mk(s);
          St.recomputeStats(g);
          return { args: [s], out: { player: g.player, kit: g.kit, weapon: g.tuning.weapon.name } };
        }),
      },
    ];
  },

  async profile() {
    const P = await import(`${SIM}profile.mjs`);
    const { createTuning } = await import(`${SIM}config.mjs`);
    const T = tools(18);
    const base = createTuning();
    const kinds = { classes: Object.keys(base.classes), weapons: Object.keys(base.weapons), skills: Object.keys(base.skills), gadgets: Object.keys(base.gadgets) };
    const upgradeIds = Object.keys(base.town.upgrades);
    const pool = await randomItems(T, 300);
    const item = () => clone(T.of(pool));
    const weapon = () => clone(T.of(pool.filter((it) => it.slot === 'arme')));
    const groups = {};
    const push = (fn, c) => (groups[fn] ??= []).push(c);
    const tunings = [null, null, null, null, { town: null }, { weapons: { dagues: { cost: 0 }, arc: { starterName: null, baseMult: null } }, town: { upgrades: { vitalite: { max: 2 } } } }];

    // Opérations de la Ville : marches aléatoires, chaque pas est un cas (profil avant → après).
    const op = (fn, profile, over, ...rest) => {
      const before = clone(profile);
      const ret = P[fn](profile, createTuning(over), ...rest);
      push(fn, { args: [before, over, ...rest], out: { ret, profile: clone(profile) } });
    };
    const loot = (profile, it) => {
      const before = clone(profile);
      const found = clone(it);
      P.stashLoot(profile, it);
      push('stashLoot', { args: [before, found], out: clone(profile) });
    };
    const step = (profile, over) => {
      const r = T.rnd();
      const uid = () => (profile.stash.length && T.chance(0.85) ? T.of(profile.stash).uid : 'i999');
      if (r < 0.2) {
        const kind = T.of([...Object.keys(kinds), 'inconnu']);
        op('unlock', profile, over, kind, T.of([...(kinds[kind] ?? []), 'zzz']));
      } else if (r < 0.32) op('buyUpgrade', profile, over, T.of([...upgradeIds, 'zzz']));
      else if (r < 0.46) op('selectClass', profile, over, T.of([...kinds.classes, 'zzz']));
      else if (r < 0.54) op('selectSkill', profile, over, T.of([...kinds.skills, 'zzz']));
      else if (r < 0.62) op('selectGadget', profile, over, T.of([...kinds.gadgets, 'zzz']));
      else if (r < 0.76) loot(profile, item());
      else if (r < 0.9) op('equipFromStash', profile, over, uid());
      else op('salvageFromStash', profile, over, uid());
    };
    for (let w = 0; w < 18; w++) {
      const over = T.of(tunings);
      const t = createTuning(over);
      const profile = P.newProfile(t);
      profile.souls = T.of([0, 50, 400, 5000]);
      if (T.chance(0.6)) profile.equipment.arme = { ...P.starterWeapon(t, 'lame'), uid: 'i0' };
      for (let i = 0; i < 26; i++) step(profile, over);
    }
    // Coffre plein : le moins bon part, jamais celui qu'on vient d'y ranger.
    for (let w = 0; w < 3; w++) {
      const profile = P.newProfile(base);
      profile.souls = 300;
      for (let i = 0; i < 22 + w; i++) P.stashLoot(profile, item());
      if (w === 1) for (const it of profile.stash) delete it.score;
      for (let i = 0; i < 6; i++) {
        const r = T.rnd();
        if (r < 0.6) loot(profile, item());
        else if (r < 0.8) op('equipFromStash', profile, null, T.of(profile.stash).uid);
        else op('selectClass', profile, null, T.of(kinds.classes));
      }
    }

    // Sauvegardes abîmées : 1 à 4 dégâts tirés sur un profil sain (un dégât qui ne s'applique plus
    // à un profil déjà abîmé est ignoré).
    const junk = () => T.of([null, 5, 'x', [], {}, true, 1.5, -3, NaN]);
    const damages = [
      (p) => { delete p[T.of(Object.keys(p))]; },
      (p) => { p[T.of(Object.keys(p))] = junk(); },
      (p) => { p.checkpoints = [1, 7, 13, 19, 37, 19, 667, 0, 1.5, '37', null, 55, 649, 631, 73]; },
      (p) => { p.bestFloor = T.of([0, 667, 12.5, 300, '5', 666]); },
      (p) => { p.souls = T.of([-1, 12.7, Infinity, '40', 1e12, 0.2]); p.gold = T.of([-1, 99.99, NaN, '40', 7]); },
      (p) => { p.unlocked.classes = ['bourreau', 'x', 5, 'bourreau', 'chasseresse', null]; },
      (p) => { p.unlocked.weapons = [...kinds.weapons, 'zzz', 'lame']; p.unlocked.skills = ['volee', 'volee', 7]; p.unlocked.gadgets = 'totem'; },
      (p) => { p.unlocked = T.of(['abc', null, [], {}]); },
      (p) => { p.upgrades = { vitalite: 9, celerite: 2, inconnu: 1, ferocite: 1.5, arsenal: '1', fortune: 0, avidite: -1 }; },
      (p) => { p.loadout = T.of([{ classId: 'chasseresse', skillId: 'brasier', gadgetId: 'totem' }, { classId: 'bourreau' }, 'x', { classId: 'zzz', skillId: 'lance', gadgetId: 'cri' }, {}]); },
      (p) => { p.equipment = { arme: item(), armure: item(), talisman: item() }; },
      (p) => { p.items = { arme: weapon(), armure: clone(T.of(pool.filter((it) => it.slot === 'armure'))) }; delete p.equipment; },
      (p) => { p.equipment = T.of([null, 'x', { arme: 5, armure: { slot: 'armure' }, talisman: { slot: 'talisman', affixes: [], name: 'nu', base: {} } }]); },
      (p) => { p.stash = many(T.of([3, 12, 30]), (i) => (i % 7 === 3 ? junk() : i % 5 === 1 ? { slot: 'arme', affixes: 'non' } : item())); },
      (p) => { p.stash = T.of([null, 'x', {}]); },
      (p) => { p.itemSeq = T.of([0, 2.5, 1e10, 77, '4', 1e9]); },
      (p) => { p.guardians = { gardien: 3, cerbere: -1, zz: 2, minos: 1.5, colosse: 1e6 }; },
      (p) => { p.stats = { runs: 5, deaths: -2, kills: 'x', guardianKills: 3, extra: 9 }; },
      (p) => { p.loadout.classId = T.of(kinds.classes); p.unlocked.classes = [...kinds.classes]; p.equipment.arme = weapon(); },
    ];
    const sanitizeCases = [null, 5, 'x', [], {}, true].map((raw) => ({ args: [raw, null], out: P.sanitizeProfile(clone(raw), base) }));
    for (let i = 0; i < 150; i++) {
      const over = T.of(tunings);
      const t = createTuning(over);
      const raw = P.newProfile(t);
      raw.souls = T.int(0, 900);
      raw.gold = T.int(0, 900);
      raw.checkpoints = [1, 19, 37];
      raw.bestFloor = T.int(1, 666);
      const stashed = T.int(0, 4);
      for (let k = 0; k < stashed; k++) P.stashLoot(raw, item());
      const hits = T.int(1, 4);
      for (let k = 0; k < hits; k++) {
        try {
          T.of(damages)(raw);
        } catch {
          // dégât inapplicable à ce profil déjà abîmé
        }
      }
      sanitizeCases.push({ args: [clone(raw), over], out: P.sanitizeProfile(clone(raw), t) });
    }
    groups.sanitizeProfile = sanitizeCases;

    // Fonctions simples.
    groups.createProfile = tunings.map((o) => ({ args: [o], out: P.createProfile(createTuning(o)) }));
    groups.newProfile = tunings.map((o) => ({ args: [o], out: P.newProfile(createTuning(o)) }));
    groups.grantClassStarters = tunings.flatMap((o) => [...kinds.classes, 'zzz'].map((c) => {
      const t = createTuning(o);
      const p = P.createProfile(t);
      const before = clone(p);
      P.grantClassStarters(p, t, c);
      return { args: [before, o, c], out: p };
    }));
    const things = [...pool.slice(0, 12), null, 5, 'x', [], {}, { slot: 'arme' }, { slot: 'bague', affixes: [], name: 'n', base: {} }, { slot: 'arme', affixes: [], name: 5, base: {} }, { slot: 'arme', affixes: [], name: 'n', base: [] }, { slot: 'arme', affixes: {}, name: 'n', base: {} }, { slot: 'talisman', affixes: [], name: '', base: {} }];
    groups.isItem = things.map((v) => ({ args: [v], out: P.isItem(v) }));
    groups.ensureUid = many(12, (i) => {
      const p = { itemSeq: T.int(1, 400) };
      const it = [{}, { uid: 'i7' }, { uid: '' }, { uid: 0 }, { uid: null }, { uid: 'x', slot: 'arme' }][i % 6];
      const args = [clone(p), clone(it)];
      const ret = P.ensureUid(p, it);
      return { args, out: { ret, itemSeq: p.itemSeq, item: clone(it) } };
    });
    groups.fixLoadout = many(60, () => {
      const over = T.of(tunings);
      const t = createTuning(over);
      const p = P.newProfile(t);
      p.unlocked.classes = kinds.classes.filter(() => T.chance(0.7));
      p.unlocked.skills = kinds.skills.filter(() => T.chance(0.5));
      p.unlocked.gadgets = kinds.gadgets.filter(() => T.chance(0.5));
      p.loadout = { classId: T.of([...kinds.classes, 'zzz']), skillId: T.of([...kinds.skills, 'zzz']), gadgetId: T.of([...kinds.gadgets, 'zzz']) };
      if (T.chance(0.3)) delete p.loadout.skillId;
      p.equipment.arme = T.chance(0.8) ? weapon() : null;
      if (p.equipment.arme && T.chance(0.2)) delete p.equipment.arme.weaponType;
      const stashed = T.int(0, 6);
      for (let k = 0; k < stashed; k++) P.stashLoot(p, item());
      const before = clone(p);
      P.fixLoadout(p, t);
      return { args: [before, over], out: p };
    });
    groups.unlockCost = tunings.slice(3).flatMap((o) => [...Object.keys(kinds), 'inconnu', null].flatMap((kind) => [...(kinds[kind] ?? ['lame']), 'zzz'].map((id) => ({ args: [o, kind, id], out: P.unlockCost(createTuning(o), kind, id) }))));
    groups.starterWeapon = tunings.slice(3).flatMap((o) => kinds.weapons.map((w) => ({ args: [o, w], out: P.starterWeapon(createTuning(o), w) })));
    groups.upgradeCost = tunings.slice(3).flatMap((o) => [...upgradeIds, 'zzz'].flatMap((id) => [0, 1, 2, 3, 4, 5, 6, 1.5, -1].map((lv) => ({ args: [o, id, lv], out: P.upgradeCost(createTuning(o), id, lv) }))));
    groups.salvageSouls = tunings.slice(3).flatMap((o) => [...ITEM_RARITIES, 'inconnue', null].map((rarity) => ({ args: [o, { rarity }], out: P.salvageSouls(createTuning(o), { rarity }) })));
    return Object.entries(groups).map(([fn, cases]) => ({ fn, cases }));
  },

  async sections() {
    const Se = await import(`${SIM}sections.mjs`);
    const { createTuning } = await import(`${SIM}config.mjs`);
    const T = tools(19);
    const base = createTuning();
    const others = [
      { circles: [] },
      { circles: null },
      { section: { eliteAt: [4, 9] } },
      { section: { halte: { fixed: null, doors: 3 } } },
      { floors: { sectionLength: 6, total: 100, circleLength: 24 } },
      { enemies: { brute: null, necromancer: null } },
      { section: { rhythms: [base.section.rhythms[1]] } },
      { section: { doorWeights: { rest: 5, boon: 0 } } },
      { encounter: { strayEliteFrom: 40, costRef: 2 } },
      { section: { treasure: { from: 17, to: 17 } } },
      { section: { treasure: { from: 16, to: 17 } } },
    ];
    const seed = () => (T.chance(0.3) ? T.of(SEEDS) : T.seed32());
    const rewards = ['boon', 'loot', 'gold', 'heal', 'elite', 'shop', 'event', 'treasure', 'rest', 'boss', 'zzz'];
    const door = (i) => {
      if (i % 9 === 0) return null;
      const d = {};
      if (i % 11 !== 0) d.reward = rewards[i % rewards.length];
      if (i % 3 !== 0) d.family = T.of(['colere', 'paresse', 'envie']);
      return d;
    };
    const call = (fn, over, ...rest) => ({ args: [over, ...rest], out: Se[fn](createTuning(over), ...rest) });
    return [
      { fn: 'sectionCount', cases: [null, ...others, { floors: { total: 667 } }, { floors: { total: 1 } }].map((o) => call('sectionCount', o)) },
      { fn: 'circleTheme', cases: [null, others[0], others[1]].flatMap((o) => many(14, (i) => call('circleTheme', o, i - 1))) },
      {
        fn: 'sectionPlan',
        cases: [
          ...[1, 0xdeadbeef, 20261001].flatMap((sd) => many(37, (i) => call('sectionPlan', null, sd, i + 1))),
          ...SEEDS.map((sd, i) => call('sectionPlan', null, sd, [0, 2, 37, 38, 5.9, -4, 11, 20, 29, 36][i])),
          ...others.flatMap((o) => many(3, () => call('sectionPlan', o, seed(), T.int(1, 37)))),
        ],
      },
      { fn: 'floorSlot', cases: many(120, (i) => call('floorSlot', i % 4 === 0 ? T.of(others) : null, seed(), T.int(1, 666))) },
      {
        fn: 'composeFloor',
        cases: [
          ...many(666, (i) => call('composeFloor', null, 7, i + 1, door(i))),
          ...many(300, (i) => call('composeFloor', i % 3 === 0 ? T.of(others) : null, seed(), T.of([T.int(1, 666), T.int(1, 666), T.int(1, 666), 0, 700, 'abc', 18, 648, 666]), door(T.int(0, 200)))),
        ],
      },
    ];
  },
};

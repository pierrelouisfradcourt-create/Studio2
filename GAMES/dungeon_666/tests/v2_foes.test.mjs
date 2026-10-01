// Lot « BESTIAIRE » (V2) — tests NEUFS du bestiaire : archétype de ZONE (Pyromancienne, flaques
// persistantes), INVOCATEUR (Nécromancien, plafond d'invocations), champions V2 (vampirique,
// bouclier, invocateur), lisibilité (télégraphe avant tout dégât, aucun dégât de contact),
// déterminisme et invariants avec le nouveau bestiaire en jeu.
//
// Des lois plutôt que des valeurs : les seuils et durées lisent game.tuning. Lancer :
//   node --test tests/v2_foes.test.mjs

import test from 'node:test';
import assert from 'node:assert/strict';
import { createGame, stepGame, emptyInput, applyCommand, stateHash } from '../src/sim/game.mjs';
import { createEnemy } from '../src/sim/enemies.mjs';
import { damageEnemy, killEnemy } from '../src/sim/combat.mjs';
import { spawnPyre, pyreSpan } from '../src/sim/foe_pyromancer.mjs';
import { pickEliteMod } from '../src/sim/foe_elites.mjs';
import { summonedCount } from '../src/sim/ai_common.mjs';
import { EXTRA_ENEMIES, EXTRA_ROSTER } from '../src/sim/foe_data.mjs';
import { pointBlocked } from '../src/sim/physics.mjs';
import { POLICIES, resolveChoice } from '../tools/bots.mjs';
import { ELITE_COLORS, ELITE_NAMES } from '../src/render/palette.mjs';
import { FOE_ART, FOE_BODY } from '../src/render/art_foes.mjs';
import { createAudio } from '../src/audio/sfx.mjs';

const DT = 1 / 60;
const SEC = 60; // pas par seconde
const MIN_TELEGRAPH = 0.4; // s : un coup doit être précédé d'un télégraphe rouge au moins aussi long
const TELEGRAPH_LOOKBACK = 4; // s : fenêtre où chercher ce télégraphe avant le coup
const FLOOR_SEEDS = 60;
const SECTION_LAST_COMBAT = 17;
const EXPECTED_KINDS = ['imp', 'brute', 'archer', 'charger', 'exploder', 'pyromancer', 'necromancer'];
const NEW_MODS = ['vampirique', 'bouclier', 'invocateur'];
const BIG_HP = 5000;
const HIGH_FLOOR = 600;
const INVARIANT_SEEDS = [1, 2, 3];
const INVARIANT_START = 8;
const INVARIANT_STEPS = 4000;
const GEOM_EPS = 0.5;
const FAST_RECHARGE = 0.3; // s : recharge d'invocateur volontairement courte (test du plafond)

// ---------------------------------------------------------------- outillage

/**
 * Salle vidée et « hors combat » (jamais nettoyée : les flaques ne s'éteignent pas d'office),
 * héros immobile au centre bas. Les ennemis du test sont posés à la main.
 */
function quietGame(opts = {}) {
  const game = createGame({ seed: opts.seed ?? 1, godMode: !!opts.godMode, tuning: opts.tuning, startFloor: opts.startFloor });
  game.enemies.length = 0;
  game.spawns.length = 0;
  game.hazards.length = 0;
  game.projectiles.length = 0;
  game.room.waves = [];
  game.room.kind = 'event';
  game.room.obstacles = [];
  game.events.length = 0;
  const p = game.player;
  p.x = game.room.w / 2;
  p.y = game.room.h * 0.62;
  if (opts.bigHp) {
    p.maxHp = BIG_HP;
    p.hp = BIG_HP;
  }
  return game;
}

/** Avance d'un pas ; rend les événements de l'image (vidés de la partie). */
function step(game, input = emptyInput()) {
  stepGame(game, input);
  const ev = game.events.slice();
  game.events.length = 0;
  return ev;
}

function stepUntil(game, cond, maxSteps, input) {
  const all = [];
  for (let i = 0; i < maxSteps; i++) {
    if (cond(game)) return { ok: true, events: all };
    all.push(...step(game, input));
  }
  return { ok: cond(game), events: all };
}

function spawnFoe(game, kind, dx, dy, opts = {}) {
  const p = game.player;
  const e = createEnemy(game, kind, p.x + dx, p.y + dy, { spawnT: 0, ...opts });
  game.events.length = 0;
  return e;
}

function dist(a, b) {
  return Math.hypot(a.x - b.x, a.y - b.y);
}

/**
 * Le héros marche vers l'ennemi le plus proche jusqu'à `stopAt` u, sans frapper (un joueur qui
 * s'approche). Immobile, il ne serait jamais pris par un diablotin : celui-ci tourne autour à
 * distance tant que le héros ne vient pas à lui (comportement d'origine de enemies.mjs).
 */
function approachInput(game, stopAt) {
  const p = game.player;
  const input = emptyInput();
  let best = null;
  for (const e of game.enemies) if (!e.dead && (!best || dist(p, e) < dist(p, best))) best = e;
  if (best && dist(p, best) > stopAt) {
    const d = dist(p, best);
    input.moveX = (best.x - p.x) / d;
    input.moveY = (best.y - p.y) / d;
  }
  return input;
}

const APPROACH_STOP = 36; // u entre les centres : au contact
const MELEE = new Set(['imp', 'brute', 'charger', 'exploder']);

/** Un télégraphe ROUGE (qui fait mal) est-il visible à l'écran ? */
function redTelegraphVisible(game) {
  for (const e of game.enemies) if (!e.dead && e.tele && !e.tele.harmless) return true;
  for (const h of game.hazards) if (!h.done && h.hitsPlayer && !h.burning) return true;
  return false;
}

// ---------------------------------------------------------------- présence dans le jeu

test('bestiaire : les 7 archétypes apparaissent ; la zone puis l\'invocateur entrent progressivement dans la 1re section', () => {
  const first = {};
  for (let seed = 1; seed <= FLOOR_SEEDS; seed++) {
    for (let floor = 1; floor <= SECTION_LAST_COMBAT; floor++) {
      const g = createGame({ seed, startFloor: floor });
      for (const wave of g.room.waves) for (const s of wave) first[s.kind] = Math.min(first[s.kind] ?? Infinity, floor);
    }
  }
  for (const kind of EXPECTED_KINDS) assert.ok(Number.isFinite(first[kind]), `archétype jamais tiré dans la 1re section : ${kind}`);
  for (const r of EXTRA_ROSTER) {
    assert.ok(first[r.kind] >= r.minIndex, `${r.kind} apparaît à l'étage ${first[r.kind]}, avant son minIndex ${r.minIndex}`);
  }
  // Demande : zone vers l'étage 5-7, invocateur vers 8-10.
  assert.ok(first.pyromancer >= 5 && first.pyromancer <= 7, `zone introduite à l'étage ${first.pyromancer}`);
  assert.ok(first.necromancer >= 8 && first.necromancer <= 10, `invocateur introduit à l'étage ${first.necromancer}`);
  // Sections suivantes : tout le bestiaire dès le 1er étage.
  const sec2 = new Set();
  for (let seed = 1; seed <= FLOOR_SEEDS; seed++) for (const w of createGame({ seed, startFloor: 19 }).room.waves) for (const s of w) sec2.add(s.kind);
  assert.ok(sec2.has('pyromancer') && sec2.has('necromancer'), `section 2, étage 1 : ${[...sec2].join(', ')}`);
});

test('dessin et noms : chaque archétype ajouté a sa silhouette et sa couleur ; chaque modificateur a sa couleur et son nom', () => {
  const g = createGame();
  for (const kind of Object.keys(EXTRA_ENEMIES)) {
    assert.equal(typeof FOE_ART[kind], 'function', `pas de dessin pour ${kind}`);
    assert.ok(FOE_BODY[kind], `pas de couleur de corps pour ${kind}`);
    assert.ok(g.tuning.enemies[kind].name, `pas de nom pour ${kind}`);
  }
  for (const mod of Object.keys(g.tuning.elite.mods)) {
    assert.ok(ELITE_COLORS[mod], `pas de couleur d'aura pour l'élite ${mod}`);
    assert.ok(ELITE_NAMES[mod], `pas de nom affiché pour l'élite ${mod}`);
  }
});

// ---------------------------------------------------------------- lisibilité commune

test('chaque archétype, posé SUR le héros : tout dégât est précédé d\'un télégraphe rouge visible — aucun dégât de contact', () => {
  for (const kind of EXPECTED_KINDS) {
    const g = quietGame({ bigHp: true });
    spawnFoe(g, kind, 4, -4);
    const visible = []; // historique : télégraphe rouge visible à chaque pas
    let hurts = 0;
    for (let i = 0; i < 10 * SEC; i++) {
      visible.push(redTelegraphVisible(g));
      for (const ev of step(g, MELEE.has(kind) ? approachInput(g, APPROACH_STOP) : emptyInput())) {
        if (ev.type !== 'playerHurt') continue;
        hurts++;
        // Plus longue suite continue de télégraphe visible dans la fenêtre précédant le coup.
        const from = Math.max(0, visible.length - TELEGRAPH_LOOKBACK * SEC);
        let run = 0;
        let best = 0;
        for (let k = from; k < visible.length; k++) {
          run = visible[k] ? run + 1 : 0;
          best = Math.max(best, run);
        }
        assert.ok(best * DT >= MIN_TELEGRAPH, `${kind} : coup (${ev.source}) sans télégraphe rouge d'au moins ${MIN_TELEGRAPH} s (vu ${(best * DT).toFixed(2)} s)`);
      }
    }
    if (kind !== 'necromancer' && kind !== 'exploder') assert.ok(hurts > 0, `${kind} : témoin — il doit avoir frappé en 10 s`);
  }
});

test('nécromancien : il ne frappe jamais lui-même (sans invocations, 10 s collé au héros = 0 dégât)', () => {
  const g = quietGame({ bigHp: true, tuning: { enemies: { necromancer: { maxMinions: 0 } } } });
  spawnFoe(g, 'necromancer', 2, -2);
  const hp = g.player.hp;
  for (let i = 0; i < 10 * SEC; i++) step(g);
  assert.equal(g.player.hp, hp);
  assert.equal(summonedCount(g), 0);
});

// ---------------------------------------------------------------- Pyromancienne (zone)

test('Pyromancienne : cercles de feu télégraphiés sur et autour du héros ; aucun dégât avant l\'allumage', () => {
  const g = quietGame({ bigHp: true });
  const def = g.tuning.enemies.pyromancer;
  spawnFoe(g, 'pyromancer', 0, -def.preferredDist);
  const seen = new Map(); // id de zone -> pas d'apparition
  const hp0 = g.player.hp;
  let attackEv = false;
  let fired = false;
  for (let i = 0; i < 8 * SEC && !fired; i++) {
    for (const ev of step(g)) {
      if (ev.type === 'enemyAttack' && ev.enemy === 'pyromancer') attackEv = true;
      if (ev.type === 'hazardFire' && ev.kind === 'pyre') fired = true;
      if (ev.type === 'playerHurt') {
        assert.equal(ev.source, 'pyre');
        assert.ok(g.hazards.some((h) => h.kind === 'pyre' && h.burning), 'dégât reçu sans cercle allumé');
      }
    }
    for (const h of g.hazards) if (h.kind === 'pyre' && !seen.has(h.id)) seen.set(h.id, g.tick);
    if (!fired) assert.equal(g.player.hp, hp0, 'aucun dégât avant le premier allumage');
  }
  assert.ok(attackEv, 'son / événement d\'attaque à l\'apparition des cercles');
  assert.ok(fired, 'un cercle doit s\'allumer');
  const pyres = g.hazards.filter((h) => h.kind === 'pyre');
  assert.equal(pyres.length, def.pyre.count, 'nombre de cercles d\'une incantation');
  for (const h of pyres) {
    assert.ok(h.delay >= def.pyre.delay, `télégraphe ${h.delay} s`);
    assert.ok(h.delay >= MIN_TELEGRAPH);
    assert.ok(h.hitsPlayer && !h.hitsEnemies);
    assert.ok(h.sourceId > 0, 'le cercle est lié à sa lanceuse (sa mort l\'annule)');
  }
  // Un cercle SUR le héros (là où il était à l'incantation : il n'a pas bougé), les autres autour.
  const onHero = pyres.filter((h) => Math.hypot(h.x - g.player.x, h.y - g.player.y) < 1);
  assert.equal(onHero.length, 1, 'un cercle centré sur le héros');
});

test('Pyromancienne : télégraphe identique à l\'étage 1 et à l\'étage 600 (la difficulté ne le raccourcit jamais)', () => {
  const delays = [1, HIGH_FLOOR].map((floor) => {
    const g = quietGame({ startFloor: floor, bigHp: true });
    spawnFoe(g, 'pyromancer', 0, -300);
    const r = stepUntil(g, (gg) => gg.hazards.some((h) => h.kind === 'pyre'), 8 * SEC);
    assert.ok(r.ok, `étage ${floor} : la Pyromancienne doit incanter`);
    return g.hazards.filter((h) => h.kind === 'pyre').map((h) => h.delay).sort().join(',');
  });
  assert.equal(delays[0], delays[1]);
});

test('Pyromancienne : la tuer (ou l\'étourdir) pendant le télégraphe ANNULE ses cercles — ni dégât ni flaque', () => {
  for (const how of ['kill', 'stun']) {
    const g = quietGame({ bigHp: true });
    const e = spawnFoe(g, 'pyromancer', 0, -300);
    const r = stepUntil(g, (gg) => gg.hazards.some((h) => h.kind === 'pyre'), 8 * SEC);
    assert.ok(r.ok);
    if (how === 'kill') killEnemy(g, e, { kind: 'melee' });
    else damageEnemy(g, e, { kind: 'wall', amount: 1, stun: 2, canCrit: false });
    const hp = g.player.hp;
    let cancels = 0;
    for (let i = 0; i < 2 * SEC; i++) {
      for (const ev of step(g)) {
        assert.ok(!(ev.type === 'hazardFire' && ev.kind === 'pyre'), `${how} : un cercle s'est allumé`);
        if (ev.type === 'hazardCancel') cancels++;
      }
    }
    assert.equal(g.player.hp, hp, `${how} : dégâts reçus`);
    assert.ok(cancels >= 1, `${how} : annulation visible (hazardCancel)`);
    assert.ok(!g.hazards.some((h) => h.burning), `${how} : flaque restée au sol`);
  }
});

// ---------------------------------------------------------------- flaque persistante

function puddleRun(offset) {
  const g = quietGame({ bigHp: true });
  const def = g.tuning.enemies.pyromancer;
  const p = g.player;
  const h = spawnPyre(g, p.x + offset, p.y, def, null, def.pyre.delay);
  // Temps de JEU (game.time) : le gel d'impact fige la scène sans faire avancer la flaque.
  const hurts = [];
  let ignitedAt = -1;
  const seenAt = g.time;
  const total = Math.ceil((def.pyre.delay + def.pyre.linger + 2) * SEC);
  let lastBurning = -1;
  for (let i = 0; i < total; i++) {
    for (const ev of step(g)) {
      if (ev.type === 'hazardFire' && ev.id === h.id) ignitedAt = g.time;
      if (ev.type === 'playerHurt') hurts.push({ time: g.time, ev, inside: Math.hypot(p.x - h.x, p.y - h.y) < h.r + p.r });
    }
    if (h.burning && !h.done) lastBurning = g.time;
  }
  return { g, h, def, hurts, ignitedAt, seenAt, lastBurning };
}

test('flaque : allumée SEULEMENT après son télégraphe, elle persiste `linger` s puis s\'éteint', () => {
  const { h, def, ignitedAt, seenAt, lastBurning, g } = puddleRun(0);
  assert.ok(ignitedAt > 0, 'la flaque doit s\'allumer');
  assert.ok(ignitedAt - seenAt >= def.pyre.delay - DT, `allumée ${(ignitedAt - seenAt).toFixed(2)} s après son apparition (télégraphe ${def.pyre.delay} s)`);
  const burned = lastBurning - ignitedAt;
  assert.ok(Math.abs(burned - def.pyre.linger) <= 2 * DT, `durée de la flaque ${burned.toFixed(2)} s (attendu ${def.pyre.linger})`);
  assert.ok(h.done && !g.hazards.includes(h), 'la flaque éteinte quitte la liste des zones');
});

test('flaque : dégâts par tick SEULEMENT à l\'intérieur (héros dedans : touché plusieurs fois ; juste dehors : jamais)', () => {
  const inside = puddleRun(0);
  const pyreHurts = inside.hurts.filter((x) => x.ev.source === 'pyre');
  assert.ok(pyreHurts.length >= 2, `dedans : impact puis brûlure attendus (${pyreHurts.length} coups)`);
  for (const x of pyreHurts) {
    assert.ok(x.inside, 'dégât de flaque reçu hors de la flaque');
    assert.ok(x.time >= inside.ignitedAt, 'dégât de flaque avant son allumage');
  }
  // Après l'impact : des ticks espacés d'au moins tickEvery.
  const ticks = pyreHurts.slice(1);
  for (let i = 1; i < ticks.length; i++) assert.ok(ticks[i].time - ticks[i - 1].time >= inside.def.pyre.tickEvery - DT);
  const p = inside.g.player;
  const outside = puddleRun(inside.h.r + p.r + 2);
  assert.equal(outside.hurts.length, 0, 'juste hors de la flaque : aucun dégât');
});

test('flaque : la salle nettoyée l\'éteint (la récompense se ramasse sans brûler)', () => {
  const g = quietGame({ bigHp: true });
  const def = g.tuning.enemies.pyromancer;
  const h = spawnPyre(g, g.player.x + 300, g.player.y, def, null, def.pyre.delay);
  stepUntil(g, () => h.burning, 3 * SEC);
  assert.ok(h.burning);
  g.room.cleared = true;
  step(g);
  assert.ok(h.done);
});

test('bot skilled : une flaque allumée sur son chemin, il la contourne sans jamais y entrer', () => {
  const g = quietGame({ bigHp: true });
  const def = g.tuning.enemies.pyromancer;
  const p = g.player;
  // Hors combat, le bot veut aller au centre de la salle : la flaque y brûle.
  p.x = g.room.w / 2;
  p.y = g.room.h / 2 + 250;
  const h = spawnPyre(g, g.room.w / 2, g.room.h / 2, def, null, 0);
  step(g); // allumage (le héros est loin : aucun dégât)
  assert.ok(h.burning);
  const mem = {};
  let inside = 0;
  let closest = Infinity;
  for (let i = 0; i < def.pyre.linger * SEC && !h.done; i++) {
    step(g, POLICIES.skilled(g, mem));
    const d = Math.hypot(p.x - h.x, p.y - h.y);
    closest = Math.min(closest, d);
    if (d < h.r + p.r) inside++;
  }
  assert.equal(inside, 0, 'le bot est entré dans la flaque');
  assert.ok(closest < h.r + p.r + 60, `témoin : le bot doit s'être approché du bord (au plus près ${closest.toFixed(0)} u)`);
});

test('bot skilled : pris par un allumage, il ne reprend plus aucune brûlure de cette flaque', () => {
  const g = quietGame({ bigHp: true });
  const def = g.tuning.enemies.pyromancer;
  const p = g.player;
  p.x = g.room.w / 2;
  p.y = g.room.h / 2;
  const h = spawnPyre(g, p.x, p.y, def, null, 0);
  const impact = step(g).filter((ev) => ev.type === 'playerHurt');
  assert.equal(impact.length, 1, 'l\'allumage frappe le héros dedans');
  const mem = {};
  for (let i = 0; i < def.pyre.linger * SEC && !h.done; i++) {
    for (const ev of step(g, POLICIES.skilled(g, mem))) assert.notEqual(ev.type, 'playerHurt', 'brûlure reprise : le bot est resté dans la flaque');
  }
});

// ---------------------------------------------------------------- Nécromancien (invocateur)

test('Nécromancien : canalisation visible et INOFFENSIVE, cercles d\'invocation, plafond d\'invocations vivantes', () => {
  // Recharge très courte : sans plafond, il dépasserait largement maxMinions en 25 s.
  const g = quietGame({ godMode: true, tuning: { enemies: { necromancer: { cooldown: FAST_RECHARGE } } } });
  const def = g.tuning.enemies.necromancer;
  const e = spawnFoe(g, 'necromancer', 0, -380);
  let maxCount = 0;
  let channelSeen = false;
  let warns = 0;
  let summoned = 0;
  for (let i = 0; i < 25 * SEC; i++) {
    for (const ev of step(g)) {
      if (ev.type === 'spawnWarn') warns++;
      if (ev.type === 'spawn' && ev.enemy === def.minionKind) summoned++;
    }
    if (e.state === 'channel') {
      channelSeen = true;
      assert.ok(e.tele && e.tele.harmless === true, 'la canalisation est une alerte inoffensive (violette)');
    }
    const n = summonedCount(g);
    maxCount = Math.max(maxCount, n);
    assert.ok(n <= def.maxMinions, `plafond dépassé : ${n} > ${def.maxMinions}`);
    for (const o of g.enemies) if (o.summoned) assert.equal(o.kind, def.minionKind);
    // Les invocations meurent en route : on les abat pour vérifier qu'il en rappelle d'autres.
    if (i === 12 * SEC) for (const o of g.enemies) if (o.summoned) killEnemy(g, o, { kind: 'melee' });
  }
  assert.ok(channelSeen, 'canalisation observée');
  assert.equal(maxCount, def.maxMinions, 'il remplit son plafond');
  assert.ok(warns >= summoned && summoned > def.maxMinions, `cercles ${warns}, invocations ${summoned} (il en rappelle après leur mort)`);
  // Les invocations ne rapportent ni or ni Âmes (pas de ferme).
  const g2 = quietGame({ godMode: true });
  const imp = createEnemy(g2, 'imp', 100, 100, { spawnT: 0, summoned: true });
  const souls = g2.meta.souls;
  killEnemy(g2, imp, { kind: 'melee' });
  assert.equal(g2.meta.souls, souls);
  assert.equal(g2.pickups.length, 0);
});

test('Nécromancien : le tuer pendant la canalisation l\'annule — aucun cercle ne s\'ouvre ; l\'étourdir aussi', () => {
  for (const how of ['kill', 'stun']) {
    const g = quietGame({ godMode: true });
    const def = g.tuning.enemies.necromancer;
    const e = spawnFoe(g, 'necromancer', 0, -380);
    const r = stepUntil(g, () => e.state === 'channel' && e.stateTime > def.channel * 0.5, 10 * SEC);
    assert.ok(r.ok, 'il doit canaliser');
    const stun = 1.5;
    if (how === 'kill') killEnemy(g, e, { kind: 'melee' });
    else damageEnemy(g, e, { kind: 'wall', amount: 1, stun, canCrit: false });
    // Fenêtre : le reste de la canalisation + l'alerte des cercles (et l'étourdissement).
    const window = (how === 'stun' ? stun : 0) + def.channel;
    for (let i = 0; i < window * SEC; i++) {
      for (const ev of step(g)) assert.notEqual(ev.type, 'spawnWarn', `${how} : un cercle d'invocation s'est ouvert`);
    }
    assert.equal(g.spawns.length, 0);
    assert.equal(summonedCount(g), 0);
  }
});

// ---------------------------------------------------------------- champions V2

test('élite bouclier : anneau d\'annonce puis bulle d\'immunité (coups sans effet), puis vulnérable de nouveau', () => {
  const g = quietGame({ godMode: true });
  const m = g.tuning.elite.mods.bouclier;
  const e = spawnFoe(g, 'brute', 0, -500, { elite: 'bouclier' });
  const hit = () => damageEnemy(g, e, { kind: 'wall', amount: 1, canCrit: false });
  assert.ok(hit() > 0, 'vulnérable au départ');
  let warnTicks = 0;
  const r = stepUntil(g, () => {
    if (e.modPhase === 'warn') warnTicks++;
    return e.invuln > 0;
  }, 10 * SEC);
  assert.ok(r.ok, 'la bulle doit se lever');
  assert.ok(warnTicks * DT >= m.warn - 2 * DT, `annonce trop courte : ${(warnTicks * DT).toFixed(2)} s`);
  const hp = e.hp;
  assert.equal(hit(), 0, 'immunisé sous la bulle');
  assert.equal(e.hp, hp);
  const r2 = stepUntil(g, () => !(e.invuln > 0), (m.duration + 1) * SEC);
  assert.ok(r2.ok, 'la bulle retombe');
  assert.ok(hit() > 0, 'vulnérable de nouveau');
});

function vampireCase(kind, dx, dy) {
  const g = quietGame({ bigHp: true });
  const e = spawnFoe(g, kind, dx, dy, { elite: 'vampirique' });
  e.hp = Math.floor(e.maxHp / 2);
  for (let i = 0; i < 12 * SEC; i++) {
    const before = e.hp;
    for (const ev of step(g, MELEE.has(kind) ? approachInput(g, APPROACH_STOP) : emptyInput())) {
      if (ev.type !== 'playerHurt') continue;
      const m = g.tuning.elite.mods.vampirique;
      assert.equal(e.hp, Math.min(e.maxHp, before + Math.round(ev.amount * m.leech)), `${kind} : soin = leech × dégâts infligés`);
      assert.ok(e.leechFlash > 0, `${kind} : drain visible`);
      return true;
    }
  }
  return false;
}

test('élite vampirique : se soigne de ce qu\'il inflige — coup direct, zone et projectile', () => {
  assert.ok(vampireCase('imp', 30, 0), 'diablotin (coup direct)');
  assert.ok(vampireCase('brute', 40, 0), 'brute (zone)');
  assert.ok(vampireCase('archer', 0, -260), 'archer (projectile)');
  // Un autre modificateur ne soigne pas.
  const g = quietGame({ bigHp: true });
  const e = spawnFoe(g, 'imp', 30, 0, { elite: 'rapide' });
  e.hp = 10;
  for (let i = 0; i < 6 * SEC; i++) step(g);
  assert.ok(e.hp <= 10);
});

test('élite invocateur : canalise (alerte inoffensive), invoque sous son plafond ; tué en canalisant, rien ne s\'ouvre', () => {
  const g = quietGame({ godMode: true });
  const m = g.tuning.elite.mods.invocateur;
  const e = spawnFoe(g, 'imp', 0, -500, { elite: 'invocateur' });
  let channel = false;
  let sound = false;
  for (let i = 0; i < 20 * SEC; i++) {
    for (const ev of step(g)) if (ev.type === 'enemyAttack' && ev.enemy === 'summon') sound = true;
    if (e.modPhase === 'channel') channel = true;
    assert.ok(summonedCount(g) <= m.maxMinions);
  }
  assert.ok(channel && sound, 'canalisation visible et audible');
  assert.equal(summonedCount(g), m.maxMinions, 'plafond atteint');
  // Tué (ou étourdi) pendant sa canalisation : aucun cercle.
  for (const how of ['kill', 'stun']) {
    const g2 = quietGame({ godMode: true });
    const e2 = spawnFoe(g2, 'archer', 0, -500, { elite: 'invocateur' });
    assert.ok(stepUntil(g2, () => e2.modPhase === 'channel', 10 * SEC).ok);
    const stun = m.channel + 0.5;
    if (how === 'kill') killEnemy(g2, e2, { kind: 'melee' });
    else damageEnemy(g2, e2, { kind: 'wall', amount: 1, stun, canCrit: false });
    for (let i = 0; i < (m.channel + (how === 'stun' ? stun : 1)) * SEC; i++) {
      for (const ev of step(g2)) assert.notEqual(ev.type, 'spawnWarn', `${how} : un cercle s'est ouvert`);
    }
    assert.equal(summonedCount(g2), 0, how);
  }
});

test('modificateurs : tirage avec exclusions et introduction progressive ; les premiers étages gardent le tirage d\'origine', () => {
  const g = createGame({ seed: 9 });
  const draw = (kind, info, n = 600) => {
    const s = new Set();
    for (let i = 0; i < n; i++) s.add(pickEliteMod(g, kind, info));
    return s;
  };
  const late = draw('imp', { section: 2, indexInSection: 1 });
  for (const m of Object.keys(g.tuning.elite.mods)) assert.ok(late.has(m), `section 2 : ${m} jamais tiré`);
  const early = draw('imp', { section: 1, indexInSection: 3 });
  assert.deepEqual([...early].sort(), ['ardent', 'blinde', 'rapide'], 'étages 1-5 : seulement les modificateurs d\'origine');
  for (const [m, def] of Object.entries(g.tuning.elite.mods)) {
    for (const kind of def.excludeKinds ?? []) assert.ok(!draw(kind, { section: 3, indexInSection: 10 }).has(m), `${kind} ne doit jamais être ${m}`);
  }
  // Et en vrai : les nouveaux champions sortent dans les vagues planifiées.
  const seen = new Set();
  for (let seed = 1; seed <= FLOOR_SEEDS * 2; seed++) {
    for (const floor of [7, 11, 13, 20, 25]) {
      for (const w of createGame({ seed, startFloor: floor }).room.waves) for (const s of w) if (s.elite) seen.add(s.elite);
    }
  }
  for (const m of NEW_MODS) assert.ok(seen.has(m), `champion ${m} jamais planifié dans une vague`);
});

// ---------------------------------------------------------------- déterminisme et invariants

function botRun(seed, startFloor, steps, check) {
  const g = createGame({ seed, startFloor });
  const mem = {};
  for (let i = 0; i < steps; i++) {
    for (let k = 0; k < 8 && g.mode === 'choice'; k++) resolveChoice(g, 'skilled');
    if (g.mode === 'dead') applyCommand(g, { type: 'respawn' });
    if (g.mode !== 'play') break;
    stepGame(g, POLICIES.skilled(g, mem));
    if (check) check(g);
    g.events.length = 0;
  }
  return g;
}

test('déterminisme : mêmes graine et entrées => même partie, nouveaux archétypes et champions en jeu', () => {
  const kinds = new Set();
  const run = () => {
    const g = botRun(4, INVARIANT_START, 3000, (gg) => {
      for (const e of gg.enemies) kinds.add(e.kind);
    });
    return [stateHash(g), g.rng.gen.s, g.rng.combat.s, g.rng.ai.s, g.hazards.length, g.spawns.length].join('|');
  };
  const a = run();
  const b = run();
  assert.equal(a, b);
  assert.ok(kinds.has('pyromancer') || kinds.has('necromancer'), `couverture : ${[...kinds].join(', ')}`);
});

/** Profondeur (u) d'un cercle dans un rectangle ; <= 0 si pas de chevauchement. */
function rectOverlap(o, x, y, r) {
  const cx = Math.min(Math.max(x, o.x0), o.x1);
  const cy = Math.min(Math.max(y, o.y0), o.y1);
  const inside = x > o.x0 && x < o.x1 && y > o.y0 && y < o.y1;
  if (inside) return r + Math.min(x - o.x0, o.x1 - x, y - o.y0, o.y1 - y);
  return r - Math.hypot(x - cx, y - cy);
}

function geometryViolation(room, x, y, r) {
  const lo = room.pad + r - GEOM_EPS;
  if (x < lo || x > room.w - lo || y < lo || y > room.h - lo) return 'hors des murs';
  for (const o of room.obstacles) if (rectOverlap(o, x, y, r) > GEOM_EPS) return 'dans un obstacle';
  return null;
}

test('invariants stricts avec le nouveau bestiaire (bot skilled, étages 8+) : PV bornés (soins vampiriques compris), murs, obstacles', () => {
  const cover = { pyro: 0, necro: 0, puddles: 0, elites: new Set() };
  for (const seed of INVARIANT_SEEDS) {
    botRun(seed, INVARIANT_START, INVARIANT_STEPS, (g) => {
      const p = g.player;
      assert.ok(p.hp >= 0 && p.hp <= p.maxHp, `PV du héros ${p.hp}`);
      for (const e of g.enemies) {
        if (e.dead) continue;
        assert.ok(e.hp > 0 && e.hp <= e.maxHp, `${e.kind}#${e.id} vivant avec ${e.hp} / ${e.maxHp}`);
        const v = geometryViolation(g.room, e.x, e.y, e.r);
        assert.equal(v, null, `${e.kind}#${e.id} ${v} (${e.x.toFixed(1)}, ${e.y.toFixed(1)})`);
        if (e.kind === 'pyromancer') cover.pyro++;
        if (e.kind === 'necromancer') cover.necro++;
        if (e.eliteMod) cover.elites.add(e.eliteMod);
      }
      if (g.hazards.some((h) => h.burning)) cover.puddles++;
    });
  }
  assert.ok(cover.pyro > 0 && cover.necro > 0, `couverture : pyromancienne ${cover.pyro}, nécromancien ${cover.necro}`);
  assert.ok(cover.puddles > 0, 'couverture : une flaque a brûlé');
});

// ---------------------------------------------------------------- audio

/** Faux WebAudio minimal et STRICT (lève là où WebAudio lèverait). */
function fakeAudioContextClass() {
  const check = (t) => {
    if (!Number.isFinite(t) || t < 0) throw new RangeError(`temps ${t}`);
  };
  const param = (v) => ({
    value: v,
    setValueAtTime(x, t) { check(t); if (!Number.isFinite(x)) throw new TypeError('valeur'); },
    linearRampToValueAtTime(x, t) { check(t); if (!Number.isFinite(x)) throw new TypeError('valeur'); },
    exponentialRampToValueAtTime(x, t) { check(t); if (!(x > 0)) throw new RangeError(`rampe exp vers ${x}`); },
    setTargetAtTime(x, t) { check(t); },
    cancelScheduledValues(t) { check(t); },
  });
  const node = () => ({ connect: (n) => n, disconnect() {} });
  const source = () => ({ ...node(), start(t = 0) { check(t); }, stop(t = 0) { check(t); }, onended: null });
  return class {
    constructor() {
      this.sampleRate = 48000;
      this.currentTime = 0;
      this.state = 'running';
      this.destination = node();
    }
    resume() { return Promise.resolve(); }
    createGain() { return { ...node(), gain: param(1) }; }
    createStereoPanner() { return { ...node(), pan: param(0) }; }
    createDynamicsCompressor() { const n = node(); for (const k of ['threshold', 'knee', 'ratio', 'attack', 'release']) n[k] = param(0); return n; }
    createWaveShaper() { return { ...node(), curve: null, oversample: 'none' }; }
    createOscillator() { return { ...source(), type: 'sine', frequency: param(440), detune: param(0) }; }
    createBiquadFilter() { return { ...node(), type: 'lowpass', frequency: param(350), Q: param(1) }; }
    createBufferSource() { return { ...source(), buffer: null, loop: false }; }
    createBuffer(c, len, rate) { const d = new Float32Array(len); return { duration: len / rate, length: len, sampleRate: rate, getChannelData: () => d }; }
  };
}

test('audio : attaques des nouveaux archétypes et allumage des flaques jouent sans erreur WebAudio', async () => {
  const audio = createAudio({ AudioContext: fakeAudioContextClass(), navigator: {}, now: () => 0 });
  audio.unlock();
  await Promise.resolve();
  const game = { player: { x: 500, y: 400 } };
  audio.handleEvents([
    ...['pyromancer', 'necromancer', 'summon'].map((enemy) => ({ type: 'enemyAttack', id: 1, x: 600, y: 400, enemy })),
    { type: 'hazardFire', id: 2, kind: 'pyre', shape: 'circle', x: 600, y: 400, r: 64, angle: 0, length: 0, width: 0 },
    { type: 'hit', id: 3, x: 600, y: 400, amount: 12, crit: false, kind: 'melee', enemy: 'pyromancer', shake: 0 },
    { type: 'kill', id: 3, x: 600, y: 400, enemy: 'necromancer', elite: true, boss: false, kind: 'melee' },
  ], game);
  const st = audio.getStats();
  assert.equal(st.errors, 0, st.lastError);
  assert.ok(st.played >= 4, `sons joués : ${st.played}`);
});

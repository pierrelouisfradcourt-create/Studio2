// Lot « BESTIAIRE 2 » (2026-10-01) — tests NEUFS des trois archétypes ajoutés :
//   pavois  (Porte-pavois)   : arrête les coups de face ; on le frappe de dos, de flanc, après son
//                              coup, ou étourdi ;
//   stalker (Traqueur)       : se dissout, disparaît, resurgit dans le dos du héros et frappe en
//                              cercle après un télégraphe rouge ;
//   banner  (Porte-étendard) : n'attaque jamais ; les autres ennemis sous son aura prennent moins.
// Pour chacun : la règle de contre-jeu est vraie, le coup est télégraphié au moins le seuil, aucun
// dégât sans télégraphe, il finit par agir contre un héros immobile, il n'entre pas avant son
// étage, l'étourdir ou le tuer pendant son télégraphe annule le coup, déterminisme, et la salle
// se termine toujours.
//
// Des lois plutôt que des valeurs : les seuils et durées lisent game.tuning. Lancer :
//   node --test tests/v2_foes_2.test.mjs

import test from 'node:test';
import assert from 'node:assert/strict';
import { createGame, stepGame, emptyInput, applyCommand, stateHash } from '../src/sim/game.mjs';
import { createEnemy } from '../src/sim/enemies.mjs';
import { damageEnemy, killEnemy } from '../src/sim/combat.mjs';
import { pickEliteMod } from '../src/sim/foe_elites.mjs';
import { enterFloor } from '../src/sim/run.mjs';
import { guardUp, frontBlocked, wardOf, wardMult } from '../src/sim/foe_defense.mjs';
import { ambushPoint } from '../src/sim/foe_stalker.mjs';
import { activeAttackers } from '../src/sim/ai_common.mjs';
import { EXTRA_ENEMIES, EXTRA_ROSTER, EXTRA_ELITE_KINDS } from '../src/sim/foe_data.mjs';
import { pointBlocked } from '../src/sim/physics.mjs';
import { angleDiff } from '../src/core/math.mjs';
import { POLICIES, resolveChoice } from '../tools/bots.mjs';
import { FOE_ART, FOE_BODY } from '../src/render/art_foes.mjs';
import { createAudio } from '../src/audio/sfx.mjs';

const DT = 1 / 60;
const SEC = 60; // pas par seconde
const MIN_TELEGRAPH = 0.4; // s : un coup doit être précédé d'un télégraphe rouge au moins aussi long
const TELEGRAPH_LOOKBACK = 4; // s : fenêtre où chercher ce télégraphe avant le coup
const FLOOR_SEEDS = 60;
const SECTION_LAST_COMBAT = 17;
const NEW_KINDS = ['pavois', 'stalker', 'banner'];
const ENTRY = { pavois: [10, 12], stalker: [12, 14], banner: [14, 16] }; // étage de première apparition attendu
const BIG_HP = 5000;
const HIGH_FLOOR = 600;
const GEOM_EPS = 0.5;
const APPROACH_STOP = 36; // u entre les centres : au contact
const ANGLE_EPS = 1e-9;

// ---------------------------------------------------------------- outillage

/** Salle vidée et « hors combat », héros immobile au centre bas. Les ennemis sont posés à la main. */
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

/** Le héros marche vers l'ennemi le plus proche jusqu'à `stopAt` u, sans frapper. */
function approachInput(game, stopAt) {
  const p = game.player;
  const input = emptyInput();
  let best = null;
  for (const e of game.enemies) if (!e.dead && !(e.spawnT > 0) && (!best || dist(p, e) < dist(p, best))) best = e;
  if (best && dist(p, best) > stopAt) {
    const d = dist(p, best);
    input.moveX = (best.x - p.x) / d;
    input.moveY = (best.y - p.y) / d;
  }
  return input;
}

/** Un télégraphe ROUGE (qui fait mal) est-il visible à l'écran ? */
function redTelegraphVisible(game) {
  for (const e of game.enemies) if (!e.dead && e.tele && !e.tele.harmless) return true;
  for (const h of game.hazards) if (!h.done && h.hitsPlayer && !h.burning) return true;
  return false;
}

/** Un coup d'arme porté à `e` depuis l'angle `from` (rad, autour de lui) : la direction va vers lui. */
function strikeFrom(game, e, from, kind = 'melee', extra = {}) {
  return damageEnemy(game, e, { kind, amount: 10, dirX: -Math.cos(from), dirY: -Math.sin(from), canCrit: false, ...extra });
}

/** Porte-pavois figé (ni pivot, ni coup), face tournée vers `face` : pour mesurer la seule garde. */
function frozenPavois(face, opts = {}) {
  const g = quietGame({ godMode: true, tuning: { enemies: { pavois: { turnRate: 0, attackRange: -1000, speed: 0 } } }, ...opts });
  const e = spawnFoe(g, 'pavois', 0, -200);
  e.face = face;
  step(g);
  assert.equal(e.face, face, 'témoin : le pavois figé ne pivote pas');
  return { g, e };
}

// ---------------------------------------------------------------- présence dans le jeu

test('bestiaire 2 : pavois, traqueur et étendard entrent un par un dans la 1re section, jamais avant leur étage ; tous là dès la section 2', () => {
  const first = {};
  for (let seed = 1; seed <= FLOOR_SEEDS; seed++) {
    for (let floor = 1; floor <= SECTION_LAST_COMBAT; floor++) {
      const g = createGame({ seed, startFloor: floor });
      for (const wave of g.room.waves) for (const s of wave) first[s.kind] = Math.min(first[s.kind] ?? Infinity, floor);
    }
  }
  const roster = Object.fromEntries(EXTRA_ROSTER.map((r) => [r.kind, r]));
  for (const kind of NEW_KINDS) {
    assert.ok(roster[kind], `${kind} : pas dans EXTRA_ROSTER`);
    assert.ok(Number.isFinite(first[kind]), `${kind} : jamais tiré dans la 1re section`);
    assert.ok(first[kind] >= roster[kind].minIndex, `${kind} apparaît à l'étage ${first[kind]}, avant son minIndex ${roster[kind].minIndex}`);
    const [lo, hi] = ENTRY[kind];
    assert.ok(first[kind] >= lo && first[kind] <= hi, `${kind} introduit à l'étage ${first[kind]} (attendu ${lo}-${hi})`);
  }
  // Entrée progressive, APRÈS les archétypes existants (le dernier : le Nécromancien).
  const older = EXTRA_ROSTER.filter((r) => !NEW_KINDS.includes(r.kind)).map((r) => r.minIndex);
  const entries = NEW_KINDS.map((k) => roster[k].minIndex);
  assert.ok(Math.min(...entries) > Math.max(...older), 'les nouveaux entrent après les anciens');
  assert.equal(new Set(entries).size, entries.length, 'un seul nouvel archétype par étage d\'entrée');
  const sec2 = new Set();
  for (let seed = 1; seed <= FLOOR_SEEDS; seed++) for (const w of createGame({ seed, startFloor: 19 }).room.waves) for (const s of w) sec2.add(s.kind);
  for (const kind of NEW_KINDS) assert.ok(sec2.has(kind), `section 2, étage 1 : ${kind} absent (${[...sec2].join(', ')})`);
});

test('dessin, noms et données : chaque nouvel archétype a sa silhouette, sa couleur, son nom, son or et son coût', () => {
  const g = createGame();
  for (const kind of NEW_KINDS) {
    assert.ok(EXTRA_ENEMIES[kind], `pas de données pour ${kind}`);
    assert.equal(typeof FOE_ART[kind], 'function', `pas de dessin pour ${kind}`);
    assert.ok(FOE_BODY[kind], `pas de couleur de corps pour ${kind}`);
    const def = g.tuning.enemies[kind];
    assert.ok(def.name && def.radius > 0 && def.hp > 0 && def.speed > 0 && def.mass > 0, `${kind} : données incomplètes`);
    assert.ok(Array.isArray(def.gold) && def.gold[0] <= def.gold[1], `${kind} : or`);
  }
  assert.equal(new Set(NEW_KINDS.map((k) => FOE_BODY[k])).size, NEW_KINDS.length, 'trois couleurs de corps distinctes');
});

// ---------------------------------------------------------------- lisibilité commune

test('chaque nouvel archétype, posé SUR le héros : tout dégât est précédé d\'un télégraphe rouge visible — aucun dégât de contact', () => {
  for (const kind of NEW_KINDS) {
    const g = quietGame({ bigHp: true });
    spawnFoe(g, kind, 4, -4);
    const visible = [];
    let hurts = 0;
    for (let i = 0; i < 12 * SEC; i++) {
      visible.push(redTelegraphVisible(g));
      for (const ev of step(g, kind === 'pavois' ? approachInput(g, APPROACH_STOP) : emptyInput())) {
        if (ev.type !== 'playerHurt') continue;
        hurts++;
        assert.equal(ev.source, kind, `${kind} : la cause du coup porte son nom`);
        const from = Math.max(0, visible.length - TELEGRAPH_LOOKBACK * SEC);
        let run = 0;
        let best = 0;
        for (let k = from; k < visible.length; k++) {
          run = visible[k] ? run + 1 : 0;
          best = Math.max(best, run);
        }
        assert.ok(best * DT >= MIN_TELEGRAPH, `${kind} : coup sans télégraphe rouge d'au moins ${MIN_TELEGRAPH} s (vu ${(best * DT).toFixed(2)} s)`);
      }
    }
    if (kind === 'banner') assert.equal(hurts, 0, 'le porte-étendard ne frappe jamais');
    else assert.ok(hurts > 0, `${kind} : témoin — il doit avoir frappé un héros immobile en 12 s`);
  }
});

test('télégraphes : durées au-dessus du seuil, identiques à l\'étage 1 et à l\'étage 600, et pour un champion « rapide »', () => {
  const measure = (floor, elite) => {
    const g = quietGame({ startFloor: floor, bigHp: true });
    const pav = spawnFoe(g, 'pavois', 0, -60, { elite });
    let teleSteps = 0;
    const r = stepUntil(g, () => {
      if (pav.tele) teleSteps++;
      return pav.state === 'recover';
    }, 10 * SEC);
    assert.ok(r.ok, `étage ${floor} : le porte-pavois doit frapper`);
    const g2 = quietGame({ startFloor: floor, bigHp: true });
    spawnFoe(g2, 'stalker', 0, -200, { elite });
    const r2 = stepUntil(g2, (gg) => gg.hazards.some((h) => h.kind === 'stalker'), 10 * SEC);
    assert.ok(r2.ok, `étage ${floor} : le traqueur doit armer sa frappe`);
    return { pavois: teleSteps, stalker: g2.hazards.find((h) => h.kind === 'stalker').delay };
  };
  const base = measure(1, null);
  assert.ok(base.pavois * DT >= MIN_TELEGRAPH, `coup de pavois télégraphié ${(base.pavois * DT).toFixed(2)} s`);
  assert.ok(base.stalker >= MIN_TELEGRAPH, `frappe du traqueur télégraphiée ${base.stalker} s`);
  assert.deepEqual(measure(HIGH_FLOOR, null), base, 'la profondeur ne raccourcit aucun télégraphe');
  assert.deepEqual(measure(1, 'rapide'), base, 'un champion rapide court plus vite, il ne frappe pas plus tôt');
});

// ---------------------------------------------------------------- Porte-pavois (garde de face)

test('Porte-pavois : frappé de face il ne prend RIEN (ni dégât, ni recul, ni étourdissement) ; de dos et de flanc il prend tout', () => {
  const { g, e } = frozenPavois(0.4);
  const def = g.tuning.enemies.pavois;
  const half = def.guardArc / 2;
  assert.ok(guardUp(g, e));
  for (const off of [0, half * 0.5, -half * 0.5, half - 0.02, -(half - 0.02)]) {
    const hp = e.hp;
    g.events.length = 0;
    const dealt = strikeFrom(g, e, e.face + off, 'melee', { knockback: 400, stun: 1 });
    assert.equal(dealt, 0, `de face (écart ${off.toFixed(2)} rad) : le coup ne porte pas`);
    assert.equal(e.hp, hp);
    assert.ok(e.kvx === 0 && e.kvy === 0, 'aucun recul');
    assert.ok(!(e.stun > 0), 'aucun étourdissement');
    assert.ok(g.events.some((ev) => ev.type === 'deflect' && ev.guard), 'le coup arrêté se VOIT et s\'ENTEND (événement de parade)');
    assert.ok(!g.events.some((ev) => ev.type === 'hit'), 'pas d\'événement de coup porté');
  }
  for (const off of [Math.PI, Math.PI / 2, -Math.PI / 2, half + 0.02, -(half + 0.02)]) {
    const hp = e.hp;
    const dealt = strikeFrom(g, e, e.face + off);
    assert.ok(dealt > 0, `de dos ou de flanc (écart ${off.toFixed(2)} rad) : le coup porte`);
    assert.equal(e.hp, hp - dealt);
  }
});

test('Porte-pavois : seuls l\'arme et la compétence rebondissent ; gadget, Super, brûlure, éclair et mur passent même de face', () => {
  const { g, e } = frozenPavois(-1.1);
  const def = g.tuning.enemies.pavois;
  for (const kind of def.guardSources) assert.equal(strikeFrom(g, e, e.face, kind), 0, `${kind} de face`);
  assert.deepEqual([...def.guardSources].sort(), ['melee', 'skill', 'strike'], 'sources arrêtées');
  for (const kind of ['gadget', 'super', 'blast', 'wall']) assert.ok(strikeFrom(g, e, e.face, kind) > 0, `${kind} de face doit porter`);
  // Coups sans direction (brûlure, éclair) : ils ne viennent d'aucun côté.
  assert.ok(damageEnemy(g, e, { kind: 'burn', amount: 5, canCrit: false }) > 0);
  assert.ok(damageEnemy(g, e, { kind: 'chain', amount: 5, canCrit: false }) > 0);
});

test('Porte-pavois : étourdi, ou pendant la récupération de son propre coup, le pavois est baissé — tout passe de face', () => {
  const { g, e } = frozenPavois(0);
  assert.equal(strikeFrom(g, e, e.face), 0);
  damageEnemy(g, e, { kind: 'gadget', amount: 1, stun: 1, canCrit: false });
  assert.ok(e.stun > 0 && !guardUp(g, e));
  assert.ok(strikeFrom(g, e, e.face) > 0, 'étourdi : le coup de face porte');
  // Récupération : en vraie partie, après son coup.
  const g2 = quietGame({ bigHp: true });
  const pav = spawnFoe(g2, 'pavois', 0, -60);
  assert.ok(stepUntil(g2, () => pav.state === 'windup', 6 * SEC).ok, 'il arme son coup');
  assert.ok(guardUp(g2, pav), 'pavois levé pendant le télégraphe');
  assert.equal(strikeFrom(g2, pav, pav.face), 0, 'de face pendant le télégraphe : arrêté');
  assert.ok(stepUntil(g2, () => pav.state === 'recover', 2 * SEC).ok);
  assert.ok(!guardUp(g2, pav));
  assert.ok(strikeFrom(g2, pav, pav.face) > 0, 'pendant sa récupération : le coup de face porte');
  assert.ok(stepUntil(g2, () => pav.state === 'chase', 3 * SEC).ok);
  assert.equal(strikeFrom(g2, pav, pav.face), 0, 'garde relevée après la récupération');
});

test('Porte-pavois : en vraie partie, le combo de face ne lui fait rien ; le même combo dans son dos le blesse', () => {
  const { g, e } = frozenPavois(Math.PI / 2); // pavois tourné vers le bas (vers le héros)
  const p = g.player;
  const attack = (seconds) => {
    let deflects = 0;
    for (let i = 0; i < seconds * SEC; i++) {
      const input = emptyInput();
      input.attack = true;
      input.aimX = e.x - p.x;
      input.aimY = e.y - p.y;
      for (const ev of step(g, input)) if (ev.type === 'deflect' && ev.guard) deflects++;
    }
    return deflects;
  };
  p.x = e.x;
  p.y = e.y + e.r + p.r + 12; // devant lui
  const hp = e.hp;
  assert.ok(attack(1.5) >= 2, 'témoin : les coups de face sonnent sur le pavois');
  assert.equal(e.hp, hp, 'de face : aucun dégât');
  p.x = e.x;
  p.y = e.y - e.r - p.r - 12; // dans son dos
  attack(1.5);
  assert.ok(e.hp < hp, 'de dos : il est blessé');
});

test('Porte-pavois : il pivote au plus à turnRate, sa face est VERROUILLÉE pendant le télégraphe et la récupération', () => {
  const g = quietGame({ bigHp: true });
  const def = g.tuning.enemies.pavois;
  const e = spawnFoe(g, 'pavois', 0, -60);
  const p = g.player;
  step(g);
  let prev = e.face;
  // Le héros saute de l'autre côté : il doit se retourner, jamais plus vite que turnRate.
  p.y = e.y - 60;
  let turned = 0;
  for (let i = 0; i < 0.5 * SEC; i++) {
    step(g);
    const d = Math.abs(angleDiff(prev, e.face));
    assert.ok(d <= def.turnRate * DT + ANGLE_EPS, `pivot de ${d.toFixed(4)} rad en une image`);
    turned += d;
    prev = e.face;
  }
  assert.ok(turned > 0.5, 'témoin : il se retourne vers le héros');
  assert.ok(stepUntil(g, () => e.state === 'windup', 8 * SEC).ok, 'il finit par armer son coup');
  const locked = e.face;
  p.y = e.y + 60; // le héros repasse derrière pendant le télégraphe
  const r = stepUntil(g, () => {
    assert.equal(e.face, locked, `face verrouillée (état ${e.state})`);
    return e.state === 'chase';
  }, 4 * SEC);
  assert.ok(r.ok);
  assert.ok(!r.events.some((ev) => ev.type === 'playerHurt'), 'passé dans son dos pendant le télégraphe : le coup de pavois manque');
});

test('Porte-pavois : un dash à travers lui dépose le héros dans son dos, hors de la garde, pour une vraie fenêtre de frappe', () => {
  const g = quietGame({ godMode: true });
  const def = g.tuning.enemies.pavois;
  const e = spawnFoe(g, 'pavois', 0, -70);
  e.cooldown = 99; // il ne frappe pas : on mesure le seul pivot
  const p = g.player;
  for (let i = 0; i < 10; i++) step(g);
  const blockedFromHero = () => frontBlocked(g, e, { kind: 'melee', dirX: e.x - p.x, dirY: e.y - p.y });
  assert.ok(blockedFromHero(), 'témoin : face à lui, les coups du héros rebondissent');
  const dash = emptyInput();
  dash.moveX = (e.x - p.x) / dist(e, p);
  dash.moveY = (e.y - p.y) / dist(e, p);
  dash.dashPressed = true;
  step(g, dash);
  assert.ok(stepUntil(g, () => p.state !== 'dash', SEC).ok);
  assert.ok(!blockedFromHero(), 'après le dash : le héros est hors de la garde');
  let open = 0;
  while (!blockedFromHero() && open < 5 * SEC) {
    step(g);
    open++;
  }
  // Demi-tour à faire avant de couvrir de nouveau le héros : (PI - demi-garde) / turnRate, à peu près.
  const expected = (Math.PI - def.guardArc / 2) / def.turnRate;
  assert.ok(open * DT >= 0.5, `fenêtre de ${(open * DT).toFixed(2)} s : trop courte pour placer un coup`);
  assert.ok(Math.abs(open * DT - expected) < 0.5, `fenêtre de ${(open * DT).toFixed(2)} s (attendu ~${expected.toFixed(2)} s)`);
});

test('Porte-pavois : le coup de pavois ne touche que dans le secteur dessiné ; l\'étourdir ou le tuer pendant le télégraphe l\'annule', () => {
  // Touché dans le secteur.
  const g = quietGame({ bigHp: true });
  const e = spawnFoe(g, 'pavois', 0, -60);
  assert.ok(stepUntil(g, () => e.state === 'windup' && e.tele, 6 * SEC).ok);
  assert.ok(e.tele.shape === 'cone' && e.tele.area === true && !e.tele.harmless, 'télégraphe rouge en secteur');
  assert.equal(e.tele.angle, e.face, 'le secteur est dessiné là où regarde le pavois');
  const r = stepUntil(g, () => e.state === 'recover', 2 * SEC);
  assert.equal(r.events.filter((ev) => ev.type === 'playerHurt').length, 1, 'héros immobile dans le secteur : touché une fois');
  assert.ok(r.events.some((ev) => ev.type === 'enemyAttack' && ev.enemy === 'pavois'), 'cri d\'attaque');
  for (const how of ['kill', 'stun']) {
    const g2 = quietGame({ bigHp: true });
    const e2 = spawnFoe(g2, 'pavois', 0, -60);
    assert.ok(stepUntil(g2, () => e2.state === 'windup' && e2.stateTime > 0.2, 6 * SEC).ok);
    if (how === 'kill') killEnemy(g2, e2, { kind: 'melee' });
    else damageEnemy(g2, e2, { kind: 'wall', amount: 1, stun: 1.2, canCrit: false });
    const hp = g2.player.hp;
    for (let i = 0; i < 1.2 * SEC; i++) {
      step(g2);
      assert.ok(!e2.tele, `${how} : le télégraphe disparaît`);
    }
    assert.equal(g2.player.hp, hp, `${how} : le coup est annulé`);
  }
});

// ---------------------------------------------------------------- Traqueur (embuscade)

/** Fait jouer un traqueur jusqu'à sa réapparition ; rend la partie, lui, et la zone de frappe. */
function ambush(opts = {}) {
  const g = quietGame({ bigHp: true, ...opts });
  const e = spawnFoe(g, 'stalker', 0, -220, { elite: opts.elite });
  const seen = { fade: 0, hidden: 0 };
  const r = stepUntil(g, () => {
    if (e.state === 'fade') seen.fade++;
    if (e.hidden) seen.hidden++;
    return g.hazards.some((h) => h.kind === 'stalker');
  }, 10 * SEC);
  return { g, e, seen, ok: r.ok, events: r.events, hazard: g.hazards.find((h) => h.kind === 'stalker') };
}

test('Traqueur : il se dissout (visible, vulnérable), disparaît (intouchable), resurgit DANS LE DOS du héros, puis frappe après un télégraphe rouge', () => {
  const { g, e, seen, ok, events, hazard } = ambush();
  const def = g.tuning.enemies.stalker;
  const p = g.player;
  assert.ok(ok, 'il doit tendre son embuscade');
  assert.ok(seen.fade * DT >= def.fade - 2 * DT, `dissolution visible ${(seen.fade * DT).toFixed(2)} s`);
  assert.ok(seen.hidden * DT >= def.hiddenTime - 2 * DT, `disparu ${(seen.hidden * DT).toFixed(2)} s`);
  assert.ok(!events.some((ev) => ev.type === 'playerHurt'), 'aucun dégât avant la frappe');
  assert.ok(!e.hidden && e.state === 'windup', 'réapparu, il arme sa frappe');
  assert.ok(events.some((ev) => ev.type === 'enemyAttack' && ev.enemy === 'stalker'), 'cri à la réapparition : on entend le traqueur resurgir');
  // Dans le dos : à backDist, à l'opposé de l'orientation du héros.
  assert.ok(Math.abs(dist(e, p) - def.backDist) < 1, `à ${dist(e, p).toFixed(1)} u du héros`);
  const behind = Math.atan2(e.y - p.y, e.x - p.x);
  assert.ok(Math.abs(angleDiff(p.facing + Math.PI, behind)) < 0.01, 'derrière le héros');
  // La frappe : zone rouge autour de lui, liée à lui, télégraphiée.
  assert.ok(hazard.hitsPlayer && !hazard.hitsEnemies && hazard.sourceId === e.id);
  assert.ok(hazard.delay >= MIN_TELEGRAPH && hazard.delay >= def.slashWindup);
  assert.ok(Math.hypot(hazard.x - e.x, hazard.y - e.y) < 1 && hazard.r === def.slashRadius);
  const r = stepUntil(g, () => e.state === 'recover', 2 * SEC);
  const hurts = r.events.filter((ev) => ev.type === 'playerHurt');
  assert.equal(hurts.length, 1, 'héros immobile : touché une fois');
  assert.equal(hurts[0].source, 'stalker');
  // Longue récupération : il reste là, visible et vulnérable.
  assert.ok(damageEnemy(g, e, { kind: 'melee', amount: 1, canCrit: false }) > 0, 'vulnérable pendant sa récupération');
});

test('Traqueur : disparu, il n\'est ni touchable ni ciblé ; dissous à moitié, il l\'est encore', () => {
  const g = quietGame({ bigHp: true });
  const e = spawnFoe(g, 'stalker', 0, -220);
  assert.ok(stepUntil(g, () => e.state === 'fade', 8 * SEC).ok);
  assert.ok(damageEnemy(g, e, { kind: 'burn', amount: 1, canCrit: false }) > 0, 'pendant la dissolution : vulnérable');
  assert.ok(stepUntil(g, () => e.hidden === true, 2 * SEC).ok);
  assert.ok(e.spawnT > 0, 'disparu : hors du jeu comme une apparition en attente');
  const hp = e.hp;
  for (const kind of ['melee', 'skill', 'gadget', 'super', 'burn']) assert.equal(damageEnemy(g, e, { kind, amount: 50, dirX: 1, dirY: 0, stun: 1, canCrit: false }), 0, `${kind} sur un traqueur disparu`);
  assert.equal(e.hp, hp);
  assert.ok(!(e.stun > 0));
});

test('Traqueur : le tuer ou l\'étourdir pendant la dissolution annule l\'embuscade ; pendant le télégraphe, annule la frappe', () => {
  for (const how of ['kill', 'stun']) {
    // Pendant la dissolution : il ne disparaît pas, aucune zone ne naît.
    const g = quietGame({ bigHp: true });
    const e = spawnFoe(g, 'stalker', 0, -220);
    assert.ok(stepUntil(g, () => e.state === 'fade', 8 * SEC).ok);
    const stun = 1;
    if (how === 'kill') killEnemy(g, e, { kind: 'melee' });
    else damageEnemy(g, e, { kind: 'wall', amount: 1, stun, canCrit: false });
    for (let i = 0; i < stun * SEC - 2; i++) {
      step(g);
      assert.ok(!e.hidden, `${how} pendant la dissolution : il ne disparaît pas`);
      assert.ok(!g.hazards.some((h) => h.kind === 'stalker'), `${how} : aucune frappe`);
    }
    // Pendant le télégraphe : la zone est annulée, visiblement.
    const a = ambush();
    assert.ok(a.ok);
    if (how === 'kill') killEnemy(a.g, a.e, { kind: 'melee' });
    else damageEnemy(a.g, a.e, { kind: 'wall', amount: 1, stun, canCrit: false });
    const hp = a.g.player.hp;
    let cancels = 0;
    for (let i = 0; i < 1.5 * SEC; i++) for (const ev of step(a.g)) if (ev.type === 'hazardCancel') cancels++;
    assert.equal(a.g.player.hp, hp, `${how} pendant le télégraphe : aucun dégât`);
    assert.ok(cancels >= 1, `${how} : annulation visible (hazardCancel)`);
  }
});

test('Traqueur : sortir du cercle (à pied ou d\'un dash) évite la frappe ; dasher À TRAVERS au bon moment est une esquive parfaite', () => {
  // À pied, droit devant (à l'opposé de lui).
  const a = ambush();
  const p = a.g.player;
  const away = emptyInput();
  away.moveX = (p.x - a.e.x) / dist(p, a.e);
  away.moveY = (p.y - a.e.y) / dist(p, a.e);
  const r = stepUntil(a.g, () => a.e.state === 'recover', 2 * SEC, away);
  assert.ok(!r.events.some((ev) => ev.type === 'playerHurt'), 'sorti du cercle : pas touché');
  // Esquive parfaite : immobile, dash lancé juste avant l'impact.
  const b = ambush();
  const def = b.g.tuning.enemies.stalker;
  const wait = Math.round((def.slashWindup - 0.08) * SEC);
  for (let i = 0; i < wait; i++) step(b.g);
  const dodges = b.g.telemetry.dodges;
  const dash = emptyInput();
  dash.moveX = 1;
  dash.dashPressed = true;
  const ev1 = step(b.g, dash);
  const r2 = stepUntil(b.g, () => b.e.state === 'recover', 2 * SEC);
  assert.ok(![...ev1, ...r2.events].some((ev) => ev.type === 'playerHurt'), 'dash au bon moment : pas touché');
  assert.equal(b.g.telemetry.dodges, dodges + 1, 'la frappe traversée pendant le dash compte comme une esquive parfaite');
});

test('Traqueur : il ne resurgit jamais dans un mur ni dans un obstacle, même quand le héros est dos au mur', () => {
  const g = quietGame({ bigHp: true });
  const def = g.tuning.enemies.stalker;
  const room = g.room;
  room.obstacles = [{ x0: 300, y0: 300, x1: 420, y1: 420 }];
  const e = spawnFoe(g, 'stalker', 0, -220);
  const p = g.player;
  const spots = [
    [room.pad + p.r + 1, room.h / 2, 0], // dos au mur gauche, tourné vers la droite
    [room.w - room.pad - p.r - 1, room.h / 2, Math.PI], // dos au mur droit
    [room.w / 2, room.pad + p.r + 1, Math.PI / 2], // dos au mur du haut
    [room.pad + p.r + 1, room.pad + p.r + 1, Math.PI / 4], // dans un coin
    [440, 360, 0], // dos à un obstacle
  ];
  for (const [x, y, facing] of spots) {
    p.x = x;
    p.y = y;
    p.facing = facing;
    const pt = ambushPoint(g, e, def);
    assert.ok(!pointBlocked(room, pt.x, pt.y, e.r), `réapparition bloquée en (${pt.x.toFixed(0)}, ${pt.y.toFixed(0)}) pour un héros en (${x}, ${y})`);
    assert.ok(Math.abs(Math.hypot(pt.x - x, pt.y - y) - def.backDist) < 1 || (pt.x === e.x && pt.y === e.y), 'à backDist du héros (ou sur place, faute de mieux)');
  }
});

test('Traqueur : il garde son jeton de mêlée de la dissolution à la frappe — jamais plus d\'attaquants que le plafond', () => {
  const g = quietGame({ godMode: true, tuning: { combat: { maxAttackers: 1 }, enemies: { stalker: { cooldown: 0.5 } } } });
  for (let i = 0; i < 3; i++) spawnFoe(g, 'stalker', -200 + i * 200, -220);
  const busy = new Set(['fade', 'ambush', 'windup']);
  let ambushes = 0;
  for (let i = 0; i < 25 * SEC; i++) {
    for (const ev of step(g)) if (ev.type === 'enemyAttack') ambushes++;
    const n = g.enemies.filter((e) => busy.has(e.state)).length;
    assert.ok(n <= 1, `${n} traqueurs en embuscade en même temps (plafond 1)`);
    assert.equal(activeAttackers(g), n, 'le jeton est compté pendant toute l\'embuscade');
  }
  assert.ok(ambushes >= 4, `témoin : ils se relaient (${ambushes} embuscades)`);
});

// ---------------------------------------------------------------- Porte-étendard (soutien)

test('Porte-étendard : sous son aura les AUTRES prennent wardMult des dégâts ; hors de l\'aura, lui-même et un autre étendard prennent tout', () => {
  const g = quietGame({ godMode: true, tuning: { enemies: { banner: { speed: 0 }, brute: { speed: 0 }, pavois: { speed: 0, turnRate: 0, attackRange: -1000 } } } });
  const def = g.tuning.enemies.banner;
  const b = spawnFoe(g, 'banner', 0, -400);
  const near = createEnemy(g, 'brute', b.x + def.auraRadius - 30, b.y, { spawnT: 0 });
  const far = createEnemy(g, 'brute', b.x - def.auraRadius - 60, b.y, { spawnT: 0 });
  const other = createEnemy(g, 'banner', b.x, b.y + 80, { spawnT: 0 });
  step(g);
  assert.equal(wardOf(g, near), b);
  assert.equal(wardOf(g, far), null);
  assert.equal(wardOf(g, b), null);
  assert.equal(wardOf(g, other), null, 'deux étendards ne se protègent pas l\'un l\'autre');
  const hit = (e) => damageEnemy(g, e, { kind: 'wall', amount: 20, canCrit: false });
  assert.equal(hit(far), 20);
  assert.equal(hit(b), 20);
  assert.equal(hit(other), 20);
  assert.equal(hit(near), Math.round(20 * def.wardMult), 'sous l\'aura');
  assert.ok(def.wardMult > 0 && def.wardMult < 1);
  assert.equal(wardMult(g, near), def.wardMult);
  // L'aura se VOIT, et elle est inoffensive.
  assert.ok(b.tele && b.tele.harmless === true && b.tele.r === def.auraRadius, 'aura dessinée en alerte inoffensive');
});

test('Porte-étendard : l\'étourdir fait tomber l\'aura (et son dessin) ; le tuer aussi — la protection cesse aussitôt', () => {
  for (const how of ['kill', 'stun']) {
    const g = quietGame({ godMode: true, tuning: { enemies: { banner: { speed: 0 }, brute: { speed: 0 } } } });
    const b = spawnFoe(g, 'banner', 0, -400);
    const ally = createEnemy(g, 'brute', b.x + 100, b.y, { spawnT: 0 });
    step(g);
    assert.equal(wardOf(g, ally), b);
    if (how === 'kill') killEnemy(g, b, { kind: 'melee' });
    else damageEnemy(g, b, { kind: 'wall', amount: 1, stun: 1, canCrit: false });
    assert.equal(wardOf(g, ally), null, `${how} : plus de protection`);
    assert.equal(damageEnemy(g, ally, { kind: 'wall', amount: 20, canCrit: false }), 20);
    step(g);
    assert.ok(!b.tele, `${how} : l'aura n'est plus dessinée`);
    if (how === 'stun') {
      assert.ok(stepUntil(g, () => !(b.stun > 0), 2 * SEC).ok);
      step(g);
      assert.equal(wardOf(g, ally), b, 'relevé, il protège de nouveau');
      assert.ok(b.tele && b.tele.harmless);
    }
  }
});

test('Porte-étendard : il n\'attaque jamais, vient couvrir la mêlée d\'un héros immobile, et recule quand on le serre', () => {
  const g = quietGame({ bigHp: true, tuning: { enemies: { brute: { speed: 0, attackRange: -1000 } } } });
  const def = g.tuning.enemies.banner;
  const p = g.player;
  const ally = spawnFoe(g, 'brute', 40, 0); // au contact du héros
  const b = spawnFoe(g, 'banner', 0, -520);
  assert.equal(wardOf(g, ally), null, 'témoin : trop loin au départ');
  const r = stepUntil(g, () => wardOf(g, ally) === b, 10 * SEC);
  assert.ok(r.ok, 'il finit par couvrir l\'ennemi qui serre le héros');
  for (let i = 0; i < 6 * SEC; i++) step(g);
  assert.equal(wardOf(g, ally), b, 'et il le couvre toujours 6 s plus tard');
  assert.equal(p.hp, BIG_HP, 'aucun dégât : il ne frappe jamais');
  assert.equal(def.damage, 0);
  // Serré de près, il recule (lentement : on le rattrape).
  const g2 = quietGame({ bigHp: true });
  const b2 = spawnFoe(g2, 'banner', 0, -60);
  const d0 = dist(b2, g2.player);
  for (let i = 0; i < SEC; i++) step(g2);
  assert.ok(dist(b2, g2.player) > d0 + 20, 'il s\'écarte du héros');
  assert.ok(def.speed < g2.tuning.player.speed, 'plus lent que le héros');
});

// ---------------------------------------------------------------- champions

test('champions : pavois et traqueur peuvent l\'être (exclusions tenues) ; le porte-étendard jamais', () => {
  assert.ok(EXTRA_ELITE_KINDS.includes('pavois') && EXTRA_ELITE_KINDS.includes('stalker'));
  assert.ok(!EXTRA_ELITE_KINDS.includes('banner'));
  const g = createGame({ seed: 9 });
  const draw = (kind) => {
    const s = new Set();
    for (let i = 0; i < 600; i++) s.add(pickEliteMod(g, kind, { section: 3, indexInSection: 10 }));
    return s;
  };
  const pav = draw('pavois');
  const sta = draw('stalker');
  assert.ok(!pav.has('bouclier') && !pav.has('blinde'), `pavois : ${[...pav].join(', ')}`);
  assert.ok(!sta.has('bouclier') && !sta.has('invocateur'), `traqueur : ${[...sta].join(', ')}`);
  assert.ok(pav.size >= 3 && sta.size >= 3, 'il leur reste au moins trois modificateurs');
  // En vrai : ils sortent champions des salles d'élite, jamais avant leur étage d'entrée.
  const roster = Object.fromEntries(EXTRA_ROSTER.map((r) => [r.kind, r.minIndex]));
  const seen = {};
  for (let seed = 1; seed <= FLOOR_SEEDS; seed++) {
    for (const floor of [6, 11, 13, 15, 25]) {
      const h = createGame({ seed, startFloor: floor });
      enterFloor(h, floor, { reward: 'elite' });
      if (h.room.kind !== 'elite') continue;
      for (const s of h.room.waves.flat()) {
        if (!s.elite) continue;
        assert.notEqual(s.kind, 'banner');
        if (NEW_KINDS.includes(s.kind)) assert.ok(floor >= roster[s.kind], `champion ${s.kind} à l'étage ${floor}, avant son entrée`);
        (seen[s.kind] ??= new Set()).add(s.elite);
      }
    }
  }
  assert.ok(seen.pavois?.size > 0 && seen.stalker?.size > 0, `champions planifiés : ${Object.keys(seen).join(', ')}`);
  assert.ok(!seen.pavois.has('bouclier') && !seen.pavois.has('blinde') && !seen.stalker.has('bouclier') && !seen.stalker.has('invocateur'));
  // Un champion traqueur frappe plus large (comme la Brute), jamais plus tôt.
  const a = ambush({ elite: 'ardent' });
  const def = a.g.tuning.enemies.stalker;
  assert.ok(a.ok);
  assert.equal(a.hazard.r, def.slashRadius * a.g.tuning.elite.sizeMult);
  assert.equal(a.hazard.delay, def.slashWindup);
});

// ---------------------------------------------------------------- bots : ils lisent ce qui se voit

function duel(kind, policy, seconds, opts = {}) {
  const g = quietGame({ seed: opts.seed ?? 3, bigHp: true });
  g.room.kind = 'combat';
  const e = spawnFoe(g, kind, 0, -260);
  const mem = {};
  let hurts = 0;
  let deflects = 0;
  let steps = 0;
  for (; steps < seconds * SEC && !e.dead; steps++) {
    for (const ev of step(g, POLICIES[policy](g, mem))) {
      if (ev.type === 'playerHurt') hurts++;
      if (ev.type === 'deflect' && ev.guard) deflects++;
    }
  }
  return { dead: e.dead, hurts, deflects, time: steps * DT, dashes: g.telemetry.dashes };
}

test('bots : seul face à chaque nouvel archétype, le bot habile le tue vite ; sans dash aussi ; celui qui martèle finit par l\'avoir', () => {
  for (const kind of NEW_KINDS) {
    const sk = duel(kind, 'skilled', 30);
    assert.ok(sk.dead, `skilled contre ${kind} : pas tué en 30 s`);
    const nd = duel(kind, 'noDash', 45);
    assert.ok(nd.dead, `noDash contre ${kind} : pas tué en 45 s`);
    const ma = duel(kind, 'masher', 90);
    assert.ok(ma.dead, `masher contre ${kind} : pas tué en 90 s (la salle doit toujours pouvoir se finir)`);
  }
});

test('bot habile : il contourne le pavois au lieu de taper dedans, et sort du cercle du traqueur', () => {
  const pav = duel('pavois', 'skilled', 30);
  const mash = duel('pavois', 'masher', 90);
  assert.ok(pav.dead && mash.dead);
  assert.ok(pav.deflects < mash.deflects, `le bot habile tape moins dans le pavois (${pav.deflects}) que celui qui martèle (${mash.deflects})`);
  assert.ok(pav.hurts <= 1, `le bot habile lit le coup de pavois (${pav.hurts} coups reçus)`);
  assert.ok(mash.hurts > pav.hurts, 'marteler de face se paie');
  // Traqueur : trois embuscades sans le tuer (héros qui ne frappe pas : on ne lit que l'esquive).
  const g = quietGame({ seed: 5, bigHp: true, tuning: { enemies: { stalker: { hp: 1e6, cooldown: 0.5 } } } });
  g.room.kind = 'combat';
  spawnFoe(g, 'stalker', 0, -260);
  const mem = {};
  let ambushes = 0;
  let hurts = 0;
  for (let i = 0; i < 20 * SEC; i++) {
    for (const ev of step(g, POLICIES.skilled(g, mem))) {
      if (ev.type === 'enemyAttack') ambushes++;
      if (ev.type === 'playerHurt') hurts++;
    }
  }
  assert.ok(ambushes >= 3, `témoin : ${ambushes} embuscades`);
  assert.ok(hurts <= ambushes / 3, `le bot habile sort du cercle (${hurts} coups pour ${ambushes} embuscades)`);
});

// ---------------------------------------------------------------- parties réelles

function botRun(seed, startFloor, steps, policy = 'skilled', check = null) {
  const g = createGame({ seed, startFloor });
  const mem = {};
  for (let i = 0; i < steps; i++) {
    for (let k = 0; k < 8 && g.mode === 'choice'; k++) resolveChoice(g, policy);
    if (g.mode === 'dead') applyCommand(g, { type: 'respawn' });
    if (g.mode !== 'play') break;
    stepGame(g, POLICIES[policy](g, mem));
    if (check) check(g);
    g.events.length = 0;
  }
  return g;
}

test('déterminisme : mêmes graine et entrées => même partie, les trois nouveaux archétypes en jeu', () => {
  const kinds = new Set();
  const run = () => {
    const g = botRun(12, 14, 4000, 'skilled', (gg) => {
      for (const e of gg.enemies) kinds.add(e.kind);
    });
    return [stateHash(g), g.rng.gen.s, g.rng.combat.s, g.rng.ai.s, g.hazards.length, g.spawns.length, g.enemies.map((e) => `${e.kind}:${e.state}:${e.face ?? ''}`).join(',')].join('|');
  };
  assert.equal(run(), run());
  for (const kind of NEW_KINDS) assert.ok(kinds.has(kind), `couverture : ${kind} absent (${[...kinds].join(', ')})`);
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

test('invariants en partie réelle (bots habile et sans dash, étages 14+) : PV bornés, personne dans un mur, un traqueur disparu n\'attaque pas', () => {
  const cover = { pavois: 0, stalker: 0, banner: 0, hidden: 0, warded: 0, deflects: 0 };
  for (const [seed, policy] of [[2, 'skilled'], [12, 'skilled'], [12, 'noDash'], [12, 'masher']]) {
    botRun(seed, 14, 4000, policy, (g) => {
      const p = g.player;
      assert.ok(p.hp >= 0 && p.hp <= p.maxHp, `PV du héros ${p.hp}`);
      for (const ev of g.events) if (ev.type === 'deflect' && ev.guard) cover.deflects++;
      for (const e of g.enemies) {
        if (e.dead) continue;
        assert.ok(e.hp > 0 && e.hp <= e.maxHp, `${e.kind}#${e.id} vivant avec ${e.hp} / ${e.maxHp}`);
        const v = geometryViolation(g.room, e.x, e.y, e.r);
        assert.equal(v, null, `${e.kind}#${e.id} ${v} (${e.x.toFixed(1)}, ${e.y.toFixed(1)})`);
        if (cover[e.kind] !== undefined) cover[e.kind]++;
        if (e.hidden) {
          cover.hidden++;
          assert.ok(e.kind === 'stalker' && e.spawnT > 0 && !e.tele, 'disparu : hors du jeu');
          assert.ok(!g.hazards.some((h) => h.sourceId === e.id && !h.done), 'disparu : aucune zone à lui');
        }
        if (wardOf(g, e)) cover.warded++;
      }
    });
  }
  for (const [k, n] of Object.entries(cover)) assert.ok(n > 0, `couverture : ${k} jamais vu (${JSON.stringify(cover)})`);
});

test('la salle se termine toujours : aux étages où ils apparaissent, chaque combat joué par un bot finit (salle nettoyée ou héros mort)', () => {
  const MAX_SECONDS = 180;
  const seen = new Set();
  for (const policy of ['skilled', 'noDash']) {
    for (let seed = 1; seed <= 6; seed++) {
      for (const floor of [10, 12, 14, 16]) {
        const g = createGame({ seed, startFloor: floor });
        const mem = {};
        let i = 0;
        for (; i < MAX_SECONDS * SEC && g.mode === 'play' && !g.room.cleared; i++) {
          stepGame(g, POLICIES[policy](g, mem));
          for (const e of g.enemies) seen.add(e.kind);
          g.events.length = 0;
        }
        assert.ok(g.room.cleared || g.mode !== 'play', `${policy}, graine ${seed}, étage ${floor} : salle toujours en cours après ${MAX_SECONDS} s (${g.enemies.filter((e) => !e.dead).map((e) => e.kind).join(', ')})`);
      }
    }
  }
  for (const kind of NEW_KINDS) assert.ok(seen.has(kind), `couverture : ${kind} jamais rencontré`);
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

test('audio : cris d\'attaque du pavois et du traqueur, coup arrêté par le pavois, frappe du traqueur — sans erreur WebAudio', async () => {
  const audio = createAudio({ AudioContext: fakeAudioContextClass(), navigator: {}, now: () => 0 });
  audio.unlock();
  await Promise.resolve();
  const game = { player: { x: 500, y: 400 } };
  audio.handleEvents([
    ...['pavois', 'stalker'].map((enemy) => ({ type: 'enemyAttack', id: 1, x: 600, y: 400, enemy })),
    { type: 'deflect', x: 600, y: 400, guard: true },
    { type: 'hazardFire', id: 2, kind: 'stalker', shape: 'circle', x: 600, y: 400, r: 82, angle: 0, length: 0, width: 0 },
    ...NEW_KINDS.map((enemy) => ({ type: 'hit', id: 3, x: 600, y: 400, amount: 12, crit: false, kind: 'melee', enemy, shake: 0 })),
    { type: 'kill', id: 3, x: 600, y: 400, enemy: 'banner', elite: false, boss: false, kind: 'melee' },
  ], game);
  const st = audio.getStats();
  assert.equal(st.errors, 0, st.lastError);
  assert.ok(st.played >= 4, `sons joués : ${st.played}`);
});

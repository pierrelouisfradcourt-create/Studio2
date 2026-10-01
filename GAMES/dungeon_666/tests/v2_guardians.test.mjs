// Lot « Gardiens » de la V2 — fichier CRÉÉ dans cette passe (aucun test existant modifié).
// Contrat des Gardiens ajoutés (Cerbère, Minos, Éphialte) à côté de Charon :
//   - rotation : chaque modèle garde l'étage du Gardien de sa section ;
//   - chaque pattern de chaque phase se joue jusqu'au bout, télégraphié >= GUARDIAN_MIN_TELE ;
//   - tout coup reçu vient d'une attaque télégraphiée (aucun dégât de contact) ;
//   - transitions de phase ; rien ne survit à la mort ; déterminisme ;
//   - la profondeur change PV et dégâts, jamais la durée d'un télégraphe ;
//   - équité mesurée par les bots (le skilled gagne, le sans-dash souffre nettement plus) ;
//   - recréation, pour la V2 (étage 18), des trois tests de feel_review cassés par les sections
//     de 18 (alerte de l'anneau entre les vagues, alerte d'invocation inoffensive, plafond de gel).
// Lancement : node --test tests/*.test.mjs

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createGame, stepGame, emptyInput, DT } from '../src/sim/game.mjs';
import { damageEnemy } from '../src/sim/combat.mjs';
import { sectionBounds, guardianFor } from '../src/sim/floors.mjs';
import { BOSS_MODELS } from '../src/sim/boss.mjs';
import { setState } from '../src/sim/boss_common.mjs';
import { EXTRA_BOSSES, GUARDIAN_ROTATION, GUARDIAN_MIN_TELE } from '../src/sim/boss_data.mjs';
import { generateItem } from '../src/sim/loot.mjs';
import { POLICIES } from '../tools/bots.mjs';

const NEW_MODELS = Object.keys(EXTRA_BOSSES);
const ALL_MODELS = ['gardien', ...NEW_MODELS];
const EPS = 1e-9;
const UNIT_FLOOR = 18; // étage du 1er Gardien : les tests unitaires y forcent chaque modèle
const PATTERN_CAP = 12; // s : au-delà, un pattern « ne finit pas »
const STRIKE_LAG = 0.25; // s : un coup au corps part au plus tard ce délai après la fin de son télégraphe
const ticks = (seconds) => Math.ceil(seconds / DT);
const input = (over = {}) => ({ ...emptyInput(), ...over });

// Sources de dégâts déclarées par modèle : zones (hazard.kind), coups au corps (télégraphe
// e.tele avant), projectiles. Tout autre source de dégâts pendant un combat de Gardien = bug.
const ATTACKS = {
  gardien: { hazards: ['bossSlam'], body: ['bossCharge'], shots: ['bossOrb'] },
  cerbere: { hazards: ['cerbereLand', 'cerbereShock', 'cerbereFlame', 'cerbereFire'], body: ['cerbereBite'], shots: [] },
  minos: { hazards: ['minosSentence', 'minosTile', 'minosSeal'], body: ['minosWhip'], shots: [] },
  colosse: { hazards: ['colosseFist', 'colosseQuake', 'colosseRock', 'colosseEmber'], body: [], shots: [] },
};
// Dégâts des serviteurs (renforts, geôliers) : ce sont des ennemis ordinaires, télégraphiés ailleurs.
const ADD_DAMAGE = { imp: 'imp', archer: 'arrow', exploder: 'exploder', brute: 'brute', charger: 'charger' };

function addKinds(t, kind) {
  const d = t.boss[kind];
  const kinds = [...(d.reinforcements[2] ?? []), ...(d.reinforcements[3] ?? [])];
  if (d.summon) kinds.push(d.summon.kind);
  if (d.geoliers) kinds.push(d.geoliers.kind);
  return kinds.map((k) => ADD_DAMAGE[k] ?? k);
}

/** Partie d'entraînement contre le modèle `kind` (rotation forcée), Gardien apparu. */
function bossGame(kind, { seed = 3, floor = UNIT_FLOOR, items } = {}) {
  const g = createGame({ seed, startFloor: floor, practice: true, items, tuning: { guardians: { rotation: [kind] } } });
  for (let i = 0; i < 240 && !g.enemies.some((e) => e.boss && !(e.spawnT > 0)); i++) stepGame(g, input());
  const boss = g.enemies.find((e) => e.boss);
  assert.ok(boss, `${kind} : Gardien présent`);
  assert.equal(boss.kind, kind);
  return { g, boss };
}

/** Gardien seul, phase et pattern imposés ; héros posé à distance (invulnérable si demandé). */
function isolate(g, boss, { phase = 1, pattern = 'rest', invulnerable = true } = {}) {
  g.enemies = [boss];
  g.spawns.length = 0;
  g.hazards.length = 0;
  g.projectiles.length = 0;
  g.pickups.length = 0;
  boss.phase = phase;
  boss.invuln = 0;
  boss.tele = null;
  boss.restFor = undefined;
  setState(boss, pattern);
  boss.pattern = pattern;
  const p = g.player;
  p.x = Math.min(g.room.w - 120, boss.x + 260);
  p.y = Math.min(g.room.h - 120, boss.y + 160);
  if (invulnerable) p.iframes = 1e9;
  g.events.length = 0;
}

/**
 * Joue la partie en notant ce qu'émet le Gardien : zones (délai de télégraphe), durées de ses
 * télégraphes « qui font mal » (e.tele non inoffensif), invocations, cris (son), coups reçus.
 */
function observe(g, boss, seconds, { policy = null, until = null } = {}) {
  const rec = { hazards: new Map(), teleRuns: [], summons: 0, cues: 0, hurts: [], finished: false, events: [] };
  let run = 0;
  let lastEnd = -Infinity;
  let lastLen = 0;
  const mem = {};
  for (let i = 0; i < ticks(seconds); i++) {
    if (g.mode !== 'play') break;
    stepGame(g, policy ? POLICIES[policy](g, mem) : input());
    for (const h of g.hazards) {
      if (h.sourceId === boss.id && !rec.hazards.has(h.id)) rec.hazards.set(h.id, { kind: h.kind, delay: h.delay, damage: h.damage, shape: h.shape });
    }
    if (boss.tele && !boss.tele.harmless) run += DT;
    else if (run > 0) {
      rec.teleRuns.push(run);
      lastEnd = g.time;
      lastLen = run;
      run = 0;
    }
    for (const ev of g.events) {
      rec.events.push(ev);
      if (ev.type === 'enemyAttack' && ev.id === boss.id) rec.cues++;
      if (ev.type === 'bossSummon' && ev.id === boss.id) rec.cues++;
      if (ev.type === 'spawnWarn') rec.summons++;
      if (ev.type === 'playerHurt') rec.hurts.push({ source: ev.source, time: g.time, teleLen: lastLen, sinceTele: g.time - lastEnd, teleNow: run });
    }
    g.events.length = 0;
    if (until && until()) {
      rec.finished = true;
      break;
    }
  }
  if (run > 0) rec.teleRuns.push(run);
  return rec;
}

function sectionOf(t, kind) {
  for (let s = 1; s <= Math.ceil(t.floors.total / t.floors.sectionLength); s++) if (guardianFor(t, s) === kind) return s;
  return -1;
}

/** Équipement « à la profondeur » : arme et armure communes du niveau de l'étage (le minimum
 *  qu'un joueur arrivé là porte ; l'entraînement utilise sinon le profil, ici neuf). */
function depthItems(floor) {
  const probe = createGame({ seed: 1, startFloor: 1, practice: true });
  return {
    arme: generateItem(probe, { slot: 'arme', rarity: 'commun', floor }),
    armure: generateItem(probe, { slot: 'armure', rarity: 'commun', floor }),
  };
}

// ---------------------------------------------------------------- rotation et données

test('rotation : section 1 = Charon, puis au moins 3 nouveaux modèles, chacun à l\'étage du Gardien de sa section', () => {
  const t = createGame({ seed: 1 }).tuning;
  assert.equal(GUARDIAN_ROTATION[0], 'gardien');
  assert.ok(NEW_MODELS.length >= 3, `nouveaux modèles : ${NEW_MODELS.join(', ')}`);
  for (const kind of NEW_MODELS) {
    assert.ok(GUARDIAN_ROTATION.includes(kind), `${kind} absent de la rotation`);
    assert.ok(BOSS_MODELS[kind], `${kind} : modèle non enregistré (boss_models.mjs)`);
    assert.ok(t.boss[kind], `${kind} : données absentes de tuning.boss (boss_data.mjs)`);
  }
  const sections = Math.ceil(t.floors.total / t.floors.sectionLength);
  const seen = {};
  for (let s = 1; s <= sections; s++) seen[guardianFor(t, s)] = (seen[guardianFor(t, s)] ?? 0) + 1;
  for (const kind of ALL_MODELS) assert.ok(seen[kind] >= 9, `${kind} garde ${seen[kind]} sections sur ${sections}`);
  // Le VRAI jeu (sans rotation forcée) : chaque modèle apparaît à l'étage du Gardien de sa section.
  for (let s = 1; s <= GUARDIAN_ROTATION.length + 1; s++) {
    const floor = sectionBounds(t, s).guardian;
    const g = createGame({ seed: s, startFloor: floor });
    assert.equal(g.info.isBoss, true, `étage ${floor} : salle de Gardien`);
    const boss = g.enemies.find((e) => e.boss);
    assert.ok(boss, `étage ${floor} : Gardien présent`);
    assert.equal(boss.kind, guardianFor(t, s), `section ${s}`);
    assert.equal(boss.kind, GUARDIAN_ROTATION[(s - 1) % GUARDIAN_ROTATION.length]);
  }
});

test('données : 3 phases (seuils en tuning), 3 à 5 patterns par modèle, chacun chiffré dans le tuning', () => {
  const t = createGame({ seed: 1 }).tuning;
  for (const kind of NEW_MODELS) {
    const d = t.boss[kind];
    const model = BOSS_MODELS[kind];
    assert.ok(d.phase2At > d.phase3At && d.phase3At > 0 && d.phase2At < 1, `${kind} : seuils de phase`);
    const names = new Set([...model.byPhase[1], ...model.byPhase[2], ...model.byPhase[3]]);
    assert.ok(names.size >= 3 && names.size <= 5, `${kind} : ${names.size} patterns`);
    for (const name of names) {
      assert.equal(typeof model.patterns[name], 'function', `${kind}/${name} : pas de code`);
      assert.ok(d[name] && typeof d[name] === 'object', `${kind}/${name} : pas de données de tuning`);
    }
    for (const field of ['hp', 'radius', 'speed', 'hitstopCap', 'transition', 'phaseHealOrb']) assert.ok(d[field] > 0, `${kind}.${field}`);
    // Les patterns de Charon ne se retrouvent pas tels quels : identité propre.
    for (const name of names) assert.ok(!BOSS_MODELS.gardien.patterns[name], `${kind}/${name} : copie d'un pattern de Charon`);
  }
});

// ---------------------------------------------------------------- patterns

for (const kind of NEW_MODELS) {
  test(`${kind} : chaque pattern de chaque phase se joue jusqu'au bout, menace télégraphiée >= ${GUARDIAN_MIN_TELE} s`, () => {
    const model = BOSS_MODELS[kind];
    const covered = new Set();
    for (const phase of [1, 2, 3]) {
      for (const name of model.byPhase[phase]) {
        const { g, boss } = bossGame(kind);
        isolate(g, boss, { phase, pattern: name });
        const rec = observe(g, boss, PATTERN_CAP, { until: () => boss.state === 'rest' });
        const where = `${kind}/${name} (phase ${phase})`;
        assert.ok(rec.finished, `${where} : le pattern ne rend jamais la main`);
        const threats = rec.hazards.size + rec.teleRuns.length + rec.summons;
        assert.ok(threats > 0, `${where} : aucune menace produite`);
        for (const h of rec.hazards.values()) assert.ok(h.delay >= GUARDIAN_MIN_TELE - EPS, `${where} : zone ${h.kind} télégraphiée ${h.delay} s`);
        for (const r of rec.teleRuns) assert.ok(r >= GUARDIAN_MIN_TELE - EPS, `${where} : télégraphe affiché ${r.toFixed(3)} s`);
        assert.ok(rec.cues > 0, `${where} : aucun signal sonore (enemyAttack / bossSummon)`);
        covered.add(name);
      }
    }
    assert.equal(covered.size, Object.keys(model.patterns).length, `${kind} : patterns jamais joués`);
  });
}

// ---------------------------------------------------------------- lisibilité : aucun coup sans télégraphe

for (const kind of ALL_MODELS) {
  test(`${kind} : tout coup reçu vient d'une attaque télégraphiée (zones, coups au corps annoncés, serviteurs)`, () => {
    const { g, boss } = bossGame(kind, { seed: 5 });
    const t = g.tuning;
    const p = g.player;
    // Héros increvable qui MARTÈLE au contact (le pire cas pour la lisibilité) : il encaisse tout.
    p.maxHp = 1e7;
    p.hp = 1e7;
    const rec = observe(g, boss, 150, { policy: 'masher', until: () => boss.dead });
    const a = ATTACKS[kind];
    const allowed = new Set([...a.hazards, ...a.body, ...a.shots, ...addKinds(t, kind)]);
    assert.ok(rec.hurts.length > 0, `${kind} : le marteleur n'a jamais été touché (test sans objet)`);
    for (const h of rec.hurts) {
      assert.ok(allowed.has(h.source), `${kind} : dégâts de source inattendue « ${h.source} » (contact ?)`);
      if (a.body.includes(h.source) && h.source !== 'bossCharge') {
        const len = h.teleNow > 0 ? h.teleNow : h.teleLen;
        assert.ok(len >= GUARDIAN_MIN_TELE - DT - EPS, `${kind} : ${h.source} après un télégraphe de ${len.toFixed(3)} s`);
        assert.ok(h.teleNow > 0 || h.sinceTele <= STRIKE_LAG + EPS, `${kind} : ${h.source} ${h.sinceTele.toFixed(3)} s après la fin de son télégraphe`);
      }
    }
    for (const h of rec.hazards.values()) assert.ok(h.delay >= GUARDIAN_MIN_TELE - EPS, `${kind} : zone ${h.kind} de ${h.delay} s`);
  });
}

for (const kind of NEW_MODELS) {
  test(`${kind} : au repos, se coller à lui ne blesse jamais (aucun dégât de contact)`, () => {
    const { g, boss } = bossGame(kind);
    isolate(g, boss, { phase: 3, pattern: 'rest', invulnerable: false });
    boss.restFor = 4;
    let hurt = 0;
    for (let i = 0; i < ticks(4) && boss.state === 'rest'; i++) {
      g.player.x = boss.x + boss.r * 0.5;
      g.player.y = boss.y;
      stepGame(g, input());
      hurt += g.events.filter((ev) => ev.type === 'playerHurt').length;
      g.events.length = 0;
    }
    assert.equal(hurt, 0);
  });
}

// ---------------------------------------------------------------- phases

for (const kind of NEW_MODELS) {
  test(`${kind} : transitions de phase (seuils du tuning, invulnérable, menaces effacées, renforts, orbe)`, () => {
    const { g, boss } = bossGame(kind);
    const d = g.tuning.boss[kind];
    for (const [phase, at] of [[2, d.phase2At], [3, d.phase3At]]) {
      isolate(g, boss, { phase: phase - 1, pattern: BOSS_MODELS[kind].byPhase[phase - 1][0] });
      observe(g, boss, 0.3);
      assert.ok(g.hazards.some((h) => h.hitsPlayer) || boss.tele || boss.sub, `${kind} : un pattern est en cours`);
      boss.hp = Math.floor(boss.maxHp * at) - 1;
      const pickups = g.pickups.length;
      stepGame(g, input());
      assert.equal(boss.phase, phase, `${kind} : phase ${phase}`);
      assert.equal(boss.state, 'roar');
      assert.ok(boss.invuln > 0, 'invulnérable pendant la transition');
      assert.ok(g.events.some((ev) => ev.type === 'bossPhase' && ev.phase === phase));
      assert.equal(g.hazards.filter((h) => h.hitsPlayer && !h.done).length, 0, 'zones effacées');
      assert.equal(g.projectiles.filter((pr) => pr.owner === 'enemy').length, 0, 'projectiles effacés');
      assert.ok(g.pickups.length > pickups, 'orbe de soin');
      assert.equal(g.spawns.length, (d.reinforcements[phase] ?? []).length, 'renforts du tuning');
      assert.equal(damageEnemy(g, boss, { kind: 'melee', amount: 50, dirX: 1, dirY: 0 }), 0, 'le coup ne porte pas');
      g.events.length = 0;
      // La transition finie, il reprend un pattern de SA nouvelle phase.
      g.spawns.length = 0;
      observe(g, boss, d.transition + 0.2, { until: () => boss.state !== 'roar' });
      assert.ok(BOSS_MODELS[kind].byPhase[phase].includes(boss.state), `${kind} : ${boss.state} hors de la phase ${phase}`);
    }
  });
}

// ---------------------------------------------------------------- mort

for (const kind of NEW_MODELS) {
  test(`${kind} : à sa mort, aucune menace ne survit (zones, braises, serviteurs, projectiles)`, () => {
    const { g, boss } = bossGame(kind);
    const model = BOSS_MODELS[kind];
    // Phase 3 : on enchaîne ses patterns jusqu'à avoir des menaces en attente, puis on le tue.
    isolate(g, boss, { phase: 3, pattern: model.byPhase[3][0] });
    let pending = 0;
    for (const name of model.byPhase[3]) {
      if (boss.dead) break;
      setState(boss, name);
      boss.pattern = name;
      observe(g, boss, 0.5);
      pending = g.hazards.filter((h) => h.hitsPlayer && !h.done).length;
    }
    if (kind === 'colosse') {
      // Braises allumées (éboulis en phase 3) et geôliers en jeu.
      setState(boss, 'eboulis');
      observe(g, boss, 1.8);
      assert.ok((boss.pools ?? []).length > 0, 'des braises brûlent');
      pending = g.hazards.filter((h) => h.hitsPlayer && !h.done).length;
    }
    assert.ok(pending > 0 || boss.tele, `${kind} : aucune menace en attente avant la mort (test sans objet)`);
    boss.invuln = 0;
    boss.shielded = false;
    boss.hidden = false;
    damageEnemy(g, boss, { kind: 'melee', amount: 1e9, dirX: 1, dirY: 0 });
    assert.ok(boss.dead, 'le Gardien est mort');
    g.player.iframes = 0;
    // Le coup fatal fige la scène (gel de mort du Gardien) : rien n'avance pendant ce gel, puis
    // le premier pas de simulation annule tout ce qu'il avait lancé.
    for (let i = 0; i < ticks(g.tuning.killHitstop.boss) + 2; i++) {
      stepGame(g, input());
      assert.ok(!g.events.some((ev) => ev.type === 'playerHurt'), `${kind} : coup reçu pendant le gel de mort`);
      g.events.length = 0;
    }
    assert.equal(g.hazards.filter((h) => h.hitsPlayer && !h.done).length, 0, 'zones annulées');
    assert.equal(g.projectiles.filter((pr) => pr.owner === 'enemy' && !pr.dead).length, 0, 'projectiles annulés');
    assert.equal(g.enemies.filter((e) => !e.dead).length + g.spawns.length, 0, 'serviteurs morts avec lui');
    assert.ok(g.room.cleared, 'salle nettoyée');
    g.events.length = 0;
    const kinds = new Set(ATTACKS[kind].hazards);
    for (let i = 0; i < ticks(3) && g.mode === 'play'; i++) {
      stepGame(g, input());
      for (const ev of g.events) {
        assert.notEqual(ev.type, 'playerHurt', `${kind} : coup reçu après sa mort (${ev.source})`);
        assert.ok(!(ev.type === 'hazardFire' && kinds.has(ev.kind)), `${kind} : ${ev.kind} frappe après sa mort`);
        assert.ok(!(ev.type === 'enemyAttack' && ev.id === boss.id), `${kind} : attaque d'un Gardien mort`);
      }
      g.events.length = 0;
    }
  });
}

// ---------------------------------------------------------------- déterminisme et profondeur

for (const kind of NEW_MODELS) {
  test(`${kind} : déterministe (même graine, mêmes entrées => même combat)`, () => {
    const digest = () => {
      const { g, boss } = bossGame(kind, { seed: 11 });
      const mem = {};
      const trace = [];
      for (let i = 0; i < ticks(45) && g.mode === 'play'; i++) {
        stepGame(g, POLICIES.skilled(g, mem));
        g.events.length = 0;
        if (i % 30 === 0) trace.push([boss.x, boss.y, boss.hp, boss.phase, boss.state, g.player.x, g.player.y, g.player.hp, g.hazards.length].join(','));
      }
      return trace.join(';');
    };
    assert.equal(digest(), digest());
  });
}

test('la profondeur change PV et dégâts, JAMAIS la durée d\'un télégraphe (phase 3, étage 18 contre 666)', () => {
  for (const kind of NEW_MODELS) {
    for (const name of BOSS_MODELS[kind].byPhase[3]) {
      const sample = (floor) => {
        const { g, boss } = bossGame(kind, { seed: 9, floor });
        isolate(g, boss, { phase: 3, pattern: name });
        const rec = observe(g, boss, PATTERN_CAP, { until: () => boss.state === 'rest' });
        const delays = [...rec.hazards.values()].map((h) => h.delay.toFixed(4)).sort();
        const damage = [...rec.hazards.values()].reduce((s, h) => s + h.damage, 0);
        return { delays, teles: rec.teleRuns.map((r) => r.toFixed(3)), damage, hp: boss.maxHp };
      };
      const shallow = sample(UNIT_FLOOR);
      const deep = sample(666);
      assert.deepEqual(deep.delays, shallow.delays, `${kind}/${name} : télégraphes des zones`);
      assert.deepEqual(deep.teles, shallow.teles, `${kind}/${name} : télégraphes au corps`);
      assert.ok(deep.hp > shallow.hp, `${kind} : PV plus hauts en profondeur`);
      if (shallow.damage > 0) assert.ok(deep.damage > shallow.damage, `${kind}/${name} : dégâts plus hauts en profondeur`);
    }
  }
});

// ---------------------------------------------------------------- contre-jeu propre à chaque modèle

test('cerbere : le bond retombe sur le cercle annoncé ; en l\'air il ne blesse pas ; épuisé il est exposé', () => {
  const { g, boss } = bossGame('cerbere');
  isolate(g, boss, { phase: 1, pattern: 'bond', invulnerable: false });
  const p = g.player;
  const target = { x: p.x, y: p.y };
  let airborneTicks = 0;
  let hurtInAir = 0;
  for (let i = 0; i < ticks(3) && boss.state === 'bond'; i++) {
    // Le héros reste dans la trajectoire du bond (sous le saut), hors du cercle d'atterrissage.
    if (boss.airborne) {
      airborneTicks++;
      p.x = boss.x;
      p.y = boss.y;
    } else if (!g.hazards.length) {
      p.x = target.x;
      p.y = target.y;
    } else {
      p.x = Math.max(60, target.x - 300);
    }
    stepGame(g, input());
    if (boss.airborne) hurtInAir += g.events.filter((ev) => ev.type === 'playerHurt').length;
    g.events.length = 0;
    if (boss.sub === 'recover') break;
  }
  assert.ok(airborneTicks > 0, 'il a bondi');
  assert.equal(hurtInAir, 0, 'aucun dégât de contact en l\'air');
  assert.ok(Math.hypot(boss.x - target.x, boss.y - target.y) < boss.r + 1, 'il retombe au centre du cercle annoncé');
  assert.equal(boss.sub, 'recover');
  assert.ok(boss.vuln > 0, 'essoufflé : point faible exposé');
});

test('minos : la brèche du fouet protège, le reste du cercle frappe ; dissous il est intouchable', () => {
  const hitAt = (inBreach) => {
    const { g, boss } = bossGame('minos');
    isolate(g, boss, { phase: 1, pattern: 'fouet', invulnerable: false });
    stepGame(g, input());
    const p = g.player;
    const a = inBreach ? boss.breachAngle : boss.breachAngle + Math.PI;
    let hurt = 0;
    for (let i = 0; i < ticks(1.2) && boss.state === 'fouet' && boss.patternStep === 0; i++) {
      p.x = boss.x + Math.cos(a) * 120;
      p.y = boss.y + Math.sin(a) * 120;
      stepGame(g, input());
      hurt += g.events.filter((ev) => ev.type === 'playerHurt' && ev.source === 'minosWhip').length;
      g.events.length = 0;
    }
    return hurt;
  };
  assert.equal(hitAt(true), 0, 'dans la brèche : épargné');
  assert.equal(hitAt(false), 1, 'hors de la brèche : touché');
  const { g, boss } = bossGame('minos');
  isolate(g, boss, { phase: 2, pattern: 'sceau' });
  stepGame(g, input());
  assert.equal(boss.hidden, true);
  assert.equal(damageEnemy(g, boss, { kind: 'melee', amount: 50, dirX: 1, dirY: 0 }), 0, 'dissous : intouchable');
  const ring = g.hazards.find((h) => h.kind === 'minosSeal');
  assert.ok(ring && ring.shape === 'ring' && ring.inner > g.player.r * 2, 'couronne avec un centre sûr');
});

test('colosse : geôliers = bouclier tant qu\'ils vivent ; poing = point faible ; braises bornées', () => {
  const { g, boss } = bossGame('colosse');
  const d = g.tuning.boss.colosse;
  isolate(g, boss, { phase: 2, pattern: 'geoliers' });
  observe(g, boss, d.geoliers.windup + 0.1);
  assert.equal(boss.shielded, true, 'chaînes levées');
  assert.equal(damageEnemy(g, boss, { kind: 'melee', amount: 50, dirX: 1, dirY: 0 }), 0, 'invulnérable sous bouclier');
  observe(g, boss, 1.0);
  const jailers = g.enemies.filter((e) => e.summoned && !e.dead);
  assert.equal(jailers.length, d.geoliers.countByPhase[1], 'geôliers en jeu');
  for (const e of jailers) damageEnemy(g, e, { kind: 'melee', amount: 1e6, dirX: 1, dirY: 0 });
  stepGame(g, input());
  assert.equal(boss.shielded, false, 'geôliers tombés : chaînes brisées');
  assert.ok(damageEnemy(g, boss, { kind: 'melee', amount: 50, dirX: 1, dirY: 0 }) > 0, 'il redevient vulnérable');
  // Bouclier borné dans le temps même si un geôlier se cache.
  isolate(g, boss, { phase: 2, pattern: 'geoliers' });
  observe(g, boss, d.geoliers.windup + d.geoliers.shieldMax + 1.5, { until: () => !boss.shielded && boss.state !== 'geoliers' && g.enemies.some((e) => e.summoned) });
  observe(g, boss, d.geoliers.shieldMax + 0.5);
  assert.equal(boss.shielded, false, `bouclier tenu au plus ${d.geoliers.shieldMax} s`);
  // Poing : après le dernier coup, point faible exposé — les dégâts reçus sont majorés.
  isolate(g, boss, { phase: 1, pattern: 'poing' });
  boss.vuln = 0;
  boss.vulnMult = 0;
  const base = damageEnemy(g, boss, { kind: 'wall', amount: 100 });
  observe(g, boss, PATTERN_CAP, { until: () => boss.sub === 'recover' });
  assert.ok(boss.vuln > 0, 'bras coincé : exposé');
  const exposed = damageEnemy(g, boss, { kind: 'wall', amount: 100 });
  assert.ok(exposed >= base * (1 + d.poing.exposedMult) - 1, `exposé ${exposed} contre ${base}`);
  // Braises : jamais plus de poolMax, et elles s'éteignent.
  isolate(g, boss, { phase: 3, pattern: 'eboulis' });
  boss.pools = [];
  for (let k = 0; k < 3; k++) {
    setState(boss, 'eboulis');
    observe(g, boss, 1.7);
  }
  assert.ok(boss.pools.length > 0 && boss.pools.length <= d.eboulis.poolMax, `braises : ${boss.pools.length}`);
  assert.ok(g.hazards.some((h) => h.kind === 'colosseEmber'), 'une braise pulse');
  isolate(g, boss, { phase: 3, pattern: 'rest' });
  boss.restFor = 99;
  observe(g, boss, d.eboulis.poolLife + d.eboulis.poolPulse + 0.5);
  assert.equal(boss.pools.length, 0, 'braises éteintes après poolLife');
});

// ---------------------------------------------------------------- équité (bots)

test('équité : en entraînement à SA profondeur, le bot skilled bat chaque nouveau Gardien ; sans dash, il souffre nettement plus', () => {
  const t = createGame({ seed: 1 }).tuning;
  const SEEDS = [1, 2, 3, 4, 5];
  const MIN_DASH_VALUE = 2;
  for (const kind of NEW_MODELS) {
    const floor = sectionBounds(t, sectionOf(t, kind)).guardian;
    const items = depthItems(floor);
    const fight = (policy, seed) => {
      const g = createGame({ seed, startFloor: floor, practice: true, items });
      const boss = g.enemies.find((e) => e.boss);
      assert.equal(boss.kind, kind, `étage ${floor} : ${kind}`);
      const mem = {};
      for (let i = 0; i < ticks(300) && g.mode === 'play' && !g.room.cleared && g.player.state !== 'dead'; i++) {
        stepGame(g, POLICIES[policy](g, mem));
        g.events.length = 0;
      }
      return { won: g.room.cleared, dps: g.telemetry.damageTaken / Math.max(1, g.time) };
    };
    const skilled = SEEDS.map((s) => fight('skilled', s));
    const noDash = SEEDS.map((s) => fight('noDash', s));
    const wins = skilled.filter((r) => r.won).length;
    assert.ok(wins > SEEDS.length / 2, `${kind} (étage ${floor}) : le skilled gagne ${wins}/${SEEDS.length}`);
    const mean = (rs) => rs.reduce((a, r) => a + r.dps, 0) / rs.length;
    const ratio = mean(noDash) / Math.max(1e-6, mean(skilled));
    assert.ok(ratio >= MIN_DASH_VALUE, `${kind} : sans dash ×${ratio.toFixed(2)} de dégâts reçus par seconde`);
    assert.ok(noDash.filter((r) => r.won).length < wins, `${kind} : sans dash il gagne autant`);
  }
});

// Copie de la liste de tests/properties_strict.test.mjs (champs invisibles pour un joueur) : les
// lectures ajoutées au bot pour ces Gardiens (airborne, hidden, shielded, tele.area, vuln) sont
// des indices DESSINÉS (art_bosses.mjs, hud.mjs), pas des compteurs cachés.
const FORBIDDEN_READS = [
  'game.rng', 'game.nextId',
  'enemies[].cooldown', 'enemies[].stateTime', 'enemies[].atkId', 'enemies[].hitPlayer',
  'enemies[].pattern', 'enemies[].patternT', 'enemies[].patternStep', 'enemies[].restFor',
  'enemies[].strafe', 'enemies[].flank', 'enemies[].dirX', 'enemies[].dirY',
  'enemies[].dmgScale', 'enemies[].burnAcc', 'enemies[].bornAt',
  // Propres aux Gardiens ajoutés : chronomètres et plans internes.
  'enemies[].sub', 'enemies[].subT', 'enemies[].leap', 'enemies[].shieldT', 'enemies[].pools',
  'enemies[].breachAngle', 'enemies[].sealX', 'enemies[].sealY', 'enemies[].sweepEnd', 'enemies[].rockEnd',
];

/** Proxy en lecture seule qui note chaque chemin lu (même principe que properties_strict). */
function observer(reads) {
  const cache = new WeakMap();
  const wrap = (obj, path) => {
    if (obj === null || typeof obj !== 'object' || ArrayBuffer.isView(obj)) return obj;
    if (cache.has(obj)) return cache.get(obj);
    const proxy = new Proxy(obj, {
      get(target, key, receiver) {
        const value = Reflect.get(target, key, receiver);
        if (typeof key === 'symbol' || typeof value === 'function') return value;
        const sub = Array.isArray(target) && /^\d+$/.test(key) ? `${path}[]` : `${path}.${key}`;
        reads.add(sub.replace(/^game\.(enemies|hazards|projectiles|spawns|pickups)\[\]/, '$1[]'));
        return wrap(value, sub);
      },
      set(target, key) {
        throw new Error(`le bot ÉCRIT dans l'état de la partie : ${path}.${String(key)}`);
      },
      deleteProperty(target, key) {
        throw new Error(`le bot SUPPRIME un champ de l'état : ${path}.${String(key)}`);
      },
    });
    cache.set(obj, proxy);
    return proxy;
  };
  return (game) => wrap(game, 'game');
}

test('bots : face aux nouveaux Gardiens, ils ne lisent que ce qui est dessiné et n\'écrivent jamais', () => {
  for (const kind of NEW_MODELS) {
    for (const name of Object.keys(POLICIES)) {
      const reads = new Set();
      const { g } = bossGame(kind, { seed: 4 });
      const view = observer(reads)(g);
      const mem = {};
      for (let i = 0; i < ticks(25) && g.mode === 'play'; i++) {
        stepGame(g, POLICIES[name](view, mem));
        g.events.length = 0;
      }
      const cheats = [...reads].filter((r) => FORBIDDEN_READS.some((f) => r === f || r.startsWith(`${f}.`)));
      assert.deepEqual(cheats, [], `${name} contre ${kind} lit : ${cheats.join(', ')}`);
      assert.ok(reads.has('enemies[].x'), `${name} contre ${kind} : l'audit doit observer des lectures d'ennemis`);
      if (name !== 'masher') assert.ok(reads.has('enemies[].tele'), `${name} contre ${kind} : l'audit doit observer la lecture des télégraphes`);
    }
  }
});

// ---------------------------------------------------------------- recréation V2 de feel_review (étage 18)

/** Gardien de la section 1 (étage 18, run normal), seul, en début de pattern donné. */
function guardianIn(pattern, phase = 1) {
  const t = createGame({ seed: 3 }).tuning;
  const g = createGame({ seed: 3, startFloor: sectionBounds(t, 1).guardian });
  g.spawns.length = 0;
  for (let i = 0; i < 200 && !g.enemies.some((e) => e.boss && !(e.spawnT > 0)); i++) stepGame(g, input());
  const boss = g.enemies.find((e) => e.boss);
  assert.ok(boss, 'Gardien présent à l\'étage 18');
  g.enemies = [boss];
  boss.phase = phase;
  boss.state = pattern;
  boss.stateTime = 0;
  boss.patternStep = 0;
  boss.patternT = 0;
  boss.tele = null;
  g.player.x = boss.x + 400;
  g.player.y = boss.y;
  g.player.iframes = 99;
  g.events.length = 0;
  return { g, boss };
}

test('V2 (étage 18) — anneau du Gardien : le cercle d\'alerte reste affiché entre les vagues', () => {
  const { g, boss } = guardianIn('ring');
  const r = g.tuning.boss[boss.kind].ring;
  let waves = 0;
  let missing = 0;
  for (let i = 0; i < 600 && boss.state === 'ring'; i++) {
    stepGame(g, input());
    const fired = g.events.filter((ev) => ev.type === 'enemyAttack' && ev.enemy === 'bossRing').length;
    g.events.length = 0;
    waves += fired;
    if (waves >= 1 && boss.state === 'ring' && !fired && !(boss.tele && boss.tele.shape === 'circle' && boss.tele.r === r.teleRadius)) missing++;
  }
  assert.equal(waves, r.waves, 'toutes les vagues de la phase 1 sont parties');
  assert.equal(missing, 0, `${missing} ticks sans alerte entre deux vagues`);
});

test('V2 (étage 18) — invocations des Gardiens : alertes marquées inoffensives (le rouge reste « ça fait mal »)', () => {
  const { g, boss } = guardianIn('summon', 3);
  stepGame(g, input());
  assert.ok(boss.tele, 'alerte affichée');
  assert.equal(boss.tele.harmless, true);
  // Les autres alertes sans danger des nouveaux Gardiens : appel des geôliers, incantations de Minos.
  for (const [kind, pattern, phase] of [['colosse', 'geoliers', 2], ['minos', 'sentence', 1], ['minos', 'jugement', 1]]) {
    const b = bossGame(kind);
    isolate(b.g, b.boss, { phase, pattern });
    stepGame(b.g, input());
    assert.ok(b.boss.tele, `${kind}/${pattern} : alerte affichée`);
    assert.equal(b.boss.tele.harmless, true, `${kind}/${pattern} : alerte inoffensive`);
    assert.equal(b.boss.tele.shape, 'circle');
  }
});

test('V2 (étage 18) — gel d\'impact sur CHAQUE Gardien : plafonné par le tuning, le finisher pèse plus qu\'un coup léger', () => {
  for (const kind of ALL_MODELS) {
    const { g, boss } = bossGame(kind);
    isolate(g, boss, { pattern: 'rest' });
    const t = g.tuning;
    const cap = t.boss[kind].hitstopCap;
    boss.invuln = 0;
    g.hitstop = 0;
    damageEnemy(g, boss, { kind: 'melee', amount: 1, dirX: 1, dirY: 0, hitstop: t.combo[0].hitstop });
    const light = g.hitstop;
    g.hitstop = 0;
    g.hitstopBank = 1;
    damageEnemy(g, boss, { kind: 'melee', amount: 1, dirX: 1, dirY: 0, hitstop: t.combo[2].hitstop });
    const heavy = g.hitstop;
    assert.ok(heavy <= cap + EPS, `${kind} : gel ${heavy} > plafond ${cap}`);
    assert.ok(heavy > light, `${kind} : finisher ${heavy} contre coup léger ${light}`);
  }
});

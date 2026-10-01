// Tests du lot KITS (V2) : classes, armes, compétences, gadgets, Supers.
//
//   - le kit par défaut (Revenant, Lame, Lance, Nova, Colère) est IDENTIQUE : mêmes valeurs
//     qu'avant les classes (recopiées ici), mêmes références dans le tuning de la partie ;
//   - chaque classe / arme / compétence / gadget / Super fonctionne en partie réelle (dégâts,
//     projectiles, zones, effets), sans erreur ;
//   - les statistiques de classe s'appliquent ; une arme d'une autre classe ne se manie pas ;
//   - les bénédictions (attaque, dash, compétence, Super) s'appliquent aux nouveaux kits ;
//   - déterminisme et invariants par classe (bot skilled) ;
//   - registre de la Ville (prix, listes) ; rendu et sons des kits sans erreur.
// Lancement : node --test tests/

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createGame, stepGame, emptyInput, DT, stateHash } from '../src/sim/game.mjs';
import { createTuning, DEFAULT_TUNING } from '../src/sim/config.mjs';
import { WEAPONS, SKILLS, GADGETS, SUPERS, CLASSES, DEFAULT_LOADOUT } from '../src/sim/kits.mjs';
import { createProfile, starterWeapon, unlock, unlockCost, selectClass, equipFromStash } from '../src/sim/profile.mjs';
import { createEnemy } from '../src/sim/enemies.mjs';
import { damagePlayer } from '../src/sim/combat.mjs';
import { spawnProjectile } from '../src/sim/projectiles.mjs';
import { addBoon } from '../src/sim/boons.mjs';
import { recomputeStats } from '../src/sim/stats.mjs';
import { canWield } from '../src/sim/run.mjs';
import { maxDashCharges } from '../src/sim/player.mjs';
import { POLICIES, resolveChoice } from '../tools/bots.mjs';

const T = createTuning();
const ticks = (seconds) => Math.ceil(seconds / DT);

// ---------------------------------------------------------------- outillage

/** Profil permanent : tout débloqué, la classe et le kit demandés équipés. */
function kitMeta(classId, { weapon, skill, gadget } = {}) {
  const m = createProfile(T);
  for (const k of ['classes', 'weapons', 'skills', 'gadgets']) m.unlocked[k] = Object.keys(T[k]);
  const c = T.classes[classId];
  m.loadout = { classId, skillId: skill ?? c.skills[0], gadgetId: gadget ?? c.gadgets[0] };
  m.equipment.arme = starterWeapon(T, weapon ?? c.weapons[0]);
  m.equipment.arme.uid = 'i9000';
  return m;
}

/** Partie de test : salle vidée (aucune vague), héros au centre, sans porte ni récompense. */
function sandbox(meta, opts = {}) {
  const g = createGame({ seed: 11, meta, ...opts });
  g.spawns.length = 0;
  g.enemies.length = 0;
  g.room.waves = [];
  g.room.waveIndex = 0;
  g.room.obstacles = [];
  g.room.cleared = true;
  g.room.interact = null;
  g.room.doors = [];
  g.player.x = g.room.w / 2;
  g.player.y = g.room.h / 2;
  g.tuning.combat.critChance = 0; // dégâts lisibles : aucun critique aléatoire
  g.events.length = 0;
  return g;
}

function input(over = {}) {
  return { ...emptyInput(), ...over };
}

/** Avance de n pas ; rend les événements de ces pas. */
function run(g, n, over = {}) {
  const evs = [];
  for (let i = 0; i < n; i++) {
    stepGame(g, input(typeof over === 'function' ? over(i) : over));
    evs.push(...g.events);
    g.events.length = 0;
  }
  return evs;
}

/** Mannequin (createEnemy l'ajoute à la salle) : ne riposte pas, PV au choix. */
function dummy(g, dx, dy, kind = 'brute', hp = 5000) {
  const e = createEnemy(g, kind, g.player.x + dx, g.player.y + dy, { spawnT: 0 });
  e.cooldown = 999;
  e.hp = hp;
  e.maxHp = hp;
  return e;
}

const hits = (evs, kind) => evs.filter((e) => e.type === 'hit' && (!kind || e.kind === kind));
const shots = (g) => g.room.kitFx?.shots ?? [];
const zones = (g) => g.room.kitFx?.zones ?? [];

// ---------------------------------------------------------------- kit par défaut : identique

// Valeurs du kit d'avant les classes (commit 680fa57), recopiées : le kit par défaut ne bouge pas.
const HISTORIC = {
  combo: [
    { startup: 0.05, active: 0.07, recovery: 0.12, range: 84, arc: 140, damage: 10, knockback: 240, lunge: 36, hitstop: 0.04, shake: 0.2 },
    { startup: 0.05, active: 0.07, recovery: 0.12, range: 84, arc: 140, damage: 11, knockback: 240, lunge: 36, hitstop: 0.04, shake: 0.2 },
    { startup: 0.09, active: 0.09, recovery: 0.24, range: 104, arc: 220, damage: 22, knockback: 560, lunge: 64, hitstop: 0.085, shake: 0.45 },
  ],
  dashStrike: { startup: 0.04, active: 0.08, recovery: 0.16, range: 96, arc: 120, damage: 18, knockback: 420, lunge: 90, hitstop: 0.06, shake: 0.35 },
  lance: { name: 'Lance infernale', kind: 'lance', text: 'Projectile qui transperce 3 ennemis.', cooldown: 4.0, damage: 30, speed: 900, radius: 12, range: 540, pierce: 3, knockback: 300, hitstop: 0.05, castTime: 0.08 },
  nova: { name: 'Nova de cendres', kind: 'nova', text: 'Onde qui repousse, étourdit et efface les projectiles.', chargesPerSection: 3, chargeOnEliteKill: 1, radius: 150, damage: 20, knockback: 900, stun: 0.9, iframes: 0.25, hitstop: 0.07, shake: 0.4 },
  colere: { name: 'Colère', kind: 'colere', text: 'Tourbillon invulnérable de 1,4 s.', startCharge: 0.4, chargeDamage: 900, duration: 1.4, tickInterval: 0.12, radius: 130, damagePerTick: 9, knockback: 260, speedMult: 0.85, shakePerTick: 0.1 },
};

const withoutCost = ({ cost, ...rest }) => rest;

test('kit par défaut : Revenant, Lame, Lance, Nova et Colère gardent leurs valeurs d\'origine', () => {
  assert.deepEqual(DEFAULT_LOADOUT, { classId: 'revenant', skillId: 'lance', gadgetId: 'nova' });
  assert.equal(Object.keys(CLASSES)[0], 'revenant', 'le Revenant reste la classe de départ');
  const rev = CLASSES.revenant;
  assert.deepEqual(rev.stats, {});
  assert.equal(rev.weapons[0], 'lame');
  assert.equal(rev.skills[0], 'lance');
  assert.equal(rev.gadgets[0], 'nova');
  assert.equal(rev.super, 'colere');
  assert.deepEqual(WEAPONS.lame.combo, HISTORIC.combo);
  assert.deepEqual(WEAPONS.lame.dashStrike, HISTORIC.dashStrike);
  assert.equal(WEAPONS.lame.baseMult, 1);
  assert.equal(WEAPONS.lame.moveMult, undefined, 'la Lame ne module pas la vitesse du combo');
  assert.equal(WEAPONS.lame.aimRange, undefined, 'la Lame garde la visée assistée de mêlée');
  assert.deepEqual(withoutCost(SKILLS.lance), HISTORIC.lance);
  assert.deepEqual(withoutCost(GADGETS.nova), HISTORIC.nova);
  assert.deepEqual(SUPERS.colere, HISTORIC.colere);
  // Le tuning par défaut pointe sur les entrées du kit (références, pas copies).
  assert.equal(DEFAULT_TUNING.combo, WEAPONS.lame.combo);
  assert.equal(DEFAULT_TUNING.dashStrike, WEAPONS.lame.dashStrike);
  assert.equal(DEFAULT_TUNING.skill, SKILLS.lance);
  assert.equal(DEFAULT_TUNING.gadget, GADGETS.nova);
  assert.equal(DEFAULT_TUNING.super, SUPERS.colere);
});

test('kit par défaut : la partie résout des RÉFÉRENCES vers les entrées du registre', () => {
  const g = createGame({ seed: 3 });
  const t = g.tuning;
  assert.deepEqual(g.kit, { classId: 'revenant', weaponType: 'lame', skillId: 'lance', gadgetId: 'nova', superId: 'colere' });
  assert.equal(t.combo, t.weapons.lame.combo);
  assert.equal(t.dashStrike, t.weapons.lame.dashStrike);
  assert.equal(t.weapon, t.weapons.lame);
  assert.equal(t.skill, t.skills.lance);
  assert.equal(t.gadget, t.gadgets.nova);
  assert.equal(t.super, t.supers.colere);
  assert.equal(g.player.maxHp, 100);
  assert.equal(g.room.kitFx, undefined, 'le kit d\'origine ne pose ni tir ni zone de kit');
});

test('kit par défaut : une partie jouée ne crée jamais de tir ou de zone de kit', () => {
  const g = createGame({ seed: 5 });
  const mem = {};
  for (let i = 0; i < 3000 && g.mode !== 'dead'; i++) {
    if (g.mode === 'choice') resolveChoice(g, 'skilled');
    stepGame(g, POLICIES.skilled(g, mem));
    g.events.length = 0;
    assert.equal(g.room.kitFx, undefined, `tick ${g.tick}`);
  }
});

// ---------------------------------------------------------------- registre (Ville)

test('registre : 3 classes, 2 armes, 2 compétences et 2 gadgets par classe, un Super chacune', () => {
  assert.ok(Object.keys(CLASSES).length >= 3);
  assert.ok(Object.keys(SKILLS).length >= 4);
  assert.ok(Object.keys(GADGETS).length >= 3);
  assert.equal(Object.keys(SUPERS).length, 3);
  const supers = new Set();
  for (const [id, c] of Object.entries(CLASSES)) {
    assert.ok(c.weapons.length >= 2 && c.skills.length >= 2 && c.gadgets.length >= 2, `${id} : listes trop courtes`);
    for (const w of c.weapons) {
      assert.ok(WEAPONS[w], `${id} : arme inconnue ${w}`);
      assert.equal(WEAPONS[w].className, id, `${w} appartient à ${id}`);
    }
    for (const s of c.skills) assert.ok(SKILLS[s], `${id} : compétence inconnue ${s}`);
    for (const g of c.gadgets) assert.ok(GADGETS[g], `${id} : gadget inconnu ${g}`);
    assert.ok(SUPERS[c.super], `${id} : Super inconnu`);
    supers.add(c.super);
    assert.ok(c.passive?.name && c.passive?.text, `${id} : passif lisible`);
  }
  assert.equal(supers.size, 3, 'un Super propre à chaque classe');
});

test('registre : chaque entrée a un prix en Âmes ; le départ de chaque classe est gratuit', () => {
  for (const [kind, table] of Object.entries({ classes: CLASSES, weapons: WEAPONS, skills: SKILLS, gadgets: GADGETS })) {
    for (const [id, d] of Object.entries(table)) {
      assert.ok(Number.isInteger(d.cost) && d.cost >= 0, `${kind}.${id} : cost ${d.cost}`);
      assert.equal(unlockCost(T, kind, id), d.cost);
    }
  }
  assert.equal(CLASSES.revenant.cost, 0);
  for (const c of Object.values(CLASSES)) {
    assert.equal(WEAPONS[c.weapons[0]].cost, 0);
    assert.equal(SKILLS[c.skills[0]].cost, 0);
    assert.equal(GADGETS[c.gadgets[0]].cost, 0);
  }
  for (const w of Object.values(WEAPONS)) {
    assert.ok(w.starterName && w.bases?.length >= 1 && w.baseMult > 0, `${w.name} : starterName / bases / baseMult`);
    for (const def of [...w.combo, w.dashStrike]) {
      for (const k of ['startup', 'active', 'recovery', 'range', 'arc', 'damage', 'knockback', 'lunge', 'hitstop', 'shake']) {
        assert.ok(Number.isFinite(def[k]), `${w.name} : ${k} manquant`);
      }
      if (w.kind === 'ranged') assert.ok(def.shot?.speed > 0 && def.shot?.radius > 0, `${w.name} : coup à distance sans shot`);
    }
  }
});

test('registre : données pures (le tuning se clone et se sérialise)', () => {
  const t = createTuning();
  assert.deepEqual(JSON.parse(JSON.stringify(t.classes)), t.classes);
  assert.deepEqual(JSON.parse(JSON.stringify(t.weapons)), t.weapons);
  assert.deepEqual(JSON.parse(JSON.stringify(t.skills)), t.skills);
  assert.deepEqual(JSON.parse(JSON.stringify(t.gadgets)), t.gadgets);
  assert.deepEqual(JSON.parse(JSON.stringify(t.supers)), t.supers);
});

test('Ville : débloquer une classe puis la choisir forge son arme de départ ; une arme débloquée va au coffre', () => {
  const p = createProfile(T);
  p.souls = 1000;
  assert.equal(selectClass(p, T, 'bourreau').ok, false, 'classe verrouillée');
  assert.equal(unlock(p, T, 'classes', 'bourreau').ok, true);
  assert.equal(p.souls, 1000 - CLASSES.bourreau.cost);
  assert.equal(selectClass(p, T, 'bourreau').ok, true);
  assert.equal(p.equipment.arme.weaponType, 'hache');
  assert.equal(p.loadout.skillId, 'bond');
  assert.equal(p.loadout.gadgetId, 'cri');
  const before = p.souls;
  assert.equal(unlock(p, T, 'weapons', 'marteau').ok, true);
  assert.equal(p.souls, before - WEAPONS.marteau.cost);
  const marteau = p.stash.find((it) => it.weaponType === 'marteau');
  assert.ok(marteau, 'un maillet commun est forgé au coffre');
  assert.equal(equipFromStash(p, T, marteau.uid).ok, true);
  const g = createGame({ seed: 2, meta: p });
  assert.equal(g.kit.classId, 'bourreau');
  assert.equal(g.kit.weaponType, 'marteau');
  assert.equal(g.tuning.combo, g.tuning.weapons.marteau.combo);
  assert.equal(g.tuning.super, g.tuning.supers.sentence);
});

// ---------------------------------------------------------------- statistiques de classe

test('classes : statistiques appliquées (PV, armure, vitesse, longueur du dash)', () => {
  const dashLen = (classId) => {
    const g = sandbox(kitMeta(classId));
    const x0 = g.player.x;
    run(g, 1, { moveX: 1, dashPressed: true });
    run(g, ticks(g.tuning.dash.duration), { moveX: 0 });
    return g.player.x - x0;
  };
  const rev = sandbox(kitMeta('revenant'));
  const bou = sandbox(kitMeta('bourreau'));
  const cha = sandbox(kitMeta('chasseresse'));
  assert.equal(rev.player.maxHp, 100);
  assert.equal(bou.player.maxHp, 100 + CLASSES.bourreau.stats.maxHpBonus);
  assert.equal(cha.player.maxHp, 100 + CLASSES.chasseresse.stats.maxHpBonus);
  assert.equal(bou.player.hp, bou.player.maxHp);
  assert.ok(Math.abs(bou.player.stats.armor - CLASSES.bourreau.stats.armor) < 1e-9);
  assert.ok(Math.abs(cha.player.stats.moveSpeedMult - (1 + CLASSES.chasseresse.stats.moveSpeedMult)) < 1e-9);
  const base = T.dash.distance;
  const dr = dashLen('revenant');
  const db = dashLen('bourreau');
  const dc = dashLen('chasseresse');
  assert.ok(Math.abs(dr - base) < 12, `Revenant : dash ${dr}`);
  assert.ok(Math.abs(db - base * (1 + CLASSES.bourreau.stats.dashDistanceMult)) < 12, `Bourreau : dash ${db}`);
  assert.ok(Math.abs(dc - base * (1 + CLASSES.chasseresse.stats.dashDistanceMult)) < 15, `Chasseresse : dash ${dc}`);
  assert.ok(db < dr && dr < dc, 'dash court < étalon < dash long');
  // L'armure du Bourreau réduit vraiment un coup reçu.
  bou.player.iframes = 0;
  rev.player.iframes = 0;
  const hb = bou.player.hp;
  const hr = rev.player.hp;
  damagePlayer(bou, 40, { kind: 'test', id: 1 });
  damagePlayer(rev, 40, { kind: 'test', id: 1 });
  assert.ok(hb - bou.player.hp < hr - rev.player.hp, 'le Bourreau encaisse moins');
});

test('classes : une arme d\'une autre classe ne se manie pas', () => {
  const rev = createGame({ seed: 1 });
  const cha = createGame({ seed: 1, meta: kitMeta('chasseresse') });
  const arc = starterWeapon(T, 'arc');
  assert.equal(canWield(rev, arc), false);
  assert.equal(canWield(cha, arc), true);
  assert.equal(canWield(cha, starterWeapon(T, 'lame')), false);
  // Le coffre refuse de l'équiper ; un profil qui la porterait la range au coffre.
  const p = kitMeta('revenant');
  p.stash.push({ ...starterWeapon(T, 'hache'), uid: 'i77' });
  assert.equal(equipFromStash(p, T, 'i77').ok, false);
  const m = kitMeta('revenant');
  m.equipment.arme = { ...starterWeapon(T, 'arbalete'), uid: 'i78' };
  const g = createGame({ seed: 1, meta: m });
  assert.equal(g.kit.weaponType, 'lame', 'retour à une arme de la classe');
  assert.ok(g.meta.stash.some((it) => it.uid === 'i78'), 'l\'arbalète est au coffre, pas perdue');
});

// ---------------------------------------------------------------- armes en partie réelle

for (const [wt, w] of Object.entries(WEAPONS)) {
  test(`arme ${wt} : le combo enchaîne tous ses coups et blesse (${w.kind})`, () => {
    const g = sandbox(kitMeta(w.className, { weapon: wt }));
    assert.equal(g.kit.weaponType, wt);
    assert.equal(g.tuning.combo, g.tuning.weapons[wt].combo);
    const ranged = w.kind === 'ranged';
    const e = dummy(g, ranged ? 220 : 60, 0);
    e.mass = 1000; // le recul ne l'éjecte pas de la portée
    let maxShots = 0;
    const evs = run(g, ticks(3), (i) => {
      maxShots = Math.max(maxShots, shots(g).length);
      return { attack: true, attackPressed: i === 0, aimX: 1, aimY: 0 };
    });
    const indices = new Set(evs.filter((ev) => ev.type === 'attackStart').map((ev) => ev.index));
    for (let i = 0; i < w.combo.length; i++) assert.ok(indices.has(i), `coup ${i} jamais joué`);
    assert.ok(e.hp < e.maxHp, 'le mannequin est blessé');
    const melee = hits(evs, 'melee');
    assert.ok(melee.length >= w.combo.length, `${melee.length} coups portés`);
    if (ranged) {
      assert.ok(maxShots >= 1, 'des traits sont en vol');
      assert.ok(evs.some((ev) => ev.type === 'swing' && ev.ranged), 'swing marqué ranged (son, effet)');
    } else {
      assert.equal(maxShots, 0, 'une arme de mêlée ne tire pas');
    }
    // Les dégâts suivent le coup joué (dégâts de base × arme de base).
    const amounts = new Set(melee.map((h) => h.amount));
    for (const def of w.combo) assert.ok(amounts.has(def.damage), `dégâts ${def.damage} jamais vus (${[...amounts]})`);
  });

  test(`arme ${wt} : frappe de dash propre (source 'strike')`, () => {
    const g = sandbox(kitMeta(w.className, { weapon: wt }));
    const e = dummy(g, w.kind === 'ranged' ? 260 : 150, 0);
    e.mass = 1000;
    run(g, 1, { moveX: 1, dashPressed: true });
    const t = g.tuning.dash;
    run(g, ticks(t.duration * (1 - t.strikeCancelFrom)) + 1, { moveX: 1 });
    run(g, 1, { attackPressed: true, aimX: 1, aimY: 0 });
    assert.equal(g.player.attack?.strike, true);
    assert.equal(g.player.attack.def, g.tuning.weapons[wt].dashStrike);
    const evs = run(g, ticks(0.6));
    const strikes = hits(evs, 'strike');
    assert.ok(strikes.length >= 1, 'la frappe de dash touche');
    assert.equal(strikes[0].amount, w.dashStrike.damage);
  });
}

test('arme à distance : visée manuelle (le trait part dans la direction visée, même sans cible)', () => {
  const g = sandbox(kitMeta('chasseresse'));
  run(g, 1, { attack: true, attackPressed: true, aimX: 0, aimY: 1 });
  run(g, ticks(WEAPONS.arc.combo[0].startup) + 1, { attack: true, aimX: 0, aimY: 1 });
  const s = shots(g)[0];
  assert.ok(s, 'un trait est parti');
  assert.ok(s.vy > 0 && Math.abs(s.vx) < 1e-6, `direction (${s.vx}, ${s.vy})`);
});

test('arme à distance : visée assistée vers un ennemi hors de portée de mêlée', () => {
  const g = sandbox(kitMeta('chasseresse'));
  const e = dummy(g, -300, 0, 'imp', 100);
  run(g, 1, { attack: true, attackPressed: true });
  run(g, ticks(0.15), { attack: true });
  const s = shots(g)[0];
  assert.ok(s && s.vx < 0, 'le trait part vers l\'ennemi à 300 u');
  run(g, ticks(0.5), { attack: true });
  assert.ok(e.hp < e.maxHp);
});

test('arme lourde : le finisher de la hache étourdit ; l\'arme règle la mobilité du combo', () => {
  const g = sandbox(kitMeta('bourreau'));
  const e = dummy(g, 70, 0, 'imp', 5000);
  e.mass = 1000;
  let stunned = false;
  run(g, ticks(2), (i) => {
    if (e.stun > 0) stunned = true;
    return { attack: true, attackPressed: i === 0, aimX: 1, aimY: 0 };
  });
  assert.ok(stunned, 'le 3e coup étourdit');
  // Vitesse pendant un coup : hache 0,5 × 0,7 ; dagues min(1, 0,5 × 1,5) ; Lame 0,5.
  const speedDuring = (classId, weapon) => {
    const h = sandbox(kitMeta(classId, { weapon }));
    run(h, 1, { attackPressed: true, aimX: 0, aimY: -1 });
    run(h, 2, { moveX: 1, attack: true, aimX: 0, aimY: -1 });
    return h.player.attack ? Math.abs(h.player.vx) : NaN;
  };
  const lame = speedDuring('revenant', 'lame');
  const dagues = speedDuring('revenant', 'dagues');
  const hache = speedDuring('bourreau', 'hache');
  assert.ok(Math.abs(lame - T.player.speed * T.player.attackMoveMult) < 1e-6, `Lame ${lame}`);
  assert.ok(dagues > lame && hache < lame, `dagues ${dagues}, hache ${hache}`);
});

// ---------------------------------------------------------------- compétences

test('compétence Chaîne d\'Enfer : harponne, étourdit et TIRE l\'ennemi contre le héros', () => {
  const g = sandbox(kitMeta('revenant', { skill: 'chaine' }));
  const e = dummy(g, 300, 0, 'imp', 500);
  const d0 = e.x - g.player.x;
  const evs = run(g, 1, { skillPressed: true, skillAimX: 1, skillAimY: 0 });
  evs.push(...run(g, ticks(0.6)));
  assert.ok(evs.some((ev) => ev.type === 'hook'), 'événement hook');
  assert.ok(hits(evs, 'skill').length >= 1, 'dégâts de compétence');
  const d1 = Math.hypot(e.x - g.player.x, e.y - g.player.y);
  assert.ok(d1 < d0 * 0.4, `tiré : ${d0} -> ${d1.toFixed(0)}`);
  assert.ok(d1 > g.player.r + e.r - 1, 'pas à travers le héros');
  assert.ok(g.player.skillCd > 0);
  assert.equal(g.telemetry.skillCasts, 1);
});

test('compétence Chaîne d\'Enfer : un Gardien n\'est pas tiré', () => {
  const g = sandbox(kitMeta('revenant', { skill: 'chaine' }));
  const b = createEnemy(g, 'gardien', g.player.x + 300, g.player.y, { boss: true, spawnT: 0 });
  b.cooldown = 999;
  b.state = 'rest';
  b.restFor = 99;
  run(g, 1, { skillPressed: true, skillAimX: 1, skillAimY: 0 });
  let maxPull = 0;
  for (let i = 0; i < ticks(0.5); i++) {
    run(g, 1);
    maxPull = Math.max(maxPull, Math.hypot(b.kvx, b.kvy));
  }
  assert.ok(b.hp < b.maxHp, 'le Gardien est touché');
  assert.ok(maxPull < 1, `le Gardien n'est pas tiré (élan ${maxPull})`);
});

test('compétence Bond : saut invulnérable vers la cible, impact qui blesse et étourdit', () => {
  const g = sandbox(kitMeta('bourreau'));
  const e = dummy(g, 220, 0, 'imp', 500);
  const x0 = g.player.x;
  run(g, 1, { skillPressed: true });
  assert.equal(g.player.state, 'cast');
  assert.ok(g.player.iframes > 0, 'invulnérable dès le saut');
  run(g, 3);
  assert.equal(damagePlayer(g, 30, { kind: 'test', id: 9 }), false, 'aucun coup ne porte pendant le saut');
  const evs = run(g, ticks(SKILLS.bond.leapTime) + 2);
  assert.equal(g.player.state, 'free');
  assert.ok(g.player.x - x0 > 120, `le héros a bondi (${(g.player.x - x0).toFixed(0)} u)`);
  assert.ok(evs.some((ev) => ev.type === 'explode' && ev.hero && ev.kind === 'bond'), 'impact');
  assert.ok(hits(evs, 'skill').length >= 1);
  assert.ok(e.stun > 0 || e.hp < e.maxHp);
});

test('compétence Bond : interrompue par un dash, elle atterrit quand même (recharge jamais perdue)', () => {
  const g = sandbox(kitMeta('bourreau'));
  dummy(g, 200, 0, 'imp', 500);
  run(g, 1, { skillPressed: true });
  run(g, 4);
  const evs = run(g, 1, { moveX: -1, dashPressed: true });
  assert.equal(g.player.state, 'dash');
  assert.ok(evs.some((ev) => ev.type === 'explode' && ev.kind === 'bond'), 'impact au moment du dash');
  assert.equal(g.player.cast, null);
});

test('compétence Brasier d\'âmes : pot lancé sur la cible, impact puis sol qui brûle, puis s\'éteint', () => {
  const g = sandbox(kitMeta('chasseresse', { skill: 'brasier' }));
  const e = dummy(g, 200, 0, 'brute', 2000);
  e.mass = 1000;
  e.stun = 99; // immobile : on juge le point de chute
  run(g, 1, { skillPressed: true });
  let evs = run(g, ticks(SKILLS.brasier.castTime + SKILLS.brasier.flight) + 3);
  assert.ok(evs.some((ev) => ev.type === 'explode' && ev.kind === 'brasier'), 'le pot éclate');
  assert.ok(hits(evs, 'skill').length >= 1, 'impact de compétence');
  const z = zones(g).find((o) => o.kind === 'brasier');
  assert.ok(z, 'le sol brûle');
  assert.ok(Math.hypot(z.x - e.x, z.y - e.y) < 40, 'le pot est tombé sur la cible');
  evs = run(g, ticks(1));
  assert.ok(e.burn > 0, 'l\'ennemi dans la zone brûle');
  assert.ok(hits(evs, 'burn').length >= 1, 'la brûlure inflige des dégâts');
  run(g, ticks(SKILLS.brasier.duration));
  assert.equal(zones(g).length, 0, 'la zone s\'éteint');
});

test('compétence Volée d\'épines : éventail de traits de compétence', () => {
  const g = sandbox(kitMeta('chasseresse'));
  const e = dummy(g, 60, 0, 'brute', 2000);
  e.mass = 1000;
  run(g, 1, { skillPressed: true, skillAimX: 1, skillAimY: 0 });
  let evs = run(g, ticks(SKILLS.volee.castTime) + 1);
  const fan = shots(g).filter((s) => s.kind === 'thorn');
  assert.equal(fan.length + new Set(hits(evs, 'skill').map((h) => h.id)).size > 0, true);
  evs = evs.concat(run(g, ticks(0.4)));
  assert.ok(hits(evs, 'skill').length >= 3, `${hits(evs, 'skill').length} épines ont touché`);
  assert.equal(g.telemetry.skillCasts, 1);
});

// ---------------------------------------------------------------- gadgets

test('gadget Bombe : lancée sur l\'ennemi, explose après la mèche, étourdit, efface les tirs ennemis', () => {
  const g = sandbox(kitMeta('bourreau', { gadget: 'bombe' }));
  const e = dummy(g, 200, 0, 'imp', 500);
  const c0 = g.player.gadgetCharges;
  run(g, 1, { gadgetPressed: true });
  assert.equal(g.player.gadgetCharges, c0 - 1);
  const b = zones(g).find((z) => z.kind === 'bombe');
  assert.ok(b && Math.hypot(b.tx - e.x, b.ty - e.y) < 20, 'visée sur l\'ennemi');
  spawnProjectile(g, { owner: 'enemy', kind: 'arrow', x: e.x, y: e.y - 40, vx: 0, vy: 0, r: 7, damage: 10, range: 600 });
  const evs = run(g, ticks(GADGETS.bombe.flight + GADGETS.bombe.fuse) + 2);
  assert.ok(evs.some((ev) => ev.type === 'explode' && ev.kind === 'bombe'), 'explosion');
  assert.ok(hits(evs, 'gadget').some((h) => h.id === e.id), 'la cible est touchée');
  assert.ok(e.stun > 0, 'étourdi');
  assert.equal(g.projectiles.filter((p) => p.owner === 'enemy' && !p.dead).length, 0, 'le souffle efface les tirs');
  assert.equal(zones(g).length, 0);
});

test('gadget Piège : se referme sur le premier ennemi qui passe ; trois pièges au plus', () => {
  const g = sandbox(kitMeta('chasseresse'));
  run(g, 1, { gadgetPressed: true });
  const trap = zones(g)[0];
  assert.equal(trap.kind, 'piege');
  run(g, ticks(GADGETS.piege.armTime) + 1);
  const e = dummy(g, 0, 0, 'imp', 500);
  e.x = trap.x + 200;
  e.y = trap.y;
  e.cooldown = 999;
  let evs = [];
  for (let i = 0; i < ticks(1); i++) {
    e.x -= 8; // l'ennemi marche sur le piège
    evs = evs.concat(run(g, 1));
    if (e.stun > 0) break;
  }
  assert.ok(evs.some((ev) => ev.type === 'explode' && ev.kind === 'piege'), 'le piège se referme');
  assert.ok(e.stun > 1, 'immobilisé');
  assert.ok(hits(evs, 'gadget').length >= 1);
  // Pose de 4 pièges : le plus ancien se désarme.
  const h = sandbox(kitMeta('chasseresse'));
  for (let i = 0; i < 4; i++) {
    h.player.x += 80;
    run(h, 1, { gadgetPressed: true });
    run(h, 2);
  }
  assert.equal(zones(h).filter((z) => z.kind === 'piege').length, GADGETS.piege.maxActive);
});

test('gadget Cri du bourreau : étourdit et rend vulnérable autour du héros, sans repousser', () => {
  const g = sandbox(kitMeta('bourreau'));
  assert.equal(g.kit.gadgetId, 'cri', 'gadget de départ du Bourreau');
  const near = dummy(g, 120, 0, 'imp', 500);
  const far = dummy(g, 420, 0, 'imp', 500);
  const evs = run(g, 1, { gadgetPressed: true });
  assert.ok(evs.some((ev) => ev.type === 'gadget' && ev.gadget === 'cri'));
  assert.ok(near.stun > 0 && near.vuln > 0 && near.vulnMult > 0, 'proche : étourdi et vulnérable');
  assert.ok(Math.hypot(near.kvx, near.kvy) < 1, 'aucun recul');
  assert.equal(far.vuln, 0, 'lointain : intact');
});

test('gadget Totem de givre : impulsions qui blessent et ralentissent à portée', () => {
  const g = sandbox(kitMeta('chasseresse', { gadget: 'totem' }));
  const near = dummy(g, 100, 0, 'imp', 500);
  const far = dummy(g, 400, 0, 'imp', 500);
  near.stun = 99; // immobiles : la portée du totem se juge sur place
  far.stun = 99;
  run(g, 1, { gadgetPressed: true });
  const evs = run(g, ticks(1.2));
  assert.ok(evs.filter((ev) => ev.type === 'kitPulse').length >= 2, 'impulsions');
  assert.ok(near.hp < near.maxHp && near.chillMult < 1, 'proche : blessé et ralenti');
  assert.equal(far.hp, far.maxHp, 'lointain : intact');
  run(g, ticks(GADGETS.totem.life));
  assert.equal(zones(g).length, 0, 'le totem s\'efface');
});

// ---------------------------------------------------------------- Supers

test('Super Sentence : invulnérable, trois exécutions, la dernière à 360° étourdit', () => {
  const g = sandbox(kitMeta('bourreau'));
  const e = dummy(g, 90, 0, 'brute', 5000);
  e.mass = 1000;
  const back = dummy(g, -100, 0, 'imp', 5000);
  back.mass = 1000;
  g.player.superCharge = 1;
  let evs = run(g, 1, { superPressed: true });
  assert.equal(g.player.state, 'super');
  const hp = g.player.hp;
  damagePlayer(g, 50, { kind: 'test', id: 5 });
  assert.equal(g.player.hp, hp, 'invulnérable');
  // Les exécutions gèlent la scène (gel d'impact) : le Super dure plus de pas que sa durée.
  for (let i = 0; i < ticks(SUPERS.sentence.duration + 1) && g.player.state === 'super'; i++) evs = evs.concat(run(g, 1));
  const ticksEv = evs.filter((ev) => ev.type === 'superTick' && ev.super === 'sentence');
  assert.equal(ticksEv.length, SUPERS.sentence.strikes.length);
  const sup = hits(evs, 'super');
  assert.ok(sup.some((h) => h.id === e.id) && sup.some((h) => h.id === back.id), 'le fracas final touche aussi derrière');
  assert.ok(back.stun > 0, 'étourdi par le fracas');
  assert.equal(g.player.state, 'free');
  assert.equal(g.player.superCharge, 0, 'les coups du Super ne rechargent pas la jauge');
});

test('Super Nuée de traits : invulnérable, tirs en rotation sur les ennemis proches', () => {
  const g = sandbox(kitMeta('chasseresse'));
  const a = dummy(g, 200, 0, 'imp', 5000);
  const b = dummy(g, -200, 50, 'imp', 5000);
  g.player.superCharge = 1;
  run(g, 1, { superPressed: true });
  assert.equal(g.player.state, 'super');
  assert.equal(damagePlayer(g, 50, { kind: 'test', id: 6 }), false);
  let evs = [];
  for (let i = 0; i < ticks(SUPERS.nuee.duration + 1) && g.player.state === 'super'; i++) evs = evs.concat(run(g, 1, { moveX: 0.5 }));
  const sup = hits(evs, 'super');
  assert.ok(sup.some((h) => h.id === a.id) && sup.some((h) => h.id === b.id), 'les deux cibles reçoivent des traits');
  assert.ok(sup.length >= 8, `${sup.length} traits ont touché`);
  assert.equal(g.player.state, 'free');
});

// ---------------------------------------------------------------- bénédictions sur les kits

test('bénédictions : attaque (brûlure) sur les traits de l\'arc, compétence (vulnérabilité) sur la Chaîne', () => {
  const g = sandbox(kitMeta('chasseresse'));
  addBoon(g.run, { id: 'lame_ardente', rarity: 'commun' });
  recomputeStats(g);
  const e = dummy(g, 200, 0, 'brute', 5000);
  e.mass = 1000;
  run(g, ticks(0.6), (i) => ({ attack: true, attackPressed: i === 0, aimX: 1, aimY: 0 }));
  assert.ok(e.burn > 0, 'les traits (source melee) enflamment');

  const h = sandbox(kitMeta('revenant', { skill: 'chaine' }));
  addBoon(h.run, { id: 'charme', rarity: 'commun' });
  recomputeStats(h);
  const f = dummy(h, 250, 0, 'imp', 500);
  run(h, 1, { skillPressed: true, skillAimX: 1, skillAimY: 0 });
  run(h, ticks(0.4));
  assert.ok(f.vuln > 0, 'la Chaîne (source skill) rend vulnérable');
});

test('bénédictions : dash (Pas de braise) pour toute classe ; Super (Gloire charnelle) sur la Sentence', () => {
  const g = sandbox(kitMeta('bourreau'));
  addBoon(g.run, { id: 'pas_de_braise', rarity: 'commun' });
  recomputeStats(g);
  const evs = run(g, 1, { moveX: 1, dashPressed: true });
  assert.ok(evs.some((ev) => ev.type === 'dashNova'));

  const firstStrike = (boon) => {
    const h = sandbox(kitMeta('bourreau'));
    if (boon) {
      addBoon(h.run, { id: 'gloire_charnelle', rarity: 'commun' });
      recomputeStats(h);
    }
    const e = dummy(h, 90, 0, 'brute', 5000);
    e.mass = 1000;
    h.player.superCharge = 1;
    const ev = run(h, ticks(0.4), (i) => ({ superPressed: i === 0 }));
    return { amount: hits(ev, 'super')[0].amount, superT: h.player.superT };
  };
  const plain = firstStrike(false);
  const boosted = firstStrike(true);
  assert.ok(boosted.amount > plain.amount * 1.3, `${plain.amount} -> ${boosted.amount}`);
  assert.ok(boosted.superT > plain.superT, 'le Super dure plus longtemps');
});

// ---------------------------------------------------------------- parties réelles par classe

const WALL_EPS = 0.5;
const finite = (...v) => v.every(Number.isFinite);

function insideObstacle(room, x, y, tol) {
  return room.obstacles.some((o) => x > o.x0 + tol && x < o.x1 - tol && y > o.y0 + tol && y < o.y1 - tol);
}

function checkInvariants(g, where) {
  const p = g.player;
  const room = g.room;
  assert.ok(finite(p.x, p.y, p.vx, p.vy), `${where} : héros non fini`);
  const lo = room.pad + p.r - WALL_EPS;
  assert.ok(p.x >= lo && p.x <= room.w - lo && p.y >= lo && p.y <= room.h - lo, `${where} : héros hors des murs`);
  assert.ok(!insideObstacle(room, p.x, p.y, p.r * 0.5), `${where} : héros dans un obstacle`);
  assert.ok(p.hp >= 0 && p.hp <= p.maxHp, `${where} : PV ${p.hp}/${p.maxHp}`);
  assert.equal(p.hp <= 0, p.state === 'dead', `${where} : PV et état incohérents`);
  assert.ok(p.dashCharges >= 0 && p.dashCharges <= maxDashCharges(g), `${where} : charges de dash`);
  assert.ok(p.gadgetCharges >= 0, `${where} : charges de gadget`);
  assert.ok(p.superCharge >= 0 && p.superCharge <= 1, `${where} : jauge de Super`);
  for (const e of g.enemies) {
    if (e.dead) continue;
    assert.ok(finite(e.x, e.y, e.kvx, e.kvy), `${where} : ${e.kind} non fini`);
    assert.ok(!insideObstacle(room, e.x, e.y, 6), `${where} : ${e.kind} dans un obstacle (traction ?)`);
    assert.ok(e.hp > 0 && e.hp <= e.maxHp, `${where} : ${e.kind} PV ${e.hp}`);
  }
  for (const s of shots(g)) assert.ok(finite(s.x, s.y, s.vx, s.vy) && s.traveled <= s.range + 60, `${where} : tir ${s.kind}`);
  for (const z of zones(g)) assert.ok(finite(z.x, z.y, z.t), `${where} : zone ${z.kind}`);
}

function playClass(meta, seed, steps, check) {
  const g = createGame({ seed, meta });
  const mem = {};
  const seen = {};
  for (let i = 0; i < steps && g.mode !== 'dead'; i++) {
    for (let k = 0; k < 8 && g.mode === 'choice'; k++) resolveChoice(g, 'skilled');
    if (g.mode !== 'play') break;
    stepGame(g, POLICIES.skilled(g, mem));
    assert.ok(g.events.length <= 500, 'trop d\'événements en une image');
    for (const ev of g.events) seen[ev.type] = (seen[ev.type] ?? 0) + 1;
    g.events.length = 0;
    if (check) check(g, `tick ${g.tick} étage ${g.run.floor}`);
  }
  return { g, seen };
}

const LOADOUTS = [
  ['revenant', { weapon: 'dagues', skill: 'chaine', gadget: 'bombe' }],
  ['bourreau', { weapon: 'hache', skill: 'bond', gadget: 'bombe' }],
  ['bourreau', { weapon: 'marteau', skill: 'chaine', gadget: 'nova' }],
  ['chasseresse', { weapon: 'arc', skill: 'volee', gadget: 'piege' }],
  ['chasseresse', { weapon: 'arbalete', skill: 'brasier', gadget: 'totem' }],
];

for (const [cls, kit] of LOADOUTS) {
  test(`partie réelle ${cls} (${Object.values(kit).join(', ')}) : invariants tenus, chaque aptitude sert`, () => {
    const { g } = playClass(kitMeta(cls, kit), 7, 5000, checkInvariants);
    const tel = g.telemetry;
    assert.ok(g.run.floor >= 4, `le bot progresse (étage ${g.run.floor})`);
    assert.ok(tel.kills >= 15, `tués ${tel.kills}`);
    assert.ok(tel.hitsLanded > 0 && tel.skillCasts > 0 && tel.superUses > 0, `coups ${tel.hitsLanded}, compétence ${tel.skillCasts}, Super ${tel.superUses}`);
  });
}

test('déterminisme par classe : même graine => même partie (tirs et zones compris) ; graines différentes => parties différentes', () => {
  for (const [cls, kit] of LOADOUTS) {
    const sig = (seed) => {
      const { g } = playClass(kitMeta(cls, kit), seed, 1800);
      return `${stateHash(g)}|${JSON.stringify(g.room.kitFx ?? null)}|${g.telemetry.damageDealt}|${g.player.x.toFixed(3)}`;
    };
    assert.equal(sig(3), sig(3), `${cls} : même graine, partie différente`);
    assert.notEqual(sig(3), sig(4), `${cls} : graines différentes, même partie`);
  }
});

// ---------------------------------------------------------------- rendu et sons (sans DOM)

/** Contexte 2D factice : accepte tout appel, mémorise les affectations. */
function fakeCtx() {
  const store = {};
  const fn = () => anything;
  const anything = new Proxy(fn, {
    get(t, k) {
      if (k === Symbol.toPrimitive) return () => 0;
      if (k in store) return store[k];
      return anything;
    },
    set(t, k, v) {
      store[k] = v;
      return true;
    },
    apply() {
      return anything;
    },
  });
  return anything;
}

test('rendu : monde, HUD et effets de chaque kit se dessinent sans erreur (contexte factice)', async () => {
  const saved = globalThis.OffscreenCanvas;
  globalThis.OffscreenCanvas = class {
    constructor(w, h) {
      this.width = w;
      this.height = h;
    }
    getContext() {
      return fakeCtx();
    }
  };
  try {
    const { drawWorld } = await import('../src/render/render.mjs');
    const { drawHud } = await import('../src/render/hud.mjs');
    const { createFx, handleFxEvents, updateFx } = await import('../src/render/fx.mjs');
    const { createCamera } = await import('../src/render/camera.mjs');
    const view = { w: 844, h: 390, safe: { top: 0, right: 0, bottom: 0, left: 0 } };
    const button = (id, x) => ({ id, x, y: 300, r: 40, pointer: id === 'skill' ? 1 : null, dragging: id === 'skill', dx: 30, dy: 0 });
    const touch = { visible: true, stick: { id: null }, buttons: ['attack', 'dash', 'skill', 'gadget', 'super'].map((id, i) => button(id, 500 + i * 60)) };
    const kbd = { ...touch, visible: false };
    for (const [cls, kit] of [['revenant', {}], ...LOADOUTS]) {
      const g = sandbox(kitMeta(cls, kit));
      dummy(g, 150, 0, 'imp', 5000);
      dummy(g, -150, 30, 'brute', 5000);
      const fx = createFx();
      const cam = createCamera();
      const frame = (over) => {
        stepGame(g, input(over));
        handleFxEvents(fx, cam, g.events, g);
        g.events.length = 0;
        updateFx(fx, DT, g);
        const ctx = fakeCtx();
        drawWorld(ctx, g, fx, g.time, touch);
        drawHud(ctx, g, fx, cam, g.tick % 2 ? touch : kbd, view, g.time);
      };
      g.player.superCharge = 1;
      frame({ attack: true, attackPressed: true, aimX: 1, aimY: 0 });
      for (let i = 0; i < 20; i++) frame({ attack: true, aimX: 1, aimY: 0 });
      frame({ skillPressed: true, skillAimX: 1, skillAimY: 0 });
      for (let i = 0; i < 25; i++) frame({});
      frame({ gadgetPressed: true });
      for (let i = 0; i < 40; i++) frame({});
      frame({ superPressed: true });
      for (let i = 0; i < 100; i++) frame({ moveX: 0.3 });
    }
  } finally {
    globalThis.OffscreenCanvas = saved;
  }
});

// Faux WebAudio strict (mêmes exigences que WebAudio : types connus, temps finis, rampes > 0).
function fakeAudioContext(instances) {
  const OSC = new Set(['sine', 'square', 'sawtooth', 'triangle']);
  const FILTERS = new Set(['lowpass', 'highpass', 'bandpass', 'lowshelf', 'highshelf', 'peaking', 'notch', 'allpass']);
  const time = (t) => {
    if (!Number.isFinite(t) || t < 0) throw new RangeError(`temps ${t}`);
  };
  const param = (v) => ({
    value: v,
    setValueAtTime(x, t) { time(t); if (!Number.isFinite(x)) throw new TypeError('valeur'); },
    linearRampToValueAtTime(x, t) { time(t); if (!Number.isFinite(x)) throw new TypeError('valeur'); },
    exponentialRampToValueAtTime(x, t) { time(t); if (!(x > 0)) throw new RangeError(`rampe vers ${x}`); },
    setTargetAtTime(x, t) { time(t); },
    cancelScheduledValues(t) { time(t); },
  });
  return class {
    constructor() {
      this.currentTime = 0;
      this.sampleRate = 48000;
      this.state = 'running';
      this.destination = this.node();
      instances.push(this);
    }
    node() {
      return { connect: (n) => n, disconnect() {} };
    }
    resume() { return Promise.resolve(); }
    createGain() { return { ...this.node(), gain: param(1) }; }
    createStereoPanner() { return { ...this.node(), pan: param(0) }; }
    createDynamicsCompressor() {
      const n = this.node();
      for (const k of ['threshold', 'knee', 'ratio', 'attack', 'release']) n[k] = param(0);
      return n;
    }
    createWaveShaper() { return { ...this.node(), curve: null }; }
    source() {
      return { ...this.node(), start(t = 0) { time(t); }, stop(t = 0) { time(t); } };
    }
    createOscillator() {
      const n = { ...this.source(), frequency: param(440), detune: param(0) };
      Object.defineProperty(n, 'type', { set(v) { if (!OSC.has(v)) throw new TypeError(`oscillateur ${v}`); } });
      return n;
    }
    createBiquadFilter() {
      const n = { ...this.node(), frequency: param(350), Q: param(1) };
      Object.defineProperty(n, 'type', { set(v) { if (!FILTERS.has(v)) throw new TypeError(`filtre ${v}`); } });
      return n;
    }
    createBufferSource() { return { ...this.source(), buffer: null }; }
    createBuffer(c, len, rate) {
      const data = new Float32Array(Math.max(1, len));
      return { duration: len / rate, length: len, sampleRate: rate, getChannelData: () => data };
    }
  };
}

test('sons : chaque variante de kit (tir, compétence, gadget, Super, explosion du héros) joue sans erreur', async () => {
  const { createAudio } = await import('../src/audio/sfx.mjs');
  const instances = [];
  const audio = createAudio({ AudioContext: fakeAudioContext(instances), navigator: {}, random: () => 0.5, now: () => 0 });
  audio.unlock();
  await Promise.resolve();
  const at = { x: 500, y: 400 };
  const events = [
    ...Object.keys(WEAPONS).map((weapon) => ({ type: 'swing', ...at, angle: 0, arc: 0, range: 400, index: 0, strike: false, weapon, ranged: WEAPONS[weapon].kind === 'ranged' })),
    { type: 'swing', ...at, angle: 0, arc: 0, range: 400, index: 0, strike: true, weapon: 'arc', ranged: true },
    ...Object.values(SKILLS).map((s) => ({ type: 'skill', ...at, angle: 0, skill: s.kind })),
    ...Object.values(GADGETS).map((gd) => ({ type: 'gadget', ...at, r: gd.radius, charges: 1, gadget: gd.kind })),
    ...Object.values(SUPERS).map((s) => ({ type: 'super', ...at, r: s.radius, super: s.kind })),
    ...Object.values(SUPERS).map((s) => ({ type: 'superTick', ...at, r: 100, super: s.kind, angle: 0 })),
    ...['bombe', 'piege', 'bond', 'brasier'].map((kind) => ({ type: 'explode', ...at, r: 110, hero: true, kind })),
  ];
  let played = 0;
  for (const ev of events) {
    const before = audio.getStats().played;
    audio.handleEvents([ev], { player: at });
    played += audio.getStats().played - before;
    instances[0].currentTime += 5; // laisse s'éteindre : la polyphonie ne masque aucun son
  }
  const st = audio.getStats();
  assert.equal(st.errors, 0, st.lastError);
  assert.equal(played, events.length, 'chaque événement de kit produit un son');
  // Les événements propres aux kits restent sans erreur même groupés dans une image.
  audio.handleEvents([{ type: 'hook', x0: 0, y0: 0, x1: 10, y1: 0 }, { type: 'kitPulse', ...at, r: 150 }], { player: at });
  assert.equal(audio.getStats().errors, 0);
});

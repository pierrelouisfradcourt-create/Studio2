// Tests unitaires des RÈGLES (une règle, un test). Les valeurs sont lues dans le tuning,
// jamais recopiées : un réglage de feel ne casse pas un test, une règle cassée oui.
// Lancement : node --test tests/

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createGame, stepGame, applyCommand, emptyInput, DT } from '../src/sim/game.mjs';
import { createEnemy } from '../src/sim/enemies.mjs';
import { damagePlayer } from '../src/sim/combat.mjs';
import { spawnProjectile } from '../src/sim/projectiles.mjs';
import { floorInfo, checkpointAfterBoss, floorScaling } from '../src/sim/floors.mjs';
import { generateItem, ITEM_RARITIES } from '../src/sim/loot.mjs';
import { addBoon, BOONS, boonDef } from '../src/sim/boons.mjs';
import { recomputeStats } from '../src/sim/stats.mjs';
import { onRoomClear, enterFloor } from '../src/sim/run.mjs';

/** Partie de test : salle vidée (aucune vague), héros au centre. */
function sandbox(opts = {}) {
  const g = createGame({ seed: 11, ...opts });
  g.spawns.length = 0;
  g.enemies.length = 0;
  g.room.waves = [];
  g.room.waveIndex = 0;
  g.room.obstacles = [];
  // Salle déclarée nettoyée, sans récompense ni porte : rien ne vient interrompre le test.
  g.room.cleared = true;
  g.room.interact = null;
  g.room.doors = [];
  g.player.x = g.room.w / 2;
  g.player.y = g.room.h / 2;
  g.events.length = 0;
  return g;
}

function input(over = {}) {
  return { ...emptyInput(), ...over };
}

function steps(g, n, over = {}) {
  for (let i = 0; i < n; i++) stepGame(g, input(over));
}

function dummy(g, dx, dy, kind = 'brute') {
  const e = createEnemy(g, kind, g.player.x + dx, g.player.y + dy, { spawnT: 0 });
  e.cooldown = 99; // ne riposte pas : on teste le héros
  return e;
}

const ticks = (seconds) => Math.ceil(seconds / DT);

// ---------------------------------------------------------------- dash

test('dash : déplace de la distance réglée et consomme une charge', () => {
  const g = sandbox();
  const t = g.tuning.dash;
  const x0 = g.player.x;
  stepGame(g, input({ moveX: 1, dashPressed: true }));
  assert.equal(g.player.state, 'dash');
  assert.equal(g.player.dashCharges, t.charges - 1);
  steps(g, ticks(t.duration) - 1, { moveX: 1 });
  const traveled = g.player.x - x0;
  assert.ok(Math.abs(traveled - t.distance) < 12, `parcouru ${traveled.toFixed(1)} u, attendu ~${t.distance}`);
});

test('dash : pendant les i-frames, aucun dégât n\'est appliqué et l\'esquive est comptée', () => {
  const g = sandbox();
  stepGame(g, input({ moveX: 1, dashPressed: true }));
  const hp = g.player.hp;
  const landed = damagePlayer(g, 30, { kind: 'test', id: 999, x: g.player.x, y: g.player.y });
  assert.equal(landed, false);
  assert.equal(g.player.hp, hp);
  assert.equal(g.telemetry.dodges, 1);
});

test('dash : i-frames expirées -> le coup porte', () => {
  const g = sandbox();
  stepGame(g, input({ moveX: 1, dashPressed: true }));
  steps(g, ticks(g.tuning.dash.iframes) + 2);
  const hp = g.player.hp;
  assert.equal(damagePlayer(g, 10, { kind: 'test', id: 1 }), true);
  assert.ok(g.player.hp < hp);
});

test('dash : les charges se rechargent une par une', () => {
  const g = sandbox();
  const t = g.tuning.dash;
  stepGame(g, input({ moveX: 1, dashPressed: true }));
  steps(g, ticks(t.duration * (1 - 0.35)) + 1);
  stepGame(g, input({ moveX: -1, dashPressed: true }));
  assert.equal(g.player.dashCharges, t.charges - 2);
  steps(g, ticks(t.recharge) + 2);
  assert.equal(g.player.dashCharges, t.charges - 1);
  steps(g, ticks(t.recharge) + 2);
  assert.equal(g.player.dashCharges, t.charges);
});

test('dash : sans charge, rien ne part', () => {
  const g = sandbox();
  g.player.dashCharges = 0;
  stepGame(g, input({ moveX: 1, dashPressed: true }));
  assert.notEqual(g.player.state, 'dash');
});

test('dash : annule la récupération d\'une attaque, immédiatement', () => {
  const g = sandbox();
  dummy(g, 50, 0);
  stepGame(g, input({ attackPressed: true }));
  assert.equal(g.player.state, 'attack');
  stepGame(g, input({ moveX: -1, dashPressed: true }));
  // Le gel d'impact a pu se déclencher : le dash l'interrompt (réactivité avant emphase).
  assert.equal(g.player.state, 'dash');
});

test('dash : un appui pendant le gel d\'impact l\'interrompt', () => {
  const g = sandbox();
  g.hitstop = 0.1;
  stepGame(g, input({ moveX: 1, dashPressed: true }));
  assert.equal(g.hitstop, 0);
  assert.equal(g.player.state, 'dash');
});

test('frappe de dash : une attaque juste après un dash utilise le profil dashStrike', () => {
  const g = sandbox();
  stepGame(g, input({ moveX: 1, dashPressed: true }));
  steps(g, ticks(g.tuning.dash.duration));
  assert.ok(g.player.strikeWindow > 0, 'fenêtre de frappe ouverte après le dash');
  stepGame(g, input({ attackPressed: true }));
  assert.equal(g.player.state, 'attack');
  assert.equal(g.player.attack.strike, true);
});

// ---------------------------------------------------------------- combo, gel, tampon

test('combo : trois coups enchaînés, le 3e est le coup lourd, puis retour au 1er', () => {
  const g = sandbox();
  const seen = [];
  for (let i = 0; i < 240 && seen.length < 4; i++) {
    stepGame(g, input({ attack: true }));
    for (const ev of g.events) if (ev.type === 'attackStart') seen.push(ev.index);
    g.events.length = 0;
  }
  assert.deepEqual(seen.slice(0, 4), [0, 1, 2, 0]);
});

test('coup qui touche : dégâts, knockback, gel d\'impact', () => {
  const g = sandbox();
  const e = dummy(g, 40, 0);
  const hp = e.hp;
  g.player.facing = 0;
  for (let i = 0; i < 20 && e.hp === hp; i++) stepGame(g, input({ attack: true, aimX: 1, aimY: 0 }));
  assert.ok(e.hp < hp, 'l\'ennemi a perdu des PV');
  assert.ok(e.kvx > 0, 'repoussé dans l\'axe du coup');
  assert.ok(g.hitstop > 0, 'gel d\'impact déclenché');
});

test('gel d\'impact : la simulation est figée (le temps de jeu n\'avance pas)', () => {
  const g = sandbox();
  g.hitstop = 0.05;
  const t0 = g.time;
  stepGame(g, input({ moveX: 1 }));
  assert.equal(g.time, t0);
});

test('tampon d\'entrée : une attaque pressée pendant un dash part à la sortie du dash', () => {
  const g = sandbox();
  stepGame(g, input({ moveX: 1, dashPressed: true }));
  stepGame(g, input({ attackPressed: true }));
  assert.equal(g.player.state, 'dash');
  steps(g, ticks(g.tuning.dash.duration));
  assert.equal(g.player.state, 'attack');
});

test('visée assistée : vise l\'ennemi le plus proche quand on ne vise pas', () => {
  const g = sandbox();
  dummy(g, -200, 0);
  const near = dummy(g, 0, 90);
  stepGame(g, input({ attackPressed: true }));
  const a = g.player.attack;
  assert.equal(a.targetId, near.id);
  assert.ok(a.dirY > 0.9);
});

test('visée manuelle : l\'emporte toujours sur la visée assistée', () => {
  const g = sandbox();
  dummy(g, 0, 90);
  stepGame(g, input({ attackPressed: true, aimX: -1, aimY: 0 }));
  assert.ok(g.player.attack.dirX < -0.99);
});

// ---------------------------------------------------------------- gadget, Super, compétence

test('gadget : consomme une charge, repousse, étourdit, détruit les projectiles ennemis', () => {
  const g = sandbox();
  const e = dummy(g, 60, 0, 'imp');
  spawnProjectile(g, { owner: 'enemy', kind: 'arrow', x: g.player.x - 50, y: g.player.y, vx: 300, vy: 0, r: 7, damage: 10, range: 600 });
  const charges = g.player.gadgetCharges;
  stepGame(g, input({ gadgetPressed: true }));
  assert.equal(g.player.gadgetCharges, charges - 1);
  assert.ok(e.stun > 0 || e.dead);
  assert.equal(g.projectiles.filter((p) => p.owner === 'enemy' && !p.dead).length, 0);
});

test('esquive parfaite : jauge de Super et recharge du dash récompensées', () => {
  const g = sandbox();
  stepGame(g, input({ moveX: 1, dashPressed: true }));
  const sup = g.player.superCharge;
  const rec = g.player.dashRecharge;
  damagePlayer(g, 10, { kind: 'test', id: 4242 });
  assert.ok(g.player.superCharge > sup);
  assert.ok(g.player.dashRecharge >= rec + g.tuning.dash.perfectDodgeRefund - 1e-9);
});

test('frappe de dash : attaquer en fin de dash coupe la ruée et frappe', () => {
  const g = sandbox();
  stepGame(g, input({ moveX: 1, dashPressed: true }));
  const t = g.tuning.dash;
  steps(g, ticks(t.duration * (1 - t.strikeCancelFrom)) + 1, { moveX: 1 });
  assert.equal(g.player.state, 'dash');
  stepGame(g, input({ attackPressed: true }));
  assert.equal(g.player.state, 'attack');
  assert.equal(g.player.attack.strike, true);
});

test('Super : se charge en infligeant des dégâts, puis rend invulnérable', () => {
  const g = sandbox();
  g.player.superCharge = 1;
  stepGame(g, input({ superPressed: true }));
  assert.equal(g.player.state, 'super');
  assert.equal(g.player.superCharge, 0);
  const hp = g.player.hp;
  damagePlayer(g, 50, { kind: 'test', id: 5 });
  assert.equal(g.player.hp, hp);
});

test('compétence : la lance part dans la direction glissée et transperce', () => {
  const g = sandbox();
  const a = dummy(g, 120, 0, 'imp');
  const b = dummy(g, 220, 0, 'imp');
  stepGame(g, input({ skillPressed: true, skillAimX: 1, skillAimY: 0 }));
  steps(g, 30);
  assert.ok(a.hp < a.maxHp && b.hp < b.maxHp, 'les deux ennemis alignés sont touchés');
  assert.ok(g.player.skillCd > 0);
});

// ---------------------------------------------------------------- ennemis : équité

test('aucun dégât de contact : un ennemi collé au héros sans attaquer ne blesse pas', () => {
  const g = sandbox();
  const e = dummy(g, 20, 0, 'brute');
  e.cooldown = 999;
  const hp = g.player.hp;
  steps(g, 120);
  assert.equal(g.player.hp, hp);
});

test('jetons d\'attaque : jamais plus de maxAttackers ennemis de mêlée en attaque simultanée', () => {
  const g = sandbox();
  for (let i = 0; i < 8; i++) {
    const a = (i / 8) * Math.PI * 2;
    const e = createEnemy(g, 'imp', g.player.x + Math.cos(a) * 45, g.player.y + Math.sin(a) * 45, { spawnT: 0 });
    e.cooldown = 0;
  }
  g.godMode = true;
  let worst = 0;
  for (let i = 0; i < 400; i++) {
    stepGame(g, input());
    const n = g.enemies.filter((e) => !e.dead && (e.state === 'windup' || e.state === 'strike')).length;
    worst = Math.max(worst, n);
  }
  assert.ok(worst <= g.tuning.combat.maxAttackers, `pire cas ${worst}`);
  assert.ok(worst >= 1, 'les ennemis attaquent bien');
});

test('télégraphe : un ennemi tué pendant sa préparation n\'inflige rien (zone annulée)', () => {
  const g = sandbox();
  const e = dummy(g, 60, 0, 'brute');
  e.cooldown = 0;
  for (let i = 0; i < 60 && g.hazards.length === 0; i++) stepGame(g, input());
  assert.equal(g.hazards.length, 1, 'la brute prépare son impact');
  e.hp = 1;
  e.dead = true;
  const hp = g.player.hp;
  steps(g, ticks(g.tuning.enemies.brute.windup) + 2);
  assert.equal(g.player.hp, hp);
});

test('wall slam : un ennemi projeté contre un mur est étourdi et blessé', () => {
  const g = sandbox();
  const e = dummy(g, 0, 0, 'imp');
  e.x = g.room.pad + e.r + 30;
  e.y = g.room.h / 2;
  g.player.x = e.x + 200;
  e.kvx = -900;
  const hp = e.hp;
  steps(g, 10);
  assert.ok(e.hp < hp);
  assert.ok(g.telemetry.wallSlams >= 1);
});

// ---------------------------------------------------------------- structure des 666 étages

test('666 étages : 111 sections de 6, Gardien au 6e étage de chaque section', () => {
  const g = sandbox();
  const t = g.tuning;
  let bosses = 0;
  for (let f = 1; f <= 666; f++) if (floorInfo(t, f).isBoss) bosses++;
  assert.equal(bosses, 111);
  assert.equal(floorInfo(t, 6).isBoss, true);
  assert.equal(floorInfo(t, 7).indexInSection, 1);
  assert.equal(floorInfo(t, 666).isFinal, true);
  assert.equal(floorInfo(t, 1).circleName, t.floors.circleNames[0]);
  assert.equal(floorInfo(t, 648).circle, 9);
  assert.equal(floorInfo(t, 649).inFinale, true);
});

test('checkpoint : battre le Gardien de l\'étage 6 ouvre la reprise à l\'étage 7', () => {
  assert.equal(checkpointAfterBoss(sandbox().tuning, 6), 7);
});

test('difficulté : croissante et finie jusqu\'à 666', () => {
  const t = sandbox().tuning;
  let prev = floorScaling(t, 1);
  for (const f of [6, 30, 72, 333, 666]) {
    const s = floorScaling(t, f);
    assert.ok(s.hp > prev.hp && s.damage > prev.damage && Number.isFinite(s.hp));
    prev = s;
  }
});

// ---------------------------------------------------------------- progression

test('butin : le nombre d\'affixes suit la rareté, les légendaires ont un pouvoir', () => {
  const g = sandbox();
  for (const r of ITEM_RARITIES) {
    const it = generateItem(g, { rarity: r.id, slot: 'arme' });
    assert.equal(it.affixes.length, r.affixes);
    assert.equal(!!it.power, r.id === 'legendaire');
  }
});

test('bénédictions : un emplacement exclusif remplace l\'ancien, les passifs s\'empilent', () => {
  const g = sandbox();
  const attacks = BOONS.filter((b) => b.slot === 'attack');
  addBoon(g.run, { id: attacks[0].id, rarity: 'commun' });
  addBoon(g.run, { id: attacks[1].id, rarity: 'commun' });
  assert.equal(g.run.boons.filter((b) => boonDef(b.id).slot === 'attack').length, 1);
  const passives = BOONS.filter((b) => b.slot === 'passive' && b.stat);
  addBoon(g.run, { id: passives[0].id, rarity: 'commun' });
  addBoon(g.run, { id: passives[1].id, rarity: 'commun' });
  assert.equal(g.run.boons.filter((b) => boonDef(b.id).slot === 'passive').length, 2);
});

test('arme : une arme plus forte augmente les dégâts de tous les coups', () => {
  const g = sandbox();
  const e1 = dummy(g, 40, 0);
  for (let i = 0; i < 20 && e1.hp === e1.maxHp; i++) stepGame(g, input({ attack: true, aimX: 1, aimY: 0 }));
  const base = e1.maxHp - e1.hp;
  const g2 = sandbox();
  g2.run.items.arme = { ...g2.run.items.arme, base: { damage: g2.tuning.weaponBase * 2 } };
  recomputeStats(g2);
  const e2 = dummy(g2, 40, 0);
  for (let i = 0; i < 20 && e2.hp === e2.maxHp; i++) stepGame(g2, input({ attack: true, aimX: 1, aimY: 0 }));
  const doubled = e2.maxHp - e2.hp;
  assert.ok(doubled >= base * 1.8, `dégâts ${base} -> ${doubled}`);
});

test('équipement : les affixes modifient les statistiques du héros', () => {
  const g = sandbox();
  const item = generateItem(g, { slot: 'armure', rarity: 'rare' });
  item.base = { hp: g.run.items.armure.base.hp }; // même base : on isole l'affixe
  item.affixes = [{ stat: 'maxHpBonus', value: 25, format: 'flat' }];
  const before = g.player.maxHp;
  g.run.items.armure = item;
  recomputeStats(g);
  assert.equal(g.player.maxHp, before + 25);
});

test('mort sans instantané : bénédictions perdues, équipement conservé, moitié de l\'or, reprise au checkpoint', () => {
  const g = sandbox();
  g.meta.checkpoints = [1, 7];
  g.run.gold = 100;
  addBoon(g.run, { id: BOONS[0].id, rarity: 'commun' });
  const item = generateItem(g, { slot: 'arme', rarity: 'magique' });
  g.run.items.arme = item;
  g.godMode = false;
  damagePlayer(g, 9999, { kind: 'test', id: 77 });
  steps(g, ticks(2));
  assert.equal(g.mode, 'dead');
  assert.equal(applyCommand(g, { type: 'respawn', floor: 7 }), true);
  assert.equal(g.mode, 'play');
  assert.equal(g.run.floor, 7);
  assert.equal(g.run.boons.length, 0);
  assert.equal(g.run.items.arme, item);
  assert.equal(g.run.gold, Math.floor(100 * g.tuning.economy.deathGoldKeep));
  assert.equal(g.player.hp, g.player.maxHp);
});

test('salle nettoyée : récompense posée, portes fermées tant qu\'elle n\'est pas prise', () => {
  const g = sandbox();
  g.room.plan = { kind: 'combat', reward: 'boon', family: 'colere' };
  onRoomClear(g);
  assert.ok(g.room.interact && g.room.interact.kind === 'boon');
  assert.ok(g.room.doors.length >= 1);
  assert.ok(g.room.doors.every((d) => !d.open));
  // Le héros touche la récompense -> menu -> choix -> portes ouvertes.
  g.player.x = g.room.interact.x;
  g.player.y = g.room.interact.y;
  // Le dernier ennemi tombé déclenche un gel d'impact : quelques pas avant le contact.
  for (let i = 0; i < 30 && g.mode === 'play'; i++) stepGame(g, input());
  assert.equal(g.mode, 'choice');
  const tick = g.tick;
  stepGame(g, input());
  assert.equal(g.tick, tick, 'la simulation est en pause pendant un choix');
  applyCommand(g, { type: 'choose', index: 0 });
  assert.equal(g.mode, 'play');
  assert.equal(g.run.boons.length, 1);
  assert.ok(g.room.doors.every((d) => d.open));
});

test('portes : l\'étage 5 mène au Gardien, l\'antichambre propose marchand ou autel', () => {
  const g = sandbox();
  enterFloor(g, 4, { reward: 'gold' });
  g.room.plan = { kind: 'combat', reward: 'gold' };
  onRoomClear(g);
  assert.deepEqual(g.room.doors.map((d) => d.reward).sort(), ['event', 'shop']);
  enterFloor(g, 5, { reward: 'shop' });
  assert.deepEqual(g.room.doors.map((d) => d.reward), ['boss']);
});

test('checkpoint : vaincre un Gardien fige le build ; mourir ensuite le restaure', () => {
  const g = sandbox();
  enterFloor(g, 6, null);
  g.spawns.length = 0;
  g.enemies.length = 0;
  addBoon(g.run, { id: BOONS[0].id, rarity: 'rare' });
  g.run.gold = 80;
  g.room.plan = { kind: 'boss', reward: 'boss' };
  g.room.kind = 'boss';
  onRoomClear(g);
  assert.ok(g.meta.checkpoints.includes(7));
  // Après le checkpoint, le build change, puis le héros meurt.
  addBoon(g.run, { id: BOONS[3].id, rarity: 'commun' });
  g.run.gold = 5;
  damagePlayer(g, 99999, { kind: 'test', id: 31 });
  steps(g, ticks(2));
  assert.equal(g.mode, 'dead');
  applyCommand(g, { type: 'respawn', floor: 7 });
  assert.deepEqual(g.run.boons.map((b) => b.id), [BOONS[0].id]);
  assert.equal(g.run.gold, 80);
  assert.equal(g.run.floor, 7);
});

test('Gardien vaincu : ses impacts en attente et ses orbes en vol ne blessent plus', () => {
  const g = createGame({ seed: 1, startFloor: 6 });
  g.events.length = 0;
  let boss = g.enemies.find((e) => e.boss);
  for (let i = 0; i < 1200 && !g.hazards.some((h) => h.hitsPlayer); i++) stepGame(g, input());
  assert.ok(g.hazards.some((h) => h.hitsPlayer), 'le Gardien a lancé une attaque');
  spawnProjectile(g, { owner: 'enemy', kind: 'bossOrb', x: g.player.x + 200, y: g.player.y, vx: -300, vy: 0, r: 9, damage: 12, range: 900 });
  boss = g.enemies.find((e) => e.boss);
  boss.hp = 0;
  boss.dead = true;
  const hp0 = g.player.hp;
  steps(g, 120);
  assert.ok(g.player.hp >= hp0, `PV ${hp0} -> ${g.player.hp}`);
  assert.equal(g.hazards.filter((h) => h.hitsPlayer && !h.done).length, 0);
});

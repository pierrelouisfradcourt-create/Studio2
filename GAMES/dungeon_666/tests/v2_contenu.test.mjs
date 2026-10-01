// CONTENU AJOUTÉ LE 2026-10-01 — 14 bénédictions (2 par famille), 4 duos, 6 pouvoirs légendaires,
// 4 événements d'autel, 4 dispositions de salle. Un test par élément : l'effet se produit dans
// une vraie partie (createGame + stepGame, le seul chemin de dégâts), il vaut ce que son texte
// annonce (les nombres sont lus dans les données, jamais recopiés), il ne casse pas le
// déterminisme. Plus : tout texte {v} se résout, tout libellé d'autel est chiffré.
// Lancement : node --test tests/

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createGame, stepGame, applyCommand, emptyInput, stateHash, DT } from '../src/sim/game.mjs';
import { createTuning } from '../src/sim/config.mjs';
import { createEnemy } from '../src/sim/enemies.mjs';
import { damageEnemy, damagePlayer, healPlayer, killEnemy } from '../src/sim/combat.mjs';
import { BOONS, DUOS, PACTS, RARITIES, FAMILIES, addBoon, boonDef, boonValue, boonText, rollBoonOffer } from '../src/sim/boons.mjs';
import { LEGENDARY_POWERS, generateItem } from '../src/sim/loot.mjs';
import { recomputeStats } from '../src/sim/stats.mjs';
import { EVENTS, enterFloor, openInteract, forgeTargets, respawn, describeItem } from '../src/sim/run.mjs';
import { LAYOUTS, LAYOUT_IDS, COMBAT_LAYOUTS, playerStart, rewardSpot } from '../src/sim/room.mjs';
import { pointBlocked } from '../src/sim/physics.mjs';
import { floorInfo } from '../src/sim/floors.mjs';
import { POLICIES, resolveChoice } from '../tools/bots.mjs';

// ---------------------------------------------------------------- le contenu sous test

const NEW_BOONS = {
  colere: ['represailles', 'coup_de_sang'],
  paresse: ['baillement', 'mur_du_sommeil'],
  avarice: ['prime_de_risque', 'tresor_de_guerre'],
  gourmandise: ['bouchee_double', 'ripaille'],
  luxure: ['baiser_vole', 'ivresse'],
  envie: ['eclair_de_depit', 'mauvais_oeil'],
  orgueil: ['invaincu', 'mepris'],
};
const NEW_DUOS = ['passion_brulante', 'faire_les_poches', 'trop_plein', 'foudre_du_dedain'];
const NEW_POWERS = ['eperons_alastor', 'marteau_belial', 'dard_lilith', 'main_de_gloire', 'fracas_moloch', 'linceul_abaddon'];
const NEW_EVENTS = ['pacte_ames', 'forge', 'miroir', 'clepsydre'];
const NEW_LAYOUTS = ['colonnade', 'chicane', 'goulet', 'ilots'];
const EPS = 1e-9;

// ---------------------------------------------------------------- outils

/** Partie de test : salle vidée (aucune vague), héros au centre, jamais de critique de base. */
function arena(boons = [], opts = {}) {
  const g = createGame({ seed: 11, ...opts });
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
  g.tuning.combat.critChance = 0; // les montants attendus sont exacts
  for (const b of boons) give(g, b);
  g.events.length = 0;
  return g;
}

function give(g, id, rarity = 'commun') {
  assert.ok(boonDef(id), `bénédiction inconnue : ${id}`);
  addBoon(g.run, { id, rarity });
  recomputeStats(g);
}

/** Équipe un talisman légendaire portant le pouvoir `id` (le chemin réel : recomputeStats). */
function wear(g, id) {
  assert.ok(LEGENDARY_POWERS.some((p) => p.id === id), `pouvoir inconnu : ${id}`);
  g.run.items.talisman = { id: 9001, slot: 'talisman', rarity: 'legendaire', name: 'Relique d\'essai', level: 1, affixes: [], power: id, base: {}, score: 0 };
  recomputeStats(g);
}

const input = (over = {}) => ({ ...emptyInput(), ...over });
const ticks = (seconds) => Math.ceil(seconds / DT);
function steps(g, n, over = {}) {
  for (let i = 0; i < n; i++) stepGame(g, input(over));
}

/** Ennemi d'essai : ne riposte pas ; `hp` (facultatif) le rend increvable ou fragile. */
function dummy(g, dx, dy, kind = 'brute', hp = 0) {
  const e = createEnemy(g, kind, g.player.x + dx, g.player.y + dy, { spawnT: 0 });
  e.cooldown = 99;
  if (hp) e.hp = e.maxHp = hp;
  return e;
}

const V = (id, rarity = 'commun') => boonValue(boonDef(id), rarity);
const procOf = (g, id) => g.player.procs.find((pr) => pr.boon === id);
const powerProc = (id) => LEGENDARY_POWERS.find((p) => p.id === id).procs[0];
const events = (g, type) => g.events.filter((ev) => ev.type === type);

/** Esquive parfaite réelle : un dash, puis un coup reçu pendant ses i-frames. */
function perfectDodge(g, id = 4242) {
  stepGame(g, input({ moveX: -1, dashPressed: true }));
  assert.equal(g.player.state, 'dash');
  const landed = damagePlayer(g, 10, { kind: 'test', id, x: g.player.x, y: g.player.y });
  assert.equal(landed, false);
  assert.equal(events(g, 'dodge').length >= 1, true, 'esquive parfaite comptée');
}

/** Dégâts d'un coup d'arme de 100 sur `e` (le chemin unique : damageEnemy). */
const hit100 = (g, e, kind = 'melee') => damageEnemy(g, e, { kind, amount: 100, canCrit: false });

/** Projette `e` contre le mur de gauche (vrai knockback, vraie collision) ; rend true s'il a percuté. */
function slam(g, e) {
  e.x = g.room.pad + e.r + 30;
  e.y = g.room.h / 2;
  g.player.x = e.x + 300;
  g.player.y = e.y;
  e.kvx = -900;
  const before = g.telemetry.wallSlams;
  for (let i = 0; i < 12 && g.telemetry.wallSlams === before; i++) stepGame(g, input());
  return g.telemetry.wallSlams > before;
}

/** Nettoie la salle de combat en cours par le vrai flux (vagues, updateWaves, onRoomClear). */
function clearRoom(g) {
  for (let i = 0; i < 4000 && !g.room.cleared; i++) {
    for (const e of g.enemies) if (!e.dead && e.spawnT <= 0) killEnemy(g, e, { kind: 'melee' });
    stepGame(g, input());
  }
  assert.ok(g.room.cleared, 'salle nettoyée');
}

/** Tient l'attaque contre un ennemi increvable ; rend les coups portés {finishers, others}. */
function comboOn(g, seconds, e) {
  const fin = g.tuning.combo[g.tuning.combo.length - 1].damage;
  const from = g.events.length;
  steps(g, ticks(seconds), { attack: true });
  steps(g, ticks(0.3)); // les explosions à retardement partent
  const hits = g.events.slice(from).filter((ev) => ev.type === 'hit' && ev.id === e.id);
  return { finishers: hits.filter((h) => h.kind === 'melee' && h.amount === fin).length, hits };
}

/** Frappe de dash réelle sur l'ennemi placé à droite du héros. */
function dashStrike(g) {
  const t = g.tuning.dash;
  stepGame(g, input({ moveX: 1, dashPressed: true }));
  steps(g, ticks(t.duration * (1 - t.strikeCancelFrom)) + 1, { moveX: 1 });
  stepGame(g, input({ attackPressed: true }));
  assert.equal(g.player.attack?.strike, true, 'frappe de dash partie');
  steps(g, ticks(0.4));
}

/** Ouvre l'autel `id` par le vrai flux (porte « Autel », objet touché) ; rend le panneau. */
function altar(g, id) {
  enterFloor(g, g.run.floor + 1, { reward: 'event' });
  assert.equal(g.room.kind, 'event');
  g.room.interact.event = id;
  openInteract(g);
  assert.equal(g.mode, 'choice');
  assert.equal(g.choice.kind, 'event');
  return g.choice;
}

/** Même graine, mêmes entrées (bot), même build : même état, image par image. */
function assertDeterministic(boons, { power = null, seconds = 6, floor = 5 } = {}) {
  const play = () => {
    const g = createGame({ seed: 77, startFloor: floor });
    for (const b of boons) addBoon(g.run, { id: b, rarity: 'rare' });
    if (power) wear(g, power);
    recomputeStats(g);
    const mem = {};
    const marks = [];
    for (let i = 0; i < ticks(seconds); i++) {
      if (g.mode === 'choice') resolveChoice(g, 'skilled');
      else if (g.mode === 'play') stepGame(g, POLICIES.skilled(g, mem));
      g.events.length = 0;
      if (i % 30 === 0) marks.push(`${stateHash(g)}:${g.rng.combat.s}:${g.rng.gen.s}:${g.player.superCharge}:${g.run.gold}`);
    }
    return marks;
  };
  assert.deepEqual(play(), play(), `déterminisme : ${[...boons, power].filter(Boolean).join(', ')}`);
}

// ---------------------------------------------------------------- inventaire et textes

test('contenu : 2 bénédictions nouvelles par famille, 4 duos, 6 pouvoirs, 4 autels, 4 dispositions — tous présents dans les tables', () => {
  for (const [fam, ids] of Object.entries(NEW_BOONS)) {
    assert.ok(FAMILIES[fam]);
    for (const id of ids) assert.equal(BOONS.find((b) => b.id === id)?.family, fam, `${id} : famille ${fam}`);
    assert.equal(BOONS.filter((b) => b.family === fam).length, 5, `${fam} : 3 d'origine + 2`);
  }
  for (const id of NEW_DUOS) assert.equal(DUOS.find((d) => d.id === id)?.families.length, 2, `duo ${id}`);
  const pairs = DUOS.map((d) => [...d.families].sort().join('+'));
  assert.equal(new Set(pairs).size, DUOS.length, 'chaque duo unit une paire de familles différente');
  for (const id of NEW_POWERS) assert.ok(LEGENDARY_POWERS.some((p) => p.id === id), `pouvoir ${id}`);
  for (const id of NEW_EVENTS) assert.ok(EVENTS.some((e) => e.id === id), `autel ${id}`);
  for (const id of NEW_LAYOUTS) assert.ok(LAYOUT_IDS.includes(id), `disposition ${id}`);
  const ids = [...BOONS, ...DUOS, ...PACTS].map((b) => b.id);
  assert.equal(new Set(ids).size, ids.length, 'identifiants uniques');
});

test('textes : chaque {v} se résout, à toute rareté, en le nombre que la partie applique', () => {
  for (const def of [...BOONS, ...DUOS, ...PACTS]) {
    assert.equal((def.text.match(/\{v\}/g) ?? []).length, def.noScale && !def.text.includes('{v}') ? 0 : 1, `${def.id} : un seul {v}`);
    for (const r of RARITIES) {
      const shown = boonValue(def, r.id);
      const text = boonText(def, r.id);
      assert.ok(!/[{}]/.test(text), `${def.id} (${r.id}) : accolade restante dans « ${text} »`);
      if (def.text.includes('{v}')) assert.ok(text.includes(String(shown)), `${def.id} (${r.id}) : ${shown} absent de « ${text} »`);
      // Ce que la partie applique : la stat ou la valeur du proc, au même nombre que le texte.
      const g = arena();
      addBoon(g.run, { id: def.id, rarity: r.id });
      const base = structuredClone(g.player.stats);
      recomputeStats(g);
      const expect = def.pct ? shown / 100 : shown;
      if (def.proc) {
        const pr = procOf(g, def.id);
        assert.ok(pr, `${def.id} : proc présent`);
        const applied = def.proc.valueFixed !== undefined ? pr.chance : pr.value;
        assert.ok(Math.abs(applied - expect) < EPS, `${def.id} (${r.id}) : la partie applique ${applied}, le texte dit ${shown}`);
      } else if (def.stat) {
        const delta = g.player.stats[def.stat] - base[def.stat];
        assert.ok(Math.abs(Math.abs(delta) - expect) < EPS, `${def.id} (${r.id}) : stat ${def.stat} ${delta}, le texte dit ${shown}`);
      }
    }
  }
});

test('textes : les pouvoirs légendaires nouveaux annoncent les nombres de leurs données', () => {
  const fr = (n) => String(n).replace('.', ',');
  for (const id of NEW_POWERS) {
    const pw = LEGENDARY_POWERS.find((p) => p.id === id);
    assert.ok(pw.text.length > 0 && !/[{}]/.test(pw.text), `${id} : texte`);
    for (const pr of pw.procs) {
      assert.ok(pw.text.includes(fr(pr.value)), `${id} : ${pr.value} absent de « ${pw.text} »`);
      for (const k of ['radius', 'bounces']) if (pr[k] !== undefined) assert.ok(pw.text.includes(fr(pr[k])), `${id} : ${k} ${pr[k]} absent du texte`);
    }
    // Affiché par ses données sur la carte d'objet (describeItem), nommé par generateItem.
    const g = arena();
    wear(g, id);
    assert.equal(describeItem(g.run.items.talisman).power, pw.text);
    assert.ok(g.player.procs.some((pr) => pr.effect === pw.procs[0].effect && pr.on === pw.procs[0].on), `${id} : proc actif une fois porté`);
  }
  // Les nouveaux pouvoirs tombent vraiment (tirage de generateItem).
  const g = arena();
  const seen = new Set();
  for (let i = 0; i < 300; i++) seen.add(generateItem(g, { rarity: 'legendaire' }).power);
  for (const id of NEW_POWERS) assert.ok(seen.has(id), `${id} : jamais tiré en 300 objets légendaires`);
});

test('offres : les nouvelles bénédictions sont proposées, les duos nouveaux aussi une fois les deux familles réunies ; un pacte jamais', () => {
  const g = arena();
  const offered = new Set();
  for (let i = 0; i < 400; i++) for (const fam of Object.keys(FAMILIES)) for (const o of rollBoonOffer(g, fam)) offered.add(o.id);
  for (const ids of Object.values(NEW_BOONS)) for (const id of ids) assert.ok(offered.has(id), `${id} : jamais offerte`);
  for (const p of PACTS) assert.ok(!offered.has(p.id), `${p.id} : un pacte ne s'offre pas`);
  for (const id of NEW_DUOS) {
    const duo = boonDef(id);
    const h = arena();
    give(h, BOONS.find((b) => b.family === duo.families[0]).id);
    let seen = false;
    for (let i = 0; i < 200 && !seen; i++) seen = rollBoonOffer(h, duo.families[1]).some((o) => o.id === id);
    assert.ok(seen, `${id} : jamais offert avec ${duo.families.join(' + ')}`);
  }
});

// ---------------------------------------------------------------- Colère

test('Représailles (Colère) : une esquive parfaite donne +{v} % de dégâts pendant 3 s, puis plus rien', () => {
  const g = arena(['represailles']);
  const e = dummy(g, 300, 0, 'brute', 1e6);
  assert.equal(hit100(g, e), 100);
  perfectDodge(g);
  const pr = procOf(g, 'represailles');
  assert.equal(pr.duration, 3);
  assert.equal(g.player.surge, 3);
  assert.equal(hit100(g, e), Math.round(100 * (1 + V('represailles') / 100)));
  steps(g, ticks(3) + 2);
  assert.equal(g.player.surge, 0);
  assert.equal(hit100(g, e), 100, 'l\'élan retombe');
  // Sans esquive (dash dans le vide), aucun élan.
  const h = arena(['represailles']);
  stepGame(h, input({ moveX: 1, dashPressed: true }));
  assert.equal(h.player.surge, 0);
  assertDeterministic(['represailles']);
});

test('Coup de sang (Colère) : le dernier coup du combo — et lui seul — fait exploser la cible pour {v} dégâts', () => {
  const g = arena(['coup_de_sang']);
  const e = dummy(g, 60, 0, 'brute', 1e6);
  const { finishers, hits } = comboOn(g, 1.6, e);
  assert.ok(finishers >= 2, `finishers portés : ${finishers}`);
  const blasts = hits.filter((h) => h.kind === 'blast');
  assert.equal(blasts.length, finishers, 'une explosion par dernier coup porté');
  for (const b of blasts) assert.equal(b.amount, V('coup_de_sang'));
  assert.equal(g.events.filter((ev) => ev.type === 'hazard' && ev.kind === 'sinBlast').length, finishers);
  assert.equal(procOf(g, 'coup_de_sang').radius, 70);
  assertDeterministic(['coup_de_sang']);
});

// ---------------------------------------------------------------- Paresse

test('Bâillement (Paresse) : une esquive parfaite blesse de {v} et ralentit de 50 % pendant 3 s autour du héros', () => {
  const g = arena(['baillement']);
  const pr = procOf(g, 'baillement');
  const near = dummy(g, 0, 100, 'brute', 1000);
  const far = dummy(g, 0, pr.radius + 200, 'brute', 1000);
  perfectDodge(g);
  assert.equal(near.hp, 1000 - V('baillement'));
  assert.equal(near.chill, 3);
  assert.equal(near.chillMult, 0.5);
  assert.equal(far.hp, 1000, 'hors du rayon : rien');
  assert.equal(far.chill, 0);
  assert.equal(events(g, 'dashNova').length, 1, 'l\'onde est montrée');
  assertDeterministic(['baillement']);
});

test('Mur du sommeil (Paresse) : un ennemi projeté contre un mur reste sonné {v} s (0,45 s sans elle)', () => {
  const base = arena();
  const e0 = dummy(base, 0, 0, 'imp', 500);
  assert.ok(slam(base, e0));
  assert.ok(e0.stun <= base.tuning.wallSlam.stun && e0.stun > 0);
  const g = arena(['mur_du_sommeil']);
  const e = dummy(g, 0, 0, 'imp', 500);
  assert.ok(slam(g, e));
  assert.ok(e.stun > V('mur_du_sommeil') - 3 * DT && e.stun <= V('mur_du_sommeil'), `sonné ${e.stun} s`);
  assert.equal(e.state, 'stunned');
  assert.ok(V('mur_du_sommeil') > g.tuning.wallSlam.stun);
  assertDeterministic(['mur_du_sommeil']);
});

// ---------------------------------------------------------------- Avarice

test('Prime de risque (Avarice) : salle nettoyée sans être touché = +{v} or ; touché, rien', () => {
  const g = createGame({ seed: 21, startFloor: 3 });
  give(g, 'prime_de_risque');
  g.events.length = 0;
  clearRoom(g);
  const paid = events(g, 'gold');
  assert.equal(paid.length, 1);
  assert.equal(paid[0].amount, V('prime_de_risque'));
  assert.equal(g.run.gold, V('prime_de_risque'));
  const h = createGame({ seed: 21, startFloor: 3 });
  give(h, 'prime_de_risque');
  assert.equal(damagePlayer(h, 5, { kind: 'test', id: 1 }), true);
  h.events.length = 0;
  clearRoom(h);
  assert.equal(events(h, 'gold').length, 0, 'blessé dans la salle : pas de prime');
  assert.equal(h.run.gold, 0);
  assertDeterministic(['prime_de_risque']);
});

test('Trésor de guerre (Avarice) : +{v} % de dégâts par tranche de 25 or en bourse, 5 tranches au plus', () => {
  const g = arena(['tresor_de_guerre']);
  const pr = procOf(g, 'tresor_de_guerre');
  const e = dummy(g, 300, 0, 'brute', 1e6);
  const v = V('tresor_de_guerre');
  assert.deepEqual([pr.per, pr.cap], [25, 5]);
  g.run.gold = 24;
  assert.equal(hit100(g, e), 100);
  g.run.gold = 60;
  assert.equal(hit100(g, e), 100 + 2 * v);
  g.run.gold = 5000;
  assert.equal(hit100(g, e), 100 + 5 * v, 'plafond');
  assertDeterministic(['tresor_de_guerre']);
});

// ---------------------------------------------------------------- Gourmandise

test('Bouchée double (Gourmandise) : le dernier coup du combo rend {v} PV par ennemi touché', () => {
  const g = arena(['bouchee_double']);
  const e = dummy(g, 60, 0, 'brute', 1e6);
  g.player.hp = g.player.maxHp - 60;
  const hp0 = g.player.hp;
  const { finishers } = comboOn(g, 1.6, e);
  assert.ok(finishers >= 2);
  assert.ok(Math.abs(g.player.hp - hp0 - finishers * V('bouchee_double')) < EPS, `soigné de ${g.player.hp - hp0} pour ${finishers} derniers coups`);
  assert.equal(events(g, 'heal').length, finishers);
  assert.equal(boonDef('bouchee_double').slot, 'attack', 'emplacement d\'attaque : un choix contre Sang dévoré');
  assertDeterministic(['bouchee_double']);
});

test('Ripaille (Gourmandise) : lancer le Super rend {v} PV', () => {
  const g = arena(['ripaille']);
  g.player.hp = g.player.maxHp - 40;
  const hp0 = g.player.hp;
  g.player.superCharge = 1;
  stepGame(g, input({ superPressed: true }));
  assert.equal(g.player.state, 'super');
  assert.equal(g.player.hp, hp0 + V('ripaille'));
  assert.equal(events(g, 'heal')[0].amount, V('ripaille'));
  assertDeterministic(['ripaille']);
});

// ---------------------------------------------------------------- Luxure

test('Baiser volé (Luxure) : la frappe de dash — pas un coup ordinaire — rend vulnérable de {v} % pendant 4 s', () => {
  const g = arena(['baiser_vole']);
  const e = dummy(g, 200, 0, 'brute', 1e6);
  hit100(g, e, 'melee');
  assert.equal(e.vuln, 0, 'un coup ordinaire ne marque pas');
  dashStrike(g);
  const struck = events(g, 'hit').filter((h) => h.kind === 'strike');
  assert.equal(struck.length, 1, 'la frappe de dash a porté');
  assert.ok(e.vuln > 4 - 0.5 && e.vuln <= 4, `vulnérable encore ${e.vuln} s`);
  assert.ok(Math.abs(e.vulnMult - V('baiser_vole') / 100) < EPS);
  assert.equal(hit100(g, e), Math.round(100 * (1 + V('baiser_vole') / 100)));
  assert.equal(boonDef('baiser_vole').slot, 'dash');
  assertDeterministic(['baiser_vole']);
});

test('Ivresse (Luxure) : une esquive parfaite charge le Super de {v} % en plus des 6 % de base', () => {
  const g = arena(['ivresse']);
  g.player.superCharge = 0;
  perfectDodge(g);
  assert.ok(Math.abs(g.player.superCharge - (g.tuning.dash.perfectDodgeSuper + V('ivresse') / 100)) < EPS, `jauge ${g.player.superCharge}`);
  const h = arena();
  h.player.superCharge = 0;
  perfectDodge(h);
  assert.ok(Math.abs(h.player.superCharge - h.tuning.dash.perfectDodgeSuper) < EPS);
  assertDeterministic(['ivresse']);
});

// ---------------------------------------------------------------- Envie

test('Éclair de dépit (Envie) : chaque dash lance un éclair de {v} dégâts sur 3 ennemis au plus, de proche en proche', () => {
  const g = arena(['eclair_de_depit']);
  const pr = procOf(g, 'eclair_de_depit');
  const foes = [60, 120, 180, 240].map((dx) => dummy(g, dx, 0, 'imp', 1000));
  const out = dummy(g, 0, pr.range + 300, 'imp', 1000);
  stepGame(g, input({ moveX: -1, dashPressed: true }));
  assert.equal(pr.bounces, 3);
  assert.deepEqual(foes.map((e) => e.hp), [1000 - V('eclair_de_depit'), 1000 - V('eclair_de_depit'), 1000 - V('eclair_de_depit'), 1000]);
  assert.equal(out.hp, 1000, 'hors de portée');
  assert.equal(events(g, 'chain').length, 3);
  assert.equal(boonDef('eclair_de_depit').slot, 'dash', 'emplacement de dash : un choix contre Pas de braise');
  assertDeterministic(['eclair_de_depit']);
});

test('Mauvais œil (Envie) : chaque ennemi tué lance un éclair de {v} dégâts, 2 rebonds', () => {
  const g = arena(['mauvais_oeil']);
  const pr = procOf(g, 'mauvais_oeil');
  const victim = dummy(g, 100, 0, 'imp', 5);
  const a = dummy(g, 160, 0, 'imp', 1000);
  const b = dummy(g, 220, 0, 'imp', 1000);
  const c = dummy(g, 280, 0, 'imp', 1000);
  hit100(g, victim);
  assert.equal(victim.dead, true);
  assert.equal(pr.bounces, 2);
  assert.deepEqual([a.hp, b.hp, c.hp], [1000 - V('mauvais_oeil'), 1000 - V('mauvais_oeil'), 1000]);
  assert.equal(events(g, 'chain').length, 2);
  // Réaction en chaîne bornée : un éclair qui tue relance un éclair, jamais sans fin.
  const h = arena(['mauvais_oeil']);
  const pack = [100, 150, 200, 250, 300].map((dx) => dummy(h, dx, 0, 'imp', 5));
  hit100(h, pack[0]);
  assert.ok(pack.every((e) => e.dead), 'la meute fragile tombe en cascade');
  assertDeterministic(['mauvais_oeil']);
});

// ---------------------------------------------------------------- Orgueil

test('Invaincu (Orgueil) : +{v} % de dégâts par salle nettoyée sans être touché (5 au plus) ; une blessure remet à zéro', () => {
  const g = createGame({ seed: 23, startFloor: 3 });
  g.tuning.combat.critChance = 0;
  give(g, 'invaincu');
  const v = V('invaincu');
  assert.equal(g.run.streak, 0);
  clearRoom(g);
  assert.equal(g.run.streak, 1);
  const e = createEnemy(g, 'brute', 300, 300, { spawnT: 0 });
  e.hp = e.maxHp = 1e6;
  assert.equal(hit100(g, e), 100 + v);
  g.run.streak = 40;
  assert.equal(hit100(g, e), 100 + procOf(g, 'invaincu').cap * v, 'plafond à 5 salles');
  assert.equal(procOf(g, 'invaincu').cap, 5);
  g.player.iframes = 0;
  assert.equal(damagePlayer(g, 3, { kind: 'test', id: 2 }), true);
  assert.equal(g.run.streak, 0);
  assert.equal(hit100(g, e), 100, 'blessé : l\'orgueil retombe');
  // Une salle où le héros a été blessé n'allonge pas la série.
  const h = createGame({ seed: 23, startFloor: 3 });
  damagePlayer(h, 3, { kind: 'test', id: 2 });
  clearRoom(h);
  assert.equal(h.run.streak, 0);
  assertDeterministic(['invaincu']);
});

test('Mépris (Orgueil) : +{v} % de chances de critique contre un ennemi sonné, rien contre les autres', () => {
  const g = arena(['mepris']);
  assert.ok(Math.abs(procOf(g, 'mepris').value - V('mepris') / 100) < EPS);
  // Épique au niveau 2 : 90 % × 1,5 > 100 % — tout coup sur un ennemi sonné est critique.
  const h = arena();
  addBoon(h.run, { id: 'mepris', rarity: 'epique' });
  addBoon(h.run, { id: 'mepris', rarity: 'epique' });
  recomputeStats(h);
  assert.ok(procOf(h, 'mepris').value >= 1);
  const e = dummy(h, 300, 0, 'brute', 1e6);
  for (let i = 0; i < 20; i++) damageEnemy(h, e, { kind: 'melee', amount: 10, canCrit: true });
  assert.ok(events(h, 'hit').every((ev) => !ev.crit), 'debout : jamais critique (chance de base nulle dans ce test)');
  h.events.length = 0;
  e.stun = 5;
  for (let i = 0; i < 20; i++) damageEnemy(h, e, { kind: 'melee', amount: 10, canCrit: true });
  assert.ok(events(h, 'hit').every((ev) => ev.crit), 'sonné : toujours critique');
  assertDeterministic(['mepris']);
});

// ---------------------------------------------------------------- duos

test('duo Passion brûlante (Colère + Luxure) : lancer le Super enflamme les ennemis proches, {v} dégâts/s pendant 4 s', () => {
  const g = arena(['passion_brulante']);
  const pr = procOf(g, 'passion_brulante');
  const near = dummy(g, 150, 0, 'brute', 1e6);
  const far = dummy(g, pr.radius + 200, 0, 'brute', 1e6);
  g.player.superCharge = 1;
  stepGame(g, input({ superPressed: true }));
  assert.ok(near.burn > 4 - 2 * DT && near.burn <= 4, `en feu encore ${near.burn} s`);
  assert.equal(pr.duration, 4);
  assert.equal(near.burnDps, V('passion_brulante'));
  assert.equal(far.burn, 0);
  assert.deepEqual(boonDef('passion_brulante').families, ['colere', 'luxure']);
  assertDeterministic(['passion_brulante']);
});

test('duo Faire les poches (Paresse + Avarice) : un ennemi projeté contre un mur lâche {v} or', () => {
  const g = arena(['faire_les_poches']);
  const e = dummy(g, 0, 0, 'imp', 500);
  g.events.length = 0;
  assert.ok(slam(g, e));
  assert.equal(g.run.gold, V('faire_les_poches'));
  assert.equal(events(g, 'gold')[0].amount, V('faire_les_poches'));
  assert.equal(V('faire_les_poches', 'epique'), V('faire_les_poches'), 'montant fixe : l\'or reste un entier annoncé');
  assertDeterministic(['faire_les_poches']);
});

test('duo Trop-plein (Gourmandise + Orgueil) : chaque PV soigné au-delà du maximum charge le Super de {v} %', () => {
  const g = arena(['trop_plein']);
  const p = g.player;
  p.superCharge = 0;
  p.hp = p.maxHp - 4;
  healPlayer(g, 14, true);
  assert.equal(p.hp, p.maxHp);
  assert.ok(Math.abs(p.superCharge - 10 * (V('trop_plein') / 100)) < EPS, `jauge ${p.superCharge} pour 10 PV de trop`);
  p.hp = p.maxHp - 20;
  healPlayer(g, 10, true);
  assert.ok(Math.abs(p.superCharge - 10 * (V('trop_plein') / 100)) < EPS, 'un soin qui ne déborde pas ne charge rien');
  // Jamais pendant le Super : il ne se recharge pas lui-même.
  p.superCharge = 1;
  stepGame(g, input({ superPressed: true }));
  healPlayer(g, 500, true);
  assert.equal(p.superCharge, 0);
  assertDeterministic(['trop_plein', 'festin']);
});

test('duo Foudre du dédain (Envie + Orgueil) : un éclair achève un ennemi sous {v} % de PV, jamais un Gardien', () => {
  const g = arena(['eclair_de_depit', 'foudre_du_dedain']);
  const limit = V('foudre_du_dedain') / 100;
  const weak = dummy(g, 60, 0, 'brute', 1000);
  weak.hp = Math.floor(1000 * limit) - 1 + V('eclair_de_depit'); // sous le seuil après l'éclair, loin de mourir des dégâts
  const strong = dummy(g, 120, 0, 'brute', 1000);
  stepGame(g, input({ moveX: -1, dashPressed: true }));
  assert.equal(weak.dead, true, 'achevé');
  assert.equal(strong.dead, false);
  assert.equal(strong.hp, 1000 - V('eclair_de_depit'));
  const h = arena(['eclair_de_depit', 'foudre_du_dedain']);
  const boss = createEnemy(h, 'gardien', h.player.x + 80, h.player.y, { boss: true, spawnT: 0 });
  boss.hp = boss.maxHp * 0.05;
  stepGame(h, input({ moveX: -1, dashPressed: true }));
  assert.equal(boss.dead, false, 'un Gardien ne s\'achève pas');
  assertDeterministic(['jalousie', 'foudre_du_dedain']);
});

// ---------------------------------------------------------------- pouvoirs légendaires

test('pouvoir d\'Alastor : une esquive parfaite rend 1 charge de dash', () => {
  const g = arena();
  wear(g, 'eperons_alastor');
  const max = g.tuning.dash.charges;
  perfectDodge(g);
  assert.equal(g.player.dashCharges, max - 1 + powerProc('eperons_alastor').value);
  assert.ok(events(g, 'dashReady').length >= 1);
  const h = arena();
  perfectDodge(h);
  assert.equal(h.player.dashCharges, max - 1, 'sans le pouvoir : la charge reste dépensée');
  assertDeterministic([], { power: 'eperons_alastor' });
});

test('pouvoir de Bélial : le dernier coup du combo étourdit 0,6 s ; la garde tient (pas de ré-étourdissement en boucle)', () => {
  const g = arena();
  wear(g, 'marteau_belial');
  const stun = powerProc('marteau_belial').value;
  const e = dummy(g, 60, 0, 'brute', 1e6);
  let stunnedAt = -1;
  for (let i = 0; i < ticks(1.2) && stunnedAt < 0; i++) {
    stepGame(g, input({ attack: true }));
    if (e.stun > 0) stunnedAt = i;
  }
  assert.ok(stunnedAt >= 0, 'le dernier coup a étourdi');
  assert.ok(e.stun <= stun && e.stun > stun - 3 * DT, `étourdi ${e.stun} s`);
  const fin = g.tuning.combo[g.tuning.combo.length - 1].damage;
  assert.equal(events(g, 'hit').filter((h) => h.kind === 'melee').at(-1).amount, fin, 'c\'est le dernier coup du combo qui a étourdi');
  // Au réveil, l'ennemi est en garde : les derniers coups suivants blessent sans ré-étourdir.
  for (let i = 0; i < 300 && e.stun > 0; i++) stepGame(g, input());
  stepGame(g, input());
  assert.ok(e.guard > 0, 'réveillé en garde');
  let restunned = false;
  for (let i = 0; i < ticks(1.2); i++) {
    stepGame(g, input({ attack: true }));
    if (e.guard > 0 && e.stun > 0) restunned = true;
  }
  assert.equal(restunned, false);
  assertDeterministic([], { power: 'marteau_belial' });
});

test('pouvoir de Lilith : la frappe de dash lance un éclair en chaîne (16 dégâts, 3 rebonds)', () => {
  const g = arena();
  wear(g, 'dard_lilith');
  const pr = powerProc('dard_lilith');
  dummy(g, 200, 0, 'brute', 1e6);
  const others = [1, 2, 3, 4].map((k) => dummy(g, 200 + 100 * k, 200, 'imp', 1000));
  dashStrike(g);
  assert.equal(events(g, 'hit').filter((h) => h.kind === 'strike').length, 1);
  assert.equal(events(g, 'chain').length, pr.bounces);
  assert.equal(others.filter((e) => e.hp === 1000 - pr.value).length, pr.bounces);
  assertDeterministic([], { power: 'dard_lilith' });
});

test('pouvoir de la Main de gloire : salle nettoyée sans être touché = +1 charge de gadget ; touché, rien', () => {
  const g = createGame({ seed: 25, startFloor: 3 });
  wear(g, 'main_de_gloire');
  g.player.gadgetCharges = 1;
  clearRoom(g);
  assert.equal(g.player.gadgetCharges, 1 + powerProc('main_de_gloire').value);
  const h = createGame({ seed: 25, startFloor: 3 });
  wear(h, 'main_de_gloire');
  h.player.gadgetCharges = 1;
  damagePlayer(h, 3, { kind: 'test', id: 3 });
  clearRoom(h);
  assert.equal(h.player.gadgetCharges, 1);
  // Jamais au-delà du plein.
  const f = createGame({ seed: 25, startFloor: 3 });
  wear(f, 'main_de_gloire');
  const full = f.player.gadgetCharges;
  clearRoom(f);
  assert.equal(f.player.gadgetCharges, full);
  assertDeterministic([], { power: 'main_de_gloire' });
});

test('pouvoir de Moloch : un ennemi projeté contre un mur explose (20 dégâts, rayon 90)', () => {
  const g = arena();
  wear(g, 'fracas_moloch');
  const pr = powerProc('fracas_moloch');
  const e = dummy(g, 0, 0, 'imp', 500);
  assert.ok(slam(g, e));
  const neighbor = createEnemy(g, 'brute', e.x + 40, e.y + 60, { spawnT: 0 });
  neighbor.cooldown = 99;
  neighbor.hp = neighbor.maxHp = 1000;
  const blast = g.hazards.find((h) => h.kind === 'sinBlast');
  assert.ok(blast, 'explosion posée');
  assert.deepEqual([blast.r, blast.damage, blast.hitsPlayer], [pr.radius, pr.value, false]);
  steps(g, ticks(0.2));
  assert.equal(neighbor.hp, 1000 - pr.value);
  assertDeterministic([], { power: 'fracas_moloch' });
});

test('pouvoir d\'Abaddon : les ennemis tués explosent (12 dégâts, rayon 80)', () => {
  const g = arena();
  wear(g, 'linceul_abaddon');
  const pr = powerProc('linceul_abaddon');
  const victim = dummy(g, 200, 0, 'imp', 5);
  const neighbor = dummy(g, 250, 0, 'brute', 1000);
  const far = dummy(g, 200 + pr.radius + 120, 0, 'brute', 1000);
  hit100(g, victim);
  assert.equal(victim.dead, true);
  const blast = g.hazards.find((h) => h.kind === 'sinBlast');
  assert.deepEqual([blast.r, blast.damage, blast.hitsPlayer], [pr.radius, pr.value, false]);
  const hp = g.player.hp;
  steps(g, ticks(0.2));
  assert.equal(neighbor.hp, 1000 - pr.value);
  assert.equal(far.hp, 1000);
  assert.equal(g.player.hp, hp, 'jamais le héros');
  assertDeterministic([], { power: 'linceul_abaddon' });
});

// ---------------------------------------------------------------- événements d'autel

test('autels : tout libellé est chiffré par les données de son option (aucune accolade restante), dans une vraie partie', () => {
  for (const ev of EVENTS) {
    const g = createGame({ seed: 31, startFloor: 5 });
    give(g, 'furie');
    give(g, 'voracite');
    const ch = altar(g, ev.id);
    assert.equal(ch.title, ev.title);
    assert.equal(ch.options.length, ev.options.length);
    ch.options.forEach((o, i) => {
      assert.ok(!/[{}]/.test(o.label), `${ev.id} option ${i} : « ${o.label} »`);
      for (const [k, v] of Object.entries(ev.options[i])) if (typeof v === 'number' && ev.options[i].label.includes(`{${k}}`)) assert.ok(o.label.includes(String(v)), `${ev.id} : ${k} = ${v} absent de « ${o.label} »`);
    });
    assert.ok(ch.options.some((o) => !o.disabled), `${ev.id} : toujours une issue`);
  }
});

test('autels : les quatre nouveaux se rencontrent en descente (tirage de la salle d\'autel)', () => {
  const seen = new Set();
  for (let seed = 1; seed <= 80; seed++) {
    const g = createGame({ seed, startFloor: 5 });
    enterFloor(g, 6, { reward: 'event' });
    seen.add(g.room.interact.event);
  }
  for (const id of NEW_EVENTS) assert.ok(seen.has(id), `${id} : jamais tiré en 80 parties`);
});

test('autel Registre des âmes : le PERMANENT (Âmes) s\'échange contre le TEMPORAIRE, dans les deux sens, aux prix affichés', () => {
  const ev = EVENTS.find((e) => e.id === 'pacte_ames');
  const [buy, sell] = ev.options;
  // Pas assez d'Âmes : l'option est grisée et refusée.
  const poor = createGame({ seed: 33, startFloor: 5 });
  poor.meta.souls = buy.souls - 1;
  assert.equal(altar(poor, 'pacte_ames').options[0].disabled, true);
  assert.equal(applyCommand(poor, { type: 'choose', index: 0 }), false);
  assert.equal(poor.meta.souls, buy.souls - 1);
  // Céder des Âmes : une bénédiction ÉPIQUE, les Âmes du profil baissent du prix affiché.
  const g = createGame({ seed: 33, startFloor: 5 });
  g.meta.souls = 100;
  const ch = altar(g, 'pacte_ames');
  assert.ok(ch.options[0].label.includes(`${buy.souls} Âmes`));
  assert.equal(applyCommand(g, { type: 'choose', index: 0 }), true);
  assert.equal(g.meta.souls, 100 - buy.souls);
  assert.deepEqual(g.run.boons.map((b) => b.rarity), ['epique']);
  assert.equal(g.mode, 'play');
  // Vendre son sang : des PV de ce run contre des Âmes qui restent après la mort.
  const h = createGame({ seed: 33, startFloor: 5 });
  const hp0 = h.player.hp;
  const souls0 = h.meta.souls;
  altar(h, 'pacte_ames');
  assert.equal(applyCommand(h, { type: 'choose', index: 1 }), true);
  assert.equal(h.player.hp, hp0 - sell.hp);
  assert.equal(h.meta.souls, souls0 + sell.gain);
  h.player.hp = 0;
  h.player.state = 'dead';
  h.mode = 'dead';
  respawn(h, 1);
  assert.equal(h.meta.souls, souls0 + sell.gain, 'les Âmes survivent à la mort');
});

test('autel Forge des regrets : la bénédiction la moins avancée est fondue, la plus avancée gagne 2 niveaux — toutes deux nommées', () => {
  const g = createGame({ seed: 35, startFloor: 5 });
  give(g, 'furie');
  assert.equal(altar(g, 'forge').options[0].disabled, true, 'une seule bénédiction : rien à fondre');
  assert.equal(applyCommand(g, { type: 'choose', index: 0 }), false);
  const h = createGame({ seed: 35, startFloor: 5 });
  give(h, 'furie');
  give(h, 'lame_ardente');
  give(h, 'lame_ardente');
  give(h, 'envol'); // sans niveau : ni fondue ni approfondie
  const dmg0 = h.player.stats.damageMult;
  const t = forgeTargets(h);
  assert.deepEqual([t.lost.id, t.gained.id], ['furie', 'lame_ardente']);
  const ch = altar(h, 'forge');
  const levels = EVENTS.find((e) => e.id === 'forge').options[0].levels;
  assert.ok(ch.options[0].label.includes('« Furie »') && ch.options[0].label.includes('« Lame ardente »') && ch.options[0].label.includes(String(levels)), ch.options[0].label);
  assert.equal(applyCommand(h, { type: 'choose', index: 0 }), true);
  assert.deepEqual(h.run.boons.map((b) => `${b.id}:${b.level}`), [`lame_ardente:${2 + levels}`, 'envol:1']);
  assert.ok(h.player.stats.damageMult < dmg0, 'Furie est vraiment perdue');
  const burn = h.player.procs.find((pr) => pr.boon === 'lame_ardente').value;
  assert.ok(Math.abs(burn - V('lame_ardente') * (1 + 0.5 * (1 + levels))) < EPS, 'Lame ardente vraiment approfondie');
});

test('autel Miroir d\'orgueil : −PV max et +dégâts aux nombres affichés, jusqu\'à la mort ; une seule fois', () => {
  const opt = EVENTS.find((e) => e.id === 'miroir').options[0];
  const pact = PACTS.find((p) => p.id === opt.pact);
  assert.equal(opt.pct, pact.value, 'le libellé et le pacte disent les mêmes dégâts');
  assert.equal(-opt.hp, pact.stats.maxHpBonus, 'le libellé et le pacte disent les mêmes PV');
  const g = createGame({ seed: 37, startFloor: 5 });
  const max0 = g.player.maxHp;
  const dmg0 = g.player.stats.damageMult;
  const ch = altar(g, 'miroir');
  assert.ok(ch.options[0].label.includes(`−${opt.hp} PV max`) && ch.options[0].label.includes(`+${opt.pct} %`), ch.options[0].label);
  assert.equal(applyCommand(g, { type: 'choose', index: 0 }), true);
  assert.equal(g.player.maxHp, max0 - opt.hp);
  assert.ok(g.player.hp <= g.player.maxHp);
  assert.ok(Math.abs(g.player.stats.damageMult - dmg0 - opt.pct / 100) < EPS);
  assert.deepEqual(g.run.boons.map((b) => b.id), [opt.pact]);
  // Déjà brisé : l'option est grisée (un pacte ne se cumule pas).
  assert.equal(altar(g, 'miroir').options[0].disabled, true);
  assert.equal(applyCommand(g, { type: 'choose', index: 1 }), true);
  // TEMPORAIRE : la mort le reprend, PV max et dégâts reviennent.
  g.player.hp = 0;
  g.player.state = 'dead';
  g.mode = 'dead';
  respawn(g, 1);
  assert.deepEqual(g.run.boons, []);
  assert.equal(g.player.maxHp, max0);
  assert.ok(Math.abs(g.player.stats.damageMult - dmg0) < EPS);
});

test('autel Clepsydre de Charon : la jauge de Super contre des PV, ou des PV contre la jauge, aux nombres affichés', () => {
  const [drink, smash] = EVENTS.find((e) => e.id === 'clepsydre').options;
  const g = createGame({ seed: 39, startFloor: 5 });
  g.player.superCharge = drink.need / 100 - 0.01;
  assert.equal(altar(g, 'clepsydre').options[0].disabled, true, 'jauge trop basse : grisé');
  assert.equal(applyCommand(g, { type: 'choose', index: 0 }), false);
  applyCommand(g, { type: 'choose', index: 2 });
  g.player.superCharge = drink.need / 100;
  g.player.hp = 10;
  altar(g, 'clepsydre');
  assert.equal(applyCommand(g, { type: 'choose', index: 0 }), true);
  assert.equal(g.player.superCharge, 0);
  assert.ok(Math.abs(g.player.hp - (10 + g.player.maxHp * drink.pct / 100)) < EPS);
  // Briser : des PV contre une jauge pleine.
  const h = createGame({ seed: 39, startFloor: 5 });
  h.player.superCharge = 0.2;
  const hp0 = h.player.hp;
  altar(h, 'clepsydre');
  assert.equal(applyCommand(h, { type: 'choose', index: 1 }), true);
  assert.equal(h.player.hp, hp0 - smash.hp);
  assert.equal(h.player.superCharge, 1);
  // Jauge déjà pleine : briser ne donnerait rien, l'option est grisée ; jamais mortel.
  assert.equal(altar(h, 'clepsydre').options[1].disabled, true);
  applyCommand(h, { type: 'choose', index: 2 });
  const low = createGame({ seed: 39, startFloor: 5 });
  low.player.hp = 3;
  altar(low, 'clepsydre');
  applyCommand(low, { type: 'choose', index: 1 });
  assert.equal(low.player.hp, 1);
});

test('autels : même graine et mêmes choix = même partie (déterminisme des quatre nouveaux)', () => {
  const play = () => {
    const out = [];
    for (const id of NEW_EVENTS) {
      for (const index of [0, 1]) {
        const g = createGame({ seed: 41, startFloor: 5 });
        g.meta.souls = 90;
        g.player.superCharge = 0.7;
        give(g, 'furie');
        give(g, 'torpeur');
        altar(g, id);
        applyCommand(g, { type: 'choose', index });
        out.push([id, index, stateHash(g), g.rng.gen.s, g.meta.souls, g.player.hp, g.player.maxHp, g.player.superCharge, g.run.boons.map((b) => `${b.id}:${b.level}:${b.rarity}`).join(',')].join('|'));
      }
    }
    return out;
  };
  assert.deepEqual(play(), play());
});

// ---------------------------------------------------------------- dispositions de salle

const T = createTuning();

/** Première partie (graine, étage) dont la salle de départ tire la disposition `id`. */
function findRoom(id) {
  const circles = T.circles.map((c, i) => (c.layouts[id] > 0 ? i : -1)).filter((i) => i >= 0);
  for (const ci of circles) {
    const floor = Math.min(T.floors.total - 20, ci * T.floors.circleLength + 3);
    for (let seed = 1; seed <= 120; seed++) {
      const g = createGame({ seed, startFloor: floor });
      if (g.room.layout === id) return g;
    }
  }
  return null;
}

for (const id of NEW_LAYOUTS) {
  test(`disposition ${id} : pondérée dans les thèmes (jamais dans les Limbes), tirée en descente, entrée / portes / récompense dégagées`, () => {
    assert.ok(!COMBAT_LAYOUTS.includes(id));
    assert.equal(T.circles[0].layouts[id], undefined, 'les Limbes gardent les six dispositions d\'origine');
    const themed = T.circles.filter((c) => c.layouts[id] > 0);
    assert.ok(themed.length >= 2, `${id} : au moins deux Cercles`);
    const g = findRoom(id);
    assert.ok(g, `${id} : jamais tirée`);
    const room = g.room;
    assert.equal(room.obstacles.length, LAYOUTS[id].length);
    for (const o of room.obstacles) {
      assert.ok(o.x0 >= room.pad && o.x1 <= room.w - room.pad && o.y0 >= room.pad && o.y1 <= room.h - room.pad, `${id} : obstacle dans les murs`);
      assert.ok(o.y0 > room.pad + 40 + 2 * g.player.r + 60, `${id} : le haut (portes) reste libre`);
    }
    const start = playerStart(room);
    assert.ok(!pointBlocked(room, start.x, start.y, 60), `${id} : entrée dégagée (60 u)`);
    // La récompense tombe à sa place naturelle (centre), sans avoir à être déplacée par un obstacle.
    assert.deepEqual(rewardSpot(room), { x: room.w / 2, y: room.h * 0.45 }, `${id} : centre libre pour la récompense`);
    for (const fx of [0.32, 0.68]) assert.ok(!pointBlocked(room, room.w * fx, room.pad + 40, g.player.r + 20), `${id} : porte dégagée`);
    assert.ok(floorInfo(T, g.run.floor).circle >= 2);
    // Une vraie partie s'y joue (bot), sans blocage ni perte de déterminisme.
    const run = () => {
      const h = createGame({ seed: g.seed, startFloor: g.run.floor, godMode: true });
      const mem = {};
      let kills = 0;
      // 45 s : à un étage profond avec l'équipement de départ, le premier ennemi peut mettre plus de 20 s à tomber.
      for (let i = 0; i < ticks(45) && h.run.floor === g.run.floor; i++) {
        if (h.mode === 'choice') resolveChoice(h, 'skilled');
        else stepGame(h, POLICIES.skilled(h, mem));
        h.events.length = 0;
        kills = h.telemetry.kills;
      }
      return [stateHash(h), kills, h.room.layout, h.run.floor];
    };
    const a = run();
    assert.deepEqual(a, run(), `${id} : déterminisme`);
    assert.ok(a[1] > 0, `${id} : le bot y combat (${a[1]} ennemis tués)`);
  });
}

// ---------------------------------------------------------------- le tout, en partie réelle

test('partie réelle : un build fait des 14 bénédictions nouvelles et des 4 duos se joue 40 s — les effets se déclenchent, la partie reste déterministe', () => {
  const ids = [...Object.values(NEW_BOONS).flat(), ...NEW_DUOS, 'jalousie', 'festin'];
  const play = () => {
    const g = createGame({ seed: 91, startFloor: 7 });
    for (const id of ids) addBoon(g.run, { id, rarity: 'commun' });
    wear(g, 'linceul_abaddon');
    const mem = {};
    const seen = {};
    const marks = [];
    for (let i = 0; i < ticks(40); i++) {
      if (g.mode === 'choice') resolveChoice(g, 'skilled');
      else if (g.mode === 'play') stepGame(g, POLICIES.skilled(g, mem));
      else break;
      for (const ev of g.events) seen[ev.type === 'hazard' ? `hazard:${ev.kind}` : ev.type] = (seen[ev.type === 'hazard' ? `hazard:${ev.kind}` : ev.type] ?? 0) + 1;
      g.events.length = 0;
      if (i % 60 === 0) marks.push(`${stateHash(g)}:${g.rng.combat.s}`);
    }
    return { marks, seen, tel: g.telemetry };
  };
  const a = play();
  const b = play();
  assert.deepEqual(a.marks, b.marks);
  assert.ok(a.tel.kills > 5, `le bot se bat (${a.tel.kills} ennemis tués)`);
  assert.ok((a.seen.chain ?? 0) > 0, 'des éclairs sont partis (dash, mort d\'un ennemi)');
  assert.ok((a.seen['hazard:sinBlast'] ?? 0) > 0, 'des explosions sont parties (dernier coup du combo, ennemis tués)');
  assert.ok((a.seen.gold ?? 0) > 0, 'une prime est tombée (salle nettoyée sans être touché)');
  assert.ok((a.seen.super ?? 0) > 0 && (a.seen.dashNova ?? 0) > 0, 'le Super lancé a embrasé les alentours');
});

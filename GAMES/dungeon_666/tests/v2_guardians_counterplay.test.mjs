// Lot « Gardiens » de la V2, passe de correction — fichier CRÉÉ dans cette passe (aucun test
// existant modifié ; tests/v2_guardians.test.mjs reste tel quel).
// Contrat du CONTRE-JEU des Gardiens ajoutés, tel que le joueur le LIT à l'écran :
//   - une zone 'line' touche exactement le RECTANGLE dessiné (render.mjs lineEdge), corps du
//     héros compris : la brèche de la sentence de Minos est une vraie brèche, le dos du souffle
//     de Cerbère et du poing d'Éphialte est sûr, le bord rouge touche ;
//   - une morsure de Cerbère ne mord que dans son cône dessiné ;
//   - une transition de phase éteint aussi les braises d'Éphialte ;
//   - les geôliers d'Éphialte : un appel par phase (le bouclier ne se recycle pas) ;
//   - le point faible (exposition) est un statut propre, qui finit avec la fenêtre de punition
//     et ne se mélange pas à la vulnérabilité d'une bénédiction ;
//   - le tremblement des zones est pondéré par la distance au héros et plafonné par lot.
// Lancement : node --test tests/*.test.mjs

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createGame, stepGame, emptyInput, DT } from '../src/sim/game.mjs';
import { damageEnemy, spawnHazard } from '../src/sim/combat.mjs';
import { updateHazards } from '../src/sim/projectiles.mjs';
import { setState } from '../src/sim/boss_common.mjs';
import { pointSegDist2, inSector } from '../src/core/math.mjs';
import { createCamera } from '../src/render/camera.mjs';
import { createFx, handleFxEvents } from '../src/render/fx.mjs';

const ticks = (seconds) => Math.ceil(seconds / DT);
const input = () => emptyInput();
const UNIT_FLOOR = 18;

/** Partie d'entraînement contre le modèle `kind` (rotation forcée), Gardien apparu. */
function bossGame(kind, { seed = 3, floor = UNIT_FLOOR } = {}) {
  const g = createGame({ seed, startFloor: floor, practice: true, tuning: { guardians: { rotation: [kind] } } });
  for (let i = 0; i < 240 && !g.enemies.some((e) => e.boss && !(e.spawnT > 0)); i++) stepGame(g, input());
  const boss = g.enemies.find((e) => e.boss);
  assert.ok(boss && boss.kind === kind, `${kind} : Gardien présent`);
  return { g, boss };
}

/** Gardien seul, phase et pattern imposés ; héros à distance (invulnérable si demandé). */
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
  p.iframes = invulnerable ? 1e9 : 0;
  g.events.length = 0;
}

/** Joue tant que `keep()` est vrai en clouant le héros en (x, y) ; rend les coups reçus de `source`. */
function holdAndCount(g, x, y, seconds, keep, source) {
  const p = g.player;
  let hurt = 0;
  for (let i = 0; i < ticks(seconds) && keep(); i++) {
    p.x = x;
    p.y = y;
    p.vx = 0;
    p.vy = 0;
    stepGame(g, input());
    hurt += g.events.filter((ev) => ev.type === 'playerHurt' && ev.source === source).length;
    g.events.length = 0;
  }
  return hurt;
}

// ---------------------------------------------------------------- géométrie des zones 'line'

/**
 * Référence INDÉPENDANTE du code de simulation : les quatre coins tracés par le rendu
 * (render.mjs lineEdge), puis « le disque mord-il ce polygone ? » (centre dedans, ou plus près
 * d'un bord que son rayon).
 */
function drawnCorners(h) {
  const c = Math.cos(h.angle);
  const s = Math.sin(h.angle);
  const hw = h.width / 2;
  return [
    [h.x - s * hw, h.y + c * hw],
    [h.x + c * h.length - s * hw, h.y + s * h.length + c * hw],
    [h.x + c * h.length + s * hw, h.y + s * h.length - c * hw],
    [h.x + s * hw, h.y - c * hw],
  ];
}

function discTouchesDrawn(h, x, y, r) {
  const q = drawnCorners(h);
  let sign = 0;
  let inside = true;
  let best = Infinity;
  for (let i = 0; i < 4; i++) {
    const [ax, ay] = q[i];
    const [bx, by] = q[(i + 1) % 4];
    const cross = (bx - ax) * (y - ay) - (by - ay) * (x - ax);
    const sg = Math.sign(cross);
    if (sg !== 0) {
      if (sign === 0) sign = sg;
      else if (sg !== sign) inside = false;
    }
    best = Math.min(best, Math.sqrt(pointSegDist2(x, y, ax, ay, bx, by)));
  }
  return { touches: inside || best < r, margin: inside ? -best : best - r };
}

test('zones \'line\' : la touche suit exactement le rectangle dessiné, corps du héros compris (propriété)', () => {
  const g = createGame({ seed: 21, startFloor: 2 });
  g.enemies.length = 0;
  g.spawns.length = 0;
  const p = g.player;
  // Générateur déterministe propre au test (le RNG de la partie n'est pas touché).
  let s = 12345;
  const rnd = () => ((s = (Math.imul(s, 1103515245) + 12345) >>> 0) / 4294967296);
  let hits = 0;
  let misses = 0;
  let checked = 0;
  for (let k = 0; k < 600; k++) {
    const h = { shape: 'line', x: 300 + rnd() * 600, y: 250 + rnd() * 400, angle: rnd() * Math.PI * 2, length: 80 + rnd() * 400, width: 40 + rnd() * 160 };
    // Point tiré autour de la bande (souvent près de ses bords et de ses bouts).
    const u = -h.width + rnd() * (h.length + 2 * h.width);
    const v = (rnd() - 0.5) * (h.width + 4 * p.r);
    const x = h.x + Math.cos(h.angle) * u - Math.sin(h.angle) * v;
    const y = h.y + Math.sin(h.angle) * u + Math.cos(h.angle) * v;
    const ref = discTouchesDrawn(h, x, y, p.r);
    if (Math.abs(ref.margin) < 0.5) continue; // pile sur le bord : arrondi flottant, sans objet
    checked++;
    g.hazards.length = 0;
    spawnHazard(g, { ...h, delay: 0, damage: 1, kind: 'probeLine' });
    p.x = x;
    p.y = y;
    p.iframes = 0;
    p.hp = p.maxHp;
    p.state = 'idle';
    g.events.length = 0;
    updateHazards(g, DT);
    const hurt = g.events.some((ev) => ev.type === 'playerHurt' && ev.source === 'probeLine');
    assert.equal(hurt, ref.touches, `bande ${JSON.stringify(h)} ; héros (${x.toFixed(1)}, ${y.toFixed(1)}) : marge ${ref.margin.toFixed(2)} u`);
    if (hurt) hits++;
    else misses++;
  }
  assert.ok(checked > 500 && hits > 100 && misses > 100, `échantillon : ${checked} cas, ${hits} touchés, ${misses} épargnés`);
});

test('minos : la brèche DESSINÉE de la sentence protège sur toute sa largeur ; le bord rouge touche', () => {
  const run = (offsetFromEdge) => {
    const { g, boss } = bossGame('minos');
    isolate(g, boss, { phase: 1, pattern: 'sentence', invulnerable: false });
    stepGame(g, input());
    g.events.length = 0;
    const s = g.tuning.boss.minos.sentence;
    const bands = g.hazards.filter((h) => h.kind === 'minosSentence');
    assert.ok(bands.length > 0, 'la sentence est posée');
    const horiz = Math.abs(Math.sin(bands[0].angle)) < 1e-9;
    const axis = (h) => (horiz ? h.y : h.x);
    const along = (h) => (horiz ? h.x : h.y);
    // Bande du milieu : ses deux segments encadrent la brèche (phase 1 : brèches alignées).
    const axes = [...new Set(bands.map(axis))].sort((a, b) => a - b);
    const mid = axes[Math.floor(axes.length / 2)];
    const segs = bands.filter((h) => axis(h) === mid).sort((a, b) => along(a) - along(b));
    assert.equal(segs.length, 2, 'une bande = deux segments autour de sa brèche');
    const gap0 = along(segs[0]) + segs[0].length;
    assert.ok(Math.abs(along(segs[1]) - gap0 - s.breach) < 1e-6, 'brèche dessinée de la largeur du tuning');
    // offsetFromEdge : distance entre le corps du héros et le bord rouge (négatif = il mord dessus).
    const r = g.player.r;
    const c = gap0 + r + offsetFromEdge;
    const [x, y] = horiz ? [c, mid] : [mid, c];
    return holdAndCount(g, x, y, 4, () => boss.state === 'sentence', 'minosSentence');
  };
  for (const off of [1, 10, 40, 80, 150]) assert.equal(run(off), 0, `corps à ${off} u du bord rouge, dans la brèche : épargné`);
  assert.ok(run(-4) >= 1, 'corps qui mord de 4 u sur le bord rouge : touché');
});

for (const [kind, pattern, source] of [['cerbere', 'souffle', 'cerbereFlame'], ['colosse', 'poing', 'colosseFist']]) {
  test(`${kind} : ${pattern} — collé au DOS du Gardien, épargné ; dans la bande, touché`, () => {
    const run = (behind, gap) => {
      const { g, boss } = bossGame(kind);
      isolate(g, boss, { phase: 1, pattern: 'rest', invulnerable: false });
      const p = g.player;
      p.x = boss.x + 220;
      p.y = boss.y;
      boss.restFor = 99;
      stepGame(g, input());
      setState(boss, pattern);
      boss.pattern = pattern;
      stepGame(g, input());
      g.events.length = 0;
      const lines = g.hazards.filter((h) => h.kind === source);
      assert.ok(lines.length > 0, `${kind} : ${pattern} posé`);
      const aim = lines[Math.floor(lines.length / 2)].angle;
      const a = behind ? aim + Math.PI : aim;
      const d = behind ? boss.r + p.r + gap : boss.r + p.r + 120;
      return holdAndCount(g, boss.x + Math.cos(a) * d, boss.y + Math.sin(a) * d, 3, () => boss.state === pattern, source);
    };
    for (const gap of [1, 10, 25]) assert.equal(run(true, gap), 0, `dos, à ${gap} u de son corps : épargné`);
    assert.ok(run(false) >= 1, 'devant, dans la bande : touché');
  });
}

// ---------------------------------------------------------------- morsures de Cerbère

test('cerbere : une morsure ne mord JAMAIS hors de son cône dessiné (corps compris), et mord dedans', () => {
  let outside = 0;
  let insideBitten = 0;
  let insideCount = 0;
  for (const dist of [55, 65, 75, 90, 110, 140]) {
    for (const offDeg of [0, 15, 40, 50, 60, 75, 90, 120]) {
      const { g, boss } = bossGame('cerbere');
      const m = g.tuning.boss.cerbere.morsures;
      isolate(g, boss, { phase: 1, pattern: 'morsures', invulnerable: false });
      const p = g.player;
      p.x = boss.x + 120;
      p.y = boss.y;
      let placed = null;
      let bitten = 0;
      for (let i = 0; i < ticks(2.5) && boss.patternStep < 1; i++) {
        if (!placed && boss.sub === 'windup' && boss.subT >= m.windup * m.lockAt + DT) {
          // Visée verrouillée : le héros se fige à (dist, offDeg) de l'axe du cône affiché.
          const t = boss.tele;
          const a = t.angle + (offDeg * Math.PI) / 180;
          placed = { x: boss.x + Math.cos(a) * dist, y: boss.y + Math.sin(a) * dist, inCone: inSector(boss.x + Math.cos(a) * dist, boss.y + Math.sin(a) * dist, boss.x, boss.y, t.range, t.angle, t.arc, p.r) };
        }
        if (placed) {
          p.x = placed.x;
          p.y = placed.y;
          p.vx = 0;
          p.vy = 0;
        }
        stepGame(g, input());
        bitten += g.events.filter((ev) => ev.type === 'playerHurt' && ev.source === 'cerbereBite').length;
        g.events.length = 0;
      }
      assert.ok(placed, 'la morsure a été armée');
      if (!placed.inCone) {
        assert.equal(bitten, 0, `hors du cône (dist ${dist}, ${offDeg}°) : mordu`);
        outside++;
      } else if (offDeg <= 15 && dist <= 110) {
        insideCount++;
        if (bitten > 0) insideBitten++;
      }
    }
  }
  assert.ok(outside >= 15, `cas hors du cône : ${outside}`);
  assert.equal(insideBitten, insideCount, `dans l'axe du cône et à portée : mordu ${insideBitten}/${insideCount}`);
});

// ---------------------------------------------------------------- Éphialte : braises et geôliers

test('colosse : la transition de phase éteint les braises — aucune ne pulse ni ne frappe pendant le rugissement', () => {
  const { g, boss } = bossGame('colosse');
  const d = g.tuning.boss.colosse;
  isolate(g, boss, { phase: 2, pattern: 'eboulis' });
  for (let i = 0; i < ticks(d.eboulis.delayMax + 0.2); i++) {
    stepGame(g, input());
    g.events.length = 0;
  }
  const lit = (boss.pools ?? []).filter((pool) => !pool.rock);
  assert.ok(lit.length > 0, 'des braises brûlent avant la transition');
  // Le héros se tient sur une braise allumée, vulnérable : ce qui y frapperait le toucherait.
  const spot = lit[0];
  const p = g.player;
  boss.hp = Math.floor(boss.maxHp * d.phase3At) - 1;
  stepGame(g, input());
  assert.equal(boss.phase, 3);
  assert.equal(boss.state, 'roar');
  assert.equal((boss.pools ?? []).length, 0, 'braises éteintes');
  g.events.length = 0;
  let embers = 0;
  for (let i = 0; i < ticks(d.transition + 0.1) && boss.state === 'roar'; i++) {
    p.x = spot.x;
    p.y = spot.y;
    p.iframes = 0;
    stepGame(g, input());
    embers += g.hazards.filter((h) => h.kind === 'colosseEmber' && !h.done).length;
    for (const ev of g.events) {
      assert.ok(!(ev.type === 'hazardFire' && ev.kind === 'colosseEmber'), 'braise qui frappe pendant la transition');
      assert.ok(!(ev.type === 'playerHurt' && ev.source === 'colosseEmber'), 'brûlé par une braise pendant la transition');
    }
    g.events.length = 0;
  }
  assert.equal(embers, 0, 'aucune braise télégraphiée pendant le rugissement');
});

test('colosse : geôliers, un appel par phase (le bouclier ne se recycle pas dès la chute des archers)', () => {
  const { g, boss } = bossGame('colosse');
  const d = g.tuning.boss.colosse;
  assert.equal(d.geoliers.callsPerPhase, 1);
  const callsDuring = (seconds) => {
    let calls = 0;
    for (let i = 0; i < ticks(seconds); i++) {
      stepGame(g, input());
      calls += g.events.filter((ev) => ev.type === 'bossSummon' && ev.id === boss.id).length;
      g.events.length = 0;
      // Les geôliers tombent dès qu'ils apparaissent : rien n'empêcherait un nouvel appel.
      for (const e of g.enemies) if (e.summoned && !e.dead && !(e.spawnT > 0)) damageEnemy(g, e, { kind: 'melee', amount: 1e9, dirX: 1, dirY: 0 });
      boss.hp = boss.maxHp; // reste dans sa phase
    }
    return calls;
  };
  isolate(g, boss, { phase: 2, pattern: 'rest' });
  assert.equal(callsDuring(60), 1, 'phase 2 : un seul appel en 60 s');
  // Phase 3 : un nouvel appel est permis, une fois.
  boss.hp = Math.floor(boss.maxHp * d.phase3At) - 1;
  boss.phase = 2;
  stepGame(g, input());
  assert.equal(boss.phase, 3);
  g.events.length = 0;
  g.spawns.length = 0;
  g.enemies = [boss];
  assert.equal(callsDuring(60), 1, 'phase 3 : un seul appel en 60 s');
});

// ---------------------------------------------------------------- point faible et vulnérabilité

test('point faible : statut propre, fini avec la fenêtre de punition, cumulé sans mélange avec le Charme fatal', () => {
  const { g, boss } = bossGame('colosse');
  const d = g.tuning.boss.colosse;
  const CHARM = 0.3;
  isolate(g, boss, { phase: 1, pattern: 'rest' });
  boss.restFor = 99;
  const base = damageEnemy(g, boss, { kind: 'wall', amount: 100 });
  // Charme seul : vulnérable, mais aucun point faible (rien de doré à frapper).
  boss.vuln = 4;
  boss.vulnMult = CHARM;
  assert.ok(!(boss.exposed > 0), 'Charme seul : pas de point faible exposé');
  assert.ok(Math.abs(damageEnemy(g, boss, { kind: 'wall', amount: 100 }) - base * (1 + CHARM)) <= 1);
  // Poing : le bras se coince ; on pose un Charme de 4 s au début de la récupération exposée.
  isolate(g, boss, { phase: 1, pattern: 'poing' });
  boss.vuln = 0;
  boss.vulnMult = 0;
  let charmed = false;
  for (let i = 0; i < ticks(8) && boss.state === 'poing'; i++) {
    stepGame(g, input());
    g.events.length = 0;
    if (boss.sub === 'recover' && !charmed) {
      charmed = true;
      assert.ok(boss.exposed > 0 && boss.vuln > 0, 'bras coincé : exposé (et statut « vulnérable » levé)');
      boss.vuln = Math.max(boss.vuln, 4);
      boss.vulnMult = Math.max(boss.vulnMult, CHARM);
      const both = damageEnemy(g, boss, { kind: 'wall', amount: 100 });
      assert.ok(Math.abs(both - base * (1 + CHARM) * (1 + d.poing.exposedMult)) <= 2, `exposé + Charme : ${both} contre ${base}`);
    }
  }
  assert.ok(charmed, 'la récupération exposée a eu lieu');
  assert.equal(boss.state, 'rest', 'fenêtre de punition terminée');
  assert.ok(!(boss.exposed > 0), 'le point faible s\'éteint avec la fenêtre');
  assert.ok(boss.vuln > 0, 'le Charme, lui, court encore sur sa propre durée');
  const after = damageEnemy(g, boss, { kind: 'wall', amount: 100 });
  assert.ok(Math.abs(after - base * (1 + CHARM)) <= 1, `après la fenêtre : seulement +${CHARM * 100} % (${after} contre ${base})`);
  // Exposition seule, puis transition de phase en pleine fenêtre : rien ne survit.
  isolate(g, boss, { phase: 1, pattern: 'poing' });
  boss.vuln = 0;
  boss.vulnMult = 0;
  for (let i = 0; i < ticks(8) && boss.sub !== 'recover'; i++) {
    stepGame(g, input());
    g.events.length = 0;
  }
  assert.ok(boss.exposed > 0);
  boss.hp = Math.floor(boss.maxHp * d.phase2At) - 1;
  stepGame(g, input());
  assert.equal(boss.state, 'roar');
  assert.ok(!(boss.exposed > 0) && !(boss.vuln > 0), 'transition : exposition et drapeau éteints');
});

// ---------------------------------------------------------------- tremblement des zones

test('tremblement : une zone loin du héros secoue moins ; un lot de zones = une secousse ; les braises ne secouent pas', () => {
  const game = { player: { x: 1000, y: 600 } };
  const fire = (events) => {
    const cam = createCamera();
    const fx = createFx();
    handleFxEvents(fx, cam, events, game);
    return cam.trauma;
  };
  const circle = (kind, x, y, r = 60) => ({ type: 'hazardFire', id: 1, kind, shape: 'circle', x, y, r, angle: 0, length: 0, width: 0 });
  const near = fire([circle('colosseRock', 1000, 600)]);
  const far = fire([circle('colosseRock', 100, 100)]);
  assert.ok(near > 0, 'une zone sur le héros secoue');
  assert.ok(far < near * 0.5, `loin : ${far} contre ${near} tout près`);
  // Balayage de Minos : 12 segments qui frappent dans le même lot d'événements.
  const sweep = [];
  for (let i = 0; i < 12; i++) sweep.push({ type: 'hazardFire', id: i, kind: 'minosSentence', shape: 'line', x: 40, y: 60 + i * 100, r: 0, angle: 0, length: 900, width: 100 });
  assert.ok(fire(sweep) <= near + 1e-9, `balayage de 12 bandes : ${fire(sweep)} (une zone : ${near})`);
  // Braises qui pulsent, même sous le héros : terrain, pas d'impact (un coup REÇU secoue, lui).
  assert.equal(fire([circle('colosseEmber', 1000, 600), circle('colosseEmber', 1100, 600)]), 0);
  assert.ok(fire([{ type: 'playerHurt', x: 1000, y: 600, amount: 10, source: 'colosseEmber', srcX: 1000, srcY: 600 }]) > 0, 'brûlé : ça secoue');
});

test('tremblement mesuré en combat : jamais saturé plus de 5 % du temps contre Minos et Éphialte (bot skilled)', async () => {
  const { updateCamera } = await import('../src/render/camera.mjs');
  const { updateFx } = await import('../src/render/fx.mjs');
  const { POLICIES } = await import('../tools/bots.mjs');
  const HIGH_TRAUMA = 0.8; // amplitude = trauma² : >= 64 % du maximum
  const MAX_SHARE = 0.05;
  for (const [kind, floor] of [['minos', 54], ['colosse', 72]]) {
    const g = createGame({ seed: 2, startFloor: floor, practice: true, tuning: { guardians: { rotation: [kind] } } });
    const cam = createCamera();
    const fx = createFx();
    const mem = {};
    let hi = 0;
    let total = 0;
    for (let i = 0; i < ticks(60) && g.mode === 'play' && !g.room.cleared; i++) {
      stepGame(g, POLICIES.skilled(g, mem));
      handleFxEvents(fx, cam, g.events, g);
      g.events.length = 0;
      updateFx(fx, DT, g);
      updateCamera(cam, g, DT);
      if (g.enemies.some((e) => e.boss && !e.dead)) {
        total++;
        if (cam.trauma >= HIGH_TRAUMA) hi++;
      }
    }
    assert.ok(total > ticks(20), `${kind} : combat observé ${(total * DT).toFixed(1)} s`);
    assert.ok(hi / total <= MAX_SHARE, `${kind} : trauma >= ${HIGH_TRAUMA} pendant ${((100 * hi) / total).toFixed(1)} % du combat`);
  }
});

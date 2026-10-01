// Effets visuels pilotés par les événements de simulation : particules (pool fixe, zéro
// allocation par image), textes flottants, effets transitoires (taillades, ondes, éclairs),
// tremblement et coups de zoom. Présentation pure : Math.random autorisé ici.

import { PAL } from './palette.mjs';
import { addTrauma, zoomKick, kick } from './camera.mjs';

const MAX_PARTICLES = 700;
const MAX_TEXTS = 48;
const MAX_EFFECTS = 80;
const TAU = Math.PI * 2;

// Particules en structure de tableaux (Float32Array) : pas de GC dans la boucle.
const P = {
  n: 0,
  x: new Float32Array(MAX_PARTICLES),
  y: new Float32Array(MAX_PARTICLES),
  vx: new Float32Array(MAX_PARTICLES),
  vy: new Float32Array(MAX_PARTICLES),
  life: new Float32Array(MAX_PARTICLES),
  max: new Float32Array(MAX_PARTICLES),
  size: new Float32Array(MAX_PARTICLES),
  drag: new Float32Array(MAX_PARTICLES),
  streak: new Uint8Array(MAX_PARTICLES),
  color: new Array(MAX_PARTICLES).fill('#fff'),
};

export function createFx() {
  return { texts: [], effects: [], quality: 1, shakeScale: 1, healAcc: 0, healT: 0, banner: null, hurtFlash: 0, flash: 0, ghosts: [], landT: 0, swingT: 0, swingAngle: 0 };
}

function spawnParticle(fx, x, y, vx, vy, life, size, color, drag = 4, streak = 0) {
  if (P.n >= MAX_PARTICLES * fx.quality) return;
  const i = P.n++;
  P.x[i] = x;
  P.y[i] = y;
  P.vx[i] = vx;
  P.vy[i] = vy;
  P.life[i] = life;
  P.max[i] = life;
  P.size[i] = size;
  P.drag[i] = drag;
  P.streak[i] = streak;
  P.color[i] = color;
}

function burst(fx, x, y, count, speed, life, size, color, opts = {}) {
  const spread = opts.spread ?? TAU;
  const dir = opts.dir ?? 0;
  for (let k = 0; k < count; k++) {
    const a = dir + (Math.random() - 0.5) * spread;
    const s = speed * (0.35 + Math.random() * 0.65);
    spawnParticle(fx, x, y, Math.cos(a) * s, Math.sin(a) * s, life * (0.6 + Math.random() * 0.4), size * (0.6 + Math.random() * 0.6), color, opts.drag ?? 5, opts.streak ?? 0);
  }
}

export function addText(fx, x, y, text, color, size = 15, life = 0.7) {
  if (fx.texts.length >= MAX_TEXTS) fx.texts.shift();
  fx.texts.push({ x: x + (Math.random() - 0.5) * 10, y, vy: -70, text, color, size, life, max: life });
}

function addEffect(fx, e) {
  if (fx.effects.length >= MAX_EFFECTS) fx.effects.shift();
  fx.effects.push(e);
}

export function setBanner(fx, title, sub, color = PAL.text, life = 2.2) {
  fx.banner = { title, sub, color, life, max: life };
}

const ENEMY_COLORS = { imp: PAL.imp, archer: PAL.archer, brute: PAL.brute, charger: PAL.charger, exploder: PAL.exploder, gardien: PAL.boss };

/** Traduit les événements de l'image en effets. `cam` reçoit le tremblement. */
export function handleFxEvents(fx, cam, events, game) {
  for (const ev of events) {
    const h = HANDLERS[ev.type];
    if (h) h(fx, cam, ev, game);
  }
}

const HANDLERS = {
  swing(fx, cam, ev) {
    addEffect(fx, { type: 'slash', angle: ev.angle, arc: ev.arc, range: ev.range, index: ev.index, strike: ev.strike, life: 0.15, max: 0.15 });
    kick(cam, Math.cos(ev.angle), Math.sin(ev.angle), 1.5);
    fx.swingT = 0.05;
    fx.swingAngle = ev.angle;
  },
  dashEnd(fx) {
    fx.landT = 0.067;
  },
  hit(fx, cam, ev) {
    const color = ENEMY_COLORS[ev.enemy] ?? PAL.imp;
    const dir = Math.atan2(ev.dirY, ev.dirX);
    const heavy = ev.amount >= 20 || ev.crit;
    if (ev.kind === 'burn') {
      burst(fx, ev.x, ev.y, 2, 60, 0.4, 2.5, PAL.lava, { drag: 2 });
      addText(fx, ev.x, ev.y - 14, String(ev.amount), '#ff9a5a', 11, 0.5);
      return;
    }
    burst(fx, ev.x, ev.y, heavy ? 12 : 7, heavy ? 520 : 380, 0.28, 2.2, PAL.slash, { dir, spread: 1.4, streak: 1, drag: 7 });
    burst(fx, ev.x, ev.y, heavy ? 9 : 5, 220, 0.45, 3.2, color, { dir, spread: 2.2, drag: 4 });
    addEffect(fx, { type: 'ring', x: ev.x, y: ev.y, r0: 6, r1: heavy ? 46 : 30, color: '#ffffff', width: heavy ? 4 : 2.5, life: 0.14, max: 0.14 });
    addText(fx, ev.x, ev.y - 18, ev.crit ? `${ev.amount}!` : String(ev.amount), ev.crit ? PAL.crit : PAL.text, ev.crit ? 21 : heavy ? 17 : 14, ev.crit ? 0.85 : 0.6);
    const shake = ev.shake || (ev.kind === 'skill' ? 0.14 : ev.kind === 'gadget' ? 0.05 : ev.kind === 'super' ? 0.04 : 0.08);
    addTrauma(cam, ev.crit ? shake + 0.08 : shake, true);
    if (ev.kind === 'melee' || ev.kind === 'strike') kick(cam, ev.dirX, ev.dirY, heavy ? 5 : 3);
    else if (ev.kind === 'skill') kick(cam, ev.dirX, ev.dirY, 4);
    if (heavy && (ev.kind === 'melee' || ev.kind === 'strike')) zoomKick(cam, 0.025);
  },
  kill(fx, cam, ev) {
    const color = ENEMY_COLORS[ev.enemy] ?? PAL.imp;
    const big = ev.boss ? 3 : ev.elite ? 1.8 : 1;
    burst(fx, ev.x, ev.y, Math.round(18 * big), 360 * big, 0.6, 3.5, color, { drag: 3.5 });
    burst(fx, ev.x, ev.y, Math.round(10 * big), 140, 1.1, 5, '#3a2a2e', { drag: 2 });
    burst(fx, ev.x, ev.y, Math.round(6 * big), 260, 0.5, 2, PAL.lava, { drag: 3, streak: 1 });
    addEffect(fx, { type: 'ring', x: ev.x, y: ev.y, r0: 10, r1: 70 * big, color, width: 5, life: 0.25, max: 0.25 });
    // Pose de mort : la silhouette blanchit puis se rétracte (pas de disparition sèche).
    addEffect(fx, { type: 'death', x: ev.x, y: ev.y, r: ev.r ?? 14, color, life: 0.22 * big, max: 0.22 * big });
    addTrauma(cam, ev.boss ? 1 : ev.elite ? 0.5 : 0.1, !ev.boss && !ev.elite);
    if (ev.boss) zoomKick(cam, 0.12);
    else if (ev.elite) zoomKick(cam, 0.04);
  },
  dash(fx, cam, ev) {
    burst(fx, ev.x, ev.y, 8, 160, 0.35, 4, '#5a4a52', { dir: Math.atan2(-ev.dirY, -ev.dirX), spread: 1.6, drag: 5 });
    addEffect(fx, { type: 'ring', x: ev.x, y: ev.y, r0: 8, r1: 34, color: PAL.heroCape, width: 2, life: 0.16, max: 0.16 });
  },
  dodge(fx, cam, ev) {
    addText(fx, ev.x, ev.y - 30, 'ESQUIVE', PAL.heroCape, 15, 0.7);
    burst(fx, ev.x, ev.y, 10, 200, 0.4, 2, PAL.heroCape, { streak: 1, drag: 6 });
  },
  playerHurt(fx, cam, ev) {
    addText(fx, ev.x, ev.y - 24, `-${ev.amount}`, PAL.heroHurt, 19, 0.8);
    burst(fx, ev.x, ev.y, 12, 260, 0.45, 3, PAL.heroHurt, { drag: 4 });
    fx.hurtFlash = 1;
    addTrauma(cam, 0.6);
    const dx = ev.x - ev.srcX;
    const dy = ev.y - ev.srcY;
    const l = Math.hypot(dx, dy) || 1;
    kick(cam, dx / l, dy / l, 7);
  },
  playerDeath(fx, cam, ev) {
    burst(fx, ev.x, ev.y, 40, 380, 1.2, 4, PAL.heroCape, { drag: 2 });
    addTrauma(cam, 1);
    zoomKick(cam, 0.12);
  },
  hazardFire(fx, cam, ev) {
    if (ev.shape === 'line') {
      addEffect(fx, { type: 'streak', x: ev.x, y: ev.y, angle: ev.angle, length: ev.length, width: ev.width, life: 0.25, max: 0.25, color: PAL.danger });
    } else {
      addEffect(fx, { type: 'shock', x: ev.x, y: ev.y, r: ev.r, life: 0.32, max: 0.32, color: ev.kind === 'sinBlast' ? '#ff8ae0' : '#ff6a3a' });
      if (ev.kind === 'bossSlam') zoomKick(cam, 0.02);
      burst(fx, ev.x, ev.y, 16, ev.r * 3, 0.5, 4, '#4a3036', { drag: 4 });
      burst(fx, ev.x, ev.y, 10, ev.r * 4, 0.35, 2.5, PAL.lava, { drag: 5, streak: 1 });
    }
    addTrauma(cam, ev.kind === 'sinBlast' ? 0.06 : 0.28);
  },
  explode(fx, cam, ev) {
    burst(fx, ev.x, ev.y, 26, 420, 0.6, 4, PAL.exploder, { drag: 3.5 });
  },
  deflect(fx, cam, ev) {
    burst(fx, ev.x, ev.y, 6, 260, 0.25, 2, '#ffffff', { streak: 1, drag: 8 });
    addEffect(fx, { type: 'ring', x: ev.x, y: ev.y, r0: 4, r1: 22, color: '#ffffff', width: 2, life: 0.12, max: 0.12 });
  },
  skill(fx, cam, ev, game) {
    const p = game.player;
    burst(fx, p.x + Math.cos(ev.angle) * 22, p.y + Math.sin(ev.angle) * 22, 10, 300, 0.25, 2.5, PAL.lance, { dir: ev.angle, spread: 0.9, streak: 1, drag: 6 });
    addTrauma(cam, 0.1);
  },
  gadget(fx, cam, ev) {
    addEffect(fx, { type: 'nova', x: ev.x, y: ev.y, r: ev.r, life: 0.35, max: 0.35, color: '#ffb36a' });
    burst(fx, ev.x, ev.y, 30, ev.r * 4, 0.5, 3.5, '#8a7a80', { drag: 5 });
    addTrauma(cam, 0.4);
    zoomKick(cam, 0.03);
  },
  super(fx, cam, ev) {
    addEffect(fx, { type: 'nova', x: ev.x, y: ev.y, r: ev.r * 1.3, life: 0.4, max: 0.4, color: PAL.superBar });
    setBanner(fx, 'COLÈRE', '', PAL.superBar, 0.9);
    addTrauma(cam, 0.5);
    fx.flash = 0.5;
  },
  superTick(fx, cam, ev) {
    addEffect(fx, { type: 'swirl', x: ev.x, y: ev.y, r: ev.r, life: 0.16, max: 0.16, a0: Math.random() * TAU });
    burst(fx, ev.x, ev.y, 4, ev.r * 3, 0.3, 2.5, PAL.superBar, { drag: 6, streak: 1 });
  },
  dashNova(fx, cam, ev) {
    addEffect(fx, { type: 'ring', x: ev.x, y: ev.y, r0: 10, r1: ev.r, color: '#ff8a4a', width: 4, life: 0.22, max: 0.22 });
  },
  chain(fx, cam, ev) {
    addEffect(fx, { type: 'bolt', x0: ev.x0, y0: ev.y0, x1: ev.x1, y1: ev.y1, life: 0.16, max: 0.16, seed: Math.random() * 1000 });
  },
  pickup(fx, cam, ev) {
    if (ev.kind === 'gold') addText(fx, ev.x, ev.y - 8, `+${ev.amount}`, PAL.gold, 12, 0.5);
    burst(fx, ev.x, ev.y, 4, 90, 0.3, 2, ev.kind === 'gold' ? PAL.gold : PAL.heal, { drag: 6 });
  },
  gold(fx, cam, ev) {
    addText(fx, ev.x, ev.y - 20, `+${ev.amount} or`, PAL.gold, 12, 0.6);
  },
  heal(fx, cam, ev) {
    fx.healAcc += ev.amount;
  },
  wallSlam(fx, cam, ev) {
    burst(fx, ev.x, ev.y, 14, 300, 0.4, 3.5, '#8a7a80', { drag: 5 });
    addText(fx, ev.x, ev.y - 30, 'IMPACT', '#ffb36a', 14, 0.6);
    addTrauma(cam, 0.25);
  },
  chargerWall(fx, cam, ev) {
    burst(fx, ev.x, ev.y, 20, 340, 0.5, 4, '#8a7a80', { drag: 4 });
    addText(fx, ev.x, ev.y - 34, 'SONNÉ', '#ffe14a', 15, 0.9);
    addTrauma(cam, ev.boss ? 0.6 : 0.35);
  },
  spawn(fx, cam, ev) {
    burst(fx, ev.x, ev.y, ev.boss ? 40 : 10, ev.boss ? 300 : 120, 0.6, 4, '#2a1420', { drag: 3 });
  },
  floorEnter(fx, cam, ev) {
    const where = ev.isBoss ? 'Gardien de la section' : `${ev.circleName} · section ${ev.section}`;
    setBanner(fx, `ÉTAGE ${ev.floor}`, where, ev.isBoss ? PAL.danger : PAL.text, 2.0);
  },
  roomClear(fx, cam, ev) {
    setBanner(fx, ev.boss ? 'GARDIEN VAINCU' : 'SALLE NETTOYÉE', ev.boss ? 'Un checkpoint s\'éveille' : '', ev.boss ? PAL.gold : PAL.text, 1.6);
  },
  bossPhase(fx, cam) {
    setBanner(fx, 'LE GARDIEN S\'ENRAGE', '', PAL.danger, 1.4);
    addTrauma(cam, 0.7);
    fx.flash = 0.6;
  },
  checkpoint(fx, cam, ev) {
    fx.checkpointFloor = ev.floor;
  },
  boonGain(fx) {
    fx.flash = 0.35;
  },
  immune(fx, cam, ev) {
    if (fx.texts.some((t) => t.text === 'INVULNÉRABLE' && t.life > 0.4)) return;
    addText(fx, ev.x, ev.y - 50, 'INVULNÉRABLE', '#c9c9d6', 13, 0.6);
  },
};

export function updateFx(fx, dt, game) {
  // Particules.
  let w = 0;
  for (let i = 0; i < P.n; i++) {
    const life = P.life[i] - dt;
    if (life <= 0) continue;
    const k = Math.exp(-P.drag[i] * dt);
    P.vx[i] *= k;
    P.vy[i] *= k;
    P.x[w] = P.x[i] + P.vx[i] * dt;
    P.y[w] = P.y[i] + P.vy[i] * dt;
    P.vx[w] = P.vx[i];
    P.vy[w] = P.vy[i];
    P.life[w] = life;
    P.max[w] = P.max[i];
    P.size[w] = P.size[i];
    P.drag[w] = P.drag[i];
    P.streak[w] = P.streak[i];
    P.color[w] = P.color[i];
    w++;
  }
  P.n = w;
  for (const t of fx.texts) {
    t.life -= dt;
    t.y += t.vy * dt;
    t.vy *= Math.exp(-3 * dt);
  }
  fx.texts = fx.texts.filter((t) => t.life > 0);
  for (const e of fx.effects) e.life -= dt;
  fx.effects = fx.effects.filter((e) => e.life > 0);
  if (fx.banner) {
    fx.banner.life -= dt;
    if (fx.banner.life <= 0) fx.banner = null;
  }
  fx.hurtFlash = Math.max(0, fx.hurtFlash - dt * 2.5);
  fx.landT = Math.max(0, fx.landT - dt);
  fx.swingT = Math.max(0, fx.swingT - dt);
  fx.flash = Math.max(0, fx.flash - dt * 2);
  // Soins regroupés : un seul chiffre vert au lieu d'une pluie de « +1 ».
  fx.healT -= dt;
  if (fx.healAcc >= 1 && fx.healT <= 0) {
    const p = game.player;
    addText(fx, p.x, p.y - 30, `+${Math.round(fx.healAcc)}`, PAL.heal, 14, 0.7);
    fx.healAcc = 0;
    fx.healT = 0.4;
  }
  // Fantômes du dash (traînée).
  const p = game.player;
  if (p.state === 'dash') fx.ghosts.push({ x: p.x, y: p.y, facing: p.facing, life: 0.18, max: 0.18 });
  for (const g of fx.ghosts) g.life -= dt;
  fx.ghosts = fx.ghosts.filter((g) => g.life > 0);
  // Braises ambiantes.
  if (Math.random() < 0.35 * fx.quality && game.room) {
    const room = game.room;
    spawnParticle(fx, Math.random() * room.w, room.h + 10, (Math.random() - 0.5) * 20, -30 - Math.random() * 50, 4 + Math.random() * 3, 1.5 + Math.random() * 1.5, Math.random() < 0.5 ? PAL.lava : '#ffb36a', 0.05);
  }
}

export function clearFx(fx) {
  P.n = 0;
  fx.texts.length = 0;
  fx.effects.length = 0;
  fx.ghosts.length = 0;
}

export function drawParticles(ctx) {
  for (let i = 0; i < P.n; i++) {
    const a = P.life[i] / P.max[i];
    ctx.globalAlpha = a;
    ctx.fillStyle = P.color[i];
    ctx.strokeStyle = P.color[i];
    const s = P.size[i];
    if (P.streak[i]) {
      ctx.lineWidth = s;
      ctx.beginPath();
      ctx.moveTo(P.x[i], P.y[i]);
      ctx.lineTo(P.x[i] - P.vx[i] * 0.03, P.y[i] - P.vy[i] * 0.03);
      ctx.stroke();
    } else {
      ctx.fillRect(P.x[i] - s / 2, P.y[i] - s / 2, s, s);
    }
  }
  ctx.globalAlpha = 1;
}

export function drawEffects(ctx, fx, game) {
  const p = game.player;
  for (const e of fx.effects) {
    const t = 1 - e.life / e.max; // 0 -> 1
    const a = e.life / e.max;
    switch (e.type) {
      case 'slash':
        drawSlash(ctx, p.x, p.y, e, t, a);
        break;
      case 'ring':
        ctx.globalAlpha = a;
        ctx.strokeStyle = e.color;
        ctx.lineWidth = e.width * a + 0.5;
        ctx.beginPath();
        ctx.arc(e.x, e.y, e.r0 + (e.r1 - e.r0) * t, 0, TAU);
        ctx.stroke();
        break;
      case 'shock':
        ctx.globalAlpha = a * 0.9;
        ctx.fillStyle = e.color;
        ctx.beginPath();
        ctx.arc(e.x, e.y, e.r * (0.6 + 0.4 * t), 0, TAU);
        ctx.globalAlpha = a * 0.35;
        ctx.fill();
        ctx.globalAlpha = a;
        ctx.strokeStyle = '#ffd0a0';
        ctx.lineWidth = 4 * a + 1;
        ctx.stroke();
        break;
      case 'nova':
        ctx.globalAlpha = a * 0.5;
        ctx.fillStyle = e.color;
        ctx.beginPath();
        ctx.arc(e.x, e.y, e.r * t, 0, TAU);
        ctx.fill();
        ctx.globalAlpha = a;
        ctx.strokeStyle = '#fff1d6';
        ctx.lineWidth = 5 * a + 1;
        ctx.stroke();
        break;
      case 'swirl':
        ctx.globalAlpha = a * 0.8;
        ctx.strokeStyle = PAL.superBar;
        ctx.lineWidth = 6;
        ctx.beginPath();
        ctx.arc(p.x, p.y, e.r * 0.85, e.a0 + t * 3, e.a0 + t * 3 + 2.2);
        ctx.stroke();
        ctx.beginPath();
        ctx.arc(p.x, p.y, e.r * 0.85, e.a0 + Math.PI + t * 3, e.a0 + Math.PI + t * 3 + 2.2);
        ctx.stroke();
        break;
      case 'streak':
        ctx.globalAlpha = a * 0.7;
        ctx.save();
        ctx.translate(e.x, e.y);
        ctx.rotate(e.angle);
        ctx.fillStyle = '#ffb08a';
        ctx.fillRect(0, (-e.width / 2) * a, e.length, e.width * a);
        ctx.restore();
        break;
      case 'bolt':
        drawBolt(ctx, e, a);
        break;
      case 'death':
        ctx.globalAlpha = a;
        ctx.fillStyle = t < 0.35 ? '#ffffff' : e.color;
        ctx.beginPath();
        ctx.arc(e.x, e.y, Math.max(0.5, e.r * (1 + 0.3 * t) * (1 - t * t)), 0, TAU);
        ctx.fill();
        break;
      default:
        break;
    }
  }
  ctx.globalAlpha = 1;
}

function drawSlash(ctx, px, py, e, t, a) {
  const half = e.arc / 2;
  const heavy = e.index === 2 || e.strike;
  const r = e.range * (0.75 + 0.25 * t);
  ctx.save();
  ctx.translate(px, py);
  ctx.rotate(e.angle);
  // Croissant : l'arc balaie de -half à +half (ou l'inverse pour le 2e coup).
  const dir = e.index === 1 ? -1 : 1;
  const sweep = Math.min(1, t * 2.2);
  const a0 = -half * dir;
  const a1 = a0 + e.arc * dir * sweep;
  ctx.globalAlpha = a * 0.95;
  ctx.fillStyle = e.strike ? PAL.slashStrike : PAL.slash;
  ctx.beginPath();
  ctx.arc(0, 0, r, Math.min(a0, a1), Math.max(a0, a1));
  ctx.arc(0, 0, r * (heavy ? 0.45 : 0.6), Math.max(a0, a1), Math.min(a0, a1), true);
  ctx.closePath();
  ctx.fill();
  ctx.globalAlpha = a * 0.35;
  ctx.fillStyle = PAL.heroCape;
  ctx.beginPath();
  ctx.arc(0, 0, r * 1.08, Math.min(a0, a1), Math.max(a0, a1));
  ctx.arc(0, 0, r * 0.9, Math.max(a0, a1), Math.min(a0, a1), true);
  ctx.closePath();
  ctx.fill();
  ctx.restore();
  ctx.globalAlpha = 1;
}

function drawBolt(ctx, e, a) {
  ctx.globalAlpha = a;
  ctx.strokeStyle = '#bff8ff';
  ctx.lineWidth = 3;
  ctx.beginPath();
  ctx.moveTo(e.x0, e.y0);
  const segs = 6;
  for (let i = 1; i < segs; i++) {
    const t = i / segs;
    const j = Math.sin(e.seed + i * 12.9) * 14;
    const dx = e.x1 - e.x0;
    const dy = e.y1 - e.y0;
    const l = Math.hypot(dx, dy) || 1;
    ctx.lineTo(e.x0 + dx * t + (-dy / l) * j, e.y0 + dy * t + (dx / l) * j);
  }
  ctx.lineTo(e.x1, e.y1);
  ctx.stroke();
  ctx.globalAlpha = 1;
}

export function drawTexts(ctx, fx) {
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  for (const t of fx.texts) {
    const a = Math.min(1, t.life / (t.max * 0.5));
    const pop = 1 + Math.max(0, (t.life - t.max + 0.12) / 0.12) * 0.5;
    ctx.globalAlpha = a;
    ctx.font = `800 ${Math.round(t.size * pop)}px system-ui, -apple-system, "Segoe UI", sans-serif`;
    ctx.lineWidth = 3;
    ctx.strokeStyle = 'rgba(10, 4, 8, 0.85)';
    ctx.strokeText(t.text, t.x, t.y);
    ctx.fillStyle = t.color;
    ctx.fillText(t.text, t.x, t.y);
  }
  ctx.globalAlpha = 1;
}

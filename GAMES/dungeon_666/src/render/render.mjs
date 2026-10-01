// Rendu du monde (espace salle) sur canvas 2D. Lecture seule de la simulation.
// Ordre de dessin = ordre de lisibilité : sol < télégraphes < objets < ennemis < héros <
// projectiles < effets < textes. Les dangers sont dessinés AVANT les corps pour rester
// visibles sous les mêlées, et leur intensité monte à l'approche de l'impact.

import { PAL, ELITE_COLORS, ELITE_NAMES, CIRCLE_TINTS, REWARD_COLORS } from './palette.mjs';
import { drawParticles, drawEffects, drawTexts } from './fx.mjs';
import { hazardProgress } from '../sim/projectiles.mjs';
import { FAMILIES } from '../sim/boons.mjs';
import { ITEM_RARITIES } from '../sim/loot.mjs';
import { REWARD_LABELS } from '../sim/run.mjs';
import { EXTRA_ART, EXTRA_BODY } from './art.mjs';
import { computeAim } from '../sim/aim.mjs';

const TAU = Math.PI * 2;
const TILE = 88;
// Échelles VISUELLES (les hitbox de la sim ne changent pas) : sur un téléphone, le héros et
// les projectiles ennemis doivent se lire au premier coup d'œil (critique « fun » n°3).
const HERO_VISUAL = 1.18;
const ENEMY_SHOT_VISUAL = 1.3;
const WALL_OVERDRAW = 1200; // u de mur peints autour de la salle (la caméra peut déborder)
const FONT = 'system-ui, -apple-system, "Segoe UI", sans-serif';
// Salles calmes du plan de section (calm_rooms.mjs) : couleur de leur porte et de leur objet.
const CALM_COLORS = { treasure: '#ffb43c', rest: '#6dd8ff' };

// ------------------------------------------------------------------ textures mises en cache

const cache = { tiles: new Map(), glows: new Map(), grads: new Map(), deco: null, decoRoom: null };

/** Dégradé vertical transparent -> couleur, mis en cache (portes, colonnes de butin). */
function verticalGradient(ctx, y0, y1, color) {
  const key = `${y0}|${y1}|${color}`;
  let g = cache.grads.get(key);
  if (!g) {
    g = ctx.createLinearGradient(0, y0, 0, y1);
    g.addColorStop(0, 'rgba(0,0,0,0)');
    g.addColorStop(1, color);
    if (cache.grads.size > 64) cache.grads.clear();
    cache.grads.set(key, g);
  }
  return g;
}

function makeCanvas(w, h) {
  if (typeof OffscreenCanvas !== 'undefined') return new OffscreenCanvas(w, h);
  const c = document.createElement('canvas');
  c.width = w;
  c.height = h;
  return c;
}

function tilePattern(ctx, tint) {
  let pat = cache.tiles.get(tint);
  if (pat) return pat;
  const n = 3; // 3 × 3 dalles par motif : la répétition se voit moins
  const size = TILE * n;
  const c = makeCanvas(size, size);
  const g = c.getContext('2d');
  g.fillStyle = PAL.crack;
  g.fillRect(0, 0, size, size);
  let seed = 7;
  const rnd = () => {
    seed = (Math.imul(seed, 1103515245) + 12345) >>> 0;
    return seed / 4294967296;
  };
  const shades = [PAL.floorA, PAL.floorB, '#1e1318', '#24171d'];
  for (let i = 0; i < n; i++) {
    for (let j = 0; j < n; j++) {
      const x = i * TILE + 1.5;
      const y = j * TILE + 1.5;
      const w = TILE - 3;
      g.fillStyle = shades[Math.floor(rnd() * shades.length)];
      g.fillRect(x, y, w, w);
      // Biseau discret : lumière en haut à gauche, ombre en bas à droite.
      g.fillStyle = 'rgba(255, 220, 200, 0.035)';
      g.fillRect(x, y, w, 3);
      g.fillRect(x, y, 3, w);
      g.fillStyle = 'rgba(0, 0, 0, 0.18)';
      g.fillRect(x, y + w - 3, w, 3);
      g.fillRect(x + w - 3, y, 3, w);
      // Grain de pierre.
      for (let k = 0; k < 10; k++) {
        g.fillStyle = rnd() < 0.5 ? 'rgba(0,0,0,0.12)' : 'rgba(255,255,255,0.025)';
        g.fillRect(x + rnd() * w, y + rnd() * w, 2 + rnd() * 3, 2 + rnd() * 3);
      }
      g.globalAlpha = 0.04;
      g.fillStyle = tint;
      g.fillRect(x, y, w, w);
      g.globalAlpha = 1;
    }
  }
  pat = ctx.createPattern(c, 'repeat');
  cache.tiles.set(tint, pat);
  return pat;
}

function glow(color, radius) {
  const key = `${color}|${radius}`;
  let c = cache.glows.get(key);
  if (c) return c;
  const s = radius * 2;
  c = makeCanvas(s, s);
  const g = c.getContext('2d');
  const grad = g.createRadialGradient(radius, radius, 0, radius, radius, radius);
  grad.addColorStop(0, color);
  grad.addColorStop(1, 'rgba(0,0,0,0)');
  g.fillStyle = grad;
  g.fillRect(0, 0, s, s);
  cache.glows.set(key, c);
  return c;
}

function drawGlow(ctx, x, y, radius, color, alpha) {
  ctx.globalAlpha = alpha;
  ctx.globalCompositeOperation = 'lighter';
  ctx.drawImage(glow(color, 64), x - radius, y - radius, radius * 2, radius * 2);
  ctx.globalCompositeOperation = 'source-over';
  ctx.globalAlpha = 1;
}

/** Décor procédural d'une salle (fissures, veines de lave), stable pour une salle donnée. */
function roomDeco(room, seed) {
  if (cache.decoRoom === room) return cache.deco;
  let s = seed >>> 0 || 1;
  const rnd = () => {
    s = (Math.imul(s, 1664525) + 1013904223) >>> 0;
    return s / 4294967296;
  };
  const cracks = [];
  for (let i = 0; i < 14; i++) {
    const pts = [[rnd() * room.w, rnd() * room.h]];
    let a = rnd() * TAU;
    for (let k = 0; k < 4; k++) {
      a += (rnd() - 0.5) * 1.4;
      const [x, y] = pts[pts.length - 1];
      pts.push([x + Math.cos(a) * (20 + rnd() * 40), y + Math.sin(a) * (20 + rnd() * 40)]);
    }
    cracks.push({ pts, lava: rnd() < 0.35 });
  }
  const pools = [];
  for (let i = 0; i < 4; i++) pools.push({ x: rnd() * room.w, y: rnd() * room.h, r: 30 + rnd() * 50 });
  cache.deco = { cracks, pools };
  cache.decoRoom = room;
  return cache.deco;
}

// ------------------------------------------------------------------ salle

function drawRoom(ctx, game, time) {
  const room = game.room;
  const tint = CIRCLE_TINTS[(game.info.circle - 1) % CIRCLE_TINTS.length];
  ctx.fillStyle = tilePattern(ctx, tint);
  ctx.fillRect(0, 0, room.w, room.h);
  const deco = roomDeco(room, game.run.floor * 7919 + game.seed);
  for (const pool of deco.pools) drawGlow(ctx, pool.x, pool.y, pool.r * 2, tint, 0.1 + 0.03 * Math.sin(time * 1.3 + pool.x));
  ctx.lineCap = 'round';
  for (const c of deco.cracks) {
    ctx.strokeStyle = c.lava ? tint : PAL.crack;
    ctx.globalAlpha = c.lava ? 0.35 + 0.15 * Math.sin(time * 2 + c.pts[0][0]) : 0.9;
    ctx.lineWidth = c.lava ? 2.5 : 3;
    ctx.beginPath();
    ctx.moveTo(c.pts[0][0], c.pts[0][1]);
    for (let i = 1; i < c.pts.length; i++) ctx.lineTo(c.pts[i][0], c.pts[i][1]);
    ctx.stroke();
  }
  ctx.globalAlpha = 1;
  drawWalls(ctx, room, tint, time);
  for (const o of room.obstacles) drawPillar(ctx, o);
}

function drawWalls(ctx, room, tint, time) {
  const p = room.pad;
  const out = WALL_OVERDRAW;
  ctx.fillStyle = PAL.wall;
  ctx.fillRect(-out, -out, room.w + 2 * out, out + p);
  ctx.fillRect(-out, room.h - p, room.w + 2 * out, out + p);
  ctx.fillRect(-out, 0, out + p, room.h);
  ctx.fillRect(room.w - p, 0, out + p, room.h);
  ctx.strokeStyle = PAL.wallEdge;
  ctx.lineWidth = 3;
  ctx.strokeRect(p, p, room.w - 2 * p, room.h - 2 * p);
  // Ombre portée des murs vers l'intérieur.
  ctx.fillStyle = 'rgba(0,0,0,0.35)';
  ctx.fillRect(p, p, room.w - 2 * p, 18);
  for (const d of room.doors) drawDoor(ctx, d, time);
}

function drawDoor(ctx, d, time) {
  const color = d.reward === 'boon' && d.family ? FAMILIES[d.family].color : REWARD_COLORS[d.reward] ?? CALM_COLORS[d.reward] ?? '#ffffff';
  const cx = d.x + d.w / 2;
  // Arche : fond noir, voûte arrondie en haut.
  const archPath = () => {
    ctx.beginPath();
    ctx.moveTo(d.x, d.y + d.h);
    ctx.lineTo(d.x, d.y + d.w / 2 - 20);
    ctx.arc(cx, d.y + d.w / 2 - 20, d.w / 2, Math.PI, 0);
    ctx.lineTo(d.x + d.w, d.y + d.h);
    ctx.closePath();
  };
  ctx.fillStyle = '#0a0508';
  archPath();
  ctx.fill();
  if (d.open) {
    drawGlow(ctx, cx, d.h - 10, 90, color, 0.35 + 0.1 * Math.sin(time * 4));
    ctx.globalAlpha = 0.45 + 0.1 * Math.sin(time * 3);
    ctx.fillStyle = verticalGradient(ctx, d.y, d.y + d.h, color);
    archPath();
    ctx.fill();
    ctx.globalAlpha = 1;
  } else {
    ctx.strokeStyle = '#3a2a30';
    ctx.lineWidth = 4;
    for (let x = d.x + 14; x < d.x + d.w; x += 18) {
      ctx.beginPath();
      ctx.moveTo(x, d.y);
      ctx.lineTo(x, d.y + d.h);
      ctx.stroke();
    }
  }
  ctx.strokeStyle = d.open ? color : PAL.wallEdge;
  ctx.lineWidth = 4;
  archPath();
  ctx.stroke();
  // Icône de récompense + libellé.
  const label = d.reward === 'boon' && d.family ? FAMILIES[d.family].name : REWARD_LABELS[d.reward];
  const iconColor = d.reward === 'boon' && d.family ? FAMILIES[d.family].color : color;
  drawRewardIcon(ctx, d.reward, cx, d.h + 26, 13, iconColor, time);
  ctx.font = `700 14px ${FONT}`;
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.lineWidth = 3;
  ctx.strokeStyle = 'rgba(0,0,0,0.8)';
  ctx.strokeText(label, cx, d.h + 50);
  ctx.fillStyle = d.open ? iconColor : PAL.textDim;
  ctx.fillText(label, cx, d.h + 50);
}

function drawRewardIcon(ctx, reward, x, y, r, color, time) {
  ctx.save();
  ctx.translate(x, y + Math.sin(time * 3) * 2);
  ctx.fillStyle = color;
  ctx.strokeStyle = 'rgba(0,0,0,0.7)';
  ctx.lineWidth = 2;
  ctx.beginPath();
  switch (reward) {
    case 'boon':
      ctx.arc(0, 0, r, 0, TAU);
      break;
    case 'loot':
    case 'elite':
      ctx.moveTo(0, -r);
      ctx.lineTo(r, 0);
      ctx.lineTo(0, r);
      ctx.lineTo(-r, 0);
      break;
    case 'gold':
      ctx.ellipse(0, 0, r, r * 0.8, 0, 0, TAU);
      break;
    case 'heal':
      ctx.rect(-r * 0.35, -r, r * 0.7, r * 2);
      ctx.rect(-r, -r * 0.35, r * 2, r * 0.7);
      break;
    case 'boss':
      ctx.arc(0, 0, r, 0, TAU);
      ctx.moveTo(-r, -r * 0.4);
      ctx.lineTo(-r * 0.6, -r * 1.4);
      ctx.lineTo(-r * 0.2, -r * 0.6);
      ctx.moveTo(r, -r * 0.4);
      ctx.lineTo(r * 0.6, -r * 1.4);
      ctx.lineTo(r * 0.2, -r * 0.6);
      break;
    case 'town':
      // Portail : anneau (téléportation vers la Ville).
      ctx.arc(0, 0, r, 0, TAU);
      ctx.arc(0, 0, r * 0.55, 0, TAU, true);
      break;
    case 'treasure':
      // Coffre : caisse et couvercle bombé.
      ctx.rect(-r, -r * 0.2, r * 2, r);
      ctx.moveTo(-r, -r * 0.2);
      ctx.quadraticCurveTo(0, -r * 1.3, r, -r * 0.2);
      ctx.closePath();
      break;
    case 'rest':
      // Goutte d'eau (fontaine).
      ctx.moveTo(0, -r * 1.2);
      ctx.quadraticCurveTo(r, 0, r * 0.7, r * 0.45);
      ctx.arc(0, r * 0.2, r * 0.75, 0.35, Math.PI - 0.35);
      ctx.quadraticCurveTo(-r, 0, 0, -r * 1.2);
      break;
    default:
      ctx.rect(-r * 0.8, -r * 0.8, r * 1.6, r * 1.6);
  }
  ctx.fill();
  ctx.stroke();
  ctx.restore();
}

function drawPillar(ctx, o) {
  const h = 14; // hauteur apparente (fausse 3D vue de dessus)
  ctx.fillStyle = PAL.shadow;
  ctx.fillRect(o.x0 + 6, o.y0 + 10, o.x1 - o.x0, o.y1 - o.y0);
  ctx.fillStyle = PAL.pillarSide;
  ctx.fillRect(o.x0, o.y0, o.x1 - o.x0, o.y1 - o.y0);
  ctx.fillStyle = PAL.pillarTop;
  ctx.fillRect(o.x0, o.y0 - h, o.x1 - o.x0, o.y1 - o.y0);
  ctx.strokeStyle = PAL.wallEdge;
  ctx.lineWidth = 2;
  ctx.strokeRect(o.x0, o.y0 - h, o.x1 - o.x0, o.y1 - o.y0);
}

// ------------------------------------------------------------------ télégraphes

function dangerAlpha(progress) {
  // Clignotement accéléré dans le dernier quart : « ça part ».
  if (progress < 0.75) return 1;
  return 0.75 + 0.25 * Math.sin(progress * 60);
}

function drawCone(ctx, x, y, angle, range, arc, progress) {
  ctx.fillStyle = PAL.dangerFill;
  ctx.beginPath();
  ctx.moveTo(x, y);
  ctx.arc(x, y, range, angle - arc / 2, angle + arc / 2);
  ctx.closePath();
  ctx.fill();
  ctx.globalAlpha = dangerAlpha(progress);
  ctx.fillStyle = PAL.dangerFillHot;
  ctx.beginPath();
  ctx.moveTo(x, y);
  ctx.arc(x, y, range * Math.min(1, progress), angle - arc / 2, angle + arc / 2);
  ctx.closePath();
  ctx.fill();
  ctx.globalAlpha = 1;
  ctx.strokeStyle = PAL.danger;
  ctx.lineWidth = 2;
  ctx.beginPath();
  ctx.arc(x, y, range, angle - arc / 2, angle + arc / 2);
  ctx.stroke();
}

function drawLine(ctx, x, y, angle, length, width, progress) {
  ctx.save();
  ctx.translate(x, y);
  ctx.rotate(angle);
  ctx.fillStyle = PAL.dangerFill;
  ctx.fillRect(0, -width / 2, length, width);
  ctx.globalAlpha = dangerAlpha(progress);
  ctx.fillStyle = PAL.dangerFillHot;
  ctx.fillRect(0, -width / 2, length * Math.min(1, progress), width);
  ctx.globalAlpha = 1;
  ctx.strokeStyle = PAL.danger;
  ctx.lineWidth = 2;
  ctx.strokeRect(0, -width / 2, length, width);
  ctx.restore();
}

function drawCircleDanger(ctx, x, y, r, progress, inner = 0) {
  ctx.fillStyle = PAL.dangerFill;
  ctx.beginPath();
  ctx.arc(x, y, r, 0, TAU);
  if (inner > 0) ctx.arc(x, y, inner, 0, TAU, true);
  ctx.fill();
  ctx.globalAlpha = dangerAlpha(progress);
  ctx.fillStyle = PAL.dangerFillHot;
  ctx.beginPath();
  // Anneau : la jauge part du bord intérieur, le centre (sûr) n'est jamais peint en rouge vif.
  ctx.arc(x, y, Math.max(0.1, inner + (r - inner) * Math.min(1, progress)), 0, TAU);
  if (inner > 0) ctx.arc(x, y, inner, 0, TAU, true);
  ctx.fill();
  ctx.globalAlpha = 1;
  ctx.strokeStyle = PAL.danger;
  ctx.lineWidth = 2.5;
  ctx.beginPath();
  ctx.arc(x, y, r, 0, TAU);
  ctx.stroke();
  if (inner > 0) {
    ctx.beginPath();
    ctx.arc(x, y, inner, 0, TAU);
    ctx.stroke();
  }
}

function drawTelegraphs(ctx, game) {
  for (const h of game.hazards) {
    const pr = hazardProgress(h);
    if (!h.hitsPlayer) continue; // les explosions des bénédictions ne menacent pas le héros
    if (h.shape === 'circle') drawCircleDanger(ctx, h.x, h.y, h.r, pr);
    else if (h.shape === 'ring') drawCircleDanger(ctx, h.x, h.y, h.r, pr, h.inner);
    else drawLine(ctx, h.x, h.y, h.angle, h.length, h.width, pr);
  }
  for (const e of game.enemies) {
    const t = e.tele;
    if (!t || e.dead) continue;
    if (t.harmless) drawHarmlessCircle(ctx, e.x, e.y, t.r, t.progress);
    else if (t.shape === 'cone') drawCone(ctx, e.x, e.y, t.angle, t.range, t.arc, t.progress);
    else if (t.shape === 'line') drawLine(ctx, e.x, e.y, t.angle, t.length, t.width, t.progress);
    else drawCircleDanger(ctx, e.x, e.y, t.r, t.progress);
  }
}

/** Alerte sans danger (invocation) : violet, sans remplissage rouge. Rouge = ça fait mal. */
function drawHarmlessCircle(ctx, x, y, r, progress) {
  ctx.strokeStyle = PAL.summon;
  ctx.globalAlpha = 0.35 + 0.5 * Math.min(1, progress);
  ctx.lineWidth = 2.5;
  ctx.beginPath();
  ctx.arc(x, y, r, 0, TAU);
  ctx.stroke();
  ctx.beginPath();
  ctx.arc(x, y, Math.max(0.1, r * Math.min(1, progress)), 0, TAU);
  ctx.stroke();
  ctx.globalAlpha = 1;
}

/** Contours seuls des télégraphes, retracés au-dessus du héros et des ennemis : le bord reste lisible. */
function drawTelegraphEdges(ctx, game) {
  ctx.strokeStyle = PAL.danger;
  ctx.lineWidth = 2.5;
  ctx.beginPath();
  for (const h of game.hazards) {
    if (!h.hitsPlayer) continue;
    if (h.shape === 'line') lineEdge(ctx, h.x, h.y, h.angle, h.length, h.width);
    else {
      ctx.moveTo(h.x + h.r, h.y);
      ctx.arc(h.x, h.y, h.r, 0, TAU);
      if (h.shape === 'ring' && h.inner > 0) {
        ctx.moveTo(h.x + h.inner, h.y);
        ctx.arc(h.x, h.y, h.inner, 0, TAU);
      }
    }
  }
  for (const e of game.enemies) {
    const t = e.tele;
    if (!t || e.dead || t.harmless) continue;
    if (t.shape === 'cone') {
      const a0 = t.angle - t.arc / 2;
      ctx.moveTo(e.x + Math.cos(a0) * t.range, e.y + Math.sin(a0) * t.range);
      ctx.arc(e.x, e.y, t.range, a0, t.angle + t.arc / 2);
    } else if (t.shape === 'line') lineEdge(ctx, e.x, e.y, t.angle, t.length, t.width);
    else {
      ctx.moveTo(e.x + t.r, e.y);
      ctx.arc(e.x, e.y, t.r, 0, TAU);
    }
  }
  ctx.stroke();
}

function lineEdge(ctx, x, y, angle, length, width) {
  const c = Math.cos(angle);
  const s = Math.sin(angle);
  const hw = width / 2;
  ctx.moveTo(x - s * hw, y + c * hw);
  ctx.lineTo(x + c * length - s * hw, y + s * length + c * hw);
  ctx.lineTo(x + c * length + s * hw, y + s * length - c * hw);
  ctx.lineTo(x + s * hw, y - c * hw);
  ctx.closePath();
}

function drawSpawnWarns(ctx, game, time) {
  for (const s of game.spawns) {
    const k = 1 - s.t / s.warn;
    const r = 18 + 14 * k;
    ctx.strokeStyle = s.elite ? PAL.eliteArdent : '#c0304a';
    ctx.globalAlpha = 0.4 + 0.5 * k;
    ctx.lineWidth = 2;
    ctx.setLineDash([6, 6]);
    ctx.lineDashOffset = -time * 40;
    ctx.beginPath();
    ctx.arc(s.x, s.y, r, 0, TAU);
    ctx.stroke();
    ctx.setLineDash([]);
    ctx.beginPath();
    ctx.arc(s.x, s.y, r * 0.55, 0, TAU);
    ctx.stroke();
    ctx.globalAlpha = 1;
    drawGlow(ctx, s.x, s.y, r * 2, '#ff2a4a', 0.25 * k);
  }
}

// ------------------------------------------------------------------ objets et butin

function drawPickups(ctx, game, time) {
  for (const pk of game.pickups) {
    if (pk.kind === 'gold') {
      ctx.save();
      ctx.translate(pk.x, pk.y);
      ctx.rotate(Math.PI / 4);
      ctx.fillStyle = PAL.gold;
      ctx.fillRect(-4, -4, 8, 8);
      ctx.restore();
      if ((time * 4 + pk.id) % 3 < 0.2) drawGlow(ctx, pk.x, pk.y, 14, PAL.gold, 0.6);
    } else {
      drawGlow(ctx, pk.x, pk.y, 26, PAL.heal, 0.5);
      ctx.fillStyle = PAL.heal;
      ctx.fillRect(pk.x - 3, pk.y - 9, 6, 18);
      ctx.fillRect(pk.x - 9, pk.y - 3, 18, 6);
    }
  }
}

function drawInteract(ctx, game, time) {
  const it = game.room.interact;
  if (!it || it.used) return;
  const bob = Math.sin(time * 3) * 4;
  let color = '#ffffff';
  let label = '';
  if (it.kind === 'boon') {
    color = FAMILIES[it.family].color;
    label = `Bénédiction · ${FAMILIES[it.family].name}`;
    drawGlow(ctx, it.x, it.y + bob, 70, color, 0.55);
    ctx.fillStyle = color;
    ctx.beginPath();
    ctx.arc(it.x, it.y + bob, 15, 0, TAU);
    ctx.fill();
    ctx.strokeStyle = '#ffffff';
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.arc(it.x, it.y + bob, 22 + 3 * Math.sin(time * 5), 0, TAU);
    ctx.stroke();
  } else if (it.kind === 'loot') {
    const rar = ITEM_RARITIES.find((r) => r.id === it.item.rarity);
    color = rar.color;
    label = it.item.name;
    // Colonne de lumière façon Diablo, plus haute pour les raretés élevées.
    const idx = ITEM_RARITIES.indexOf(rar);
    const h = 60 + idx * 50;
    ctx.globalAlpha = 0.35 + 0.1 * Math.sin(time * 4);
    ctx.fillStyle = verticalGradient(ctx, it.y - h, it.y, color);
    ctx.fillRect(it.x - 10, it.y - h, 20, h);
    ctx.globalAlpha = 1;
    drawGlow(ctx, it.x, it.y, 40, color, 0.5);
    drawItemGlyph(ctx, it.item.slot, it.x, it.y + bob * 0.5, color);
  } else if (it.kind === 'shop') {
    color = '#7fe8ff';
    label = 'Marchand des âmes';
    ctx.fillStyle = '#3a2430';
    ctx.fillRect(it.x - 46, it.y - 6, 92, 26);
    ctx.fillStyle = '#5a3a44';
    ctx.fillRect(it.x - 50, it.y - 12, 100, 8);
    ctx.fillStyle = '#18101a';
    ctx.beginPath();
    ctx.arc(it.x, it.y - 30, 16, 0, TAU);
    ctx.fill();
    ctx.fillStyle = color;
    ctx.fillRect(it.x - 6, it.y - 34, 3, 3);
    ctx.fillRect(it.x + 3, it.y - 34, 3, 3);
    drawGlow(ctx, it.x, it.y - 20, 50, color, 0.25);
  } else if (it.kind === 'event') {
    color = '#b98cff';
    label = 'Autel';
    ctx.fillStyle = '#2e2433';
    ctx.fillRect(it.x - 30, it.y - 14, 60, 28);
    ctx.strokeStyle = color;
    ctx.lineWidth = 2;
    ctx.strokeRect(it.x - 30, it.y - 14, 60, 28);
    drawGlow(ctx, it.x, it.y - 10, 60, color, 0.35 + 0.15 * Math.sin(time * 3));
  } else if (it.kind === 'treasure') {
    color = CALM_COLORS.treasure;
    label = 'Chambre forte';
    drawChest(ctx, it.x, it.y, color, time);
  } else if (it.kind === 'rest') {
    color = CALM_COLORS.rest;
    label = 'Fontaine du Léthé';
    drawFountain(ctx, it.x, it.y, color, time);
  }
  ctx.font = `700 14px ${FONT}`;
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.lineWidth = 3;
  ctx.strokeStyle = 'rgba(0,0,0,0.85)';
  ctx.strokeText(label, it.x, it.y + 40);
  ctx.fillStyle = color;
  ctx.fillText(label, it.x, it.y + 40);
}

/** Coffre scellé de la chambre forte : caisse, couvercle, ferrures et sceau qui pulse. */
function drawChest(ctx, x, y, color, time) {
  drawGlow(ctx, x, y - 6, 70, color, 0.3 + 0.1 * Math.sin(time * 2.5));
  ctx.fillStyle = PAL.shadow;
  ctx.fillRect(x - 30, y + 12, 64, 10);
  ctx.fillStyle = '#4a2a1a';
  ctx.fillRect(x - 32, y - 8, 64, 26);
  ctx.beginPath();
  ctx.moveTo(x - 32, y - 8);
  ctx.quadraticCurveTo(x, y - 34, x + 32, y - 8);
  ctx.closePath();
  ctx.fillStyle = '#5e3620';
  ctx.fill();
  ctx.strokeStyle = color;
  ctx.lineWidth = 3;
  ctx.strokeRect(x - 32, y - 8, 64, 26);
  ctx.beginPath();
  ctx.moveTo(x - 32, y - 8);
  ctx.quadraticCurveTo(x, y - 34, x + 32, y - 8);
  ctx.stroke();
  ctx.fillStyle = color;
  ctx.fillRect(x - 6, y - 12, 12, 14);
  ctx.globalAlpha = 0.6 + 0.4 * Math.sin(time * 4);
  ctx.fillStyle = '#fff4c0';
  ctx.fillRect(x - 2, y - 8, 4, 6);
  ctx.globalAlpha = 1;
}

/** Fontaine du repos : vasque de pierre, eau claire qui ondule (jamais rouge : rien ne blesse). */
function drawFountain(ctx, x, y, color, time) {
  drawGlow(ctx, x, y - 4, 80, color, 0.3 + 0.1 * Math.sin(time * 2));
  ctx.fillStyle = PAL.shadow;
  ctx.beginPath();
  ctx.ellipse(x + 4, y + 16, 40, 12, 0, 0, TAU);
  ctx.fill();
  ctx.fillStyle = '#3a3440';
  ctx.beginPath();
  ctx.ellipse(x, y + 4, 38, 18, 0, 0, TAU);
  ctx.fill();
  ctx.fillStyle = color;
  ctx.globalAlpha = 0.75;
  ctx.beginPath();
  ctx.ellipse(x, y + 2, 30, 12, 0, 0, TAU);
  ctx.fill();
  ctx.globalAlpha = 1;
  ctx.strokeStyle = '#e8fbff';
  ctx.lineWidth = 1.5;
  for (let i = 0; i < 2; i++) {
    const k = (time * 0.8 + i * 0.5) % 1;
    ctx.globalAlpha = 1 - k;
    ctx.beginPath();
    ctx.ellipse(x, y + 2, 6 + 22 * k, 2 + 9 * k, 0, 0, TAU);
    ctx.stroke();
  }
  ctx.globalAlpha = 1;
  ctx.fillStyle = '#5a5262';
  ctx.fillRect(x - 5, y - 26, 10, 26);
  ctx.fillStyle = color;
  ctx.beginPath();
  ctx.arc(x, y - 28, 5 + Math.sin(time * 5), 0, TAU);
  ctx.fill();
}

function drawItemGlyph(ctx, slot, x, y, color) {
  ctx.save();
  ctx.translate(x, y);
  ctx.fillStyle = color;
  ctx.strokeStyle = '#120a0e';
  ctx.lineWidth = 2;
  ctx.beginPath();
  if (slot === 'arme') {
    ctx.rotate(-Math.PI / 4);
    ctx.rect(-3, -18, 6, 26);
    ctx.rect(-9, 6, 18, 4);
    ctx.rect(-2, 10, 4, 8);
  } else if (slot === 'armure') {
    ctx.moveTo(-14, -12);
    ctx.lineTo(14, -12);
    ctx.lineTo(10, 14);
    ctx.lineTo(-10, 14);
    ctx.closePath();
  } else {
    ctx.arc(0, 0, 10, 0, TAU);
    ctx.moveTo(4, 0);
    ctx.arc(0, 0, 4, 0, TAU, true);
  }
  ctx.fill();
  ctx.stroke();
  ctx.restore();
}

// ------------------------------------------------------------------ créatures

const ENEMY_BODY = { imp: PAL.imp, archer: PAL.archer, brute: PAL.brute, charger: PAL.charger, exploder: PAL.exploder, gardien: PAL.boss };

function drawShadow(ctx, x, y, r) {
  ctx.fillStyle = PAL.shadow;
  ctx.beginPath();
  ctx.ellipse(x, y + r * 0.55, r * 1.05, r * 0.5, 0, 0, TAU);
  ctx.fill();
}

function drawEnemy(ctx, e, game, time) {
  let scale = 1;
  let alpha = 1;
  if (e.spawnT > 0) {
    // Apparition « easeOutBack » : 0 -> 1,15 -> 1.
    const k = 1 - Math.max(0, e.spawnT) / 0.25;
    const s = 1.70158;
    scale = Math.max(0.05, 1 + (s + 1) * (k - 1) ** 3 + s * (k - 1) ** 2);
    alpha = 0.5 + 0.5 * k;
  }
  if (e.state === 'windup') scale *= 1 + 0.1 * Math.sin(e.stateTime * 30);
  const r = e.r * scale;
  const face = Math.atan2(game.player.y - e.y, game.player.x - e.x);
  drawShadow(ctx, e.x, e.y, r);
  if (e.eliteMod) {
    const ec = ELITE_COLORS[e.eliteMod];
    drawGlow(ctx, e.x, e.y, r * 2.6, ec, 0.45);
    ctx.strokeStyle = ec;
    ctx.lineWidth = 3;
    ctx.setLineDash([8, 6]);
    ctx.lineDashOffset = -time * 30;
    ctx.beginPath();
    ctx.arc(e.x, e.y, r + 7, 0, TAU);
    ctx.stroke();
    ctx.setLineDash([]);
  }
  if (e.boss) drawGlow(ctx, e.x, e.y, r * 2.4, e.phase === 2 ? '#ff3a1a' : '#8a1a3a', 0.5 + 0.15 * Math.sin(time * 5));
  if (e.kind === 'exploder' && e.state === 'windup') drawGlow(ctx, e.x, e.y, r * 4, '#ff9c2a', 0.4 + 0.4 * Math.sin(e.stateTime * 40));
  ctx.globalAlpha = alpha;
  ctx.save();
  ctx.translate(e.x, e.y);
  if (e.flash > 0 && (e.hitDirX || e.hitDirY)) {
    // Touché : tremblement le long de l'axe du coup pendant le gel (principe de Sakurai),
    // puis écrasement dans l'axe (aire conservée).
    const a = Math.atan2(e.hitDirY, e.hitDirX);
    const jitter = game.hitstop > 0 || e.freeze > 0 ? (Math.floor(time * 60) % 2 === 0 ? 2 : -2) : 0;
    ctx.translate(Math.cos(a) * jitter, Math.sin(a) * jitter);
    if (!e.boss) {
      ctx.rotate(a);
      ctx.scale(0.8, 1.25);
      ctx.rotate(-a);
    }
  }
  const body = e.flash > 0 ? PAL.enemyFlash : ENEMY_BODY[e.kind] ?? EXTRA_BODY[e.kind] ?? PAL.imp;
  (KIND_DRAW[e.kind] ?? EXTRA_ART[e.kind] ?? KIND_DRAW.imp)(ctx, r, face, body, e, time);
  ctx.restore();
  ctx.globalAlpha = 1;
  if (e.chill > 0) {
    ctx.strokeStyle = '#8fd8ff';
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.arc(e.x, e.y, r + 3, 0, TAU);
    ctx.stroke();
  }
  if (e.burn > 0) drawGlow(ctx, e.x, e.y - r * 0.5, r * 1.6, PAL.lava, 0.45 + 0.2 * Math.sin(time * 20 + e.id));
  if (e.stun > 0) drawStun(ctx, e.x, e.y - r - 10, time);
  if (!e.boss && (e.hp < e.maxHp || e.eliteMod)) drawEnemyHp(ctx, e, r);
  if (e.eliteMod) {
    ctx.font = `800 11px ${FONT}`;
    ctx.textAlign = 'center';
    ctx.fillStyle = ELITE_COLORS[e.eliteMod];
    ctx.strokeStyle = 'rgba(0,0,0,0.85)';
    ctx.lineWidth = 3;
    const label = ELITE_NAMES[e.eliteMod].toUpperCase();
    ctx.strokeText(label, e.x, e.y - r - 22);
    ctx.fillText(label, e.x, e.y - r - 22);
  }
}

function outlineCircle(ctx, r, fill) {
  ctx.fillStyle = fill;
  ctx.strokeStyle = PAL.enemyOutline;
  ctx.lineWidth = 3;
  ctx.beginPath();
  ctx.arc(0, 0, r, 0, TAU);
  ctx.fill();
  ctx.stroke();
}

function eyes(ctx, r, face, color = '#ffe14a', spread = 0.45, dist = 0.45) {
  ctx.fillStyle = color;
  for (const s of [-spread, spread]) {
    const a = face + s;
    ctx.beginPath();
    ctx.arc(Math.cos(a) * r * dist, Math.sin(a) * r * dist, Math.max(1.5, r * 0.13), 0, TAU);
    ctx.fill();
  }
}

function horns(ctx, r, face, color, size = 0.6) {
  ctx.fillStyle = color;
  ctx.strokeStyle = PAL.enemyOutline;
  ctx.lineWidth = 2;
  for (const s of [-0.8, 0.8]) {
    const a = face + s;
    const bx = Math.cos(a) * r * 0.8;
    const by = Math.sin(a) * r * 0.8;
    ctx.beginPath();
    ctx.moveTo(bx + Math.cos(a + 1.6) * r * 0.25, by + Math.sin(a + 1.6) * r * 0.25);
    ctx.lineTo(bx + Math.cos(face + s * 0.6) * r * size, by + Math.sin(face + s * 0.6) * r * size);
    ctx.lineTo(bx + Math.cos(a - 1.6) * r * 0.25, by + Math.sin(a - 1.6) * r * 0.25);
    ctx.closePath();
    ctx.fill();
    ctx.stroke();
  }
}

const KIND_DRAW = {
  imp(ctx, r, face, body) {
    horns(ctx, r, face, '#2a0a0a', 0.7);
    outlineCircle(ctx, r, body);
    eyes(ctx, r, face);
  },
  archer(ctx, r, face, body, e) {
    outlineCircle(ctx, r, body);
    ctx.fillStyle = '#5b4436';
    ctx.beginPath();
    ctx.arc(-Math.cos(face) * r * 0.2, -Math.sin(face) * r * 0.2, r * 0.48, 0, TAU);
    ctx.fill();
    eyes(ctx, r, face, '#ff3b3b', 0.4, 0.4);
    // Arc tendu pendant la visée.
    const draw = e.state === 'windup' ? Math.min(1, e.stateTime / 0.4) : 0;
    ctx.strokeStyle = '#8a6a4a';
    ctx.lineWidth = 3;
    ctx.beginPath();
    ctx.arc(Math.cos(face) * r * (0.6 - 0.3 * draw), Math.sin(face) * r * (0.6 - 0.3 * draw), r * 0.9, face - 1.1, face + 1.1);
    ctx.stroke();
  },
  brute(ctx, r, face, body, e) {
    const raise = e.state === 'windup' ? 1.25 : 1;
    ctx.fillStyle = '#5a1a1a';
    ctx.strokeStyle = PAL.enemyOutline;
    ctx.lineWidth = 3;
    for (const s of [-1.3, 1.3]) {
      const a = face + s;
      ctx.beginPath();
      ctx.arc(Math.cos(a) * r * 0.85 * raise, Math.sin(a) * r * 0.85 * raise, r * 0.45, 0, TAU);
      ctx.fill();
      ctx.stroke();
    }
    outlineCircle(ctx, r, body);
    eyes(ctx, r, face, '#ffb03a', 0.35, 0.55);
  },
  charger(ctx, r, face, body, e) {
    horns(ctx, r, face, '#f0e0c0', e.state === 'charge' ? 1.5 : 1.2);
    outlineCircle(ctx, r, body);
    eyes(ctx, r, face, '#fff3a0', 0.5, 0.5);
  },
  exploder(ctx, r, face, body, e, time) {
    const pulse = e.state === 'windup' ? (Math.sin(e.stateTime * 40) > 0 ? '#ffffff' : body) : body;
    outlineCircle(ctx, r, pulse);
    ctx.strokeStyle = '#5a1a00';
    ctx.lineWidth = 2;
    ctx.beginPath();
    for (let i = 0; i < 4; i++) {
      const a = i * 1.7 + time;
      ctx.moveTo(0, 0);
      ctx.lineTo(Math.cos(a) * r * 0.9, Math.sin(a) * r * 0.9);
    }
    ctx.stroke();
  },
  gardien(ctx, r, face, body, e, time) {
    // Couronne de pointes dorées.
    ctx.fillStyle = PAL.bossTrim;
    ctx.strokeStyle = PAL.enemyOutline;
    ctx.lineWidth = 3;
    ctx.beginPath();
    const spikes = 9;
    for (let i = 0; i < spikes; i++) {
      const a = (i / spikes) * TAU + time * 0.3;
      ctx.moveTo(Math.cos(a - 0.18) * r, Math.sin(a - 0.18) * r);
      ctx.lineTo(Math.cos(a) * r * 1.35, Math.sin(a) * r * 1.35);
      ctx.lineTo(Math.cos(a + 0.18) * r, Math.sin(a + 0.18) * r);
    }
    ctx.fill();
    ctx.stroke();
    outlineCircle(ctx, r, body);
    ctx.fillStyle = '#2a0610';
    ctx.beginPath();
    ctx.arc(0, 0, r * 0.62, 0, TAU);
    ctx.fill();
    eyes(ctx, r, face, e.phase === 2 ? '#ff3a1a' : '#ffcf5a', 0.42, 0.35);
  },
};

function drawStun(ctx, x, y, time) {
  ctx.fillStyle = '#ffe14a';
  for (let i = 0; i < 3; i++) {
    const a = time * 6 + (i * TAU) / 3;
    ctx.beginPath();
    ctx.arc(x + Math.cos(a) * 12, y + Math.sin(a) * 4, 3, 0, TAU);
    ctx.fill();
  }
}

function drawEnemyHp(ctx, e, r) {
  const w = Math.max(28, r * 2.2);
  const x = e.x - w / 2;
  const y = e.y - r - 12;
  ctx.fillStyle = PAL.hpBack;
  ctx.fillRect(x, y, w, 5);
  ctx.fillStyle = e.eliteMod ? ELITE_COLORS[e.eliteMod] : PAL.hpBar;
  ctx.fillRect(x, y, (w * Math.max(0, e.hp)) / e.maxHp, 5);
}

function playerAlpha(p, time) {
  if (p.state === 'dead') return Math.max(0, 1 - p.stateTime);
  if (p.iframes > 0 && p.state !== 'dash' && p.hurtFlash <= 0 && Math.floor(time * 15) % 2 === 0) return 0.4;
  return 1;
}

/**
 * Traînées de dash, ombre et halos du héros : dessinés SOUS les télégraphes, sinon leur
 * mélange additif délave le rouge exactement là où l'attaque va frapper.
 */
function drawPlayerUnderlay(ctx, game, fx, time) {
  const p = game.player;
  const pr = p.r * HERO_VISUAL;
  for (const g of fx.ghosts) {
    ctx.globalAlpha = (g.life / g.max) * 0.45;
    ctx.fillStyle = PAL.heroCape;
    ctx.beginPath();
    ctx.arc(g.x, g.y, pr * 0.95, 0, TAU);
    ctx.fill();
  }
  const a = playerAlpha(p, time);
  ctx.globalAlpha = a;
  drawShadow(ctx, p.x, p.y, pr);
  drawGlow(ctx, p.x, p.y, 60, PAL.heroGlow, 0.9 * a);
  if (p.state === 'super') drawGlow(ctx, p.x, p.y, 150, PAL.superBar, (0.4 + 0.2 * Math.sin(time * 18)) * a);
  ctx.globalAlpha = 1;
}

function drawPlayer(ctx, game, fx, time) {
  const p = game.player;
  const pr = p.r * HERO_VISUAL;
  ctx.globalAlpha = playerAlpha(p, time);
  ctx.save();
  ctx.translate(p.x, p.y);
  const f = p.facing;
  const speed = Math.hypot(p.vx, p.vy);
  // Cape qui flotte à l'opposé du mouvement.
  const capeLen = pr * (1.1 + Math.min(1, speed / 400) * 0.8);
  ctx.fillStyle = PAL.heroCape;
  ctx.beginPath();
  ctx.moveTo(Math.cos(f + 1.9) * pr * 0.9, Math.sin(f + 1.9) * pr * 0.9);
  ctx.quadraticCurveTo(Math.cos(f + Math.PI) * capeLen * 1.3 + Math.sin(time * 12) * 3, Math.sin(f + Math.PI) * capeLen * 1.3, Math.cos(f - 1.9) * pr * 0.9, Math.sin(f - 1.9) * pr * 0.9);
  ctx.closePath();
  ctx.fill();
  // Étirement (dash, frappe) et écrasement (sortie de dash), aire conservée.
  let sx = 1;
  let axis = f;
  if (p.state === 'dash') sx = 1.35;
  else if (fx.landT > 0) {
    sx = 0.82;
    axis = Math.atan2(p.dashDirY, p.dashDirX);
  } else if (fx.swingT > 0) {
    sx = 1.18;
    axis = fx.swingAngle;
  }
  if (sx !== 1) {
    ctx.rotate(axis);
    ctx.scale(sx, 1 / sx);
    ctx.rotate(-axis);
  }
  ctx.fillStyle = p.hurtFlash > 0 ? PAL.heroHurt : PAL.hero;
  ctx.strokeStyle = PAL.heroCape; // liseré propre au héros : on ne le confond avec aucun ennemi flashé
  ctx.lineWidth = 3.5;
  ctx.beginPath();
  ctx.arc(0, 0, pr, 0, TAU);
  ctx.fill();
  ctx.stroke();
  // Visière orientée.
  ctx.fillStyle = '#0d2a36';
  ctx.beginPath();
  ctx.arc(Math.cos(f) * pr * 0.35, Math.sin(f) * pr * 0.35, pr * 0.42, f - 1.2, f + 1.2);
  ctx.closePath();
  ctx.fill();
  drawBlade(ctx, p, pr);
  ctx.restore();
  ctx.globalAlpha = 1;
}

function drawBlade(ctx, p, pr) {
  let a = p.facing + 0.9;
  if (p.state === 'attack' && p.attack) {
    const at = p.attack;
    const half = (at.def.arc * Math.PI) / 360;
    const dir = at.index === 1 ? -1 : 1;
    let k = 0;
    if (at.phase === 'active') k = Math.min(1, at.t / at.dur.active);
    else if (at.phase === 'recovery') k = 1;
    a = at.angle - half * dir + at.def.arc * (Math.PI / 180) * dir * k;
  }
  ctx.strokeStyle = '#cfe9f5';
  ctx.lineWidth = 4;
  ctx.lineCap = 'round';
  ctx.beginPath();
  ctx.moveTo(Math.cos(a) * pr * 0.8, Math.sin(a) * pr * 0.8);
  ctx.lineTo(Math.cos(a) * pr * 2.3, Math.sin(a) * pr * 2.3);
  ctx.stroke();
}

function drawProjectiles(ctx, game) {
  for (const pr of game.projectiles) {
    if (pr.dead) continue;
    const a = Math.atan2(pr.vy, pr.vx);
    if (pr.owner === 'player') {
      drawGlow(ctx, pr.x, pr.y, 34, PAL.lance, 0.6);
      ctx.save();
      ctx.translate(pr.x, pr.y);
      ctx.rotate(a);
      ctx.fillStyle = PAL.lance;
      ctx.beginPath();
      ctx.moveTo(18, 0);
      ctx.lineTo(-30, -5);
      ctx.lineTo(-30, 5);
      ctx.closePath();
      ctx.fill();
      ctx.restore();
    } else if (pr.kind === 'bossOrb') {
      const vr = pr.r * ENEMY_SHOT_VISUAL;
      drawGlow(ctx, pr.x, pr.y, vr * 3, PAL.bossOrb, 0.55);
      ctx.fillStyle = PAL.bossOrb;
      ctx.strokeStyle = '#2a0018';
      ctx.lineWidth = 3;
      ctx.beginPath();
      ctx.arc(pr.x, pr.y, vr, 0, TAU);
      ctx.fill();
      ctx.stroke();
      // Cœur blanc : un projectile ennemi se lit sur n'importe quel fond.
      ctx.fillStyle = '#ffffff';
      ctx.beginPath();
      ctx.arc(pr.x, pr.y, vr * 0.45, 0, TAU);
      ctx.fill();
    } else {
      ctx.save();
      ctx.translate(pr.x, pr.y);
      ctx.rotate(a);
      ctx.scale(ENEMY_SHOT_VISUAL, ENEMY_SHOT_VISUAL);
      ctx.strokeStyle = PAL.enemyOutline;
      ctx.lineWidth = 6;
      ctx.beginPath();
      ctx.moveTo(-16, 0);
      ctx.lineTo(10, 0);
      ctx.stroke();
      ctx.strokeStyle = PAL.arrow;
      ctx.lineWidth = 3;
      ctx.stroke();
      ctx.strokeStyle = '#fff4e0';
      ctx.lineWidth = 1.2;
      ctx.stroke();
      ctx.fillStyle = PAL.arrow;
      ctx.beginPath();
      ctx.moveTo(14, 0);
      ctx.lineTo(6, -5);
      ctx.lineTo(6, 5);
      ctx.closePath();
      ctx.fill();
      ctx.restore();
      drawGlow(ctx, pr.x, pr.y, 18, PAL.arrow, 0.5);
    }
  }
}

/** Visée tactile : ligne d'aperçu pendant un glisser (attaque ou compétence) + réticule auto. */
function drawAimHints(ctx, game, touch) {
  const p = game.player;
  if (!touch?.visible || p.state === 'dead') return;
  for (const b of touch.buttons) {
    if (b.pointer === null || !b.dragging) continue;
    const l = Math.hypot(b.dx, b.dy) || 1;
    const ax = b.dx / l;
    const ay = b.dy / l;
    const len = b.id === 'skill' ? game.tuning.skill.range : game.tuning.combo[0].range + 30;
    ctx.strokeStyle = b.id === 'skill' ? PAL.lance : '#ffffff';
    ctx.globalAlpha = 0.55;
    ctx.lineWidth = b.id === 'skill' ? 10 : 6;
    ctx.beginPath();
    ctx.moveTo(p.x + ax * 20, p.y + ay * 20);
    ctx.lineTo(p.x + ax * len, p.y + ay * len);
    ctx.stroke();
    ctx.globalAlpha = 1;
  }
  // Réticule sur la cible de la visée assistée (ce qu'un tap frapperait).
  const aim = computeAim(game, 0, 0);
  if (aim.targetId) {
    const e = game.enemies.find((o) => o.id === aim.targetId);
    if (e) {
      ctx.strokeStyle = 'rgba(255,255,255,0.55)';
      ctx.lineWidth = 2;
      ctx.beginPath();
      ctx.arc(e.x, e.y, e.r + 6, 0, TAU);
      ctx.stroke();
    }
  }
}

/** Dessine toute la salle. ctx est déjà transformé par la caméra. */
export function drawWorld(ctx, game, fx, time, touch) {
  drawRoom(ctx, game, time);
  drawPlayerUnderlay(ctx, game, fx, time);
  drawSpawnWarns(ctx, game, time);
  drawTelegraphs(ctx, game);
  drawEffects(ctx, fx, game, true);
  drawPickups(ctx, game, time);
  drawInteract(ctx, game, time);
  drawAimHints(ctx, game, touch);
  const sorted = game.enemies.slice().sort((a, b) => a.y - b.y);
  for (const e of sorted) if (!e.dead) drawEnemy(ctx, e, game, time);
  drawPlayer(ctx, game, fx, time);
  drawTelegraphEdges(ctx, game);
  drawProjectiles(ctx, game);
  drawEffects(ctx, fx, game, false);
  drawParticles(ctx);
  drawTexts(ctx, fx);
}

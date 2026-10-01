// HUD en espace écran (px CSS) : PV, progression de la descente, or, bénédictions, barre
// du boss, contrôles tactiles (avec recharges et charges), barre d'aptitudes au clavier,
// bannières, vignette de danger, indicateurs hors champ.

import { PAL } from './palette.mjs';
import { worldToScreen } from './camera.mjs';
import { FAMILIES, boonDef } from '../sim/boons.mjs';
import { maxDashCharges } from '../sim/player.mjs';

const TAU = Math.PI * 2;
const FONT = 'system-ui, -apple-system, "Segoe UI", sans-serif';
const EDGE = 14;
const GHOST_HOLD = 0.35; // s pendant lesquelles la vie perdue reste visible (segment blanc)
const GHOST_DRAIN = 1.2; // fraction de PV max vidée par seconde ensuite
const tmp = { x: 0, y: 0 };
const ghost = { hp: -1, hold: 0, last: -1 };

function updateGhost(p, dt) {
  if (ghost.hp < 0 || p.hp >= ghost.hp) {
    ghost.hp = p.hp;
    ghost.hold = 0;
    ghost.last = p.hp;
    return;
  }
  // Nouvelle perte de PV : le segment blanc reste visible un instant, puis se vide.
  if (p.hp < ghost.last) ghost.hold = GHOST_HOLD;
  ghost.last = p.hp;
  if (ghost.hold > 0) {
    ghost.hold -= dt;
    return;
  }
  ghost.hp = Math.max(p.hp, ghost.hp - GHOST_DRAIN * p.maxHp * dt);
}

function text(ctx, str, x, y, size, color, align = 'left', weight = 700) {
  ctx.font = `${weight} ${size}px ${FONT}`;
  ctx.textAlign = align;
  ctx.textBaseline = 'middle';
  ctx.lineWidth = Math.max(2, size / 5);
  ctx.strokeStyle = 'rgba(8, 3, 6, 0.85)';
  ctx.strokeText(str, x, y);
  ctx.fillStyle = color;
  ctx.fillText(str, x, y);
}

function bar(ctx, x, y, w, h, frac, color, back = PAL.hpBack) {
  ctx.fillStyle = back;
  ctx.fillRect(x, y, w, h);
  ctx.fillStyle = color;
  ctx.fillRect(x, y, w * Math.max(0, Math.min(1, frac)), h);
  ctx.strokeStyle = 'rgba(0,0,0,0.7)';
  ctx.lineWidth = 2;
  ctx.strokeRect(x, y, w, h);
}

function drawTopLeft(ctx, game, safe, screenW) {
  const p = game.player;
  const x = EDGE + safe.left;
  const y = EDGE + safe.top;
  // Écran étroit (portrait) : la barre rétrécit pour ne pas chevaucher le titre central.
  const w = Math.min(190, Math.max(90, screenW * 0.26));
  bar(ctx, x, y, w, 16, ghost.hp / p.maxHp, '#fff4ea');
  ctx.fillStyle = p.hp / p.maxHp < 0.3 ? '#ff2a2a' : PAL.hpBar;
  ctx.fillRect(x, y, w * Math.max(0, p.hp / p.maxHp), 16);
  ctx.strokeStyle = 'rgba(0,0,0,0.7)';
  ctx.lineWidth = 2;
  ctx.strokeRect(x, y, w, 16);
  text(ctx, `${Math.ceil(p.hp)} / ${p.maxHp}`, x + w / 2, y + 8.5, 11, PAL.text, 'center', 800);
  // Bénédictions acquises : losanges de la couleur du péché.
  let bx = x;
  for (const b of game.run.boons) {
    const def = boonDef(b.id);
    const color = def?.family ? FAMILIES[def.family].color : '#ffffff';
    ctx.save();
    ctx.translate(bx + 7, y + 30);
    ctx.rotate(Math.PI / 4);
    ctx.fillStyle = color;
    ctx.fillRect(-5, -5, 10, 10);
    ctx.restore();
    bx += 16;
  }
}

function drawTopCenter(ctx, game, w, safe) {
  const info = game.info;
  const cx = w / 2;
  const y = EDGE + safe.top + 6;
  if (game.sandbox) {
    text(ctx, 'ARÈNE D\'ESSAI', cx, y, 15, PAL.text, 'center', 800);
    text(ctx, `${game.telemetry.kills} démons · ${game.telemetry.dodges} esquives parfaites`, cx, y + 20, 11, PAL.textDim, 'center', 600);
    return;
  }
  text(ctx, `ÉTAGE ${info.floor} / 666`, cx, y, 15, info.isBoss ? PAL.danger : PAL.text, 'center', 800);
  const boss = game.enemies.find((e) => e.boss && !e.dead);
  if (boss) {
    // Combat de Gardien : bande haute réduite (titre + barre portant le nom), l'arène reste visible.
    const bw = Math.min(420, w * 0.5);
    bar(ctx, cx - bw / 2, y + 14, bw, 14, boss.hp / boss.maxHp, boss.phase === 1 ? '#c0304a' : '#ff4a1a');
    text(ctx, game.tuning.boss[boss.kind].name, cx, y + 21, 10, PAL.bossTrim, 'center', 800);
    return;
  }
  // Six pastilles = la section ; la dernière est le Gardien.
  const n = game.tuning.floors.sectionLength;
  const step = 16;
  const x0 = cx - ((n - 1) * step) / 2;
  for (let i = 1; i <= n; i++) {
    const px = x0 + (i - 1) * step;
    const done = i < info.indexInSection;
    const cur = i === info.indexInSection;
    ctx.fillStyle = i === n ? (done || cur ? PAL.danger : '#5a1a22') : done ? PAL.text : cur ? PAL.gold : '#3a2a30';
    ctx.beginPath();
    ctx.arc(px, y + 18, i === n ? 5 : 3.5, 0, TAU);
    ctx.fill();
  }
  text(ctx, info.circleName, cx, y + 33, 11, PAL.textDim, 'center', 600);
}

function drawTopRight(ctx, game, w, safe) {
  const x = w - EDGE - safe.right - 52;
  const y = EDGE + safe.top + 8;
  text(ctx, `${game.run.gold}`, x - 8, y, 15, PAL.gold, 'right', 800);
  ctx.save();
  ctx.translate(x + 2, y);
  ctx.rotate(Math.PI / 4);
  ctx.fillStyle = PAL.gold;
  ctx.fillRect(-5, -5, 10, 10);
  ctx.restore();
  // Bouton pause (zone gérée par main).
  ctx.fillStyle = 'rgba(255,255,255,0.12)';
  ctx.beginPath();
  ctx.arc(w - EDGE - safe.right - 18, y + 4, 17, 0, TAU);
  ctx.fill();
  ctx.fillStyle = PAL.text;
  ctx.fillRect(w - EDGE - safe.right - 24, y - 3, 4, 14);
  ctx.fillRect(w - EDGE - safe.right - 16, y - 3, 4, 14);
}

/** Zone du bouton pause, en px CSS (pour main). */
export function pauseButtonRect(w, safe) {
  const x = w - EDGE - safe.right - 18;
  const y = EDGE + safe.top + 12;
  return { x, y, r: 26 };
}

// ------------------------------------------------------------------ contrôles tactiles

const ICONS = {
  attack(ctx, r) {
    ctx.rotate(-Math.PI / 4);
    ctx.fillRect(-r * 0.09, -r * 0.55, r * 0.18, r * 0.8);
    ctx.fillRect(-r * 0.3, r * 0.22, r * 0.6, r * 0.1);
    ctx.fillRect(-r * 0.07, r * 0.3, r * 0.14, r * 0.22);
  },
  dash(ctx, r) {
    for (const o of [-0.22, 0.12]) {
      ctx.beginPath();
      ctx.moveTo(r * (o - 0.1), -r * 0.35);
      ctx.lineTo(r * (o + 0.22), 0);
      ctx.lineTo(r * (o - 0.1), r * 0.35);
      ctx.lineTo(r * (o - 0.0), 0);
      ctx.closePath();
      ctx.fill();
    }
  },
  skill(ctx, r) {
    ctx.rotate(-Math.PI / 4);
    ctx.fillRect(-r * 0.05, -r * 0.5, r * 0.1, r * 1.0);
    ctx.beginPath();
    ctx.moveTo(0, -r * 0.62);
    ctx.lineTo(r * 0.16, -r * 0.38);
    ctx.lineTo(-r * 0.16, -r * 0.38);
    ctx.closePath();
    ctx.fill();
  },
  gadget(ctx, r) {
    for (let i = 0; i < 8; i++) {
      const a = (i / 8) * TAU;
      ctx.fillRect(Math.cos(a) * r * 0.3 - 2, Math.sin(a) * r * 0.3 - 2, 4, 4);
    }
    ctx.beginPath();
    ctx.arc(0, 0, r * 0.18, 0, TAU);
    ctx.fill();
  },
  super(ctx, r) {
    ctx.beginPath();
    ctx.moveTo(0, -r * 0.5);
    ctx.quadraticCurveTo(r * 0.45, -r * 0.05, r * 0.2, r * 0.45);
    ctx.quadraticCurveTo(0, r * 0.2, -r * 0.2, r * 0.45);
    ctx.quadraticCurveTo(-r * 0.45, -r * 0.05, 0, -r * 0.5);
    ctx.fill();
  },
};

/** État d'un bouton d'aptitude, lu dans la simulation. ready ∈ [0, 1]. */
function abilityState(game, id) {
  const p = game.player;
  const t = game.tuning;
  switch (id) {
    case 'dash': {
      const max = maxDashCharges(game);
      const need = t.dash.recharge * p.stats.dashRechargeMult;
      return { ready: p.dashCharges > 0 ? 1 : p.dashRecharge / need, charges: p.dashCharges, max, partial: p.dashCharges < max ? p.dashRecharge / need : 0 };
    }
    case 'skill': {
      const cd = t.skill.cooldown * p.stats.skillCooldownMult;
      return { ready: 1 - p.skillCd / cd };
    }
    case 'gadget':
      return { ready: p.gadgetCharges > 0 ? 1 : 0, charges: p.gadgetCharges, max: t.gadget.chargesPerSection + p.stats.gadgetChargesBonus };
    case 'super':
      return { ready: p.superCharge, glow: p.superCharge >= 1 };
    default:
      return { ready: 1 };
  }
}

function drawButton(ctx, b, st, time) {
  const pressed = b.pointer !== null;
  const ready = st.ready >= 1;
  ctx.save();
  ctx.translate(b.x, b.y);
  if (st.glow) {
    ctx.fillStyle = 'rgba(255, 176, 46, 0.35)';
    ctx.beginPath();
    ctx.arc(0, 0, b.r + 8 + 3 * Math.sin(time * 8), 0, TAU);
    ctx.fill();
  }
  ctx.fillStyle = pressed ? 'rgba(255,255,255,0.32)' : 'rgba(20, 10, 16, 0.55)';
  ctx.strokeStyle = ready ? 'rgba(255,255,255,0.75)' : 'rgba(255,255,255,0.25)';
  ctx.lineWidth = 2.5;
  ctx.beginPath();
  ctx.arc(0, 0, b.r * (pressed ? 0.94 : 1), 0, TAU);
  ctx.fill();
  ctx.stroke();
  // Recharge : secteur sombre qui se vide dans le sens horaire.
  if (st.ready < 1) {
    ctx.fillStyle = 'rgba(0,0,0,0.55)';
    ctx.beginPath();
    ctx.moveTo(0, 0);
    ctx.arc(0, 0, b.r, -Math.PI / 2 + TAU * st.ready, -Math.PI / 2 + TAU);
    ctx.closePath();
    ctx.fill();
  }
  ctx.fillStyle = ready ? (b.id === 'super' ? PAL.superBar : PAL.text) : 'rgba(243,233,228,0.4)';
  ctx.save();
  ICONS[b.id](ctx, b.r);
  ctx.restore();
  if (b.id === 'super') {
    ctx.strokeStyle = PAL.superBar;
    ctx.lineWidth = 4;
    ctx.beginPath();
    ctx.arc(0, 0, b.r + 4, -Math.PI / 2, -Math.PI / 2 + TAU * st.ready);
    ctx.stroke();
  }
  if (st.max) drawChargeRing(ctx, b.r, st.charges, st.max, st.partial ?? 0, b.id === 'dash' ? PAL.dashPip : PAL.gold);
  ctx.restore();
}

const RING_GAP = 0.14; // rad entre deux segments de charge
const RING_WIDTH = 4;

/**
 * Charges en segments sur l'anneau du bouton (comme la jauge du Super) : rien ne dépasse du
 * bouton, donc aucun bouton voisin ne peut cacher la charge qui se recharge.
 */
function drawChargeRing(ctx, r, charges, max, partial, color) {
  const seg = TAU / max;
  const rr = r + RING_WIDTH;
  const gap = max > 1 ? RING_GAP : 0;
  ctx.lineWidth = RING_WIDTH;
  for (let i = 0; i < max; i++) {
    const a0 = -Math.PI / 2 + i * seg + gap / 2;
    const a1 = a0 + seg - gap;
    ctx.strokeStyle = i < charges ? color : 'rgba(255,255,255,0.18)';
    ctx.beginPath();
    ctx.arc(0, 0, rr, a0, a1);
    ctx.stroke();
    if (i === charges && partial > 0) {
      ctx.strokeStyle = color;
      ctx.globalAlpha = 0.55;
      ctx.beginPath();
      ctx.arc(0, 0, rr, a0, a0 + (a1 - a0) * Math.min(1, partial));
      ctx.stroke();
      ctx.globalAlpha = 1;
    }
  }
}

function drawTouchControls(ctx, game, touch, time) {
  const s = touch.stick;
  if (s.id !== null) {
    ctx.fillStyle = 'rgba(255,255,255,0.08)';
    ctx.strokeStyle = 'rgba(255,255,255,0.3)';
    ctx.lineWidth = 2;
    // Dessin recalé loin des bords ; le bouton garde l'écart réel doigt/origine.
    const bx = s.drawX ?? s.baseX;
    const by = s.drawY ?? s.baseY;
    ctx.beginPath();
    ctx.arc(bx, by, 58, 0, TAU);
    ctx.fill();
    ctx.stroke();
    ctx.fillStyle = 'rgba(255,255,255,0.45)';
    ctx.beginPath();
    ctx.arc(bx + (s.knobX - s.baseX), by + (s.knobY - s.baseY), 26, 0, TAU);
    ctx.fill();
  }
  for (const b of touch.buttons) drawButton(ctx, b, abilityState(game, b.id), time);
}

function drawAbilityBar(ctx, game, w, h, safe, time) {
  // Clavier/souris : barre compacte en bas au centre, avec les touches.
  const items = [
    { id: 'dash', key: 'Espace' },
    { id: 'skill', key: 'Clic D' },
    { id: 'gadget', key: 'E' },
    { id: 'super', key: 'F' },
  ];
  const r = 22;
  const gap = 66;
  const x0 = w / 2 - ((items.length - 1) * gap) / 2;
  const y = h - EDGE - safe.bottom - r - 14;
  items.forEach((it, i) => {
    const b = { id: it.id, x: x0 + i * gap, y, r, pointer: null };
    drawButton(ctx, b, abilityState(game, it.id), time);
    text(ctx, it.key, b.x, y + r + 12, 10, PAL.textDim, 'center', 600);
  });
}

// ------------------------------------------------------------------ indicateurs et bannières

const ARROW_MARGIN = 26; // px des bords de la zone utile
const HUD_BAND = 60; // px : hauteur de la bande haute du HUD (hors combat de Gardien)
const HUD_BAND_BOSS = 52;

function drawOffscreen(ctx, game, cam, touch, w, h, safe) {
  const boss = game.enemies.some((e) => e.boss && !e.dead);
  const top = EDGE + safe.top + (boss ? HUD_BAND_BOSS : HUD_BAND);
  // Coin du groupe de boutons : une flèche n'y est jamais posée.
  let gx = w;
  let gy = h;
  if (touch.visible) {
    for (const b of touch.buttons) {
      gx = Math.min(gx, b.x - b.r);
      gy = Math.min(gy, b.y - b.r);
    }
  }
  const point = (x, y, color, size) => {
    worldToScreen(cam, w, h, x, y, tmp);
    if (tmp.x > 0 && tmp.x < w && tmp.y > top && tmp.y < h) return;
    const cx = w / 2;
    const cy = h / 2;
    const a = Math.atan2(tmp.y - cy, tmp.x - cx);
    const ey = Math.max(top + 10, Math.min(h - ARROW_MARGIN - safe.bottom, tmp.y));
    const right = ey > gy - ARROW_MARGIN ? gx - 14 : w - ARROW_MARGIN - safe.right;
    const ex = Math.max(ARROW_MARGIN + safe.left, Math.min(right, tmp.x));
    ctx.save();
    ctx.translate(ex, ey);
    ctx.rotate(a);
    ctx.fillStyle = color;
    ctx.beginPath();
    ctx.moveTo(size, 0);
    ctx.lineTo(-size * 0.6, -size * 0.7);
    ctx.lineTo(-size * 0.6, size * 0.7);
    ctx.closePath();
    ctx.fill();
    ctx.restore();
  };
  for (const e of game.enemies) if (!e.dead) point(e.x, e.y, e.boss ? PAL.bossTrim : 'rgba(255,70,60,0.85)', e.boss || e.eliteMod ? 11 : 8);
  const it = game.room.interact;
  if (it && !it.used) point(it.x, it.y, PAL.gold, 11);
}

/** Ennemis cachés sous le groupe de boutons : marqueur au-dessus du groupe (pouce). */
function drawOccluded(ctx, game, cam, touch, w, h) {
  if (!touch.visible) return;
  let x0 = Infinity;
  let y0 = Infinity;
  for (const b of touch.buttons) {
    x0 = Math.min(x0, b.x - b.r - 24);
    y0 = Math.min(y0, b.y - b.r - 24);
  }
  for (const e of game.enemies) {
    if (e.dead) continue;
    worldToScreen(cam, w, h, e.x, e.y, tmp);
    if (tmp.x < x0 || tmp.y < y0 || tmp.x > w || tmp.y > h) continue;
    const danger = e.state === 'windup' || e.tele;
    ctx.fillStyle = danger ? '#ff3b3b' : 'rgba(255, 90, 70, 0.75)';
    ctx.beginPath();
    ctx.moveTo(tmp.x, y0 - 2);
    ctx.lineTo(tmp.x - 7, y0 - 14);
    ctx.lineTo(tmp.x + 7, y0 - 14);
    ctx.closePath();
    ctx.fill();
  }
}

const BANNER_ALPHA = 0.75;
const BANNER_Y = 92; // px sous le bord haut sûr : juste sous la bande du HUD, au-dessus de l'action

function drawBanner(ctx, fx, w, safe) {
  const b = fx.banner;
  if (!b) return;
  const t = 1 - b.life / b.max;
  const a = t < 0.15 ? t / 0.15 : b.life < 0.4 ? b.life / 0.4 : 1;
  const y = EDGE + safe.top + BANNER_Y;
  ctx.globalAlpha = a * BANNER_ALPHA;
  text(ctx, b.title, w / 2, y, Math.min(26, w / 16), b.color, 'center', 900);
  if (b.sub) text(ctx, b.sub, w / 2, y + 22, 12, PAL.textDim, 'center', 600);
  ctx.globalAlpha = 1;
}

// Calques pré-rendus (vignette rouge, bande haute) : recréés seulement au redimensionnement,
// jamais un dégradé plein écran par image (téléphones modestes, moments tendus).
const layers = { key: '', vignette: null, top: null };

function layerCanvas(w, h) {
  const c = typeof OffscreenCanvas !== 'undefined' ? new OffscreenCanvas(Math.max(1, w), Math.max(1, h)) : Object.assign(document.createElement('canvas'), { width: w, height: h });
  return c;
}

function ensureLayers(w, h, safeTop) {
  const key = `${w}x${h}:${safeTop}`;
  if (layers.key === key) return;
  layers.key = key;
  const v = layerCanvas(w, h);
  const vg = v.getContext('2d');
  const g = vg.createRadialGradient(w / 2, h / 2, Math.max(w, h) * 0.38, w / 2, h / 2, Math.max(w, h) * 0.62);
  g.addColorStop(0, 'rgba(255,0,0,0)');
  g.addColorStop(1, 'rgba(200,0,0,1)');
  vg.fillStyle = g;
  vg.fillRect(0, 0, w, h);
  layers.vignette = v;
  const th = Math.round(90 + safeTop);
  const t = layerCanvas(w, th);
  const tg = t.getContext('2d');
  const lg = tg.createLinearGradient(0, 0, 0, th);
  lg.addColorStop(0, 'rgba(5, 2, 4, 0.55)');
  lg.addColorStop(1, 'rgba(5, 2, 4, 0)');
  tg.fillStyle = lg;
  tg.fillRect(0, 0, w, th);
  layers.top = t;
}

function drawVignettes(ctx, game, fx, w, h, time) {
  const p = game.player;
  const low = p.hp / p.maxHp < 0.3 && p.state !== 'dead';
  const intensity = Math.max(fx.hurtFlash * 0.45, low ? 0.22 + 0.1 * Math.sin(time * 5) : 0);
  if (intensity > 0.01) {
    ctx.globalAlpha = Math.min(1, intensity);
    ctx.drawImage(layers.vignette, 0, 0, w, h);
    ctx.globalAlpha = 1;
  }
  if (fx.flash > 0) {
    ctx.fillStyle = `rgba(255, 240, 220, ${fx.flash * 0.25})`;
    ctx.fillRect(0, 0, w, h);
  }
}

function drawHints(ctx, game, w, h, safe, usingTouch) {
  const room = game.room;
  if (room.cleared && room.doors.some((d) => d.open) && !(room.interact && !room.interact.used)) {
    text(ctx, 'Choisissez une porte ↑', w / 2, h - EDGE - safe.bottom - (usingTouch ? 30 : 92), 14, PAL.text, 'center', 700);
  }
}

/** Dessine tout le HUD (calques de vignette et de bande haute pré-rendus). */
export function drawHud(ctx, game, fx, cam, touch, view, time, dt = 1 / 60) {
  const { w, h, safe } = view;
  updateGhost(game.player, dt);
  ensureLayers(w, h, safe.top);
  // Dégradé sombre derrière la bande haute du HUD : le texte reste lisible sur tout fond.
  ctx.drawImage(layers.top, 0, 0);
  drawVignettes(ctx, game, fx, w, h, time);
  drawOccluded(ctx, game, cam, touch, w, h);
  drawTopLeft(ctx, game, safe, w);
  drawTopCenter(ctx, game, w, safe);
  drawTopRight(ctx, game, w, safe);
  drawOffscreen(ctx, game, cam, touch, w, h, safe);
  if (game.mode !== 'choice') drawBanner(ctx, fx, w, safe);
  drawHints(ctx, game, w, h, safe, touch.visible);
  if (touch.visible) drawTouchControls(ctx, game, touch, time);
  else drawAbilityBar(ctx, game, w, h, safe, time);
}

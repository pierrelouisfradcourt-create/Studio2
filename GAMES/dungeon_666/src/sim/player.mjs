// Le héros : machine à états (free | attack | dash | cast | super | dead), tampon d'input,
// annulations (cancels). Règle de feel n°1 : le DASH annule presque tout, tout de suite.
//
// InputFrame attendu (produit par src/input, ou par un bot) :
//   { moveX, moveY,            // [-1, 1], norme <= 1 (analogique)
//     aimX, aimY,              // visée manuelle (0, 0 = visée assistée)
//     attack,                  // maintenu : enchaîne le combo
//     attackPressed, dashPressed, skillPressed, gadgetPressed, superPressed,  // fronts
//     skillAimX, skillAimY }   // visée de la compétence au relâcher (0, 0 = assistée)

import { DEG } from './config.mjs';
import { inSector, dist2 } from '../core/math.mjs';
import { emit } from './state.mjs';
import { computeAim } from './aim.mjs';
import { moveCircle } from './physics.mjs';
import { damageEnemy } from './combat.mjs';
import { spawnProjectile, destroyEnemyProjectilesInCircle } from './projectiles.mjs';

const PRIORITY = ['dash', 'super', 'skill', 'attack'];
const DASH_CHAIN_FRACTION = 0.35; // on peut re-dasher quand il reste moins de 35 % du dash

export function maxDashCharges(game) {
  return game.tuning.dash.charges + game.player.stats.dashChargesBonus;
}

function bufferAction(p, action, t, aimX = 0, aimY = 0) {
  const cur = p.buffer.action;
  // Un dash en attente n'est jamais écrasé par une action moins prioritaire.
  if (cur && p.buffer.t > 0 && PRIORITY.indexOf(cur) < PRIORITY.indexOf(action)) return;
  p.buffer.action = action;
  p.buffer.t = t;
  p.buffer.aimX = aimX;
  p.buffer.aimY = aimY;
}

/** Vrai si un dash peut partir maintenant (utilisé aussi pour annuler le gel d'impact). */
export function canDash(game) {
  const p = game.player;
  if (p.dashCharges < 1) return false;
  if (p.state === 'free' || p.state === 'attack' || p.state === 'cast') return true;
  if (p.state === 'dash') return p.dashT <= game.tuning.dash.duration * DASH_CHAIN_FRACTION;
  return false;
}

function canAttack(game) {
  const p = game.player;
  if (p.state === 'free') return true;
  // Frappe de dash : attaquer en fin de dash coupe la ruée et frappe tout de suite.
  if (p.state === 'dash') return p.dashT <= game.tuning.dash.duration * game.tuning.dash.strikeCancelFrom;
  return p.state === 'attack' && p.attack.phase === 'recovery';
}

function canSkill(p) {
  if (p.skillCd > 0) return false;
  if (p.state === 'free') return true;
  return p.state === 'attack' && p.attack.phase === 'recovery';
}

function canSuper(p) {
  return p.superCharge >= 1 && (p.state === 'free' || p.state === 'attack' || p.state === 'cast' || p.state === 'dash');
}

/** Lit les fronts de l'InputFrame et les met en tampon. Rend true si dash est en attente. */
export function readInput(game, input) {
  const p = game.player;
  const t = game.tuning;
  const buf = t.player.inputBuffer;
  let mx = input.moveX || 0;
  let my = input.moveY || 0;
  const ml = Math.sqrt(mx * mx + my * my);
  if (ml > 1) {
    mx /= ml;
    my /= ml;
  }
  p.moveX = mx;
  p.moveY = my;
  p.manualAimX = input.aimX || 0;
  p.manualAimY = input.aimY || 0;
  p.attackHeld = !!input.attack;
  if (input.attackPressed) bufferAction(p, 'attack', buf);
  if (input.skillPressed) bufferAction(p, 'skill', buf, input.skillAimX || 0, input.skillAimY || 0);
  if (input.superPressed) bufferAction(p, 'super', buf);
  if (input.dashPressed) bufferAction(p, 'dash', buf);
  if (input.gadgetPressed) useGadget(game);
  return p.buffer.action === 'dash' && p.buffer.t > 0;
}

export function updatePlayer(game, dt) {
  const p = game.player;
  const t = game.tuning;
  p.stateTime += dt;
  if (p.state === 'dead') {
    p.vx *= 0.85;
    p.vy *= 0.85;
    return;
  }
  tickTimers(game, dt);
  if (p.buffer.t > 0) {
    tryBuffered(game);
    p.buffer.t -= dt;
    if (p.buffer.t <= 0) p.buffer.action = null;
  }
  // Attaque maintenue : enchaîne le combo sans re-taper (confort mobile).
  if (p.attackHeld && !p.buffer.action && canAttack(game) && p.state !== 'dash') startAttack(game);

  switch (p.state) {
    case 'free':
      locomotion(game, dt, t.player.speed * p.stats.moveSpeedMult);
      if (Math.abs(p.manualAimX) + Math.abs(p.manualAimY) > 0.15) p.facing = Math.atan2(p.manualAimY, p.manualAimX);
      else if (p.moveX * p.moveX + p.moveY * p.moveY > 0.04) p.facing = Math.atan2(p.moveY, p.moveX);
      break;
    case 'attack':
      updateAttack(game, dt);
      break;
    case 'dash':
      updateDash(game, dt);
      break;
    case 'cast':
      updateCast(game, dt);
      break;
    case 'super':
      updateSuper(game, dt);
      break;
    default:
      break;
  }
  moveCircle(game.room, p, p.vx * dt, p.vy * dt);
}

function tickTimers(game, dt) {
  const p = game.player;
  const t = game.tuning;
  p.iframes = Math.max(0, p.iframes - dt);
  p.dodgeIframes = Math.max(0, p.dodgeIframes - dt);
  p.hurtFlash = Math.max(0, p.hurtFlash - dt);
  p.skillCd = Math.max(0, p.skillCd - dt);
  p.strikeWindow = Math.max(0, p.strikeWindow - dt);
  if (p.state !== 'attack') p.comboTimer += dt;
  const maxC = maxDashCharges(game);
  if (p.dashCharges < maxC) {
    p.dashRecharge += dt;
    const need = t.dash.recharge * p.stats.dashRechargeMult;
    if (p.dashRecharge >= need) {
      p.dashRecharge -= need;
      p.dashCharges++;
      emit(game, 'dashReady', { charges: p.dashCharges });
    }
  } else {
    p.dashRecharge = 0;
  }
}

function tryBuffered(game) {
  const p = game.player;
  switch (p.buffer.action) {
    case 'dash':
      if (canDash(game)) {
        p.buffer.action = null;
        startDash(game);
      }
      break;
    case 'super':
      if (canSuper(p)) {
        p.buffer.action = null;
        startSuper(game);
      }
      break;
    case 'skill':
      if (canSkill(p)) {
        const ax = p.buffer.aimX;
        const ay = p.buffer.aimY;
        p.buffer.action = null;
        startCast(game, ax, ay);
      }
      break;
    case 'attack':
      if (canAttack(game)) {
        p.buffer.action = null;
        startAttack(game);
      }
      break;
    default:
      break;
  }
}

function locomotion(game, dt, speed) {
  const p = game.player;
  const t = game.tuning.player;
  const tx = p.moveX * speed;
  const ty = p.moveY * speed;
  const accelerating = p.moveX * p.moveX + p.moveY * p.moveY > 0.0001;
  const rate = (accelerating ? speed / t.accelTime : speed / t.decelTime) * dt;
  const dx = tx - p.vx;
  const dy = ty - p.vy;
  const d = Math.sqrt(dx * dx + dy * dy);
  if (d <= rate) {
    p.vx = tx;
    p.vy = ty;
  } else {
    p.vx += (dx / d) * rate;
    p.vy += (dy / d) * rate;
  }
}

// ---------------------------------------------------------------- attaque (combo / frappe de dash)

function phaseDurations(def, speedMult) {
  return { startup: def.startup / speedMult, active: def.active / speedMult, recovery: def.recovery / speedMult };
}

function startAttack(game) {
  const p = game.player;
  const t = game.tuning;
  const strike = p.strikeWindow > 0 || p.state === 'dash';
  if (p.state === 'dash') emit(game, 'cancel', { from: 'dash' });
  let index = 0;
  if (!strike) {
    if (p.state === 'attack') index = (p.attack.index + 1) % t.combo.length;
    else if (p.comboTimer <= t.comboResetTime) index = p.comboIndex;
  }
  const def = strike ? t.dashStrike : t.combo[index];
  const aim = computeAim(game, p.manualAimX, p.manualAimY);
  p.attack = {
    def,
    index,
    strike,
    phase: 'startup',
    t: 0,
    dur: phaseDurations(def, p.stats.attackSpeedMult),
    dirX: aim.x,
    dirY: aim.y,
    angle: Math.atan2(aim.y, aim.x),
    targetId: aim.targetId,
    targetDist: aim.targetDist,
    hitIds: [],
    swingId: ++p.swingSeq,
    lungeV: 0,
  };
  p.strikeWindow = 0;
  p.facing = p.attack.angle;
  if (aim.targetId) {
    p.lastTargetId = aim.targetId;
    p.lastTargetAt = game.time;
  }
  p.state = 'attack';
  p.stateTime = 0;
  game.telemetry.attacks++;
  emit(game, 'attackStart', { index, strike, angle: p.attack.angle });
}

function updateAttack(game, dt) {
  const p = game.player;
  const t = game.tuning;
  const a = p.attack;
  a.t += dt;
  // Mouvement résiduel + élan (lunge) pendant l'actif.
  const slow = t.player.speed * p.stats.moveSpeedMult * t.player.attackMoveMult;
  let vx = p.moveX * slow;
  let vy = p.moveY * slow;
  if (a.phase === 'startup' && a.t >= a.dur.startup) {
    a.phase = 'active';
    a.t -= a.dur.startup;
    a.lungeV = lungeDistance(game, a) / Math.max(1e-3, a.dur.active);
    emit(game, 'swing', { x: p.x, y: p.y, angle: a.angle, arc: a.def.arc * DEG, range: a.def.range, index: a.index, strike: a.strike });
  }
  if (a.phase === 'active') {
    vx += a.dirX * a.lungeV;
    vy += a.dirY * a.lungeV;
    sweepHits(game, a);
    if (a.t >= a.dur.active) {
      a.phase = 'recovery';
      a.t -= a.dur.active;
    }
  }
  if (a.phase === 'recovery' && a.t >= a.dur.recovery) {
    p.comboIndex = a.strike ? 0 : (a.index + 1) % t.combo.length;
    p.comboTimer = 0;
    p.attack = null;
    p.state = 'free';
    p.stateTime = 0;
  }
  p.vx = vx;
  p.vy = vy;
}

/** Élan « aimanté » : on s'arrête au contact de la cible au lieu de la traverser, et on
 *  allonge un peu l'élan si elle est juste hors de portée (indulgence mobile). */
function lungeDistance(game, a) {
  const p = game.player;
  const base = a.def.lunge;
  if (!a.targetId) return base;
  const e = game.enemies.find((o) => o.id === a.targetId);
  if (!e || e.dead) return base;
  const gap = Math.sqrt(dist2(p.x, p.y, e.x, e.y)) - p.r - e.r - 6;
  return Math.max(0, Math.min(base * 1.5, gap));
}

function sweepHits(game, a) {
  const p = game.player;
  const def = a.def;
  const arc = def.arc * DEG;
  for (const e of game.enemies) {
    if (e.dead || e.spawnT > 0 || a.hitIds.includes(e.id)) continue;
    if (!inSector(e.x, e.y, p.x, p.y, def.range, a.angle, arc, e.r)) continue;
    a.hitIds.push(e.id);
    const dx = e.x - p.x;
    const dy = e.y - p.y;
    const l = Math.max(1e-6, Math.sqrt(dx * dx + dy * dy));
    // Knockback dans l'axe du coup, légèrement ouvert vers l'extérieur.
    const kx = a.dirX * 0.7 + (dx / l) * 0.3;
    const ky = a.dirY * 0.7 + (dy / l) * 0.3;
    const kl = Math.max(1e-6, Math.sqrt(kx * kx + ky * ky));
    damageEnemy(game, e, {
      kind: a.strike ? 'strike' : 'melee',
      amount: def.damage,
      dirX: kx / kl,
      dirY: ky / kl,
      knockback: def.knockback,
      hitstop: def.hitstop,
      canCrit: true,
      shake: def.shake,
    });
  }
  // Parade : un coup détruit les projectiles ennemis qu'il balaie.
  for (const pr of game.projectiles) {
    if (pr.owner !== 'enemy' || pr.dead) continue;
    if (inSector(pr.x, pr.y, p.x, p.y, def.range, a.angle, arc, pr.r)) {
      pr.dead = true;
      game.telemetry.deflects++;
      emit(game, 'deflect', { x: pr.x, y: pr.y });
    }
  }
}

// ---------------------------------------------------------------- dash

function startDash(game) {
  const p = game.player;
  const t = game.tuning.dash;
  let dx = p.moveX;
  let dy = p.moveY;
  const l = Math.sqrt(dx * dx + dy * dy);
  if (l > 0.2) {
    dx /= l;
    dy /= l;
  } else {
    dx = Math.cos(p.facing);
    dy = Math.sin(p.facing);
  }
  if (p.state === 'attack') emit(game, 'cancel', { from: 'attack' });
  p.attack = null;
  p.dashCharges--;
  p.dashDirX = dx;
  p.dashDirY = dy;
  p.dashT = t.duration;
  p.iframes = Math.max(p.iframes, t.iframes);
  p.dodgeIframes = Math.max(p.dodgeIframes, t.iframes);
  p.facing = Math.atan2(dy, dx);
  p.state = 'dash';
  p.stateTime = 0;
  game.hitstop = 0;
  game.telemetry.dashes++;
  emit(game, 'dash', { x: p.x, y: p.y, dirX: dx, dirY: dy, charges: p.dashCharges });
  for (const pr of p.procs) {
    if (pr.on === 'dash' && pr.effect === 'nova') dashNova(game, pr);
  }
}

function dashNova(game, pr) {
  const p = game.player;
  for (const e of game.enemies) {
    if (e.dead || e.spawnT > 0) continue;
    const rr = pr.radius + e.r;
    if (dist2(p.x, p.y, e.x, e.y) < rr * rr) {
      damageEnemy(game, e, { kind: 'blast', amount: pr.value, dirX: 0, dirY: 0, canCrit: false });
      if (pr.chill) {
        e.chill = Math.max(e.chill, pr.chill);
        e.chillMult = Math.min(e.chillMult || 1, 0.5);
      }
    }
  }
  emit(game, 'dashNova', { x: p.x, y: p.y, r: pr.radius });
}

function updateDash(game, dt) {
  const p = game.player;
  const t = game.tuning;
  const speed = t.dash.distance / t.dash.duration;
  p.vx = p.dashDirX * speed;
  p.vy = p.dashDirY * speed;
  p.dashT -= dt;
  if (p.dashT <= 0) {
    p.state = 'free';
    p.stateTime = 0;
    p.strikeWindow = t.dash.strikeWindow;
    // L'élan se prolonge à la vitesse de course : sortie de dash fluide, pas un arrêt sec.
    const run = t.player.speed * p.stats.moveSpeedMult;
    p.vx = p.dashDirX * run;
    p.vy = p.dashDirY * run;
    emit(game, 'dashEnd', { x: p.x, y: p.y });
  }
}

// ---------------------------------------------------------------- compétence (Lance infernale)

function startCast(game, aimX, aimY) {
  const p = game.player;
  const s = game.tuning.skill;
  const mx = aimX || p.manualAimX;
  const my = aimY || p.manualAimY;
  const aim = computeAim(game, mx, my, game.tuning.autoAim.skillRange);
  if (p.state === 'attack') emit(game, 'cancel', { from: 'attack' });
  p.attack = null;
  p.castDirX = aim.x;
  p.castDirY = aim.y;
  p.facing = Math.atan2(aim.y, aim.x);
  p.castT = s.castTime;
  p.skillCd = s.cooldown * p.stats.skillCooldownMult;
  p.state = 'cast';
  p.stateTime = 0;
  emit(game, 'castStart', { angle: p.facing });
}

function updateCast(game, dt) {
  const p = game.player;
  const t = game.tuning;
  const s = t.skill;
  const slow = t.player.speed * p.stats.moveSpeedMult * t.player.attackMoveMult;
  p.vx = p.moveX * slow;
  p.vy = p.moveY * slow;
  p.castT -= dt;
  if (p.castT > 0) return;
  spawnProjectile(game, {
    owner: 'player',
    kind: 'lance',
    x: p.x + p.castDirX * (p.r + 4),
    y: p.y + p.castDirY * (p.r + 4),
    vx: p.castDirX * s.speed,
    vy: p.castDirY * s.speed,
    r: s.radius,
    damage: s.damage,
    range: s.range,
    pierce: s.pierce,
    knockback: s.knockback,
    hitstop: s.hitstop,
  });
  // Recul : la lance repousse légèrement le héros (sensation de puissance).
  p.vx -= p.castDirX * 120;
  p.vy -= p.castDirY * 120;
  game.telemetry.skillCasts++;
  emit(game, 'skill', { x: p.x, y: p.y, angle: Math.atan2(p.castDirY, p.castDirX) });
  p.state = 'free';
  p.stateTime = 0;
}

// ---------------------------------------------------------------- gadget (Nova de cendres)

export function useGadget(game) {
  const p = game.player;
  const g = game.tuning.gadget;
  if (p.state === 'dead' || p.state === 'super' || p.gadgetCharges <= 0) return false;
  p.gadgetCharges--;
  p.iframes = Math.max(p.iframes, g.iframes);
  for (const e of game.enemies) {
    if (e.dead || e.spawnT > 0) continue;
    const dx = e.x - p.x;
    const dy = e.y - p.y;
    const rr = g.radius + e.r;
    const d2 = dx * dx + dy * dy;
    if (d2 >= rr * rr) continue;
    const l = Math.max(1e-6, Math.sqrt(d2));
    damageEnemy(game, e, {
      kind: 'gadget', amount: g.damage, dirX: dx / l, dirY: dy / l,
      knockback: g.knockback, stun: g.stun, hitstop: g.hitstop, canCrit: false,
    });
  }
  destroyEnemyProjectilesInCircle(game, p.x, p.y, g.radius);
  game.telemetry.gadgetUses++;
  emit(game, 'gadget', { x: p.x, y: p.y, r: g.radius, charges: p.gadgetCharges });
  return true;
}

// ---------------------------------------------------------------- Super (Colère)

function startSuper(game) {
  const p = game.player;
  const s = game.tuning.super;
  if (p.state === 'attack' || p.state === 'dash') emit(game, 'cancel', { from: p.state });
  p.attack = null;
  p.superCharge = 0;
  p.superT = s.duration + (p.stats.superDurationBonus ?? 0);
  p.superTick = 0;
  p.state = 'super';
  p.stateTime = 0;
  game.telemetry.superUses++;
  emit(game, 'super', { x: p.x, y: p.y, r: s.radius });
}

function updateSuper(game, dt) {
  const p = game.player;
  const t = game.tuning;
  const s = t.super;
  locomotion(game, dt, t.player.speed * p.stats.moveSpeedMult * s.speedMult);
  p.superT -= dt;
  p.superTick -= dt;
  if (p.superTick <= 0) {
    p.superTick += s.tickInterval;
    for (const e of game.enemies) {
      if (e.dead || e.spawnT > 0) continue;
      const dx = e.x - p.x;
      const dy = e.y - p.y;
      const rr = s.radius + e.r;
      const d2 = dx * dx + dy * dy;
      if (d2 >= rr * rr) continue;
      const l = Math.max(1e-6, Math.sqrt(d2));
      damageEnemy(game, e, {
        kind: 'super', amount: s.damagePerTick, dirX: dx / l, dirY: dy / l,
        knockback: s.knockback, canCrit: true,
      });
    }
    destroyEnemyProjectilesInCircle(game, p.x, p.y, s.radius);
    emit(game, 'superTick', { x: p.x, y: p.y, r: s.radius });
  }
  if (p.superT <= 0) {
    p.state = 'free';
    p.stateTime = 0;
    emit(game, 'superEnd', { x: p.x, y: p.y });
  }
}

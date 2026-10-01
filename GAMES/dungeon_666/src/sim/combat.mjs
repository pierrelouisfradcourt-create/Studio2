// Résolution des dégâts — UN SEUL chemin pour toucher un ennemi (damageEnemy) et UN SEUL
// pour toucher le héros (damagePlayer). Les bénédictions n'exécutent pas de code : elles
// déclarent des « procs » (données) que ce module interprète. Pas d'import circulaire.

import { rand } from '../core/rng.mjs';
import { dist2, clamp } from '../core/math.mjs';
import { emit, newId } from './state.mjs';

// Sources de dégâts du héros qui déclenchent les procs « au toucher ».
const PROC_SOURCES = new Set(['melee', 'strike', 'skill', 'gadget', 'super']);
// Sources qui ne remplissent pas la jauge de Super (sinon le Super se recharge lui-même).
const NO_SUPER_CHARGE = new Set(['super', 'burn', 'blast', 'chain']);
const ARMOR_CAP = 0.6;

/** Gel d'impact des coups du héros, puisé dans une réserve qui se recharge (anti-diaporama). */
export function applyHitstop(game, h) {
  const allowed = Math.min(h, game.hitstopBank);
  if (allowed <= game.hitstop) return;
  game.hitstopBank -= allowed - game.hitstop;
  game.hitstop = allowed;
}

/** Gel imposé (héros touché, mort d'un élite, d'un boss) : hors réserve, toujours ressenti. */
export function forceHitstop(game, h) {
  game.hitstop = Math.max(game.hitstop, h);
}

export function isPlayerSource(kind) {
  return kind !== 'enemyBlast' && kind !== 'wall';
}

/**
 * Inflige des dégâts à un ennemi. `src` : {kind, amount, dirX, dirY, knockback, hitstop,
 * canCrit, stun}. Rend les dégâts réellement infligés.
 */
export function damageEnemy(game, e, src) {
  if (e.dead || e.spawnT > 0) return 0;
  if (e.invuln > 0) {
    // Boss en transition de phase : le coup est vu, mais ne porte pas.
    if (src.kind === 'melee' || src.kind === 'strike' || src.kind === 'skill') emit(game, 'immune', { x: e.x, y: e.y });
    return 0;
  }
  const t = game.tuning;
  const p = game.player;
  const st = p.stats;
  let amount = src.amount;
  if (isPlayerSource(src.kind) && src.kind !== 'wall') {
    amount *= st.damageMult * (st.weaponDamage / t.weaponBase);
    if (src.kind === 'skill') amount *= st.skillDamageMult;
    // Bonus d'exécution (bénédiction) contre les ennemis affaiblis.
    for (const pr of p.procs) {
      if (pr.effect === 'execute' && e.hp / e.maxHp <= pr.threshold && (!pr.needsBurnChill || (e.burn > 0 && e.chill > 0))) amount *= 1 + pr.value;
      if (pr.effect === 'fullHpBonus' && p.hp >= p.maxHp) amount *= 1 + pr.value;
    }
    if (src.kind === 'super') amount *= st.superDamageMult ?? 1;
  }
  if (e.eliteMod === 'blinde') amount *= t.elite.mods.blinde.damageTakenMult;
  if (e.stun > 0) amount *= t.combat.stunDamageTakenMult;
  if (e.vuln > 0) amount *= 1 + e.vulnMult;

  let crit = false;
  if (src.canCrit) {
    const chance = t.combat.critChance + st.critChance;
    if (rand(game.rng.combat) < chance) {
      crit = true;
      amount *= t.combat.critMult + st.critMult;
    }
  }
  amount = Math.max(1, Math.round(amount));
  const hpBefore = e.hp;
  e.hp -= amount;
  e.flash = 0.1;
  e.lastHitAt = game.time;
  if (src.dirX || src.dirY) {
    e.hitDirX = src.dirX;
    e.hitDirY = src.dirY;
  }

  // Knockback : on remplace l'élan courant s'il est plus faible (pas d'accumulation infinie).
  if (src.knockback) {
    let kb = (src.knockback * st.knockbackMult) / e.mass;
    if (e.eliteMod === 'blinde') kb *= t.elite.mods.blinde.knockbackMult;
    if (e.boss) kb *= 0.15;
    const cur2 = e.kvx * e.kvx + e.kvy * e.kvy;
    if (kb * kb > cur2) {
      e.kvx = src.dirX * kb;
      e.kvy = src.dirY * kb;
    }
  }
  if (src.stun && !e.boss) {
    e.stun = Math.max(e.stun, src.stun);
    e.tele = null;
    e.state = 'stunned';
    e.stateTime = 0;
  }
  if (src.hitstop) applyHitstop(game, e.boss ? Math.min(src.hitstop, t.boss[e.kind].hitstopCap) : src.hitstop);

  const tel = game.telemetry;
  tel.damageDealt += amount;
  if (src.kind === 'melee' || src.kind === 'strike') tel.hitsLanded++;

  if (isPlayerSource(src.kind) && !NO_SUPER_CHARGE.has(src.kind) && p.state !== 'super') {
    const before = p.superCharge;
    // L'overkill ne compte pas : achever un ennemi à 1 PV ne remplit pas la jauge.
    const effective = Math.min(amount, Math.max(0, hpBefore));
    p.superCharge = Math.min(1, p.superCharge + (effective / t.super.chargeDamage) * st.superChargeMult);
    if (before < 1 && p.superCharge >= 1) emit(game, 'superReady');
  }
  if (st.lifesteal > 0 && PROC_SOURCES.has(src.kind)) healPlayer(game, amount * st.lifesteal, false);

  emit(game, 'hit', { id: e.id, x: e.x, y: e.y, amount, crit, kind: src.kind, dirX: src.dirX ?? 0, dirY: src.dirY ?? 0, enemy: e.kind, shake: src.shake ?? 0 });

  if (PROC_SOURCES.has(src.kind)) applyHitProcs(game, e, src);
  if (e.hp <= 0) killEnemy(game, e, src);
  return amount;
}

function applyHitProcs(game, e, src) {
  const p = game.player;
  for (const pr of p.procs) {
    if (pr.on !== 'hit' || !pr.sources.includes(src.kind)) continue;
    if (pr.chance < 1 && rand(game.rng.combat) >= pr.chance) continue;
    switch (pr.effect) {
      case 'burn':
        e.burn = Math.max(e.burn, pr.duration);
        e.burnDps = Math.max(e.burnDps, pr.value);
        break;
      case 'chill':
        e.chill = Math.max(e.chill, pr.duration);
        // Borné : un ennemi ralenti reste un ennemi qui avance (jamais de vitesse négative).
        e.chillMult = Math.min(e.chillMult || 1, Math.max(game.tuning.combat.minChillMult, 1 - pr.value));
        break;
      case 'vuln':
        e.vuln = Math.max(e.vuln, pr.duration);
        e.vulnMult = Math.max(e.vulnMult, pr.value);
        break;
      case 'chain':
        chainLightning(game, e, pr);
        break;
      case 'gold':
        game.run.gold += pr.value;
        emit(game, 'gold', { x: e.x, y: e.y, amount: pr.value });
        break;
      default:
        break;
    }
  }
}

function chainLightning(game, from, pr) {
  let cur = from;
  const hit = [from.id];
  for (let i = 0; i < pr.bounces; i++) {
    let best = null;
    let bestD = pr.range * pr.range;
    for (const o of game.enemies) {
      if (o.dead || o.spawnT > 0 || hit.includes(o.id)) continue;
      const d = dist2(cur.x, cur.y, o.x, o.y);
      if (d < bestD) {
        bestD = d;
        best = o;
      }
    }
    if (!best) break;
    emit(game, 'chain', { x0: cur.x, y0: cur.y, x1: best.x, y1: best.y });
    hit.push(best.id);
    damageEnemy(game, best, { kind: 'chain', amount: pr.value, canCrit: false });
    if (!best.dead) applyHitProcs(game, best, { kind: 'chainHit' });
    cur = best;
  }
}

export function killEnemy(game, e, src) {
  if (e.dead) return;
  const t = game.tuning;
  e.dead = true;
  e.hp = 0;
  e.tele = null;
  const tel = game.telemetry;
  tel.kills++;
  tel.killTimes.push({ kind: e.kind, life: game.time - e.bornAt });
  emit(game, 'kill', { id: e.id, x: e.x, y: e.y, r: e.r, enemy: e.kind, elite: !!e.eliteMod, boss: !!e.boss, kind: src?.kind ?? 'none' });

  // Butin d'or (les boss ont leur propre récompense, gérée par la salle).
  if (!e.boss && !e.summoned) {
    const def = t.enemies[e.kind];
    const [lo, hi] = def.gold;
    let amount = lo + Math.floor(rand(game.rng.gen) * (hi - lo + 1));
    if (e.eliteMod) amount *= t.elite.goldMult;
    amount = Math.round(amount * game.player.stats.goldFindMult);
    if (amount > 0) spawnPickup(game, 'gold', e.x, e.y, amount);
  }
  if (e.eliteMod) {
    const p = game.player;
    const maxG = t.gadget.chargesPerSection + p.stats.gadgetChargesBonus;
    if (p.gadgetCharges < maxG) {
      p.gadgetCharges = Math.min(maxG, p.gadgetCharges + t.gadget.chargeOnEliteKill);
      emit(game, 'gadgetCharge', { x: e.x, y: e.y, charges: p.gadgetCharges });
    }
    forceHitstop(game, t.killHitstop.elite);
  }
  if (e.boss) forceHitstop(game, t.killHitstop.boss);
  if (e.eliteMod === 'ardent') {
    const m = t.elite.mods.ardent;
    spawnHazard(game, {
      shape: 'circle', x: e.x, y: e.y, r: m.deathBlastRadius, delay: m.deathBlastDelay,
      damage: m.deathBlastDamage * e.dmgScale, hitsPlayer: true, hitsEnemies: false, kind: 'fireBlast', sourceId: 0,
    });
  }
  const p = game.player;
  for (const pr of p.procs) {
    if (pr.on !== 'kill') continue;
    if (pr.effect === 'heal') healPlayer(game, pr.value, true);
    if (pr.effect === 'blast') {
      spawnHazard(game, {
        shape: 'circle', x: e.x, y: e.y, r: pr.radius, delay: 0.12, damage: pr.value,
        hitsPlayer: false, hitsEnemies: true, kind: 'sinBlast', sourceId: 0,
      });
    }
  }
  if (p.stats.healOnKill > 0) healPlayer(game, p.stats.healOnKill, true);
  if (p.stats.extraGoldOnKill > 0 && !e.summoned) {
    game.run.gold += p.stats.extraGoldOnKill;
    emit(game, 'gold', { x: e.x, y: e.y, amount: p.stats.extraGoldOnKill });
  }
}

export function healPlayer(game, amount, show) {
  const p = game.player;
  if (p.state === 'dead' || amount <= 0) return;
  const before = p.hp;
  p.hp = Math.min(p.maxHp, p.hp + amount);
  if (show && p.hp - before >= 1) emit(game, 'heal', { x: p.x, y: p.y, amount: Math.round(p.hp - before) });
}

/**
 * Inflige des dégâts au héros. Rend true si le coup a porté. Pendant les i-frames, le coup
 * est esquivé — et compté comme tel s'il était évité grâce à un dash.
 */
export function damagePlayer(game, amount, src) {
  const p = game.player;
  const t = game.tuning;
  if (p.state === 'dead' || game.godMode) return false;
  if (p.iframes > 0 || p.state === 'super') {
    if (p.dodgeIframes > 0 && !p.dodgedIds.includes(src.id)) {
      p.dodgedIds.push(src.id);
      game.telemetry.dodges++;
      // Esquive parfaite : la jauge de Super grimpe et le dash se recharge plus vite.
      const d = t.dash;
      const before = p.superCharge;
      p.superCharge = Math.min(1, p.superCharge + d.perfectDodgeSuper);
      if (before < 1 && p.superCharge >= 1) emit(game, 'superReady');
      p.dashRecharge += d.perfectDodgeRefund;
      emit(game, 'dodge', { x: p.x, y: p.y });
    }
    return false;
  }
  const armor = clamp(p.stats.armor, 0, ARMOR_CAP);
  const dmg = Math.max(1, Math.round(amount * (1 - armor)));
  p.hp -= dmg;
  p.iframes = t.player.hurtIframes;
  p.dodgeIframes = 0;
  p.hurtFlash = 0.35;
  forceHitstop(game, t.player.hurtHitstop);
  const tel = game.telemetry;
  tel.damageTaken += dmg;
  tel.hitsTaken++;
  emit(game, 'playerHurt', { x: p.x, y: p.y, amount: dmg, source: src.kind, srcX: src.x ?? p.x, srcY: src.y ?? p.y });
  if (p.hp <= 0) {
    p.hp = 0;
    p.state = 'dead';
    p.stateTime = 0;
    p.attack = null;
    tel.deaths++;
    tel.deathCauses[src.kind] = (tel.deathCauses[src.kind] ?? 0) + 1;
    emit(game, 'playerDeath', { x: p.x, y: p.y, source: src.kind });
  }
  return true;
}

export function spawnPickup(game, kind, x, y, value, extra) {
  const a = rand(game.rng.gen) * Math.PI * 2;
  const s = 80 + rand(game.rng.gen) * 120;
  const pk = { id: newId(game), kind, x, y, vx: Math.cos(a) * s, vy: Math.sin(a) * s, r: kind === 'gold' ? 6 : 10, value, age: 0, ...extra };
  game.pickups.push(pk);
  return pk;
}

/**
 * Zone de danger télégraphiée : visible pendant `delay`, puis frappe une fois.
 * shape 'circle' {x, y, r} | 'line' {x, y, angle, length, width} | 'ring' {x, y, r, inner}.
 */
export function spawnHazard(game, h) {
  const hz = {
    id: newId(game),
    shape: 'circle',
    angle: 0,
    length: 0,
    width: 0,
    inner: 0,
    t: 0,
    sourceId: 0,
    hitsPlayer: true,
    hitsEnemies: false,
    done: false,
    ...h,
  };
  game.hazards.push(hz);
  emit(game, 'hazard', { id: hz.id, kind: hz.kind, x: hz.x, y: hz.y });
  return hz;
}

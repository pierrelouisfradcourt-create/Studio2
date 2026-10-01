// Ennemis : création, IA par archétype, statuts, knockback, collisions.
//
// Règle de lisibilité : AUCUN dégât de contact. Tout coup ennemi passe par un télégraphe
// (e.tele ou une zone de danger) d'une durée >= au seuil de réaction, et un nombre limité
// d'ennemis de mêlée attaque en même temps (jetons d'attaque).

import { rand, randRange } from '../core/rng.mjs';
import { dist2 } from '../core/math.mjs';
import { emit, newId } from './state.mjs';
import { moveCircle, lineOfSight } from './physics.mjs';
import { damageEnemy, damagePlayer, spawnHazard } from './combat.mjs';
import { spawnProjectile } from './projectiles.mjs';
import { floorScaling } from './floors.mjs';
import { updateBoss } from './boss.mjs';
import { MELEE_KINDS, SHOOTER_KINDS, speedOf, windupOf, activeAttackers, activeShooters, setState, toPlayer, steer, trackUntilLock } from './ai_common.mjs';
import { EXTRA_FOES } from './foes.mjs';
import { updateEliteMod, foeDealt } from './foe_elites.mjs';

const BURN_TICK = 0.25;

export function createEnemy(game, kind, x, y, opts = {}) {
  const t = game.tuning;
  const isBoss = !!opts.boss;
  const def = isBoss ? t.boss[kind] : t.enemies[kind];
  const scale = floorScaling(t, game.run.floor);
  const elite = opts.elite ?? null;
  const sizeMult = elite ? t.elite.sizeMult : 1;
  const hp = Math.round(def.hp * scale.hp * (elite ? t.elite.hpMult : 1));
  const e = {
    id: newId(game),
    kind,
    boss: isBoss,
    x,
    y,
    vx: 0,
    vy: 0,
    kvx: 0,
    kvy: 0,
    r: def.radius * sizeMult,
    hp,
    maxHp: hp,
    mass: def.mass * (elite ? 1.5 : 1),
    dmgScale: scale.damage * (elite ? t.elite.damageMult : 1),
    eliteMod: elite,
    state: 'chase',
    stateTime: 0,
    cooldown: 0.4 + rand(game.rng.ai) * 0.8, // désynchronise les premières attaques
    dirX: 0,
    dirY: 1,
    tele: null,
    flash: 0,
    stun: 0,
    burn: 0,
    burnDps: 0,
    burnAcc: 0,
    chill: 0,
    chillMult: 1,
    vuln: 0,
    vulnMult: 0,
    spawnT: opts.spawnT ?? 0.25,
    bornAt: game.time,
    dead: false,
    strafe: rand(game.rng.ai) < 0.5 ? -1 : 1,
    flank: rand(game.rng.ai) * Math.PI * 2,
    hitPlayer: false,
    atkId: 0,
    summoned: !!opts.summoned,
    lastHitAt: -1,
    freeze: 0, // gel d'impact LOCAL restant (D8) : l'ennemi touché se fige, le reste continue
    // État propre au boss (patterns), ignoré par les autres.
    phase: 1,
    pattern: null,
    patternStep: 0,
    patternT: 0,
  };
  game.enemies.push(e);
  emit(game, 'spawn', { id: e.id, x, y, enemy: kind, elite: !!elite, boss: isBoss });
  return e;
}






export function updateEnemies(game, dt) {
  const t = game.tuning;
  const p = game.player;
  for (const e of game.enemies) {
    if (e.dead) continue;
    if (e.freeze > 0) {
      // Gel LOCAL : figé dans la pose d'impact ; son recul part au dégel (élan conservé).
      e.freeze = Math.max(0, e.freeze - dt);
      continue;
    }
    e.stateTime += dt;
    e.flash = Math.max(0, e.flash - dt);
    if (e.spawnT > 0) {
      e.spawnT -= dt;
      continue;
    }
    tickStatuses(game, e, dt);
    if (e.dead) continue;
    e.cooldown = Math.max(0, e.cooldown - dt);
    e.vx = 0;
    e.vy = 0;
    // Champions V2 (bouclier, invocateur, vampirique) : foe_elites.mjs.
    if (e.eliteMod && p.state !== 'dead') updateEliteMod(game, e, dt);
    if (e.stun > 0) {
      e.stun -= dt;
      e.tele = null;
      if (e.stun <= 0) {
        setState(e, 'chase');
        e.cooldown = Math.max(e.cooldown, 0.3);
      }
    } else if (p.state !== 'dead') {
      if (e.boss) updateBoss(game, e, dt);
      else {
        const hp0 = p.hp;
        AI[e.kind](game, e, t.enemies[e.kind], dt);
        if (e.eliteMod && p.hp < hp0) foeDealt(game, e, hp0 - p.hp); // coup direct qui a porté
      }
    }
    integrate(game, e, dt);
  }
  separate(game);
  // La séparation pousse sans regarder les murs : on repasse la collision (jamais dans un
  // obstacle, jamais à travers un mur fin).
  for (const e of game.enemies) if (!e.dead) moveCircle(game.room, e, 0, 0);
}

function tickStatuses(game, e, dt) {
  if (e.chill > 0) e.chill -= dt;
  else e.chillMult = 1;
  if (e.vuln > 0) e.vuln -= dt;
  else e.vulnMult = 0;
  if (e.burn > 0) {
    e.burn -= dt;
    e.burnAcc += e.burnDps * dt;
    if (e.burnAcc >= e.burnDps * BURN_TICK || e.burn <= 0) {
      const amount = e.burnAcc;
      e.burnAcc = 0;
      if (amount >= 0.5) damageEnemy(game, e, { kind: 'burn', amount, canCrit: false });
    }
  }
}

function integrate(game, e, dt) {
  const t = game.tuning;
  const ws = t.wallSlam;
  const k = Math.exp(-t.combat.enemyFriction * dt);
  const kSpeed = Math.sqrt(e.kvx * e.kvx + e.kvy * e.kvy);
  const res = moveCircle(game.room, e, (e.vx + e.kvx) * dt, (e.vy + e.kvy) * dt);
  if (res.hitWall) {
    if (kSpeed > ws.minSpeed && !e.boss) {
      // Projeté contre un mur : dégâts bonus, étourdissement, gel d'impact — le knockback
      // devient une arme de positionnement.
      e.kvx = 0;
      e.kvy = 0;
      game.telemetry.wallSlams++;
      emit(game, 'wallSlam', { id: e.id, x: e.x, y: e.y });
      damageEnemy(game, e, { kind: 'wall', amount: ws.damage, stun: ws.stun, hitstop: ws.hitstop, canCrit: false });
    } else {
      // Glissement le long du mur : on retire la composante normale du knockback.
      const vn = e.kvx * res.nx + e.kvy * res.ny;
      if (vn < 0) {
        e.kvx -= vn * res.nx;
        e.kvy -= vn * res.ny;
      }
    }
  }
  e.kvx *= k;
  e.kvy *= k;
}

function separate(game) {
  const t = game.tuning;
  const p = game.player;
  const list = game.enemies;
  for (let i = 0; i < list.length; i++) {
    const a = list[i];
    if (a.dead) continue;
    for (let j = i + 1; j < list.length; j++) {
      const b = list[j];
      if (b.dead) continue;
      const dx = b.x - a.x;
      const dy = b.y - a.y;
      const rr = a.r + b.r;
      const d2 = dx * dx + dy * dy;
      if (d2 >= rr * rr || d2 < 1e-9) continue;
      const d = Math.sqrt(d2);
      const push = ((rr - d) / d) * t.combat.enemySeparation;
      const wa = b.mass / (a.mass + b.mass);
      const wb = a.mass / (a.mass + b.mass);
      a.x -= dx * push * wa;
      a.y -= dy * push * wa;
      b.x += dx * push * wb;
      b.y += dy * push * wb;
    }
    // Le héros est « infiniment lourd » : il repousse les ennemis, jamais l'inverse
    // (déplacement net garanti). Pendant un dash, on traverse.
    if (p.state !== 'dash' && p.state !== 'dead') {
      const dx = a.x - p.x;
      const dy = a.y - p.y;
      const rr = a.r + p.r;
      const d2 = dx * dx + dy * dy;
      if (d2 < rr * rr && d2 > 1e-9) {
        const d = Math.sqrt(d2);
        a.x = p.x + (dx / d) * rr;
        a.y = p.y + (dy / d) * rr;
      }
    }
  }
}




const AI = {
  imp(game, e, def, dt) {
    const p = game.player;
    const tp = toPlayer(game, e);
    const windup = windupOf(game, e, def.windup);
    switch (e.state) {
      case 'chase': {
        const reach = def.attackRange + p.r;
        if (tp.d < reach && e.cooldown <= 0 && activeAttackers(game) < game.tuning.combat.maxAttackers) {
          setState(e, 'windup');
          e.dirX = tp.dx;
          e.dirY = tp.dy;
          e.hitPlayer = false;
          e.atkId = newId(game);
          break;
        }
        // Sans jeton : on encercle à distance au lieu de s'empiler sur le héros.
        const ring = tp.d < reach * 1.6 ? reach * 1.25 : 0;
        const tx = p.x + Math.cos(e.flank) * ring;
        const ty = p.y + Math.sin(e.flank) * ring;
        steer(game, e, tx, ty, speedOf(game, e, def));
        e.flank += e.strafe * dt * 0.6;
        break;
      }
      case 'windup':
        trackUntilLock(game, e, 0.7, windup);
        e.tele = { shape: 'cone', angle: Math.atan2(e.dirY, e.dirX), range: def.strikeSpeed * def.strikeTime + e.r + 14, arc: 0.9, progress: e.stateTime / windup };
        if (e.stateTime >= windup) {
          setState(e, 'strike');
          e.tele = null;
          emit(game, 'enemyAttack', { id: e.id, x: e.x, y: e.y, enemy: e.kind });
        }
        break;
      case 'strike':
        e.vx = e.dirX * def.strikeSpeed;
        e.vy = e.dirY * def.strikeSpeed;
        if (!e.hitPlayer && dist2(e.x, e.y, p.x, p.y) < (e.r + p.r + 8) ** 2) {
          e.hitPlayer = true;
          damagePlayer(game, def.damage * e.dmgScale, { kind: 'imp', id: e.atkId, x: e.x, y: e.y });
        }
        if (e.stateTime >= def.strikeTime) setState(e, 'recover');
        break;
      case 'recover':
        if (e.stateTime >= def.recover) {
          setState(e, 'chase');
          e.cooldown = def.cooldown;
        }
        break;
      default:
        setState(e, 'chase');
    }
  },

  archer(game, e, def) {
    const p = game.player;
    const tp = toPlayer(game, e);
    const windup = windupOf(game, e, def.windup);
    const sees = lineOfSight(game.room, e.x, e.y, p.x, p.y);
    switch (e.state) {
      case 'chase': {
        const speed = speedOf(game, e, def);
        if (e.cooldown <= 0 && sees && tp.d < def.projRange * 0.9 && activeShooters(game) < game.tuning.combat.maxShooters) {
          setState(e, 'windup');
          e.dirX = tp.dx;
          e.dirY = tp.dy;
          break;
        }
        if (tp.d < def.fleeDist) {
          e.vx = -tp.dx * speed;
          e.vy = -tp.dy * speed;
        } else if (tp.d > def.preferredDist + 60 || !sees) {
          steer(game, e, p.x, p.y, speed);
        } else {
          // Strafe perpendiculaire, change de sens de temps en temps.
          e.vx = -tp.dy * speed * 0.7 * e.strafe;
          e.vy = tp.dx * speed * 0.7 * e.strafe;
          if (rand(game.rng.ai) < 0.01) e.strafe = -e.strafe;
        }
        break;
      }
      case 'windup':
        trackUntilLock(game, e, def.lockAt, windup);
        e.tele = { shape: 'line', angle: Math.atan2(e.dirY, e.dirX), length: def.teleLength, width: def.projRadius * 2 + 4, progress: e.stateTime / windup };
        if (e.stateTime >= windup) {
          e.tele = null;
          spawnProjectile(game, {
            owner: 'enemy', kind: 'arrow',
            x: e.x + e.dirX * (e.r + 4), y: e.y + e.dirY * (e.r + 4),
            vx: e.dirX * def.projSpeed, vy: e.dirY * def.projSpeed,
            r: def.projRadius, damage: def.damage * e.dmgScale, range: def.projRange, sourceId: e.id,
          });
          emit(game, 'enemyAttack', { id: e.id, x: e.x, y: e.y, enemy: e.kind });
          setState(e, 'recover');
        }
        break;
      case 'recover':
        if (e.stateTime >= def.recover) {
          setState(e, 'chase');
          e.cooldown = def.cooldown * randRange(game.rng.ai, 0.85, 1.25);
        }
        break;
      default:
        setState(e, 'chase');
    }
  },

  brute(game, e, def) {
    const p = game.player;
    const tp = toPlayer(game, e);
    const windup = windupOf(game, e, def.windup);
    switch (e.state) {
      case 'chase':
        if (tp.d < def.attackRange * 0.85 + p.r && e.cooldown <= 0 && activeAttackers(game) < game.tuning.combat.maxAttackers) {
          setState(e, 'windup');
          spawnHazard(game, {
            shape: 'circle', x: e.x, y: e.y, r: def.slamRadius * (e.eliteMod ? game.tuning.elite.sizeMult : 1),
            delay: windup, damage: def.damage * e.dmgScale, kind: 'brute', sourceId: e.id,
          });
          break;
        }
        steer(game, e, p.x, p.y, speedOf(game, e, def));
        break;
      case 'windup':
        if (e.stateTime >= windup) {
          setState(e, 'recover');
          emit(game, 'enemyAttack', { id: e.id, x: e.x, y: e.y, enemy: e.kind });
        }
        break;
      case 'recover':
        if (e.stateTime >= def.recover) {
          setState(e, 'chase');
          e.cooldown = def.cooldown;
        }
        break;
      default:
        setState(e, 'chase');
    }
  },

  charger(game, e, def, dt) {
    const p = game.player;
    const tp = toPlayer(game, e);
    const windup = windupOf(game, e, def.windup);
    switch (e.state) {
      case 'chase': {
        const sees = lineOfSight(game.room, e.x, e.y, p.x, p.y);
        if (tp.d < def.attackRange && sees && e.cooldown <= 0 && activeAttackers(game) < game.tuning.combat.maxAttackers) {
          setState(e, 'windup');
          e.dirX = tp.dx;
          e.dirY = tp.dy;
          e.hitPlayer = false;
          e.atkId = newId(game);
          break;
        }
        steer(game, e, p.x, p.y, speedOf(game, e, def));
        break;
      }
      case 'windup':
        trackUntilLock(game, e, 0.7, windup);
        e.tele = { shape: 'line', angle: Math.atan2(e.dirY, e.dirX), length: def.chargeSpeed * def.chargeMaxTime, width: e.r * 2 + 10, progress: e.stateTime / windup };
        if (e.stateTime >= windup) {
          e.tele = null;
          setState(e, 'charge');
          emit(game, 'enemyAttack', { id: e.id, x: e.x, y: e.y, enemy: e.kind });
        }
        break;
      case 'charge': {
        e.vx = e.dirX * def.chargeSpeed;
        e.vy = e.dirY * def.chargeSpeed;
        if (!e.hitPlayer && dist2(e.x, e.y, p.x, p.y) < (e.r + p.r + 4) ** 2) {
          e.hitPlayer = true;
          damagePlayer(game, def.damage * e.dmgScale, { kind: 'charger', id: e.atkId, x: e.x, y: e.y });
        }
        // La charge se déplace ici (et non dans integrate) pour détecter le mur percuté.
        const res = moveCircle(game.room, e, e.vx * dt, e.vy * dt);
        e.vx = 0;
        e.vy = 0;
        if (res.hitWall) {
          // Mur percuté : longue fenêtre de punition.
          e.stun = def.wallStun;
          setState(e, 'stunned');
          game.telemetry.wallSlams++;
          emit(game, 'chargerWall', { id: e.id, x: e.x, y: e.y });
        } else if (e.stateTime >= def.chargeMaxTime) {
          setState(e, 'recover');
        }
        break;
      }
      case 'recover':
        if (e.stateTime >= def.recover) {
          setState(e, 'chase');
          e.cooldown = def.cooldown;
        }
        break;
      default:
        setState(e, 'chase');
    }
  },

  exploder(game, e, def) {
    const p = game.player;
    const tp = toPlayer(game, e);
    switch (e.state) {
      case 'chase':
        if (tp.d < def.triggerRange + p.r) {
          setState(e, 'windup');
          break;
        }
        steer(game, e, p.x, p.y, speedOf(game, e, def));
        break;
      case 'windup': {
        const windup = windupOf(game, e, def.windup);
        e.tele = { shape: 'circle', r: def.blastRadius, progress: e.stateTime / windup };
        if (e.stateTime >= windup) {
          e.tele = null;
          e.dead = true;
          e.exploded = true;
          spawnHazard(game, {
            shape: 'circle', x: e.x, y: e.y, r: def.blastRadius, delay: 0,
            damage: def.damage * e.dmgScale, hitsPlayer: true, hitsEnemies: def.blastHurtsEnemies,
            kind: 'exploder', ownerId: e.id,
          });
          emit(game, 'explode', { id: e.id, x: e.x, y: e.y, r: def.blastRadius });
        }
        break;
      }
      default:
        setState(e, 'chase');
    }
  },
};

// Archétypes ajoutés (un fichier chacun : src/sim/foe_<archétype>.mjs) : branchés dans la même table.
for (const f of EXTRA_FOES) {
  AI[f.kind] = f.ai;
  if (f.melee) MELEE_KINDS.add(f.kind);
  if (f.shooter) SHOOTER_KINDS.add(f.kind);
}

export { windupOf };

export function aliveEnemies(game) {
  let n = 0;
  for (const e of game.enemies) if (!e.dead) n++;
  return n;
}

// COMPÉTENCES (bouton Lance) autres que la Lance infernale, jouées selon `kind` :
//   chain   — Chaîne d'Enfer : crochet qui harponne, étourdit et tire l'ennemi au contact
//   bond    — Bond du bourreau : saut invulnérable vers la cible, impact à l'atterrissage
//   brasier — Brasier d'âmes : pot lancé sur la cible, impact puis sol qui brûle
//   volee   — Volée d'épines : éventail de traits
//
// player.mjs garde la machine à états (état 'cast', recharge, tampon, annulations) et appelle :
//   beginKitSkill   au début du lancer (mémorise la cible ; le Bond part aussitôt)
//   updateLeap      à chaque pas du Bond (rend true à l'atterrissage)
//   releaseKitSkill à la fin du lancer, ou AVANT un dash / Super qui l'interrompt : une
//                   recharge consommée produit toujours son effet (comme la Lance).

import * as TRIG from '../core/trig.mjs'; // sinus, cosinus… déterministes : jamais Math.sin & co dans la simulation
import { clamp } from '../core/math.mjs';
import { emit } from './state.mjs';
import { spawnShot, fireFan } from './kit_shots.mjs';
import { spawnZone } from './kit_zones.mjs';
import { hitCircle, liveEnemy, throwPoint } from './kit_common.mjs';

const LAND_OVERLAP = 0.5; // le Bond s'arrête quand le héros chevauche la cible de moitié
const point = { x: 0, y: 0 };

/** Début du lancer : `aim` = visée résolue par player.mjs (objet partagé : on le copie). */
export function beginKitSkill(game, s, aim) {
  const p = game.player;
  p.cast = { kind: s.kind, targetId: aim.targetId, targetDist: aim.targetDist, vx: 0, vy: 0 };
  if (s.kind === 'bond') beginLeap(game, s);
}

function beginLeap(game, s) {
  const p = game.player;
  let d = s.range;
  const e = liveEnemy(game, p.cast.targetId);
  if (e) d = clamp(p.cast.targetDist - (p.r + e.r) * LAND_OVERLAP, s.minRange, s.range);
  const speed = d / s.leapTime;
  p.cast.vx = p.castDirX * speed;
  p.cast.vy = p.castDirY * speed;
  p.castT = s.leapTime;
  p.iframes = Math.max(p.iframes, s.leapTime + s.iframesGrace);
  game.telemetry.skillCasts++;
  emit(game, 'skill', { x: p.x, y: p.y, angle: TRIG.atan2(p.castDirY, p.castDirX), skill: 'bond' });
}

/** Un pas du Bond (état 'cast'). Rend true quand le héros a atterri. */
export function updateLeap(game, dt) {
  const p = game.player;
  if (p.castT <= 0 || !p.cast) {
    land(game);
    return true;
  }
  p.vx = p.cast.vx;
  p.vy = p.cast.vy;
  p.castT -= dt;
  return false;
}

function land(game) {
  const p = game.player;
  const s = game.tuning.skill;
  p.cast = null;
  p.vx = 0;
  p.vy = 0;
  hitCircle(game, p.x, p.y, s.radius, { kind: 'skill', amount: s.damage, knockback: s.knockback, stun: s.stun, hitstop: s.hitstop, canCrit: true, shake: s.shake });
  emit(game, 'explode', { x: p.x, y: p.y, r: s.radius, hero: true, kind: 'bond' });
}

/** Effet de la compétence au relâcher (ou à l'interruption). */
export function releaseKitSkill(game) {
  const p = game.player;
  const s = game.tuning.skill;
  const angle = TRIG.atan2(p.castDirY, p.castDirX);
  switch (s.kind) {
    case 'bond':
      // Interrompu en plein saut (dash, Super) : il atterrit là où il est.
      if (p.cast) land(game);
      return;
    case 'chain':
      spawnShot(game, {
        kind: 'hook', x: p.x, y: p.y, vx: p.castDirX * s.speed, vy: p.castDirY * s.speed, r: s.radius, range: s.range,
        pierce: 0, damage: s.damage, source: 'skill', knockback: s.knockback, hitstop: s.hitstop, stun: s.stun,
        pull: { stopGap: s.pullGap, mass: s.pullMass },
      });
      break;
    case 'volee':
      fireFan(game, angle, s.count, s.spread, {
        kind: 'thorn', r: s.radius, speed: s.speed, range: s.range, pierce: s.pierce, damage: s.damage, source: 'skill',
        knockback: s.knockback, hitstop: s.hitstop,
      });
      break;
    case 'brasier': {
      const target = throwPoint(game, p.castDirX, p.castDirY, p.cast?.targetId ?? 0, s.range, s.throwDist, point);
      spawnZone(game, {
        kind: 'pot', x: p.x, y: p.y, x0: p.x, y0: p.y, tx: target.x, ty: target.y, flight: s.flight, lift: 0,
        r: s.radius, damage: s.damage, knockback: s.knockback, hitstop: s.hitstop,
        duration: s.duration, tick: s.tick, burnDps: s.burnDps, burnRefresh: s.burnRefresh,
      });
      break;
    }
    default:
      return;
  }
  // Recul léger au tir (sensation de puissance), comme la Lance.
  const recoil = s.recoil ?? 0;
  p.vx -= p.castDirX * recoil;
  p.vy -= p.castDirY * recoil;
  p.cast = null;
  game.telemetry.skillCasts++;
  emit(game, 'skill', { x: p.x, y: p.y, angle, skill: s.kind });
}

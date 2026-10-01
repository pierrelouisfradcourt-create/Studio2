// ÉLITES — modificateurs façon champions Diablo (données : tuning.elite.mods, config.mjs).
// Un seul modificateur par élite. Les trois d'origine sont lus là où ils agissent (rapide :
// ai_common.speedOf ; blindé : combat.damageEnemy ; ardent : combat.killEnemy). Les champions
// V2 vivent ici :
//   vampirique — chaque coup qui BLESSE le héros soigne l'élite (leech × dégâts infligés) ;
//                rayon de drain visible (e.leechFlash). Branché sur toutes les façons de
//                blesser : coup direct (enemies.mjs), zone et projectile (projectiles.mjs).
//   bouclier   — bulle d'immunité périodique (e.invuln, lu par combat.damageEnemy), annoncée
//                `warn` s à l'avance par un anneau doré inoffensif (e.modPhase 'warn').
//   invocateur — canalise (alerte violette inoffensive, e.modPhase 'channel'), puis ouvre des
//                cercles d'invocation sous le plafond de la salle. Le tuer pendant la
//                canalisation l'annule ; l'étourdir aussi.
// Module feuille côté sim (n'importe ni enemies.mjs ni projectiles.mjs).

import { pick } from '../core/rng.mjs';
import { emit, summonRoom, summonAround } from './ai_common.mjs';

/**
 * Modificateur d'élite pour un archétype `kind` à l'étage `info` (floorInfo). UN tirage dans
 * game.rng.gen, comme avant : dans la 1re section, un modificateur n'entre qu'à partir de son
 * `minIndex` (les premiers étages gardent exactement le tirage d'origine).
 */
export function pickEliteMod(game, kind, info) {
  const mods = game.tuning.elite.mods;
  const idx = info.section > 1 ? Infinity : info.indexInSection;
  const pool = Object.keys(mods).filter((m) => (mods[m].minIndex ?? 1) <= idx && !(mods[m].excludeKinds ?? []).includes(kind));
  return pick(game.rng.gen, pool) ?? null;
}

/**
 * Comportement temporel des modificateurs, à chaque image où l'élite vit (même étourdi :
 * l'étourdissement INTERROMPT une canalisation d'invocateur). Appelé par enemies.mjs.
 */
export function updateEliteMod(game, e, dt) {
  if (e.leechFlash > 0) e.leechFlash = Math.max(0, e.leechFlash - dt);
  const m = game.tuning.elite.mods[e.eliteMod];
  if (!m) return;
  if (e.modPhase === undefined) {
    e.modPhase = 'idle';
    e.modT = m.firstDelay ?? 0;
    e.modDur = 0;
  }
  if (e.eliteMod === 'bouclier') shieldTick(e, m, dt);
  else if (e.eliteMod === 'invocateur') summonTick(game, e, m, dt);
}

/** Bouclier : repos -> anneau d'annonce (warn) -> bulle d'immunité (duration) -> repos. */
function shieldTick(e, m, dt) {
  e.modT -= dt;
  if (e.modPhase === 'up') e.invuln = Math.max(0, e.modT);
  if (e.modT > 0) return;
  if (e.modPhase === 'idle') {
    e.modPhase = 'warn';
    e.modT = m.warn;
    e.modDur = m.warn;
  } else if (e.modPhase === 'warn') {
    e.modPhase = 'up';
    e.modT = m.duration;
    e.modDur = m.duration;
    e.invuln = m.duration;
  } else {
    e.modPhase = 'idle';
    e.modT = m.every;
    e.modDur = 0;
    e.invuln = 0;
  }
}

/** Invocateur : repos -> canalisation (alerte inoffensive) -> cercles d'invocation -> repos. */
function summonTick(game, e, m, dt) {
  if (e.stun > 0) {
    // Étourdi : la canalisation est perdue (contre-jeu), le cycle repart de zéro.
    if (e.modPhase === 'channel') {
      e.modPhase = 'idle';
      e.modT = m.every;
      e.modDur = 0;
    }
    return;
  }
  e.modT -= dt;
  if (e.modT > 0) return;
  if (e.modPhase === 'channel') {
    summonAround(game, e, m.kind, Math.min(m.count, summonRoom(game)), m.summonMinR, m.summonMaxR, m.summonMinPlayerDist);
    e.modPhase = 'idle';
    e.modT = m.every;
    e.modDur = 0;
    return;
  }
  if (summonRoom(game) <= 0) {
    e.modT = m.retry; // plafond atteint : réessaie un peu plus tard
    return;
  }
  e.modPhase = 'channel';
  e.modT = m.channel;
  e.modDur = m.channel;
  emit(game, 'enemyAttack', { id: e.id, x: e.x, y: e.y, enemy: 'summon' });
}

/**
 * Vampirique : `src` (l'ennemi qui a porté le coup) vient d'infliger `dealt` PV au héros.
 * Sans effet pour un autre modificateur, un ennemi mort ou un coup esquivé (dealt = 0).
 */
export function foeDealt(game, src, dealt) {
  if (!src || src.dead || src.eliteMod !== 'vampirique' || !(dealt > 0)) return;
  const m = game.tuning.elite.mods.vampirique;
  src.leechFlash = m.flash;
  src.hp = Math.min(src.maxHp, src.hp + Math.round(dealt * m.leech));
}

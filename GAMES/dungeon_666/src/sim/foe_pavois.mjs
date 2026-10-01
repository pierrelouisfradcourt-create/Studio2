// GARDE DE FACE — « Porte-pavois » (kind 'pavois'). Données : tuning.enemies.pavois (foe_data.mjs).
//
// Il porte un pavois tourné vers `e.face` (angle, rad). De FACE, dans l'arc `guardArc`, les coups
// d'arme et la compétence ne portent pas (foe_defense.frontBlocked, lu par combat.damageEnemy) ;
// de dos et de flanc, tout passe.
//
// Machine d'états :
//   chase   — marche vers le héros et PIVOTE vers lui, lentement (turnRate rad/s) ; arme son coup
//             quand le héros est à portée ET devant lui, si un jeton de mêlée est libre.
//   windup  — face VERROUILLÉE ; télégraphe rouge en secteur (e.tele cone + area : tout le secteur
//             frappe d'un bloc à la fin de la jauge). Passer dans son dos sort du secteur.
//   recover — face toujours verrouillée, pavois ÉCARTÉ (foe_defense.guardUp est faux) : fenêtre de
//             punition, de n'importe quel côté.
// L'étourdir (mur, gadget, Super) baisse le pavois et annule le coup. Aucun dégât de contact.

import * as TRIG from '../core/trig.mjs'; // sinus, cosinus… déterministes : jamais Math.sin & co dans la simulation
import { angleDiff, clamp, inSector } from '../core/math.mjs';
import { newId } from './state.mjs';
import { damagePlayer } from './combat.mjs';
import { emit, setState, toPlayer, steer, speedOf, windupOf, activeAttackers } from './ai_common.mjs';

/** Portée du coup de pavois (un champion, plus gros, frappe plus loin : comme la Brute). */
function bashRange(game, e, def) {
  return def.bashRange * (e.eliteMod ? game.tuning.elite.sizeMult : 1);
}

function chase(game, e, def, dt) {
  const p = game.player;
  const tp = toPlayer(game, e);
  // Il pivote vers le héros, jamais plus vite que turnRate : un dash le prend de vitesse.
  const want = TRIG.atan2(tp.dy, tp.dx);
  const turn = def.turnRate * dt;
  e.face += clamp(angleDiff(e.face, want), -turn, turn);
  const facing = Math.abs(angleDiff(e.face, want)) <= def.bashArc / 2;
  if (tp.d < def.attackRange + p.r && facing && e.cooldown <= 0 && activeAttackers(game) < game.tuning.combat.maxAttackers) {
    setState(e, 'windup');
    e.atkId = newId(game);
    return;
  }
  steer(game, e, p.x, p.y, speedOf(game, e, def));
}

function windup(game, e, def) {
  const p = game.player;
  const w = windupOf(game, e, def.windup);
  const range = bashRange(game, e, def);
  e.tele = { shape: 'cone', area: true, angle: e.face, range, arc: def.bashArc, progress: e.stateTime / w };
  if (e.stateTime < w) return;
  e.tele = null;
  emit(game, 'enemyAttack', { id: e.id, x: e.x, y: e.y, enemy: e.kind });
  if (inSector(p.x, p.y, e.x, e.y, range, e.face, def.bashArc, p.r)) {
    damagePlayer(game, def.damage * e.dmgScale, { kind: 'pavois', id: e.atkId, x: e.x, y: e.y });
  }
  setState(e, 'recover');
}

function pavoisAI(game, e, def, dt) {
  if (e.face === undefined) {
    // Première image : il fait face au héros.
    const tp = toPlayer(game, e);
    e.face = TRIG.atan2(tp.dy, tp.dx);
  }
  switch (e.state) {
    case 'chase':
      chase(game, e, def, dt);
      break;
    case 'windup':
      windup(game, e, def);
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
}

export const PAVOIS = { kind: 'pavois', ai: pavoisAI, melee: true };

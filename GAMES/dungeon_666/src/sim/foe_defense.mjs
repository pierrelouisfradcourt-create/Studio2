// DÉFENSES d'archétypes lues par combat.damageEnemy (module feuille : n'importe rien de la sim,
// pour que combat.mjs reste sans import circulaire). Données : tuning.enemies[kind] (foe_data.mjs).
//
//   PAVOIS (Porte-pavois) — tout archétype qui déclare `guardArc` : un coup d'arme ou de
//     compétence (def.guardSources) qui arrive DE FACE, dans l'arc `guardArc` autour de `e.face`,
//     ne porte pas. Le pavois est baissé quand son porteur est étourdi, et écarté pendant la
//     récupération de son propre coup (état 'recover') : là, tout passe.
//   ÉTENDARD (Porte-étendard) — tout archétype qui déclare `auraRadius` : les AUTRES ennemis
//     (hors Gardiens, hors porte-étendards) à moins de `auraRadius` d'un porteur debout (ni mort,
//     ni étourdi, ni en train d'apparaître) ne prennent que `wardMult` des dégâts.
// Ce que l'écran doit montrer se lit avec les mêmes fonctions : guardUp (pavois levé ?) et
// wardOf (qui protège cet ennemi ?).

import * as TRIG from '../core/trig.mjs'; // sinus, cosinus… déterministes : jamais Math.sin & co dans la simulation

const MIN_DIR = 1e-6; // en deçà, le coup n'a pas de direction (brûlure, éclair) : il n'est pas arrêté

/** Le pavois de `e` est-il levé (porteur ni étourdi, ni en récupération de son coup) ? */
export function guardUp(game, e) {
  if (e.boss) return false;
  const def = game.tuning.enemies[e.kind];
  if (!def || !(def.guardArc > 0) || e.face === undefined) return false;
  return !(e.stun > 0) && e.state !== 'recover';
}

/**
 * Le coup `src` ({kind, dirX, dirY} : direction du coup, de l'attaquant VERS la cible) est-il
 * arrêté par le pavois de `e` ? Vrai s'il arrive de face, dans l'arc de garde.
 */
export function frontBlocked(game, e, src) {
  if (!guardUp(game, e)) return false;
  const def = game.tuning.enemies[e.kind];
  if (!def.guardSources.includes(src.kind)) return false;
  const dx = src.dirX ?? 0;
  const dy = src.dirY ?? 0;
  const l = Math.sqrt(dx * dx + dy * dy);
  if (l < MIN_DIR) return false;
  // Le coup vient de la direction opposée à son élan : on la compare à la face du pavois.
  const toward = -(dx * TRIG.cos(e.face) + dy * TRIG.sin(e.face)) / l;
  return toward >= TRIG.cos(def.guardArc / 2);
}

/** Le porte-étendard debout qui couvre `e`, ou null (le premier trouvé : les auras ne se cumulent pas). */
export function wardOf(game, e) {
  if (e.boss) return null;
  const enemies = game.tuning.enemies;
  if (enemies[e.kind]?.auraRadius > 0) return null; // un étendard n'en protège pas un autre
  for (const o of game.enemies) {
    if (o.dead || o.boss || o.spawnT > 0 || o.stun > 0) continue;
    const r = enemies[o.kind]?.auraRadius ?? 0;
    if (!(r > 0)) continue;
    const dx = e.x - o.x;
    const dy = e.y - o.y;
    if (dx * dx + dy * dy < r * r) return o;
  }
  return null;
}

/** Part des dégâts que `e` subit (1 = tout ; `wardMult` sous un étendard). */
export function wardMult(game, e) {
  const o = wardOf(game, e);
  return o ? game.tuning.enemies[o.kind].wardMult : 1;
}

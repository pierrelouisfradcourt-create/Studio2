// Briques communes à tous les Gardiens (module feuille, sans import de boss.mjs) : états,
// visée, repos. Chaque modèle de Gardien vit dans son fichier src/sim/boss_<modèle>.mjs.

export function bossDef(game, e) {
  return game.tuning.boss[e.kind];
}

/** Les télégraphes d'un Gardien ne raccourcissent JAMAIS (équité, spec §4.1). */
export function wmult() {
  return 1;
}

export function toPlayer(game, e) {
  const p = game.player;
  const dx = p.x - e.x;
  const dy = p.y - e.y;
  const d = Math.max(1e-6, Math.sqrt(dx * dx + dy * dy));
  return { dx: dx / d, dy: dy / d, d };
}

export function setState(e, s) {
  e.state = s;
  e.stateTime = 0;
  e.patternStep = 0;
  e.patternT = 0;
}

/** Fin de pattern : l'alerte disparaît, le Gardien souffle (fenêtre de punition). */
export function toRest(game, e) {
  e.tele = null;
  setState(e, 'rest');
}

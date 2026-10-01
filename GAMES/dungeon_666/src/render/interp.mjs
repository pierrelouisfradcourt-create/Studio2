// Interpolation de rendu : la simulation avance par pas fixes de 1/60 s, l'écran peut tourner à
// 90, 120 ou 144 Hz. On dessine chaque entité entre sa position avant et après le dernier pas
// (alpha = reste de l'accumulateur / DT) : le mouvement reste fluide à toute fréquence.
//
// La sim n'est JAMAIS modifiée durablement : applyInterp() remplace x/y le temps du dessin,
// restoreInterp() les rétablit avant le pas suivant (appelés dans un try/finally par main).

const JUMP = 150; // u : au-delà (téléportation, changement de salle), pas d'interpolation

function lists(game) {
  return [game.enemies, game.projectiles, game.pickups];
}

/** À appeler juste AVANT chaque stepGame : mémorise la position de départ du pas. */
export function recordPrev(game) {
  const p = game.player;
  p.px = p.x;
  p.py = p.y;
  for (const arr of lists(game)) {
    for (const e of arr) {
      e.px = e.x;
      e.py = e.y;
    }
  }
}

const touched = [];

function lerpInto(e, alpha) {
  if (e.px === undefined) return;
  const dx = e.x - e.px;
  const dy = e.y - e.py;
  if (dx * dx + dy * dy > JUMP * JUMP) return;
  e.cx = e.x;
  e.cy = e.y;
  e.x = e.px + dx * alpha;
  e.y = e.py + dy * alpha;
  touched.push(e);
}

export function applyInterp(game, alpha) {
  touched.length = 0;
  lerpInto(game.player, alpha);
  for (const arr of lists(game)) for (const e of arr) lerpInto(e, alpha);
}

export function restoreInterp() {
  for (const e of touched) {
    e.x = e.cx;
    e.y = e.cy;
  }
  touched.length = 0;
}

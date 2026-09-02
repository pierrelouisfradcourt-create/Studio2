// PONG — input (LOGIQUE PURE).
// Fournit input.action (traduire une entree joueur en action) et error.guard
// (une entree invalide ne casse jamais l'etat de jeu).
// GARDE-FOU (d) : aucune I/O ; ne lit pas le clavier, ne connait aucun adaptateur.
// L'adaptateur (browser/godot) collecte l'entree brute et appelle translate().

// Direction normalisee d'une raquette : -1 (haut), 0 (immobile), +1 (bas).
// Vocabulaire d'entree FERME. Tout le reste est ramene a une valeur sure.
const UP = 'up';
const DOWN = 'down';

// error.guard, coeur du contrat : quelle que soit l'entree brute (nulle, hors
// domaine, repetee, simultanee), renvoie TOUJOURS une direction valide de {-1,0,1}.
// Simultane haut+bas => 0 (les deux s'annulent, jamais un etat casse).
function dirFor(raw) {
  if (raw === UP) return -1;
  if (raw === DOWN) return 1;
  if (raw && typeof raw === 'object') {
    const up = raw.up === true || raw[UP] === true;
    const down = raw.down === true || raw[DOWN] === true;
    if (up && down) return 0;   // simultane : neutralise
    if (up) return -1;
    if (down) return 1;
    return 0;
  }
  return 0;   // null, undefined, nombre, chaine inconnue, booleen... => immobile
}

// input.action — traduit l'entree brute des DEUX joueurs en action normalisee.
// Ne leve jamais : une entree totalement invalide donne l'action neutre {0,0}.
export function translate(raw) {
  if (!raw || typeof raw !== 'object') return { p1: 0, p2: 0 };
  return { p1: dirFor(raw.p1), p2: dirFor(raw.p2) };
}

// Applique une action normalisee a une raquette et BORNE le deplacement au terrain
// (play.paddle : ne sort JAMAIS de l'aire de jeu, meme entree maintenue).
// clamp pur — reutilise par le loop.
export function clampPaddle(y, minY, maxY) {
  if (y < minY) return minY;
  if (y > maxY) return maxY;
  return y;
}

export { dirFor, UP, DOWN };

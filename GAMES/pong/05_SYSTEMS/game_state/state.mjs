// PONG — game_state (LOGIQUE PURE).
// Fournit game.state / game.end / game.restart.
// GARDE-FOU (d) : aucun rendu, aucune I/O, aucun temps reel, aucun alea non seede.
// L'etat est un objet simple, entierement deterministe.

// --- constantes de terrain (unites logiques, pas des pixels) ---
export const FIELD_W = 200;
export const FIELD_H = 120;
export const PADDLE_H = 24;
export const PADDLE_W = 4;
export const PADDLE_SPEED = 4;
export const BALL_R = 2;
// BALL_VX abaisse de 3 -> 1.25 (play.playable_speed, playtest-2026-07-27) : a 3, la
// balle traversait le centre->raquette en ~0.52 s (aucun temps de reaction). A 1.25,
// le temps de traversee de service tombe dans la bande jouable de la Genre Bible
// (genre.pong.playable_speed_range : 1.0-1.5 s). Verifie MECANIQUEMENT depuis les
// constantes par ballCrossingTimeSeconds() (game_loop) + 07_TESTS/unit/playable_speed.test.mjs.
export const BALL_VX = 1.25;  // vitesse horizontale de service (bande jouable)
export const BALL_VY = 2;   // vitesse verticale de service
export const P1_X = 6;      // face droite de la raquette gauche (x du plan de collision)
export const P2_X = FIELD_W - 6; // face gauche de la raquette droite
export const WIN_SCORE = 3;

// Les SEULES valeurs que `status` peut prendre (SCHEMA core.game_state :
// "ne prend que des valeurs declarees").
export const STATUS = Object.freeze({
  PLAYING: 'PLAYING',
  P1_WIN: 'P1_WIN',
  P2_WIN: 'P2_WIN',
});
const STATUS_VALUES = Object.freeze(Object.values(STATUS));

// Direction de service DETERMINISTE : depend du seed et du nombre de points deja
// marques (parite). Aucun Math.random. seed=+1 sert vers la droite au premier point.
function serveVx(seed, pointsPlayed) {
  const dir = (pointsPlayed % 2 === 0) ? seed : -seed;
  return dir >= 0 ? BALL_VX : -BALL_VX;
}

// Etat initial PROPRE. `seed` (+1/-1) rend le service reproductible.
export function initialState(seed = 1) {
  const s = seed >= 0 ? 1 : -1;
  return {
    seed: s,
    p1: { y: (FIELD_H - PADDLE_H) / 2 },
    p2: { y: (FIELD_H - PADDLE_H) / 2 },
    ball: { x: FIELD_W / 2, y: FIELD_H / 2, vx: serveVx(s, 0), vy: BALL_VY },
    score: { p1: 0, p2: 0 },
    status: STATUS.PLAYING,
  };
}

// game.state — lecture du statut nomme, a tout instant.
export function readStatus(state) {
  return state.status;
}

export function isValidStatus(status) {
  return STATUS_VALUES.includes(status);
}

// Un etat est structurellement VALIDE : bornes des raquettes, score entier >= 0,
// statut declare, balle dans le terrain (au rayon pres, tolerance de service).
export function isValidState(state) {
  if (!state || typeof state !== 'object') return false;
  if (!isValidStatus(state.status)) return false;
  for (const p of ['p1', 'p2']) {
    const y = state[p]?.y;
    if (typeof y !== 'number' || Number.isNaN(y)) return false;
    if (y < 0 || y > FIELD_H - PADDLE_H) return false;
  }
  for (const who of ['p1', 'p2']) {
    const v = state.score?.[who];
    if (!Number.isInteger(v) || v < 0) return false;
  }
  const b = state.ball;
  if (!b || typeof b.x !== 'number' || typeof b.y !== 'number') return false;
  if (Number.isNaN(b.x) || Number.isNaN(b.y)) return false;
  if (b.y < 0 || b.y > FIELD_H) return false;
  return true;
}

// game.end — la partie se termine quand un camp atteint WIN_SCORE. Issue toujours
// definie (jamais indefinie) : renvoie STATUS.PLAYING tant que personne n'a gagne.
export function endStatus(score) {
  if (score.p1 >= WIN_SCORE) return STATUS.P1_WIN;
  if (score.p2 >= WIN_SCORE) return STATUS.P2_WIN;
  return STATUS.PLAYING;
}

export function isOver(state) {
  return state.status === STATUS.P1_WIN || state.status === STATUS.P2_WIN;
}

// game.restart — nouvel etat initial PROPRE (aucun residu). Identite bit-a-bit
// avec un premier demarrage de meme seed.
export function restart(seed = 1) {
  return initialState(seed);
}

export { serveVx };

// Bots de playtest headless : des « joueurs » automatiques qui produisent un InputFrame à
// partir de ce qu'un joueur VOIT à l'écran — positions, télégraphes (e.tele), zones de
// danger (game.hazards), projectiles et mouvements des ennemis. Ils ne lisent JAMAIS le RNG
// de la partie ni les compteurs cachés des ennemis (cooldowns, durées de windup) : le temps
// restant d'un télégraphe est estimé à partir de la vitesse de remplissage observée de sa
// jauge, comme le ferait l'œil. Ils connaissent en revanche leur propre héros (portée,
// vitesse, dash), comme un joueur qui a pris le jeu en main.
//
//   import { POLICIES, resolveChoice } from './bots.mjs';
//   const mem = {};                                  // mémoire libre, une par partie
//   if (game.mode === 'choice') resolveChoice(game, 'skilled');
//   stepGame(game, POLICIES.skilled(game, mem));
//
// Politiques :
//   skilled — joue bien : lit les télégraphes, esquive au dernier moment (marche ou dash),
//             punit les béliers sonnés, gère compétence / gadget / Super.
//   noDash  — identique mais n'utilise JAMAIS le dash ni le gadget : mesure la valeur du dash.
//   masher  — fonce sur l'ennemi le plus proche et tape sans arrêt, dash aléatoire rare.

import { DT, emptyInput, applyCommand } from '../src/sim/game.mjs';
import { hazardProgress } from '../src/sim/projectiles.mjs';
import { pointSegDist2, dist2, clamp } from '../src/core/math.mjs';

// ---------------------------------------------------------------- constantes de jeu du bot

const SAMPLE_HZ = 30; // résolution temporelle de l'anticipation
const REACTION_TIME = 0.15; // s : un danger n'est « vu » qu'après ce délai (réflexe humain)
const HORIZON = 0.7; // s d'anticipation des menaces
const SAMPLES = Math.round(HORIZON * SAMPLE_HZ);
const DIRECTION_COUNT = 16; // directions candidates pour marcher / dasher
const DASH_TRIGGER = 0.25; // s : on dashe quand l'impact est plus proche que ça
const GADGET_TRIGGER = 0.2; // s : gadget en dernier recours (sans charge de dash)
const TELE_IMMINENT_PROGRESS = 0.6; // jauge de télégraphe « presque pleine »
const DEFAULT_WINDUP_GUESS = 0.7; // s, durée supposée d'un télégraphe avant d'avoir sa vitesse
const IMMINENT_GUESS = 0.1; // s restantes supposées pour une jauge presque pleine jamais mesurée
const MIN_RATE_WINDOW = 0.05; // s d'observation avant de faire confiance à la vitesse de jauge
const ZONE_SLACK = 0.07; // s de marge avant l'impact d'une zone
const FRAME_SPAN = 1 / SAMPLE_HZ;
const LUNGE_TIME = 0.15; // s : durée d'une ruée de diablotin (vue à l'écran)
const CHARGE_SPAN = 0.5; // s pendant lesquels une charge en ligne reste dangereuse
const ARROW_SPAN = 0.6; // s pendant lesquels une ligne d'archer reste dangereuse
const SAFETY_MARGIN = 4; // u ajoutées au rayon du héros dans les tests de zone
const MOVER_PAD = 8; // u : portée de contact d'un ennemi lancé (ruée, charge)
const PROJECTILE_PAD = 3; // u de marge autour des projectiles
const FAST_MOVER_SPEED = 350; // u/s : au-delà, un ennemi « fonce » (ruée, charge)
const PROJECTILE_ALERT_PAD = 60; // u : préfiltre des projectiles qui passeront près
const WALL_COMFORT = 70; // u : finir un mouvement près d'un mur est pénalisé
const WALL_PENALTY = 0.35;
const DANGER_WEIGHT = 100;
const DEPTH_BASE = 0.5; // poids d'un coup reçu, + sa profondeur dans la zone (0..1)
const ARROW_LINE_PAD = 80; // u : on prolonge la ligne d'archer au-delà du héros (la flèche vole)
const COMMIT_TIME = 0.25; // s : on garde une direction d'esquive (évite les hésitations)
const COMMIT_MIN = 0.12; // s minimum d'une esquive avant de revenir au plan
const DASH_CANCEL_MARGIN = 0.1; // s : avec un dash en poche, on frappe jusqu'au dernier moment

const STANDOFF_GAP = 18; // u entre les bords du héros et de sa cible
const REACH_MARGIN = 6; // u retirées à la portée du coup 1 pour attaquer « sûr »
const PUNISH_BONUS = 220; // priorité d'une cible sonnée (u équivalentes)
const ARCHER_BONUS = 50;
const EXPLODER_BONUS = 40;
const AVOID_PENALTY = 500; // une brute qui frappe ou un possédé qui gonfle : on s'écarte
const STICKY_BONUS = 35; // garder la même cible évite les hésitations
const RETREAT_DIST = 170; // u : distance de recul face à une menace de zone
const GADGET_CROWD = 3;
const GADGET_LOW_HP = 0.35;
const GADGET_MIN_GAP = 1.0; // s entre deux gadgets offensifs
const SUPER_CROWD = 2;
const SUPER_LOW_HP = 0.4;
const SUPER_REACH_PAD = 20;
const LANCE_BOSS_WEIGHT = 3; // un boss aligné vaut trois ennemis pour la Lance

const PICKUP_WINDOW = 5; // s passées à ramasser l'or après le combat
const SPAWN_WAIT_DIST = 160; // u : on attend la vague à cette distance des cercles d'invocation
const NAV_MARGIN = 2; // u ajoutées au rayon pour les tests de passage
const NAV_CORNER = 16; // u de marge autour des coins d'obstacle
const ARRIVE_DIST = 6;
const BLOCKED_CORNER_COST = 400; // u : un coin qu'on ne voit pas directement coûte un détour
const MOVE_INTENT_MIN2 = 0.25; // norme² minimale d'une intention de marche (détection de blocage)
const IDLE_MOVE_COST = 0.2; // sans intention, bouger coûte un peu plus que rester
const PROJECTILE_ALERT_LEAD = 0.1; // s de trajet ajoutées au préfiltre des projectiles
const STUCK_WINDOW = 0.75; // s
const STUCK_DIST = 14; // u parcourues en moins => coincé
const UNSTICK_TIME = 0.35; // s de déplacement latéral pour se décoincer

const MASHER_DASH_CHANCE = 0.0025; // par image (~ un dash toutes les 7 s)
const MASHER_CONTACT_GAP = 10;
const LOW_HP_SHOP = 0.6; // achète le soin sous 60 % de PV
const HEAL_DOOR_HP = 0.5;
const ELITE_DOOR_HP = 0.75;

// Préférences de porte (bonus additif, + un bruit déterministe pour varier les runs).
const DOOR_PREFS = { boon: 3, loot: 2.5, event: 2, elite: 1.6, gold: 1.2, heal: 0.6, shop: 1.5, boss: 10 };
const DOOR_NOISE = 1.2;
const DOOR_URGENT_HEAL = 4; // blessé : la porte de soin passe devant tout
const DOOR_URGENT_SHOP = 2;
const DOOR_ELITE_RISK = 2; // blessé : on évite les élites
const U32 = 4294967296;

const DIRS = Array.from({ length: DIRECTION_COUNT }, (_, i) => {
  const a = (i / DIRECTION_COUNT) * Math.PI * 2;
  return { x: Math.cos(a), y: Math.sin(a) };
});

// ---------------------------------------------------------------- utilitaires

/** Hachage entier déterministe (variété des choix sans toucher au RNG de la partie). */
function mixHash(...values) {
  let h = 2166136261;
  for (const v of values) h = Math.imul(h ^ (v >>> 0), 16777619) >>> 0;
  h ^= h >>> 15;
  return Math.imul(h, 2246822519) >>> 0;
}

/**
 * RNG local au bot (mulberry32), dérivé de la graine : n'avance jamais celui de la partie.
 * L'état est exposé (`rng.state`) pour que la mémoire du bot reste clonable (audit des dash).
 */
function makeRng(seed) {
  const state = { s: seed >>> 0 };
  const rng = () => {
    state.s = (state.s + 0x6d2b79f5) >>> 0;
    let t = state.s;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / U32;
  };
  rng.state = state;
  return rng;
}

/**
 * Copie indépendante de la mémoire d'un bot : sert à rejouer une même situation depuis un
 * clone de la partie (audit contrefactuel des dash) sans perturber la partie réelle.
 */
export function cloneMemory(mem) {
  if (!mem.ready) return {};
  const copyMap = (m) => new Map([...m].map(([k, v]) => [k, { ...v }]));
  return { ...mem, rng: makeRng(mem.rng.state.s), motion: copyMap(mem.motion), tele: copyMap(mem.tele), buf: new Float64Array(mem.buf) };
}

function norm(x, y) {
  const l = Math.sqrt(x * x + y * y);
  return l > 1e-6 ? { x: x / l, y: y / l, l } : { x: 0, y: 0, l: 0 };
}

function ensureMem(game, mem, salt) {
  if (mem.ready) return mem;
  mem.ready = true;
  mem.rng = makeRng(mixHash(game.seed, salt));
  mem.motion = new Map(); // id -> {x, y, t, vx, vy} : mouvement observé
  mem.tele = new Map(); // id -> {p0, t0, shape} : début d'observation d'une jauge
  mem.buf = new Float64Array((SAMPLES + 1) * 2);
  mem.targetId = 0;
  mem.doorFloor = -1;
  mem.door = 0;
  mem.lastGadget = -Infinity;
  mem.evadeUntil = -1;
  mem.evadeStart = -1;
  mem.evadeX = 0;
  mem.evadeY = 0;
  mem.stuckX = 0;
  mem.stuckY = 0;
  mem.stuckT = 0;
  mem.unstickT = 0;
  mem.unstickX = 0;
  mem.unstickY = 0;
  mem.unstickSign = 1;
  mem.floor = -1;
  return mem;
}

function onNewFloor(game, mem) {
  if (mem.floor === game.run.floor && mem.roomRef === game.room) return;
  mem.floor = game.run.floor;
  mem.roomRef = game.room;
  mem.motion.clear();
  mem.tele.clear();
  mem.targetId = 0;
}

function visibleEnemies(game) {
  return game.enemies.filter((e) => !e.dead && e.spawnT <= 0);
}

function distTo(p, o) {
  return Math.sqrt(dist2(p.x, p.y, o.x, o.y));
}

// ---------------------------------------------------------------- géométrie et navigation

/** Le segment [a, b] traverse-t-il le rectangle (méthode des dalles) ? */
function segHitsRect(ax, ay, bx, by, x0, y0, x1, y1) {
  let tmin = 0;
  let tmax = 1;
  const dx = bx - ax;
  const dy = by - ay;
  for (const [o, d, lo, hi] of [[ax, dx, x0, x1], [ay, dy, y0, y1]]) {
    if (Math.abs(d) < 1e-9) {
      if (o < lo || o > hi) return false;
    } else {
      let t1 = (lo - o) / d;
      let t2 = (hi - o) / d;
      if (t1 > t2) [t1, t2] = [t2, t1];
      tmin = Math.max(tmin, t1);
      tmax = Math.min(tmax, t2);
      if (tmin > tmax) return false;
    }
  }
  return true;
}

function firstBlocker(room, ax, ay, bx, by, margin) {
  let best = null;
  let bestD = Infinity;
  for (const o of room.obstacles) {
    if (!segHitsRect(ax, ay, bx, by, o.x0 - margin, o.y0 - margin, o.x1 + margin, o.y1 + margin)) continue;
    const d = dist2(ax, ay, (o.x0 + o.x1) / 2, (o.y0 + o.y1) / 2);
    if (d < bestD) {
      bestD = d;
      best = o;
    }
  }
  return best;
}

/** Ligne de tir dégagée (aucun obstacle sur le segment). */
function clearShot(room, ax, ay, bx, by) {
  return firstBlocker(room, ax, ay, bx, by, 0) === null;
}

/** Direction de marche vers (tx, ty) en contournant un obstacle par le meilleur coin. */
function navDir(room, px, py, tx, ty, r) {
  const margin = r + NAV_MARGIN;
  const o = firstBlocker(room, px, py, tx, ty, margin);
  if (!o) return norm(tx - px, ty - py);
  const c = r + NAV_CORNER;
  const corners = [[o.x0 - c, o.y0 - c], [o.x1 + c, o.y0 - c], [o.x0 - c, o.y1 + c], [o.x1 + c, o.y1 + c]];
  let best = null;
  let bestCost = Infinity;
  for (const [cx, cy] of corners) {
    const leg = Math.sqrt(dist2(px, py, cx, cy));
    if (leg < ARRIVE_DIST) continue;
    const direct = firstBlocker(room, px, py, cx, cy, margin) === null;
    const cost = leg + Math.sqrt(dist2(cx, cy, tx, ty)) + (direct ? 0 : BLOCKED_CORNER_COST);
    if (cost < bestCost) {
      bestCost = cost;
      best = [cx, cy];
    }
  }
  return best ? norm(best[0] - px, best[1] - py) : norm(tx - px, ty - py);
}

function insideObstacle(room, x, y, r) {
  for (const o of room.obstacles) {
    if (x > o.x0 - r && x < o.x1 + r && y > o.y0 - r && y < o.y1 + r) return true;
  }
  return false;
}

function wallPenalty(room, x, y) {
  const m = Math.min(x - room.pad, room.w - room.pad - x, y - room.pad, room.h - room.pad - y);
  return m < WALL_COMFORT ? WALL_PENALTY * (1 - m / WALL_COMFORT) : 0;
}

// ---------------------------------------------------------------- perception

/** Vitesse observée des ennemis (différence de positions), comme un œil qui suit le sprite. */
function trackMotion(game, mem) {
  for (const e of game.enemies) {
    if (e.dead) continue;
    const o = mem.motion.get(e.id);
    if (!o) {
      mem.motion.set(e.id, { x: e.x, y: e.y, t: game.time, vx: 0, vy: 0 });
      continue;
    }
    const dt = game.time - o.t;
    if (dt > 1e-6) {
      o.vx = (e.x - o.x) / dt;
      o.vy = (e.y - o.y) / dt;
      o.x = e.x;
      o.y = e.y;
      o.t = game.time;
    }
  }
}

/** Temps restant estimé d'un télégraphe, d'après la vitesse de remplissage de sa jauge. */
function teleRemaining(game, mem, e) {
  const prog = e.tele.progress;
  let rec = mem.tele.get(e.id);
  if (!rec || prog < rec.p0 - 1e-6 || rec.shape !== e.tele.shape) {
    rec = { p0: prog, t0: game.time, shape: e.tele.shape };
    mem.tele.set(e.id, rec);
  }
  const elapsed = game.time - rec.t0;
  if (elapsed >= MIN_RATE_WINDOW && prog > rec.p0) {
    const rate = (prog - rec.p0) / elapsed;
    return Math.max(0, (1 - prog) / rate);
  }
  // Pas encore de mesure : jauge presque pleine = imminent.
  return prog > TELE_IMMINENT_PROGRESS ? IMMINENT_GUESS : (1 - prog) * DEFAULT_WINDUP_GUESS;
}

function zone(test, t0, t1) {
  return { type: 'zone', test, t0: Math.max(0, t0), t1 };
}

/** Profondeur (0..1) d'un point dans un disque de rayon `rr` ; 0 = dehors. */
function discDepth(x, y, cx, cy, rr) {
  const d2 = dist2(x, y, cx, cy);
  return d2 < rr * rr ? 1 - Math.sqrt(d2) / rr : 0;
}

function segDepth(x, y, ax, ay, bx, by, hw) {
  const d2 = pointSegDist2(x, y, ax, ay, bx, by);
  return d2 < hw * hw ? 1 - Math.sqrt(d2) / hw : 0;
}

/**
 * Temps restant d'une zone, lu sur ce que montre l'écran : sa jauge (hazardProgress, celle
 * que dessine le rendu) et le temps écoulé depuis son apparition. Jauge linéaire : la règle
 * de trois donne le temps restant sans lire la durée cachée du télégraphe.
 */
function hazardRemaining(h) {
  const prog = hazardProgress(h);
  return prog >= 1 ? 0 : (h.t * (1 - prog)) / prog;
}

function hazardThreat(h, r) {
  if (h.done || !h.hitsPlayer || h.t < REACTION_TIME) return null;
  const tI = Math.max(0, hazardRemaining(h));
  if (tI > HORIZON) return null;
  let test;
  if (h.shape === 'circle') test = (x, y) => discDepth(x, y, h.x, h.y, h.r + r);
  else if (h.shape === 'ring') {
    test = (x, y) => {
      const d = Math.sqrt(dist2(x, y, h.x, h.y));
      return d < h.r + r && d > h.inner - r ? 1 - Math.abs(d - (h.r + h.inner) / 2) / ((h.r - h.inner) / 2 + r) : 0;
    };
  } else {
    const ex = h.x + Math.cos(h.angle) * h.length;
    const ey = h.y + Math.sin(h.angle) * h.length;
    test = (x, y) => segDepth(x, y, h.x, h.y, ex, ey, h.width / 2 + r);
  }
  return zone(test, tI - ZONE_SLACK, tI + FRAME_SPAN);
}

/** Ruée télégraphiée par un cône : le corps de l'ennemi file le long de l'axe du cône. */
function lungeThreat(e, tele, tI, r) {
  return {
    type: 'lunge', x: e.x, y: e.y, dx: Math.cos(tele.angle), dy: Math.sin(tele.angle),
    len: Math.max(0, tele.range - e.r), t0: tI, rad: e.r + r + MOVER_PAD,
  };
}

function lineThreat(game, e, tele, tI, r) {
  let length = tele.length;
  if (e.kind === 'archer') {
    // La ligne d'un archer est courte, mais la flèche vole au-delà : on l'extrapole.
    length = Math.max(length, distTo(game.player, e) + ARROW_LINE_PAD);
  }
  const ex = e.x + Math.cos(tele.angle) * length;
  const ey = e.y + Math.sin(tele.angle) * length;
  const hw = tele.width / 2 + r;
  const span = e.kind === 'archer' ? ARROW_SPAN : CHARGE_SPAN;
  return zone((x, y) => segDepth(x, y, e.x, e.y, ex, ey, hw), tI - ZONE_SLACK, tI + span);
}

function teleThreat(game, mem, e, r) {
  const tele = e.tele;
  const tI = teleRemaining(game, mem, e);
  if (tI > HORIZON || game.time - mem.tele.get(e.id).t0 < REACTION_TIME) return null;
  if (tele.shape === 'cone') return lungeThreat(e, tele, tI, r);
  if (tele.shape === 'line') return lineThreat(game, e, tele, tI, r);
  // Cercle : celui du possédé (explosion) et ceux du boss (anneau de projectiles qui naît dans
  // le cercle) font mal ; l'alerte d'invocation est marquée inoffensive.
  if (tele.harmless || (e.kind !== 'exploder' && !e.boss)) return null;
  return zone((x, y) => discDepth(x, y, e.x, e.y, tele.r + r), tI - ZONE_SLACK, tI + FRAME_SPAN);
}

function moverThreat(mem, e, r) {
  const m = mem.motion.get(e.id);
  if (!m || m.vx * m.vx + m.vy * m.vy < FAST_MOVER_SPEED * FAST_MOVER_SPEED) return null;
  return { type: 'mover', x: e.x, y: e.y, vx: m.vx, vy: m.vy, rad: e.r + r + MOVER_PAD };
}

function projectileThreat(pr, p) {
  const v2 = pr.vx * pr.vx + pr.vy * pr.vy;
  if (v2 > 1e-6 && pr.traveled / Math.sqrt(v2) < REACTION_TIME) return null; // pas encore vu
  const rad = pr.r + p.r + PROJECTILE_PAD;
  // Préfiltre : point le plus proche de la trajectoire dans l'horizon.
  const rx = pr.x - p.x;
  const ry = pr.y - p.y;
  const tc = v2 > 1e-6 ? clamp(-(rx * pr.vx + ry * pr.vy) / v2, 0, HORIZON) : 0;
  const cx = rx + pr.vx * tc;
  const cy = ry + pr.vy * tc;
  const alert = rad + PROJECTILE_ALERT_PAD + Math.sqrt(v2) * PROJECTILE_ALERT_LEAD;
  if (cx * cx + cy * cy > alert * alert) return null;
  return { type: 'mover', x: pr.x, y: pr.y, vx: pr.vx, vy: pr.vy, rad };
}

/** Toutes les menaces visibles qui peuvent frapper dans l'horizon. */
function perceiveThreats(game, mem) {
  const p = game.player;
  const r = p.r + SAFETY_MARGIN;
  const out = [];
  for (const h of game.hazards) {
    const th = hazardThreat(h, r);
    if (th) out.push(th);
  }
  for (const e of game.enemies) {
    if (e.dead || e.spawnT > 0) continue;
    if (e.tele) {
      const th = teleThreat(game, mem, e, r);
      if (th) out.push(th);
    } else {
      mem.tele.delete(e.id);
    }
    const mv = moverThreat(mem, e, p.r);
    if (mv) out.push(mv);
  }
  for (const pr of game.projectiles) {
    if (pr.owner !== 'enemy' || pr.dead) continue;
    const th = projectileThreat(pr, p);
    if (th) out.push(th);
  }
  return out;
}

// ---------------------------------------------------------------- anticipation (planner)

/** Temps pendant lequel le héros reste freiné par son action en cours (attaque, lancer). */
function lockRemaining(p) {
  if (p.state === 'attack' && p.attack) {
    const a = p.attack;
    const d = a.dur;
    if (a.phase === 'startup') return d.startup - a.t + d.active + d.recovery;
    if (a.phase === 'active') return d.active - a.t + d.recovery;
    return Math.max(0, d.recovery - a.t);
  }
  if (p.state === 'cast') return p.castT;
  return 0;
}

function invulnerability(p) {
  return p.state === 'super' ? Math.max(p.iframes, p.superT) : p.iframes;
}

/** Trajectoire échantillonnée du héros (x, y tous les 1/SAMPLE_HZ s) pour un geste donné. */
function simulateMove(game, out, dx, dy, lockT, dash) {
  const p = game.player;
  const t = game.tuning;
  const room = game.room;
  const run = t.player.speed * p.stats.moveSpeedMult;
  const slow = run * t.player.attackMoveMult;
  const dashSpeed = t.dash.distance / t.dash.duration;
  const step = 1 / SAMPLE_HZ;
  const lo = room.pad + p.r;
  let x = p.x;
  let y = p.y;
  for (let k = 0; k <= SAMPLES; k++) {
    out[2 * k] = x;
    out[2 * k + 1] = y;
    const tau = k * step;
    let v = tau < lockT ? slow : run;
    if (dash && tau < t.dash.duration) v = dashSpeed;
    const nx = clamp(x + dx * v * step, lo, room.w - lo);
    const ny = clamp(y + dy * v * step, lo, room.h - lo);
    if (!insideObstacle(room, nx, ny, p.r)) {
      x = nx;
      y = ny;
    }
  }
}

let hitDepth = 0; // profondeur du dernier contact trouvé par threatHitTime (sans allocation)

function lungeCenterDepth(th, x, y, tau) {
  const f = clamp((tau - th.t0) / LUNGE_TIME, 0, 1);
  return discDepth(x, y, th.x + th.dx * th.len * f, th.y + th.dy * th.len * f, th.rad);
}

/** Premier instant (s) où la trajectoire est touchée par la menace, ou -1. */
function threatHitTime(th, traj, invulT) {
  let k0 = 0;
  let k1 = SAMPLES;
  if (th.type === 'zone') {
    k0 = Math.max(0, Math.floor(th.t0 * SAMPLE_HZ));
    k1 = Math.min(SAMPLES, Math.ceil(th.t1 * SAMPLE_HZ));
  } else if (th.type === 'lunge') {
    k0 = Math.max(0, Math.floor((th.t0 - ZONE_SLACK) * SAMPLE_HZ));
    k1 = Math.min(SAMPLES, Math.ceil((th.t0 + LUNGE_TIME) * SAMPLE_HZ));
  }
  for (let k = k0; k <= k1; k++) {
    const tau = k / SAMPLE_HZ;
    if (tau < invulT) continue;
    const x = traj[2 * k];
    const y = traj[2 * k + 1];
    let depth;
    if (th.type === 'zone') depth = th.test(x, y);
    else if (th.type === 'lunge') depth = lungeCenterDepth(th, x, y, tau);
    else depth = discDepth(x, y, th.x + th.vx * tau, th.y + th.vy * tau, th.rad);
    if (depth > 0) {
      hitDepth = depth;
      return tau;
    }
  }
  return -1;
}

function evaluate(traj, threats, invulT) {
  let danger = 0;
  let firstHit = Infinity;
  for (const th of threats) {
    const hit = threatHitTime(th, traj, invulT);
    if (hit < 0) continue;
    // Un coup proche pèse plus lourd ; être au bord de la zone vaut mieux qu'en son cœur.
    danger += (DEPTH_BASE + hitDepth) * (1 + HORIZON - hit);
    firstHit = Math.min(firstHit, hit);
  }
  return { danger, firstHit };
}

/** Balaye les directions (et l'immobilité) ; rend le meilleur geste au sens danger + écart au plan. */
function scanMoves(game, mem, threats, intentDir, lockT, dash, invulT) {
  const room = game.room;
  const buf = mem.buf;
  let best = null;
  const candidates = dash ? DIRS : [...DIRS, { x: 0, y: 0 }];
  for (const d of candidates) {
    simulateMove(game, buf, d.x, d.y, lockT, dash);
    const ev = evaluate(buf, threats, invulT);
    const still = d.x === 0 && d.y === 0;
    const deviation = intentDir.l > 0 ? (still ? 1 : 1 - (d.x * intentDir.x + d.y * intentDir.y)) : still ? 0 : IDLE_MOVE_COST;
    const score = ev.danger * DANGER_WEIGHT + deviation + wallPenalty(room, buf[2 * SAMPLES], buf[2 * SAMPLES + 1]);
    if (!best || score < best.score) best = { x: d.x, y: d.y, score, danger: ev.danger, firstHit: ev.firstHit };
  }
  return best;
}

function canDashNow(game) {
  const p = game.player;
  return p.dashCharges >= 1 && (p.state === 'free' || p.state === 'attack' || p.state === 'cast');
}

function planIsSafe(game, mem, threats, intent, dir, lock, invul, opts) {
  simulateMove(game, mem.buf, dir.x, dir.y, intent.attack ? HORIZON : lock, false);
  const plan = evaluate(mem.buf, threats, invul);
  if (plan.danger === 0) return true;
  // Un dash disponible annule n'importe quelle attaque : on continue de frapper tant que
  // le coup adverse n'est pas imminent (le jeu « attaque puis dash » à la Hades).
  return opts.dash && canDashNow(game) && plan.firstHit > DASH_TRIGGER + DASH_CANCEL_MARGIN;
}

/** Retient une direction d'esquive sûre pour COMMIT_TIME (anti-hésitation). */
function commitEvade(game, mem, walk, committed) {
  if (walk.danger !== 0 || (walk.x === 0 && walk.y === 0)) return;
  if (!committed) mem.evadeStart = game.time;
  mem.evadeUntil = game.time + COMMIT_TIME;
  mem.evadeX = walk.x;
  mem.evadeY = walk.y;
}

/** Aucune marche n'évite le coup imminent : dash (i-frames + distance), sinon gadget. */
function emergencyDodge(game, mem, threats, ref, walk, invul, opts, input) {
  const p = game.player;
  if (opts.dash && canDashNow(game)) {
    const dashInvul = Math.max(invul, game.tuning.dash.iframes);
    const dash = scanMoves(game, mem, threats, ref, 0, true, dashInvul);
    if (dash.danger < walk.danger) {
      input.moveX = dash.x;
      input.moveY = dash.y;
      input.dashPressed = true;
      return input;
    }
  }
  if (opts.gadget && p.gadgetCharges > 0 && walk.firstHit <= GADGET_TRIGGER && p.state !== 'super') {
    input.gadgetPressed = true;
    mem.lastGadget = game.time;
  }
  return input;
}

/**
 * Si le plan courant mène sous un coup : esquive en marchant si possible, sinon dash (au
 * dernier moment), sinon gadget. Rend un InputFrame, ou null si le plan est sûr.
 */
function planEvasion(game, mem, threats, intent, opts) {
  const lock = lockRemaining(game.player);
  const invul = invulnerability(game.player);
  const dir = norm(intent.mx, intent.my);
  const committed = game.time < mem.evadeUntil;
  if (planIsSafe(game, mem, threats, intent, dir, lock, invul, opts)) {
    // Plan sûr : on y revient, sauf esquive toute fraîche (évite d'osciller à chaque image).
    if (!committed || game.time - mem.evadeStart >= COMMIT_MIN) {
      mem.evadeUntil = -1;
      return null;
    }
  }
  // Référence : l'esquive en cours (on ne change pas d'avis à chaque image), sinon le plan.
  const ref = committed ? { x: mem.evadeX, y: mem.evadeY, l: 1 } : dir;
  const walk = scanMoves(game, mem, threats, ref, lock, false, invul);
  commitEvade(game, mem, walk, committed);
  const input = emptyInput();
  input.moveX = walk.x;
  input.moveY = walk.y;
  if (walk.danger === 0 || walk.firstHit > DASH_TRIGGER) return input;
  return emergencyDodge(game, mem, threats, ref, walk, invul, opts, input);
}

// ---------------------------------------------------------------- intention : combat

function isWindingDanger(e) {
  return (e.kind === 'brute' && e.state === 'windup') || (e.kind === 'exploder' && !!e.tele);
}

function pickTarget(game, mem, enemies) {
  const p = game.player;
  let best = null;
  let bestScore = Infinity;
  for (const e of enemies) {
    let score = distTo(p, e) - e.r;
    if (e.stun > 0) score -= PUNISH_BONUS;
    if (e.kind === 'archer') score -= ARCHER_BONUS;
    if (e.kind === 'exploder' && !e.tele) score -= EXPLODER_BONUS;
    if (isWindingDanger(e)) score += AVOID_PENALTY;
    if (e.id === mem.targetId) score -= STICKY_BONUS;
    if (score < bestScore) {
      bestScore = score;
      best = e;
    }
  }
  mem.targetId = best ? best.id : 0;
  return best;
}

/** Meilleure ligne de Lance : le plus d'ennemis alignés, tir dégagé. */
function bestLanceAim(game, enemies) {
  const p = game.player;
  const s = game.tuning.skill;
  let best = null;
  for (const e of enemies) {
    const d = norm(e.x - p.x, e.y - p.y);
    if (d.l > s.range) continue;
    if (!clearShot(game.room, p.x, p.y, e.x, e.y)) continue;
    let count = 0;
    for (const o of enemies) {
      const ox = o.x - p.x;
      const oy = o.y - p.y;
      const along = ox * d.x + oy * d.y;
      if (along < 0 || along > s.range) continue;
      const perp2 = ox * ox + oy * oy - along * along;
      if (perp2 < (s.radius + o.r) ** 2) count += o.boss ? LANCE_BOSS_WEIGHT : 1;
    }
    if (!best || count > best.count) best = { x: d.x, y: d.y, count };
  }
  return best;
}

function countNear(p, enemies, radius) {
  let n = 0;
  for (const e of enemies) if (dist2(p.x, p.y, e.x, e.y) < (radius + e.r) ** 2) n++;
  return n;
}

function abilityIntent(game, mem, enemies, intent, opts) {
  const p = game.player;
  const t = game.tuning;
  const hpFrac = p.hp / p.maxHp;
  if (p.skillCd <= 0 && (p.state === 'free' || (p.state === 'attack' && p.attack?.phase === 'recovery'))) {
    const aim = bestLanceAim(game, enemies);
    if (aim && aim.count >= 1) intent.skill = aim;
  }
  const nearSuper = countNear(p, enemies, t.super.radius + SUPER_REACH_PAD);
  const bossNear = enemies.some((e) => e.boss && distTo(p, e) < t.super.radius + e.r + SUPER_REACH_PAD);
  if (p.superCharge >= 1 && (nearSuper >= SUPER_CROWD || bossNear || (nearSuper >= 1 && hpFrac < SUPER_LOW_HP))) intent.superP = true;
  if (opts.gadget && p.gadgetCharges > 0 && game.time - mem.lastGadget > GADGET_MIN_GAP) {
    const near = countNear(p, enemies, t.gadget.radius);
    if (near >= GADGET_CROWD || (hpFrac < GADGET_LOW_HP && near >= 1)) {
      intent.gadget = true;
      mem.lastGadget = game.time;
    }
  }
}

function engageIntent(game, mem, enemies, opts) {
  const p = game.player;
  const target = pickTarget(game, mem, enemies);
  const intent = { mx: 0, my: 0, attack: false, skill: null, gadget: false, superP: false };
  const d = distTo(p, target);
  if (isWindingDanger(target)) {
    // Recul face à une brute qui arme son coup ou un possédé qui gonfle.
    if (d < RETREAT_DIST + target.r) {
      const away = norm(p.x - target.x, p.y - target.y);
      intent.mx = away.x;
      intent.my = away.y;
    }
  } else {
    const standoff = target.r + p.r + STANDOFF_GAP;
    const reach = game.tuning.combo[0].range + target.r - REACH_MARGIN;
    if (d > standoff) {
      const nav = navDir(game.room, p.x, p.y, target.x, target.y, p.r);
      intent.mx = nav.x;
      intent.my = nav.y;
    }
    intent.attack = d <= reach;
  }
  abilityIntent(game, mem, enemies, intent, opts);
  return intent;
}

// ---------------------------------------------------------------- intention : hors combat

function nearest(p, list) {
  let best = null;
  let bestD = Infinity;
  for (const o of list) {
    const d = dist2(p.x, p.y, o.x, o.y);
    if (d < bestD) {
      bestD = d;
      best = o;
    }
  }
  return best;
}

function chooseDoor(game, mem) {
  const p = game.player;
  const doors = game.room.doors;
  if (mem.doorFloor === game.run.floor && mem.doorRoom === game.room) return doors[mem.door];
  const hpFrac = p.hp / p.maxHp;
  let best = 0;
  let bestScore = -Infinity;
  doors.forEach((d, i) => {
    let s = DOOR_PREFS[d.reward] ?? 1;
    if (d.reward === 'heal' && hpFrac < HEAL_DOOR_HP) s += DOOR_URGENT_HEAL;
    if (d.reward === 'shop' && hpFrac < LOW_HP_SHOP) s += DOOR_URGENT_SHOP;
    if (d.reward === 'elite' && hpFrac < ELITE_DOOR_HP) s -= DOOR_ELITE_RISK;
    s += (mixHash(game.seed, game.run.floor, i) / U32) * DOOR_NOISE;
    if (s > bestScore) {
      bestScore = s;
      best = i;
    }
  });
  mem.doorFloor = game.run.floor;
  mem.doorRoom = game.room;
  mem.door = best;
  return doors[best];
}

function toward(game, x, y) {
  const p = game.player;
  if (dist2(p.x, p.y, x, y) < ARRIVE_DIST * ARRIVE_DIST) return { mx: 0, my: 0 };
  const d = navDir(game.room, p.x, p.y, x, y, p.r);
  return { mx: d.x, my: d.y };
}

/** Entre deux vagues, après le combat : ramasser, toucher la récompense, prendre une porte. */
function exploreIntent(game, mem) {
  const room = game.room;
  const p = game.player;
  const base = { mx: 0, my: 0, attack: false, skill: null, gadget: false, superP: false };
  if (!room.cleared) {
    const s = nearest(p, game.spawns);
    if (!s) return { ...base, ...toward(game, room.w / 2, room.h / 2) };
    if (distTo(p, s) > SPAWN_WAIT_DIST) return { ...base, ...toward(game, s.x, s.y) };
    return base;
  }
  const hurt = p.hp < p.maxHp;
  const pickups = game.pickups.filter((k) => k.kind === 'gold' || hurt);
  if (pickups.length && game.time - room.clearedAt < PICKUP_WINDOW) {
    const k = nearest(p, pickups);
    return { ...base, ...toward(game, k.x, k.y) };
  }
  const it = room.interact;
  if (it && !it.used) return { ...base, ...toward(game, it.x, it.y) };
  const open = room.doors.some((d) => d.open);
  if (!open) return base;
  const door = chooseDoor(game, mem);
  return { ...base, ...toward(game, door.x + door.w / 2, door.h / 2) };
}

// ---------------------------------------------------------------- composition

/** Se décoince quand l'intention de marche ne produit aucun déplacement. */
function applyUnstick(game, mem, intent) {
  const p = game.player;
  const now = game.tick * DT;
  if (mem.unstickT > 0) {
    mem.unstickT -= DT;
    intent.mx = mem.unstickX;
    intent.my = mem.unstickY;
    intent.attack = false;
    return;
  }
  const wants = intent.mx * intent.mx + intent.my * intent.my > MOVE_INTENT_MIN2 && !intent.attack && p.state === 'free';
  if (!wants || game.hitstop > 0) {
    mem.stuckX = p.x;
    mem.stuckY = p.y;
    mem.stuckT = now;
    return;
  }
  if (now - mem.stuckT < STUCK_WINDOW) return;
  if (dist2(p.x, p.y, mem.stuckX, mem.stuckY) < STUCK_DIST * STUCK_DIST) {
    mem.unstickSign = -mem.unstickSign;
    mem.unstickX = -intent.my * mem.unstickSign;
    mem.unstickY = intent.mx * mem.unstickSign;
    mem.unstickT = UNSTICK_TIME;
  }
  mem.stuckX = p.x;
  mem.stuckY = p.y;
  mem.stuckT = now;
}

function intentToInput(intent) {
  const input = emptyInput();
  input.moveX = intent.mx;
  input.moveY = intent.my;
  input.attack = intent.attack;
  if (intent.skill) {
    input.skillPressed = true;
    input.skillAimX = intent.skill.x;
    input.skillAimY = intent.skill.y;
  }
  input.gadgetPressed = intent.gadget;
  input.superPressed = intent.superP;
  return input;
}

function tactical(game, mem, opts) {
  const input = emptyInput();
  if (game.mode !== 'play') return input;
  ensureMem(game, mem, opts.salt);
  onNewFloor(game, mem);
  trackMotion(game, mem);
  const p = game.player;
  if (p.state === 'dead') return input;
  if (p.state === 'dash') {
    input.moveX = p.dashDirX;
    input.moveY = p.dashDirY;
    return input;
  }
  const enemies = visibleEnemies(game);
  const intent = enemies.length ? engageIntent(game, mem, enemies, opts) : exploreIntent(game, mem);
  applyUnstick(game, mem, intent);
  const threats = perceiveThreats(game, mem);
  if (threats.length) {
    const evasive = planEvasion(game, mem, threats, intent, opts);
    if (evasive) {
      // On garde le Super s'il est prêt : il rend invulnérable pendant sa durée.
      evasive.superPressed = intent.superP;
      return evasive;
    }
  }
  return intentToInput(intent);
}

// ---------------------------------------------------------------- politiques

function skilled(game, mem) {
  return tactical(game, mem, { dash: true, gadget: true, salt: 1 });
}

function noDash(game, mem) {
  return tactical(game, mem, { dash: false, gadget: false, salt: 2 });
}

function masher(game, mem) {
  const input = emptyInput();
  if (game.mode !== 'play') return input;
  ensureMem(game, mem, 3);
  onNewFloor(game, mem);
  const p = game.player;
  if (p.state === 'dead') return input;
  const enemies = visibleEnemies(game);
  const intent = enemies.length ? { mx: 0, my: 0, attack: true } : exploreIntent(game, mem);
  if (enemies.length) {
    const e = nearest(p, enemies);
    if (distTo(p, e) > e.r + p.r + MASHER_CONTACT_GAP) {
      const d = navDir(game.room, p.x, p.y, e.x, e.y, p.r);
      intent.mx = d.x;
      intent.my = d.y;
    }
  }
  applyUnstick(game, mem, intent);
  input.moveX = intent.mx;
  input.moveY = intent.my;
  input.attack = !!intent.attack;
  if (mem.rng() < MASHER_DASH_CHANCE) {
    const a = mem.rng() * Math.PI * 2;
    input.moveX = Math.cos(a);
    input.moveY = Math.sin(a);
    input.dashPressed = true;
  }
  return input;
}

export const POLICIES = { skilled, noDash, masher };

// ---------------------------------------------------------------- menus (mode 'choice')

const POLICY_SALT = { skilled: 1, noDash: 2, masher: 3 };

function boonIndex(game, policyName, count) {
  return mixHash(game.seed, game.run.floor, POLICY_SALT[policyName] ?? 0, game.run.boons.length) % count;
}

function primaryCommand(game, policyName) {
  const ch = game.choice;
  const p = game.player;
  if (ch.kind === 'boon') return { type: 'choose', index: boonIndex(game, policyName, ch.options.length) };
  if (ch.kind === 'loot') {
    const cur = ch.equipped ? ch.equipped.score : -Infinity;
    return { type: ch.item.score > cur ? 'equip' : 'salvage' };
  }
  if (ch.kind === 'shop') {
    const i = ch.offers.findIndex((o) => o.kind === 'heal' && !o.sold);
    const offer = ch.offers[i];
    if (offer && p.hp < p.maxHp * LOW_HP_SHOP && game.run.gold >= offer.price) return { type: 'choose', index: i };
    return { type: 'close' };
  }
  if (ch.kind === 'event') {
    const i = ch.options[0]?.disabled ? ch.options.findIndex((o) => !o.disabled) : 0;
    return { type: 'choose', index: Math.max(0, i) };
  }
  return { type: 'close' };
}

const FALLBACK_COMMANDS = [
  { type: 'close' }, { type: 'salvage' },
  { type: 'choose', index: 0 }, { type: 'choose', index: 1 }, { type: 'choose', index: 2 },
];

/**
 * Résout le menu ouvert (game.mode === 'choice') via applyCommand. Rend true si une
 * commande a été acceptée. Repli sur des commandes génériques si la première échoue.
 */
export function resolveChoice(game, policyName) {
  if (game.mode !== 'choice' || !game.choice) return false;
  if (applyCommand(game, primaryCommand(game, policyName))) return true;
  for (const cmd of FALLBACK_COMMANDS) {
    if (game.mode !== 'choice') return true;
    if (applyCommand(game, cmd)) return true;
  }
  return false;
}

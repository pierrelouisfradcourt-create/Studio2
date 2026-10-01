// Caméra : suivi lissé avec avance dans la direction de visée/mouvement, bornée à la salle,
// tremblement par « trauma » (amplitude = trauma², Vlambeer/Squirrel Eiserloh) et coups
// de zoom. Présentation pure : ne lit la simulation qu'en lecture seule.

const TARGET_AREA = 840 * 472; // unités² visibles (≈ 840 × 472 en 16:9)
const MIN_VISIBLE = 400; // la plus petite dimension visible ne descend pas sous ce seuil
const MARGIN_SIDE = 40; // u de « hors salle » autorisés à l'écran
const MARGIN_TOP = 110; // plus large en haut : le HUD ne recouvre jamais le héros
const MARGIN_BOTTOM = 70;
const FOLLOW_RATE = 10; // 1/s — lissage exponentiel du suivi
const LOOK_AHEAD = 70; // u — avance vers la visée
const SHAKE_MAX = 16; // u — amplitude max du tremblement
const SHAKE_ROT = 0.03; // rad — rotation max
const TRAUMA_DECAY = 1.8; // trauma perdu par seconde (linéaire)
const PLAYER_TRAUMA_CAP = 0.55; // les coups du héros ne poussent pas le trauma au-delà
const KICK_RETURN = 16; // 1/s — retour exponentiel du recul directionnel
const KICK_CAP = 12; // u — somme des reculs plafonnée
const SHAKE_RATE = 55; // rad/s du bruit de tremblement : fondamentale ≈ 9 Hz, harmoniques jusqu'à ≈ 36 Hz
const ZOOM_RATE = 9;
const BOSS_FRAMING = 0.35; // part de l'écart héros -> boss intégrée au cadrage
const BOSS_ZOOM = 0.88; // léger recul de caméra pendant un combat de boss
const BOSS_FRAME_RATE = 3; // 1/s — transition douce du cadrage
const THUMB_OFFSET = 0.05; // fraction de la hauteur visible : le héros est cadré au-dessus du centre (pouces en bas)
const THUMB_OFFSET_PORTRAIT = 0.16; // en portrait, les boutons occupent le bas : héros à ~35 % du haut
const THUMB_BAND = 0.1; // fraction de la vue « hors salle » permise en bas (paysage)
const THUMB_BAND_PORTRAIT = 0.4; // idem en portrait
const HERO_PAD = 40; // u : marge minimale entre le héros et le groupe de boutons (paysage tactile)

export function createCamera() {
  return { x: 0, y: 0, scale: 1, viewW: 900, viewH: 506, trauma: 0, shakeX: 0, shakeY: 0, rot: 0, zoom: 1, zoomTarget: 1, t: 0, shakeScale: 1, snapped: false, kickX: 0, kickY: 0, bossFrame: 0, baseZoom: 1, rightInsetPx: 0 };
}

/** Échelle px CSS par unité, selon la taille d'écran. */
export function fitCamera(cam, cssW, cssH) {
  let scale = Math.sqrt((cssW * cssH) / TARGET_AREA);
  const minDim = Math.min(cssW, cssH) / scale;
  if (minDim < MIN_VISIBLE) scale = Math.min(cssW, cssH) / MIN_VISIBLE;
  cam.scale = scale;
  cam.viewW = cssW / scale;
  cam.viewH = cssH / scale;
}

export function addTrauma(cam, amount, fromPlayer = false) {
  const add = amount * cam.shakeScale;
  if (fromPlayer) {
    if (cam.trauma < PLAYER_TRAUMA_CAP) cam.trauma = Math.min(PLAYER_TRAUMA_CAP, cam.trauma + add);
    return;
  }
  cam.trauma = Math.min(1, cam.trauma + add);
}

/** Recul directionnel (principe Vlambeer) : c'est lui qui fait sentir les coups légers. */
export function kick(cam, dirX, dirY, amount) {
  const a = amount * cam.shakeScale;
  cam.kickX += dirX * a;
  cam.kickY += dirY * a;
  const l = Math.hypot(cam.kickX, cam.kickY);
  if (l > KICK_CAP) {
    cam.kickX *= KICK_CAP / l;
    cam.kickY *= KICK_CAP / l;
  }
}

export function zoomKick(cam, amount) {
  cam.zoomTarget = Math.max(cam.zoomTarget, 1 + amount);
}

// Bruit pseudo-continu bon marché (somme de sinus) : pas d'aléa image par image.
function noise(t, seed) {
  return Math.sin(t * 1.0 + seed) * 0.5 + Math.sin(t * 2.3 + seed * 1.7) * 0.3 + Math.sin(t * 4.1 + seed * 2.9) * 0.2;
}

export function updateCamera(cam, game, dt) {
  const p = game.player;
  const room = game.room;
  let ax = p.aimX;
  let ay = p.aimY;
  if (p.moveX * p.moveX + p.moveY * p.moveY > 0.04) {
    ax = p.moveX;
    ay = p.moveY;
  } else {
    ax = Math.cos(p.facing);
    ay = Math.sin(p.facing);
  }
  // Paysage tactile : la bande droite est occupée par les boutons. Le héros est cadré au centre
  // de la zone libre, et la caméra peut dépasser le mur droit pour qu'il n'y passe jamais dessous.
  const inset = cam.viewW > cam.viewH ? (cam.rightInsetPx || 0) / (cam.scale * cam.zoom) : 0;
  let tx = p.x + ax * LOOK_AHEAD + inset / 2;
  const thumb = cam.viewH > cam.viewW ? THUMB_OFFSET_PORTRAIT : THUMB_OFFSET;
  let ty = p.y + ay * LOOK_AHEAD + cam.viewH * thumb;
  // Combat de boss : on cadre le duel (héros + Gardien) et on recule un peu.
  const boss = game.enemies.find((e) => e.boss && !e.dead);
  const want = boss ? 1 : 0;
  cam.bossFrame += (want - cam.bossFrame) * (1 - Math.exp(-BOSS_FRAME_RATE * dt));
  if (boss) {
    tx += (boss.x - p.x) * BOSS_FRAMING * cam.bossFrame;
    ty += (boss.y - p.y) * BOSS_FRAMING * cam.bossFrame;
  }
  // Le cadrage du duel ne pousse jamais le héros sous les boutons.
  if (inset > 0) tx = Math.max(tx, p.x - cam.viewW / (2 * cam.zoom) + inset + HERO_PAD);
  cam.baseZoom = 1 + (BOSS_ZOOM - 1) * cam.bossFrame;
  // Bornes : la salle reste cadrée ; si elle est plus petite que la vue, on la centre.
  const halfW = cam.viewW / (2 * cam.zoom);
  const halfH = cam.viewH / (2 * cam.zoom);
  tx = room.w + 2 * MARGIN_SIDE + inset <= 2 * halfW ? (room.w + inset) / 2 : Math.max(halfW - MARGIN_SIDE, Math.min(room.w + MARGIN_SIDE + inset - halfW, tx));
  // Sous la salle, la caméra peut montrer du mur : c'est là que les pouces couvrent l'écran.
  const bottom = MARGIN_BOTTOM + cam.viewH * (cam.viewH > cam.viewW ? THUMB_BAND_PORTRAIT : THUMB_BAND);
  ty = room.h + MARGIN_TOP + bottom <= 2 * halfH ? room.h / 2 : Math.max(halfH - MARGIN_TOP, Math.min(room.h + bottom - halfH, ty));
  if (!cam.snapped) {
    cam.x = tx;
    cam.y = ty;
    cam.snapped = true;
  } else {
    const k = 1 - Math.exp(-FOLLOW_RATE * dt);
    cam.x += (tx - cam.x) * k;
    cam.y += (ty - cam.y) * k;
  }
  cam.t += dt;
  cam.trauma = Math.max(0, cam.trauma - TRAUMA_DECAY * dt);
  const s = cam.trauma * cam.trauma;
  const ft = cam.t * SHAKE_RATE;
  cam.shakeX = SHAKE_MAX * s * noise(ft, 1);
  cam.shakeY = SHAKE_MAX * s * noise(ft, 7);
  cam.rot = SHAKE_ROT * s * noise(ft, 13);
  const kr = Math.exp(-KICK_RETURN * dt);
  cam.kickX *= kr;
  cam.kickY *= kr;
  cam.zoom += (cam.zoomTarget * cam.baseZoom - cam.zoom) * (1 - Math.exp(-ZOOM_RATE * dt));
  cam.zoomTarget += (1 - cam.zoomTarget) * (1 - Math.exp(-ZOOM_RATE * 0.6 * dt));
}

/** Applique la transformation monde -> écran (px CSS) au contexte. */
export function applyCamera(ctx, cam, cssW, cssH) {
  ctx.translate(cssW / 2, cssH / 2);
  ctx.rotate(cam.rot);
  ctx.scale(cam.scale * cam.zoom, cam.scale * cam.zoom);
  ctx.translate(-cam.x + cam.shakeX - cam.kickX, -cam.y + cam.shakeY - cam.kickY);
}

export function worldToScreen(cam, cssW, cssH, x, y, out) {
  const k = cam.scale * cam.zoom;
  out.x = (x - cam.x + cam.shakeX - cam.kickX) * k + cssW / 2;
  out.y = (y - cam.y + cam.shakeY - cam.kickY) * k + cssH / 2;
  return out;
}

export function resetCamera(cam) {
  cam.snapped = false;
  cam.trauma = 0;
  cam.kickX = 0;
  cam.kickY = 0;
}

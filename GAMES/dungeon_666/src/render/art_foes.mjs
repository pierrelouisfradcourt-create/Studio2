// Dessin des archétypes d'ennemis ajoutés (voir art.mjs pour la signature). Contexte déjà
// centré sur l'ennemi ; `face` = angle vers le héros ; `body` = couleur de corps (ou flash).
// Silhouettes distinctes au premier coup d'œil, même sur petit écran :
//   pyromancer  — capuche pointue rouge sombre + bâton à flamme (la flamme ENFLE pendant
//                 l'incantation : on voit QUI pose les cercles)
//   necromancer — robe violette, crâne d'os, éclats d'os en orbite (ils s'accélèrent et
//                 brillent pendant la canalisation)
//   pavois      — corps trapu rouille + grand PAVOIS de bronze tourné vers e.face (PAS vers le
//                 héros) : l'arc dessiné est l'arc qui arrête les coups ; le dos est nu. Pavois
//                 écarté et terni quand la garde est baissée (récupération, étourdi).
//   stalker     — corps mince prune, deux lames, yeux magenta ; il PÂLIT pendant la dissolution,
//                 n'est plus dessiné une fois disparu (render.mjs), lames levées avant la frappe.
//   banner      — porteur ocre, hampe et étendard cramoisi qui flotte ; son aura est l'alerte
//                 inoffensive (violette) dessinée par render.mjs ; les ennemis qu'il couvre
//                 portent un chevron violet (drawWard).

import { PAL } from './palette.mjs';
import { EXTRA_ENEMIES } from '../sim/foe_data.mjs';

const TAU = Math.PI * 2;

export const FOE_BODY = { pyromancer: '#a8233a', necromancer: '#4b2d72', pavois: PAL.pavois, stalker: PAL.stalker, banner: PAL.banner };

function outlineCircle(ctx, r, fill) {
  ctx.fillStyle = fill;
  ctx.strokeStyle = PAL.enemyOutline;
  ctx.lineWidth = 3;
  ctx.beginPath();
  ctx.arc(0, 0, r, 0, TAU);
  ctx.fill();
  ctx.stroke();
}

function eyes(ctx, r, face, color, spread, dist) {
  ctx.fillStyle = color;
  for (const s of [-spread, spread]) {
    const a = face + s;
    ctx.beginPath();
    ctx.arc(Math.cos(a) * r * dist, Math.sin(a) * r * dist, Math.max(1.5, r * 0.13), 0, TAU);
    ctx.fill();
  }
}

function pyromancer(ctx, r, face, body, e, time) {
  const casting = e.state === 'windup';
  // Capuche pointue derrière la tête : la silhouette « mage ».
  const back = face + Math.PI;
  ctx.fillStyle = '#5a0f1c';
  ctx.strokeStyle = PAL.enemyOutline;
  ctx.lineWidth = 3;
  ctx.beginPath();
  ctx.moveTo(Math.cos(back - 0.9) * r * 0.85, Math.sin(back - 0.9) * r * 0.85);
  ctx.lineTo(Math.cos(back) * r * 1.75, Math.sin(back) * r * 1.75);
  ctx.lineTo(Math.cos(back + 0.9) * r * 0.85, Math.sin(back + 0.9) * r * 0.85);
  ctx.closePath();
  ctx.fill();
  ctx.stroke();
  // Bâton : levé vers le héros pendant l'incantation, tenu de côté sinon.
  const sa = casting ? face + 0.35 : face + 1.25;
  const len = r * (casting ? 1.9 : 1.6);
  const tx = Math.cos(sa) * len;
  const ty = Math.sin(sa) * len;
  ctx.strokeStyle = '#5a3a22';
  ctx.lineWidth = 3;
  ctx.beginPath();
  ctx.moveTo(Math.cos(sa) * r * 0.4, Math.sin(sa) * r * 0.4);
  ctx.lineTo(tx, ty);
  ctx.stroke();
  outlineCircle(ctx, r, body);
  eyes(ctx, r, face, '#ffd23c', 0.4, 0.45);
  // Flamme au bout du bâton : petite au repos, grosse et vive pendant l'incantation.
  const flicker = 0.85 + 0.15 * Math.sin(time * 22 + e.id);
  const fr = r * (casting ? 0.75 : 0.42) * flicker;
  ctx.fillStyle = PAL.lava;
  ctx.beginPath();
  ctx.arc(tx, ty, fr, 0, TAU);
  ctx.fill();
  ctx.fillStyle = '#ffe14a';
  ctx.beginPath();
  ctx.arc(tx, ty, fr * 0.5, 0, TAU);
  ctx.fill();
}

const BONE_SHARDS = 3;

function necromancer(ctx, r, face, body, e, time) {
  const channeling = e.state === 'channel';
  // Éclats d'os en orbite (violets et rapides pendant la canalisation).
  const spin = time * (channeling ? 7 : 1.6);
  ctx.fillStyle = channeling ? PAL.summon : '#d8d0c0';
  ctx.strokeStyle = PAL.enemyOutline;
  ctx.lineWidth = 2;
  for (let i = 0; i < BONE_SHARDS; i++) {
    const a = spin + (i / BONE_SHARDS) * TAU;
    const d = r * (channeling ? 1.75 : 1.45);
    const x = Math.cos(a) * d;
    const y = Math.sin(a) * d;
    ctx.beginPath();
    ctx.moveTo(x + Math.cos(a) * r * 0.32, y + Math.sin(a) * r * 0.32);
    ctx.lineTo(x + Math.cos(a + 2.2) * r * 0.2, y + Math.sin(a + 2.2) * r * 0.2);
    ctx.lineTo(x + Math.cos(a - 2.2) * r * 0.2, y + Math.sin(a - 2.2) * r * 0.2);
    ctx.closePath();
    ctx.fill();
    ctx.stroke();
  }
  // Robe : corps à bord dentelé (silhouette distincte du diablotin rond).
  ctx.fillStyle = body;
  ctx.strokeStyle = PAL.enemyOutline;
  ctx.lineWidth = 3;
  ctx.beginPath();
  const teeth = 9;
  for (let i = 0; i <= teeth * 2; i++) {
    const a = (i / (teeth * 2)) * TAU;
    const rr = i % 2 === 0 ? r : r * 0.86;
    if (i === 0) ctx.moveTo(Math.cos(a) * rr, Math.sin(a) * rr);
    else ctx.lineTo(Math.cos(a) * rr, Math.sin(a) * rr);
  }
  ctx.closePath();
  ctx.fill();
  ctx.stroke();
  // Crâne tourné vers le héros.
  const sx = Math.cos(face) * r * 0.25;
  const sy = Math.sin(face) * r * 0.25;
  ctx.fillStyle = '#e8e0d0';
  ctx.beginPath();
  ctx.arc(sx, sy, r * 0.55, 0, TAU);
  ctx.fill();
  ctx.save();
  ctx.translate(sx, sy);
  eyes(ctx, r * 0.55, face, channeling ? PAL.summon : '#1a0a14', 0.55, 0.42);
  ctx.restore();
}

function pavois(ctx, r, face, body, e) {
  const def = EXTRA_ENEMIES.pavois;
  const up = !(e.stun > 0) && e.state !== 'recover'; // même règle que foe_defense.guardUp
  const f = e.face ?? face;
  // Dos nu : une échine sombre à l'opposé du pavois (c'est LÀ qu'il faut frapper).
  const back = f + Math.PI;
  ctx.fillStyle = '#3a1a10';
  ctx.beginPath();
  ctx.arc(Math.cos(back) * r * 0.55, Math.sin(back) * r * 0.55, r * 0.5, 0, TAU);
  ctx.fill();
  outlineCircle(ctx, r, body);
  eyes(ctx, r, f, '#ffe14a', 0.35, 0.3);
  // Pavois : arc épais, exactement de la largeur de la garde ; écarté sur le côté s'il est baissé.
  const half = def.guardArc / 2;
  const a = up ? f : f + 1.9;
  const rr = r * (up ? 1.35 : 1.15);
  ctx.lineCap = 'round';
  ctx.strokeStyle = PAL.enemyOutline;
  ctx.lineWidth = r * 0.62;
  ctx.beginPath();
  ctx.arc(0, 0, rr, a - (up ? half : 0.5), a + (up ? half : 0.5));
  ctx.stroke();
  ctx.strokeStyle = up ? PAL.pavoisShield : '#6e5a3a';
  ctx.lineWidth = r * 0.38;
  ctx.beginPath();
  ctx.arc(0, 0, rr, a - (up ? half : 0.5), a + (up ? half : 0.5));
  ctx.stroke();
  ctx.lineCap = 'butt';
  if (up) {
    // Umbo : le bossage central, pour lire d'un coup d'œil où le pavois regarde.
    ctx.fillStyle = '#fff1c0';
    ctx.beginPath();
    ctx.arc(Math.cos(f) * rr, Math.sin(f) * rr, r * 0.2, 0, TAU);
    ctx.fill();
  }
}

function stalker(ctx, r, face, body, e) {
  const def = EXTRA_ENEMIES.stalker;
  const fading = e.state === 'fade';
  const striking = e.state === 'windup';
  const alpha = ctx.globalAlpha;
  if (fading) ctx.globalAlpha = alpha * Math.max(0.12, 1 - e.stateTime / def.fade);
  // Deux lames : le long du corps au repos, écartées et levées avant la frappe.
  ctx.strokeStyle = striking ? '#ffd0e8' : '#c9b8c8';
  ctx.lineWidth = 3;
  for (const s of [-1, 1]) {
    const a = face + s * (striking ? 1.15 : 2.3);
    const len = r * (striking ? 2.1 : 1.6);
    ctx.beginPath();
    ctx.moveTo(Math.cos(a) * r * 0.7, Math.sin(a) * r * 0.7);
    ctx.lineTo(Math.cos(a) * len, Math.sin(a) * len);
    ctx.stroke();
  }
  // Corps mince : une amande allongée vers le héros (silhouette distincte des ronds).
  ctx.save();
  ctx.rotate(face);
  ctx.fillStyle = body;
  ctx.strokeStyle = PAL.enemyOutline;
  ctx.lineWidth = 3;
  ctx.beginPath();
  ctx.ellipse(0, 0, r * 1.15, r * 0.72, 0, 0, TAU);
  ctx.fill();
  ctx.stroke();
  ctx.restore();
  eyes(ctx, r, face, PAL.bossOrb, 0.3, 0.6);
  ctx.globalAlpha = alpha;
}

function banner(ctx, r, face, body, e, time) {
  const down = e.stun > 0; // étourdi : l'étendard tombe, l'aura avec lui
  outlineCircle(ctx, r, body);
  eyes(ctx, r, face, '#2a0a0a', 0.4, 0.45);
  // Hampe plantée derrière l'épaule, étendard cramoisi qui flotte (couché s'il est étourdi).
  const tilt = down ? 1.2 : 0;
  const px = r * 0.5;
  const top = -r * (down ? 1.2 : 2.9);
  ctx.save();
  ctx.rotate(tilt);
  ctx.strokeStyle = '#3a2a1a';
  ctx.lineWidth = 3;
  ctx.beginPath();
  ctx.moveTo(px, r * 0.4);
  ctx.lineTo(px, top);
  ctx.stroke();
  const wave = Math.sin(time * 6 + e.id) * r * 0.18;
  ctx.fillStyle = down ? '#6a1a24' : PAL.bannerFlag;
  ctx.strokeStyle = PAL.enemyOutline;
  ctx.lineWidth = 2;
  ctx.beginPath();
  ctx.moveTo(px, top);
  ctx.lineTo(px + r * 1.5, top + r * 0.3 + wave);
  ctx.lineTo(px + r * 1.1, top + r * 0.75);
  ctx.lineTo(px + r * 1.5, top + r * 1.2 - wave);
  ctx.lineTo(px, top + r * 1.1);
  ctx.closePath();
  ctx.fill();
  ctx.stroke();
  ctx.restore();
}

/**
 * Marque d'un ennemi COUVERT par un étendard (foe_defense.wardOf) : chevron violet au-dessus de
 * lui, de la couleur des alertes inoffensives (la même que l'aura). Contexte en coordonnées monde.
 */
export function drawWard(ctx, e, r, time) {
  const y = e.y - r - 16 + Math.sin(time * 5 + e.id) * 1.5;
  ctx.strokeStyle = PAL.summon;
  ctx.lineWidth = 3;
  ctx.beginPath();
  ctx.moveTo(e.x - 7, y - 4);
  ctx.lineTo(e.x, y + 3);
  ctx.lineTo(e.x + 7, y - 4);
  ctx.stroke();
}

export const FOE_ART = { pyromancer, necromancer, pavois, stalker, banner };

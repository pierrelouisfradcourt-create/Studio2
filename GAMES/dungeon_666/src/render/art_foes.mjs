// Dessin des archétypes d'ennemis ajoutés (voir art.mjs pour la signature). Contexte déjà
// centré sur l'ennemi ; `face` = angle vers le héros ; `body` = couleur de corps (ou flash).
// Silhouettes distinctes au premier coup d'œil, même sur petit écran :
//   pyromancer  — capuche pointue rouge sombre + bâton à flamme (la flamme ENFLE pendant
//                 l'incantation : on voit QUI pose les cercles)
//   necromancer — robe violette, crâne d'os, éclats d'os en orbite (ils s'accélèrent et
//                 brillent pendant la canalisation)

import { PAL } from './palette.mjs';

const TAU = Math.PI * 2;

export const FOE_BODY = { pyromancer: '#a8233a', necromancer: '#4b2d72' };

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

export const FOE_ART = { pyromancer, necromancer };

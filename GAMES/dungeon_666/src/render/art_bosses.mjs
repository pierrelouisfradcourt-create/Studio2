// Dessin des Gardiens ajoutés (voir art.mjs pour la signature). Charon (`gardien`) reste dans render.mjs.
// Silhouettes pensées pour se reconnaître d'un coup d'œil sur un téléphone :
//   Cerbère  — trois têtes en éventail, crinière en pointes ; en l'air pendant un bond ;
//   Minos    — mitre dorée, robe indigo, queue de serpent enroulée ; en filigrane quand il se dissout ;
//   Éphialte — bloc de pierre fissuré, deux poings énormes, chaînes (qui brillent sous bouclier).
// Commun : un POINT FAIBLE doré pulse quand le Gardien est exposé (e.vuln), là où frapper.

const TAU = Math.PI * 2;
const OUTLINE = '#140507';

export const BOSS_BODY = {
  cerbere: '#8a2e1e', // fourrure rouge braise : tranche sur le sol sombre
  minos: '#2e2458',
  colosse: '#6b5a50',
};

function disc(ctx, x, y, r, fill, stroke = OUTLINE, width = 3) {
  ctx.fillStyle = fill;
  ctx.strokeStyle = stroke;
  ctx.lineWidth = width;
  ctx.beginPath();
  ctx.arc(x, y, r, 0, TAU);
  ctx.fill();
  ctx.stroke();
}

function eyePair(ctx, cx, cy, r, face, color, spread = 0.5) {
  ctx.fillStyle = color;
  for (const s of [-spread, spread]) {
    ctx.beginPath();
    ctx.arc(cx + Math.cos(face + s) * r * 0.5, cy + Math.sin(face + s) * r * 0.5, Math.max(1.5, r * 0.16), 0, TAU);
    ctx.fill();
  }
}

/** Point faible exposé : anneau doré qui pulse (même langage pour tous les Gardiens). */
function weakPoint(ctx, x, y, size, time) {
  const k = 0.5 + 0.5 * Math.sin(time * 14);
  ctx.save();
  ctx.globalCompositeOperation = 'lighter';
  ctx.fillStyle = `rgba(255, 200, 60, ${0.25 + 0.35 * k})`;
  ctx.beginPath();
  ctx.arc(x, y, size * (1.3 + 0.3 * k), 0, TAU);
  ctx.fill();
  ctx.restore();
  ctx.strokeStyle = '#ffd23c';
  ctx.lineWidth = 3;
  ctx.beginPath();
  ctx.arc(x, y, size, 0, TAU);
  ctx.stroke();
  ctx.fillStyle = '#fff4c0';
  ctx.beginPath();
  ctx.arc(x, y, size * 0.35, 0, TAU);
  ctx.fill();
}

// ---------------------------------------------------------------- Cerbère

const HEAD_ANGLES = [-0.7, 0, 0.7];

function cerbere(ctx, r, face, body, e, time) {
  const k = e.airborne ? Math.sin(Math.PI * (e.leapK ?? 0)) : 0;
  const frenzy = e.phase === 3;
  ctx.save();
  // En l'air : le corps monte et grossit, l'ombre (dessinée par render.mjs) reste au sol.
  ctx.translate(0, -k * r * 1.3);
  ctx.scale(1 + 0.18 * k, 1 + 0.18 * k);
  if (frenzy) {
    ctx.save();
    ctx.globalCompositeOperation = 'lighter';
    ctx.fillStyle = `rgba(255, 110, 30, ${0.18 + 0.12 * Math.sin(time * 18)})`;
    ctx.beginPath();
    ctx.arc(0, 0, r * 1.55, 0, TAU);
    ctx.fill();
    ctx.restore();
  }
  // Crinière en pointes (dos), tournée à l'opposé des têtes.
  ctx.fillStyle = frenzy ? '#ff6a1a' : '#2a0c08';
  ctx.strokeStyle = OUTLINE;
  ctx.lineWidth = 2;
  ctx.beginPath();
  const spikes = 7;
  for (let i = 0; i < spikes; i++) {
    const a = face + Math.PI + (i - (spikes - 1) / 2) * 0.32;
    const flick = 1.25 + 0.08 * Math.sin(time * 9 + i);
    ctx.moveTo(Math.cos(a - 0.14) * r * 0.85, Math.sin(a - 0.14) * r * 0.85);
    ctx.lineTo(Math.cos(a) * r * flick, Math.sin(a) * r * flick);
    ctx.lineTo(Math.cos(a + 0.14) * r * 0.85, Math.sin(a + 0.14) * r * 0.85);
  }
  ctx.fill();
  ctx.stroke();
  disc(ctx, 0, 0, r, body);
  // Trois têtes ; celle qui mord (cône affiché) ouvre une gueule rouge.
  const biting = e.tele && e.tele.shape === 'cone';
  for (const off of HEAD_ANGLES) {
    const a = face + off * (biting ? 0.8 : 1);
    const hx = Math.cos(a) * r * 0.85;
    const hy = Math.sin(a) * r * 0.85;
    const hr = r * (off === 0 ? 0.5 : 0.42);
    // Oreilles pointues.
    ctx.fillStyle = '#2a0c08';
    ctx.beginPath();
    for (const s of [-0.9, 0.9]) {
      ctx.moveTo(hx + Math.cos(a + s) * hr * 0.7, hy + Math.sin(a + s) * hr * 0.7);
      ctx.lineTo(hx + Math.cos(a + s * 0.6) * hr * 1.5, hy + Math.sin(a + s * 0.6) * hr * 1.5);
      ctx.lineTo(hx + Math.cos(a + s * 0.2) * hr * 0.9, hy + Math.sin(a + s * 0.2) * hr * 0.9);
    }
    ctx.fill();
    disc(ctx, hx, hy, hr, body, OUTLINE, 2.5);
    if (biting && off === 0) {
      ctx.fillStyle = '#ff3b3b';
      ctx.beginPath();
      ctx.arc(hx + Math.cos(a) * hr * 0.55, hy + Math.sin(a) * hr * 0.55, hr * 0.45, 0, TAU);
      ctx.fill();
    }
    eyePair(ctx, hx, hy, hr, a, frenzy ? '#ff3a1a' : '#ffb03a', 0.55);
  }
  if (e.vuln > 0) weakPoint(ctx, -Math.cos(face) * r * 0.35, -Math.sin(face) * r * 0.35, r * 0.3, time);
  ctx.restore();
}

// ---------------------------------------------------------------- Minos

function minos(ctx, r, face, body, e, time) {
  ctx.save();
  if (e.hidden) {
    // Dissous : filigrane violet, il se matérialisera au centre de la couronne rouge.
    ctx.globalAlpha *= 0.28 + 0.12 * Math.sin(time * 20);
  }
  // Queue de serpent enroulée autour de lui (elle balaie à 360° lors du fouet).
  const whip = e.tele && e.tele.area;
  ctx.strokeStyle = '#1d3a24';
  ctx.lineWidth = whip ? 7 : 5;
  ctx.beginPath();
  const turns = 1.6;
  const steps = 40;
  for (let i = 0; i <= steps; i++) {
    const u = i / steps;
    const a = time * (whip ? 6 : 1.2) + u * turns * TAU;
    const rr = r * (1.05 + 0.35 * u) * (whip ? 1 + 0.25 * (e.tele.progress ?? 0) : 1);
    if (i === 0) ctx.moveTo(Math.cos(a) * rr, Math.sin(a) * rr);
    else ctx.lineTo(Math.cos(a) * rr, Math.sin(a) * rr);
  }
  ctx.stroke();
  ctx.strokeStyle = '#4f8a5a';
  ctx.lineWidth = 2;
  ctx.stroke();
  // Robe et capuche.
  disc(ctx, 0, 0, r, body);
  ctx.fillStyle = '#160f2e';
  ctx.beginPath();
  ctx.arc(Math.cos(face) * r * 0.12, Math.sin(face) * r * 0.12, r * 0.62, 0, TAU);
  ctx.fill();
  // Mitre dorée (toujours vers le haut de l'écran : on le reconnaît à sa coiffe).
  ctx.fillStyle = '#ffcf5a';
  ctx.strokeStyle = OUTLINE;
  ctx.lineWidth = 2.5;
  ctx.beginPath();
  ctx.moveTo(-r * 0.45, -r * 0.55);
  ctx.lineTo(-r * 0.3, -r * 1.45);
  ctx.lineTo(0, -r * 1.05);
  ctx.lineTo(r * 0.3, -r * 1.45);
  ctx.lineTo(r * 0.45, -r * 0.55);
  ctx.closePath();
  ctx.fill();
  ctx.stroke();
  ctx.fillStyle = '#ff3b3b';
  ctx.beginPath();
  ctx.arc(0, -r * 0.85, r * 0.1, 0, TAU);
  ctx.fill();
  eyePair(ctx, Math.cos(face) * r * 0.12, Math.sin(face) * r * 0.12, r * 0.62, face, '#f3f0ff', 0.45);
  if (e.vuln > 0) weakPoint(ctx, 0, r * 0.35, r * 0.28, time);
  ctx.restore();
}

// ---------------------------------------------------------------- Éphialte, le Colosse

// Contour rocheux : rayon relatif de 12 sommets (fixe, déterministe).
const ROCK = [1, 0.93, 1.04, 0.96, 1.02, 0.9, 1.05, 0.95, 1, 0.92, 1.03, 0.97];

function colosse(ctx, r, face, body, e, time) {
  const raised = e.state === 'poing' && e.sub !== 'recover';
  const stuck = e.state === 'poing' && e.sub === 'recover';
  // Poings : levés quand il arme, l'un planté au sol quand son bras est coincé.
  for (const s of [-1, 1]) {
    const reach = stuck && s === 1 ? 1.35 : raised ? 0.8 : 0.95;
    const a = face + s * (raised ? 1.25 : 0.95);
    const fx = Math.cos(a) * r * reach;
    const fy = Math.sin(a) * r * reach;
    disc(ctx, fx, fy, r * 0.42, '#5a4a42');
    // Bracelet de fer (menotte).
    ctx.strokeStyle = e.shielded ? '#b48cff' : '#3a3438';
    ctx.lineWidth = 4;
    ctx.beginPath();
    ctx.arc(fx, fy, r * 0.3, 0, TAU);
    ctx.stroke();
  }
  // Corps : bloc de pierre au contour irrégulier.
  ctx.fillStyle = body;
  ctx.strokeStyle = OUTLINE;
  ctx.lineWidth = 3.5;
  ctx.beginPath();
  for (let i = 0; i < ROCK.length; i++) {
    const a = (i / ROCK.length) * TAU;
    const x = Math.cos(a) * r * ROCK[i];
    const y = Math.sin(a) * r * ROCK[i];
    if (i === 0) ctx.moveTo(x, y);
    else ctx.lineTo(x, y);
  }
  ctx.closePath();
  ctx.fill();
  ctx.stroke();
  // Fissures (la lave affleure quand le point faible est exposé).
  const exposed = e.vuln > 0;
  ctx.strokeStyle = exposed ? '#ff8a2a' : '#2a201c';
  ctx.lineWidth = exposed ? 3 : 2;
  ctx.beginPath();
  ctx.moveTo(-r * 0.5, -r * 0.2);
  ctx.lineTo(-r * 0.1, r * 0.05);
  ctx.lineTo(r * 0.15, -r * 0.35);
  ctx.moveTo(-r * 0.1, r * 0.05);
  ctx.lineTo(r * 0.05, r * 0.5);
  ctx.stroke();
  // Chaînes autour de la taille : maillons ; elles brillent tant que les geôliers vivent.
  const links = 14;
  ctx.lineWidth = 3;
  for (let i = 0; i < links; i++) {
    const a = (i / links) * TAU + (e.shielded ? time * 0.8 : 0);
    const x = Math.cos(a) * r * 1.08;
    const y = Math.sin(a) * r * 1.08;
    ctx.strokeStyle = e.shielded ? (i % 2 ? '#ffd23c' : '#b48cff') : '#4a4448';
    ctx.beginPath();
    ctx.ellipse(x, y, r * 0.11, r * 0.06, a + Math.PI / 2, 0, TAU);
    ctx.stroke();
  }
  if (e.shielded) {
    ctx.save();
    ctx.globalCompositeOperation = 'lighter';
    ctx.strokeStyle = `rgba(180, 140, 255, ${0.35 + 0.25 * Math.sin(time * 6)})`;
    ctx.lineWidth = 6;
    ctx.beginPath();
    ctx.arc(0, 0, r * 1.25, 0, TAU);
    ctx.stroke();
    ctx.restore();
  }
  eyePair(ctx, 0, 0, r * 0.7, face, exposed ? '#ff8a2a' : '#ffe14a', 0.4);
  if (exposed) weakPoint(ctx, -r * 0.1, r * 0.05, r * 0.24, time);
}

export const BOSS_ART = { cerbere, minos, colosse };

// Rendu canvas 2D — ne modifie JAMAIS l'état. Dessine plateau, terrain, unités, surbrillances,
// main et panneau d'information. Tout texte est en police système (aucun emoji : rendu
// identique en navigateur headless).

import { TERRAIN, TYPE, RULES, STATE_PLAYING, STATE_WON, key } from './engine.mjs';
import { cardById } from './cards.mjs';
import { HL } from './controller.mjs';
import { BOARD, HAND, PANEL, CANVAS_W, CANVAS_H, cellRect, cellCenter, handRect } from './layout.mjs';

export const WIN_TEXT = 'VICTOIRE';
export const LOSE_TEXT = 'DEFAITE';

export const COLORS = Object.freeze({
  bg: '#0b0e11',
  panel: '#151a20',
  text: '#eceff1',
  muted: '#90a4ae',
  grid: '#0b0e11',
  p1: '#2f7de1',
  p2: '#d84b3a',
  hero: '#ffd54f',
  shield: '#4dd0e1',
  frozen: 'rgba(120, 200, 255, 0.55)',
  terrain: {
    [TERRAIN.PLAINE]: ['#3b5d3a', '#35553a'],
    [TERRAIN.FORET]: ['#1f4d2a', '#1a4526'],
    [TERRAIN.ROCHER]: ['#55575a', '#4b4d50'],
    [TERRAIN.MARAIS]: ['#2c4f5c', '#274854'],
    [TERRAIN.BRASIER]: ['#7a2a14', '#6d2410'],
    [TERRAIN.FONTAINE]: ['#2d4f8a', '#284780'],
  },
  hl: {
    [HL.SELECTED]: 'rgba(255, 235, 59, 0.45)',
    [HL.MOVE]: 'rgba(66, 165, 245, 0.45)',
    [HL.ATTACK]: 'rgba(244, 67, 54, 0.55)',
    [HL.DEPLOY]: 'rgba(102, 187, 106, 0.5)',
    [HL.TARGET]: 'rgba(255, 152, 0, 0.5)',
  },
});

/** Glyphe à deux lettres par carte d'unité (lisible sans police d'emoji). */
export const GLYPHS = Object.freeze({
  gobelin: 'Go', recruteur_gobelin: 'Rc', loup: 'Lp', meute_de_loups: 'La', archer: 'Ar',
  chevalier: 'Ch', assassin: 'As', golem: 'Gm', elementaire_de_feu: 'El', ogre: 'Og',
  dragon: 'Dr', pretresse: 'Pr', ombre: 'Om', seigneur_de_guerre: 'SG', archimage: 'AM',
  necromancienne: 'Nc', paladin: 'Pa',
});

export const TERRAIN_LABEL = Object.freeze({
  [TERRAIN.PLAINE]: 'Plaine',
  [TERRAIN.FORET]: 'Forêt (+1 armure)',
  [TERRAIN.ROCHER]: 'Rocher (infranchissable)',
  [TERRAIN.MARAIS]: 'Marais (stoppe le déplacement)',
  [TERRAIN.BRASIER]: 'Brasier (2 dégâts en fin de tour)',
  [TERRAIN.FONTAINE]: 'Fontaine (+1 mana si occupée)',
});

export function overlayTextFor(engine) {
  if (engine.state === STATE_PLAYING) return '';
  return engine.state === STATE_WON ? WIN_TEXT : LOSE_TEXT;
}

export function objectiveTextFor(engine) {
  const mine = engine.towerOf(0).hp;
  const theirs = engine.towerOf(1).hp;
  return `Objectif : détruire la tour ennemie (${theirs} PV). Votre tour : ${mine} PV. Tour ${engine.round}.`;
}

/** Découpe un texte en lignes tenant dans `maxWidth` (mesure fournie par le contexte). */
export function wrapText(ctx, text, maxWidth) {
  const words = String(text).split(/\s+/).filter(Boolean);
  const lines = [];
  let line = '';
  for (const word of words) {
    const candidate = line ? `${line} ${word}` : word;
    if (ctx.measureText(candidate).width <= maxWidth || !line) {
      line = candidate;
    } else {
      lines.push(line);
      line = word;
    }
  }
  if (line) lines.push(line);
  return lines;
}

function statsLine(card) {
  return `ATQ ${card.atk} · PV ${card.hp} · MV ${card.mov} · P ${card.rng}`;
}

export class Renderer {
  constructor(canvas) {
    this.canvas = canvas;
    this.ctx = canvas.getContext('2d');
    if (this.ctx.measureText === undefined) this.ctx.measureText = (t) => ({ width: t.length * 6 });
  }

  render(engine, controller, human = 0) {
    const ctx = this.ctx;
    ctx.fillStyle = COLORS.bg;
    ctx.fillRect(0, 0, CANVAS_W, CANVAS_H);
    const hl = controller ? controller.highlights() : { cells: new Map(), units: new Map(), tower: false };
    this.drawBoard(engine, hl);
    this.drawTowers(engine, hl);
    this.drawUnits(engine, hl, human);
    this.drawHand(engine, controller, human);
    this.drawPanel(engine, controller, human);
  }

  drawBoard(engine, hl) {
    const ctx = this.ctx;
    for (let y = 0; y < BOARD.rows; y++) {
      for (let x = 0; x < BOARD.cols; x++) {
        const cell = engine.cell(x, y);
        const r = cellRect(x, y);
        const shades = COLORS.terrain[cell.terrain] ?? COLORS.terrain[TERRAIN.PLAINE];
        ctx.fillStyle = shades[(x + y) % 2];
        ctx.fillRect(r.x, r.y, r.w, r.h);
        this.drawTerrainMark(cell, r);
        const mark = hl.cells.get(key(x, y));
        if (mark) {
          ctx.fillStyle = COLORS.hl[mark];
          ctx.fillRect(r.x, r.y, r.w, r.h);
        }
        ctx.strokeStyle = COLORS.grid;
        ctx.lineWidth = 1;
        ctx.strokeRect(r.x + 0.5, r.y + 0.5, r.w - 1, r.h - 1);
      }
    }
  }

  drawTerrainMark(cell, r) {
    const ctx = this.ctx;
    const cx = r.x + r.w / 2;
    const cy = r.y + r.h / 2;
    ctx.save();
    switch (cell.terrain) {
      case TERRAIN.FORET:
        ctx.fillStyle = '#2e7d32';
        for (const [dx, dy] of [[-16, 8], [10, 12], [-2, -10]]) {
          ctx.beginPath();
          ctx.moveTo(cx + dx, cy + dy - 12);
          ctx.lineTo(cx + dx - 8, cy + dy + 6);
          ctx.lineTo(cx + dx + 8, cy + dy + 6);
          ctx.closePath();
          ctx.fill();
        }
        break;
      case TERRAIN.ROCHER:
        ctx.fillStyle = '#8d8f93';
        ctx.beginPath();
        ctx.moveTo(cx - 20, cy + 16);
        ctx.lineTo(cx - 8, cy - 14);
        ctx.lineTo(cx + 6, cy - 4);
        ctx.lineTo(cx + 20, cy + 16);
        ctx.closePath();
        ctx.fill();
        break;
      case TERRAIN.MARAIS:
        ctx.strokeStyle = '#4fc3f7';
        ctx.lineWidth = 2;
        for (const dy of [-10, 0, 10]) {
          ctx.beginPath();
          ctx.moveTo(cx - 18, cy + dy);
          ctx.quadraticCurveTo(cx - 9, cy + dy - 6, cx, cy + dy);
          ctx.quadraticCurveTo(cx + 9, cy + dy + 6, cx + 18, cy + dy);
          ctx.stroke();
        }
        break;
      case TERRAIN.BRASIER:
        ctx.fillStyle = '#ff9800';
        ctx.beginPath();
        ctx.moveTo(cx, cy - 20);
        ctx.quadraticCurveTo(cx + 18, cy, cx, cy + 18);
        ctx.quadraticCurveTo(cx - 18, cy, cx, cy - 20);
        ctx.fill();
        ctx.fillStyle = '#ffeb3b';
        ctx.beginPath();
        ctx.arc(cx, cy + 6, 6, 0, Math.PI * 2);
        ctx.fill();
        break;
      case TERRAIN.FONTAINE:
        ctx.strokeStyle = '#80deea';
        ctx.lineWidth = 3;
        ctx.beginPath();
        ctx.arc(cx, cy, 16, 0, Math.PI * 2);
        ctx.stroke();
        ctx.fillStyle = '#e0f7fa';
        ctx.beginPath();
        ctx.arc(cx, cy, 5, 0, Math.PI * 2);
        ctx.fill();
        break;
      default:
        break;
    }
    if (cell.ttl > 0) {
      ctx.fillStyle = COLORS.text;
      ctx.font = 'bold 11px Arial';
      ctx.textAlign = 'right';
      ctx.fillText(String(cell.ttl), r.x + r.w - 4, r.y + 12);
    }
    ctx.restore();
  }

  drawTowers(engine, hl) {
    const ctx = this.ctx;
    for (const tower of engine.towers) {
      const r = cellRect(tower.x, tower.y);
      ctx.fillStyle = tower.owner === 0 ? COLORS.p1 : COLORS.p2;
      ctx.fillRect(r.x + 8, r.y + 10, r.w - 16, r.h - 14);
      ctx.fillStyle = '#0b0e11';
      for (let i = 0; i < 3; i++) ctx.fillRect(r.x + 12 + i * 14, r.y + 4, 8, 8);
      ctx.fillStyle = COLORS.text;
      ctx.font = 'bold 15px Arial';
      ctx.textAlign = 'center';
      ctx.fillText(`${tower.hp}`, r.x + r.w / 2, r.y + r.h / 2 + 10);
      ctx.font = '10px Arial';
      ctx.fillText('TOUR', r.x + r.w / 2, r.y + r.h / 2 - 6);
      if (hl.tower && tower.owner !== 0) {
        ctx.strokeStyle = '#f44336';
        ctx.lineWidth = 4;
        ctx.strokeRect(r.x + 2, r.y + 2, r.w - 4, r.h - 4);
      }
    }
  }

  drawUnits(engine, hl, human) {
    const ctx = this.ctx;
    for (const u of engine.units.values()) {
      const c = cellCenter(u.x, u.y);
      const card = cardById(u.cardId);
      const mark = hl.units.get(u.id);
      const canAct = engine.canAct(u) && (!u.attacked || u.movLeft > 0);
      ctx.save();
      if (mark) {
        ctx.fillStyle = COLORS.hl[mark];
        ctx.beginPath();
        ctx.arc(c.x, c.y, 29, 0, Math.PI * 2);
        ctx.fill();
      }
      ctx.globalAlpha = u.owner === engine.current && !canAct ? 0.6 : 1;
      ctx.fillStyle = u.owner === 0 ? COLORS.p1 : COLORS.p2;
      ctx.beginPath();
      ctx.arc(c.x, c.y, 22, 0, Math.PI * 2);
      ctx.fill();
      if (card.type === TYPE.HERO) {
        ctx.strokeStyle = COLORS.hero;
        ctx.lineWidth = 3;
        ctx.stroke();
      }
      if (u.shield) {
        ctx.strokeStyle = COLORS.shield;
        ctx.lineWidth = 3;
        ctx.beginPath();
        ctx.arc(c.x, c.y, 26, 0, Math.PI * 2);
        ctx.stroke();
      }
      ctx.fillStyle = COLORS.text;
      ctx.font = 'bold 15px Arial';
      ctx.textAlign = 'center';
      ctx.fillText(GLYPHS[u.cardId] ?? '??', c.x, c.y + 5);
      // badges ATQ / PV
      ctx.font = 'bold 11px Arial';
      ctx.fillStyle = '#ffb74d';
      ctx.fillRect(c.x - 28, c.y + 14, 20, 14);
      ctx.fillStyle = '#000';
      ctx.fillText(String(engine.atkOf(u)), c.x - 18, c.y + 25);
      ctx.fillStyle = '#81c784';
      ctx.fillRect(c.x + 8, c.y + 14, 20, 14);
      ctx.fillStyle = '#000';
      ctx.fillText(String(u.hp), c.x + 18, c.y + 25);
      if (u.equips.length > 0) {
        ctx.fillStyle = COLORS.hero;
        for (let i = 0; i < u.equips.length; i++) {
          ctx.beginPath();
          ctx.arc(c.x - 22 + i * 10, c.y - 20, 4, 0, Math.PI * 2);
          ctx.fill();
        }
      }
      if (engine.isFrozen(u)) {
        ctx.fillStyle = COLORS.frozen;
        ctx.beginPath();
        ctx.arc(c.x, c.y, 22, 0, Math.PI * 2);
        ctx.fill();
      }
      if (u.owner === human && canAct && engine.current === human) {
        ctx.fillStyle = '#69f0ae';
        ctx.beginPath();
        ctx.arc(c.x + 20, c.y - 20, 5, 0, Math.PI * 2);
        ctx.fill();
      }
      ctx.restore();
    }
  }

  drawHand(engine, controller, human) {
    const ctx = this.ctx;
    const p = engine.players[human];
    const sel = controller && controller.sel && controller.sel.kind === 'card' ? controller.sel.hand : -1;
    ctx.fillStyle = COLORS.muted;
    ctx.font = '12px Arial';
    ctx.textAlign = 'left';
    ctx.fillText(`Main (${p.hand.length}/${RULES.HAND_MAX}) — touches 1-7 pour choisir, clic sur la cible`, HAND.x, HAND.y - 8);
    p.hand.forEach((id, i) => {
      const card = cardById(id);
      const r = handRect(i);
      const affordable = p.mana >= card.cost;
      ctx.save();
      ctx.globalAlpha = affordable ? 1 : 0.55;
      ctx.fillStyle = card.type === TYPE.HERO ? '#3e2f0e' : card.type === TYPE.SPELL ? '#2a1f4e'
        : card.type === TYPE.EQUIP ? '#3a3a1a' : '#1e2a3a';
      ctx.fillRect(r.x, r.y, r.w, r.h);
      ctx.strokeStyle = i === sel ? '#ffeb3b' : '#455a64';
      ctx.lineWidth = i === sel ? 3 : 1;
      ctx.strokeRect(r.x + 1, r.y + 1, r.w - 2, r.h - 2);
      ctx.fillStyle = '#42a5f5';
      ctx.beginPath();
      ctx.arc(r.x + 14, r.y + 14, 11, 0, Math.PI * 2);
      ctx.fill();
      ctx.fillStyle = '#fff';
      ctx.font = 'bold 13px Arial';
      ctx.textAlign = 'center';
      ctx.fillText(String(card.cost), r.x + 14, r.y + 19);
      ctx.fillStyle = COLORS.text;
      ctx.font = 'bold 11px Arial';
      ctx.textAlign = 'left';
      const nameLines = wrapText(ctx, card.name, r.w - 34);
      ctx.fillText(nameLines[0], r.x + 29, r.y + 13);
      if (nameLines[1]) ctx.fillText(nameLines[1], r.x + 29, r.y + 25);
      ctx.fillStyle = COLORS.muted;
      ctx.font = '10px Arial';
      const typeLabel = { creature: 'Créature', hero: 'Héros', spell: 'Sort', equip: 'Équipement' }[card.type];
      ctx.fillText(typeLabel, r.x + 6, r.y + 40);
      let y = r.y + 54;
      if (card.type === TYPE.CREATURE || card.type === TYPE.HERO) {
        ctx.fillStyle = COLORS.text;
        ctx.fillText(statsLine(card), r.x + 6, y);
        y += 13;
      }
      ctx.fillStyle = COLORS.muted;
      ctx.font = '9px Arial';
      const lines = wrapText(ctx, card.text, r.w - 12).slice(0, 5);
      for (const line of lines) {
        ctx.fillText(line, r.x + 6, y);
        y += 11;
      }
      ctx.restore();
    });
  }

  drawPanel(engine, controller, human) {
    const ctx = this.ctx;
    ctx.fillStyle = COLORS.panel;
    ctx.fillRect(PANEL.x, PANEL.y, PANEL.w, PANEL.h);
    const p = engine.players[human];
    const foe = engine.players[1 - human];
    let y = PANEL.y + 24;
    const line = (text, font = '13px Arial', color = COLORS.text) => {
      ctx.fillStyle = color;
      ctx.font = font;
      ctx.textAlign = 'left';
      ctx.fillText(text, PANEL.x + 14, y);
      y += 19;
    };
    line(`BASTION — ${engine.mapName}`, 'bold 15px Arial', COLORS.hero);
    const whose = engine.over ? 'Partie terminée' : engine.current === human ? 'À VOUS DE JOUER' : 'Tour de l\'adversaire…';
    line(`Tour ${engine.round} — ${whose}`, 'bold 13px Arial');
    line(`Mana : ${p.mana} / ${p.manaMax}   Deck : ${p.deck.length}   Adversaire : ${foe.mana} mana, ${foe.hand.length} cartes, deck ${foe.deck.length}`);
    line(`Votre tour : ${engine.towerOf(human).hp} PV   Tour ennemie : ${engine.towerOf(1 - human).hp} PV`);
    y += 6;
    const u = controller ? controller.selectedUnit() : null;
    if (u) {
      const card = cardById(u.cardId);
      line(`${u.name} (${u.owner === human ? 'vous' : 'ennemi'})`, 'bold 14px Arial', u.owner === human ? '#90caf9' : '#ef9a9a');
      line(`ATQ ${engine.atkOf(u)}  PV ${u.hp}/${u.hpMax}  Déplacement ${u.movLeft}/${engine.movOf(u)}  Portée ${engine.rngOf(u)}  Armure ${engine.armorOf(u)}`);
      const kws = [...engine.keywordsOf(u)];
      if (kws.length) line(`Mots-clés : ${kws.join(', ')}`, '12px Arial', COLORS.muted);
      if (u.equips.length) line(`Équipement : ${u.equips.map((e) => cardById(e).name).join(', ')}  (U = rendre en main, 1 mana)`, '12px Arial', COLORS.muted);
      if (card.ability) line(`Capacité (A) : ${card.ability.name} — ${card.ability.cost} mana${u.abilityUsed ? ' (utilisée)' : ''}`, '12px Arial', COLORS.hero);
      ctx.font = '12px Arial';
      for (const l of wrapText(ctx, card.text, PANEL.w - 28)) line(l, '12px Arial', COLORS.muted);
      line(`Terrain : ${TERRAIN_LABEL[engine.cell(u.x, u.y).terrain]}`, '12px Arial', COLORS.muted);
      if (u.shield) line('Bouclier actif', '12px Arial', COLORS.shield);
      if (engine.isFrozen(u)) line('Gelée : ne peut ni bouger, ni attaquer', '12px Arial', COLORS.shield);
    } else {
      const card = controller ? controller.selectedCard() : null;
      if (card) {
        line(`${card.name} — ${card.cost} mana`, 'bold 14px Arial', '#ffcc80');
        ctx.font = '12px Arial';
        for (const l of wrapText(ctx, card.text, PANEL.w - 28)) line(l, '12px Arial', COLORS.muted);
        line('Cliquez une case / unité en surbrillance. Échap pour annuler.', '12px Arial', COLORS.muted);
      } else {
        line('Cliquez une de vos unités pour la déplacer ou attaquer.', '12px Arial', COLORS.muted);
        line('Cliquez une carte (ou 1-7) puis sa cible pour la jouer.', '12px Arial', COLORS.muted);
        line('E / Entrée : fin de tour · A : capacité du héros · U : rendre un équipement.', '12px Arial', COLORS.muted);
      }
    }
    if (controller && controller.message) {
      y += 6;
      ctx.font = 'bold 12px Arial';
      for (const l of wrapText(ctx, controller.message, PANEL.w - 28)) line(l, 'bold 12px Arial', '#ffab91');
    }
    y = PANEL.y + PANEL.h - 84;
    line('Terrain', 'bold 12px Arial', COLORS.muted);
    line('Forêt +1 armure · Rocher bloque · Marais stoppe · Brasier brûle 2 · Fontaine +1 mana', '11px Arial', COLORS.muted);
    line('Zone de contrôle : entrer au contact d\'un ennemi arrête le déplacement.', '11px Arial', COLORS.muted);
    line('Zone de déploiement : à 2 cases de votre tour, ou à 1 case d\'un héros allié.', '11px Arial', COLORS.muted);
  }

  renderOverlay(engine) {
    const ctx = this.ctx;
    ctx.fillStyle = 'rgba(0,0,0,0.5)';
    ctx.fillRect(0, 0, CANVAS_W, CANVAS_H);
    ctx.fillStyle = COLORS.text;
    ctx.font = 'bold 40px Arial';
    ctx.textAlign = 'center';
    ctx.fillText(overlayTextFor(engine), CANVAS_W / 2, CANVAS_H / 2);
  }
}

// Contrôleur d'interface — machine à états de SÉLECTION, pure (aucun DOM).
// Traduit des clics sur des cases / cartes en actions du moteur, et expose les surbrillances
// à dessiner. Le moteur reste l'unique juge de la légalité : le contrôleur ne fait que proposer.

import { TYPE, TARGET, ABILITY, RULES, key } from './engine.mjs';
import { cardById, isUnitCard } from './cards.mjs';

export const HL = Object.freeze({
  SELECTED: 'selected',
  MOVE: 'move',
  ATTACK: 'attack',
  DEPLOY: 'deploy',
  TARGET: 'target',
});

export class Controller {
  constructor(engine, { human = 0 } = {}) {
    this.engine = engine;
    this.human = human;
    this.sel = null;
    this.message = '';
  }

  get isHumanTurn() {
    return !this.engine.over && this.engine.current === this.human;
  }

  reset() {
    this.sel = null;
    this.message = '';
  }

  /** Unité sélectionnée (mode unité ou capacité), ou null. */
  selectedUnit() {
    if (!this.sel) return null;
    if (this.sel.kind === 'unit' || this.sel.kind === 'ability') return this.engine.unit(this.sel.id);
    return null;
  }

  selectedCard() {
    if (!this.sel || this.sel.kind !== 'card') return null;
    const hand = this.engine.players[this.human].hand;
    return this.sel.hand < hand.length ? cardById(hand[this.sel.hand]) : null;
  }

  // --- surbrillances ---------------------------------------------------------------------

  /** @returns {{cells: Map<string,string>, units: Map<number,string>, tower: boolean}} */
  highlights() {
    const cells = new Map();
    const units = new Map();
    let tower = false;
    const e = this.engine;
    if (!this.sel || !this.isHumanTurn) return { cells, units, tower };
    if (this.sel.kind === 'unit') {
      const u = e.unit(this.sel.id);
      if (!u) return { cells, units, tower };
      cells.set(key(u.x, u.y), HL.SELECTED);
      units.set(u.id, HL.SELECTED);
      for (const c of e.reachable(u).values()) cells.set(key(c.x, c.y), HL.MOVE);
      for (const t of e.attackTargets(u)) {
        if (t.tower) tower = true;
        else units.set(t.unit, HL.ATTACK);
      }
      return { cells, units, tower };
    }
    if (this.sel.kind === 'ability') {
      const u = e.unit(this.sel.id);
      if (!u) return { cells, units, tower };
      units.set(u.id, HL.SELECTED);
      for (const t of e.abilityTargets(u)) if (t.unit) units.set(t.unit, HL.TARGET);
      return { cells, units, tower };
    }
    const card = this.selectedCard();
    if (!card) return { cells, units, tower };
    for (const c of this.cardTargetCells(card)) cells.set(key(c.x, c.y), isUnitCard(card) ? HL.DEPLOY : HL.TARGET);
    for (const id of this.cardTargetUnits(card)) units.set(id, HL.TARGET);
    return { cells, units, tower };
  }

  affordable(card, cell) {
    return this.engine.players[this.human].mana >= this.engine.costOf(card, this.human, cell);
  }

  cardTargetCells(card) {
    const e = this.engine;
    if (isUnitCard(card)) return this.affordable(card) ? e.deployCells(this.human) : [];
    if (card.type !== TYPE.SPELL) return [];
    let pool = [];
    if (card.target === TARGET.CELL) {
      for (let y = 0; y < e.board.length; y++) for (let x = 0; x < e.board[0].length; x++) pool.push({ x, y });
    } else if (card.target === TARGET.EMPTY_CELL) {
      pool = e.wallCells();
    } else if (card.target === TARGET.ALLY_THEN_CELL && this.sel.stage === 1) {
      const u = e.unit(this.sel.unitId);
      pool = u ? e.portalCells(u, card.range) : [];
    }
    return pool.filter((c) => this.affordable(card, c));
  }

  cardTargetUnits(card) {
    const e = this.engine;
    let pool = [];
    if (card.type === TYPE.EQUIP) {
      pool = e.unitsOf(this.human).filter((u) => u.equips.length < RULES.MAX_EQUIPS);
    } else if (card.type === TYPE.SPELL) {
      if (card.target === TARGET.ALLY) pool = e.unitsOf(this.human);
      else if (card.target === TARGET.ENEMY) pool = e.unitsOf(1 - this.human);
      else if (card.target === TARGET.UNIT) pool = [...e.units.values()];
      else if (card.target === TARGET.ALLY_THEN_CELL && this.sel.stage === 0) pool = e.unitsOf(this.human);
    }
    return pool.filter((u) => this.affordable(card, u)).map((u) => u.id);
  }

  // --- entrées -----------------------------------------------------------------------------

  apply(action) {
    const res = this.engine.apply(action);
    this.message = res.ok ? '' : res.error;
    return res.ok;
  }

  clickHand(index) {
    if (!this.isHumanTurn) return false;
    const hand = this.engine.players[this.human].hand;
    if (index < 0 || index >= hand.length) return false;
    if (this.sel && this.sel.kind === 'card' && this.sel.hand === index) {
      this.sel = null;
      return true;
    }
    const card = cardById(hand[index]);
    if (!this.affordable(card)) {
      const discount = card.type === TYPE.SPELL;
      this.message = discount
        ? `${card.name} coûte ${card.cost} (1 de moins près d'un Archimage).`
        : `Mana insuffisant pour ${card.name} (${card.cost}).`;
      if (!discount) return false;
    } else {
      this.message = '';
    }
    this.sel = { kind: 'card', hand: index, stage: 0, unitId: null };
    return true;
  }

  clickCell(x, y) {
    if (!this.isHumanTurn) return false;
    const e = this.engine;
    const occupant = e.unitAt(x, y);
    if (this.sel && this.sel.kind === 'card') return this.clickCellWithCard(x, y, occupant);
    if (this.sel && this.sel.kind === 'ability') {
      const hero = e.unit(this.sel.id);
      if (occupant && hero && e.abilityTargets(hero).some((t) => t.unit === occupant.id)) {
        this.apply({ type: 'ability', unit: hero.id, target: { unit: occupant.id } });
        this.sel = null;
        return true;
      }
      this.sel = null;
      return true;
    }
    if (this.sel && this.sel.kind === 'unit') {
      const u = e.unit(this.sel.id);
      if (!u) {
        this.sel = null;
        return true;
      }
      if (occupant && occupant.owner === this.human) {
        this.sel = occupant.id === u.id ? null : { kind: 'unit', id: occupant.id };
        return true;
      }
      const targets = e.attackTargets(u);
      if (occupant && targets.some((t) => t.unit === occupant.id)) {
        this.apply({ type: 'attack', unit: u.id, target: { unit: occupant.id } });
        this.sel = null;
        return true;
      }
      const enemyTower = e.towerOf(1 - this.human);
      if (enemyTower.x === x && enemyTower.y === y && targets.some((t) => t.tower)) {
        this.apply({ type: 'attack', unit: u.id, target: { tower: true } });
        this.sel = null;
        return true;
      }
      if (e.reachable(u).has(key(x, y))) {
        this.apply({ type: 'move', unit: u.id, x, y });
        return true;
      }
      this.sel = null;
      return true;
    }
    if (occupant && occupant.owner === this.human) {
      this.sel = { kind: 'unit', id: occupant.id };
      this.message = e.isSummonSick(occupant) ? `${occupant.name} vient d'arriver : elle agira au prochain tour.`
        : e.isFrozen(occupant) ? `${occupant.name} est gelée.` : '';
      return true;
    }
    return false;
  }

  clickCellWithCard(x, y, occupant) {
    const card = this.selectedCard();
    const hand = this.sel.hand;
    if (!card) {
      this.sel = null;
      return true;
    }
    if (isUnitCard(card)) {
      if (this.cardTargetCells(card).some((c) => c.x === x && c.y === y)) {
        this.apply({ type: 'play', hand, x, y });
        this.sel = null;
        return true;
      }
      this.sel = null;
      return true;
    }
    if (card.type === TYPE.EQUIP || (card.type === TYPE.SPELL
      && [TARGET.ALLY, TARGET.ENEMY, TARGET.UNIT].includes(card.target))) {
      if (occupant && this.cardTargetUnits(card).includes(occupant.id)) {
        this.apply({ type: 'play', hand, unit: occupant.id });
      }
      this.sel = null;
      return true;
    }
    if (card.target === TARGET.ALLY_THEN_CELL) {
      if (this.sel.stage === 0) {
        if (occupant && this.cardTargetUnits(card).includes(occupant.id)) {
          this.sel = { kind: 'card', hand, stage: 1, unitId: occupant.id };
          this.message = 'Choisissez la case de destination.';
          return true;
        }
        this.sel = null;
        return true;
      }
      if (this.cardTargetCells(card).some((c) => c.x === x && c.y === y)) {
        this.apply({ type: 'play', hand, unit: this.sel.unitId, toX: x, toY: y });
      }
      this.sel = null;
      return true;
    }
    // sorts de zone / de case
    if (this.cardTargetCells(card).some((c) => c.x === x && c.y === y)) {
      this.apply({ type: 'play', hand, x, y });
    }
    this.sel = null;
    return true;
  }

  /** Capacité active du héros sélectionné : immédiate (ralliement) ou passe en ciblage. */
  useAbility() {
    if (!this.isHumanTurn) return false;
    const u = this.selectedUnit();
    if (!u) {
      this.message = 'Sélectionnez d\'abord un héros.';
      return false;
    }
    const card = cardById(u.cardId);
    if (!card.ability) {
      this.message = `${u.name} n'a pas de capacité.`;
      return false;
    }
    const targets = this.engine.abilityTargets(u);
    if (targets.length === 0) {
      this.message = `${card.ability.name} indisponible (mana ${card.ability.cost}, une fois par tour, cible à portée).`;
      return false;
    }
    if (card.ability.kind === ABILITY.RALLY) {
      this.apply({ type: 'ability', unit: u.id, target: targets[0] });
      this.sel = { kind: 'unit', id: u.id };
      return true;
    }
    this.sel = { kind: 'ability', id: u.id };
    this.message = `${card.ability.name} : choisissez une cible.`;
    return true;
  }

  unequip(index = 0) {
    if (!this.isHumanTurn) return false;
    const u = this.selectedUnit();
    if (!u) {
      this.message = 'Sélectionnez d\'abord une unité équipée.';
      return false;
    }
    if (u.equips.length === 0) {
      this.message = `${u.name} ne porte rien.`;
      return false;
    }
    return this.apply({ type: 'unequip', unit: u.id, index: Math.min(index, u.equips.length - 1) });
  }

  cancel() {
    this.sel = null;
    this.message = '';
    return true;
  }

  endTurn() {
    if (!this.isHumanTurn) return false;
    this.sel = null;
    return this.apply({ type: 'end' });
  }
}

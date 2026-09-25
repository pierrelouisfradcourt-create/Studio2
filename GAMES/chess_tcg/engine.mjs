// Moteur de règles — PUR et DÉTERMINISTE. Aucune dépendance DOM, aucun aléa non injecté.
// Le plateau est une grille 7×8 (maps.mjs). Chaque camp a une Tour ; détruire celle de
// l'adversaire gagne la partie. Les cartes coûtent du mana (1 au 1er tour, +1 par tour, max 10).
//
// Patterns cités (knowledge_base/patterns/tactical_combat) :
//   pat-zone-of-control — entrer au contact d'un ennemi arrête le déplacement (`reachable`).
//   pat-damage-floor    — tout coup inflige au moins 1 dégât ; le CODE vient de la brique
//                         sys-damage-floor (`applyHit`), réutilisée telle quelle.

import { applyHit } from '../../knowledge_base/systems/combat/damage_floor.mjs';
import { CARDS, DECK_LIST, TYPE, KW, AURA, ABILITY, TARGET, cardById, isUnitCard } from './cards.mjs';
import { COLS, ROWS, TERRAIN, TOWER_COL, MAP_TEMPLATES, buildBoard, templateName } from './maps.mjs';

export { COLS, ROWS, TERRAIN, CARDS, TYPE, KW, AURA, ABILITY, TARGET };

export const STATE_PLAYING = 'playing';
export const STATE_WON = 'won';   // du point de vue du joueur 0 (humain)
export const STATE_LOST = 'lost';

export const RULES = Object.freeze({
  TOWER_HP: 20,
  TOWER_ATK: 2,          // la tour tire sur un ennemi adjacent au début du tour de son camp
  MAX_MANA: 10,
  HAND_MAX: 7,
  START_HAND: 3,         // + 1 carte pour le second joueur
  DEPLOY_RADIUS: 2,      // zone de déploiement : distance ≤ 2 de sa tour
  HERO_DEPLOY_RADIUS: 1, // ... ou distance ≤ 1 d'un héros allié
  BRASIER_DMG: 2,        // brûlure de fin de tour
  FORET_ARMOR: 1,
  MAX_EQUIPS: 2,
  UNEQUIP_COST: 1,
  LOG_MAX: 40,
});

export const PLAYER_ONE = 0;
export const PLAYER_TWO = 1;

/** Générateur pseudo-aléatoire déterministe (mulberry32) — la seule source d'aléa. */
export function makeRng(seed) {
  let a = (seed >>> 0) || 1;
  return function next() {
    a = (a + 0x6D2B79F5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

export function manhattan(a, b) {
  return Math.abs(a.x - b.x) + Math.abs(a.y - b.y);
}

export function inBounds(x, y) {
  return x >= 0 && x < COLS && y >= 0 && y < ROWS;
}

const DIRS = Object.freeze([[1, 0], [-1, 0], [0, 1], [0, -1]]);

export function neighbors4(x, y) {
  const out = [];
  for (const [dx, dy] of DIRS) {
    const nx = x + dx;
    const ny = y + dy;
    if (inBounds(nx, ny)) out.push({ x: nx, y: ny });
  }
  return out;
}

export const key = (x, y) => `${x},${y}`;

/** Empreinte FNV-1a d'une chaîne, pour comparer deux états sans les sérialiser côté test. */
export function fnv1a(str) {
  let h = 0x811c9dc5;
  for (let i = 0; i < str.length; i++) {
    h ^= str.charCodeAt(i);
    h = Math.imul(h, 0x01000193) >>> 0;
  }
  return h.toString(16).padStart(8, '0');
}

function shuffled(list, rng) {
  const out = list.slice();
  for (let i = out.length - 1; i > 0; i--) {
    const j = Math.floor(rng() * (i + 1));
    [out[i], out[j]] = [out[j], out[i]];
  }
  return out;
}

class RuleError extends Error {}

export class Engine {
  constructor({ seed = 1, deckList = DECK_LIST } = {}) {
    this.seed = seed;
    this.deckList = deckList;
    this.init();
  }

  // --- cycle de vie --------------------------------------------------------------------

  init() {
    this.rng = makeRng(this.seed);
    this.mapIndex = this.seed % MAP_TEMPLATES.length;
    this.mapName = templateName(this.mapIndex);
    this.board = buildBoard(this.mapIndex);
    this.towers = [
      { owner: PLAYER_ONE, x: TOWER_COL, y: ROWS - 1, hp: RULES.TOWER_HP },
      { owner: PLAYER_TWO, x: TOWER_COL, y: 0, hp: RULES.TOWER_HP },
    ];
    this.players = [PLAYER_ONE, PLAYER_TWO].map(() => ({
      mana: 0, manaMax: 0, deck: shuffled(this.deckList, this.rng), hand: [], fatigue: 0,
    }));
    this.units = new Map();
    this.nextUnitId = 1;
    this.ply = 1;
    this.round = 1;
    this.current = PLAYER_ONE;
    this.state = STATE_PLAYING;
    this.winner = null;
    this.log = [];
    for (let i = 0; i < RULES.START_HAND; i++) this.draw(PLAYER_ONE, true);
    for (let i = 0; i < RULES.START_HAND + 1; i++) this.draw(PLAYER_TWO, true);
    this.beginTurn(PLAYER_ONE);
  }

  get over() {
    return this.state !== STATE_PLAYING;
  }

  say(text) {
    this.log.push(`T${this.round}·J${this.current + 1} ${text}`);
    if (this.log.length > RULES.LOG_MAX) this.log.shift();
  }

  // --- accès -----------------------------------------------------------------------------

  cell(x, y) {
    return this.board[y][x];
  }

  towerOf(owner) {
    return this.towers[owner];
  }

  isTowerCell(x, y) {
    return this.towers.some((t) => t.x === x && t.y === y);
  }

  unitAt(x, y) {
    for (const u of this.units.values()) if (u.x === x && u.y === y) return u;
    return null;
  }

  unitsOf(owner) {
    return [...this.units.values()].filter((u) => u.owner === owner);
  }

  unit(id) {
    return this.units.get(id) ?? null;
  }

  // --- statistiques effectives (équipements + auras + terrain) ---------------------------

  keywordsOf(unit) {
    const set = new Set(cardById(unit.cardId).keywords);
    for (const eq of unit.equips) for (const kw of cardById(eq).mods.keywords) set.add(kw);
    return set;
  }

  has(unit, kw) {
    return this.keywordsOf(unit).has(kw);
  }

  /** Héros alliés à `unit` (ou à une case) dont l'aura `kind` couvre la position. */
  auraSources(owner, pos, kind, excludeId = null) {
    return this.unitsOf(owner).filter((h) => {
      const card = cardById(h.cardId);
      return card.aura && card.aura.kind === kind && h.id !== excludeId
        && manhattan(h, pos) <= card.aura.radius;
    });
  }

  atkOf(unit) {
    let atk = unit.atk;
    for (const eq of unit.equips) atk += cardById(eq).mods.atk;
    for (const h of this.auraSources(unit.owner, unit, AURA.ATK, unit.id)) atk += cardById(h.cardId).aura.value;
    return atk;
  }

  rngOf(unit) {
    let rng = unit.rng;
    for (const eq of unit.equips) rng += cardById(eq).mods.rng;
    return rng;
  }

  movOf(unit) {
    let mov = unit.mov;
    for (const eq of unit.equips) mov += cardById(eq).mods.mov;
    return mov;
  }

  armorOf(unit) {
    let armor = 0;
    if (this.cell(unit.x, unit.y).terrain === TERRAIN.FORET) armor += RULES.FORET_ARMOR;
    for (const h of this.auraSources(unit.owner, unit, AURA.ARMOR, unit.id)) armor += cardById(h.cardId).aura.value;
    return armor;
  }

  /** Une unité invoquée ce tour ne peut pas agir (sauf Célérité) ; gelée non plus. */
  isSummonSick(unit) {
    return unit.summonedPly === this.ply && !this.has(unit, KW.CELERITE);
  }

  isFrozen(unit) {
    return this.ply < unit.frozenUntil;
  }

  canAct(unit) {
    return !this.over && unit.owner === this.current && !this.isSummonSick(unit) && !this.isFrozen(unit);
  }

  // --- coût des cartes -------------------------------------------------------------------

  /** Coût réel : l'Archimage réduit les sorts qui visent une case de son aura. */
  costOf(card, owner, targetCell = null) {
    if (card.type !== TYPE.SPELL || !targetCell) return card.cost;
    const discount = this.auraSources(owner, targetCell, AURA.SPELL_DISCOUNT)
      .reduce((sum, h) => sum + cardById(h.cardId).aura.value, 0);
    return Math.max(0, card.cost - discount);
  }

  // --- déploiement -------------------------------------------------------------------------

  isLandable(x, y) {
    return inBounds(x, y) && !this.isTowerCell(x, y)
      && this.cell(x, y).terrain !== TERRAIN.ROCHER && this.unitAt(x, y) === null;
  }

  deployCells(owner) {
    const tower = this.towerOf(owner);
    const heroes = this.unitsOf(owner).filter((u) => cardById(u.cardId).type === TYPE.HERO);
    const out = [];
    for (let y = 0; y < ROWS; y++) {
      for (let x = 0; x < COLS; x++) {
        if (!this.isLandable(x, y)) continue;
        const pos = { x, y };
        const nearTower = manhattan(pos, tower) <= RULES.DEPLOY_RADIUS;
        const nearHero = heroes.some((h) => manhattan(pos, h) <= RULES.HERO_DEPLOY_RADIUS);
        if (nearTower || nearHero) out.push(pos);
      }
    }
    return out;
  }

  // --- déplacement (BFS, zone de contrôle, marais, vol) -------------------------------------

  adjacentToEnemy(x, y, owner) {
    return neighbors4(x, y).some((n) => {
      const u = this.unitAt(n.x, n.y);
      return u !== null && u.owner !== owner;
    });
  }

  /**
   * Cases atteignables par `unit` avec son déplacement restant.
   * @returns {Map<string, {x:number,y:number,cost:number}>}
   */
  reachable(unit) {
    const result = new Map();
    if (!this.canAct(unit) || unit.attacked || unit.movLeft <= 0) return result;
    const flying = this.has(unit, KW.VOL);
    const ignoreZoc = flying || this.has(unit, KW.PIETINEMENT);
    const seen = new Set([key(unit.x, unit.y)]);
    let frontier = [{ x: unit.x, y: unit.y, cost: 0 }];
    while (frontier.length > 0) {
      const next = [];
      for (const cur of frontier) {
        for (const n of neighbors4(cur.x, cur.y)) {
          const k = key(n.x, n.y);
          if (seen.has(k) || this.isTowerCell(n.x, n.y)) continue;
          const terrain = this.cell(n.x, n.y).terrain;
          const occupant = this.unitAt(n.x, n.y);
          if (terrain === TERRAIN.ROCHER && !flying) continue;
          if (occupant !== null && !flying) continue;
          const cost = cur.cost + 1;
          if (cost > unit.movLeft) continue;
          seen.add(k);
          const landable = occupant === null && terrain !== TERRAIN.ROCHER;
          if (landable) result.set(k, { x: n.x, y: n.y, cost });
          const stops = (!ignoreZoc && this.adjacentToEnemy(n.x, n.y, unit.owner))
            || (!flying && terrain === TERRAIN.MARAIS);
          if (!stops) next.push({ x: n.x, y: n.y, cost });
        }
      }
      frontier = next;
    }
    return result;
  }

  // --- attaque ---------------------------------------------------------------------------------

  /** Cibles légales : unités ennemies à portée (Provocation prime), puis la tour ennemie. */
  attackTargets(unit) {
    if (!this.canAct(unit) || unit.attacked) return [];
    const range = this.rngOf(unit);
    const enemies = this.unitsOf(1 - unit.owner).filter((e) => manhattan(unit, e) <= range);
    const taunts = enemies.filter((e) => this.has(e, KW.PROVOCATION));
    if (taunts.length > 0) return taunts.map((e) => ({ unit: e.id }));
    const out = enemies.map((e) => ({ unit: e.id }));
    if (manhattan(unit, this.towerOf(1 - unit.owner)) <= range) out.push({ tower: true });
    return out;
  }

  /** Dégâts à une unité : bouclier, puis armure (forêt, Paladin) avec plancher 1 (brique KB). */
  damageUnit(target, raw, sourceLabel) {
    if (target.shield) {
      target.shield = false;
      this.say(`${target.name} : le bouclier absorbe ${sourceLabel}.`);
      return 0;
    }
    const { hp, dealt } = applyHit(target.hp, raw, this.armorOf(target));
    target.hp = hp;
    this.say(`${target.name} subit ${dealt} (${sourceLabel}) → ${target.hp} PV.`);
    if (target.hp <= 0) this.killUnit(target, sourceLabel);
    return dealt;
  }

  damageTower(owner, raw, sourceLabel) {
    const tower = this.towerOf(owner);
    tower.hp = Math.max(0, tower.hp - raw);
    this.say(`Tour J${owner + 1} subit ${raw} (${sourceLabel}) → ${tower.hp} PV.`);
    this.checkWin();
    return raw;
  }

  killUnit(unit, cause) {
    this.units.delete(unit.id);
    this.say(`${unit.name} meurt (${cause}).`);
    const hand = this.players[unit.owner].hand;
    for (const eq of unit.equips) {
      if (hand.length < RULES.HAND_MAX) {
        hand.push(eq);
        this.say(`${cardById(eq).name} revient dans la main de J${unit.owner + 1}.`);
      } else {
        this.say(`${cardById(eq).name} est perdu (main pleine).`);
      }
    }
    const card = cardById(unit.cardId);
    if (!card.token && this.auraSources(unit.owner, unit, AURA.NECRO, unit.id).length > 0) {
      const ombre = this.spawn('ombre', unit.owner, unit.x, unit.y);
      this.say(`Une ${ombre.name} se lève là où ${unit.name} est tombé.`);
    }
  }

  checkWin() {
    if (this.over) return;
    for (const tower of this.towers) {
      if (tower.hp <= 0) {
        this.winner = 1 - tower.owner;
        this.state = this.winner === PLAYER_ONE ? STATE_WON : STATE_LOST;
        this.say(`La tour de J${tower.owner + 1} s'effondre. J${this.winner + 1} l'emporte.`);
        return;
      }
    }
  }

  // --- pioche ----------------------------------------------------------------------------------

  draw(owner, silent = false) {
    const p = this.players[owner];
    if (p.deck.length === 0) {
      p.fatigue += 1;
      if (!silent) this.say(`J${owner + 1} n'a plus de cartes : fatigue ${p.fatigue}.`);
      this.damageTower(owner, p.fatigue, 'fatigue');
      return null;
    }
    const cardId = p.deck.pop();
    if (p.hand.length >= RULES.HAND_MAX) {
      if (!silent) this.say(`Main pleine : ${cardById(cardId).name} est brûlée.`);
      return null;
    }
    p.hand.push(cardId);
    return cardId;
  }

  // --- invocation ------------------------------------------------------------------------------

  /** `escort` : unité amenée par une autre (Recruteur, Meute) — un jeton, pas une carte du deck. */
  spawn(cardId, owner, x, y, escort = false) {
    const card = cardById(cardId);
    const unit = {
      id: this.nextUnitId++,
      owner,
      cardId,
      name: card.name,
      token: Boolean(card.token) || escort,
      atk: card.atk,
      hp: card.hp,
      hpMax: card.hp,
      mov: card.mov,
      rng: card.rng,
      x,
      y,
      movLeft: card.mov,
      attacked: false,
      summonedPly: this.ply,
      frozenUntil: 0,
      shield: false,
      equips: [],
      abilityUsed: false,
    };
    this.units.set(unit.id, unit);
    return unit;
  }

  summonEscort(unit, summon) {
    let placed = 0;
    for (const n of neighbors4(unit.x, unit.y)) {
      if (placed >= summon.count) break;
      if (!this.isLandable(n.x, n.y)) continue;
      this.spawn(summon.card, unit.owner, n.x, n.y, true);
      placed += 1;
    }
    this.say(`${unit.name} amène ${placed} ${cardById(summon.card).name}(s).`);
  }

  // --- validation des cibles ---------------------------------------------------------------------

  targetUnitFor(kind, owner, id) {
    const u = this.unit(id);
    if (!u) throw new RuleError('unité cible introuvable');
    if (kind === TARGET.ALLY && u.owner !== owner) throw new RuleError('cible : allié attendu');
    if (kind === TARGET.ENEMY && u.owner === owner) throw new RuleError('cible : ennemi attendu');
    return u;
  }

  requireCell(x, y) {
    if (!inBounds(x, y)) throw new RuleError('case hors plateau');
    return { x, y };
  }

  /** Cases de destination d'un portail pour une unité. */
  portalCells(unit, range) {
    const out = [];
    for (let y = 0; y < ROWS; y++) {
      for (let x = 0; x < COLS; x++) {
        if (manhattan(unit, { x, y }) <= range && this.isLandable(x, y)) out.push({ x, y });
      }
    }
    return out;
  }

  wallCells() {
    const out = [];
    for (let y = 0; y < ROWS; y++) {
      for (let x = 0; x < COLS; x++) {
        const t = this.cell(x, y).terrain;
        if (this.isLandable(x, y) && t !== TERRAIN.FONTAINE && t !== TERRAIN.BRASIER) out.push({ x, y });
      }
    }
    return out;
  }

  // --- actions ------------------------------------------------------------------------------------

  /**
   * Applique une action. Renvoie { ok:true } ou { ok:false, error }. Ne lève jamais.
   * Actions : play(hand, x, y | unit | unit,toX,toY) · move(unit, x, y) · attack(unit, target)
   *           · ability(unit, x, y | target) · unequip(unit, index) · end
   */
  apply(action) {
    try {
      if (this.over) throw new RuleError('la partie est terminée');
      switch (action.type) {
        case 'play': this.doPlay(action); break;
        case 'move': this.doMove(action); break;
        case 'attack': this.doAttack(action); break;
        case 'ability': this.doAbility(action); break;
        case 'unequip': this.doUnequip(action); break;
        case 'end': this.endTurn(); break;
        default: throw new RuleError(`action inconnue : ${action.type}`);
      }
      return { ok: true };
    } catch (err) {
      if (err instanceof RuleError) return { ok: false, error: err.message };
      throw err;
    }
  }

  doPlay(action) {
    const owner = this.current;
    const p = this.players[owner];
    if (!Number.isInteger(action.hand) || action.hand < 0 || action.hand >= p.hand.length) {
      throw new RuleError('carte introuvable en main');
    }
    const card = cardById(p.hand[action.hand]);
    let targetCell = null;
    let resolve;
    if (isUnitCard(card)) {
      const cell = this.requireCell(action.x, action.y);
      if (!this.deployCells(owner).some((c) => c.x === cell.x && c.y === cell.y)) {
        throw new RuleError('case hors de la zone de déploiement');
      }
      targetCell = cell;
      resolve = () => {
        const unit = this.spawn(card.id, owner, cell.x, cell.y);
        this.say(`${card.name} entre en jeu en (${cell.x},${cell.y}).`);
        if (card.summon) this.summonEscort(unit, card.summon);
      };
    } else if (card.type === TYPE.EQUIP) {
      const u = this.targetUnitFor(TARGET.ALLY, owner, action.unit);
      if (u.equips.length >= RULES.MAX_EQUIPS) throw new RuleError('cette unité porte déjà 2 équipements');
      targetCell = { x: u.x, y: u.y };
      resolve = () => {
        u.equips.push(card.id);
        u.hpMax += card.mods.hp;
        u.hp += card.mods.hp;
        u.movLeft += card.mods.mov;
        this.say(`${u.name} s'équipe : ${card.name}.`);
      };
    } else {
      ({ targetCell, resolve } = this.prepareSpell(card, owner, action));
    }
    const cost = this.costOf(card, owner, targetCell);
    if (p.mana < cost) throw new RuleError(`mana insuffisant (${p.mana}/${cost})`);
    p.mana -= cost;
    p.hand.splice(action.hand, 1);
    resolve();
    this.checkWin();
  }

  prepareSpell(card, owner, action) {
    switch (card.id) {
      case 'boule_de_feu': {
        const c = this.requireCell(action.x, action.y);
        return { targetCell: c, resolve: () => this.castFireball(card, c) };
      }
      case 'eclair': {
        const u = this.targetUnitFor(TARGET.ENEMY, owner, action.unit);
        return { targetCell: { x: u.x, y: u.y }, resolve: () => {
          this.say(`Éclair sur ${u.name}.`);
          this.damageUnit(u, card.damage, 'Éclair');
        } };
      }
      case 'portail': {
        const u = this.targetUnitFor(TARGET.ALLY, owner, action.unit);
        const dest = this.requireCell(action.toX, action.toY);
        if (!this.portalCells(u, card.range).some((c) => c.x === dest.x && c.y === dest.y)) {
          throw new RuleError('destination du portail invalide');
        }
        return { targetCell: dest, resolve: () => {
          this.say(`${u.name} traverse un portail vers (${dest.x},${dest.y}).`);
          u.x = dest.x;
          u.y = dest.y;
        } };
      }
      case 'bouclier_temporel': {
        const u = this.targetUnitFor(TARGET.ALLY, owner, action.unit);
        return { targetCell: { x: u.x, y: u.y }, resolve: () => {
          u.shield = true;
          this.say(`${u.name} gagne un Bouclier Temporel.`);
        } };
      }
      case 'mur_de_pierre': {
        const c = this.requireCell(action.x, action.y);
        if (!this.wallCells().some((w) => w.x === c.x && w.y === c.y)) throw new RuleError('case de mur invalide');
        return { targetCell: c, resolve: () => {
          const cell = this.cell(c.x, c.y);
          cell.terrain = TERRAIN.ROCHER;
          cell.ttl = card.rocherTtl;
          this.say(`Un Mur de Pierre se dresse en (${c.x},${c.y}).`);
        } };
      }
      case 'soin': {
        const u = this.targetUnitFor(TARGET.UNIT, owner, action.unit);
        return { targetCell: { x: u.x, y: u.y }, resolve: () => {
          const before = u.hp;
          u.hp = Math.min(u.hpMax, u.hp + card.heal);
          this.say(`${u.name} est soigné de ${u.hp - before} PV.`);
        } };
      }
      case 'gel': {
        const u = this.targetUnitFor(TARGET.ENEMY, owner, action.unit);
        return { targetCell: { x: u.x, y: u.y }, resolve: () => {
          u.frozenUntil = this.ply + 2;
          this.say(`${u.name} est gelé jusqu'à la fin de son prochain tour.`);
        } };
      }
      default:
        throw new RuleError(`sort non implémenté : ${card.id}`);
    }
  }

  castFireball(card, center) {
    this.say(`Boule de Feu en (${center.x},${center.y}) !`);
    const victims = [...this.units.values()].filter(
      (u) => Math.abs(u.x - center.x) <= card.radius && Math.abs(u.y - center.y) <= card.radius);
    for (const v of victims) this.damageUnit(v, card.damage, 'Boule de Feu');
    for (const tower of this.towers) {
      if (Math.abs(tower.x - center.x) <= card.radius && Math.abs(tower.y - center.y) <= card.radius) {
        this.damageTower(tower.owner, card.damage, 'Boule de Feu');
      }
    }
    const cell = this.cell(center.x, center.y);
    const burnable = cell.terrain === TERRAIN.PLAINE || cell.terrain === TERRAIN.FORET
      || cell.terrain === TERRAIN.MARAIS;
    if (burnable && !this.isTowerCell(center.x, center.y)) {
      cell.terrain = TERRAIN.BRASIER;
      cell.ttl = card.brasierTtl;
    }
  }

  doMove(action) {
    const u = this.targetUnitFor(TARGET.ALLY, this.current, action.unit);
    const dest = this.requireCell(action.x, action.y);
    const cells = this.reachable(u);
    const entry = cells.get(key(dest.x, dest.y));
    if (!entry) throw new RuleError('case inaccessible');
    u.x = dest.x;
    u.y = dest.y;
    u.movLeft -= entry.cost;
    this.say(`${u.name} se déplace en (${dest.x},${dest.y}).`);
  }

  doAttack(action) {
    const u = this.targetUnitFor(TARGET.ALLY, this.current, action.unit);
    const targets = this.attackTargets(u);
    const t = action.target ?? {};
    const legal = targets.some((c) => (t.tower ? c.tower === true : c.unit === t.unit));
    if (!legal) throw new RuleError('cible d\'attaque illégale');
    u.attacked = true;
    u.movLeft = 0;
    const atk = this.atkOf(u);
    if (t.tower) {
      this.say(`${u.name} frappe la tour ennemie.`);
      this.damageTower(1 - u.owner, atk, u.name);
      return;
    }
    const target = this.unit(t.unit);
    this.say(`${u.name} attaque ${target.name}.`);
    this.damageUnit(target, atk, u.name);
    const alive = this.units.has(target.id);
    if (alive && !this.isFrozen(target) && manhattan(u, target) <= this.rngOf(target)) {
      this.say(`${target.name} riposte.`);
      this.damageUnit(u, this.atkOf(target), `riposte de ${target.name}`);
    }
  }

  abilityTargets(hero) {
    const card = cardById(hero.cardId);
    const ab = card.ability;
    if (!ab || hero.abilityUsed || this.isFrozen(hero) || hero.owner !== this.current || this.over) return [];
    if (this.players[hero.owner].mana < ab.cost) return [];
    if (ab.kind === ABILITY.RALLY) return [{ self: true }];
    const pool = ab.target === TARGET.ENEMY ? this.unitsOf(1 - hero.owner) : this.unitsOf(hero.owner);
    return pool.filter((u) => manhattan(hero, u) <= ab.range).map((u) => ({ unit: u.id }));
  }

  doAbility(action) {
    const hero = this.targetUnitFor(TARGET.ALLY, this.current, action.unit);
    const card = cardById(hero.cardId);
    const ab = card.ability;
    if (!ab) throw new RuleError('cette unité n\'a pas de capacité');
    const targets = this.abilityTargets(hero);
    if (targets.length === 0) throw new RuleError('capacité indisponible');
    const t = action.target ?? {};
    if (ab.kind !== ABILITY.RALLY && !targets.some((c) => c.unit === t.unit)) throw new RuleError('cible de capacité illégale');
    this.players[hero.owner].mana -= ab.cost;
    hero.abilityUsed = true;
    this.say(`${hero.name} utilise ${ab.name}.`);
    switch (ab.kind) {
      case ABILITY.RALLY:
        for (const u of this.unitsOf(hero.owner)) {
          if (u.id !== hero.id && manhattan(u, hero) <= ab.radius) u.movLeft += 1;
        }
        break;
      case ABILITY.SPARK:
        this.damageUnit(this.unit(t.unit), 1, ab.name);
        break;
      case ABILITY.DRAIN:
        this.damageUnit(this.unit(t.unit), 2, ab.name);
        hero.hp = Math.min(hero.hpMax, hero.hp + 2);
        break;
      case ABILITY.BLESS:
        this.unit(t.unit).shield = true;
        break;
      default:
        throw new RuleError(`capacité inconnue : ${ab.kind}`);
    }
    this.checkWin();
  }

  doUnequip(action) {
    const u = this.targetUnitFor(TARGET.ALLY, this.current, action.unit);
    const p = this.players[u.owner];
    if (!Number.isInteger(action.index) || action.index < 0 || action.index >= u.equips.length) {
      throw new RuleError('équipement introuvable');
    }
    if (p.mana < RULES.UNEQUIP_COST) throw new RuleError('mana insuffisant');
    if (p.hand.length >= RULES.HAND_MAX) throw new RuleError('main pleine');
    const [eq] = u.equips.splice(action.index, 1);
    const card = cardById(eq);
    u.hpMax -= card.mods.hp;
    u.hp = Math.min(u.hp, u.hpMax);
    u.movLeft = Math.max(0, u.movLeft - card.mods.mov);
    p.mana -= RULES.UNEQUIP_COST;
    p.hand.push(eq);
    this.say(`${u.name} rend ${card.name} à la main.`);
  }

  // --- tours ----------------------------------------------------------------------------------------

  endTurn() {
    const owner = this.current;
    // brûlure du brasier, soin des prêtresses : fin du tour du propriétaire
    for (const u of this.unitsOf(owner)) {
      if (this.cell(u.x, u.y).terrain === TERRAIN.BRASIER && !this.has(u, KW.VOL)) {
        this.damageUnit(u, RULES.BRASIER_DMG, 'Brasier');
      }
    }
    for (const u of this.unitsOf(owner)) {
      const card = cardById(u.cardId);
      if (!card.heal) continue;
      for (const n of neighbors4(u.x, u.y)) {
        const ally = this.unitAt(n.x, n.y);
        if (ally && ally.owner === owner && ally.hp < ally.hpMax) {
          ally.hp = Math.min(ally.hpMax, ally.hp + card.heal);
        }
      }
    }
    // terrains temporaires
    for (const row of this.board) {
      for (const cell of row) {
        if (cell.ttl > 0) {
          cell.ttl -= 1;
          if (cell.ttl === 0) cell.terrain = cell.base;
        }
      }
    }
    if (this.over) return;
    this.ply += 1;
    this.current = 1 - owner;
    if (this.current === PLAYER_ONE) this.round += 1;
    this.beginTurn(this.current);
  }

  beginTurn(owner) {
    const p = this.players[owner];
    p.manaMax = Math.min(RULES.MAX_MANA, p.manaMax + 1);
    const fountains = this.unitsOf(owner)
      .filter((u) => this.cell(u.x, u.y).terrain === TERRAIN.FONTAINE).length;
    p.mana = Math.min(RULES.MAX_MANA, p.manaMax + fountains);
    for (const u of this.unitsOf(owner)) {
      u.movLeft = this.movOf(u);
      u.attacked = false;
      u.abilityUsed = false;
    }
    this.say(`début du tour : ${p.mana} mana${fountains ? ` (+${fountains} fontaine)` : ''}.`);
    this.towerShoots(owner);
    if (this.over) return;
    this.draw(owner);
  }

  /** La tour tire sur l'ennemi adjacent le plus menaçant (ATQ la plus haute, puis id). */
  towerShoots(owner) {
    const tower = this.towerOf(owner);
    const adjacent = this.unitsOf(1 - owner).filter((u) => manhattan(u, tower) === 1);
    if (adjacent.length === 0) return;
    adjacent.sort((a, b) => this.atkOf(b) - this.atkOf(a) || a.id - b.id);
    this.say(`La tour J${owner + 1} tire sur ${adjacent[0].name}.`);
    this.damageUnit(adjacent[0], RULES.TOWER_ATK, 'tir de tour');
  }

  // --- énumération des actions légales (bots, tests de propriétés) -------------------------------

  legalActions() {
    if (this.over) return [];
    const owner = this.current;
    const p = this.players[owner];
    const actions = [];
    p.hand.forEach((cardId, hand) => {
      const card = cardById(cardId);
      if (isUnitCard(card)) {
        if (p.mana < card.cost) return;
        for (const c of this.deployCells(owner)) actions.push({ type: 'play', hand, x: c.x, y: c.y });
        return;
      }
      if (card.type === TYPE.EQUIP) {
        if (p.mana < card.cost) return;
        for (const u of this.unitsOf(owner)) {
          if (u.equips.length < RULES.MAX_EQUIPS) actions.push({ type: 'play', hand, unit: u.id });
        }
        return;
      }
      for (const a of this.spellActions(card, owner, hand)) {
        if (p.mana >= this.costOf(card, owner, a.cell)) {
          const { cell, ...rest } = a;
          actions.push(rest);
        }
      }
    });
    for (const u of this.unitsOf(owner)) {
      for (const c of this.reachable(u).values()) actions.push({ type: 'move', unit: u.id, x: c.x, y: c.y });
      for (const t of this.attackTargets(u)) actions.push({ type: 'attack', unit: u.id, target: t });
      for (const t of this.abilityTargets(u)) actions.push({ type: 'ability', unit: u.id, target: t });
      if (p.mana >= RULES.UNEQUIP_COST && p.hand.length < RULES.HAND_MAX) {
        u.equips.forEach((_, index) => actions.push({ type: 'unequip', unit: u.id, index }));
      }
    }
    actions.push({ type: 'end' });
    return actions;
  }

  /** Actions candidates d'un sort, chacune avec sa case cible (pour le coût). */
  spellActions(card, owner, hand) {
    const out = [];
    const allCells = () => {
      const cells = [];
      for (let y = 0; y < ROWS; y++) for (let x = 0; x < COLS; x++) cells.push({ x, y });
      return cells;
    };
    const unitsFor = (kind) => {
      if (kind === TARGET.ALLY) return this.unitsOf(owner);
      if (kind === TARGET.ENEMY) return this.unitsOf(1 - owner);
      return [...this.units.values()];
    };
    switch (card.target) {
      case TARGET.CELL:
        for (const c of allCells()) out.push({ type: 'play', hand, x: c.x, y: c.y, cell: c });
        break;
      case TARGET.EMPTY_CELL:
        for (const c of this.wallCells()) out.push({ type: 'play', hand, x: c.x, y: c.y, cell: c });
        break;
      case TARGET.ALLY_THEN_CELL:
        for (const u of this.unitsOf(owner)) {
          for (const c of this.portalCells(u, card.range)) {
            out.push({ type: 'play', hand, unit: u.id, toX: c.x, toY: c.y, cell: c });
          }
        }
        break;
      default:
        for (const u of unitsFor(card.target)) out.push({ type: 'play', hand, unit: u.id, cell: { x: u.x, y: u.y } });
    }
    return out;
  }

  // --- état inspectable --------------------------------------------------------------------------

  snapshot() {
    return {
      seed: this.seed,
      map: this.mapName,
      ply: this.ply,
      round: this.round,
      current: this.current,
      state: this.state,
      winner: this.winner,
      towers: this.towers.map((t) => ({ ...t })),
      players: this.players.map((p) => ({
        mana: p.mana, manaMax: p.manaMax, deck: p.deck.length, hand: p.hand.slice(), fatigue: p.fatigue,
      })),
      board: this.board.map((row) => row.map((c) => (c.ttl > 0 ? `${c.terrain}:${c.ttl}` : c.terrain))),
      units: [...this.units.values()].map((u) => ({
        ...u, equips: u.equips.slice(), atkEff: this.atkOf(u), rngEff: this.rngOf(u), movEff: this.movOf(u),
      })),
    };
  }

  hashState() {
    return fnv1a(JSON.stringify(this.snapshot()));
  }
}

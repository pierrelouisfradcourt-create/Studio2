// Bot adverse — politique gloutonne DÉTERMINISTE, une action à la fois (main.mjs l'anime).
// Il ne connaît que l'API publique du moteur (reachable, attackTargets, legalActions...).
// Chaque action choisie consomme une ressource (mana, déplacement, attaque, capacité), ce qui
// garantit que `chooseAction` finit toujours par rendre { type: 'end' }.

import { manhattan, TERRAIN, TYPE, KW, ABILITY, RULES } from './engine.mjs';
import { cardById, isUnitCard } from './cards.mjs';

const VALUE = Object.freeze({
  KILL_BONUS: 3,
  HERO_BONUS: 3,
  TOWER_HP: 1,      // valeur d'un PV de tour ennemie
  FIREBALL_MIN: 5,  // valeur nette minimale pour lancer une Boule de Feu
  MOVE_TOWER_WEIGHT: 2,
});

function byId(a, b) {
  return a.id - b.id;
}

/** Valeur d'une unité ennemie touchée : PV retirés + prime de mort + prime de héros. */
function hitValue(engine, target, raw) {
  const dealt = Math.min(target.hp, Math.max(1, raw - engine.armorOf(target)));
  const kills = dealt >= target.hp;
  let v = dealt + (kills ? VALUE.KILL_BONUS + engine.atkOf(target) : 0);
  if (cardById(target.cardId).type === TYPE.HERO) v += VALUE.HERO_BONUS;
  return v;
}

function bestOf(list, score) {
  let best = null;
  let bestScore = -Infinity;
  for (const item of list) {
    const s = score(item);
    if (s > bestScore) {
      bestScore = s;
      best = item;
    }
  }
  return { best, score: bestScore };
}

// --- attaques --------------------------------------------------------------------------

function pickAttack(engine, me, killsOnly) {
  const enemyTower = engine.towerOf(1 - me);
  for (const u of engine.unitsOf(me).sort(byId)) {
    const targets = engine.attackTargets(u);
    if (targets.length === 0) continue;
    const atk = engine.atkOf(u);
    if (targets.some((t) => t.tower)) return { type: 'attack', unit: u.id, target: { tower: true } };
    const scored = targets.filter((t) => t.unit).map((t) => {
      const target = engine.unit(t.unit);
      const dealt = Math.max(1, atk - engine.armorOf(target));
      const kills = !target.shield && dealt >= target.hp;
      const retaliation = kills || engine.isFrozen(target) || manhattan(u, target) > engine.rngOf(target)
        ? 0 : Math.max(1, engine.atkOf(target) - engine.armorOf(u));
      const survives = retaliation < u.hp;
      return { t, kills, survives, value: hitValue(engine, target, atk) - retaliation };
    });
    const pool = killsOnly ? scored.filter((s) => s.kills) : scored.filter((s) => s.survives || s.kills);
    const { best } = bestOf(pool, (s) => s.value);
    if (best && (killsOnly || best.value > 0 || manhattan(u, enemyTower) <= 2)) {
      return { type: 'attack', unit: u.id, target: best.t };
    }
  }
  return null;
}

// --- cartes ----------------------------------------------------------------------------------

function pickUnitCard(engine, me) {
  const p = engine.players[me];
  const enemyTower = engine.towerOf(1 - me);
  const cells = engine.deployCells(me);
  if (cells.length === 0) return null;
  let bestHand = -1;
  let bestCost = -1;
  p.hand.forEach((id, i) => {
    const card = cardById(id);
    if (isUnitCard(card) && card.cost <= p.mana && card.cost > bestCost) {
      bestCost = card.cost;
      bestHand = i;
    }
  });
  if (bestHand < 0) return null;
  const { best } = bestOf(cells, (c) => -manhattan(c, enemyTower)
    + (engine.cell(c.x, c.y).terrain === TERRAIN.FONTAINE ? 2 : 0)
    - (engine.cell(c.x, c.y).terrain === TERRAIN.BRASIER ? 5 : 0));
  return { type: 'play', hand: bestHand, x: best.x, y: best.y };
}

function pickEquip(engine, me) {
  const p = engine.players[me];
  const carriers = engine.unitsOf(me).filter((u) => u.equips.length < RULES.MAX_EQUIPS);
  if (carriers.length === 0) return null;
  for (let i = 0; i < p.hand.length; i++) {
    const card = cardById(p.hand[i]);
    if (card.type !== TYPE.EQUIP || card.cost > p.mana) continue;
    const { best } = bestOf(carriers, (u) => u.hp * 2 + engine.atkOf(u) - (engine.isSummonSick(u) ? 3 : 0));
    return { type: 'play', hand: i, unit: best.id };
  }
  return null;
}

function fireballPlan(engine, me, hand, card) {
  const enemyTower = engine.towerOf(1 - me);
  let plan = null;
  let planValue = 0;
  for (let y = 0; y < engine.board.length; y++) {
    for (let x = 0; x < engine.board[0].length; x++) {
      const cost = engine.costOf(card, me, { x, y });
      if (cost > engine.players[me].mana) continue;
      let value = 0;
      for (const u of engine.units.values()) {
        if (Math.abs(u.x - x) > card.radius || Math.abs(u.y - y) > card.radius) continue;
        const v = hitValue(engine, u, card.damage);
        value += u.owner === me ? -v - 1 : v;
      }
      if (Math.abs(enemyTower.x - x) <= card.radius && Math.abs(enemyTower.y - y) <= card.radius) {
        value += card.damage * VALUE.TOWER_HP + (enemyTower.hp <= card.damage ? 100 : 0);
      }
      const myTower = engine.towerOf(me);
      if (Math.abs(myTower.x - x) <= card.radius && Math.abs(myTower.y - y) <= card.radius) value -= 6;
      if (value > planValue) {
        planValue = value;
        plan = { type: 'play', hand, x, y };
      }
    }
  }
  return planValue >= VALUE.FIREBALL_MIN ? plan : null;
}

function pickSpell(engine, me) {
  const p = engine.players[me];
  const myTower = engine.towerOf(me);
  const enemyTower = engine.towerOf(1 - me);
  const enemies = engine.unitsOf(1 - me);
  const allies = engine.unitsOf(me);
  const affordable = (card, cell) => engine.costOf(card, me, cell) <= p.mana;
  for (let hand = 0; hand < p.hand.length; hand++) {
    const card = cardById(p.hand[hand]);
    if (card.type !== TYPE.SPELL) continue;
    switch (card.id) {
      case 'boule_de_feu': {
        const plan = fireballPlan(engine, me, hand, card);
        if (plan) return plan;
        break;
      }
      case 'eclair': {
        const pool = enemies.filter((e) => affordable(card, e)
          && (e.hp <= card.damage || cardById(e.cardId).type === TYPE.HERO));
        const { best } = bestOf(pool, (e) => hitValue(engine, e, card.damage));
        if (best) return { type: 'play', hand, unit: best.id };
        break;
      }
      case 'soin': {
        const pool = allies.filter((a) => affordable(card, a) && a.hpMax - a.hp >= card.heal);
        const { best } = bestOf(pool, (a) => a.hpMax + engine.atkOf(a));
        if (best) return { type: 'play', hand, unit: best.id };
        break;
      }
      case 'bouclier_temporel': {
        const pool = allies.filter((a) => affordable(card, a) && !a.shield
          && engine.adjacentToEnemy(a.x, a.y, me));
        const { best } = bestOf(pool, (a) => a.hpMax + engine.atkOf(a));
        if (best) return { type: 'play', hand, unit: best.id };
        break;
      }
      case 'gel': {
        const pool = enemies.filter((e) => affordable(card, e) && manhattan(e, myTower) <= 2 && !engine.isFrozen(e));
        const { best } = bestOf(pool, (e) => engine.atkOf(e));
        if (best) return { type: 'play', hand, unit: best.id };
        break;
      }
      case 'portail': {
        // amener un frappeur prêt à agir au contact de la tour ennemie
        const strikers = allies.filter((a) => engine.canAct(a) && !a.attacked);
        let plan = null;
        let planValue = 0;
        for (const a of strikers) {
          for (const c of engine.portalCells(a, card.range)) {
            if (!affordable(card, c)) continue;
            const reach = manhattan(c, enemyTower) <= engine.rngOf(a);
            if (!reach) continue;
            const value = engine.atkOf(a) + (manhattan(a, enemyTower) > engine.rngOf(a) ? 2 : 0);
            if (value > planValue) {
              planValue = value;
              plan = { type: 'play', hand, unit: a.id, toX: c.x, toY: c.y };
            }
          }
        }
        if (plan && planValue >= 4) return plan;
        break;
      }
      case 'mur_de_pierre': {
        // barrer le chemin d'un ennemi menaçant qui approche de notre tour
        const threats = enemies.filter((e) => !engine.has(e, KW.VOL) && manhattan(e, myTower) <= 3
          && manhattan(e, myTower) > 1);
        if (threats.length === 0) break;
        const threat = bestOf(threats, (e) => engine.atkOf(e)).best;
        const dx = Math.sign(myTower.x - threat.x);
        const dy = Math.sign(myTower.y - threat.y);
        const candidates = [{ x: threat.x, y: threat.y + dy }, { x: threat.x + dx, y: threat.y }]
          .filter((c) => (dx !== 0 || c.x === threat.x) && (dy !== 0 || c.y === threat.y));
        const walls = engine.wallCells();
        for (const c of candidates) {
          if (walls.some((w) => w.x === c.x && w.y === c.y) && affordable(card, c)) {
            return { type: 'play', hand, x: c.x, y: c.y };
          }
        }
        break;
      }
      default:
        break;
    }
  }
  return null;
}

function pickAbility(engine, me) {
  for (const hero of engine.unitsOf(me).sort(byId)) {
    const targets = engine.abilityTargets(hero);
    if (targets.length === 0) continue;
    const ab = cardById(hero.cardId).ability;
    switch (ab.kind) {
      case ABILITY.RALLY: {
        const allies = engine.unitsOf(me).filter((u) => u.id !== hero.id && manhattan(u, hero) <= ab.radius);
        if (allies.length >= 2) return { type: 'ability', unit: hero.id, target: targets[0] };
        break;
      }
      case ABILITY.SPARK:
      case ABILITY.DRAIN: {
        const dmg = ab.kind === ABILITY.SPARK ? 1 : 2;
        const { best } = bestOf(targets, (t) => hitValue(engine, engine.unit(t.unit), dmg));
        if (best) return { type: 'ability', unit: hero.id, target: best };
        break;
      }
      case ABILITY.BLESS: {
        const pool = targets.filter((t) => {
          const u = engine.unit(t.unit);
          return !u.shield && engine.adjacentToEnemy(u.x, u.y, me);
        });
        const { best } = bestOf(pool, (t) => engine.unit(t.unit).hpMax);
        if (best) return { type: 'ability', unit: hero.id, target: best };
        break;
      }
      default:
        break;
    }
  }
  return null;
}

// --- déplacement -------------------------------------------------------------------------------

/** Score d'une position pour une unité : approche de la tour ennemie, opportunités, terrain. */
function positionScore(engine, u, pos) {
  const enemyTower = engine.towerOf(1 - u.owner);
  const range = engine.rngOf(u);
  const atk = engine.atkOf(u);
  let score = -manhattan(pos, enemyTower) * VALUE.MOVE_TOWER_WEIGHT;
  if (manhattan(pos, enemyTower) <= range) score += 6;
  let bestHit = 0;
  for (const e of engine.unitsOf(1 - u.owner)) {
    if (manhattan(pos, e) <= range) bestHit = Math.max(bestHit, hitValue(engine, e, atk));
  }
  score += Math.min(bestHit, 8);
  if (range > 1 && engine.adjacentToEnemy(pos.x, pos.y, u.owner)) score -= 3;
  const terrain = engine.cell(pos.x, pos.y).terrain;
  if (terrain === TERRAIN.FONTAINE) score += 3;
  if (terrain === TERRAIN.FORET) score += 1;
  if (terrain === TERRAIN.BRASIER && !engine.has(u, KW.VOL)) score -= 6;
  return score;
}

function pickMove(engine, me) {
  for (const u of engine.unitsOf(me).sort((a, b) => engine.atkOf(b) - engine.atkOf(a) || a.id - b.id)) {
    const cells = engine.reachable(u);
    if (cells.size === 0) continue;
    const here = positionScore(engine, u, u);
    const { best, score } = bestOf([...cells.values()], (c) => positionScore(engine, u, c));
    if (best && score > here) return { type: 'move', unit: u.id, x: best.x, y: best.y };
  }
  return null;
}

/** Prochaine action du bot pour le camp `me`, ou { type: 'end' }. */
export function chooseAction(engine, me) {
  if (engine.over || engine.current !== me) return { type: 'end' };
  return pickAttack(engine, me, true)
    ?? pickUnitCard(engine, me)
    ?? pickSpell(engine, me)
    ?? pickEquip(engine, me)
    ?? pickAbility(engine, me)
    ?? pickMove(engine, me)
    ?? pickAttack(engine, me, false)
    ?? { type: 'end' };
}

/** Joue le tour complet du camp `me`. Renvoie le nombre d'actions jouées (hors `end`). */
export function playTurn(engine, me, maxActions = 200) {
  let count = 0;
  while (count < maxActions && !engine.over && engine.current === me) {
    const action = chooseAction(engine, me);
    const res = engine.apply(action);
    if (!res.ok) throw new Error(`le bot a proposé une action illégale : ${JSON.stringify(action)} — ${res.error}`);
    if (action.type === 'end') break;
    count += 1;
  }
  if (!engine.over && engine.current === me) {
    throw new Error(`le bot n'a pas fini son tour en ${maxActions} actions`);
  }
  return count;
}

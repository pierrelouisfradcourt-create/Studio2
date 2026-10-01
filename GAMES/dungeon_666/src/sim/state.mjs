// Briques d'état partagées par tous les modules de simulation : identifiants, événements,
// création du héros, statistiques dérivées par défaut. Aucune dépendance vers les autres
// modules de sim (évite les imports circulaires).

export function newId(game) {
  return game.nextId++;
}

/**
 * Événement de simulation, consommé par le rendu, l'audio et la télémétrie.
 * La sim ne sait pas qui l'écoute ; `main` vide la liste après chaque image.
 */
export function emit(game, type, data) {
  const ev = data ? { type, tick: game.tick, ...data } : { type, tick: game.tick };
  game.events.push(ev);
  return ev;
}

/** Statistiques dérivées : bases + équipement + bénédictions (recalculées par stats.mjs). */
export function baseStats() {
  return {
    damageMult: 1,
    attackSpeedMult: 1,
    critChance: 0,
    critMult: 0,
    maxHpBonus: 0,
    armor: 0, // fraction de dégâts réduite, plafonnée
    moveSpeedMult: 1,
    dashChargesBonus: 0,
    dashRechargeMult: 1,
    skillDamageMult: 1,
    skillCooldownMult: 1,
    superChargeMult: 1,
    gadgetChargesBonus: 0,
    healOnKill: 0,
    lifesteal: 0,
    goldFindMult: 1,
    knockbackMult: 1,
    weaponDamage: 0, // dégâts de base de l'arme portée (W)
    armorHp: 0, // PV apportés par l'armure portée
  };
}

export function createPlayer(tuning, x, y) {
  const p = tuning.player;
  return {
    x,
    y,
    vx: 0,
    vy: 0,
    r: p.radius,
    hp: p.maxHp,
    maxHp: p.maxHp,
    facing: -Math.PI / 2,
    aimX: 0,
    aimY: -1,
    moveX: 0,
    moveY: 0,
    manualAimX: 0,
    manualAimY: 0,
    attackHeld: false,
    state: 'free', // free | attack | dash | cast | super | dead
    stateTime: 0,
    attack: null,
    comboIndex: 0,
    comboTimer: 99,
    swingSeq: 0,
    dashCharges: tuning.dash.charges,
    dashRecharge: 0,
    dashDirX: 0,
    dashDirY: -1,
    dashT: 0,
    strikeWindow: 0,
    iframes: 0,
    dodgeIframes: 0, // part des i-frames qui vient d'un dash (sert l'événement « esquive »)
    hurtFlash: 0,
    skillCd: 0,
    castT: 0,
    castDirX: 0,
    castDirY: -1,
    gadgetCharges: tuning.gadget.chargesPerSection,
    superCharge: tuning.super.startCharge ?? 0,
    superT: 0,
    superTick: 0,
    buffer: { action: null, t: 0, aimX: 0, aimY: 0 },
    dodgedIds: [], // attaques déjà esquivées pendant le dash en cours
    lastTargetId: 0, // cible « collante » de la visée assistée
    lastTargetAt: -99,
    stats: baseStats(),
    procs: [], // effets déclenchés des bénédictions (données interprétées par combat.mjs)
  };
}

/** Statistiques de télémétrie : lues par les bots, les tests et le rapport de playtest. */
export function createTelemetry() {
  return {
    damageDealt: 0,
    damageTaken: 0,
    hitsTaken: 0,
    dodges: 0,
    dashes: 0,
    attacks: 0,
    hitsLanded: 0,
    kills: 0,
    deaths: 0,
    roomsCleared: 0,
    skillCasts: 0,
    gadgetUses: 0,
    superUses: 0,
    deflects: 0,
    wallSlams: 0,
    roomTimes: [],
    killTimes: [], // durée de vie (s) des ennemis tués, par type
    deathCauses: {},
  };
}

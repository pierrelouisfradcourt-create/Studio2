// logic.mjs — cœur métier déterministe de Chaton Clicker (module `logic`, blueprint.json).
// Économie (gain/caresse, production passive, coût croissant), point de décision actif
// vs passif, rejeu enrichi, prestige (reset + avantage permanent), RNG seedé et hash
// d'état. Pur : aucune dépendance DOM, aucun Date.now() — testable hors navigateur.
//
// knowledge_base/search.mjs consulté avant écriture (économie idle/RNG seedé/hash d'état
// déterministe) : aucune brique réutilisable pour un économie de clicker n'existe dans la
// bibliothèque (uniquement des systèmes tactiques/navigation sans rapport) — implémentation
// originale, delta = 100%. RNG : mulberry32 (Tommy Ettinger, domaine public/CC0), technique
// connue réécrite ici, pas une dépendance externe.
//
// hashEtat() N'UTILISE PAS node:crypto : ce module est chargé tel quel par le navigateur
// (import direct depuis main.mjs -> index.html) où le spécificateur `node:crypto` est
// irrésolvable (échec CORS/URL mesuré via e2e.mjs réel — cf. BUILDER_REPORT.md §2h).
// FNV-1a pur JS suffit : seule la reproductibilité (même entrée => même sortie) est
// exigée par le brief, aucune propriété cryptographique.

/** RNG seedé mulberry32 : pur, déterministe, [0,1). Domaine public (CC0). */
export function makeRng(seed) {
  let state = seed >>> 0;
  return function rng() {
    state = (state + 0x6d2b79f5) | 0;
    let t = Math.imul(state ^ (state >>> 15), 1 | state);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

// Un producteur : coût de base, production/tick, taux de croissance du coût (N4 : valeurs
// uniques à ce projet, libertés déléguées du brief).
export const PRODUCER_DEFS = [
  { id: 0, label: 'Panier de chatons', baseCost: 10, baseProduction: 0.5, growth: 1.15 },
  { id: 1, label: 'Arbre à chats', baseCost: 60, baseProduction: 3, growth: 1.15 },
  { id: 2, label: 'Chatterie', baseCost: 300, baseProduction: 15, growth: 1.15 },
];

// Chance de caresse critique (gain doublé) — seul point d'usage du RNG seedé : reste
// déterministe (même seed + même suite d'actions => même suite de tirages).
const CRIT_CHANCE = 0.1;
const CRIT_MULTIPLIER = 2;

/** FNV-1a 32 bits — pur JS, aucune dépendance (portable navigateur + Node). */
function fnv1a(str) {
  let h = 0x811c9dc5;
  for (let i = 0; i < str.length; i++) {
    h ^= str.charCodeAt(i);
    h = Math.imul(h, 0x01000193);
  }
  return (h >>> 0).toString(16).padStart(8, '0');
}

/** Empreinte 64 bits (deux passes FNV-1a, avant/inversé) — réduit les collisions d'un
 * simple hash 32 bits sans introduire de dépendance crypto. */
function hashPur(str) {
  return fnv1a(str) + fnv1a(Array.from(str).reverse().join(''));
}

export class GameState {
  constructor(seed = 12345) {
    this.seed = seed;
    this._rng = makeRng(seed);
    this._cloneSalt = 0;
    this.ronrons = 0;
    this.prestige = 0;
    this.producteurs = PRODUCER_DEFS.map((def) => ({
      id: def.id,
      count: 0,
      cost: def.baseCost,
    }));
    this.tickCount = 0;
    this.achatsCount = 0;
    this.caressesCount = 0;
    this.prestigeCount = 0;
  }

  /** R15 : gain par caresse, boosté à vie de +10% par point de prestige. */
  get gainParCaresse() {
    return 1 + this.prestige * 0.1;
  }

  /** R3 (P02 gain) : caresser incrémente ronrons ; chance de critique via RNG seedé. */
  caresser() {
    const critique = this._rng() < CRIT_CHANCE;
    const gain = this.gainParCaresse * (critique ? CRIT_MULTIPLIER : 1);
    this.ronrons += gain;
    this.caressesCount += 1;
    return { gain, critique };
  }

  /** R8 : coût courant d'un producteur (croît après chaque achat de ce producteur). */
  coutProducteur(idx) {
    return this.producteurs[idx].cost;
  }

  /** R5 : le bouton d'achat passe d'inactif à actif dès que ronrons >= coût. */
  producteurAbordable(idx = 0) {
    return this.ronrons >= this.coutProducteur(idx);
  }

  /** R6/R8 : achat d'un producteur — coût croissant, production passive au tick. */
  acheterProducteur(idx) {
    if (idx < 0 || idx >= this.producteurs.length) return false;
    if (!this.producteurAbordable(idx)) return false;
    const prod = this.producteurs[idx];
    this.ronrons -= prod.cost;
    prod.count += 1;
    prod.cost = Math.round(prod.cost * PRODUCER_DEFS[idx].growth * 100) / 100;
    this.achatsCount += 1;
    return true;
  }

  /** R7 : production passive — un pas logique fixe par appel, jamais Date.now(). */
  tick() {
    let production = 0;
    for (let i = 0; i < this.producteurs.length; i++) {
      production += this.producteurs[i].count * PRODUCER_DEFS[i].baseProduction;
    }
    this.ronrons += production;
    this.tickCount += 1;
    return production;
  }

  /** R14/R15 : renouveau de portée — reset ronrons/producteurs, prestige permanent. */
  renouveauPortee() {
    if (this.ronrons <= 0) return 0;
    const gained = Math.max(1, Math.floor(Math.sqrt(this.ronrons / 100)));
    this.prestige += gained;
    this.ronrons = 0;
    for (let i = 0; i < this.producteurs.length; i++) {
      this.producteurs[i].count = 0;
      this.producteurs[i].cost = PRODUCER_DEFS[i].baseCost;
    }
    this.prestigeCount += 1;
    return gained;
  }

  /** R10/R11 : objectif courant, change à chaque palier franchi. */
  objectifCourant() {
    if (this.achatsCount === 0) return 'Caresse le chaton pour acheter ton premier panier de chatons';
    if (this.producteurs[1].count === 0) return 'Achète un arbre à chats pour accélérer la production';
    return 'Renouvelle ta portée pour un bonus permanent';
  }

  /** Copie indépendante — RNG dérivé (salt incrémental) pour ne jamais partager un flux. */
  clone() {
    const c = new GameState(this.seed);
    c._rng = makeRng(((this.seed * 2654435761) ^ (this._cloneSalt + 1)) >>> 0);
    this._cloneSalt += 1;
    c.ronrons = this.ronrons;
    c.prestige = this.prestige;
    c.producteurs = this.producteurs.map((p) => ({ ...p }));
    c.tickCount = this.tickCount;
    c.achatsCount = this.achatsCount;
    c.caressesCount = this.caressesCount;
    c.prestigeCount = this.prestigeCount;
    return c;
  }

  /** R9 : divergence mesurable entre une politique oisive et une politique active. */
  comparerPolitiques(frames = 300) {
    const passif = this.clone();
    const actif = this.clone();
    for (let i = 0; i < frames; i++) {
      passif.tick();
      actif.tick();
      if (i % 5 === 0) actif.caresser();
    }
    return {
      passif: passif.ronrons,
      actif: actif.ronrons,
      diff: actif.ronrons - passif.ronrons,
      caressesActif: actif.caressesCount,
    };
  }

  /** R12 : rejeu de la boucle (caresse -> achat -> tick) dans l'état post-achat. */
  rejouerBoucle(frames = 50) {
    const etat = this.clone();
    etat.caresser();
    etat.caresser();
    if (etat.producteurAbordable(0)) etat.acheterProducteur(0);
    for (let i = 0; i < frames; i++) etat.tick();
    return {
      ronronsApres: etat.ronrons,
      producteursAchetes: etat.producteurs[0].count,
    };
  }

  /** R16 : hash d'état — même seed + même suite d'actions => même hash. */
  hashEtat() {
    const payload = JSON.stringify({
      ronrons: Math.round(this.ronrons * 1000),
      prestige: this.prestige,
      producteurs: this.producteurs,
      tickCount: this.tickCount,
      achatsCount: this.achatsCount,
      caressesCount: this.caressesCount,
    });
    return hashPur(payload);
  }
}

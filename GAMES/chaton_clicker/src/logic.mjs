import crypto from 'crypto';

export class GameState {
  constructor(seed = 12345) {
    this.seed = seed;
    this.rng = this.seededRNG(seed);
    this.ronrons = 0;
    this.gainParCaresse = 1;
    this.prestige = 0;
    this.producteurs = [
      { count: 0, cost: 10, production: 0.5 },
      { count: 0, cost: 50, production: 3 },
      { count: 0, cost: 200, production: 15 }
    ];
    this.tick_count = 0;
    this.decisions = { caresse: 0, achat: 0, prestige: 0 };
  }

  seededRNG(seed) {
    let state = seed;
    return () => {
      state = (state * 1103515245 + 12345) % (2 ** 31);
      return (state / (2 ** 31)) % 1;
    };
  }

  caresser() {
    const gain = this.gainParCaresse + Math.floor(this.rng() * 0.1 * this.gainParCaresse);
    this.ronrons += gain;
    this.decisions.caresse++;
    return { ronrons: this.ronrons, gain };
  }

  acheterProducteur(idx) {
    if (idx < 0 || idx >= this.producteurs.length) return null;
    const prod = this.producteurs[idx];
    if (this.ronrons < prod.cost) return null;
    this.ronrons -= prod.cost;
    prod.count++;
    prod.cost = Math.floor(prod.cost * 1.15);
    this.decisions.achat++;
    return { success: true, cost: prod.cost, producteur: idx };
  }

  tick() {
    let totalProduction = 0;
    for (const prod of this.producteurs) {
      totalProduction += prod.count * prod.production;
    }
    this.ronrons += totalProduction;
    this.tick_count++;
    return { ronrons: this.ronrons, production: totalProduction };
  }

  renouveauPortee() {
    if (this.ronrons === 0) return null;
    const prestige_gained = Math.max(1, Math.floor(Math.sqrt(this.ronrons / 100)));
    this.prestige += prestige_gained;
    this.ronrons = 0;
    this.gainParCaresse = 1 + this.prestige * 0.1;
    this.producteurs.forEach(p => p.count = 0);
    this.decisions.prestige++;
    return { prestige: this.prestige, gainParCaresse: this.gainParCaresse };
  }

  objectifCourant() {
    if (this.decisions.achat === 0) {
      return "Caresse le chaton 10 fois";
    } else if (this.decisions.achat === 1) {
      return "Achete un 2e producteur";
    } else {
      return "Atteins une prestige de 5";
    }
  }

  producteurAbordable(idx = 0) {
    if (idx < 0 || idx >= this.producteurs.length) return false;
    return this.ronrons >= this.producteurs[idx].cost;
  }

  hashEtat() {
    const state_str = JSON.stringify({
      ronrons: this.ronrons,
      gainParCaresse: this.gainParCaresse,
      prestige: this.prestige,
      producteurs: this.producteurs,
      decisions: this.decisions,
      tick_count: this.tick_count
    });
    return crypto.createHash('sha256').update(state_str).digest('hex');
  }

  clone() {
    const cloned = new GameState(this.seed);
    cloned.ronrons = this.ronrons;
    cloned.gainParCaresse = this.gainParCaresse;
    cloned.prestige = this.prestige;
    cloned.producteurs = JSON.parse(JSON.stringify(this.producteurs));
    cloned.tick_count = this.tick_count;
    cloned.decisions = JSON.parse(JSON.stringify(this.decisions));
    cloned.rng = this.rng;
    return cloned;
  }

  comparerPolitiques(frames = 300) {
    const etat_passif = this.clone();
    const etat_actif = this.clone();

    for (let i = 0; i < frames; i++) {
      etat_passif.tick();
      etat_actif.tick();
      if (i % 5 === 0) etat_actif.caresser();
    }

    return {
      passif: etat_passif.ronrons,
      actif: etat_actif.ronrons,
      diff: etat_actif.ronrons - etat_passif.ronrons
    };
  }

  rejouerBoucle(frames = 50) {
    const etat = this.clone();
    for (let i = 0; i < 2; i++) {
      etat.caresser();
    }
    if (etat.producteurAbordable(0)) {
      etat.acheterProducteur(0);
    }
    for (let i = 0; i < frames; i++) {
      etat.tick();
    }
    return {
      ronrons_apres: etat.ronrons,
      producteurs_achetes: etat.producteurs[0].count
    };
  }
}

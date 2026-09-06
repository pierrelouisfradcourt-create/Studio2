// render.mjs — vue DOM pure (module `render`, blueprint.json). Lit un état FOURNI par
// l'appelant (main), ne décide jamais des règles du jeu, n'importe jamais logic.mjs.
// Les seuls calculs faits ici sont des comparaisons d'affichage sur les nombres reçus
// (ex. ronrons >= coût pour l'attribut `disabled`) — une transformation de présentation,
// jamais une règle de jeu.

const IDS = {
  objectif: 'objectif',
  chaton: 'chaton',
  compteur: 'compteur-ronrons',
  producteurs: 'producteurs',
  panier: 'panier_chatons',
  prestige: 'prestige',
  renouveau: 'renouveau_portee',
};

export class Renderer {
  constructor(doc, containerId = 'game') {
    this.doc = doc;
    this.container = doc.getElementById(containerId);
    if (!this.container) {
      this.container = doc.createElement('div');
      this.container.id = containerId;
      doc.body.appendChild(this.container);
    }
  }

  _ensure(id, tag, className) {
    let el = this.doc.getElementById(id);
    if (!el) {
      el = this.doc.createElement(tag);
      el.id = id;
      if (className) el.className = className;
      this.container.appendChild(el);
    }
    return el;
  }

  /** R1 : HUD objectif, non vide dès le premier rendu. */
  renderObjectif(text) {
    const el = this._ensure(IDS.objectif, 'div', 'hud-objectif');
    el.textContent = text;
  }

  /** R17 : chaton dessiné, visible et cliquable dès le chargement. */
  dessinerChaton() {
    const el = this._ensure(IDS.chaton, 'div', 'chaton');
    el.setAttribute('data-testid', 'caresser_chaton');
    if (!el.textContent) el.textContent = '🐱';
    return el;
  }

  /** R4 : réaction visuelle transitoire juste après une caresse. */
  reagirCaresse() {
    const el = this.doc.getElementById(IDS.chaton);
    if (!el) return;
    el.classList.add('caresse-feedback');
    setTimeout(() => el.classList.remove('caresse-feedback'), 200);
  }

  afficherRonrons(ronrons) {
    const el = this._ensure(IDS.compteur, 'div', 'compteur');
    const arrondi = Math.floor(ronrons * 10) / 10;
    el.setAttribute('data-ronrons', String(arrondi));
    el.textContent = `Ronrons : ${arrondi}`;
  }

  /** R5/R6 : boutons producteurs — actif/inactif calculé par comparaison d'affichage. */
  afficherProducteurs(ronrons, producteurs) {
    const panierProducteurs = this._ensure(IDS.producteurs, 'div', 'producteurs');
    producteurs.forEach((prod, idx) => {
      const btnId = `producteur-btn-${idx}`;
      let btn = this.doc.getElementById(btnId);
      if (!btn) {
        btn = this.doc.createElement('button');
        btn.id = btnId;
        btn.className = 'producteur-btn';
        btn.setAttribute('data-testid', `acheter_producteur_${idx}`);
        panierProducteurs.appendChild(btn);
      }
      const abordable = ronrons >= prod.cost;
      btn.disabled = !abordable;
      btn.setAttribute('data-cost', String(prod.cost));
      btn.setAttribute('data-count', String(prod.count));
      btn.textContent = `Producteur ${idx + 1} (x${prod.count}) — coût ${prod.cost}`;
    });

    // R7 : le panier de chatons n'apparaît qu'une fois un producteur possédé.
    const owned = producteurs.some((p) => p.count > 0);
    let panier = this.doc.getElementById(IDS.panier);
    if (!owned) {
      if (panier) panier.hidden = true;
      return;
    }
    if (!panier) {
      panier = this.doc.createElement('div');
      panier.id = IDS.panier;
      panier.className = 'panier';
      this.container.appendChild(panier);
    }
    panier.hidden = false;
    panier.textContent = producteurs.map((p, idx) => `🐈#${idx}×${p.count}`).join(' ');
  }

  afficherPrestige(prestige) {
    const el = this._ensure(IDS.prestige, 'div', 'prestige');
    el.setAttribute('data-prestige', String(prestige));
    el.textContent = `Prestige : ${prestige}`;
  }

  /** R13/R14 : bouton de renouveau, actif seulement si un renouveau rapporterait quelque chose. */
  afficherBoutonRenouveau(ronrons) {
    const el = this._ensure(IDS.renouveau, 'button', 'renouveau-btn');
    el.setAttribute('data-testid', 'renouveau_portee');
    el.disabled = !(ronrons > 0);
    el.textContent = 'Renouveau de portée';
  }

  /** Composition de rendu — appelée à chaque changement d'état par `main`. */
  render(gameState) {
    this.renderObjectif(gameState.objectifCourant());
    this.dessinerChaton();
    this.afficherRonrons(gameState.ronrons);
    this.afficherProducteurs(gameState.ronrons, gameState.producteurs);
    this.afficherPrestige(gameState.prestige);
    this.afficherBoutonRenouveau(gameState.ronrons);
  }
}

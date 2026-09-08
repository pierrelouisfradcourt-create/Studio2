export class Renderer {
  constructor(containerId = 'game') {
    this.container = document.getElementById(containerId);
    if (!this.container) {
      this.container = document.createElement('div');
      this.container.id = 'game';
      document.body.appendChild(this.container);
    }
  }

  renderObjectif(text) {
    let objectifEl = document.getElementById('objectif');
    if (!objectifEl) {
      objectifEl = document.createElement('div');
      objectifEl.id = 'objectif';
      objectifEl.className = 'hud-objectif';
      this.container.appendChild(objectifEl);
    }
    objectifEl.textContent = text;
  }

  dessinerChaton() {
    let chatonEl = document.getElementById('chaton');
    if (!chatonEl) {
      chatonEl = document.createElement('div');
      chatonEl.id = 'chaton';
      chatonEl.className = 'chaton';
      chatonEl.textContent = '🐱';
      chatonEl.setAttribute('data-testid', 'caresser_chaton');
      this.container.appendChild(chatonEl);
    }
    return chatonEl;
  }

  reagirCaresse() {
    const chatonEl = document.getElementById('chaton');
    if (chatonEl) {
      chatonEl.classList.add('caresse-feedback');
      setTimeout(() => chatonEl.classList.remove('caresse-feedback'), 200);
    }
  }

  afficherRonrons(count) {
    let compteurEl = document.getElementById('compteur-ronrons');
    if (!compteurEl) {
      compteurEl = document.createElement('div');
      compteurEl.id = 'compteur-ronrons';
      compteurEl.className = 'compteur';
      this.container.appendChild(compteurEl);
    }
    compteurEl.textContent = `Ronrons: ${Math.floor(count)}`;
  }

  afficherProducteurs(producteurs) {
    let panierEl = document.getElementById('panier_chatons');
    if (!panierEl) {
      panierEl = document.createElement('div');
      panierEl.id = 'panier_chatons';
      panierEl.className = 'panier';
      this.container.appendChild(panierEl);
    }
    panierEl.innerHTML = '';

    producteurs.forEach((prod, idx) => {
      const prodEl = document.createElement('button');
      prodEl.className = 'producteur-btn';
      prodEl.setAttribute('data-testid', `acheter_producteur_${idx}`);
      prodEl.textContent = `Producteur ${idx + 1}: ${prod.count} (Coût: ${prod.cost})`;
      panierEl.appendChild(prodEl);
    });
  }

  afficherPrestige(prestige) {
    let prestigeEl = document.getElementById('prestige');
    if (!prestigeEl) {
      prestigeEl = document.createElement('div');
      prestigeEl.id = 'prestige';
      prestigeEl.className = 'prestige';
      this.container.appendChild(prestigeEl);
    }
    prestigeEl.textContent = `Prestige: ${prestige}`;
  }

  afficherBoutonRenouveau() {
    let renouvelloEl = document.getElementById('renouveau_portee');
    if (!renouvelloEl) {
      renouvelloEl = document.createElement('button');
      renouvelloEl.id = 'renouveau_portee';
      renouvelloEl.className = 'renouveau-btn';
      renouvelloEl.setAttribute('data-testid', 'renouveau_portee');
      renouvelloEl.textContent = 'Renouveau de Portée';
      this.container.appendChild(renouvelloEl);
    }
  }

  render(gameState) {
    this.renderObjectif(gameState.objectifCourant());
    this.dessinerChaton();
    this.afficherRonrons(gameState.ronrons);
    this.afficherProducteurs(gameState.producteurs);
    this.afficherPrestige(gameState.prestige);
    this.afficherBoutonRenouveau();
  }
}

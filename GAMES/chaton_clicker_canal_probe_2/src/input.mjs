export class InputHandler {
  constructor(gameState, renderer) {
    this.gameState = gameState;
    this.renderer = renderer;
  }

  brancherCaresse(chatonEl) {
    if (!chatonEl) {
      chatonEl = document.getElementById('chaton');
    }
    if (chatonEl) {
      chatonEl.addEventListener('click', () => {
        this.gameState.caresser();
        this.renderer.reagirCaresse();
      });
    }
  }

  brancherAchat(producteurIdx = 0) {
    const btnEl = document.querySelector(`[data-testid="acheter_producteur_${producteurIdx}"]`);
    if (btnEl) {
      btnEl.addEventListener('click', () => {
        this.gameState.acheterProducteur(producteurIdx);
      });
    }
  }

  brancherRenouveau() {
    const renouvelloEl = document.getElementById('renouveau_portee');
    if (renouvelloEl) {
      renouvelloEl.addEventListener('click', () => {
        this.gameState.renouveauPortee();
      });
    }
  }

  brancherTout() {
    this.brancherCaresse();
    for (let i = 0; i < this.gameState.producteurs.length; i++) {
      this.brancherAchat(i);
    }
    this.brancherRenouveau();
  }
}

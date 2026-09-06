// input.mjs — câblage des affordances joueur (module `input`, blueprint.json).
// Câble les événements DOM vers les actions PUBLIQUES de logic uniquement — ne touche
// jamais au rendu (deps_interdites: input -> render). Après chaque action il notifie un
// callback fourni par la composition (main), qui décide seul de ce qui se redessine.

export class InputHandler {
  constructor(gameState, doc, onAction = () => {}) {
    this.gameState = gameState;
    this.doc = doc;
    this.onAction = onAction;
  }

  /** R2 : clic sur le chaton -> logic.caresser(). */
  brancherCaresse() {
    const el = this.doc.querySelector('[data-testid="caresser_chaton"]');
    if (!el) return;
    el.addEventListener('click', () => {
      const result = this.gameState.caresser();
      this.onAction('caresse', result);
    });
  }

  /** R6 : clic sur le bouton d'achat -> logic.acheterProducteur(idx). */
  brancherAchat(idx) {
    const el = this.doc.querySelector(`[data-testid="acheter_producteur_${idx}"]`);
    if (!el) return;
    el.addEventListener('click', () => {
      const achete = this.gameState.acheterProducteur(idx);
      this.onAction('achat', { idx, achete });
    });
  }

  /** R13 : clic sur le bouton de renouveau -> logic.renouveauPortee(). */
  brancherRenouveau() {
    const el = this.doc.querySelector('[data-testid="renouveau_portee"]');
    if (!el) return;
    el.addEventListener('click', () => {
      const gagne = this.gameState.renouveauPortee();
      this.onAction('renouveau', { gagne });
    });
  }

  /** Câble toutes les affordances connues du jeu. */
  brancherTout() {
    this.brancherCaresse();
    for (let i = 0; i < this.gameState.producteurs.length; i++) {
      this.brancherAchat(i);
    }
    this.brancherRenouveau();
  }
}

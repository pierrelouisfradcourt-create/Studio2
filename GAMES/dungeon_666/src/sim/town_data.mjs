// VILLE — améliorations permanentes du Sanctuaire (payées en Âmes, jamais perdues).
//
// stat : statistique du héros modifiée (voir state.baseStats) ; perLevel : gain par niveau ;
// costs[n] : prix du niveau n+1. Les valeurs visent une progression testable en 20-40 min.

export const UPGRADES = {
  vitalite: { name: 'Vitalité', text: '+10 PV max par niveau.', stat: 'maxHpBonus', perLevel: 10, max: 5, costs: [15, 30, 50, 75, 105] },
  celerite: { name: 'Célérité', text: 'Recharge du dash −6 % par niveau.', stat: 'dashRechargeMult', perLevel: -0.06, max: 3, costs: [25, 50, 90] },
  ferocite: { name: 'Férocité', text: '+5 % de dégâts par niveau.', stat: 'damageMult', perLevel: 0.05, max: 4, costs: [20, 40, 70, 110] },
  arsenal: { name: 'Arsenal', text: '+1 charge de gadget par section.', stat: 'gadgetChargesBonus', perLevel: 1, max: 1, costs: [60] },
  fortune: { name: 'Fortune', text: '+15 % d\'or trouvé par niveau.', stat: 'goldFindMult', perLevel: 0.15, max: 3, costs: [15, 30, 55] },
  avidite: { name: 'Avidité de Charon', text: 'Charon prélève 15 % de moins à chaque mort.', stat: 'deathGoldKeepBonus', perLevel: 0.15, max: 2, costs: [30, 60] },
};

// Âmes rendues par le recyclage d'un objet du coffre, selon sa rareté.
export const SALVAGE_SOULS = { commun: 1, magique: 3, rare: 8, legendaire: 20 };

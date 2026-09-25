// Catalogue des cartes — DONNÉES pures, aucune logique. Chaque carte a un COÛT en mana.
// Quatre familles : créature (présence), héros/commandant (aura + capacité active),
// sort (situation instantanée), équipement (circule entre porteurs : revient en main à la mort).
// Les mots-clés sont des identifiants stables consommés par engine.mjs.

export const TYPE = Object.freeze({
  CREATURE: 'creature',
  HERO: 'hero',
  SPELL: 'spell',
  EQUIP: 'equip',
});

export const KW = Object.freeze({
  VOL: 'vol',                 // ignore obstacles, unités, zones de contrôle et marais en déplacement
  CELERITE: 'celerite',       // peut agir le tour où elle est invoquée
  PROVOCATION: 'provocation', // les ennemis à portée DOIVENT la cibler
  PIETINEMENT: 'pietinement', // ignore les zones de contrôle
});

export const AURA = Object.freeze({
  ATK: 'atk',                       // alliés dans le rayon : +valeur ATQ
  SPELL_DISCOUNT: 'spell_discount', // sorts ciblant une case du rayon : -valeur mana
  NECRO: 'necro',                   // allié mort dans le rayon : une Ombre apparaît
  ARMOR: 'armor',                   // alliés dans le rayon : dégâts subis -valeur (plancher 1)
});

export const ABILITY = Object.freeze({
  RALLY: 'rally',   // alliés dans le rayon : +1 déplacement ce tour
  SPARK: 'spark',   // 1 dégât à un ennemi à portée
  DRAIN: 'drain',   // 2 dégâts à un ennemi à portée, soigne le héros de 2
  BLESS: 'bless',   // bouclier sur un allié à portée
});

/** Types de cible d'un sort, d'un équipement ou d'une capacité. */
export const TARGET = Object.freeze({
  CELL: 'cell',             // n'importe quelle case du plateau
  EMPTY_CELL: 'empty_cell', // case libre, hors tours
  UNIT: 'unit',             // n'importe quelle unité
  ALLY: 'ally',             // unité alliée
  ENEMY: 'enemy',           // unité ennemie
  ALLY_THEN_CELL: 'ally_then_cell', // allié puis case de destination (portail)
});

function creature(id, name, cost, atk, hp, mov, extra = {}) {
  return Object.freeze({
    id, name, cost, atk, hp, mov, rng: 1, keywords: [], text: '', type: TYPE.CREATURE, ...extra,
  });
}

function hero(id, name, cost, atk, hp, mov, extra = {}) {
  return Object.freeze({
    id, name, cost, atk, hp, mov, rng: 1, keywords: [], text: '', type: TYPE.HERO, ...extra,
  });
}

function spell(id, name, cost, target, text, extra = {}) {
  return Object.freeze({ id, name, cost, target, text, type: TYPE.SPELL, ...extra });
}

function equip(id, name, cost, mods, text) {
  return Object.freeze({
    id, name, cost, type: TYPE.EQUIP, target: TARGET.ALLY, text,
    mods: Object.freeze({ atk: 0, hp: 0, mov: 0, rng: 0, keywords: [], ...mods }),
  });
}

export const CARDS = Object.freeze({
  // --- créatures : elles créent une PRÉSENCE, avancent, combattent, meurent -------------
  gobelin: creature('gobelin', 'Gobelin', 1, 1, 1, 3, { text: 'Petit, rapide, nombreux.' }),
  recruteur_gobelin: creature('recruteur_gobelin', 'Recruteur Gobelin', 2, 1, 2, 2, {
    summon: { card: 'gobelin', count: 2 },
    text: 'À son arrivée : invoque 2 Gobelins sur les cases adjacentes libres.',
  }),
  loup: creature('loup', 'Loup', 2, 2, 1, 3, { text: 'Fragile, mais il court.' }),
  meute_de_loups: creature('meute_de_loups', 'Loup Alpha', 4, 2, 2, 3, {
    summon: { card: 'loup', count: 2 },
    text: 'À son arrivée : invoque 2 Loups sur les cases adjacentes libres. Une meute.',
  }),
  archer: creature('archer', 'Archer', 3, 2, 2, 2, {
    rng: 2, text: 'Portée 2 : frappe sans riposte au corps à corps.',
  }),
  chevalier: creature('chevalier', 'Chevalier', 3, 3, 3, 2, { text: 'Solide et fiable.' }),
  assassin: creature('assassin', 'Assassin', 3, 3, 2, 3, {
    keywords: [KW.CELERITE], text: 'Célérité : agit le tour où il arrive.',
  }),
  golem: creature('golem', 'Golem de Pierre', 4, 2, 7, 1, {
    keywords: [KW.PROVOCATION], text: 'Provocation : les ennemis à portée doivent le frapper.',
  }),
  elementaire_de_feu: creature('elementaire_de_feu', 'Élémentaire de Feu', 3, 2, 3, 2, {
    rng: 2, text: 'Portée 2. Brûle de loin.',
  }),
  ogre: creature('ogre', 'Ogre des Profondeurs', 5, 5, 7, 1, {
    text: 'Très lent. Très gros. Attire les tirs de la tour.',
  }),
  dragon: creature('dragon', 'Dragon', 7, 5, 5, 3, {
    keywords: [KW.VOL], text: 'Vol : survole rochers, unités, marais et zones de contrôle.',
  }),
  pretresse: creature('pretresse', 'Prêtresse', 3, 1, 3, 2, {
    rng: 2, heal: 1, text: 'Portée 2. Fin de ton tour : soigne 1 PV aux alliés adjacents.',
  }),
  ombre: creature('ombre', 'Ombre', 0, 1, 1, 2, {
    token: true, text: 'Jeton. Ne laisse pas d\'Ombre en mourant.',
  }),

  // --- héros / commandants : l'identité de l'armée ---------------------------------------
  seigneur_de_guerre: hero('seigneur_de_guerre', 'Seigneur de Guerre', 5, 3, 6, 2, {
    aura: { kind: AURA.ATK, radius: 2, value: 1 },
    ability: { kind: ABILITY.RALLY, cost: 2, radius: 2, name: 'Cri de ralliement' },
    text: 'Aura (2) : alliés +1 ATQ. Actif 2 mana : alliés dans l\'aura +1 déplacement ce tour.',
  }),
  archimage: hero('archimage', 'Archimage', 4, 2, 4, 2, {
    rng: 2,
    aura: { kind: AURA.SPELL_DISCOUNT, radius: 2, value: 1 },
    ability: { kind: ABILITY.SPARK, cost: 1, range: 2, target: TARGET.ENEMY, name: 'Étincelle' },
    text: 'Aura (2) : les sorts visant une case de l\'aura coûtent 1 de moins. Actif 1 mana : 1 dégât à portée 2.',
  }),
  necromancienne: hero('necromancienne', 'Nécromancienne', 5, 2, 5, 2, {
    rng: 2,
    aura: { kind: AURA.NECRO, radius: 2 },
    ability: { kind: ABILITY.DRAIN, cost: 2, range: 2, target: TARGET.ENEMY, name: 'Drain' },
    text: 'Aura (2) : un allié qui meurt dans l\'aura laisse une Ombre 1/1. Actif 2 mana : 2 dégâts à portée 2, se soigne de 2.',
  }),
  paladin: hero('paladin', 'Paladin', 5, 2, 7, 2, {
    aura: { kind: AURA.ARMOR, radius: 1, value: 1 },
    ability: { kind: ABILITY.BLESS, cost: 2, range: 2, target: TARGET.ALLY, name: 'Bénédiction' },
    text: 'Aura (1) : alliés adjacents subissent 1 dégât de moins. Actif 2 mana : bouclier sur un allié à portée 2.',
  }),

  // --- sorts : ils créent ou retournent une situation --------------------------------------
  boule_de_feu: spell('boule_de_feu', 'Boule de Feu', 4, TARGET.CELL,
    '3 dégâts à TOUT ce qui se trouve dans le carré 3×3 (alliés compris, tours comprises). La case centrale devient un Brasier pendant 4 tours.',
    { damage: 3, radius: 1, brasierTtl: 4 }),
  eclair: spell('eclair', 'Éclair', 2, TARGET.ENEMY, '3 dégâts à une unité ennemie.', { damage: 3 }),
  portail: spell('portail', 'Portail Dimensionnel', 2, TARGET.ALLY_THEN_CELL,
    'Téléporte une unité alliée sur une case libre à 3 cases ou moins.', { range: 3 }),
  bouclier_temporel: spell('bouclier_temporel', 'Bouclier Temporel', 1, TARGET.ALLY,
    'Une unité alliée ignore les prochains dégâts qu\'elle subirait.'),
  mur_de_pierre: spell('mur_de_pierre', 'Mur de Pierre', 2, TARGET.EMPTY_CELL,
    'Une case libre devient un Rocher infranchissable pendant 6 tours.', { rocherTtl: 6 }),
  soin: spell('soin', 'Soin', 2, TARGET.UNIT, 'Rend 4 PV à une unité.', { heal: 4 }),
  gel: spell('gel', 'Gel', 2, TARGET.ENEMY,
    'Une unité ennemie ne peut ni bouger, ni attaquer, ni riposter à son prochain tour.'),

  // --- équipements : circulent entre porteurs -----------------------------------------------
  epee_du_titan: equip('epee_du_titan', 'Épée du Titan', 3,
    { atk: 3, keywords: [KW.PIETINEMENT] }, '+3 ATQ. Piétinement : ignore les zones de contrôle.'),
  couronne_du_tyran: equip('couronne_du_tyran', 'Couronne du Tyran', 2,
    { atk: 1, mov: 1 }, '+1 ATQ, +1 déplacement.'),
  arc_long: equip('arc_long', 'Arc Long', 2, { rng: 1 }, '+1 portée.'),
  bottes_ailees: equip('bottes_ailees', 'Bottes Ailées', 1, { keywords: [KW.VOL] }, 'Le porteur gagne Vol.'),
});

/** Liste de deck (30 cartes) — identique pour les deux camps, mélangée par seed. */
export const DECK_LIST = Object.freeze([
  'gobelin', 'gobelin', 'recruteur_gobelin', 'loup', 'meute_de_loups', 'archer',
  'chevalier', 'chevalier', 'assassin', 'golem', 'elementaire_de_feu', 'ogre', 'dragon',
  'pretresse', 'loup',
  'seigneur_de_guerre', 'archimage', 'necromancienne', 'paladin',
  'boule_de_feu', 'eclair', 'portail', 'bouclier_temporel', 'mur_de_pierre', 'soin', 'gel',
  'epee_du_titan', 'couronne_du_tyran', 'arc_long', 'bottes_ailees',
]);

export function cardById(id) {
  const card = CARDS[id];
  if (!card) throw new Error(`carte inconnue : ${id}`);
  return card;
}

export function isUnitCard(card) {
  return card.type === TYPE.CREATURE || card.type === TYPE.HERO;
}

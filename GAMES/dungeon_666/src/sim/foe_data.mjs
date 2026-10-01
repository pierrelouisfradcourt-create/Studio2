// DONNÉES des archétypes d'ennemis AJOUTÉS (tuning), fusionnées dans tuning.enemies par
// config.mjs, et leur place dans les vagues (ROSTER de room.mjs).
//
// EXTRA_ENEMIES : { kind: { name, radius, hp, speed, mass, damage, …, gold: [lo, hi] } }
// EXTRA_ROSTER  : [{ kind, cost, minIndex, weight }] — coût en budget de vague, index minimal
//                 dans la 1re section (les sections suivantes ont tout le bestiaire), poids.
// EXTRA_ELITE_KINDS : archétypes pouvant recevoir un modificateur d'élite.
//
// BESTIAIRE (priorité 4 de la demande) — archétype -> kind :
//   mêlée rapide   -> imp (Diablotin)          mêlée lourde -> brute (Brute)
//   distance       -> archer (Archer squelette) chargeur     -> charger (Bélier)
//   kamikaze       -> exploder (Possédé)
//   ZONE           -> pyromancer (Pyromancienne, foe_pyromancer.mjs) — NOUVEAU
//   INVOCATEUR     -> necromancer (Nécromancien, foe_necromancer.mjs) — NOUVEAU
//   ÉLITE          -> modificateurs façon champions Diablo (config.mjs elite.mods, foe_elites.mjs)
//
// Règles de lisibilité tenues par chaque archétype : aucun dégât de contact ; toute menace est
// télégraphiée (rouge = ça fait mal ; une alerte inoffensive porte harmless: true) ; les durées
// de télégraphe ne dépendent jamais de l'étage.

export const EXTRA_ENEMIES = {
  // ZONE : garde ses distances, pose des cercles de feu télégraphiés sur et autour du héros ;
  // chaque cercle laisse ensuite une FLAQUE brûlante persistante (dégâts par tick, à
  // l'intérieur seulement). Contre-jeu : sortir des cercles, la rattraper (elle est lente et
  // fragile) ; la tuer ou l'étourdir pendant le télégraphe ANNULE ses cercles.
  pyromancer: {
    name: 'Pyromancienne', radius: 14, hp: 30, speed: 125, mass: 1, damage: 12,
    preferredDist: 320, fleeDist: 210, approachSlack: 60, castRange: 560, strafeMult: 0.6, strafeFlip: 0.01,
    castTime: 0.4, // bâton levé (lisible sur elle) avant que les cercles n'apparaissent
    recover: 0.55, cooldown: 3.4, cooldownJitter: [0.85, 1.25],
    pyre: {
      count: 3, // 1 cercle sur le héros + 2 autour
      radius: 64,
      spread: 130, // distance des cercles satellites au héros
      delay: 1.0, // télégraphe du 1er cercle (s) — jamais raccourci
      stagger: 0.2, // les satellites s'allument ensuite, un par un
      linger: 3.2, // durée de la flaque brûlante (s)
      tickEvery: 0.5, // un tick de brûlure toutes les 0,5 s…
      tickDamage: 4, // … seulement si le héros est DANS la flaque
      wallInset: 0.5, // centre d'un cercle à au moins 0,5 rayon du mur
    },
    gold: [2, 4],
  },
  // INVOCATEUR : fuit le héros, canalise visiblement (alerte violette inoffensive), puis ouvre
  // des cercles d'invocation (queueSpawn) d'où sortent des diablotins. Plafond d'invocations
  // vivantes ; peu de PV ; cible prioritaire. Le tuer ou l'étourdir pendant la canalisation
  // l'annule (aucun cercle ne s'ouvre).
  necromancer: {
    name: 'Nécromancien', radius: 15, hp: 26, speed: 118, mass: 1, damage: 0,
    preferredDist: 380, fleeDist: 250, approachSlack: 60, fleeSpeedMult: 1.15, strafeMult: 0.5, strafeFlip: 0.01,
    channel: 1.2, // canalisation visible (s)
    channelRadius: 58, // rayon de l'alerte inoffensive dessinée autour de lui
    recover: 0.5, cooldown: 5, cooldownJitter: [0.9, 1.2],
    minionKind: 'imp', count: 2,
    maxMinions: 4, // invocations VIVANTES (et en attente) qu'il peut entretenir
    summonMinR: 40, summonMaxR: 130, summonMinPlayerDist: 160,
    gold: [2, 5],
  },
};

export const EXTRA_ROSTER = [
  // Introduction progressive dans la 1re section de 18 étages : la zone à l'étage 5,
  // l'invocateur à l'étage 8 (l'étage 9 est la halte marchand / autel).
  { kind: 'pyromancer', cost: 2, minIndex: 5, weight: 2 },
  { kind: 'necromancer', cost: 2.5, minIndex: 8, weight: 1.5 },
];

export const EXTRA_ELITE_KINDS = ['pyromancer'];

#!/usr/bin/env node
// upstream_fixtures.mjs — artefacts amont de RÉFÉRENCE et leurs variantes DÉGRADÉES.
//
// Double usage assumé, et c'est la raison d'être du fichier :
//   1. les suites de test s'en servent comme entrée connue-bonne ;
//   2. le protocole d'expérience s'en sert de CONTRÔLE DÉGRADÉ — un comparateur
//      qui ne distingue pas une référence d'une version tronquée ne mesure rien,
//      et un oracle qui accepte tout ne classe personne. Sans contrôle, un vert
//      n'est pas une information.
//
// Les fixtures décrivent un clicker minimal (thème Cookie Clicker, le jeu retenu
// pour l'expérience contrôlée). Elles ne prétendent pas être une bonne conception
// de jeu : elles sont COHÉRENTES d'un artefact à l'autre, ce qui est la seule
// propriété dont les oracles de couverture ont besoin.
//
// Chaque constructeur rend un objet NEUF (structuredClone) : une fixture mutée par
// un test ne doit jamais contaminer le test suivant.

const clone = (o) => structuredClone(o);

const URL_WIKI = 'https://cookieclicker.fandom.com/wiki/Building';
const URL_ARTICLE = 'https://www.gamedeveloper.com/design/the-cow-clicker-story';
const URL_VIDEO = 'https://www.youtube.com/watch?v=exemple-clicker';

const _worldscan = {
  advisory: true,
  games: [
    {
      game: 'Cookie Clicker',
      sources: [
        { url: URL_WIKI, type: 'wiki' },
        { url: URL_ARTICLE, type: 'article' },
        { url: URL_VIDEO, type: 'video', timestamp: '00:04:12' },
      ],
      loops: {
        minute_1: 'Le joueur clique le cookie et voit le compteur monter.',
        minute_10: 'Le joueur achete son premier batiment producteur.',
        hour_5: 'La production passive depasse largement le clic manuel.',
        endgame: 'Le joueur optimise des paliers de production de plus en plus grands.',
      },
      objectives: [
        {
          mode: 'solo',
          has_win_state: false,
          victory_condition: null,
          has_defeat_state: false,
          defeat_condition: null,
          player_goal: 'Maximiser la production cumulee, sans etat gagne ni perdu.',
        },
      ],
      retention_answer: 'La courbe de production exponentielle et les paliers d achat relancent en permanence un objectif proche.',
    },
    {
      game: 'Adventure Capitalist',
      sources: [
        { url: 'https://adventurecapitalist.fandom.com/wiki/Businesses', type: 'wiki' },
        { url: 'https://www.pocketgamer.com/adventure-capitalist/review/', type: 'article' },
        { url: 'https://www.youtube.com/watch?v=exemple-adcap', type: 'video', timestamp: '00:01:30' },
      ],
      loops: {
        minute_1: 'Le joueur lance manuellement une premiere activite.',
        minute_10: 'Le joueur achete un manager qui automatise l activite.',
        hour_5: 'Toutes les activites tournent seules, le joueur arbitre les investissements.',
        endgame: 'Le joueur relance une partie pour un multiplicateur permanent.',
      },
      objectives: [
        {
          mode: 'solo',
          has_win_state: false,
          victory_condition: null,
          has_defeat_state: false,
          defeat_condition: null,
          player_goal: 'Automatiser toute production puis relancer pour un bonus permanent.',
        },
      ],
      retention_answer: 'L automatisation transforme l effort en revenu passif, ce qui rend chaque retour au jeu payant.',
    },
  ],
};

const _prisme = {
  schema_version: 1,
  game_id: 'cookie_clicker',
  exigences: [
    {
      id: 'ex.clic',
      source: 'EXPECTED',
      source_role: 'joueur',
      reference: URL_WIKI,
      observation: 'Dans les clickers observes, le clic manuel incremente un compteur visible immediatement.',
      claim: 'Le clic manuel est la seule source de progression accessible a la premiere seconde de jeu.',
      enonce: 'Un clic sur le cookie incremente le compteur de production d une unite au moins.',
      expected_proof: {
        kind: 'bot_action',
        statement: 'Un bot clique une fois : le compteur affiche vaut exactement la valeur precedente + gain_par_clic.',
      },
      destination: 's3-decompo',
    },
    {
      id: 'ex.production',
      source: 'EXPECTED',
      source_role: 'game_designer',
      reference: URL_VIDEO,
      observation: 'La production passive continue quand le joueur ne clique pas.',
      claim: 'La progression doit exister en l absence totale d entree joueur.',
      enonce: 'La production passive s applique a intervalle fixe, independamment du clic.',
      expected_proof: {
        kind: 'oracle',
        statement: 'Sans aucune entree pendant N ticks, le compteur croit de N * production_par_tick.',
      },
      destination: 's3-decompo',
    },
    {
      id: 'ex.achat',
      source: 'EXPECTED',
      source_role: 'back',
      reference: URL_ARTICLE,
      observation: 'L achat d un batiment consomme la monnaie et augmente la production.',
      claim: 'L achat est un echange : il retire une ressource et modifie un taux.',
      enonce: 'Un achat n est possible que si le solde couvre le prix, et il augmente la production passive.',
      expected_proof: {
        kind: 'bot_action',
        statement: 'Achat avec solde insuffisant refuse et solde inchange ; achat avec solde suffisant debite et augmente production_par_tick.',
      },
      destination: 's3-decompo',
    },
    {
      id: 'ex.progression',
      source: 'ADDITIONS',
      source_role: 'front',
      reference: null,
      observation: 'Aucune source observee ne montre le compteur pendant une pause de jeu.',
      claim: 'La lisibilite permanente de l etat n est attestee par aucune source : c est une proposition, pas une observation.',
      enonce: 'Le compteur reste lisible a l ecran a tout instant, y compris pendant un achat.',
      expected_proof: {
        kind: 'visual',
        statement: 'Capture pendant un achat : la zone du compteur est non vide et affiche la valeur courante.',
      },
      destination: 's5-wiremap',
    },
  ],
};

const _featuremap = {
  schema_version: 1,
  game_id: 'cookie_clicker',
  systemes: [
    {
      id: 'game_state',
      features: [
        {
          id: 'feat.cookie',
          capacites: [
            {
              id: 'cap.clic.increment',
              capacite: 'Incrementer le compteur au clic selon gain_par_clic.',
              source_ref: 'ex.clic',
              expected_proof: {
                kind: 'bot_action',
                statement: 'Un clic : compteur += gain_par_clic, aucune autre variable modifiee.',
              },
            },
            {
              id: 'cap.production.tick',
              capacite: 'Appliquer la production passive a chaque tick fixe.',
              source_ref: 'ex.production',
              expected_proof: {
                kind: 'oracle',
                statement: 'N ticks sans entree : compteur += N * production_par_tick.',
              },
            },
          ],
        },
      ],
    },
    {
      id: 'interaction',
      features: [
        {
          id: 'feat.batiments',
          capacites: [
            {
              id: 'cap.achat.batiment',
              capacite: 'Acheter un batiment si le solde couvre le prix, puis augmenter la production.',
              source_ref: 'ex.achat',
              expected_proof: {
                kind: 'bot_action',
                statement: 'Solde insuffisant : refus, etat inchange. Solde suffisant : debit + production_par_tick augmentee.',
              },
            },
          ],
        },
      ],
    },
    {
      id: 'presentation',
      features: [
        {
          id: 'feat.hud',
          capacites: [
            {
              id: 'cap.hud.compteur',
              capacite: 'Afficher en permanence la valeur courante du compteur.',
              source_ref: 'ex.progression',
              expected_proof: {
                kind: 'visual',
                statement: 'Capture a tout instant : zone compteur non vide, valeur egale a l etat.',
              },
            },
          ],
        },
      ],
    },
  ],
};

const _blueprint = {
  modules: ['game_state', 'interaction', 'presentation'],
  deps_interdites: [
    ['presentation', 'interaction'],
    ['game_state', 'presentation'],
  ],
  responsabilites: [
    {
      module: 'game_state',
      responsabilite: 'Detient le compteur, le gain par clic et la production par tick. Seul ecrivain de l etat.',
      couvre: ['feat.cookie'],
      dependances: [],
      preuve_attendue: {
        kind: 'oracle',
        statement: 'Toute mutation du compteur passe par une fonction de game_state (aucun autre module ne l ecrit).',
      },
    },
    {
      module: 'interaction',
      responsabilite: 'Traduit les entrees joueur (clic, achat) en transitions demandees a game_state.',
      couvre: ['feat.batiments'],
      dependances: ['game_state'],
      preuve_attendue: {
        kind: 'bot_action',
        statement: 'Un achat refuse ne laisse aucune trace dans l etat.',
      },
    },
    {
      module: 'presentation',
      responsabilite: 'Lit l etat et le rend a l ecran. N ecrit jamais l etat.',
      couvre: ['feat.hud'],
      dependances: ['game_state'],
      preuve_attendue: {
        kind: 'visual',
        statement: 'Capture : la valeur affichee egale la valeur de l etat au meme instant.',
      },
    },
  ],
};

const _wiremap = {
  schema_version: 2,
  game_id: 'cookie_clicker',
  systems: [
    { id: 'game_state', category: 'system', allowed_deps: [] },
    { id: 'interaction', category: 'system', allowed_deps: ['game_state'] },
    { id: 'presentation', category: 'system.adapter', allowed_deps: ['game_state'] },
  ],
  lines: [
    {
      id: 'core.clic',
      source: 'EXPECTED',
      source_role: 'joueur',
      reference: URL_WIKI,
      couvre: ['cap.clic.increment'],
      system_parent: 'game_state',
      state: 'REQUIRED',
      expected_proof: { kind: 'bot_action', statement: 'Un clic incremente le compteur de gain_par_clic.' },
    },
    {
      id: 'core.tick',
      source: 'EXPECTED',
      source_role: 'game_designer',
      reference: URL_VIDEO,
      couvre: ['cap.production.tick'],
      system_parent: 'game_state',
      state: 'REQUIRED',
      expected_proof: { kind: 'oracle', statement: 'N ticks sans entree incrementent de N * production_par_tick.' },
    },
    {
      id: 'core.achat',
      source: 'EXPECTED',
      source_role: 'back',
      reference: URL_ARTICLE,
      couvre: ['cap.achat.batiment'],
      system_parent: 'interaction',
      state: 'REQUIRED',
      expected_proof: { kind: 'bot_action', statement: 'Achat refuse si solde insuffisant, etat inchange.' },
    },
    {
      id: 'core.hud',
      source: 'ADDITIONS',
      source_role: 'front',
      reference: null,
      couvre: ['cap.hud.compteur'],
      system_parent: 'presentation',
      state: 'REQUIRED',
      expected_proof: { kind: 'visual', statement: 'Zone compteur non vide a tout instant.' },
    },
  ],
};

export const worldscanReference = () => clone(_worldscan);
export const prismeReference = () => clone(_prisme);
export const featuremapReference = () => clone(_featuremap);
export const blueprintReference = () => clone(_blueprint);
export const wiremapReference = () => clone(_wiremap);

// --- variantes dégradées (contrôles) --------------------------------------------

/**
 * Prisme TRONQUÉ : ne garde que la première exigence. Contrôle de perte — un
 * comparateur qui ne voit pas 3 LOSS ici ne mesure pas la perte.
 * @returns {object}
 */
export function prismeTronque() {
  const d = clone(_prisme);
  d.exigences = d.exigences.slice(0, 1);
  return d;
}

/**
 * Prisme SANS PREUVE ATTENDUE : la chaîne s'arrête au maillon 2. Contrôle
 * d'actionnabilité — structurellement conforme, mais non routable.
 * @returns {object}
 */
export function prismeSansPreuve() {
  const d = clone(_prisme);
  d.exigences.forEach((e) => { delete e.expected_proof; });
  return d;
}

/**
 * Prisme SANS PROVENANCE : les EXPECTED n'ont plus de `reference`. Contrôle de
 * traçabilité — et cas d'alignement où la similarité de texte doit prendre le relais.
 * @returns {object}
 */
export function prismeSansProvenance() {
  const d = clone(_prisme);
  d.exigences.forEach((e) => {
    if (e.source === 'EXPECTED') delete e.reference;
  });
  return d;
}

/**
 * Prisme USURPANT LA PROVENANCE CORE : une sortie de modèle ne peut pas revendiquer
 * CORE (origine `core_list` par construction, règle mesurée le 2026-08-03).
 * @returns {object}
 */
export function prismeSourceCore() {
  const d = clone(_prisme);
  d.exigences[0].source = 'CORE';
  return d;
}

/**
 * Featuremap dont une feuille cite une exigence INEXISTANTE : invention non
 * déclarée. Contrôle de non-invention.
 * @returns {object}
 */
export function featuremapInventee() {
  const d = clone(_featuremap);
  d.systemes[0].features[0].capacites[0].source_ref = 'ex.inexistante';
  return d;
}

/**
 * Featuremap AMPUTÉE d'un système : une exigence du Prisme n'est plus portée.
 * Contrôle de couverture.
 * @returns {object}
 */
export function featuremapAmputee() {
  const d = clone(_featuremap);
  d.systemes = d.systemes.slice(0, 2);
  return d;
}

/**
 * LE blueprint historique : 82 octets, 2 modules inventés, aucune responsabilité.
 * Il passait 34 runs sur 34 avec check_architecture (appelé avant build, sur un
 * src vide). C'est le contrôle négatif de référence du chantier.
 * @returns {object}
 */
export function blueprintVacant() {
  return { modules: ['gen', 'spawn'], deps_interdites: [['gen', 'spawn']] };
}

/**
 * Blueprint qui déclare une dépendance qu'il interdit lui-même.
 * @returns {object}
 */
export function blueprintContradictoire() {
  const d = clone(_blueprint);
  d.responsabilites[2].dependances = ['interaction'];
  return d;
}

/**
 * Blueprint avec un cycle game_state -> interaction -> game_state.
 * @returns {object}
 */
export function blueprintCyclique() {
  const d = clone(_blueprint);
  d.responsabilites[0].dependances = ['interaction'];
  return d;
}

/**
 * WireMap dont les lignes ne déclarent aucun `couvre` : le delta plan/carte devient
 * incalculable, ce qui est exactement l'état d'avant ce chantier.
 * @returns {object}
 */
export function wiremapSansCouvre() {
  const d = clone(_wiremap);
  d.lines.forEach((l) => { delete l.couvre; });
  return d;
}

/**
 * WireMap amputée d'une ligne : une capacité du plan n'est portée par rien.
 * @returns {object}
 */
export function wiremapAmputee() {
  const d = clone(_wiremap);
  d.lines = d.lines.slice(0, 3);
  return d;
}

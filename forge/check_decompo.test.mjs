// Tests de l'oracle s3-decompo (featuremap vs prisme).
// node --test forge/check_decompo.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { resolve, dirname } from 'node:path';
import { existsSync } from 'node:fs';
import { checkDecompoDoc, granularite, greyBlocks, checkGreyBlockCoverage } from './check_decompo.mjs';
import {
  prismeReference, featuremapReference, featuremapInventee, featuremapAmputee,
} from './upstream_fixtures.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(__dirname, '..');

/**
 * Resout la premiere paire {featuremap, prisme} existante parmi une liste de
 * repertoires candidats (archive datee en priorite, run courant en secours).
 * Retourne null si aucun n'existe (skip propre plutot qu'un chemin invente).
 * @param {string[]} dirs
 * @returns {{featuremapPath:string, prismePath:string}|null}
 */
function resoudreFixtureRun(dirs) {
  for (const dir of dirs) {
    const featuremapPath = resolve(dir, 'featuremap.json');
    const prismePath = resolve(dir, 'prisme.json');
    if (existsSync(featuremapPath) && existsSync(prismePath)) {
      return { featuremapPath, prismePath };
    }
  }
  return null;
}

test('VALIDITE: l oracle ACCEPTE la featuremap de reference', () => {
  const r = checkDecompoDoc(featuremapReference(), prismeReference());
  assert.deepEqual(r.problems, []);
  assert.deepEqual(r.exigences_non_couvertes, []);
  assert.deepEqual(r.feuilles_non_sourcees, []);
  assert.equal(r.verdict, 'OK');
  assert.equal(r.stats.feuilles, 4);
  assert.equal(r.stats.exigences_couvertes, 4);
  assert.equal(r.stats.exigences_prisme, 4);
});

test('COUVERTURE: une exigence non portee par une feuille est une omission signalee', () => {
  const r = checkDecompoDoc(featuremapAmputee(), prismeReference());
  assert.equal(r.verdict, 'FAIL');
  assert.equal(r.exigences_non_couvertes.length, 1);
  assert.match(r.exigences_non_couvertes[0], /ex\.progression/);
  assert.equal(r.stats.exigences_couvertes, 3);
});

test('NON-INVENTION: une feuille citant une exigence inexistante est refusee', () => {
  const r = checkDecompoDoc(featuremapInventee(), prismeReference());
  assert.equal(r.verdict, 'FAIL');
  assert.equal(r.feuilles_non_sourcees.length, 1);
  assert.match(r.feuilles_non_sourcees[0], /invention non declaree/);
  // et l'exigence orpheline remonte aussi en couverture
  assert.ok(r.exigences_non_couvertes.some((p) => /ex\.clic/.test(p)));
});

test('COMPLETUDE: une feuille sans preuve attendue ou sans capacite est refusee', () => {
  const d = featuremapReference();
  delete d.systemes[0].features[0].capacites[0].expected_proof;
  assert.equal(checkDecompoDoc(d, prismeReference()).verdict, 'FAIL');
  const d2 = featuremapReference();
  d2.systemes[0].features[0].capacites[0].capacite = '';
  assert.ok(checkDecompoDoc(d2, prismeReference()).problems.some((p) => /capacite: absent ou vide/.test(p)));
});

test('une featuremap vide ou absurde est refusee (pas de vert vacant)', () => {
  assert.equal(checkDecompoDoc({}, prismeReference()).verdict, 'FAIL');
  assert.equal(checkDecompoDoc({ game_id: 'x', systemes: [] }, prismeReference()).verdict, 'FAIL');
  assert.equal(checkDecompoDoc('texte libre', prismeReference()).verdict, 'FAIL');
});

test('sans Prisme, l oracle REFUSE au lieu de sauter la verification en silence', () => {
  const r = checkDecompoDoc(featuremapReference(), null);
  assert.equal(r.verdict, 'FAIL');
  assert.ok(r.problems.some((p) => /ni sautees en silence/.test(p)));
});

test('GRANULARITE: mesuree et reportee, jamais gatee (regle de variance)', () => {
  const d = featuremapReference();
  assert.deepEqual(granularite(d), { min: 1, max: 2 });
  // une granularite extreme reste OK : l'oracle la REPORTE, il ne la juge pas
  d.systemes[1].features[0].capacites.push({
    id: 'cap.achat.lot',
    capacite: 'Acheter dix batiments d un coup.',
    source_ref: 'ex.achat',
    expected_proof: { kind: 'bot_action', statement: 'Achat x10 debite dix fois le prix unitaire courant.' },
  });
  const r = checkDecompoDoc(d, prismeReference());
  assert.equal(r.verdict, 'OK');
  assert.equal(r.stats.feuilles_par_feature_max, 2);
  assert.equal(r.stats.feuilles, 5);
});

// --- V4 GAME LOOP (2026-08-22) : une action joueur = une capacite d'ENTREE reelle -

/** Prisme de reference dont 'ex.clic' porte acteur PLAYER + affordance. */
function prismeAvecActionJoueur() {
  const d = prismeReference();
  const ex = d.exigences.find((e) => e.id === 'ex.clic');
  ex.acteur = 'PLAYER';
  ex.affordance = 'pelote';
  return d;
}

test('BOUCLE: action joueur (acteur PLAYER + affordance) portee par bot_action depuis main.tscn -> OK', () => {
  const prisme = prismeAvecActionJoueur();
  const fm = featuremapReference();
  const leaf = fm.systemes[0].features[0].capacites[0]; // cap.clic.increment, source_ref ex.clic
  leaf.expected_proof = {
    kind: 'bot_action',
    statement: 'Un bot clique la cible pelote depuis main.tscn : compteur += gain_par_clic.',
  };
  const r = checkDecompoDoc(fm, prisme);
  assert.equal(r.verdict, 'OK');
  assert.deepEqual(r.boucle_sans_entree, []);
  assert.equal(r.stats.actions_joueur, 1);
  assert.equal(r.stats.actions_joueur_prouvees_depuis_scene, 1);
});

test('BOUCLE: action joueur realisee par une feuille visual (pas bot_action) -> finding + FAIL', () => {
  const prisme = prismeAvecActionJoueur();
  const fm = featuremapReference();
  const leaf = fm.systemes[0].features[0].capacites[0];
  leaf.expected_proof = {
    kind: 'visual',
    statement: 'Capture : la zone pelote change de couleur au clic.',
  };
  const r = checkDecompoDoc(fm, prisme);
  assert.equal(r.verdict, 'FAIL');
  assert.equal(r.boucle_sans_entree.length, 1);
  assert.match(r.boucle_sans_entree[0], /cap\.clic\.increment/);
  assert.match(r.boucle_sans_entree[0], /pelote/);
  assert.match(r.boucle_sans_entree[0], /ex\.clic/);
  assert.equal(r.stats.actions_joueur, 1);
  assert.equal(r.stats.actions_joueur_prouvees_depuis_scene, 0);
});

test('BOUCLE: feuille bot_action dont le statement ne mentionne pas main.tscn -> finding', () => {
  const prisme = prismeAvecActionJoueur();
  const fm = featuremapReference();
  const leaf = fm.systemes[0].features[0].capacites[0];
  leaf.expected_proof = {
    kind: 'bot_action',
    statement: 'Un bot clique la cible pelote : compteur += gain_par_clic.',
  };
  const r = checkDecompoDoc(fm, prisme);
  assert.equal(r.verdict, 'FAIL');
  assert.equal(r.boucle_sans_entree.length, 1);
  assert.match(r.boucle_sans_entree[0], /sans preuve bot_action depuis main\.tscn/);
  assert.equal(r.stats.actions_joueur_prouvees_depuis_scene, 0);
});

test('BOUCLE: exigence acteur SYSTEM n impose aucune contrainte de boucle', () => {
  const d = prismeReference();
  const ex = d.exigences.find((e) => e.id === 'ex.clic');
  ex.acteur = 'SYSTEM';
  // pas d'affordance : la feuille garde sa preuve existante (bot_action, sans main.tscn)
  const r = checkDecompoDoc(featuremapReference(), d);
  assert.equal(r.verdict, 'OK');
  assert.deepEqual(r.boucle_sans_entree, []);
  assert.equal(r.stats.actions_joueur, 0);
});

test('BOUCLE: fixture REELLE run 6 (0 exigence PLAYER) -> actions_joueur=0, verdict inchange (OK)', (t) => {
  const fixture = resoudreFixtureRun([
    resolve(REPO_ROOT, 'EVIDENCE', 'runs', 'kitten_clicker', '_run6_20260821f'),
  ]);
  if (!fixture) {
    t.skip('archive run 6 (_run6_20260821f/) absente — fixture non reancree, skip propre');
    return;
  }
  const fm = JSON.parse(readFileSync(fixture.featuremapPath, 'utf-8'));
  const prisme = JSON.parse(readFileSync(fixture.prismePath, 'utf-8'));
  assert.equal(prisme.exigences.filter((e) => e.acteur === 'PLAYER').length, 0,
    'diagnostic du lot V4 : le run 6 ne porte aucune exigence PLAYER');
  const r = checkDecompoDoc(fm, prisme);
  assert.equal(r.verdict, 'OK');
  assert.deepEqual(r.boucle_sans_entree, []);
  assert.equal(r.stats.actions_joueur, 0);
  assert.equal(r.stats.actions_joueur_prouvees_depuis_scene, 0);
});

test('BOUCLE: fixture REELLE run 7 (8 actions joueur) -> boucle fermee, verdict OK', (t) => {
  const fixture = resoudreFixtureRun([
    resolve(REPO_ROOT, 'EVIDENCE', 'runs', 'kitten_clicker', '_run7_20260821g'),
    resolve(REPO_ROOT, 'EVIDENCE', 'runs', 'kitten_clicker'),
  ]);
  if (!fixture) {
    t.skip('run 7 introuvable (ni _run7_20260821g/ ni le run courant) — skip propre');
    return;
  }
  const fm = JSON.parse(readFileSync(fixture.featuremapPath, 'utf-8'));
  const prisme = JSON.parse(readFileSync(fixture.prismePath, 'utf-8'));
  const r = checkDecompoDoc(fm, prisme);
  assert.equal(r.verdict, 'OK');
  assert.deepEqual(r.boucle_sans_entree, []);
  assert.equal(r.stats.actions_joueur, 8);
  assert.equal(r.stats.actions_joueur_prouvees_depuis_scene, 8);
});

test('un id de capacite duplique est refuse', () => {
  const d = featuremapReference();
  d.systemes[1].features[0].capacites[0].id = 'cap.clic.increment';
  assert.ok(checkDecompoDoc(d, prismeReference()).problems.some((p) => /id duplique/.test(p)));
});

// --- V4 GAME LOOP — maillons F/G/H/I/J (2026-08-22, GO Pierre) -----------------

/** Exigence Prisme minimale valide, surchargeable. */
function exigence(over) {
  return {
    id: over.id,
    source: 'ADDITIONS',
    source_role: 'test',
    reference: null,
    observation: `observation ${over.id}`,
    claim: `claim ${over.id}`,
    enonce: `enonce ${over.id}`,
    expected_proof: { kind: 'bot_action', statement: 'stmt' },
    destination: 's3-decompo',
    ...over,
  };
}

/** Featuremap minimale a une feuille, surchargeable. */
function featuremapUneFeuille(leafOver) {
  return {
    game_id: 'g',
    systemes: [{
      id: 'sys',
      features: [{
        id: 'feat',
        capacites: [{
          id: leafOver.id,
          capacite: `capacite ${leafOver.id}`,
          source_ref: leafOver.source_ref,
          expected_proof: leafOver.expected_proof,
        }],
      }],
    }],
  };
}

test('F/I MAILLON: UNLOCK et META_LOOP suivent la regle existante boucle_sans_entree (entree obligatoire)', () => {
  const prisme = {
    game_id: 'g',
    exigences: [
      exigence({
        id: 'ex.f1', loop_role: 'UNLOCK', acteur: 'PLAYER', affordance: 'acheter_chaton',
      }),
      exigence({
        id: 'ex.i1', loop_role: 'META_LOOP', acteur: 'PLAYER', affordance: 'prestige',
      }),
    ],
  };
  const fm = {
    game_id: 'g',
    systemes: [{
      id: 'sys',
      features: [{
        id: 'feat',
        capacites: [
          {
            id: 'cap.f1', capacite: 'c', source_ref: 'ex.f1',
            expected_proof: { kind: 'bot_action', statement: 'Un bot achete depuis main.tscn.' },
          },
          {
            id: 'cap.i1', capacite: 'c', source_ref: 'ex.i1',
            expected_proof: { kind: 'bot_action', statement: 'Un bot prestige depuis main.tscn.' },
          },
        ],
      }],
    }],
  };
  const r = checkDecompoDoc(fm, prisme);
  assert.equal(r.verdict, 'OK');
  assert.deepEqual(r.boucle_sans_entree, []);
  assert.equal(r.stats.maillons_couverts.F, 1);
  assert.equal(r.stats.maillons_couverts.I, 1);
});

test('F MAILLON: UNLOCK sans preuve bot_action depuis main.tscn -> boucle_sans_entree, F non compte', () => {
  const prisme = {
    game_id: 'g',
    exigences: [exigence({
      id: 'ex.f1', loop_role: 'UNLOCK', acteur: 'PLAYER', affordance: 'acheter_chaton',
    })],
  };
  const fm = featuremapUneFeuille({
    id: 'cap.f1', source_ref: 'ex.f1', expected_proof: { kind: 'visual', statement: 'capture achat' },
  });
  const r = checkDecompoDoc(fm, prisme);
  assert.equal(r.verdict, 'FAIL');
  assert.equal(r.boucle_sans_entree.length, 1);
  assert.equal(r.stats.maillons_couverts.F, 0);
});

test('G MAILLON: NEXT_GOAL avec feuille d effet (file_write|visual) sourcee -> OK, compte G', () => {
  const prisme = {
    game_id: 'g',
    exigences: [exigence({ id: 'ex.g1', loop_role: 'NEXT_GOAL' })],
  };
  const fm = featuremapUneFeuille({
    id: 'cap.g1', source_ref: 'ex.g1', expected_proof: { kind: 'visual', statement: 'objectif change de texte' },
  });
  const r = checkDecompoDoc(fm, prisme);
  assert.equal(r.verdict, 'OK');
  assert.equal(r.stats.maillons_couverts.G, 1);
});

test('G MAILLON: NEXT_GOAL sans feuille d effet (seulement bot_action) -> boucle_sans_effet, FAIL', () => {
  const prisme = {
    game_id: 'g',
    exigences: [exigence({ id: 'ex.g1', loop_role: 'NEXT_GOAL' })],
  };
  const fm = featuremapUneFeuille({
    id: 'cap.g1', source_ref: 'ex.g1', expected_proof: { kind: 'bot_action', statement: 'stmt' },
  });
  const r = checkDecompoDoc(fm, prisme);
  assert.equal(r.verdict, 'FAIL');
  assert.equal(r.boucle_sans_effet.length, 1);
  assert.match(r.boucle_sans_effet[0], /ex\.g1/);
  assert.equal(r.stats.maillons_couverts.G, 0);
});

test('H MAILLON: REPEAT est un rejeux (aucune feuille propre), replay ciblant une exigence couverte -> OK', () => {
  const prisme = {
    game_id: 'g',
    exigences: [
      exigence({
        id: 'ex.b1', loop_role: 'PLAYER_ACTION', acteur: 'PLAYER', affordance: 'pelote',
      }),
      exigence({ id: 'ex.h1', loop_role: 'REPEAT', replay: ['ex.b1'] }),
    ],
  };
  const fm = featuremapUneFeuille({
    id: 'cap.b1',
    source_ref: 'ex.b1',
    expected_proof: { kind: 'bot_action', statement: 'Un bot clique pelote depuis main.tscn.' },
  });
  const r = checkDecompoDoc(fm, prisme);
  assert.equal(r.verdict, 'OK');
  assert.deepEqual(r.boucle_replay_non_couvert, []);
  // ex.h1 n'a pas de feuille propre et n'est PAS une omission :
  assert.deepEqual(r.exigences_non_couvertes, []);
  assert.equal(r.stats.maillons_couverts.H, 1);
});

test('H MAILLON: REPEAT dont une ref de replay ne resout aucune exigence -> boucle_replay_non_couvert, FAIL', () => {
  const prisme = {
    game_id: 'g',
    exigences: [
      exigence({
        id: 'ex.b1', loop_role: 'PLAYER_ACTION', acteur: 'PLAYER', affordance: 'pelote',
      }),
      exigence({ id: 'ex.h1', loop_role: 'REPEAT', replay: ['ex.inexistante'] }),
    ],
  };
  const fm = featuremapUneFeuille({
    id: 'cap.b1',
    source_ref: 'ex.b1',
    expected_proof: { kind: 'bot_action', statement: 'Un bot clique pelote depuis main.tscn.' },
  });
  const r = checkDecompoDoc(fm, prisme);
  assert.equal(r.verdict, 'FAIL');
  assert.equal(r.boucle_replay_non_couvert.length, 1);
  assert.match(r.boucle_replay_non_couvert[0], /ex\.h1/);
  assert.equal(r.stats.maillons_couverts.H, 0);
});

test('J MAILLON: ADVANTAGE est un rejeux, replay_ref ciblant une exigence couverte -> OK', () => {
  const prisme = {
    game_id: 'g',
    exigences: [
      exigence({
        id: 'ex.b1', loop_role: 'PLAYER_ACTION', acteur: 'PLAYER', affordance: 'pelote',
      }),
      exigence({
        id: 'ex.j1', loop_role: 'ADVANTAGE', replay_ref: 'ex.b1',
      }),
    ],
  };
  const fm = featuremapUneFeuille({
    id: 'cap.b1',
    source_ref: 'ex.b1',
    expected_proof: { kind: 'bot_action', statement: 'Un bot clique pelote depuis main.tscn.' },
  });
  const r = checkDecompoDoc(fm, prisme);
  assert.equal(r.verdict, 'OK');
  assert.deepEqual(r.boucle_replay_non_couvert, []);
  assert.deepEqual(r.exigences_non_couvertes, []);
  assert.equal(r.stats.maillons_couverts.J, 1);
});

test('J MAILLON: ADVANTAGE dont replay_ref cible une exigence non couverte -> boucle_replay_non_couvert, FAIL', () => {
  const prisme = {
    game_id: 'g',
    exigences: [
      exigence({
        id: 'ex.b1', loop_role: 'PLAYER_ACTION', acteur: 'PLAYER', affordance: 'pelote',
      }),
      exigence({
        id: 'ex.j1', loop_role: 'ADVANTAGE', replay_ref: 'ex.b1',
      }),
    ],
  };
  // ex.b1 existe dans le Prisme mais n'est portee par AUCUNE feuille : non couverte.
  const fm = {
    game_id: 'g',
    systemes: [{
      id: 'sys',
      features: [{
        id: 'feat',
        capacites: [{
          id: 'cap.autre',
          capacite: 'c',
          source_ref: 'ex.j1',
          expected_proof: { kind: 'bot_action', statement: 'sans rapport' },
        }],
      }],
    }],
  };
  const r = checkDecompoDoc(fm, prisme);
  assert.equal(r.verdict, 'FAIL');
  assert.equal(r.boucle_replay_non_couvert.length, 1);
  assert.match(r.boucle_replay_non_couvert[0], /ex\.j1/);
  assert.match(r.boucle_replay_non_couvert[0], /ex\.b1/);
  assert.equal(r.stats.maillons_couverts.J, 0);
});

test('MAILLONS: stats.maillons_couverts par defaut a zero quand aucun role F/G/H/I/J present', () => {
  const r = checkDecompoDoc(featuremapReference(), prismeReference());
  assert.deepEqual(r.stats.maillons_couverts, {
    F: 0, G: 0, H: 0, I: 0, J: 0,
  });
});

// --- Lot B, T3 (2026-08-23) : couverture des grey_blocks[] du Game Master ------

test('grey blocks: sans --gm (gm=null), 0 grey block, comportement inchange', () => {
  const r = checkDecompoDoc(featuremapReference(), prismeReference(), null);
  assert.equal(r.verdict, 'OK');
  assert.equal(r.stats.grey_blocks, 0);
  assert.equal(r.stats.grey_blocks_couverts, 0);
  assert.deepEqual(r.grey_blocks_non_decomposes, []);
});

test('grey blocks: gm SANS bloc game_master, 0 grey block, comportement inchange', () => {
  const gm = { genre: 'clicker/idle', games_observed: [], dimensions: [] };
  const r = checkDecompoDoc(featuremapReference(), prismeReference(), gm);
  assert.equal(r.verdict, 'OK');
  assert.equal(r.stats.grey_blocks, 0);
});

test('greyBlocks(): extrait les ids valides, ignore les entrees mal formees', () => {
  const gm = {
    game_master: {
      grey_blocks: [
        { id: 'garden', type: 'LOCATION' },
        { type: 'ACTOR' }, // sans id -> ignore
        'texte', // pas un objet -> ignore
        { id: 'shop' },
      ],
    },
  };
  assert.deepEqual(greyBlocks(gm).map((b) => b.id), ['garden', 'shop']);
});

test('grey blocks: id porte par une feuille (leaf.id) -> couvert', () => {
  const fm = featuremapReference();
  const firstLeaf = fm.systemes[0].features[0].capacites[0];
  const gm = { game_master: { grey_blocks: [{ id: firstLeaf.id }] } };
  const r = checkGreyBlockCoverage(fm, gm);
  assert.equal(r.grey_blocks, 1);
  assert.equal(r.grey_blocks_couverts, 1);
  assert.deepEqual(r.findings, []);
});

test('grey blocks: id porte par source_ref d une feuille -> couvert', () => {
  const fm = featuremapReference();
  const firstLeaf = fm.systemes[0].features[0].capacites[0];
  const gm = { game_master: { grey_blocks: [{ id: firstLeaf.source_ref }] } };
  const r = checkGreyBlockCoverage(fm, gm);
  assert.equal(r.grey_blocks_couverts, 1);
});

test('grey blocks: id absent de toute feuille -> finding grey_block_non_decompose, FAIL', () => {
  const gm = { game_master: { grey_blocks: [{ id: 'jamais_decompose' }] } };
  const r = checkDecompoDoc(featuremapReference(), prismeReference(), gm);
  assert.equal(r.verdict, 'FAIL');
  assert.equal(r.stats.grey_blocks, 1);
  assert.equal(r.stats.grey_blocks_couverts, 0);
  assert.equal(r.grey_blocks_non_decomposes.length, 1);
  assert.match(r.grey_blocks_non_decomposes[0], /jamais_decompose/);
  assert.match(r.grey_blocks_non_decomposes[0], /grey_block_non_decompose/);
});

test('grey blocks: mesure reelle run 9 -- gm_worldscan sans game_master -> 0 grey block', () => {
  const gmPath = resolve(REPO_ROOT, 'EVIDENCE/runs/kitten_clicker/_run9_20260823a/gm_worldscan.json');
  if (!existsSync(gmPath)) return; // fixture absente sur ce poste, pas une assertion sur du vide
  const gm = JSON.parse(readFileSync(gmPath, 'utf-8'));
  assert.equal(greyBlocks(gm).length, 0, 'baseline mesuree run 9 : pas de bloc game_master');
});

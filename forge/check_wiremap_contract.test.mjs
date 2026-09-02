// Tests de l'oracle d'AVANT-BUILD de la WireMap (couverture du plan).
// node --test forge/check_wiremap_contract.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { resolve, dirname } from 'node:path';
import { checkWiremapContractDoc, extraireLignes } from './check_wiremap_contract.mjs';
import {
  wiremapReference, featuremapReference, wiremapSansCouvre, wiremapAmputee,
} from './upstream_fixtures.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(__dirname, '..');

test('VALIDITE: l oracle ACCEPTE la wiremap de reference', () => {
  const r = checkWiremapContractDoc(wiremapReference(), featuremapReference());
  assert.deepEqual(r.problems, []);
  assert.deepEqual(r.capacites_non_couvertes, []);
  assert.deepEqual(r.couverture_fantome, []);
  assert.equal(r.verdict, 'OK');
  assert.equal(r.stats.schema, 'v2');
  assert.equal(r.stats.lignes, 4);
  assert.equal(r.stats.capacites_couvertes, 4);
});

test('DISCRIMINATION: une wiremap sans `couvre` ne rend le delta plan/carte calculable par personne', () => {
  const r = checkWiremapContractDoc(wiremapSansCouvre(), featuremapReference());
  assert.equal(r.verdict, 'FAIL');
  assert.equal(r.stats.lignes_sans_couvre, 4);
  assert.equal(r.capacites_non_couvertes.length, 4);
});

test('COUVERTURE: une capacite du plan portee par aucune ligne est signalee', () => {
  const r = checkWiremapContractDoc(wiremapAmputee(), featuremapReference());
  assert.equal(r.verdict, 'FAIL');
  assert.equal(r.capacites_non_couvertes.length, 1);
  assert.match(r.capacites_non_couvertes[0], /cap\.hud\.compteur/);
});

test('COUVERTURE FANTOME: un couvre qui ne resout aucune capacite est signale', () => {
  const d = wiremapReference();
  d.lines[0].couvre = ['cap.inexistante'];
  const r = checkWiremapContractDoc(d, featuremapReference());
  assert.equal(r.couverture_fantome.length, 1);
  assert.equal(r.verdict, 'FAIL');
});

test('le schema v1 (features[]) est accepte comme le v2 (lines[])', () => {
  const v1 = {
    features: [
      { feature: 'clic', couvre: ['cap.clic.increment'] },
      { feature: 'tick', couvre: ['cap.production.tick'] },
      { feature: 'achat', couvre: ['cap.achat.batiment'] },
      { feature: 'hud', couvre: ['cap.hud.compteur'] },
    ],
  };
  const r = checkWiremapContractDoc(v1, featuremapReference());
  assert.equal(r.stats.schema, 'v1');
  assert.equal(r.verdict, 'OK');
  assert.deepEqual(extraireLignes(v1).schema, 'v1');
  assert.deepEqual(extraireLignes({}).schema, 'inconnu');
});

test('une wiremap absurde ou vide est refusee (pas de vert vacant)', () => {
  assert.equal(checkWiremapContractDoc({}, featuremapReference()).verdict, 'FAIL');
  assert.equal(checkWiremapContractDoc({ lines: [] }, featuremapReference()).verdict, 'FAIL');
  assert.equal(checkWiremapContractDoc('texte libre', featuremapReference()).verdict, 'FAIL');
});

test('une featuremap sans capacite rend la couverture inverifiable, et l oracle le dit', () => {
  const r = checkWiremapContractDoc(wiremapReference(), { game_id: 'x', systemes: [] });
  assert.equal(r.verdict, 'FAIL');
  assert.ok(r.problems.some((p) => /ni sautee en silence/.test(p)));
});

// Périmètre : ce que cet oracle NE fait PAS (sinon deux vérités concurrentes).
test('PERIMETRE: les regles d etat de ligne restent a check_line_states', () => {
  const d = wiremapReference();
  d.lines[0].state = 'ETAT_INVENTE';       // du ressort de check_line_states
  d.lines[0].source_role = '';             // idem
  const r = checkWiremapContractDoc(d, featuremapReference());
  assert.equal(r.verdict, 'OK'); // la COUVERTURE, elle, reste intacte
  assert.deepEqual(r.problems, []);
});

test('MAILLON: une wiremap sans ligne affordance ne declenche aucun finding, stats a zero', () => {
  const r = checkWiremapContractDoc(wiremapReference(), featuremapReference());
  assert.deepEqual(r.maillon_non_lie, []);
  assert.equal(r.stats.affordances, 0);
  assert.equal(r.stats.affordances_liees, 0);
});

// --- V4 GAME LOOP — liaison affordance -> input -> systeme -> effet (2026-08-22) -

/** Featuremap a deux feuilles d'une meme exigence : une ENTREE, une EFFET. */
function featuremapEntreeEffet() {
  return {
    game_id: 'g',
    systemes: [{
      id: 'sys',
      features: [{
        id: 'feat',
        capacites: [
          {
            id: 'cap.entry.pelote', capacite: 'entree', source_ref: 'ex.b1',
            expected_proof: { kind: 'bot_action', statement: 'Un bot clique pelote depuis main.tscn.' },
          },
          {
            id: 'cap.effect.pelote', capacite: 'effet', source_ref: 'ex.b1',
            expected_proof: { kind: 'visual', statement: 'Le hud ronrons augmente.' },
          },
          {
            id: 'cap.effect.autre', capacite: 'effet autre exigence', source_ref: 'ex.autre',
            expected_proof: { kind: 'visual', statement: 'Sans rapport.' },
          },
        ],
      }],
    }],
  };
}

test('MAILLON: affordance -> requires -> systeme dont couvre porte l effet de la MEME exigence -> lie, pas de finding', () => {
  const fm = featuremapEntreeEffet();
  const wm = {
    schema_version: 2,
    game_id: 'g',
    lines: [
      {
        id: 'input.pelote', provides: ['affordance:pelote'], requires: ['game.state'],
        couvre: ['cap.entry.pelote'],
      },
      {
        id: 'core.state', provides: ['game.state'], requires: [],
        couvre: ['cap.effect.pelote'],
      },
      { id: 'core.autre', provides: [], requires: [], couvre: ['cap.effect.autre'] },
    ],
  };
  const r = checkWiremapContractDoc(wm, fm);
  assert.deepEqual(r.maillon_non_lie, []);
  assert.equal(r.verdict, 'OK');
  assert.equal(r.stats.affordances, 1);
  assert.equal(r.stats.affordances_liees, 1);
});

test('MAILLON: affordance avec requires VIDE -> maillon_non_lie, FAIL', () => {
  const fm = featuremapEntreeEffet();
  const wm = {
    schema_version: 2,
    game_id: 'g',
    lines: [
      { id: 'input.pelote', provides: ['affordance:pelote'], requires: [], couvre: ['cap.entry.pelote'] },
      { id: 'core.state', provides: ['game.state'], requires: [], couvre: ['cap.effect.pelote'] },
    ],
  };
  const r = checkWiremapContractDoc(wm, fm);
  assert.equal(r.verdict, 'FAIL');
  assert.equal(r.maillon_non_lie.length, 1);
  assert.match(r.maillon_non_lie[0], /pelote/);
  assert.equal(r.stats.affordances, 1);
  assert.equal(r.stats.affordances_liees, 0);
});

test('MAILLON: requires cite une capacite que personne ne `provides` -> maillon_non_lie, FAIL', () => {
  const fm = featuremapEntreeEffet();
  const wm = {
    schema_version: 2,
    game_id: 'g',
    lines: [
      {
        id: 'input.pelote', provides: ['affordance:pelote'], requires: ['game.fantome'],
        couvre: ['cap.entry.pelote'],
      },
      { id: 'core.state', provides: ['game.state'], requires: [], couvre: ['cap.effect.pelote'] },
    ],
  };
  const r = checkWiremapContractDoc(wm, fm);
  assert.equal(r.verdict, 'FAIL');
  assert.equal(r.maillon_non_lie.length, 1);
  assert.equal(r.stats.affordances_liees, 0);
});

test('MAILLON: la ligne resolue couvre un effet d une AUTRE exigence -> maillon_non_lie, FAIL', () => {
  const fm = featuremapEntreeEffet();
  const wm = {
    schema_version: 2,
    game_id: 'g',
    lines: [
      {
        id: 'input.pelote', provides: ['affordance:pelote'], requires: ['game.state'],
        couvre: ['cap.entry.pelote'],
      },
      { id: 'core.state', provides: ['game.state'], requires: [], couvre: ['cap.effect.autre'] },
    ],
  };
  const r = checkWiremapContractDoc(wm, fm);
  assert.equal(r.verdict, 'FAIL');
  assert.equal(r.maillon_non_lie.length, 1);
  assert.equal(r.stats.affordances_liees, 0);
});

test('MAILLON: la ligne resolue couvre une feuille d ENTREE (pas d effet) -> maillon_non_lie, FAIL', () => {
  const fm = featuremapEntreeEffet();
  const wm = {
    schema_version: 2,
    game_id: 'g',
    lines: [
      {
        id: 'input.pelote', provides: ['affordance:pelote'], requires: ['game.state'],
        couvre: ['cap.entry.pelote'],
      },
      { id: 'core.state', provides: ['game.state'], requires: [], couvre: ['cap.entry.pelote'] },
    ],
  };
  const r = checkWiremapContractDoc(wm, fm);
  assert.equal(r.verdict, 'FAIL');
  assert.equal(r.maillon_non_lie.length, 1);
});

test('MAILLON: liaison transitive profondeur 2 (adaptateur intermediaire) -> lie', () => {
  const fm = featuremapEntreeEffet();
  const wm = {
    schema_version: 2,
    game_id: 'g',
    lines: [
      {
        id: 'input.pelote', provides: ['affordance:pelote'], requires: ['adapter.click'],
        couvre: ['cap.entry.pelote'],
      },
      {
        id: 'adapter.click', provides: ['adapter.click'], requires: ['game.state'], couvre: ['cap.effect.autre'],
      },
      { id: 'core.state', provides: ['game.state'], requires: [], couvre: ['cap.effect.pelote'] },
    ],
  };
  const r = checkWiremapContractDoc(wm, fm);
  assert.deepEqual(r.maillon_non_lie, []);
  assert.equal(r.verdict, 'OK');
  assert.equal(r.stats.affordances_liees, 1);
});

test('MAILLON: mesure sur la WireMap REELLE du run 7 (kitten_clicker) — rapportee, non inventee', (t) => {
  const wmPath = resolve(REPO_ROOT, 'EVIDENCE', 'runs', 'kitten_clicker', 'wiremap.json');
  const fmPath = resolve(REPO_ROOT, 'EVIDENCE', 'runs', 'kitten_clicker', 'featuremap.json');
  if (!existsSync(wmPath) || !existsSync(fmPath)) {
    t.skip('run 7 (kitten_clicker) introuvable — skip propre');
    return;
  }
  const wm = JSON.parse(readFileSync(wmPath, 'utf-8'));
  const fm = JSON.parse(readFileSync(fmPath, 'utf-8'));
  const r = checkWiremapContractDoc(wm, fm);
  const inputLines = wm.lines.filter((l) => Array.isArray(l.provides)
    && l.provides.some((p) => p.startsWith('affordance:')));
  assert.equal(inputLines.length, 4, 'diagnostic : 4 lignes input.* portent une affordance dans le run 7');
  assert.equal(r.stats.affordances, 4);
  // MESURE, pas une valeur inventee : au run 7 aucune ligne affordance ne porte
  // de `requires` (cf. wiremap.json), donc 0 sur 4 sont liees par ce nouveau
  // controle de resolution d'ids.
  assert.equal(r.stats.affordances_liees, 0);
});

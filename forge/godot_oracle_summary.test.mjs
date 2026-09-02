// REÇU STRUCTURÉ de `godot_oracle` (GO Pierre 2026-08-18) — frontière 2.
//
// DEFAUT MESURE. Le recu de solvabilite (`trials`, `won`, `lost`, `failed_seeds`, `verdict`,
// et depuis 1a64359 les `diagnostics`) est imprime par `solvability_godot.mjs` sur stdout,
// puis RELAYE tel quel par `runSolvabilityGate` via `stdio: 'inherit'`. `godot_oracle` ne
// voit donc JAMAIS ce JSON — il ne recupere que `res.status`. Cote Python, `oracle.run_oracle`
// capture tout le flux dans `evidence/oracle_<jeu>.log`, EXCLU par `.gitignore:81`, et le
// driver ne conserve que `returncode` + `evidence_path`.
//
// Consequence mesuree : `won: 0/50` de tetris et le `gagne: true, kills_du_bot: 0` de
// bomberman_3d n'existent QUE sur le poste. Le depot conserve des verdicts sans les mesures
// qui les fondent — il ne permet pas de re-instruire ses propres decisions.
//
// CE LOT NE FERME QUE LA PREMIERE MOITIE : rendre le recu DISPONIBLE et EMIS sous une forme
// machine. Le cabler jusqu'au `state.json` cote Python est un lot DISTINCT — il touche la
// forme du `detail` signe, et la lecon de e48801c s'y applique.
//
// `stdio: 'inherit'` -> `'pipe'` EST LE VRAI CHANGEMENT, et il a un prix : la sortie de
// l'enfant cesse de s'afficher EN CONTINU pour n'apparaitre qu'a la fin. On la re-imprime
// donc integralement — un operateur qui lisait ce flux doit continuer de le lire.
import assert from 'node:assert/strict';
import test from 'node:test';

import { parseSolvabilityReceipt, SUMMARY_PREFIX, buildSummaryLine } from './godot_oracle.mjs';

const RECU = JSON.stringify({
  project: 'GAMES/tetris', trials: 50, won: 50, lost: 0,
  failed_seeds: [], verdict: 'OK',
}, null, 2);

// --- extraction du recu depuis une sortie BRUITEE ---------------------------------------

test('le recu est extrait au milieu du bruit du moteur', () => {
  const out = ['Godot Engine v4.6.3', '[godot_oracle] === solvability ===', RECU, ''].join('\n');
  const r = parseSolvabilityReceipt(out);
  assert.equal(r.verdict, 'OK');
  assert.equal(r.won, 50);
  assert.deepEqual(r.failed_seeds, []);
});

test('les DIAGNOSTICS survivent a l extraction', () => {
  // Ce que 1a64359 a rendu disponible ne doit pas se perdre a la frontiere suivante.
  const avecDiag = JSON.stringify({
    trials: 1, won: 0, lost: 1, failed_seeds: [1], verdict: 'FAIL',
    diagnostics: [{ seed: 1, diag: { gagne: true, kills_du_bot: 0 } }],
  });
  const r = parseSolvabilityReceipt(['bruit', avecDiag].join('\n'));
  assert.equal(r.diagnostics[0].diag.kills_du_bot, 0);
});

test('une sortie SANS recu rend null, jamais une exception', () => {
  // Best-effort strict : le recu structure est un GAIN, jamais une condition. Un oracle qui
  // tourne sans emettre de JSON ne doit pas devenir un echec de parsing.
  assert.equal(parseSolvabilityReceipt('Godot Engine\n[godot_oracle] OK\n'), null);
  assert.equal(parseSolvabilityReceipt(''), null);
  assert.equal(parseSolvabilityReceipt(null), null);
});

test('un JSON ILLISIBLE rend null, jamais une exception', () => {
  assert.equal(parseSolvabilityReceipt('{ceci nest pas du json'), null);
});

test('le DERNIER recu gagne si plusieurs sont presents', () => {
  // Un run peut relancer la solvabilite ; c'est le dernier etat qui fait foi.
  const a = JSON.stringify({ verdict: 'FAIL', won: 0 });
  const b = JSON.stringify({ verdict: 'OK', won: 3 });
  assert.equal(parseSolvabilityReceipt([a, 'bruit', b].join('\n')).verdict, 'OK');
});

test('un JSON qui n est PAS un recu de solvabilite est IGNORE', () => {
  // Discrimination : sans elle, n importe quel objet imprime par le moteur passerait pour
  // un recu et le driver conserverait du bruit dans un detail signe.
  assert.equal(parseSolvabilityReceipt('{"autre": 1}'), null);
  assert.equal(parseSolvabilityReceipt('[1,2,3]'), null);
});

// --- la ligne de resume, destinee au consommateur Python ----------------------------------

test('la ligne de resume porte un PREFIXE stable et un JSON sur UNE ligne', () => {
  // Meme convention que `FORGE_ORACLE`/`FORGE_TRIAL`/`FORGE_DIAG` : un prefixe, un JSON,
  // une ligne — un consommateur peut l extraire d un flux bruite sans le parser entier.
  const l = buildSummaryLine({ mecanique: true, solvabilite: JSON.parse(RECU) });
  assert.ok(l.startsWith(SUMMARY_PREFIX));
  assert.equal(l.split('\n').length, 1, 'le JSON doit tenir sur UNE ligne');
  const d = JSON.parse(l.slice(SUMMARY_PREFIX.length));
  assert.equal(d.mecanique, true);
  assert.equal(d.solvabilite.verdict, 'OK');
});

test('le resume reste EMIS quand la solvabilite n a pas produit de recu', () => {
  // `null` explicite plutot qu absence de ligne : « je n ai rien recu » est une information,
  // et un consommateur qui ne trouve aucune ligne ne peut pas la distinguer d un oracle
  // qui n aurait pas tourne.
  const d = JSON.parse(buildSummaryLine({ mecanique: false, solvabilite: null })
                       .slice(SUMMARY_PREFIX.length));
  assert.equal(d.mecanique, false);
  assert.equal(d.solvabilite, null);
});

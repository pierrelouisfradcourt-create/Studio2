// Cablage du signal « budget de solvabilite » dans l'auto-audit (GO Pierre 2026-08-17).
//
// Ce fichier teste le PONT, pas la detection : la logique vit en Python
// (`forge/solvability_budget_audit.py`, 9 tests) parce qu'aucun parseur YAML n'existe cote
// Node dans ce depot — meme contrainte, meme solution que `auditContractSync`.
//
// TESTS CONDITIONNELS, et la raison compte. Le pont spawn un interpreteur trouve par
// `pythonCandidates`, qui cherche `.venv312` — NON VERSIONNE. Sur une copie isolee
// (`git archive HEAD`, protocole de validation prospective de ce depot), aucun venv n'existe :
// le pont retombe sur `python` nu, echoue, et rend `non_evaluable`. C'est son comportement
// DEGRADE PREVU, pas un defaut. Une premiere redaction assertait `status === 'ok'` sans
// condition : 4 tests rouges sur la copie isolee, verts sur le depot — un test qui depend de
// l'ENVIRONNEMENT et non du CODE. Meme piege que `test_sur_l_artefact_REEL_tetris`
// (commit 4e3223c), corrige de la meme facon : on saute avec un MOTIF NOMME.
// Mieux vaut un saut nomme qu'un rouge d'environnement.
import assert from 'node:assert/strict';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

import { auditSolvabilityBudget, runSelfAudit } from './studio_selfaudit.mjs';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..');

/** Le pont est-il exploitable ICI ? (venv present) */
function pontDisponible() {
  return auditSolvabilityBudget(REPO).status === 'ok';
}

const SAUT = { skip: 'pont Python indisponible (pas de .venv312 — copie isolee)' };

test('le statut est TOUJOURS l un des deux prevus, jamais une exception', () => {
  // Vrai dans TOUS les environnements : c'est l'invariant de robustesse du pont.
  const r = auditSolvabilityBudget(REPO);
  assert.ok(['ok', 'non_evaluable'].includes(r.status), `statut inattendu : ${r.status}`);
  assert.ok(Array.isArray(r.anomalies), 'anomalies doit rester un tableau, meme degrade');
  if (r.status === 'non_evaluable') assert.ok(r.detail, 'un non_evaluable doit dire POURQUOI');
});

test('DEPOT REEL : AUCUN contrat n est ignore', (t) => {
  if (!pontDisponible()) return t.skip(SAUT.skip);
  // ETAT DU PARC INVERSE LE 2026-08-19, et le commentaire d'origine l'avait prevu :
  // « si ce test rougit AVEC le pont disponible, c'est que le PARC a change ». Il a change.
  //
  // La redaction du 2026-08-17 exigeait `['tetris']` — tetris etait alors le seul contrat
  // dont le budget divergeait d'`oracles.json`. `1c0eb95` (2026-08-18) a ALIGNE ce contrat :
  // `max_ticks 500`, `trials 50`, `trial_timeout_ms 10000` des deux cotes. L'assertion est
  // donc devenue une exigence de DEFAUT — elle rougissait parce que le defaut avait ete
  // corrige. Elle est INVERSEE plutot que supprimee : « aucune divergence » est desormais
  // l'etat ratifie, et ce test rougira si quelqu'un en reintroduit une.
  const { anomalies } = auditSolvabilityBudget(REPO);
  const ignores = anomalies.filter((a) => a.etat === 'CONTRAT_IGNORE').map((a) => a.jeu).sort();
  assert.deepEqual(ignores, [], `divergence contrat/oracles.json reapparue : ${ignores}`);
});

test('le rapport porte EXACTEMENT ce que le detecteur a produit', (t) => {
  if (!pontDisponible()) return t.skip(SAUT.skip);
  // Un detecteur qu'aucun rapport ne porte serait un « producteur sans consommateur ».
  //
  // La redaction d'origine prouvait le transport en cherchant une anomalie NOMMEE
  // (`some(a => a.jeu === 'tetris')`) : elle liait un test de PONT a l'etat du PARC, et
  // devenait donc invalide des que le parc etait assaini — un test qui exige un defaut
  // pour prouver un cablage. L'egalite au detecteur prouve le MEME transport sans rien
  // exiger du parc : elle tient parc propre ou non, et rougit si le pont se coupe.
  const attendu = auditSolvabilityBudget(REPO);
  const r = runSelfAudit(REPO);
  assert.ok(r.solvabilityBudget, 'le rapport ne porte pas le signal');
  assert.deepEqual(r.solvabilityBudget.anomalies, attendu.anomalies,
                   'le rapport a filtre ou altere ce que le detecteur a rendu');
  assert.equal(r.solvabilityBudget.status, attendu.status);
});

test('une anomalie NON VIDE traverse jusqu au rapport', () => {
  // PREUVE POSITIVE, et elle ne saute JAMAIS — aucun pont Python, donc aucune dependance a
  // l'environnement ni au parc. Le test precedent compare deux resultats qui peuvent tous
  // deux etre vides : parc propre, il ne distingue plus « transporte » de « rend vide ».
  // Celui-ci injecte une anomalie SYNTHETIQUE via le point d'injection de `runSelfAudit`
  // (deps, 2026-08-17) et exige de la retrouver INTACTE dans le rapport.
  //
  // C'est ce que la redaction d'origine cherchait en exigeant `tetris` — mais en le
  // demandant au PARC au lieu de le fabriquer. Un test de transport doit apporter sa
  // propre charge, jamais compter sur un defaut de production pour exister.
  const sonde = { status: 'ok', anomalies: [{ jeu: '_sonde', etat: 'CONTRAT_IGNORE' }] };
  const r = runSelfAudit(REPO, { solvabilityBudget: () => sonde });
  assert.deepEqual(r.solvabilityBudget.anomalies, sonde.anomalies,
                   'le rapport n a pas transporte l anomalie injectee');
});

test('le signal n entre PAS dans `ok` — il rapporte, il ne ratifie pas', () => {
  // Vrai dans TOUS les environnements : `ok` est la conjonction des TROIS signaux durs,
  // que le pont ait abouti ou non. Meme regime que `registryDivergences` — la promotion
  // en gate dur serait une decision Pierre, pas un cablage.
  const r = runSelfAudit(REPO);
  const attendu = r.docDrift.length === 0
    && r.dormancy.filter((d) => d.status === 'dormant').length === 0
    && r.contractSync.status === 'ok';
  assert.equal(r.ok, attendu, '`ok` doit rester la conjonction des TROIS signaux durs');
});

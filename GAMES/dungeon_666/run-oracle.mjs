#!/usr/bin/env node
// Harnais d'oracles de Dungeon 666 — même forme que les jeux web du studio
// (GAMES/v2_breakout_slice/run-oracle.mjs).
//
//   (a) règles         tests/logic, feel_review       une règle, un test (dash, combo, i-frames, 666…)
//   (b) propriétés     tests/properties*              déterminisme et invariants sur longues parties
//   (c) audio          tests/audio                    sons procéduraux sans erreur, polyphonie bornée
//   (d) V2             tests/v2_*.test.mjs            boucle Ville → Gardien → checkpoint, labo, contenu
//                      (tout fichier v2_* présent est pris : les lots fusionnés y ajoutent les leurs)
//   (e) fichier unique tools/bundle.mjs               dist/dungeon_666.html se construit
//   (f) solvabilité    solvability.mjs                un bot bat la section 1 (18 étages) ; le dash compte
//   (g) e2e            e2e.mjs                        navigateur réel, doigts tactiles, clavier, clics
//   (h) mesures        tools/playtest.mjs             rapport de feel des bots, labo D5/D8/D9 (non bloquants)
//
// Les tests vivent sous tests/ : surface protégée du studio (forge/test_surfaces.yaml) — les
// créer est permis, les modifier après coup demande une gate Pierre.
//
// ÉCHECS CONNUS : douze tests d'avant la V2 encodaient l'ancienne structure (Gardien tous les 6
// étages, build figé au checkpoint, « Réessayer le Gardien »). S'ils échouent, ils sont rapportés
// en clair comme « en conflit avec la spec V2 — gate Pierre requise » : ni masqués, ni sautés, et
// la suite reste ROUGE. Toute AUTRE défaillance est une RÉGRESSION.
// État au 2026-10-01 : gate accordée par Pierre, les douze réécrits a minima (commit f8dc9ad,
// 01_DESIGN/GATE_TESTS_V2.md) ; leurs anciens noms n'existent donc plus, sauf retour en arrière.
//
// Code de sortie : 0 tout est vert ; 2 seuls des conflits connus sont rouges ; 1 régression ou
// volet bloquant rouge.
//
// Usage : node run-oracle.mjs

import { spawn } from 'node:child_process';
import { readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const GAME_DIR = dirname(fileURLToPath(import.meta.url));
const GATE_DOC = '01_DESIGN/GATE_TESTS_V2.md';

// Les douze tests en conflit avec la spec V2 (noms d'origine, avant la gate).
const KNOWN_V2_CONFLICTS = [
  ['feel_review', 'anneau du Gardien : le cercle d\'alerte reste affiché entre les vagues'],
  ['feel_review', 'invocation du Gardien : alerte marquée inoffensive (le rouge reste « ça fait mal »)'],
  ['feel_review', 'gel d\'impact sur le Gardien : plafonné par le tuning, le finisher pèse plus qu\'un coup léger'],
  ['logic', '666 étages : 111 sections de 6, Gardien au 6e étage de chaque section'],
  ['logic', 'portes : l\'étage 5 mène au Gardien, l\'antichambre propose marchand ou autel'],
  ['logic', 'checkpoint : vaincre un Gardien fige le build ; mourir ensuite le restaure'],
  ['logic', 'Gardien vaincu : ses impacts en attente et ses orbes en vol ne blessent plus'],
  ['logic', 'réessayer le Gardien : retour à l\'entrée de sa salle avec le build d\'entrée'],
  ['logic', 'relance de l\'appli au checkpoint : même build que la reprise après une mort'],
  ['properties_strict', '(k) invariants stricts (cercles entiers, murs, obstacles, PV) — sections complètes du bot skilled'],
  ['properties_strict', '(k bis) invariants stricts — entrées aléatoires, départ dans chaque type de salle (étages 2 à 6)'],
  ['properties_strict', '(l) le run qui bat la section 1 a réellement tué le boss (l\'oracle ne passe pas sur une salle vide)'],
];
const KNOWN_NAMES = new Set(KNOWN_V2_CONFLICTS.map(([, name]) => name));

/** Fichiers de tests présents, rangés par volet (un fichier inconnu va dans « autres »). */
function testGroups() {
  const files = readdirSync(join(GAME_DIR, 'tests')).filter((f) => f.endsWith('.test.mjs')).sort();
  const groups = [
    { label: 'règles (tests unitaires)', match: (f) => f === 'logic.test.mjs' || f === 'feel_review.test.mjs' },
    { label: 'propriétés', match: (f) => f.startsWith('properties') },
    { label: 'audio', match: (f) => f === 'audio.test.mjs' },
    { label: 'V2 (boucle, labo, contenu)', match: (f) => f.startsWith('v2_') },
  ];
  const taken = new Set();
  const out = [];
  for (const g of groups) {
    const mine = files.filter((f) => g.match(f) && !taken.has(f));
    mine.forEach((f) => taken.add(f));
    if (mine.length) out.push({ label: g.label, files: mine });
  }
  const rest = files.filter((f) => !taken.has(f));
  if (rest.length) out.push({ label: 'autres tests', files: rest });
  return out;
}

function run(argv, capture = false) {
  return new Promise((accept) => {
    const child = spawn(argv[0], argv.slice(1), { cwd: GAME_DIR, stdio: capture ? ['ignore', 'pipe', 'inherit'] : 'inherit' });
    let out = '';
    if (capture) child.stdout.on('data', (chunk) => { out += chunk; });
    child.on('close', (code) => accept({ code, out }));
    child.on('error', () => accept({ code: 127, out }));
  });
}

/**
 * Lit la sortie TAP de node --test : tests de premier niveau, réussis ou non, avec le message
 * d'erreur des échecs. Le fichier d'un test est retrouvé par le chemin de son « location ».
 */
export function parseTap(out) {
  const tests = [];
  let cur = null;
  let inError = false;
  for (const line of out.split('\n')) {
    const m = /^(not ok|ok) \d+ - (.*)$/.exec(line);
    if (m) {
      cur = { ok: m[1] === 'ok', name: m[2].replace(/ # (SKIP|TODO).*$/, ''), file: '', error: [] };
      tests.push(cur);
      inError = false;
      continue;
    }
    if (!cur || cur.ok) continue;
    const loc = /^ {2}location: '.*\/tests\/([^/]+)\.test\.mjs:/.exec(line);
    if (loc) cur.file = loc[1];
    if (/^ {2}error: /.test(line)) {
      inError = true;
      const rest = line.replace(/^ {2}error: (\|-)?\s*/, '').replace(/^'|'$/g, '');
      if (rest) cur.error.push(rest);
      continue;
    }
    if (inError && /^ {4}/.test(line)) {
      if (line.trim() && cur.error.length < 4) cur.error.push(line.trim());
      continue;
    }
    inError = false;
  }
  return tests;
}

async function testStep(group) {
  const argv = ['node', '--test', '--test-reporter=tap', ...group.files.map((f) => `tests/${f}`)];
  const { code, out } = await run(argv, true);
  const tests = parseTap(out);
  const failed = tests.filter((t) => !t.ok);
  console.log(`  ${tests.length - failed.length}/${tests.length} tests réussis (${group.files.join(', ')})`);
  for (const t of failed) {
    const known = KNOWN_NAMES.has(t.name);
    console.log(`  ${known ? 'CONFLIT CONNU (spec V2, gate Pierre requise)' : 'RÉGRESSION'} — ${t.file ? `${t.file} · ` : ''}« ${t.name} »`);
    for (const e of t.error.filter(Boolean)) console.log(`      ${e}`);
  }
  // Sortie non nulle sans échec lisible (fichier qui ne se charge pas…) : régression aussi.
  const unexplained = code !== 0 && failed.length === 0;
  if (unexplained) console.log(`  RÉGRESSION — node --test sort en code ${code} sans test en échec lisible (import cassé ?)`);
  return { tests, failed, unexplained };
}

const OTHER_STEPS = [
  { label: 'fichier unique jouable', argv: ['node', 'tools/bundle.mjs'], gating: true },
  { label: 'solvabilité (un bot bat la section 1 de 18 étages)', argv: ['node', 'solvability.mjs', '20'], gating: true },
  { label: 'e2e navigateur réel', argv: ['node', 'e2e.mjs'], gating: true },
  { label: 'rapport de playtest des bots', argv: ['node', 'tools/playtest.mjs', '--seeds', '20'], gating: false },
  { label: 'labo D5/D8/D9 : mesure comparée (reports/lab.md)', argv: ['node', 'tools/playtest.mjs', '--lab-report', '--seeds', '20'], gating: false },
];

async function main() {
  console.log('=== Dungeon 666 — suite d\'oracles ===\n');
  const groups = testGroups();
  const total = groups.length + OTHER_STEPS.length;
  const regressions = [];
  const conflicts = [];
  const seen = new Set();
  let i = 0;
  for (const g of groups) {
    console.log(`[${++i}/${total}] ${g.label}...`);
    const r = await testStep(g);
    for (const t of r.tests) seen.add(t.name);
    for (const t of r.failed) (KNOWN_NAMES.has(t.name) ? conflicts : regressions).push(`${t.file || g.label} · ${t.name}`);
    if (r.unexplained) regressions.push(`${g.label} (sortie non nulle)`);
    console.log(r.failed.length || r.unexplained ? `ROUGE — ${g.label}\n` : `OK — ${g.label}\n`);
  }
  const gatingRed = [];
  for (const step of OTHER_STEPS) {
    console.log(`[${++i}/${total}] ${step.label}${step.gating ? '' : ' (mesure, non bloquant)'}...`);
    const { code } = await run(step.argv);
    if (code === 0) console.log(`OK — ${step.label}\n`);
    else if (step.gating) {
      gatingRed.push(`${step.label} (code ${code})`);
      console.error(`ECHEC — ${step.label} (code ${code})\n`);
    } else console.warn(`MESURE NON ABOUTIE — ${step.label} (code ${code}) — ne bloque pas\n`);
  }

  console.log('=== fin de la suite ===');
  const present = KNOWN_V2_CONFLICTS.filter(([, n]) => seen.has(n)).length;
  console.log(`les 12 tests en conflit avec la spec V2 : ${conflicts.length} en échec sous leur nom d'origine, ${present - conflicts.length} verts sous leur nom d'origine, ${KNOWN_V2_CONFLICTS.length - present} renommés ou remplacés — gate Pierre du 2026-10-01 appliquée, voir ${GATE_DOC}`);
  for (const c of conflicts) console.log(`  conflit connu — gate Pierre requise : ${c}`);
  if (regressions.length) console.error(`RÉGRESSIONS (${regressions.length}) :\n  ${regressions.join('\n  ')}`);
  if (gatingRed.length) console.error(`volets bloquants rouges : ${gatingRed.join(' | ')}`);
  if (regressions.length || gatingRed.length) {
    console.error('VERDICT : ROUGE — régression ou volet bloquant en échec');
    process.exit(1);
  }
  if (conflicts.length) {
    console.error(`VERDICT : ROUGE — seuls les ${conflicts.length} conflits connus avec la spec V2 échouent (gate Pierre requise) ; aucune autre régression`);
    process.exit(2);
  }
  console.log('VERDICT : VERT — tous les tests et tous les volets bloquants passent');
  process.exit(0);
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) main();

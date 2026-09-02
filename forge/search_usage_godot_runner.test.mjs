// DETECTABILITE DU CABLAGE GODOT (GO Pierre 2026-08-19).
//
// LE DEFAUT N'EST PAS LE VERDICT, C'EST SON EVOLUTIVITE. `reuseRatioCable` n'observe que
// `join(gameDir, 'run-oracle.mjs')`. Or ce fichier est la convention WEB : le cablage d'un
// jeu web vit DANS LE JEU (kb_tactics 4 occurrences, shmup_slice 3), tandis qu'un jeu Godot
// n'a pas de runner propre — son oracle est le script PARTAGE du studio, declare dans
// `oracles.json` : `node forge/godot_oracle.mjs GAMES/<jeu>`.
//
// Consequence mesuree : si `godot_oracle.mjs` cablait `reuse_ratio` demain, l'oracle
// continuerait de repondre « run-oracle.mjs absent / NOT_WIRED ». Ce n'est pas un verdict
// faux aujourd'hui — c'est UN VERDICT QUI NE PEUT PAS CHANGER DEMAIN.
//
// CE QUE CE LOT NE FAIT PAS, ET POURQUOI — deux pistes anterieures FALSIFIEES par leur
// propre cadrage :
//
//   1. ajouter `NOT_APPLICABLE` a `PROOF_STATES`. Le module le refuse PAR ECRIT : « Etats
//      AUTORISES ... exactement trois. Un quatrieme etat serait une facon de ne pas
//      trancher », et cite la lecon `oracle_fail_vs_not_measured_marker`. En outre le
//      verdict Godot est HONNETE : `reuse_ratio.mjs` gere `.gd` et `project.godot`, et
//      `GAMES/tetris` mesure 36 fichiers de logique. La mesure a bien eu lieu.
//   2. faire partir la detection d'`oracles.json`. Mesure : SIX jeux ont un
//      `run-oracle.mjs` et AUCUNE entree dans `oracles.json` (`chase_prototype`,
//      `collect_runner_legacy/_r1/_r2`, `survival_arena_legacy/_r1`). En remplacement,
//      cette piste PERDRAIT leur detection. Le discriminant retenu est `project.godot` —
//      deja utilise par `reuse_ratio.mjs` (`findGodotProjectRoot`), present dans exactement
//      les 4 jeux Godot, absent de `kb_tactics`.
//
// LE MOTIF DU « CABLE » RESTE INTOUCHE. `search_usage.mjs:47` et `static_oracles.py:705`
// declarent « une seule definition du cable » — seul change le FICHIER OU L'ON CHERCHE, pas
// ce qu'on y cherche. Un test ci-dessous verrouille cette egalite, qui n'etait jusqu'ici
// qu'un commentaire.
import assert from 'node:assert/strict';
import test from 'node:test';
import { mkdirSync, writeFileSync, readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { tmpdir } from 'node:os';

import { reuseRatioCable, PROOF_STATES } from './search_usage.mjs';

const ICI = dirname(fileURLToPath(import.meta.url));
let n = 0;
function jeu({ godot = false, runner = null } = {}) {
  const d = join(tmpdir(), `su_godot_${process.pid}_${n++}`);
  mkdirSync(d, { recursive: true });
  if (godot) writeFileSync(join(d, 'project.godot'), '[application]\n', 'utf-8');
  if (runner !== null) writeFileSync(join(d, 'run-oracle.mjs'), runner, 'utf-8');
  return d;
}
const CABLE = 'spawn("node", ["../../knowledge_base/reuse_ratio.mjs"]);\n';

/** Un runner PARTAGE jetable, pour ne pas dependre du vrai `godot_oracle.mjs` : ce test
 *  mesure le PASSAGE par le runner partage, pas l'etat actuel de ce fichier-la. */
function runnerPartage(contenu) {
  const p = join(tmpdir(), `su_shared_${process.pid}_${n++}.mjs`);
  writeFileSync(p, contenu, 'utf-8');
  return p;
}

// --- le cas Godot : la detection ATTEINT le runner partage --------------------------------

test('un jeu Godot sans runner propre cesse de rendre « run-oracle.mjs absent »', () => {
  // LE test du lot. La raison nommait un fichier qui n'est pas le runner du projet — un
  // lecteur en concluait que le jeu etait mal forme, alors que sa topologie est normale.
  const r = reuseRatioCable(jeu({ godot: true }),
                            { runnerPartage: runnerPartage('// rien\n') });
  assert.equal(r.wired, false);
  assert.ok(!/run-oracle\.mjs absent/.test(r.raison),
            `la raison designe encore la convention web : ${r.raison}`);
  assert.match(r.raison, /partag/i, 'la raison doit nommer le runner PARTAGE');
});

test('un jeu Godot dont le runner PARTAGE cable reuse_ratio rend wired=true', () => {
  // Le coeur du defaut : AVANT ce lot, ce cas etait indetectable — le verdict ne pouvait
  // pas changer, quoi que fasse `godot_oracle.mjs`.
  const r = reuseRatioCable(jeu({ godot: true }),
                            { runnerPartage: runnerPartage(CABLE) });
  assert.equal(r.wired, true, 'un cablage reel du runner partage doit etre VU');
  assert.equal(r.raison, null);
});

test('un runner partage INTROUVABLE ne fait pas exploser la detection', () => {
  const r = reuseRatioCable(jeu({ godot: true }),
                            { runnerPartage: join(tmpdir(), 'inexistant_xyz.mjs') });
  assert.equal(r.wired, false);
  assert.ok(r.raison && r.raison.length > 0, 'un refus muet ne se diagnostique pas');
});

test('le cablage en COMMENTAIRE ne compte pas, meme dans le runner partage', () => {
  // Meme exigence que la voie web : `sansCommentaires` doit s'appliquer des deux cotes,
  // sinon le runner partage deviendrait la porte de service du theatre d'oracle.
  const r = reuseRatioCable(jeu({ godot: true }),
                            { runnerPartage: runnerPartage(`// ${CABLE}`) });
  assert.equal(r.wired, false);
});

// --- la voie WEB reste STRICTEMENT inchangee ----------------------------------------------

test('un jeu web cable reste wired=true', () => {
  assert.equal(reuseRatioCable(jeu({ runner: CABLE })).wired, true);
});

test('un jeu web non cable garde SA raison, mot pour mot', () => {
  const r = reuseRatioCable(jeu({ runner: '// rien\n' }));
  assert.equal(r.wired, false);
  assert.equal(r.raison, "run-oracle.mjs n'invoque pas reuse_ratio.mjs");
});

test('un jeu NI web NI Godot garde « run-oracle.mjs absent »', () => {
  // Regression a proteger : SIX jeux reels ont un `run-oracle.mjs` sans entree dans
  // `oracles.json` (`chase_prototype`, `collect_runner_legacy/_r1/_r2`,
  // `survival_arena_legacy/_r1`). La convention par nom de fichier RESTE la voie par
  // defaut — c'est ce qui interdisait de fonder la detection sur `oracles.json`.
  assert.equal(reuseRatioCable(jeu({})).raison, 'run-oracle.mjs absent');
});

test('un jeu Godot QUI POSSEDE AUSSI un run-oracle.mjs privilegie le sien', () => {
  // Topologie hybride : le fichier du jeu est plus specifique que le runner partage du
  // studio. Sans cette regle, un jeu qui declare son propre cablage se le verrait ignorer.
  const r = reuseRatioCable(jeu({ godot: true, runner: CABLE }),
                            { runnerPartage: runnerPartage('// rien\n') });
  assert.equal(r.wired, true);
});

// --- les invariants que ce lot NE DOIT PAS franchir ---------------------------------------

test('PROOF_STATES reste EXACTEMENT trois', () => {
  // « Un quatrieme etat serait une facon de ne pas trancher » — docstring du module.
  assert.deepEqual([...PROOF_STATES], ['MEASURED', 'NOT_WIRED', 'NOT_MEASURED']);
});

test('les DEUX definitions du « cable » restent identiques, JS et Python', () => {
  // `search_usage.mjs:47` annonce reprendre le motif de `static_oracles.py:705` « a
  // l'identique : une seule definition du cable ». C'etait un COMMENTAIRE, pas une garde :
  // rien n'empechait les deux de deriver en silence. Ce lot touche le FICHIER cherche, pas
  // le motif — et attache desormais les deux autorites l'une a l'autre.
  const js = readFileSync(join(ICI, 'search_usage.mjs'), 'utf-8')
    .match(/const REUSE_RATIO_WIRED = \/(.+?)\/;/)[1];
  const py = readFileSync(join(ICI, 'static_oracles.py'), 'utf-8')
    .match(/_REUSE_RATIO_WIRED = re\.compile\(r"(.+?)"\)/)[1];
  assert.equal(js, py, 'les deux motifs ont DIVERGE — l’un des deux juge autre chose');
});

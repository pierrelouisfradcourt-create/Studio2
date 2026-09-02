// check_worldscan.test.mjs — oracle structurel du dossier d'observation World Scan
// (GAME_REFERENCE/). Patron : forge/check_artbible.test.mjs.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile, rm, readFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  REQUIRED_FILES,
  isValidHttpUrl,
  validateSource,
  validateLoops,
  validateConditionState,
  validateObjective,
  validateGameEntry,
  validateManifest,
  checkNoLocalMedia,
  listFilesRecursive,
  checkWorldScan,
  checkWorldScanFile,
  checkFactConsistency,
  checkSourceUrlStability,
} from './check_worldscan.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolveRepoRoot(__dirname);

function resolveRepoRoot(startDir) {
  // forge/check_worldscan.test.mjs -> repo root est deux niveaux au-dessus.
  return join(startDir, '..');
}

function goodSource(overrides = {}) {
  return { url: 'https://example.test/article', type: 'article', ...overrides };
}

function goodLoops(overrides = {}) {
  return {
    minute_1: 'le joueur choisit une unite et un objectif proche',
    minute_10: 'premiere boucle de ressources bouclee, premier arbitrage',
    hour_5: 'build complet, premiere synergie decouverte',
    endgame: 'classement/leaderboard et rejouabilite via seed',
    ...overrides,
  };
}

function goodObjective(overrides = {}) {
  return {
    mode: 'solo',
    has_win_state: true,
    victory_condition: 'eliminer toutes les unites ennemies avant la fin du tour limite',
    has_defeat_state: true,
    defeat_condition: 'toutes les unites du joueur sont detruites ou le batiment central tombe',
    player_goal: 'proteger le maximum de batiments civils sur la carte',
    ...overrides,
  };
}

function marathonObjective(overrides = {}) {
  // Genre sans etat gagne (marathon/score-attack) : l'absence doit etre EXPLICITE,
  // jamais une simple omission de champ.
  return {
    mode: 'solo_marathon',
    has_win_state: false,
    victory_condition: null,
    has_defeat_state: true,
    defeat_condition: 'la pile depasse la zone de spawn (topout)',
    player_goal: 'faire le meilleur score possible avant le topout',
    ...overrides,
  };
}

function goodGame(overrides = {}) {
  return {
    game: 'Into the Breach',
    sources: [
      goodSource({ url: 'https://example.test/a' }),
      goodSource({ url: 'https://example.test/b', type: 'wiki' }),
      goodSource({ url: 'https://example.test/c', type: 'video', timestamp: '00:12:34' }),
    ],
    loops: goodLoops(),
    objectives: [goodObjective()],
    retention_answer: 'le joueur revient pour battre son propre score sur une seed connue',
    ...overrides,
  };
}

function goodManifest(overrides = {}) {
  return {
    games: [goodGame(), goodGame({ game: 'FTL' })],
    advisory: true,
    ...overrides,
  };
}

async function makeValidFolder(dir) {
  await mkdir(dir, { recursive: true });
  await writeFile(join(dir, 'mechanics_analysis.md'), '# Mecaniques\n\nAnalyse suffisamment longue et non triviale des mecaniques observees.', 'utf-8');
  await writeFile(join(dir, 'progression_map.md'), '# Progression\n\nCarte de progression du joueur, paliers et debloquages observes.', 'utf-8');
  await writeFile(join(dir, 'economy_map.md'), '# Economie\n\nRessources, sinks et sources observees dans le jeu de reference.', 'utf-8');
  await writeFile(join(dir, 'ux_flow.md'), '# UX Flow\n\nEcrans traverses, boucle de menu, onboarding observe.', 'utf-8');
  await writeFile(join(dir, 'architecture_guess.md'), '# Architecture (hypothese)\n\nHypothese d architecture technique deduite de l observation externe.', 'utf-8');
  await writeFile(join(dir, 'observation_manifest.json'), JSON.stringify(goodManifest(), null, 2), 'utf-8');
}

// --- helpers unitaires ---

test('isValidHttpUrl : accepte http/https, rejette le reste', () => {
  assert.equal(isValidHttpUrl('https://example.test'), true);
  assert.equal(isValidHttpUrl('http://example.test'), true);
  assert.equal(isValidHttpUrl('ftp://example.test'), false);
  assert.equal(isValidHttpUrl('pas une url'), false);
  assert.equal(isValidHttpUrl(''), false);
  assert.equal(isValidHttpUrl(undefined), false);
});

test('validateSource : source bien formee => aucun finding', () => {
  assert.deepEqual(validateSource(goodSource(), 0, 0), []);
});

test('validateSource : url absente => finding', () => {
  const findings = validateSource({ type: 'article' }, 0, 0);
  assert.ok(findings.some((f) => f.includes('url')));
});

test('validateSource : type inconnu => finding', () => {
  const findings = validateSource(goodSource({ type: 'tweet' }), 0, 0);
  assert.ok(findings.some((f) => f.includes('type invalide')));
});

test('validateSource : video sans timestamp => finding', () => {
  const findings = validateSource(goodSource({ type: 'video' }), 0, 0);
  assert.ok(findings.some((f) => f.includes('timestamp')));
});

test('validateSource : video avec timestamp => aucun finding', () => {
  const findings = validateSource(goodSource({ type: 'video', timestamp: '00:01:00' }), 0, 0);
  assert.deepEqual(findings, []);
});

test('validateLoops : 4 cles non vides => aucun finding', () => {
  assert.deepEqual(validateLoops(goodLoops(), 0), []);
});

test('validateLoops : une cle vide => finding cible', () => {
  const findings = validateLoops(goodLoops({ hour_5: '' }), 0);
  assert.ok(findings.some((f) => f.includes('hour_5')));
});

test('validateLoops : objet absent => finding', () => {
  const findings = validateLoops(null, 0);
  assert.ok(findings.length > 0);
});

test('validateConditionState : has_win_state=true + victory_condition non vide => aucun finding', () => {
  const obj = { has_win_state: true, victory_condition: 'atteindre le boss final' };
  assert.deepEqual(validateConditionState(obj, 'games[0].objectives[0]', 'has_win_state', 'victory_condition'), []);
});

test('validateConditionState : has_win_state=true + victory_condition absente => finding', () => {
  const obj = { has_win_state: true };
  const findings = validateConditionState(obj, 'games[0].objectives[0]', 'has_win_state', 'victory_condition');
  assert.ok(findings.some((f) => f.includes('victory_condition') && f.includes('requis')));
});

test('validateConditionState : has_win_state=false + victory_condition=null explicite => aucun finding', () => {
  const obj = { has_win_state: false, victory_condition: null };
  assert.deepEqual(validateConditionState(obj, 'games[0].objectives[0]', 'has_win_state', 'victory_condition'), []);
});

test('validateConditionState : has_win_state=false + victory_condition absente (champ omis) => finding', () => {
  const obj = { has_win_state: false };
  const findings = validateConditionState(obj, 'games[0].objectives[0]', 'has_win_state', 'victory_condition');
  assert.ok(findings.some((f) => f.includes('champ omis')));
});

test('validateConditionState : has_win_state=false + victory_condition="" (chaine vide, pas null) => finding', () => {
  const obj = { has_win_state: false, victory_condition: '' };
  const findings = validateConditionState(obj, 'games[0].objectives[0]', 'has_win_state', 'victory_condition');
  assert.ok(findings.some((f) => f.includes('exactement null')));
});

test('validateConditionState : has_win_state absent (pas un booleen) => finding, jamais de silence', () => {
  const findings = validateConditionState({}, 'games[0].objectives[0]', 'has_win_state', 'victory_condition');
  assert.ok(findings.some((f) => f.includes('booleen explicite')));
});

test('validateObjective : mode marathon sans victoire mais declaree explicitement => aucun finding', () => {
  assert.deepEqual(validateObjective(marathonObjective(), 0, 0), []);
});

test('validateObjective : mode versus bien forme => aucun finding', () => {
  assert.deepEqual(validateObjective(goodObjective({ mode: 'versus' }), 0, 0), []);
});

test('validateObjective : player_goal vide => finding', () => {
  const findings = validateObjective(goodObjective({ player_goal: '' }), 0, 0);
  assert.ok(findings.some((f) => f.includes('player_goal')));
});

test('validateObjective : mode absent => finding', () => {
  const findings = validateObjective(goodObjective({ mode: '' }), 0, 0);
  assert.ok(findings.some((f) => f.includes('mode')));
});

test('validateObjective : objet absent => finding', () => {
  assert.ok(validateObjective(null, 0, 0).length > 0);
});

test('validateGameEntry : jeu bien forme => aucun finding', () => {
  assert.deepEqual(validateGameEntry(goodGame(), 0), []);
});

test('validateGameEntry : moins de 3 sources => finding', () => {
  const findings = validateGameEntry(goodGame({ sources: [goodSource()] }), 0);
  assert.ok(findings.some((f) => f.includes('sources')));
});

test('validateGameEntry : objectives absent => finding', () => {
  const { objectives, ...withoutObjectives } = goodGame();
  const findings = validateGameEntry(withoutObjectives, 0);
  assert.ok(findings.some((f) => f.includes('objectives') && f.includes('tableau')));
});

test('validateGameEntry : objectives tableau vide => finding minimum', () => {
  const findings = validateGameEntry(goodGame({ objectives: [] }), 0);
  assert.ok(findings.some((f) => f.includes('objectives') && f.includes('minimum 1')));
});

test('validateGameEntry : plusieurs modes coexistent (solo + versus) => aucun finding', () => {
  const findings = validateGameEntry(goodGame({
    objectives: [goodObjective({ mode: 'solo' }), goodObjective({ mode: 'versus', victory_condition: 'eliminer le camp adverse' })],
  }), 0);
  assert.deepEqual(findings, []);
});

test('validateGameEntry : retention_answer vide => finding', () => {
  const findings = validateGameEntry(goodGame({ retention_answer: '' }), 0);
  assert.ok(findings.some((f) => f.includes('retention_answer')));
});

test('validateManifest : manifest bien forme => aucun finding', () => {
  assert.deepEqual(validateManifest(goodManifest()), []);
});

test('validateManifest : moins de 2 jeux => finding', () => {
  const findings = validateManifest(goodManifest({ games: [goodGame()] }));
  assert.ok(findings.some((f) => f.includes('minimum 2')));
});

test('validateManifest : advisory absent ou false => finding', () => {
  const findingsAbsent = validateManifest(goodManifest({ advisory: undefined }));
  assert.ok(findingsAbsent.some((f) => f.includes('advisory')));
  const findingsFalse = validateManifest(goodManifest({ advisory: false }));
  assert.ok(findingsFalse.some((f) => f.includes('advisory')));
});

test('checkNoLocalMedia : detecte les extensions interdites, ignore le reste', () => {
  const files = ['mechanics_analysis.md', 'ref/shot.png', 'notes.txt', 'clip.mp4'];
  const found = checkNoLocalMedia(files);
  assert.deepEqual(found.sort(), ['clip.mp4', 'ref/shot.png']);
});

// --- bout-en-bout : checkWorldScan sur un vrai dossier temporaire ---

test('checkWorldScan : dossier complet et valide => OK, exit implicite 0', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'worldscan_valid_'));
  try {
    await makeValidFolder(dir);
    const result = await checkWorldScan(dir);
    assert.equal(result.verdict, 'OK');
    assert.equal(result.ok, true);
    assert.deepEqual(result.problems, []);
    assert.equal(result.stats.games, 2);
    assert.equal(result.stats.sources_total, 6);
    assert.equal(result.stats.objectives_total, 2);
    assert.equal(result.stats.files_checked, REQUIRED_FILES.length);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});

test('checkWorldScan : fichier requis manquant => FAIL', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'worldscan_missingfile_'));
  try {
    await makeValidFolder(dir);
    await rm(join(dir, 'economy_map.md'));
    const result = await checkWorldScan(dir);
    assert.equal(result.verdict, 'FAIL');
    assert.ok(result.problems.some((p) => p.includes('economy_map.md')));
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});

test('checkWorldScan : fichier requis present mais vide => FAIL', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'worldscan_emptyfile_'));
  try {
    await makeValidFolder(dir);
    await writeFile(join(dir, 'ux_flow.md'), '   \n  ', 'utf-8');
    const result = await checkWorldScan(dir);
    assert.equal(result.verdict, 'FAIL');
    assert.ok(result.problems.some((p) => p.includes('ux_flow.md') && p.includes('vide')));
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});

test('checkWorldScan : observation_manifest.json JSON invalide => FAIL', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'worldscan_badjson_'));
  try {
    await makeValidFolder(dir);
    await writeFile(join(dir, 'observation_manifest.json'), '{ceci n\'est pas du json}', 'utf-8');
    const result = await checkWorldScan(dir);
    assert.equal(result.verdict, 'FAIL');
    assert.ok(result.problems.some((p) => p.includes('JSON invalide')));
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});

test('checkWorldScan : moins de 2 jeux analyses => FAIL', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'worldscan_onegame_'));
  try {
    await makeValidFolder(dir);
    await writeFile(join(dir, 'observation_manifest.json'), JSON.stringify(goodManifest({ games: [goodGame()] })), 'utf-8');
    const result = await checkWorldScan(dir);
    assert.equal(result.verdict, 'FAIL');
    assert.ok(result.problems.some((p) => p.includes('minimum 2')));
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});

test('checkWorldScan : source sans url => FAIL', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'worldscan_nourl_'));
  try {
    await makeValidFolder(dir);
    const badGame = goodGame({ sources: [goodSource({ url: undefined }), goodSource({ url: 'https://example.test/b' }), goodSource({ url: 'https://example.test/c' })] });
    await writeFile(join(dir, 'observation_manifest.json'), JSON.stringify(goodManifest({ games: [badGame, goodGame({ game: 'FTL' })] })), 'utf-8');
    const result = await checkWorldScan(dir);
    assert.equal(result.verdict, 'FAIL');
    assert.ok(result.problems.some((p) => p.includes('url manquante ou invalide')));
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});

test('checkWorldScan : source video sans timestamp => FAIL', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'worldscan_novideots_'));
  try {
    await makeValidFolder(dir);
    const badGame = goodGame({ sources: [goodSource({ type: 'video' }), goodSource({ url: 'https://example.test/b' }), goodSource({ url: 'https://example.test/c' })] });
    await writeFile(join(dir, 'observation_manifest.json'), JSON.stringify(goodManifest({ games: [badGame, goodGame({ game: 'FTL' })] })), 'utf-8');
    const result = await checkWorldScan(dir);
    assert.equal(result.verdict, 'FAIL');
    assert.ok(result.problems.some((p) => p.includes('timestamp')));
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});

test('checkWorldScan : loops vide => FAIL', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'worldscan_emptyloops_'));
  try {
    await makeValidFolder(dir);
    const badGame = goodGame({ loops: goodLoops({ minute_1: '', minute_10: '', hour_5: '', endgame: '' }) });
    await writeFile(join(dir, 'observation_manifest.json'), JSON.stringify(goodManifest({ games: [badGame, goodGame({ game: 'FTL' })] })), 'utf-8');
    const result = await checkWorldScan(dir);
    assert.equal(result.verdict, 'FAIL');
    assert.ok(result.problems.some((p) => p.includes('loops') && p.includes('minute_1')));
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});

test('checkWorldScan : jeu marathon sans etat gagne declare explicitement (has_win_state:false + victory_condition:null) => OK', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'worldscan_marathon_ok_'));
  try {
    await makeValidFolder(dir);
    const marathonGame = goodGame({ game: 'Tetris', objectives: [marathonObjective()] });
    await writeFile(join(dir, 'observation_manifest.json'), JSON.stringify(goodManifest({ games: [marathonGame, goodGame({ game: 'FTL' })] })), 'utf-8');
    const result = await checkWorldScan(dir);
    assert.equal(result.verdict, 'OK');
    assert.equal(result.stats.objectives_total, 2);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});

test('checkWorldScan : plusieurs modes (solo + versus) avec conditions differentes => OK', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'worldscan_multimode_'));
  try {
    await makeValidFolder(dir);
    const versusGame = goodGame({
      objectives: [
        goodObjective({ mode: 'solo' }),
        goodObjective({ mode: 'versus', victory_condition: 'detruire la base adverse avant le joueur' }),
      ],
    });
    await writeFile(join(dir, 'observation_manifest.json'), JSON.stringify(goodManifest({ games: [versusGame, goodGame({ game: 'FTL' })] })), 'utf-8');
    const result = await checkWorldScan(dir);
    assert.equal(result.verdict, 'OK');
    assert.equal(result.stats.objectives_total, 3);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});

test('checkWorldScan : bloc objectives absent du manifest => FAIL (validateur sans producteur interdit)', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'worldscan_noobjectives_'));
  try {
    await makeValidFolder(dir);
    const { objectives, ...gameWithoutObjectives } = goodGame();
    await writeFile(join(dir, 'observation_manifest.json'), JSON.stringify(goodManifest({ games: [gameWithoutObjectives, goodGame({ game: 'FTL' })] })), 'utf-8');
    const result = await checkWorldScan(dir);
    assert.equal(result.verdict, 'FAIL');
    assert.ok(result.problems.some((p) => p.includes('objectives') && p.includes('tableau')));
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});

test('checkWorldScan : genre sans etat gagne MAL declare (champ absent au lieu de has_win_state:false) => FAIL', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'worldscan_badmarathon_'));
  try {
    await makeValidFolder(dir);
    const { has_win_state, victory_condition, ...badMarathon } = marathonObjective();
    const badGame = goodGame({ objectives: [badMarathon] });
    await writeFile(join(dir, 'observation_manifest.json'), JSON.stringify(goodManifest({ games: [badGame, goodGame({ game: 'FTL' })] })), 'utf-8');
    const result = await checkWorldScan(dir);
    assert.equal(result.verdict, 'FAIL');
    assert.ok(result.problems.some((p) => p.includes('has_win_state') && p.includes('booleen explicite')));
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});

test('checkWorldScan : media local present (png) => FAIL, meme si le manifest est valide', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'worldscan_media_'));
  try {
    await makeValidFolder(dir);
    await mkdir(join(dir, 'shots'), { recursive: true });
    await writeFile(join(dir, 'shots', 'capture.png'), Buffer.from([137, 80, 78, 71]), 'utf-8');
    const result = await checkWorldScan(dir);
    assert.equal(result.verdict, 'FAIL');
    assert.ok(result.problems.some((p) => p.includes('media local interdit') && p.includes('capture.png')));
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});

test('checkWorldScan : dossier inexistant => FAIL, jamais une exception', async () => {
  const result = await checkWorldScan(join(tmpdir(), 'worldscan_does_not_exist_xyz'));
  assert.equal(result.verdict, 'FAIL');
  assert.equal(result.ok, false);
  assert.ok(result.problems[0].includes('illisible'));
});

// --- mode fichier (v0.3, 2026-08-03) : worldscan.json matérialisé par l'exécuteur,
// l'agent s2-worldscan n'a plus le droit d'écrire (invariant « un agent de
// connaissance ne doit jamais posséder l'état qu'il décrit »). checkWorldScan()
// doit dispatcher sur le TYPE du chemin (fichier vs dossier), aucun flag séparé.

test('checkWorldScan (mode fichier) : manifeste JSON valide seul => OK, dispatch automatique sur checkWorldScanFile', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'worldscan_file_valid_'));
  try {
    const filePath = join(dir, 'worldscan.json');
    await writeFile(filePath, JSON.stringify(goodManifest(), null, 2), 'utf-8');
    const result = await checkWorldScan(filePath);
    assert.equal(result.verdict, 'OK');
    assert.equal(result.ok, true);
    assert.deepEqual(result.problems, []);
    assert.equal(result.stats.games, 2);
    assert.equal(result.stats.sources_total, 6);
    assert.equal(result.stats.objectives_total, 2);
    assert.equal(result.stats.files_checked, 1);
    assert.equal(result.stats.media_files_found, 0);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});

test('checkWorldScanFile : appel direct, meme resultat que via checkWorldScan', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'worldscan_file_direct_'));
  try {
    const filePath = join(dir, 'worldscan.json');
    await writeFile(filePath, JSON.stringify(goodManifest()), 'utf-8');
    const result = await checkWorldScanFile(filePath);
    assert.equal(result.verdict, 'OK');
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});

test('checkWorldScan (mode fichier) : moins de 2 jeux => FAIL, meme regle que le mode dossier', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'worldscan_file_onegame_'));
  try {
    const filePath = join(dir, 'worldscan.json');
    await writeFile(filePath, JSON.stringify(goodManifest({ games: [goodGame()] })), 'utf-8');
    const result = await checkWorldScan(filePath);
    assert.equal(result.verdict, 'FAIL');
    assert.ok(result.problems.some((p) => p.includes('minimum 2')));
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});

test('checkWorldScan (mode fichier) : objectives absent => FAIL, meme regle que le mode dossier', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'worldscan_file_noobjectives_'));
  try {
    const filePath = join(dir, 'worldscan.json');
    const { objectives, ...gameWithoutObjectives } = goodGame();
    await writeFile(filePath, JSON.stringify(goodManifest({ games: [gameWithoutObjectives, goodGame({ game: 'FTL' })] })), 'utf-8');
    const result = await checkWorldScan(filePath);
    assert.equal(result.verdict, 'FAIL');
    assert.ok(result.problems.some((p) => p.includes('objectives') && p.includes('tableau')));
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});

test('checkWorldScan (mode fichier) : genre sans etat gagne MAL declare => FAIL, meme regle que le mode dossier', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'worldscan_file_badmarathon_'));
  try {
    const filePath = join(dir, 'worldscan.json');
    const { has_win_state, victory_condition, ...badMarathon } = marathonObjective();
    const badGame = goodGame({ objectives: [badMarathon] });
    await writeFile(filePath, JSON.stringify(goodManifest({ games: [badGame, goodGame({ game: 'FTL' })] })), 'utf-8');
    const result = await checkWorldScan(filePath);
    assert.equal(result.verdict, 'FAIL');
    assert.ok(result.problems.some((p) => p.includes('has_win_state') && p.includes('booleen explicite')));
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});

test('checkWorldScan (mode fichier) : JSON invalide => FAIL', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'worldscan_file_badjson_'));
  try {
    const filePath = join(dir, 'worldscan.json');
    await writeFile(filePath, '{ceci n\'est pas du json}', 'utf-8');
    const result = await checkWorldScan(filePath);
    assert.equal(result.verdict, 'FAIL');
    assert.ok(result.problems.some((p) => p.includes('JSON invalide')));
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});

test('checkWorldScan (mode fichier) : fichier vide => FAIL', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'worldscan_file_empty_'));
  try {
    const filePath = join(dir, 'worldscan.json');
    await writeFile(filePath, '   \n  ', 'utf-8');
    const result = await checkWorldScan(filePath);
    assert.equal(result.verdict, 'FAIL');
    assert.ok(result.problems.some((p) => p.includes('vide')));
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});

test('checkWorldScan (mode fichier) : fichier inexistant => FAIL, jamais une exception', async () => {
  const result = await checkWorldScan(join(tmpdir(), 'worldscan_file_does_not_exist_xyz.json'));
  assert.equal(result.verdict, 'FAIL');
  assert.equal(result.ok, false);
});

test('checkWorldScan (mode dossier) : toujours fonctionnel apres l ajout du mode fichier, verdict OK inchange', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'worldscan_dirmode_unaffected_'));
  try {
    await makeValidFolder(dir);
    const result = await checkWorldScan(dir);
    assert.equal(result.verdict, 'OK');
    assert.equal(result.stats.files_checked, REQUIRED_FILES.length);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});

test('listFilesRecursive : liste les fichiers en sous-dossiers', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'worldscan_listfiles_'));
  try {
    await mkdir(join(dir, 'sub'), { recursive: true });
    await writeFile(join(dir, 'a.md'), 'x', 'utf-8');
    await writeFile(join(dir, 'sub', 'b.md'), 'y', 'utf-8');
    const files = await listFilesRecursive(dir);
    assert.deepEqual(files.sort(), ['a.md', 'sub/b.md']);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});

// --- P5 (v0.4) : checkFactConsistency — juge de CONTENU, contradiction interne
// has_win_state=false vs vocabulaire de complétion dans le meme document. Patron de
// preuve : EVIDENCE/bundles/MCTS_WORLDSCAN_QWEN/qwen_gen1_worldscan.json (Pac-Man,
// has_win_state:false + loops.endgame = "Le but ultime est d'atteindre la fin du
// jeu en accumulant le plus de points possible.").

test('checkFactConsistency : has_win_state=false + loops.endgame encadre "atteindre la fin" comme un but => finding', () => {
  const doc = goodManifest({
    games: [
      goodGame({
        objectives: [goodObjective({ has_win_state: false, victory_condition: null })],
        loops: goodLoops({ endgame: "Le but ultime est d'atteindre la fin du jeu en accumulant le plus de points possible." }),
      }),
      goodGame({ game: 'FTL' }),
    ],
  });
  const findings = checkFactConsistency(doc);
  assert.ok(findings.some((f) => f.includes('games[0].objectives[0]') && f.includes('has_win_state=false')));
});

test('checkFactConsistency : has_win_state=false + "reach the end" (EN) dans player_goal => finding', () => {
  const doc = goodManifest({
    games: [
      goodGame({
        objectives: [goodObjective({
          has_win_state: false,
          victory_condition: null,
          player_goal: 'The ultimate goal is reaching the end of the run before the timer expires.',
        })],
      }),
      goodGame({ game: 'FTL' }),
    ],
  });
  const findings = checkFactConsistency(doc);
  assert.ok(findings.length > 0);
});

test('checkFactConsistency : has_win_state=false sans vocabulaire de completion (marathon legitime) => aucun finding', () => {
  const doc = goodManifest({
    games: [
      goodGame({ objectives: [marathonObjective()] }),
      goodGame({ game: 'FTL' }),
    ],
  });
  assert.deepEqual(checkFactConsistency(doc), []);
});

test('checkFactConsistency : has_win_state=true (mode normal) meme avec vocabulaire "but ultime" => aucun finding (rien a contredire)', () => {
  const doc = goodManifest({
    games: [
      goodGame({
        objectives: [goodObjective({ has_win_state: true })],
        loops: goodLoops({ endgame: 'Le but ultime est de vider le labyrinthe.' }),
      }),
      goodGame({ game: 'FTL' }),
    ],
  });
  assert.deepEqual(checkFactConsistency(doc), []);
});

test('checkFactConsistency : doc sans games (deja invalide structurellement) => aucun finding, ne jette pas', () => {
  assert.deepEqual(checkFactConsistency({}), []);
  assert.deepEqual(checkFactConsistency(null), []);
});

test('checkWorldScan (mode fichier) : has_win_state=false + vocabulaire de completion contradictoire => FAIL via le juge de contenu', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'worldscan_factcheck_'));
  try {
    const filePath = join(dir, 'worldscan.json');
    const badGame = goodGame({
      objectives: [goodObjective({ has_win_state: false, victory_condition: null })],
      loops: goodLoops({ endgame: "Le but ultime est d'atteindre la fin du jeu." }),
    });
    await writeFile(filePath, JSON.stringify(goodManifest({ games: [badGame, goodGame({ game: 'FTL' })] })), 'utf-8');
    const result = await checkWorldScan(filePath);
    assert.equal(result.verdict, 'FAIL');
    assert.ok(result.problems.some((p) => p.includes('has_win_state=false')));
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});

test('checkWorldScan (mode dossier) : has_win_state=false + vocabulaire de completion contradictoire => FAIL via le juge de contenu', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'worldscan_factcheck_dir_'));
  try {
    await makeValidFolder(dir);
    const badGame = goodGame({
      objectives: [goodObjective({ has_win_state: false, victory_condition: null })],
      loops: goodLoops({ endgame: "Le but ultime est d'atteindre la fin du jeu." }),
    });
    await writeFile(join(dir, 'observation_manifest.json'), JSON.stringify(goodManifest({ games: [badGame, goodGame({ game: 'FTL' })] })), 'utf-8');
    const result = await checkWorldScan(dir);
    assert.equal(result.verdict, 'FAIL');
    assert.ok(result.problems.some((p) => p.includes('has_win_state=false')));
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});

// --- P5 (v0.4) : checkSourceUrlStability — advisory multi-generations, non branchee
// sur le verdict OK/FAIL de la CLI. Preuve : les 3 generations Qwen (gen1/gen2/gen3)
// citent 2 IDs YouTube differents pour la meme source "Pac-Man Gameplay" alors que
// l'URL Wikipedia du meme jeu reste identique dans les 3.

test('checkSourceUrlStability : moins de 2 documents fournis => aucun finding', () => {
  assert.deepEqual(checkSourceUrlStability([]), []);
  assert.deepEqual(checkSourceUrlStability([goodManifest()]), []);
});

test('checkSourceUrlStability : meme jeu, meme type, URL identique sur toutes les generations => aucun finding', () => {
  const docA = goodManifest({ games: [goodGame({ sources: [goodSource({ url: 'https://en.wikipedia.org/wiki/X', type: 'wiki' })] })] });
  const docB = goodManifest({ games: [goodGame({ sources: [goodSource({ url: 'https://en.wikipedia.org/wiki/X', type: 'wiki' })] })] });
  assert.deepEqual(checkSourceUrlStability([docA, docB]), []);
});

test('checkSourceUrlStability : meme jeu, meme type, URL qui derive entre generations => finding', () => {
  const docA = goodManifest({ games: [goodGame({ sources: [goodSource({ url: 'https://www.youtube.com/watch?v=04sJGfVZKdA', type: 'video', timestamp: '00:00' })] })] });
  const docB = goodManifest({ games: [goodGame({ sources: [goodSource({ url: 'https://www.youtube.com/watch?v=04aW5nXrjgk', type: 'video', timestamp: '00:00' })] })] });
  const findings = checkSourceUrlStability([docA, docB]);
  assert.ok(findings.some((f) => f.includes('Into the Breach') && f.includes('type=video')));
});

test('checkSourceUrlStability : jeux differents dans chaque doc => pas de faux positif (groupement par nom de jeu)', () => {
  const docA = goodManifest({ games: [goodGame({ game: 'Pac-Man', sources: [goodSource({ url: 'https://a.test/1' })] })] });
  const docB = goodManifest({ games: [goodGame({ game: 'Tetris', sources: [goodSource({ url: 'https://b.test/2' })] })] });
  assert.deepEqual(checkSourceUrlStability([docA, docB]), []);
});

// --- Integration : les 4 artefacts REELS de EVIDENCE/bundles/MCTS_WORLDSCAN_QWEN/
// et la reference EVIDENCE/runs/pacman/worldscan.json. Garde-fou du studio :
// "un oracle qui recale le producteur connu-bon se mesure lui-meme" — la reference
// Claude DOIT passer, gen1 (has_win_state=false errone) DOIT echouer.

test('integration reelle : reference Claude EVIDENCE/runs/pacman/worldscan.json => OK (l oracle n accepte pas de recaler le producteur connu-bon)', async () => {
  const refPath = join(REPO_ROOT, 'EVIDENCE', 'runs', 'pacman', 'worldscan.json');
  const raw = await readFile(refPath, 'utf-8');
  const doc = JSON.parse(raw);
  assert.deepEqual(checkFactConsistency(doc), []);
  const result = await checkWorldScan(refPath);
  assert.equal(result.verdict, 'OK', `reference devrait passer, problems: ${JSON.stringify(result.problems)}`);
});

test('integration reelle : qwen_gen1_worldscan.json (has_win_state=false errone pour Pac-Man) => FAIL via checkFactConsistency', async () => {
  const gen1Path = join(REPO_ROOT, 'EVIDENCE', 'bundles', 'MCTS_WORLDSCAN_QWEN', 'qwen_gen1_worldscan.json');
  const raw = await readFile(gen1Path, 'utf-8');
  const doc = JSON.parse(raw);
  const findings = checkFactConsistency(doc);
  assert.ok(findings.length > 0, 'gen1 devrait produire au moins une contradiction interne detectee');
  const result = await checkWorldScan(gen1Path);
  assert.equal(result.verdict, 'FAIL');
  assert.ok(result.problems.some((p) => p.includes('has_win_state=false')));
});

test('integration reelle : qwen_gen2_worldscan.json (has_win_state=true, coherent) => checkFactConsistency ne trouve rien (rule directionnelle, pas de faux positif)', async () => {
  const gen2Path = join(REPO_ROOT, 'EVIDENCE', 'bundles', 'MCTS_WORLDSCAN_QWEN', 'qwen_gen2_worldscan.json');
  const raw = await readFile(gen2Path, 'utf-8');
  const doc = JSON.parse(raw);
  assert.deepEqual(checkFactConsistency(doc), []);
});

test('integration reelle : qwen_gen3_worldscan.json (has_win_state=true, coherent) => checkFactConsistency ne trouve rien (rule directionnelle, pas de faux positif)', async () => {
  const gen3Path = join(REPO_ROOT, 'EVIDENCE', 'bundles', 'MCTS_WORLDSCAN_QWEN', 'qwen_gen3_worldscan.json');
  const raw = await readFile(gen3Path, 'utf-8');
  const doc = JSON.parse(raw);
  assert.deepEqual(checkFactConsistency(doc), []);
});

test('integration reelle : checkSourceUrlStability detecte la derive video Pac-Man entre gen1/gen2/gen3 (advisory, pas branche sur le verdict CLI)', async () => {
  const base = join(REPO_ROOT, 'EVIDENCE', 'bundles', 'MCTS_WORLDSCAN_QWEN');
  const [gen1, gen2, gen3] = await Promise.all(
    ['qwen_gen1_worldscan.json', 'qwen_gen2_worldscan.json', 'qwen_gen3_worldscan.json'].map(
      (f) => readFile(join(base, f), 'utf-8').then(JSON.parse)
    )
  );
  const findings = checkSourceUrlStability([gen1, gen2, gen3]);
  assert.ok(findings.some((f) => f.includes('Pac-Man') && f.includes('type=video')), `attendu une derive video Pac-Man, obtenu: ${JSON.stringify(findings)}`);
  // Les 3 generations passent quand meme le verdict de FORME sur chacune isolement
  // (checkSourceUrlStability n'est pas branchee sur checkWorldScan) : verifie ici
  // que gen2 seul (isole) n'echoue PAS a cause de cette regle multi-gen.
  const result2 = await checkWorldScan(join(base, 'qwen_gen2_worldscan.json'));
  assert.equal(result2.verdict, 'OK');
});

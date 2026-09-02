import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { resolveSolvabilityConfig } from './godot_oracle.mjs';
import { DEFAULT_MAX_TICKS, DEFAULT_TRIAL_TIMEOUT_MS, DEFAULT_SEED_START } from './solvability_godot.mjs';

function withTempConfig(contents, fn) {
  const dir = mkdtempSync(join(tmpdir(), 'godot-oracle-test-'));
  const path = join(dir, 'oracles.json');
  writeFileSync(path, contents, 'utf8');
  try {
    return fn(path);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

test('jeu SANS champ solvability -> repli EXACT sur les defauts historiques (non-regression grid_nav_probe)', () => {
  withTempConfig(JSON.stringify({
    grid_nav_probe: {
      cwd: '.',
      command: ['node', 'forge/godot_oracle.mjs', 'GAMES/grid_nav_probe'],
    },
  }), (path) => {
    const cfg = resolveSolvabilityConfig('GAMES/grid_nav_probe', path);
    assert.equal(cfg.maxTicks, DEFAULT_MAX_TICKS);
    assert.equal(cfg.maxTicks, 200);
    assert.equal(cfg.trials, 50);
    assert.equal(cfg.trialTimeoutMs, DEFAULT_TRIAL_TIMEOUT_MS);
    assert.equal(cfg.seedStart, DEFAULT_SEED_START);
  });
});

test('jeu AVEC champ solvability declare (snake) -> le budget declare est utilise', () => {
  withTempConfig(JSON.stringify({
    snake: {
      cwd: '.',
      command: ['node', 'forge/godot_oracle.mjs', 'GAMES/snake'],
      solvability: { max_ticks: 5000, trials: 50, trial_timeout_ms: 60000 },
    },
  }), (path) => {
    const cfg = resolveSolvabilityConfig('GAMES/snake', path);
    assert.equal(cfg.maxTicks, 5000);
    assert.equal(cfg.trials, 50);
    assert.equal(cfg.trialTimeoutMs, 60000);
  });
});

test('champ solvability PARTIEL -> seuls les champs absents retombent sur le defaut', () => {
  withTempConfig(JSON.stringify({
    demo: {
      cwd: '.',
      command: ['node', 'x'],
      solvability: { max_ticks: 999 },
    },
  }), (path) => {
    const cfg = resolveSolvabilityConfig('GAMES/demo', path);
    assert.equal(cfg.maxTicks, 999);
    assert.equal(cfg.trials, 50);
    assert.equal(cfg.trialTimeoutMs, DEFAULT_TRIAL_TIMEOUT_MS);
  });
});

test('oracles.json illisible (chemin inexistant) -> repli sur les defauts, jamais une exception', () => {
  const cfg = resolveSolvabilityConfig('GAMES/snake', '/chemin/qui/n/existe/pas/oracles.json');
  assert.equal(cfg.maxTicks, DEFAULT_MAX_TICKS);
  assert.equal(cfg.trials, 50);
  assert.equal(cfg.trialTimeoutMs, DEFAULT_TRIAL_TIMEOUT_MS);
});

test('oracles.json invalide (JSON casse) -> repli sur les defauts, jamais une exception', () => {
  withTempConfig('{ not valid json', (path) => {
    const cfg = resolveSolvabilityConfig('GAMES/snake', path);
    assert.equal(cfg.maxTicks, DEFAULT_MAX_TICKS);
  });
});

test('entree du jeu absente du config -> repli sur les defauts', () => {
  withTempConfig(JSON.stringify({ autre_jeu: { cwd: '.', command: ['node', 'x'] } }), (path) => {
    const cfg = resolveSolvabilityConfig('GAMES/snake', path);
    assert.equal(cfg.maxTicks, DEFAULT_MAX_TICKS);
    assert.equal(cfg.trials, 50);
  });
});

test('le vrai forge/oracles.json declare bien max_ticks=5000 pour snake', () => {
  const cfg = resolveSolvabilityConfig('GAMES/snake');
  assert.equal(cfg.maxTicks, 5000);
  assert.equal(cfg.trials, 50);
  assert.equal(cfg.trialTimeoutMs, 60000);
});

test('le vrai forge/oracles.json laisse grid_nav_probe au defaut (non-regression)', () => {
  const cfg = resolveSolvabilityConfig('GAMES/grid_nav_probe');
  assert.equal(cfg.maxTicks, DEFAULT_MAX_TICKS);
  assert.equal(cfg.trials, 50);
  assert.equal(cfg.trialTimeoutMs, DEFAULT_TRIAL_TIMEOUT_MS);
});

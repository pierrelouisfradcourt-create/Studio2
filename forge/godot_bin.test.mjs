import { test } from 'node:test';
import assert from 'node:assert/strict';
import { writeFileSync, mkdtempSync, rmSync } from 'node:fs';
import { join, resolve, dirname } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { resolveGodotBin } from './godot_bin.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));

test('GODOT_BIN dans l env a la priorite', () => {
  const dir = mkdtempSync(join(tmpdir(), 'gb-'));
  try {
    const fake = join(dir, 'godot.exe');
    writeFileSync(fake, 'x');
    const got = resolveGodotBin({ env: { GODOT_BIN: fake }, configPath: join(dir, 'absent.json') });
    assert.equal(got, fake);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('fallback sur le fichier de config', () => {
  const dir = mkdtempSync(join(tmpdir(), 'gb-'));
  try {
    const fake = join(dir, 'godot.exe');
    writeFileSync(fake, 'x');
    const cfg = join(dir, 'godot.config.json');
    writeFileSync(cfg, JSON.stringify({ godot_bin: fake }), 'utf-8');
    const got = resolveGodotBin({ env: {}, configPath: cfg });
    assert.equal(got, fake);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('binaire declare mais absent du disque -> erreur actionnable', () => {
  const dir = mkdtempSync(join(tmpdir(), 'gb-'));
  try {
    const cfg = join(dir, 'godot.config.json');
    writeFileSync(cfg, JSON.stringify({ godot_bin: join(dir, 'nope.exe') }), 'utf-8');
    assert.throws(
      () => resolveGodotBin({ env: {}, configPath: cfg }),
      /introuvable sur le disque/
    );
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('aucune source de configuration -> erreur qui explique quoi faire', () => {
  const dir = mkdtempSync(join(tmpdir(), 'gb-'));
  try {
    assert.throws(
      () => resolveGodotBin({ env: {}, configPath: join(dir, 'absent.json') }),
      /GODOT_BIN|godot\.config\.json/
    );
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('chemin relatif dans GODOT_BIN est resolu par rapport a la racine du depot', () => {
  // HERE = forge/, donc repoRoot = forge/../../ = TACTICAL_CHESS_STUDIO/
  const repoRoot = resolve(HERE, '../..');
  // Utiliser un chemin relatif qui pointe vers un fichier qui existe (godot_bin.mjs lui-même)
  const relativePath = 'forge/godot_bin.mjs';
  const expectedAbsolute = resolve(repoRoot, relativePath);

  const dir = mkdtempSync(join(tmpdir(), 'gb-'));
  try {
    const got = resolveGodotBin({ env: { GODOT_BIN: relativePath }, configPath: join(dir, 'absent.json') });
    assert.equal(got, expectedAbsolute);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('JSON malformé dans le fichier de config produit une erreur lisible', () => {
  const dir = mkdtempSync(join(tmpdir(), 'gb-'));
  try {
    const cfg = join(dir, 'godot.config.json');
    writeFileSync(cfg, '{invalid json}', 'utf-8');
    assert.throws(
      () => resolveGodotBin({ env: {}, configPath: cfg }),
      /illisible/
    );
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

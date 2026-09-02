import { test } from 'node:test';
import assert from 'node:assert/strict';
import { makeGodotRunTrial, parseReceipt } from './godot_trial.mjs';

const CFG = { godot_project: 'fixtures/godot_trial_probe', godot_script: 'res://trial.gd', trial_timeout_ms: 30000 };

test('parseReceipt extrait la ligne prefixee au milieu du bruit', () => {
  const out = 'Godot Engine v4.6.3\nblabla\nFORGE_TRIAL {"succeeded":true,"ticks":9}\nautre bruit\n';
  // `diag: null` depuis 2026-08-18 : le recu porte desormais le canal de DIAGNOSTIC
  // optionnel (`FORGE_DIAG`). `null` et non `{}` — un objet vide laisserait croire a un
  // diagnostic vierge la ou il n'y en a PAS. Cette sortie n'en emet aucun.
  assert.deepEqual(parseReceipt(out), { succeeded: true, ticks: 9, diag: null });
});

test('parseReceipt rejette une sortie sans recu', () => {
  assert.throws(() => parseReceipt('rien ici'), /aucun recu FORGE_TRIAL/);
});

test('parseReceipt rejette un recu mal forme', () => {
  assert.throws(() => parseReceipt('FORGE_TRIAL {pas du json}'), /recu FORGE_TRIAL illisible/);
});

test('parseReceipt rejette un recu au mauvais type', () => {
  assert.throws(() => parseReceipt('FORGE_TRIAL {"succeeded":"oui","ticks":9}'), /champ succeeded/);
});

test('parseReceipt rejette une sortie avec plusieurs recus (ambigu)', () => {
  const out = 'FORGE_TRIAL {"succeeded":true,"ticks":1}\nblabla\nFORGE_TRIAL {"succeeded":false,"ticks":null}\n';
  assert.throws(() => parseReceipt(out), /2/);
});

test('runTrial passe le seed a Godot et rend le recu', () => {
  const calls = [];
  const spawnFn = (bin, args) => {
    calls.push({ bin, args });
    return { status: 0, stdout: 'FORGE_TRIAL {"succeeded":true,"ticks":5}', stderr: '' };
  };
  const runTrial = makeGodotRunTrial(spawnFn, () => 'FAKE_GODOT');
  const res = runTrial(42, CFG);
  assert.deepEqual(res, { succeeded: true, ticks: 5, diag: null });
  assert.equal(calls[0].bin, 'FAKE_GODOT');
  assert.ok(calls[0].args.includes('--headless'));
  assert.ok(calls[0].args.includes('--seed=42'));
});

test('exit code non nul -> erreur incluant stderr', () => {
  const spawnFn = () => ({ status: 1, stdout: '', stderr: 'SCRIPT ERROR: boom' });
  const runTrial = makeGodotRunTrial(spawnFn, () => 'FAKE_GODOT');
  assert.throws(() => runTrial(1, CFG), /exit 1.*boom/s);
});

test('cfg incomplet -> erreur explicite avant tout spawn', () => {
  let spawned = false;
  const spawnFn = () => { spawned = true; return { status: 0, stdout: '', stderr: '' }; };
  const runTrial = makeGodotRunTrial(spawnFn, () => 'FAKE_GODOT');
  assert.throws(() => runTrial(1, { godot_project: 'x' }), /godot_script/);
  assert.equal(spawned, false);
});

test('trial_timeout_ms non numerique -> erreur explicite avant tout spawn', () => {
  let spawned = false;
  const spawnFn = () => { spawned = true; return { status: 0, stdout: '', stderr: '' }; };
  const runTrial = makeGodotRunTrial(spawnFn, () => 'FAKE_GODOT');
  const badCfg = { ...CFG, trial_timeout_ms: 'trente mille' };
  assert.throws(() => runTrial(1, badCfg), /trial_timeout_ms/);
  assert.equal(spawned, false);
});

test('trial_timeout_ms negatif ou nul -> erreur explicite avant tout spawn', () => {
  let spawned = false;
  const spawnFn = () => { spawned = true; return { status: 0, stdout: '', stderr: '' }; };
  const runTrial = makeGodotRunTrial(spawnFn, () => 'FAKE_GODOT');
  assert.throws(() => runTrial(1, { ...CFG, trial_timeout_ms: 0 }), /trial_timeout_ms/);
  assert.equal(spawned, false);
});

test('runTrial transmet trial_timeout_ms dans opts.timeout au spawnFn', () => {
  let capturedOpts = null;
  const spawnFn = (bin, args, opts) => {
    capturedOpts = opts;
    return { status: 0, stdout: 'FORGE_TRIAL {"succeeded":true,"ticks":5}', stderr: '' };
  };
  const runTrial = makeGodotRunTrial(spawnFn, () => 'FAKE_GODOT');
  runTrial(1, CFG);
  assert.equal(capturedOpts.timeout, CFG.trial_timeout_ms);
});

test('depassement de timeout -> runTrial leve et ne rend jamais de recu', () => {
  const spawnFn = () => ({ error: new Error('spawnSync ETIMEDOUT'), status: null, stdout: '', stderr: '' });
  const runTrial = makeGodotRunTrial(spawnFn, () => 'FAKE_GODOT');
  assert.throws(() => runTrial(1, CFG), /ETIMEDOUT|spawn Godot impossible/);
});

// check_prisme.test.mjs — jamais testé avant promotion (Tier 2 #6). Oracle de forme
// pur (aucun jugement de contenu) pour un artefact product_snapshot.md.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { checkFile, splitSections } from './check_prisme.mjs';

function _tmpFile(t, content) {
  const dir = mkdtempSync(join(tmpdir(), 'prisme-check-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const p = join(dir, 'snapshot.md');
  writeFileSync(p, content, 'utf-8');
  return p;
}

const VALID = `# Snapshot

## 1. CE QUE LE JOUEUR VOIT

Une raquette, une balle, un mur de briques dans une aire de jeu bien définie et lisible.

## 2. CE QUE LE JOUEUR FAIT

Deplace la raquette au clavier pour intercepter la balle et casser les briques du niveau.

## 3. CE QUE LE JOUEUR RESSENT

Tension croissante a mesure que le niveau se vide, satisfaction a la destruction finale.

## 4. RÈGLES OBSERVABLES

- **R1 — la balle rebondit sur les murs lateraux avec inversion stricte de vx.**
- **R2 — victoire ssi briques_restantes == 0.**
`;

test('artefact conforme aux 4 sections -> pass', async (t) => {
  const p = _tmpFile(t, VALID);
  const res = await checkFile(p);
  assert.equal(res.pass, true, JSON.stringify(res.findings));
});

test('section manquante (ressent) -> rejet', async (t) => {
  const broken = VALID.replace(/## 3\. CE QUE LE JOUEUR RESSENT[\s\S]*?(?=## 4)/, '');
  const p = _tmpFile(t, broken);
  const res = await checkFile(p);
  assert.equal(res.pass, false);
  assert.ok(res.findings.some((f) => f.includes('ressent')));
});

test('section trop courte (< 40 caracteres) -> rejet', async (t) => {
  const broken = VALID.replace(
    /## 2\. CE QUE LE JOUEUR FAIT\n\n[\s\S]*?(?=## 3)/,
    '## 2. CE QUE LE JOUEUR FAIT\n\ntrop court.\n\n'
  );
  const p = _tmpFile(t, broken);
  const res = await checkFile(p);
  assert.equal(res.pass, false);
  assert.ok(res.findings.some((f) => f.includes('trop courte')));
});

test('placeholder "à définir" dans une section -> rejet', async (t) => {
  const broken = VALID.replace('Une raquette', 'à définir — Une raquette');
  const p = _tmpFile(t, broken);
  const res = await checkFile(p);
  assert.equal(res.pass, false);
  assert.ok(res.findings.some((f) => f.includes('placeholder')));
});

test('preambule qui AFFIRME l\'absence de placeholder ne doit PAS declencher un faux positif (bug reel documente)', async (t) => {
  const withPreamble = `Aucun champ « à définir ».\n\n${VALID}`;
  const p = _tmpFile(t, withPreamble);
  const res = await checkFile(p);
  // le preambule est HORS des 4 sections requises -> ne doit pas etre scanne
  assert.equal(res.pass, true, JSON.stringify(res.findings));
});

test('regles_observables sans regle numerotee "- **Rn" -> rejet', async (t) => {
  const broken = VALID.replace(
    /## 4\. RÈGLES OBSERVABLES[\s\S]*$/,
    '## 4. RÈGLES OBSERVABLES\n\nDes regles generiques sans numerotation formelle ici.\n'
  );
  const p = _tmpFile(t, broken);
  const res = await checkFile(p);
  assert.equal(res.pass, false);
  assert.ok(res.findings.some((f) => f.includes('numerotee') || f.includes('numérotée')));
});

test('fichier illisible -> pass=false, pas de crash', async () => {
  const res = await checkFile('/chemin/inexistant/xyz.md');
  assert.equal(res.pass, false);
  assert.ok(res.findings[0].includes('illisible'));
});

test('splitSections capture les 4 sections attendues dans l\'ordre', () => {
  const sections = splitSections(VALID);
  assert.deepEqual([...sections.keys()], ['voit', 'fait', 'ressent', 'regles_observables']);
});

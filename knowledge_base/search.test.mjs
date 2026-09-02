// search.test.mjs — tests du moteur de recherche par intention (search.mjs).
// node --test, zéro réseau, zéro LLM. Charge le VRAI catalog.json (pas un fixture) —
// ces tests documentent le comportement réel sur la bibliothèque telle qu'elle est.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { search, findFulfilling } from './search.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const catalog = JSON.parse(readFileSync(resolve(__dirname, 'catalog.json'), 'utf-8'));

// ---------- pont SEARCH↔ROLE (Tier 1 #4) ----------
test('findFulfilling : role-pursuer-mobile est reellement couvert par sys-pursuer-mobile', () => {
  const { role, fulfilling, declaredButNotCovered } = findFulfilling('role-pursuer-mobile', catalog);
  assert.ok(role, 'le role doit etre trouve dans le catalogue reel');
  assert.deepEqual(fulfilling.map((b) => b.brick_id), ['sys-pursuer-mobile']);
  assert.deepEqual(declaredButNotCovered, []);
});

test('findFulfilling : role-guardian-static est reellement couvert par sys-guardian-zoc', () => {
  const { fulfilling } = findFulfilling('role-guardian-static', catalog);
  assert.deepEqual(fulfilling.map((b) => b.brick_id), ['sys-guardian-zoc']);
});

test('findFulfilling : role inconnu -> role null, listes vides (pas de crash)', () => {
  const res = findFulfilling('role-n-existe-pas', catalog);
  assert.equal(res.role, null);
  assert.deepEqual(res.fulfilling, []);
  assert.deepEqual(res.declaredButNotCovered, []);
});

test('findFulfilling : detecte un fulfilled_by perime (declare mais affordances ne couvre plus)', () => {
  const perime = {
    catalog_version: 1,
    entries: [
      { entry_type: 'role', role_id: 'role-x', archetype: 'x',
        requires: { move: { type: 'fn()->pos', description: 'x' } },
        fulfilled_by: ['sys-x'], tier: 'candidate', license: 'MIT',
        path: 'knowledge_base/roles/x.yaml', proof_of_use: null },
      { entry_type: 'brick', brick_id: 'sys-x', kind: 'system', function: 'x',
        source: 'x', provenance_url: null, license: 'MIT', runtime: 'html',
        dependencies: [], parameters: {}, genre_compatible: ['tactical'],
        invariants: ['x'], proof_of_use: null, tier: 'candidate',
        path: null, sha256: null, tests: null, advisory_only: false,
        affordances: {} }, // ne couvre PAS "move" — perime
    ],
  };
  const { fulfilling, declaredButNotCovered } = findFulfilling('role-x', perime);
  assert.deepEqual(fulfilling, []);
  assert.deepEqual(declaredButNotCovered.map((b) => b.brick_id), ['sys-x']);
});

test('findFulfilling : une piece NON declaree dans fulfilled_by mais qui couvre requires est quand meme trouvee', () => {
  const undeclared = {
    catalog_version: 1,
    entries: [
      { entry_type: 'role', role_id: 'role-y', archetype: 'y',
        requires: { move: { type: 'fn()->pos', description: 'y' } },
        fulfilled_by: [], tier: 'candidate', license: 'MIT',
        path: 'knowledge_base/roles/y.yaml', proof_of_use: null },
      { entry_type: 'brick', brick_id: 'sys-y', kind: 'system', function: 'y',
        source: 'y', provenance_url: null, license: 'MIT', runtime: 'html',
        dependencies: [], parameters: {}, genre_compatible: ['tactical'],
        invariants: ['y'], proof_of_use: null, tier: 'candidate',
        path: null, sha256: null, tests: null, advisory_only: false,
        affordances: { move: { type: 'fn()->pos', description: 'y' } } },
    ],
  };
  const { fulfilling } = findFulfilling('role-y', undeclared);
  assert.deepEqual(fulfilling.map((b) => b.brick_id), ['sys-y']);
});

test('régression : une requête "temps réel/continu" doit préférer sys-pursuer-continuous, pas sys-pursuer-mobile — bug réel trouvé le 2026-07-13 (les 2 fiches se citaient l\'une l\'autre en négation, "pour X" vs "PAS pour X" scoraient pareil ; corrigé en rendant chaque fiche autonome, sans le vocabulaire de l\'autre cas d\'usage)', () => {
  const results = search('poursuite continue temps reel canvas vecteur arcade', catalog);
  assert.equal(results[0].entry.brick_id, 'sys-pursuer-continuous');
  const mobile = results.find((r) => r.entry.brick_id === 'sys-pursuer-mobile');
  if (mobile) {
    assert.ok(mobile.score < results[0].score, 'sys-pursuer-mobile ne doit plus scorer à égalité avec sys-pursuer-continuous sur une requête temps réel');
  }
});

test('régression symétrique : une requête "grille/tour par tour" doit préférer sys-pursuer-mobile, pas sys-pursuer-continuous', () => {
  const results = search('poursuite grille tour par tour plateau rogue-like', catalog);
  assert.equal(results[0].entry.brick_id, 'sys-pursuer-mobile');
});

test('recherche par intention : "zone de controle qui bloque un deplacement" trouve le pattern ET le système réel', () => {
  // Mis à jour le 2026-07-13 : depuis l'enregistrement de sys-guardian-zoc (2e ROLE),
  // le système qui IMPLÉMENTE réellement le mécanisme matche mieux que la simple
  // citation du pattern — attendu, pas une régression (chercher "une zone de contrôle
  // qui bloque un déplacement" doit prioritairement remonter le code qui le FAIT).
  const results = search('zone de controle qui bloque un deplacement', catalog);
  const ids = results.map((r) => r.entry.brick_id);
  assert.ok(ids.includes('pat-zone-of-control'), `attendu pat-zone-of-control dans ${JSON.stringify(ids)}`);
  assert.ok(ids.includes('sys-guardian-zoc'), `attendu sys-guardian-zoc dans ${JSON.stringify(ids)}`);
  assert.equal(results[0].entry.brick_id, 'sys-guardian-zoc', 'le système réel doit primer sur la citation du pattern');
});

test('recherche "degats" trouve les 2 entrées damage-floor (pattern ET système)', () => {
  const results = search('degats', catalog);
  const ids = results.map((r) => r.entry.brick_id).sort();
  assert.deepEqual(ids, ['pat-damage-floor', 'sys-damage-floor']);
});

test('filtre --tier validated exclut les patterns (candidate), garde les systems (validated)', () => {
  const results = search('degats', catalog, { tier: 'validated' });
  assert.equal(results.length, 1);
  assert.equal(results[0].entry.brick_id, 'sys-damage-floor');
  assert.equal(results[0].entry.tier, 'validated');
});

test('les résultats validated sont triés avant les candidate à score égal', () => {
  const results = search('reechrit propre inspiree', catalog); // proche des 2 systems réécrits
  const validatedIndex = results.findIndex((r) => r.entry.tier === 'validated');
  const candidateIndex = results.findIndex((r) => r.entry.tier === 'candidate');
  if (validatedIndex !== -1 && candidateIndex !== -1) {
    assert.ok(validatedIndex < candidateIndex, 'validated doit apparaître avant candidate à score égal');
  }
});

test('filtre --genre restreint aux entrées compatibles avec ce genre', () => {
  const results = search('brique', catalog, { genre: 'rpg' });
  for (const r of results) {
    const genres = [...(r.entry.genre || []), ...(r.entry.genre_compatible || [])].map((g) => g.toLowerCase());
    assert.ok(genres.includes('rpg'), `${r.entry.brick_id || r.entry.asset_id} doit être compatible rpg`);
  }
});

test('requête sans aucun mot-clé pertinent retourne zéro résultat (pas un crash, pas un mauvais match)', () => {
  const results = search('xyzzy plugh nonsense query qwerty', catalog);
  assert.equal(results.length, 0);
});

test('régression : une requête en phrase naturelle avec des mots vides fréquents ("tout", "pas", "du") ne doit PAS fuiter en faux positif — bug réel trouvé en testant le CLI (v1 matchait "tout")', () => {
  const results = search("quelque chose qui n'existe pas du tout", catalog);
  assert.equal(results.length, 0);
});

test('régression : "poursuite" ne doit PAS matcher via le mot français "pour" (préfixe de 4) présent dans un texte sans rapport — bug réel trouvé en vérifiant le catalogue enrichi (seuil relevé à 5)', () => {
  const results = search('poursuite mobile qui rattrape une cible', catalog);
  const ids = results.map((r) => r.entry.brick_id);
  assert.ok(!ids.includes('pat-damage-floor'), 'pat-damage-floor ne doit pas matcher (aucun rapport avec "poursuite", juste le mot "pour" dans un invariant)');
  assert.ok(ids.includes('sys-pursuer-mobile'), 'sys-pursuer-mobile doit rester trouvé (matches réels : poursuite/mobile/cible)');
});

test('les mots vides seuls (stopwords) ne produisent aucun score artificiel', () => {
  const results = search('le la de un une et', catalog);
  assert.equal(results.length, 0, 'une requête entièrement composée de mots vides ne doit matcher aucune entrée');
});

test('chaque résultat expose les tokens qui ont matché (transparence, pas une boîte noire)', () => {
  const results = search('degats', catalog);
  assert.ok(results.length > 0);
  for (const r of results) {
    assert.ok(Array.isArray(r.matchedTokens) && r.matchedTokens.length > 0);
    assert.ok(r.matchedTokens.includes('degats'));
  }
});

test('le tri est déterministe : deux appels identiques donnent le même ordre exact', () => {
  const r1 = search('systeme deterministe', catalog).map((r) => r.entry.brick_id || r.entry.asset_id);
  const r2 = search('systeme deterministe', catalog).map((r) => r.entry.brick_id || r.entry.asset_id);
  assert.deepEqual(r1, r2);
});

test('recherche insensible aux accents : "degats" et "dégâts" donnent le même résultat', () => {
  const withoutAccents = search('degats', catalog).map((r) => r.entry.brick_id);
  const withAccents = search('dégâts', catalog).map((r) => r.entry.brick_id);
  assert.deepEqual(withoutAccents, withAccents);
});

test('filtre --kind restreint au type exact (system vs pattern)', () => {
  const results = search('reechrit propre inspiree brique jeu tactique', catalog, { kind: 'system', minScore: 1 });
  for (const r of results) assert.equal(r.entry.kind, 'system');
});

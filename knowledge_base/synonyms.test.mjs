// synonyms.test.mjs — tests de l'élargissement de requête par synonymes déterministes
// (expandWithSynonyms) et de son câblage dans search(). node --test, zéro réseau, zéro LLM.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { search, expandWithSynonyms } from './search.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const catalog = JSON.parse(readFileSync(resolve(__dirname, 'catalog.json'), 'utf-8'));

// ---------- expandWithSynonyms (fonction pure) ----------

test('expandWithSynonyms : un token clé de groupe ajoute tous les synonymes du groupe', () => {
  const map = { poursuite: ['poursuite', 'chasse', 'traque'] };
  const result = expandWithSynonyms(['poursuite'], map);
  assert.deepEqual(new Set(result), new Set(['poursuite', 'chasse', 'traque']));
});

test('expandWithSynonyms : un token membre (pas la clé) ajoute aussi tout le groupe, y compris la clé', () => {
  const map = { poursuite: ['poursuite', 'chasse', 'traque'] };
  const result = expandWithSynonyms(['chasse'], map);
  assert.deepEqual(new Set(result), new Set(['chasse', 'poursuite', 'traque']));
});

test('expandWithSynonyms : un token déjà présent dans le résultat n\'est pas dupliqué', () => {
  const map = { poursuite: ['poursuite', 'chasse'] };
  const result = expandWithSynonyms(['poursuite', 'chasse'], map);
  assert.equal(result.length, new Set(result).size, 'pas de doublon');
  assert.deepEqual(new Set(result), new Set(['poursuite', 'chasse']));
});

test('expandWithSynonyms : un token sans groupe reste inchangé (pas ajouté, pas retiré)', () => {
  const map = { poursuite: ['poursuite', 'chasse'] };
  const result = expandWithSynonyms(['zorglub'], map);
  assert.deepEqual(result, ['zorglub']);
});

test('expandWithSynonyms : le résultat est toujours un sur-ensemble strict-ou-égal des tokens d\'entrée', () => {
  const map = { poursuite: ['poursuite', 'chasse', 'traque'], garde: ['garde', 'sentinelle'] };
  const input = ['chasse', 'inconnu', 'garde'];
  const result = new Set(expandWithSynonyms(input, map));
  for (const t of input) assert.ok(result.has(t), `${t} doit rester présent`);
});

test('expandWithSynonyms : synonymMap vide ou absent -> tokens inchangés (aucune expansion)', () => {
  assert.deepEqual(expandWithSynonyms(['poursuite'], {}), ['poursuite']);
  assert.deepEqual(expandWithSynonyms(['poursuite'], null), ['poursuite']);
  assert.deepEqual(expandWithSynonyms(['poursuite'], undefined), ['poursuite']);
});

// ---------- non-régression : fichier synonymes absent/invalide ----------

test('search() avec synonymsPath pointant vers un fichier absent -> comportement identique à avant (pas de crash, pas d\'expansion)', () => {
  const query = 'zone de controle qui bloque un deplacement';
  const withMissing = search(query, catalog, { synonymsPath: resolve(__dirname, 'does_not_exist_synonyms.json') });
  const withoutOption = search(query, catalog, { synonymsPath: resolve(__dirname, 'does_not_exist_synonyms.json') });
  assert.deepEqual(
    withMissing.map((r) => r.entry.brick_id ?? r.entry.asset_id ?? r.entry.role_id),
    withoutOption.map((r) => r.entry.brick_id ?? r.entry.asset_id ?? r.entry.role_id)
  );
});

test('search() avec synonymsPath pointant vers un JSON invalide -> pas de crash, résultats identiques à un fichier absent', () => {
  const query = 'ennemi qui poursuit';
  const invalidPath = resolve(__dirname, 'search.mjs'); // fichier existant mais pas du JSON valide
  const withInvalid = search(query, catalog, { synonymsPath: invalidPath });
  const withMissing = search(query, catalog, { synonymsPath: resolve(__dirname, 'does_not_exist_synonyms.json') });
  assert.deepEqual(
    withInvalid.map((r) => r.entry.brick_id),
    withMissing.map((r) => r.entry.brick_id)
  );
});

// ---------- preuve concrète : "poursuite" élargi trouve des briques ratées sans synonymes ----------

test('preuve AVANT/APRÈS : "monstre qui chasse le heros sur la grille" trouve DAVANTAGE de briques avec expansion synonymes qu\'ans (sur le vrai catalogue)', () => {
  const query = 'monstre qui chasse le heros sur la grille';
  const before = search(query, catalog, { synonymsPath: resolve(__dirname, 'does_not_exist_synonyms.json') });
  const after = search(query, catalog); // synonyms.json réel, chargé par défaut

  const beforeIds = new Set(before.map((r) => r.entry.brick_id));
  const afterIds = new Set(after.map((r) => r.entry.brick_id));

  // sur-ensemble : rien perdu par l'expansion
  for (const id of beforeIds) assert.ok(afterIds.has(id), `${id} présent avant doit rester présent après`);

  // différence mesurée et non vide : au moins une brique nouvelle apparaît grâce aux synonymes
  const newlyFound = [...afterIds].filter((id) => !beforeIds.has(id));
  assert.ok(newlyFound.length > 0, 'l\'expansion synonymes doit faire apparaître au moins une nouvelle brique');
  assert.ok(afterIds.has('sys-pursuer-continuous'), 'sys-pursuer-continuous (poursuite vectorielle) doit être trouvé via le synonyme "chasse"');
});

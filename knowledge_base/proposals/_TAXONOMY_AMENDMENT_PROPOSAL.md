# Amendement de taxonomie KB — provenance interne (leçons Forge) vs provenance externe (R3)

- **Statut** : **RATIFIÉ (option 1) ET IMPLÉMENTÉ** — décision Pierre 2026-08-02
  (message « MISSION — Implémentation amendement KB provenance interne »).
  Implémentation : `knowledge_base/kb-validate.mjs` v4 (`isProvenanceInternal`,
  schéma fermé ; R3 = exactement une provenance, externe XOR interne) +
  `scripts/forge/kb_proposal.py` (entrées générées avec `provenance_internal`).
  Preuves : catalogue réel PASS 32/32 inchangé · apply sur copie PASS 33 entrées ·
  rollback sur proposition corrompue prouvé · propositions réelles toujours
  PROPOSED (l'application reste un geste Pierre, une commande par leçon).
  Le reste du document est conservé tel quel comme trace de la décision.
- **Décideur** : Pierre
- **Date** : 2026-08-02 (proposition et ratification le même jour)
- **Provenance de ce constat** :
  - Drift Observer : `lecon_routee_sans_consommateur` (x5) — voir `studio_brain/planning/planning.yaml`, tâche `P0-boucle-lessons-kb`.
  - Directive Pierre verbatim (citée dans `scripts/forge/kb_proposal.py:4-6`) : « Créer le vrai cycle : Playtest -> Observer -> Lesson candidate -> Validation humaine -> KB proposal -> KB update -> Nouvelle construction. Pas d'écriture automatique. Mais le chemin doit exister. »
  - `scripts/forge/kb_proposal.py` (module livré, propose-only, jamais commité au catalogue) implémente `--generate` et documente déjà — avant même l'échec réel — la limite décrite ici (docstring `_lesson_to_pattern_entry`, lignes 152-167).

---

## 1. Constat

Le validateur `knowledge_base/kb-validate.mjs` impose, pour tout brick de `kind: "pattern"` :

```
knowledge_base/kb-validate.mjs:445
  if (e.provenance_url === null) err(id, "R3", "provenance_url obligatoire pour un pattern (citation verifiable)");

knowledge_base/kb-validate.mjs:448
  if (e.provenance_url !== null && !URL_RE.test(e.provenance_url)) err(id, "R3", "provenance_url doit etre http(s)");
```

où `URL_RE = /^https?:\/\/.+/` (`knowledge_base/kb-validate.mjs:48`).

Un pattern déjà admis dans le catalogue respecte cette règle avec une **URL externe réelle**, ex. :

```
knowledge_base/catalog.json:134-138
  "brick_id": "pat-damage-floor",
  "kind": "pattern",
  "source": "Battle for Wesnoth — CombatMechanics (concept cite, zero code)",
  "provenance_url": "https://wiki.wesnoth.org/CombatMechanics",
```

Les 5 propositions générées par `scripts/forge/kb_proposal.py --generate` (`knowledge_base/proposals/forge.*.yaml`) sont, elles, structurellement différentes : chacune vient d'une leçon Forge `validated` dans `lab/reports/lessons.jsonl` (schéma `forge.lesson.v1` : `lesson_id`, `statement`, `status`, `supporting_runs`, `caused_by`, `evidence_count`…). C'est une **observation de processus interne**, pas une citation d'une source externe — il n'existe pas d'URL à citer. Les 5 propositions portent toutes `provenance_url: null` (ex. `knowledge_base/proposals/forge.timeout_greenfield_by_profile.yaml`), et échoueraient donc R3 telles quelles au moment de `--apply`.

Le module producteur lui-même documente ce trou par anticipation, sans le corriger (extrait) :

```
scripts/forge/kb_proposal.py:157-167
  Limite honnete, ASSUMEE et non corrigee ici : un pattern deja present dans le
  catalogue (ex. pat-damage-floor) cite une source EXTERNE avec un
  provenance_url http(s) verifiable — R3 de kb-validate.mjs l'exige pour tout
  brick de kind=pattern. Une Lesson Forge est une observation INTERNE issue de
  runs du studio : elle n'a structurellement pas de citation externe verifiable.
  `provenance_url` est donc laisse a `None` ici — ce qui fait echouer R3 au
  moment de --apply, DELIBEREMENT : c'est le validateur, pas ce module, qui doit
  trancher qu'une proposition manque de provenance, et Pierre qui doit ensuite
  decider (fournir une reference reelle, ou juger que cette lecon ne releve pas
  de cette taxonomie).
```

Conclusion du constat : **la taxonomie R3 a été conçue pour la connaissance importée** (pattern cité depuis une source externe, GPL-safe, advisory) et n'a **jamais prévu** la connaissance produite en interne par le studio lui-même (leçon Forge validée par un humain). Ce n'est pas un bug du validateur — c'est un angle mort de conception, maintenant réel (5/5 propositions bloquées).

---

## 2. Option 1 (recommandée) — provenance interne légitime, champ dédié

### 2.1 Le champ

Ajouter à `BRICK_SPEC` une alternative **explicite et structurée** à `provenance_url`, réservée au cas où la provenance est interne au studio :

```
provenance_internal: {
  lessons_source: string,       // ex. "lab/reports/lessons.jsonl"
  lesson_id: string,             // ex. "forge.timeout_greenfield_by_profile"
  supporting_runs: string[],     // non vide — ex. ["breakout_v2-run1-20260731-082705"]
}
```

Nullable par défaut (`v === null || isProvenanceInternal(v)`), au même régime que `provenance_url` aujourd'hui. Exactement un des deux doit être renseigné pour un pattern (voir diff R3 ci-dessous) — jamais les deux, jamais aucun.

Pourquoi cette forme et pas une simple chaîne libre : le studio a déjà tranché ce principe ailleurs (mémoire `structured_field_not_comment` — « toute donnée qui influence un comportement doit avoir un champ structuré validé, pas un commentaire »). `supporting_runs[]` non vide rend la provenance interne **vérifiable mécaniquement** — le validateur peut (dans un futur incrément, hors scope ici) confirmer que `lesson_id` existe réellement dans `lab/reports/lessons.jsonl` avec `status: "validated"`, symétrique de la garde de chemin déjà appliquée à `path`/`proof_of_use`.

### 2.2 Pseudo-diff PROPOSÉ sur `knowledge_base/kb-validate.mjs` (non appliqué)

```diff
@@ helpers de typage (~ligne 208, à côté de isLearnedFrom)
+// Provenance INTERNE (amendement R3 proposé) : une leçon Forge validée par un
+// humain (lab/reports/lessons.jsonl, forge.learning_memory) n'a structurellement
+// pas de citation externe. Schéma fermé à 3 clés, supporting_runs non vide —
+// vérifiable mécaniquement (même patron que isLearnedFrom).
+function isProvenanceInternal(v) {
+  return isPlainObj(v) && isStr(v.lessons_source) && isStr(v.lesson_id)
+    && isNonEmptyStrArr(v.supporting_runs) && Object.keys(v).length === 3;
+}

@@ BRICK_SPEC (~ligne 277)
   provenance_url: (v) => v === null || isStr(v),
+  provenance_internal: optional((v) => v === null || isProvenanceInternal(v)),
   license: isStr,

@@ validateBrick, bloc kind === "pattern" (~ligne 442, remplace les 2 lignes R3 existantes)
   if (e.kind === "pattern") {
     if (KNOWN_SPDX.includes(e.license) && !PATTERN_LICENSES.includes(e.license)) err(id, "R5", ...);
     if (e.advisory_only !== true) err(id, "R5", ...);
-    if (e.provenance_url === null) err(id, "R3", "provenance_url obligatoire pour un pattern (citation verifiable)");
+    const hasExternal = e.provenance_url !== null;
+    const hasInternal = e.provenance_internal != null;
+    if (!hasExternal && !hasInternal) {
+      err(id, "R3", "provenance obligatoire pour un pattern : provenance_url (citation externe) OU provenance_internal (lesson Forge validee)");
+    }
+    if (hasExternal && hasInternal) {
+      err(id, "R3", "provenance ambigue : provenance_url ET provenance_internal renseignes, un seul autorise");
+    }
     if (e.path !== null && !e.path.endsWith(".md")) err(id, "R5", ...);
   }
   if (e.provenance_url !== null && !URL_RE.test(e.provenance_url)) err(id, "R3", "provenance_url doit etre http(s)");
```

Points de conception à valider par Pierre en même temps que le champ :
- `optional(...)` place `provenance_internal` dans le régime déjà utilisé pour `usage_examples`/`learned_from` (absent ≠ erreur R1 ; présent = type-vérifié) — aucune des ~11 entrées `pattern` existantes du catalogue n'est affectée (elles gardent `provenance_url`, `hasInternal` reste `false`).
- La garde XOR (`hasExternal && hasInternal` → rejet) empêche une brique de revendiquer les deux provenances à la fois, ce qui préserverait la lisibilité de la distinction importé/produit voulue par le README (« Mémoire de production… **ingestion**… de composants **open source existants** »).
- Hors scope de ce diff (à discuter séparément si retenu) : une vérification disque de `lesson_id` contre `lab/reports/lessons.jsonl` (même patron que `guardedPath`) — actuellement le champ est structuré mais pas encore recoupé avec le fichier source. Sans cet incrément, `provenance_internal` reste une déclaration typée mais non contre-vérifiée automatiquement (à noter comme dette si l'option est ratifiée).

### 2.3 Impact chiffré sur les 5 propositions existantes

| Proposition (`knowledge_base/proposals/*.yaml`) | R3 aujourd'hui | R3 avec le diff proposé |
|---|---|---|
| `forge.forge_oracle_convention_undocumented.yaml` | REJET (provenance_url null) | PASS si `provenance_internal` renseigné (lesson_id + 1 supporting_run présents dans la proposition) |
| `forge.oracle_fail_vs_not_measured_marker.yaml` | REJET | PASS (idem) |
| `forge.preflight_oracle_registration.yaml` | REJET | PASS (idem) |
| `forge.timeout_greenfield_by_profile.yaml` | REJET | PASS (idem) |
| `forge.wiremap_concept_reuse_requalification.yaml` | REJET | PASS (idem) |

**5/5 propositions bloquées aujourd'hui → 5/5 débloquées** avec le diff, à condition que `scripts/forge/kb_proposal.py::_lesson_to_pattern_entry` soit aussi modifié (hors scope de ce document, changement séparé et ratifié séparément) pour peupler `provenance_internal` au lieu de laisser `provenance_url: null` sans alternative. Chaque proposition dispose déjà des données nécessaires — le bloc `provenance:` de chaque YAML porte `lessons_source`, `lesson_id` (implicite = nom du fichier) et `supporting_runs` (ex. `forge.timeout_greenfield_by_profile.yaml` → `supporting_runs: [breakout_v2-run1-20260731-082705]`) : aucune donnée manquante, seulement un champ catalogue à mapper.

### 2.4 Invariants préservés

- **`advisory_only: true`** reste obligatoire pour tout pattern (R5, inchangé) — une leçon promue au catalogue reste **citée, jamais injectée comme code**, identique au régime des patterns externes.
- **Tier `candidate`** par défaut, inchangé — aucune leçon ne devient `validated` par ce diff seul ; `validated` continue d'exiger `proof_of_use` (R8, inchangé).
- **Le validateur reste seul juge.** Le diff ajoute une règle mécanique de plus (schéma fermé, XOR vérifié) ; aucune décision de conformité n'est déplacée vers `kb_proposal.py` ou vers un jugement humain non outillé. `--apply` continue d'invoquer le VRAI `kb-validate.mjs` après écriture et de restaurer sur échec (`scripts/forge/kb_proposal.py:318-346`).
- **Propose-only inchangé** : ce diff ne touche ni `--apply`, ni le geste d'écriture, ni `--ratifie-par` — seule la définition de conformité R3 change, la porte (Pierre ratifie chaque application) reste identique.

---

## 3. Option 2 — statu quo (ne pas amender R3)

Si R3 reste tel quel, chaque leçon Forge candidate à la promotion catalogue doit se voir attribuer une **référence externe réelle** avant `--apply` :

- **Qui la fournit** : Pierre (ou un red-team de recherche, ex. skill `world-scan`), au cas par cas, pour chacune des 5 (et de toute future) leçon — aucun mécanisme automatique du studio ne peut inventer une URL externe crédible pour une observation de processus interne (ex. « le timeout par défaut de 1800s est insuffisant pour un greenfield Godot » n'a pas de source Wesnoth/SPD équivalente).
- **Coût** : recherche manuelle par leçon, sans garantie qu'une source externe pertinente existe (ces leçons documentent des défauts du pipeline Forge lui-même, pas des mécaniques de jeu génériques) ; risque de citation forcée/artificielle juste pour satisfaire R3, ce qui dégraderait la valeur de la citation pour les patterns réellement importés.
- **Alternative de repli déjà visible dans le code** : `kb_proposal.py` documente explicitement que Pierre peut aussi juger qu'« cette leçon ne relève pas de cette taxonomie » (ligne 165-166) — c'est-à-dire refuser certaines des 5 propositions plutôt que les forcer dans le moule pattern. Cela laisse le drift `lecon_routee_sans_consommateur` partiellement non résorbé par choix assumé, pas par défaut technique.
- Aucune modification de `kb-validate.mjs` n'est nécessaire dans cette option — statu quo strict.

---

## 4. Critère de décision + preuve de fin

Reprend la preuve de fin déjà ratifiée pour `P0-boucle-lessons-kb` (`studio_brain/planning/planning.yaml:25`) :

> « le bloc retour KB passe ACTIF dans Observer : une leçon validée produit une proposition KB datée, et après ratification une entrée catalogue reliée au projet ; le drift `lecon_routee_sans_consommateur` tombe à 0 »

Concrètement, si Option 1 est ratifiée puis implémentée (diff appliqué + `_lesson_to_pattern_entry` mis à jour) :
1. `node knowledge_base/kb-validate.mjs knowledge_base/catalog.json` reste `VERDICT CATALOGUE: PASS` sur le catalogue actuel (aucune entrée existante affectée — `provenance_internal` absent partout ailleurs).
2. Pour au moins une des 5 propositions, `kb_proposal.py --apply <lesson_id> --ratifie-par "Pierre"` insère l'entrée et le validateur repasse **PASS** au lieu du REJET R3 actuel.
3. Le compteur du drift `lecon_routee_sans_consommateur` (Observer) redescend en fonction du nombre de propositions effectivement appliquées — 0 si les 5 sont ratifiées et appliquées.

Si Option 2 est retenue : la preuve de fin ci-dessus ne peut être atteinte que leçon par leçon, au rythme où une provenance externe est trouvée et fournie par Pierre — pas de mécanisme studio pour l'accélérer.

---

## 5. Ce que ce document NE fait PAS

Aucun fichier `kb-validate.mjs` ni `catalog.json` n'a été modifié : R3 reste, dans le validateur réel, exactement ce qu'il était en §1 — toute proposition continue d'échouer `--apply` sur `provenance_url: null`. Ce document est une proposition de décision, à ratifier ou rejeter explicitement par Pierre avant toute implémentation du diff §2.2.

---

## 6. Delta V2 (2026-08-02) — `knowledge_source` explicite dans la proposition, avant même l'implémentation du diff

Delta ratifié Pierre, appliqué à `scripts/forge/kb_proposal.py` et régénéré dans les 5 `knowledge_base/proposals/forge.*.yaml` (le document ci-dessus, §1 à §5, reste la décision de fond à trancher — ce delta ne la préempte pas, il enrichit ce que la proposition **déclare** en attendant).

### 6.1 Constat du delta

Le champ `provenance_internal{lessons_source, lesson_id, supporting_runs}` décrit en §2.1 est correct mais minimal : il ne dit rien de la **confiance** qu'on peut accorder à une leçon interne, ni de son **origine causale** (quel échec ou quelle expérience l'a produite), ni de la distinction entre le **constat** et un éventuel **résultat observé** séparé. Pour qu'un futur lecteur humain (ou un futur incrément mécanique de `kb-validate.mjs`) puisse juger une leçon interne aussi vite qu'un pattern externe cité par URL, la proposition doit porter ces signaux — dérivés mécaniquement des champs déjà écrits par `forge.learning_memory`, jamais inventés.

### 6.2 Schéma élargi (implémenté dans `kb_proposal.py`, EN PLUS de l'existant — compat descendante)

```
knowledge_source: external_reference | internal_lesson   # enum ferme, KNOWLEDGE_SOURCE_* dans kb_proposal.py
internal_lesson:                                          # present ssi knowledge_source == internal_lesson
  lesson_id: string
  supporting_runs: string[]
  origine: string          # depuis caused_by.failure_id (prefere) ou caused_by.experience — jamais invente
  confiance: unique | recurrente | forte | non_validee     # derive mecaniquement, JAMAIS un score
  resultat_observe:
    valeur: string          # = statement si la lecon ne porte pas de resultat distinct (cas actuel des 5)
    note: string             # rend visible que valeur == constat, ne le masque pas
```

`knowledge_source` et `internal_lesson` ne remplacent PAS `provenance_internal` proposé en §2.1 pour le validateur — ce sont deux vocabulaires pour la même intention (l'un `entree_catalogue_proposee` côté génération, l'autre `provenance_internal` côté `BRICK_SPEC` si §2.2 est un jour appliqué). Si Option 1 est ratifiée, l'implémentation devra choisir *un* nom canonique pour le champ côté catalogue — décision Pierre, hors scope de ce delta qui ne touche que la proposition, jamais le validateur ni le catalogue.

### 6.3 Règle de dérivation de `confiance` (jamais un score inventé)

Implémentée dans `_confidence_level_from_lesson` (`scripts/forge/kb_proposal.py`) : `status != validated` → `non_validee` ; sinon `len(supporting_runs)` : 1 → `unique`, 2-3 → `recurrente`, ≥4 → `forte`. Avec les 5 leçons `breakout_v2` actuelles (1 `supporting_run` chacune), les 5 valent `unique` — pas de variance artificielle inventée pour faire joli ; la règle est écrite pour varier dès qu'une leçon accumule plusieurs runs (transition `validated` → `weakened` avec `add_supporting_run` répété côté `forge.learning_memory`).

### 6.4 Ce que ce delta NE fait PAS

- Ne modifie ni `kb-validate.mjs` ni `catalog.json` — R3 rejette toujours `provenance_url: null` exactement comme en §1, testé et confirmé (voir preuve de mission, `--apply` sur copie hors dépôt, rejet R3 inchangé, catalogue restauré).
- N'ouvre aucune nouvelle voie de PASS pour `--apply` : `knowledge_source`/`internal_lesson` sont des champs supplémentaires sur l'objet proposé, ignorés par le validateur réel tant que §2.2 n'est pas appliqué.
- Ne tranche pas Option 1 vs Option 2 (§2 vs §3) — ce delta rend la proposition plus lisible/complète en attendant la décision, il ne la présuppose pas.

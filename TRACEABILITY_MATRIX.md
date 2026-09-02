# MATRICE DE TRAÇABILITÉ CIBLE — v0.1

*2026-09-01 · DOCUMENTED_ONLY · aucun code, aucun renommage, aucun déplacement.
Dépôt source `feeb29cb`, non touché.*

---

## 1 · Vérification mécanique de F1 — **concluante**

> *Toutes les informations nécessaires à l'Architecte peuvent-elles être exprimées dans
> `GAME_BLUEPRINT.game_flow` sans dupliquer `FEATURE_MAP`, `charter` ou `ARCHITECTURE_CONTRACT` ?*

### Ce que chaque objet porte réellement — mesuré

| objet | clés réelles | nature |
|---|---|---|
| `FEATURE_MAP` | `systemes · features · capacites · id · capacite · source_ref · expected_proof{kind,statement}` | **arbre**, hiérarchie |
| `charter.yaml` | `objectif · reference_jeu · plateforme_cible · criteres_succes · criteres_demo · hors_scope · actions_interdites` | **intention et bornes** |
| `ARCHITECTURE_CONTRACT` | `modules · deps_interdites · ownership · responsabilites` | **interdictions statiques** |
| `loop.json` | `steps[{role, ref, repeat, observe{hud,predicate}}]` — rôles : `PLAYER_GOAL · PLAYER_ACTION · GAME_RESPONSE · REWARD · DECISION · UNLOCK · NEXT_GOAL · REPEAT · META_LOOP · ADVANTAGE` | **script d'observation** dérivé de `prisme.json` |

### Le test de duplication
```
clés de RELATION dans featuremap.json (depend/trigger/emit/cause/after/flow/edge…) : AUCUNE
```
`FEATURE_MAP` est une **hiérarchie sans arêtes**. Elle dit *ce qui doit exister*, jamais
*qui déclenche quoi*. `ARCHITECTURE_CONTRACT` porte `deps_interdites` — des **interdictions
statiques** (`economy ↛ render`), pas des déclenchements. `charter` porte l'intention et les
bornes, aucune mécanique.

### Le seul recouvrement réel — et il est de nature différente
`loop.json` ressemble à un flux, mais :
- sa **grammaire est fermée et générique** (10 rôles applicables à tout jeu) — là où le flux
  demandé est spécifique : `TOWER_DETECTS`, `TOWER_ATTACKS`, `DAMAGE`, `DEATH` ;
- il porte `observe: {hud, predicate}` — de **l'observabilité pour un bot**, pas de l'architecture ;
- c'est une **projection déterministe** de `prisme.json` sous verrou anti-écriture LLM : un
  *dérivé*, jamais un *flux conçu*.

Recouvrement partiel assumé sur `REWARD` et `DECISION`. Il ne justifie pas une fusion : l'un
**prouve qu'une boucle existe**, l'autre **dit ce que l'architecture doit supporter**.

### Ce que seul `game_flow` porterait
| information dont l'Architecte a besoin | porté aujourd'hui par |
|---|---|
| quels systèmes existent | `FEATURE_MAP` ✔ |
| pourquoi, invariants, hors_scope | `charter` ✔ |
| contraintes de dépôt | `repo_map` ✔ |
| connaissance externe advisory | `knowledge_packet` ✔ |
| **qui déclenche quoi** | **personne** |
| **quel effet produit quel état** | **personne** |
| **où le joueur reprend la main** | **personne** |

> **F1 est validée mécaniquement** : `game_flow` décrit des **interactions**, pas une procédure de
> fabrication. Aucun des quatre objets ne les porte. Elle devient une **section du
> `GAME_BLUEPRINT`**, lue par l'Architecte via `mandatory_read` — **aucun nouveau maillon**.

Les quatre niveaux deviennent nettement séparés :
```
game_flow            quels comportements l'architecture doit-elle supporter ?
FEATURE_MAP          quelles fonctionnalités doivent exister ?
ARCHITECTURE_CONTRACT comment sont-elles organisées techniquement ?
WIREMAP              où sont-elles réellement implémentées ?
```

---

## 2 · Matrice de traçabilité

`R` = droit de lecture · `A` = droit d'amendement · **notification** = qui est prévenu quand
l'information change.

| information | producteur | consommateurs | R | A | notification | preuve attendue | preuve réelle |
|---|---|---|---|---|---|---|---|
| **vision** | **Pierre** | tous | tous | **Pierre seul** | tous — invalide les décisions dérivées | — | reformulation confirmée par Pierre |
| **charter / intention** *(objectif · criteres_succes · hors_scope · actions_interdites)* | Gameplay sous Fable | Architect, Build, QA | tous | Gameplay ; Fable arbitre | Architect, Feature Map | `criteres_succes` mesurables | `check_charter` (advisory aujourd'hui) |
| **research / genre_context** | Research | Fable, design | tous | Research | design | sources citées, non fabriquées | `provenance` par champ, source absente = FAIL |
| **understanding / prisme** | Prisme | Feature Map, design | tous | Prisme | Feature Map | exigences identifiées `E1..En` | `check_prisme.mjs` |
| **gameplay** | Gameplay | UX, Systems, Architect | tous | Gameplay | UX, Systems, Architect, Feature Map | — | couverture par `FEATURE_MAP` |
| **systems / economy** | System Design | Build, QA | tous | System Design | Gameplay, UX, QA | projection déterministe reproductible | `economy.json` = sha256 identique à `03_WORLD/economy.json` |
| **ux** | UX | Gameplay, Art, Architect, QA | tous | UX | Gameplay, Art, Architect | affordances lisibles | **NOT_FOUND — aucun oracle UX** |
| **art_direction** | Art | Build, QA visuelle | tous | Art | Tech, UX | `art_bible` complète | `check_artbible.mjs` · `check_art_response.mjs` |
| **design_metrics** *(cibles)* | **Pierre** | design, QA | tous | **Pierre seul** — Systems propose des *valeurs* | design, QA | **variance prouvée** ≥2 valeurs distinctes | **NOT_FOUND — la boucle n'existe pas** |
| **game_flow** | Design / System | **Architect**, QA | tous | Design | Architect, QA | chaque transition atteignable | **NOT_FOUND — objet à définir (F1)** |
| **feature_map** | Design *(fonction, plus étape)* | Architect, Build, QA | tous | dérivé — jamais saisi | Architect | **couverture bidirectionnelle** : toute exigence → une unité ; toute unité → une exigence | `check_decompo.mjs` — règle dure `source_ref` |
| **ARCHITECTURE_CONTRACT** | Architect | Build, Wiremap | tous | Architect | Build, Gameplay, Art | `deps_interdites` respectées | `s10b-oracle-archi` |
| **wiremap** | Architect / Build | QA, Evidence | tous | dérivé du build | QA | chaque entrée porte `fonction · fichiers · preuve · statut` | `s10c-oracle-wiremap` · `check_wiremap_contract.mjs` |
| **jeu réel** | Build workers | QA, Human | — | personne après build | QA, Red Team | le jeu démarre et se joue | oracles produit + capture GPU |
| **expected_proof** | Feature Map | QA, Evidence | tous | dérivé | QA | déclarée par unité `{kind, statement}` | présente dans `featuremap.json` |
| **actual_proof** | QA / oracles | Evidence, Fable, Human | tous | **personne** — append-only | Fable | reçu d'oracle **vérifié** | `verdict.json` signé HMAC, `verify_run` → `AUTHENTIQUE` |
| **decisions** | **Fable seul** | tous | tous | Fable | tous | quoi · pourquoi · qui · quand | **NOT_FOUND — `decision-log` absent du V2** |
| **objections** | toute capacité | Fable, Human | tous | l'auteur ; **jamais effacée** | Fable | conservée même rejetée | `HUMANGATE_READY_WITH_OBJECTION` |
| **questions** | toute capacité | destinataire, Fable | tous | l'auteur, jusqu'à réponse | destinataire | **freeze interdit si ouverte** | `design_questions.json` (matérialisé au RUN 1) |

### Le trou de traçabilité, en une ligne
```
expected_proof  (featuremap, 26 ids)  ⟷  actual_proof  (wiremap, 25 entrées)
                        intersection : 0
```
**C'est le seul endroit de la matrice où deux colonnes voisines ne se rejoignent pas.**

---

## 3 · Q4 — la notification, mécanisme prioritaire

Tu as raison de la mettre devant : **11 objets sur 18 exigent une communication dynamique**, et la
colonne *notification* de la matrice ci-dessus est aujourd'hui **vide en pratique**. Aucun mécanisme
ne prévient qui que ce soit quand une section change.

### Ce qui existe déjà, mesuré
| pièce | ce qu'elle fait | ce qui lui manque pour être une notification |
|---|---|---|
| `design_questions.json` | transporte une question adressée, avec sa raison | ne prévient personne — il faut le lire |
| objections dans les verdicts | conservées, même rejetées | en fin de chaîne seulement |
| `context_manifest` | empreinte sha256 des artefacts injectés | détecte le changement, **n'en informe personne** |
| `reference_guard` | 349 diffs/run | **0 consommateur de décision** — le contre-exemple parfait |

### Trois formes possibles — non tranchées
| # | forme | coût | risque |
|---|---|---|---|
| **N1** | **discipline du Director** : Fable relit le Blueprint entre deux convocations et décide qui rappeler | ~0 — aucun mécanisme | dépend de l'attention d'un agent ; non vérifiable |
| **N2** | **journal d'amendements** : chaque écriture inscrit `auteur · section · raison · horodatage` ; une capacité convoquée lit les amendements depuis sa dernière intervention | faible — un fichier append-only, patron déjà utilisé (`RUN_INDEX`) | il faut définir « depuis ma dernière intervention » |
| **N3** | **graphe de dépendances entre sections** : `gameplay → {ux, systems, architecture}` ; un amendement notifie mécaniquement les dépendants | moyen — le graphe doit être maintenu | un graphe faux notifie mal ; devient une seconde source de vérité |

**Ce que la mesure suggère** : `reference_guard` est l'avertissement à ne pas oublier — un capteur
sans consommateur produit 349 diffs par run que personne ne lit. **Une notification sans obligation
de lecture est le même piège.** Ce qui rend N2 supérieur à N1 n'est pas le mécanisme, c'est que
la lecture devienne une **précondition de la convocation** — le patron `mandatory_read` existe déjà
et est une *précondition dure*.

> Proposition : **N2**, et le rendre obligatoire via `mandatory_read` — la seule pièce qui, dans ce
> studio, force effectivement une lecture. À trancher.

---

## 4 · État des questions

| # | question | état |
|---|---|---|
| **Q1** | forme de `game_flow` | **RÉSOLUE — F1**, vérifiée mécaniquement (§1) |
| **Q4** | notification | **prioritaire** — N1/N2/N3 posés, non tranchée |
| Q2 | verrou *« World Scan hors périmètre »* + R8 vs Research systématique | ouverte — **non levé** |
| Q3 | qui prouve la variance d'une `design_metric` | ouverte |
| Q5 | qui décide du prochain jeu (rail = catalogue) | ouverte |

```
status_by_surface:
  f1_verification:        TESTED       # clés réelles des 4 objets, 0 clé de relation dans featuremap
  traceability_matrix:    DOCUMENTED_ONLY
  notification_options:   DOCUMENTED_ONLY
  expected_actual_join:   NOT_FOUND
  ux_oracle:              NOT_FOUND
  metrics_loop:           NOT_FOUND
  decision_log:           NOT_FOUND
  implementation:         BLOCKED
```
`software_verdict: OK` (document) · `evidence_verdict: MECHANICAL_VALIDATION_ONLY` ·
`claim_verdict: NO_CLAIM_ALLOWED` · `no_global_ready_verdict: true`

# TARGET INTERACTION MODEL — comment la Forge circule

*2026-09-01 · **DOCUMENTED_ONLY** · aucun code, aucun déplacement, aucune suppression, aucun
renommage. Dépôt source à `feeb29cb`, non touché.*

`FORGE_TARGET_MODEL` + `CAPABILITY_MAP` + `UNKNOWN_RESOLUTION` + **`TARGET_INTERACTION_MODEL`**.
Ce document définit **les liaisons**, pas les composants.

---

## Décision 1 — nommage des objets centraux *(figée)*

```
GAME_BLUEPRINT          la vision / le design du jeu — l'objet central, vivant
ARCHITECTURE_CONTRACT   ex-`blueprint.json` (s4-archi) : modules · deps_interdites
                        · ownership · responsabilites — vérifié par s10b-oracle-archi
```
Deux objets, deux noms. Les laisser cohabiter sous « blueprint » recréerait la confusion
conceptuelle qu'on retire. *(Renommage non exécuté — décision enregistrée.)*

## Décision 3 — quatre boucles, aucun ordre interne

```
UNDERSTAND ──▶ DESIGN ──▶ BUILD ──▶ PROVE ──▶ HUMAN ──▶ REWORK ──▶ FABLE
                 │                                                    ▲
                 │  aucun ordre obligatoire à l'intérieur             │
                 └── Gameplay · Systems · UX · Art · Narrative ───────┘
                     Research · Prisme
```
L'architecture technique n'est pas « l'étape 4 » : elle intervient quand le Build Orchestrator
doit transformer le design en structure.

---

# Les huit liaisons

Chacune répond aux six questions : **quoi est transmis · qui en est propriétaire · qui peut
modifier quoi · comment les autres sont informés · ce qui déclenche une réévaluation · ce qui
constitue une convergence.**

---

## L1 · `HUMAN → FABLE`

| | |
|---|---|
| **transmis** | une **vision** : fantasy, expérience visée, audience, sensation recherchée · les `must_not_have` · le scope et le budget · les **cibles** de `design_metrics` |
| **propriétaire** | **Pierre**, exclusivement |
| **qui modifie quoi** | Pierre seul écrit `vision`, `constraints.must_not_have`, `scope`, et **pose** les cibles métriques. Fable ne les amende jamais — il peut seulement **objecter** |
| **information des autres** | l'entrée crée ou met à jour le `GAME_BLUEPRINT` ; toute capacité lit la même version |
| **déclenche une réévaluation** | toute modification de `vision` ou `must_not_have` **invalide les décisions dérivées** et force Fable à re-convoquer les capacités concernées |
| **convergence** | Fable a reformulé l'intention et Pierre a confirmé que la reformulation est fidèle. Pas de vote, pas de score — une confirmation |
| **existe déjà** | `FORGE_PROJECT_INPUT_V0` : entrée canonique unique ratifiée, `provenance` par champ (source absente = FAIL), **entrées alternatives interdites**, pré-vol fail-closed **avant toute dépense LLM** |
| **manque** | les sections `design_metrics`, `art`, `ux`, `technical` ; et le Brief est figé à l'entrée alors que le Blueprint doit rester vivant |

## L2 · `FABLE → CAPABILITY`

| | |
|---|---|
| **transmis** | une **convocation** : la capacité demandée, la question posée, la portion du Blueprint concernée, les contraintes qui s'appliquent |
| **propriétaire** | **Fable** — lui seul convoque |
| **qui modifie quoi** | Fable n'écrit rien dans la section de la capacité ; il fixe l'objet de la demande |
| **information des autres** | la convocation est **visible** : les autres capacités savent qui a été appelé et sur quelle question |
| **déclenche une réévaluation** | un manque de connaissance (→ Research), une contradiction (→ Red Team), un changement de section amont (→ les capacités qui en dépendent) |
| **convergence** | la capacité a rendu son amendement **ou** a rendu une question — jamais un silence |
| **existe déjà** | `prepare_dispatch` valide et **enregistre** ; la porte `hook_guard.check_spawn` autorise si et seulement si `count == 1` dispatch enregistré. **Invariant mesuré : un spawn ⇔ exactement un dispatch — pas « il existe un YAML »** ⇒ la composition dynamique est **nativement compatible** |
| **manque** | la composition elle-même : aujourd'hui `self.order = order_for_profile(profile)`, un humain choisit un profil |

## L3 · `CAPABILITY ↔ CAPABILITY` — **la liaison qui fait la différence**

| | |
|---|---|
| **transmis** | trois formes, jamais autre chose : **amendement** (je modifie ma section) · **question** (j'ai besoin d'une décision d'un autre) · **objection** (je conteste une décision) |
| **propriétaire** | chaque capacité possède **sa** section du Blueprint et rien d'autre |
| **qui modifie quoi** | Gameplay écrit `gameplay` · Systems écrit `systems` · UX écrit `ux` · Art écrit `art` · Tech écrit `technical` et `ARCHITECTURE_CONTRACT`. **Personne n'écrit chez un autre** — on lui adresse une question |
| **information des autres** | tout amendement d'une section **notifie les capacités qui en dépendent**. C'est le `↕` : *« le gameplay a changé — UX, économie et architecture doivent réévaluer leurs conséquences »* |
| **déclenche une réévaluation** | un amendement dans une section dont je dépends · une objection qui me vise · une mesure QA hors cible |
| **convergence** | **aucune question ouverte** et **aucune objection non tranchée**. Une objection *rejetée* reste consignée — elle ne disparaît pas, elle cesse de bloquer |
| **existe déjà** | `design_questions.json` (matérialisé au RUN 1 : 2 questions ART→GM répondues) · objections conservées dans les verdicts (`HUMANGATE_READY_WITH_OBJECTION`) · doctrine ratifiée de **complétion mutuelle Art ↔ GM** : *« le jeu émerge de l'échange ; pas de freeze avec question ouverte »* |
| **manque** | la **notification**. Aujourd'hui c'est un passage de relais : chaque étape lit l'artefact de la précédente, donc un désaccord ne peut s'exprimer qu'en aval, trop tard |

## L4 · `CAPABILITY → GAME_BLUEPRINT`

| | |
|---|---|
| **transmis** | un **amendement daté et signé** : auteur · section · contenu · raison |
| **propriétaire** | le Blueprint appartient au **projet** ; chaque section a un propriétaire nommé |
| **qui modifie quoi** | selon la table de propriété (L3). `feature_map` et `wiremap` ne sont **jamais saisis à la main** — ils sont dérivés. `loop.json` et `economy.json` non plus : **projections déterministes** |
| **information des autres** | le Blueprint est l'unique source ; lire le Blueprint suffit à connaître l'état |
| **déclenche une réévaluation** | tout amendement d'une section dont d'autres dépendent |
| **convergence** | la chaîne est **complète et cohérente** : `VISION → REQUIREMENTS → FEATURES → DESIGN → METRICS → IMPLEMENTATION INTENT → EXPECTED PROOF → ACTUAL PROOF` |
| **existe déjà** | **le verrou anti-écriture LLM**, verbatim : *« `loop.json` est une PROJECTION DÉTERMINISTE de `prisme.json`. `deriveLoopSpec` est une fonction PURE — **aucun LLM n'écrit jamais ce fichier**. Si un agent tentait de l'écrire, ce serait IGNORÉ »* + vérification sha256 contre le build · l'invariant de couverture de `s3-decompo` : *« une feuille qui ne cite aucune exigence est une invention non déclarée ; une exigence que nulle feuille ne porte est une omission silencieuse »* |
| **manque** | le Blueprint comme **objet unique** — aujourd'hui 13 artefacts séparés · le chaînon `design_metrics → paramètres des projections` |

## L5 · `GAME_BLUEPRINT → BUILD`

| | |
|---|---|
| **transmis** | le Blueprint **suffisant** : `gameplay` · `systems` · `ux` · `art` · `technical` · `constraints` · `feature_map` · les projections déterministes |
| **propriétaire** | le **Build Orchestrator** possède le passage, pas le contenu |
| **qui modifie quoi** | le Build ne modifie **jamais** le Blueprint. Le Technical Architect écrit `ARCHITECTURE_CONTRACT` et le `wiremap` — c'est sa section |
| **information des autres** | l'ouverture du build est un **événement visible** ; toute capacité peut encore être rappelée pendant |
| **déclenche une réévaluation** | **l'architecte a le droit de remonter.** Si l'architecture révèle *« cette mécanique demande une décision de design »*, elle **ne l'invente pas pour continuer** — elle remonte vers Fable |
| **convergence — la porte de suffisance** | **mesurable, pas au jugé** : *toute exigence portée par au moins une feature · toute feature portant un `expected_proof`*. C'est la règle dure de `s3-decompo` promue en **condition d'entrée du build** |
| **existe déjà** | 4 builders (`s9-build` html/standard/godot/godot-standard) · le squelette gelé `forge/standard/` · le contexte injecté (charter + art_bible + loop.json + economy.json + asset_requests) · `s4-archi` → `ARCHITECTURE_CONTRACT` vérifié par `s10b` |
| **manque** | la porte de suffisance comme **gate** (la règle existe, elle ne garde pas le build) · le droit de remontée **formalisé** |

## L6 · `BUILD → EVIDENCE`

| | |
|---|---|
| **transmis** | le **jeu réel** + ses reçus : oracles code/archi/wiremap/standard/visuel · mutation · solvabilité · `verdict.json` signé HMAC |
| **propriétaire** | **EVIDENCE** possède les faits ; personne ne les réécrit |
| **qui modifie quoi** | **personne** — append-only. `RUN_INDEX.md` s'est déclaré append-only le 2026-07-26 |
| **information des autres** | le verdict signé et re-vérifié est lisible par tous ; les écarts aux `design_metrics` sont explicites |
| **déclenche une réévaluation** | un oracle rouge · une métrique hors bande · une mutation survivante · une objection red-team |
| **convergence** | `verify_run` rend **`AUTHENTIQUE`**, et le `software_verdict` ne provient **que** de reçus d'oracle vérifiés |
| **existe déjà** | ≈5 800 lignes d'oracles déterministes non-LLM (14 tests `oracle` + 13 `mutation`) · `verdict.py` HMAC · `verify_run.py` (4+5 tests) · l'invariant *« une preuve provient du mécanisme qui a réalisé l'action, sinon `AUTO_ATTESTED` »* |
| **manque** | **QA design** — rien ne mesure la conformité aux `design_metrics`, qui n'existent pas encore · la surface `EVIDENCE/` elle-même · `.forge_key` (à générer, jamais copier) |

## L7 · `EVIDENCE → FABLE`

| | |
|---|---|
| **transmis** | *« voici ce que le jeu fait réellement »* — jamais *« c'est bon »* : couverture, écarts aux métriques, objections, dérives |
| **propriétaire** | **Fable** possède l'interprétation, **pas** les faits |
| **qui modifie quoi** | Fable ne modifie aucun fait ; il décide **quelles capacités rappeler** et l'inscrit dans `decisions` |
| **information des autres** | la décision de rework nomme les sections à revoir ; les capacités concernées sont convoquées (L2) |
| **déclenche une réévaluation** | condition de sortie non satisfaite (§ ci-dessous) |
| **convergence** | **le rework passe par le Blueprint, jamais par un patch direct du jeu** — sinon le Blueprint devient faux et l'objet central redevient le run |
| **existe déjà** | `studio_link.py` · Observer (40 fichiers, lien Forge prouvé) · la boucle d'apprentissage `learning_hook → learning_memory → kb_proposal` — **la seule boucle du système qui tourne vraiment** |
| **manque** | la **boucle des métriques** : `MEASURE → COMPARE → REWORK` n'existe pas ; les métriques auditent le pipeline, elles ne pilotent pas la conception |

## L8 · `EVIDENCE → HUMAN`

| | |
|---|---|
| **transmis** | le **jeu jouable** + ce qu'il fait, mesuré + les écarts + **les objections conservées** |
| **propriétaire** | **Pierre** possède le jugement de valeur. Personne d'autre, jamais |
| **qui modifie quoi** | Pierre tranche : merge / reject / freeze. Il peut **accepter un écart explicitement** — c'est une décision, pas un contournement |
| **information des autres** | la décision est inscrite au **decision-log** ; les leçons deviennent des propositions KB, ratifiées une par une |
| **déclenche une réévaluation** | *« je n'ai pas envie d'y jouer »* — le seul signal qu'aucun oracle ne peut produire |
| **convergence** | les 4 conditions du critère de sortie (ci-dessous) |
| **existe déjà** | `gate.py`, *« the FORCER brick »* : *« l'appelant NE DOIT PAS poursuivre au-delà d'une porte non-OK »* · vocabulaire unique `OK/FAIL/BLOCKED` · `claim_verdict: NO_CLAIM_ALLOWED` · `kb_proposal --apply --ratifie-par` |
| **manque** | **la destination des décisions** : `decision-log.md` est absent du V2. Le gate peut produire un verdict, il n'a pas où inscrire la décision |

---

## Ce qui constitue une convergence — récapitulatif

| liaison | convergence |
|---|---|
| L1 | Pierre confirme que la reformulation de son intention est fidèle |
| L2 | la capacité a rendu un amendement **ou** une question — jamais un silence |
| L3 | **aucune question ouverte, aucune objection non tranchée** |
| L4 | la chaîne `VISION → ACTUAL PROOF` est complète et cohérente |
| L5 | **porte de suffisance verte** : toute exigence → une feature ; toute feature → un `expected_proof` |
| L6 | `verify_run` rend `AUTHENTIQUE` ; le verdict ne vient que de reçus vérifiés |
| L7 | le rework est passé par le Blueprint |
| L8 | **les 4 conditions** : couverture · métriques dans les bandes ou écart accepté · aucune objection ouverte · **Pierre a joué et dit oui** |

## Ce qui déclenche une réévaluation — récapitulatif

```
vision ou must_not_have modifiés        → tout ce qui en dérive
section amendée                         → les capacités qui en dépendent (notification)
question posée                          → le destinataire, jusqu'à réponse
objection déposée                       → Fable, jusqu'à arbitrage
architecture bute sur un choix de design → Fable (l'architecte n'invente pas)
oracle rouge / mutation survivante      → la capacité responsable
métrique hors bande                     → Design + Systems
« je n'ai pas envie d'y jouer »          → Fable, et lui seul décide quoi rouvrir
```

---

## Les cinq manques structurels, en un coup d'œil

| # | manque | liaison | conséquence mesurée |
|---|---|---|---|
| M1 | **notification entre capacités** | L3 | un désaccord ne peut s'exprimer qu'en aval, trop tard |
| M2 | **jointure `expected_proof ↔ actual_proof`** | L4/L5 | 26 ids vs 25, **intersection 0** — le `must_not_have` de PAIRE 2 n'a jamais eu d'oracle |
| M3 | **boucle des métriques** | L7 | les métriques auditent le pipeline, elles ne pilotent pas la conception |
| M4 | **rôle UX** | L3/L4 | `\bUX\b` : 2 contrats, et seulement comme *chose observée chez les concurrents* |
| M5 | **destination des décisions** | L8 | `decision-log.md` absent du V2 |

**Aucun des cinq n'est un framework.** M1 est une notification, M2 un anneau, M3 une boucle,
M4 un rôle, M5 un fichier. Tout le reste des huit liaisons existe déjà, en pièces mesurées et
testées.

---

```
status_by_surface:
  interaction_model:            DOCUMENTED_ONLY
  naming_decision:              DOCUMENTED_ONLY   # renommage NON exécuté
  loops_model:                  DOCUMENTED_ONLY
  spawn_gate_invariant:         TESTED            # count==1 dispatch, pas de fichier de contrat
  deterministic_projections:    TESTED            # verrou anti-écriture LLM + sha256
  coverage_invariant:           TESTED            # règle dure s3-decompo lue au contrat
  notification_between_agents:  NOT_FOUND
  expected_actual_join:         NOT_FOUND
  metrics_loop:                 NOT_FOUND
  ux_role:                      NOT_FOUND
  decision_log_destination:     NOT_FOUND
  implementation:               BLOCKED
  runtime_validation:           BLOCKED
```
`software_verdict: OK` (document) · `evidence_verdict: MECHANICAL_VALIDATION_ONLY` ·
`claim_verdict: NO_CLAIM_ALLOWED` · `no_global_ready_verdict: true`

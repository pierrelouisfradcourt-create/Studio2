# ROLE-SIM — 2e rôle : `role-guardian-static` (test de généralisation) — 2026-07-13

- **Demande** : Pierre, « go fait le 2eme role » (suite à ma proposition de tester si
  Role-Sim généralise à un archétype différent avant d'investir dans l'intégration
  catalogue complète).
- **Archétype** : gardien statique à zone de contrôle — repris du pattern déjà cité
  `pat-zone-of-control` (Battle for Wesnoth, concept only).
- **claim_verdict** : NO_CLAIM_ALLOWED

## 1. `role_sim.mjs` généralisé — plus aucune mécanique de jeu en dur

Avant ce rôle, `role_sim.mjs` connaissait EN DUR la poursuite (import direct de
`pursuer.mjs`/`evader.mjs`, fonction `simulateOne` hardcodée). Pour tester une vraie
généralisation (pas juste écrire un 2e script séparé qui prouverait seulement que je sais
écrire deux simulations, pas que le MÉCANISME généralise), refactor :
- `simulation_config`/`runTrial` extrait vers `systems/ai/pursuer_scenario.mjs`
  (logique **inchangée** — vérifié : mêmes médianes mesurées avant/après extraction sur
  les mêmes seeds, 25 sur seeds 1000..1299).
- `role_sim.mjs` ne connaît plus AUCUNE mécanique — il charge dynamiquement le
  `simulation_module` déclaré par CHAQUE rôle (nouveau champ Critique, SCHEMA.md v2,
  13 champs) et lui délègue tout le comportement du scénario.
- Régression : `role_sim.test.mjs` inclut maintenant un test avec un `runTrial` FACTICE
  (sans rapport avec la poursuite) pour prouver la généricité elle-même, pas seulement
  rejouer le rôle existant.
- `pursuer-mobile.yaml` mis à jour (`simulation_module` ajouté), proof_of_use
  régénéré avec le code actuel (mêmes chiffres, format de sortie à jour).

## 2. Un vrai problème de conception trouvé et corrigé AVANT toute conclusion

1re version du scénario guardian : distance de croisement ET hauteur d'approche
ALÉATOIRES ensemble. Résultat mesuré (pas supposé) : **bande de difficulté IDENTIQUE
avec `zoc_radius=4` et `zoc_radius=0`** — la zone de contrôle n'avait AUCUN effet
détectable. Diagnostic : la variance de distance de base (10 à 40 ticks selon le tirage)
noyait complètement l'effet réel de la zone (au plus 1 tick de délai par franchissement,
prouvé par `stepTowardWithZoC` — 7 tests verts sur la mécanique elle-même). Une
validation qui « passe » sur une métrique insensible à la mécanique testée aurait été
exactement le théâtre que cette étude entière s'efforce d'éviter.

**Corrigé, pas contourné** : distance de croisement fixée (`crossing_half_distance: 11`),
seule la hauteur d'approche varie. Effet immédiatement mesurable et prouvé par
comparaison directe contre un scénario SANS zone
(`guardian_scenario.mjs#runTrialWithoutZone`, utilisé uniquement en test, jamais par
l'oracle) : **exactement les traversées à hauteur `|y| <= zoc_radius` subissent +1 tick,
jamais plus** (`systems/ai/guardian_scenario.test.mjs`, 5 tests verts, dont un qui
échouerait si l'effet n'existait pas — `anyDelay` doit être vrai sur 300 essais).

Conséquence sur la métrique déclarée : la MÉDIANE reste égale au baseline sans zone
(majorité de traversées jamais affectées) — **la médiane ne prouve rien sur ce rôle**.
Le **MAX**, lui, ne peut valoir 12 que si au moins une traversée a réellement été
retardée. `difficulty_target.metric` déclaré = `ticks_to_reach_goal_max`, pas médiane —
un choix motivé par ce que la mesure a révélé, pas une préférence arbitraire.

## 3. Calibration → validation disjointe (même discipline que pursuer-mobile)

```
Calibration (seeds 1..300)     : min=11, médiane=11, max=12, 300/300 succès.
Bande déclarée (APRÈS calibration, AVANT validation) : ticks_to_reach_goal_max ∈ [12, 20].
Validation officielle (seeds 1000..1299, DISJOINT) : min=11, médiane=11, max=12 → PASS.
```
`tier` promu `candidate` → `validated`, `proof_of_use` =
`knowledge_base/proofs/role_sim_guardian_static_validation.log` (réel, régénéré après
chaque changement de code touchant le calcul).

## 4. Intégration catalogue — faite dès cette fois (leçon du 1er rôle appliquée)

`sys-guardian-zoc` enregistré directement dans `catalog.json` (`tier: validated`, preuve
réelle) — PAS laissé comme trou déclaré cette fois, contrairement au 1er rôle où
l'intégration avait été faite dans un 2e temps. Provenance : `dependencies:
["pat-zone-of-control"]` (contrairement à `sys-pursuer-mobile`/`sys-evader-basic` qui
utilisaient le marqueur `ORIGINAL` — ici une vraie citation de pattern existe et
s'applique). `kb-validate.mjs` : PASS, 14 entrées. `search.mjs "gardien statique zone de
controle"` trouve `sys-guardian-zoc` en tête (score 4), devant la simple citation du
pattern — mise à jour d'un test existant qui assumait l'inverse (pas une régression,
une conséquence attendue d'avoir enrichi le catalogue).

## 5. Tests — 102/102 verts (ensemble knowledge_base)

```
zone_of_control.test.mjs      : 7 tests (mécanique ZoC isolée)
guardian_scenario.test.mjs    : 5 tests (dont la preuve anti-artefact : delta jamais négatif,
                                 toujours 0 ou 1, au moins 1 délai réel observé)
role_sim.test.mjs             : 6 tests (dont 1 scénario factice prouvant la généricité)
+ tous les tests précédents (pursuer/evader/search/kb-validate/damage_floor/reachability)
```

## 6. Conclusion — ce que le test de généralisation établit réellement

- **Le mécanisme généralise structurellement** : un 2e archétype totalement différent
  (statique vs mobile, ralentissement vs capture, mécanique de zone vs mécanique de
  fuite) branché SANS modifier `role_sim.mjs` autrement qu'en le rendant générique une
  fois — c'est le résultat positif recherché.
- **Le mécanisme NE généralise PAS « gratuitement » côté conception de scénario** :
  la 1re tentative de scénario guardian ne testait RIEN (effet noyé dans le bruit), et ça
  n'a été détecté qu'en comparant explicitement contre un baseline sans le mécanisme —
  une vérification qui n'était pas automatique, qu'il a fallu faire consciemment. Leçon
  méthodologique pour tout futur rôle : **toujours vérifier qu'un scénario réagit
  différemment avec le mécanisme activé vs désactivé AVANT de déclarer une bande de
  difficulté** — sinon la validation peut passer sans avoir rien testé.
- **N=2 rôles, toujours pas une généralisation prouvée au sens statistique** — deux
  archétypes, deux succès, mais le prochain rôle pourrait révéler une limite du schéma
  à 13 champs ou du contrat `runTrial(seed,cfg)` que ces deux-là n'ont pas exercée.

```
software_verdict: OK (2e rôle validé sur échantillon disjoint, oracle généralisé, catalogue intégré dès la construction)
evidence_verdict: MECHANICAL_VALIDATION_ONLY
claim_verdict: NO_CLAIM_ALLOWED
```

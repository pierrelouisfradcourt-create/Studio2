# PHASE 0.5 — Evidence Runtime Foundation (charter)

> **Statut** : PROPOSED — non commité. Création ratifiée Pierre, 2026-07-29.
> **Objectif, en une phrase falsifiable** : après cette phase, deux runs Forge peuvent être
> comparés et l'on peut dire lequel a changé **quoi** — pas seulement que « le dépôt a changé ».
> **Trois buts, pas un de plus** : rendre l'expérience fiable · rendre les preuves exploitables ·
> préparer la première mutation.
> **Interdits de phase** : aucune mutation, aucun MCTS, aucun builder, aucun oracle nouveau, aucun
> changement de gate ni de verdict, aucun commit. Observation seulement.
> **Règles d'évolution** (témoin, régimes de preuve, format des mutations, adoption) : elles ne
> sont pas ici. Voir `docs/forge/FORGE_EVOLUTION_DOCTRINE_V0.md`.

---

## 1. Diagnostic — exécuté en lecture seule le 2026-07-29

Trois mesures fondent les chantiers. Chacune est une commande réellement lancée.

**D-1 — La suite passe, la porte tourne.**
`pytest scripts/forge/tests -q` → **1090 passed, 1 skipped** (71,6 s).
`forge.dispatch --dry-run --profile standard_godot` → 5 étapes planifiées, résolution rôle →
exécutant réellement observée. Hook `pretool_forge_guard.py` armé sur le matcher `Task`.

**D-2 — La provenance est produite, et mal rangée.**
Les deux points d'appel du driver traversent la porte (`driver.py:427` LLM, `driver.py:681`
déterministe) et le manifeste `dispatch` est écrit. Mesure : **13 runs Snake, 93 lignes
`"kind": "dispatch"` signées**, portant `contract_sha256`, `payload_prompt_sha256`, `git_head`,
`activation`, `model`, `provider`, et une table `sources` avec un `sha256` par fichier lu.

Elles sont **toutes** sous `lab/forge_runs/_orphan_context/`. Cause : aucun point d'appel ne passe
`run_dir` ; la fonction retombe sur une dérivation du projet depuis le `run_id`, qui échoue dès que
le nom dépasse `<projet>-<date>` :

```
'breakout-20260711'             -> 'breakout' -> forge_runs/breakout
'snake-final2-20260729-174101'  -> None       -> _orphan_context/…
```

**D-3 — Deux organes nomment le mauvais modèle, et le coût des échecs est invisible.**
`model_override` n'apparaît **nulle part** dans `dispatch.py`, `context_manifest.py` ni
`contract.py` : la ligne signée enregistre le modèle **du contrat**, jamais celui exécuté après
escalade. La télémétrie a le même défaut, plus deux autres — elle n'est écrite qu'après un statut
`OK`, et `cost_usd` est calculé puis jeté (3 533 362 tokens tracés, tous sur des succès ; 187 267
tokens d'échec invisibles).

---

## 2. Les quatre chantiers

| # | Chantier | Ce qu'il ferme | Périmètre |
|---|---|---|---|
| **0.5.a** | **rebrancher la provenance sur son run** — routage **explicite** (ratifié) | D-2 | le point d'appel passe le `run_dir` qu'il connaît déjà. Ne toucher **ni** la validation de contrat, **ni** la ligne d'audit signée, **ni** la route de décision |
| **0.5.b** | **lancer M1 (télémétrie d'échec)** — ne pas redessiner | moitié de D-3 | mission déjà écrite, design arbitré, TDD strict, advisory strict, trois fichiers |
| **0.5.c** | **empreintes de graphe** — `graph_declared_hash` (avec `roles_sha256`) et `graph_execution_hash` | l'attribution | calcul neuf, en lecture seule ; descriptif, aucun gate ne le lit |
| **0.5.d** | **modèle réellement exécuté dans la provenance signée** | l'autre moitié de D-3 | **hors périmètre de M1** — chantier distinct, découvert le 2026-07-29 |

Les livrables « `piece_id` » et « `definition_hash` » ne sont pas des chantiers : le nom d'étape est
déjà une identité stable, `contract_sha256` est déjà une empreinte de définition. Il s'agit de les
**nommer**, pas de les créer.

---

## 3. Critères de sortie

| # | Test | Ce qu'il prouve |
|---|---|---|
| **E1** | rejouer deux fois la même chaîne → `graph_declared_hash` identique | l'empreinte est stable |
| **E2** | modifier **un** contrat → l'empreinte change, le diff désigne **cette pièce** | l'attribution fonctionne |
| **E3** | interrompre une étape → la tentative échouée apparaît avec son coût | l'échec cesse d'être invisible |
| **E4** | un run avec escalade → empreinte déclarée identique, empreinte d'exécution différente, `execution_difference.type` renseigné | hypothèse et déroulement ne seront pas confondus |
| **E5** | dériver l'empreinte des 13 runs Snake existants → ≥ 2 valeurs distinctes | la **plomberie** produit une valeur variable. Ne prouve **aucune** attribution |
| **E6** | la provenance d'un run se trouve dans le dossier de ce run | le fil est rebranché |
| **E7** | **construire** une paire ne différant que par un contrat → le diff l'isole | l'attribution, pour de vrai. Ce couple se fabrique, il n'existe pas dans l'historique |

E5 est le seul exécutable immédiatement, sur données existantes, sans rien modifier — et il valide
la tuyauterie, pas la mesure.

---

## 4. Séquence — cinq étapes, ratifiées le 2026-07-29

La V2 est le **socle expérimental**, pas une grosse mutation simultanée.

**Séquence ratifiée Pierre, 2026-07-29 (corrigée) — 7 étapes.**

```
1. reference_protected     protéger le témoin · rendre la non-régression vérifiable
        |
2. PROVENANCE COMPLÈTE     dispatch rebranché · modèle réellement exécuté · génome d'exécution
        |
3. MÉMOIRE D'APPRENTISSAGE failure_event append-only · statut de lesson · génération
        |                   · filtrage DÉTERMINISTE au pré-mortem
        |
4. SKILLS OBSERVABLES      savoir ce qui est déclaré · savoir ce qui est réellement consommé
        |
5. RAISONNEMENT            d'abord tracer le paramètre, ensuite rendre le mécanisme effectif
        |                   (à valeurs déclarées inchangées — voir la nuance ci-dessous)
        |
   [GEL DU TRONC]          entrées gelées (§4.3) · Snake relancé, `comparable_to: aucun`
        |
6. CALIBRATION             tronc complet · métriques · bande de bruit
        |
7. PREMIÈRE VAGUE          mutations contrôlées, une variable à la fois, comparées au tronc
```

> **Règle de phase** : *aucune capacité qui modifie le contexte, la mémoire ou le comportement
> d'exécution ne peut arriver après la calibration.*

### 4.0 Observer n'est pas améliorer

| Socle de mesure (étapes 1-5) | Mutation (étape 7) |
|---|---|
| tracer le raisonnement | **augmenter** le raisonnement |
| tracer les skills | **donner** des skills |
| tracer les leçons | **changer** la politique d'apprentissage |

C'est ce qui garde V2 mesurable sans mélanger instrumentation et optimisation.

**Nuance sur l'étape 5, et c'est la seule du lot.** Rendre le mécanisme d'injection effectif change
le comportement, même à valeurs inchangées : un paramètre jusque-là ignoré se met à s'appliquer.
Cette bascule doit donc rester **avant** la calibration (règle de phase) — et elle sera, par
construction, **non mesurable** : il n'existe aucun tronc antérieur qui la porte. Elle est absorbée
dans le changement de génération, au même titre que la simplification.

Ce qui reste mesurable en étape 7, c'est le **choix d'une valeur** sur un axe désormais réel :
« niveau `high` pour le rôle R ». Rendre l'axe possible appartient au socle ; choisir un point sur
l'axe est l'expérience.

**L'étape 4 n'est pas une formalité.** Rejouer la même chaîne ne redonne pas les mêmes chiffres :
un exécutant LLM n'est pas déterministe. Sans bande de bruit mesurée, un écart V3 est
ininterprétable — on ne peut pas distinguer un gain réel d'une variation ordinaire. Doctrine §6.4.

À ne pas confondre avec E1 : E1 teste la stabilité d'une **empreinte** (déterministe par
construction) ; l'étape 4 mesure la dispersion des **métriques** (non déterministes).

### 4.1 Priorité V2 : passer en mode production

**Snake V1 (chaîne Opus) est un génome historique** : Opus partout a servi à **scanner la chaîne et
trouver les trous** — c'est fait, et c'est ce qui a produit tout ce charter. On l'archive, on ne le
compare pas.

V2 vise le premier **génome industriel** : celui qui produit **plusieurs jeux** avec des références
mesurables. Ce n'est pas un objectif de productivité, c'est la condition d'existence du corpus —
sans plusieurs jeux, `scope: generalized` reste inassertable et la boucle d'évolution n'a rien à
lire (doctrine §1.0, §7).

**Deux corpus, deux usages, à ne jamais confondre :**

| Ce qu'on répète | Ce que ça produit | Sert à |
|---|---|---|
| **le même** projet, N fois | la bande de bruit | interpréter un écart de mutation |
| **des projets différents** | le corpus de génomes | `scope: generalized` · statistiques par classe d'erreur |

Cinq jeux différents ne donnent aucune bande de bruit. Cinq répétitions de Snake ne donnent aucun
corpus. Les deux sont nécessaires, pour des choses différentes.

### 4.2 Deux règles de séquence à ne pas enfreindre

- **La calibration est le dernier acte de V2, pas une étape à l'intérieur.** Elle mesure la
  dispersion du tronc ; la mesurer pendant que le tronc bouge encore la rendrait sans objet.
- **Gel du tronc entre la calibration et la première mutation.** Si quoi que ce soit change dans
  l'intervalle, la bande de bruit ne décrit plus le tronc auquel V3 sera comparée — et toute la
  chaîne de comparaison s'effondre en silence, sans qu'aucun oracle ne s'en aperçoive.
- **Tout ce qui touche la chaîne entre dans V2.** Y compris l'instrumentation de la mémoire
  d'apprentissage, qui paraît « juste de l'observation » mais s'écrit depuis le driver. Après le
  gel, plus rien ne bouge sauf la mutation testée — un ajout « neutre » ne serait neutre qu'une
  fois prouvé, et le prouver coûterait de refaire la calibration.
- **Le gel inclut le corpus de leçons.** Le pré-mortem fait partie de l'environnement
  expérimental : deux runs aux contrats identiques, séparés par l'ajout d'une leçon, ne reçoivent
  pas le même pré-mortem. Contrôle de validité **gratuit et déjà outillé** — le manifeste
  d'exécution enregistre `premortem_sha256` : *tous les runs de calibration doivent porter le même.*
  S'ils divergent, la bande de bruit est contaminée.

### 4.3 Ce que le gel couvre, et l'empreinte qui le prouve

*Sinon on mesure un système qui apprend pendant qu'on mesure son bruit.* (Pierre, 2026-07-29)

| À geler | Empreinte qui le prouve | État |
|---|---|---|
| code | `git_head` + `code_sha256` par fichier (reçu de mutation) | **existe** |
| contrats | `contract_sha256` | **existe** |
| rôles | `roles_sha256` | proposé (§0.5.c) |
| modèles | *déclarés* via `roles_sha256` — voir ci-dessous | proposé |
| skills actifs | aucune | **à créer** (aujourd'hui `allowed_tools` est un tuple vide) |
| corpus de leçons + pré-mortem résultant | `premortem_sha256` | **existe** |

Deux précisions qui évitent de geler la mauvaise chose :

- **On gèle les entrées, jamais les sorties.** Le modèle *déclaré* est une entrée ; le modèle
  *exécuté* après escalade est une sortie. Geler l'escalade reviendrait à calibrer un tronc qui
  n'est pas le vrai tronc. Une escalade pendant la calibration **fait partie du bruit**, et c'est
  correct : une mutation future affrontera la même possibilité.
- **« Corpus de leçons » et « pré-mortem résultant » sont une seule empreinte, et c'est la bonne.**
  `premortem_sha256` capture ce qui est **réellement entré** dans le run — une leçon ajoutée puis
  filtrée par son statut ne change rien, et c'est exactement le comportement voulu.

> **Contrôle de validité de la calibration, en une ligne** : tous les runs de calibration
> partagent le même jeu d'empreintes d'entrée. C'est ce qui rend le gel **vérifiable** au lieu de
> promis — et c'est le seul moyen de distinguer « le tronc a bougé » de « la métrique est bruitée ».

## 4.4 Protocole de calibration — révisé le 2026-07-30 avant tout appel payant

### Ce que cette campagne mesure, et ce qu'elle ne mesure pas

**Découverte de pré-vol, ratifiée Pierre** : `games/snake/**` est commité **à l'état construit**
(66 fichiers `.gd`, 282 assertions). Il n'existe **aucun état pré-build de Snake dans
l'historique** — le jeu a été bâti incrémentalement et commité au fur et à mesure. Restaurer
« l'état initial » restaure donc un jeu fini.

| Surface | Statut de calibration | Raison |
|---|---|---|
| chaîne **aval** — oracle code, oracles du standard, red-team, verdict | **CALIBRABLE** | ces étapes font un travail réel quel que soit l'état du jeu |
| chaîne **amont** — s9 / forgeron, *construction depuis zéro* | **`NOT_MEASURED`** | le forgeron trouve tout déjà fait : la mesure porterait sur un quasi no-op |

`NOT_MEASURED` et non `OK` : invariant Pierre du 2026-07-27, un résultat non mesuré n'est jamais
un résultat vert. La bande de bruit produite décrira **une passe sur un artefact déjà construit**,
pas une construction — et le rapport doit le dire, sinon il ment par omission.

### Décisions écartées, et pourquoi

- **Reconstruire un état pré-build** (vider les `.gd` en gardant le squelette) : rejeté — ce serait
  *fabriquer* une condition expérimentale qui n'a jamais existé, pas restaurer un état.
- **Créer un génome vierge maintenant** : rejeté — changer d'expérience au moment de la mesurer.
- **Modifier le tronc pour instrumenter le cas** : rejeté — *« ne transforme pas un problème de
  manque d'expérience en problème de code »* (Pierre).

### Conséquence sur l'ORDRE des mutations

L'ordre initialement envisagé est inversé par cette contrainte :

| Mutation | Étape visée | Mesurable contre cette calibration |
|---|---|---|
| red-team Opus → Qwen | s11, travail réel sur un jeu construit | **oui — première expérience naturelle** |
| niveau de raisonnement d'un rôle aval | s10/s11/s12 | oui |
| `game_forger` Opus → Sonnet | s9, sans travail à faire | **non — attendre un génome vierge** |

### Protocole opératoire

1. état initial vérifié propre vs `HEAD`, restauré depuis git **entre chaque run** ;
2. `run_dir` distinct par run ; les sorties du run précédent archivées selon la convention
   `_run_<label>/` déjà en usage (jamais supprimées) ;
3. **un seul run à la fois** — le coût est lu après coup et rapporté avant de décider du suivant ;
4. `N = 3`, extension à 5 **seulement si** l'écart relatif `(max − min) / médiane` dépasse **20 %**
   sur le coût ou la durée — seuil fixé **avant** lecture des résultats ;
5. plafond de campagne **50 $**, contrôle **entre** les runs. **Il n'existe aucun coupe-circuit
   intra-run** : `run_real` n'a pas de plafond de budget, et en ajouter un toucherait le tronc gelé.
   L'exposition maximale est donc le coût d'un run isolé qui dérape, borné seulement par
   `--step-timeout`. Assumé et écrit, pas contourné.

### Rapport attendu — par surface, jamais de verdict global

Séparer : **coût financier · tokens · durée · variance entre runs · résultats fonctionnels**.
Défalquer la constante d'environnement (~32,8k tokens de `cache_creation` par appel, hooks
`SessionStart`) au lieu de la confondre avec le coût propre. Marquer explicitement
`s9 / construction depuis zéro : NOT_MEASURED`.

### Reprise différée

Le jour où un **génome vierge existe réellement**, une mesure dédiée du build sera faite — elle ne
s'improvise pas sur un artefact fini.

> **Leçon de cette pré-vérification** *(Pierre)* : la Forge a fait son travail — elle a empêché de
> mesurer la mauvaise chose. Le manque n'était pas dans le code, il était dans l'expérience
> disponible.

Deux points établis le 2026-07-29 qui conditionnent cette séquence :

- **Le routage par rôle n'est pas un chantier.** Le registre le fait déjà et il est déjà
  différencié — builders et world scan sur Haiku, outillage sur Sonnet, red-team du plan sur Qwen,
  escalade des builders Haiku → Sonnet → Opus. Ce qui est uniforme, ce sont **les valeurs**.
  Éditer `roles.yaml` **est** une hypothèse, pas une infrastructure.
- **Deux contraintes d'ordre.** Qwen ne se route qu'après l'existence du champ
  `intended` / `incident`, sinon un run exécuté en repli par Claude serait rapporté comme un
  résultat Qwen. Les skills ne s'activent qu'après le patron de confinement — liste d'outils
  constante, refus par défaut sur tout nom inconnu, testé **sans** passer par le modèle.

---

## 5. Périmètre exclu

Aucune mutation de wiremap, prisme, agent ou workflow · aucune exploration de branches · aucune
interface · aucun changement de verdict, gate ou oracle · **aucun déplacement ni suppression** des
69 dossiers de `_orphan_context/` — ratifié : **indexer sans déplacer ni supprimer**, ce sont des
traces historiques.

Et, pour la mémoire d'apprentissage introduite en V2 : **aucun scoring, aucune probabilité, aucune
sélection automatique, aucun MCTS.** Ils viennent après les premiers génomes industriels. Le risque
évité est nommé : reconstruire une usine avant d'avoir validé la boucle d'apprentissage.

**Après le gel : aucune amélioration de la Forge elle-même. Uniquement des mutations
expérimentales.**

---

## 6. Risques

| # | Risque | Ce qui le contient |
|---|---|---|
| R1 | 0.5.a touche la porte unique, zone la plus sensible de la Forge | le manifeste est déjà hors du chemin de décision ; n'y toucher qu'à ce niveau |
| R2 | corriger le routage **coupe la lignée en deux régimes** | décider **avant** du sort des 13 runs Snake : indexer sans déplacer |
| R3 | M1 modifie le driver et le connecteur studio — zone chaude | mission cadrée TDD, advisory strict, trois fichiers |
| R4 | l'empreinte se met à influencer une décision | descriptive en 0.5 ; toute promotion est une décision ultérieure distincte |
| R5 | la phase glisse vers « et tant qu'on y est, la comparaison automatique » | E1-E7 sont la définition du fini |

---

## 7. Décisions

**Ratifiées le 2026-07-29** — routage **explicite** (« ne pas revenir aux heuristiques qui créent
de faux génomes ») · orphelins **indexés sans déplacement ni suppression** · `roles_sha256` dans
l'empreinte déclarée · un axe de mutation doit être `observed` · V2 = socle, mutations en V3.

**Ouvertes** :

1. **`reference_protected`** — invariant ratifié, **périmètre minimal ratifié** : protection du
   témoin · détection de modification · dérogation humaine explicite. Rien d'autre avant la
   calibration. Sa pose reste une écriture dans la configuration : **geste de Pierre**, et c'est
   l'étape 1 de la séquence. Point de vigilance : c'est la **détection** qui porte la complétude
   (doctrine §1.2) — une protection sans elle laisse passer tout ce qui écrit hors des outils de
   session.
2. **Qui exécute M1** ? Un rôle existe déjà (`forge_toolsmith`, outillage hors profil, dispatch en
   dérogation assumée et inscrite).
3. **L'empreinte de graphe : dans le driver ou dans un lecteur séparé** ? Un lecteur séparé ne
   touche pas la porte et rend l'empreinte dérivable sur les runs passés.
4. **Quel rôle pour la première mutation V3** ? Le candidat le moins cher est un changement d'une
   ligne de registre — *« Sonnet suffit pour le rôle R »*. Précaution mesurée : dans
   `standard_godot`, producteur et red-team résolvent **tous deux** vers Opus ; les changer ensemble
   rendrait l'écart inattribuable.

---

## Rapport de charter

- **software_verdict: OK** — charter produit, diagnostic exécuté en lecture seule. Aucune
  modification de la V1, aucun code, aucune migration. PROPOSED, non commité.
- **evidence_verdict: MECHANICAL_VALIDATION_ONLY** — D-1 à D-3 reposent sur des commandes réellement
  exécutées le 2026-07-29 : suite de tests, dry-run de la porte, comptage des manifestes par type et
  par run, test direct de la dérivation de `run_dir` sur cinq `run_id` réels, recherche d'occurrences
  de `model_override`, lecture des deux points d'appel du driver et d'une ligne `dispatch` réelle.
- **claim_verdict: NO_CLAIM_ALLOWED** — aucune affirmation que les quatre chantiers soient réalisables
  au coût supposé, ni que E1-E7 seront atteints. Le diagnostic établit une cause **probable** du
  mauvais routage ; il ne prouve pas qu'elle soit la seule.

**SKIPPED_VALIDATION**

- *Unicité de la cause (D-2)* — non prouvée : rien n'exclut une seconde cause sur un autre chemin.
- *Runs non-Snake* — partiel : le comptage détaillé n'a porté que sur 13 des 69 dossiers orphelins.
- *M1* — non rejouée : ses chiffres sont cités depuis son document de mission.
- *Coût des quatre chantiers* — non estimé.
- *E5* — non exécuté : la dérivation des 13 empreintes n'a pas été faite.
- *§4 (« le routage existe déjà »)* — établi par lecture du registre et par le dry-run D-1 ; non
  vérifié qu'aucune contrainte ailleurs n'empêche d'y déclarer un autre modèle pour un rôle
  producteur.

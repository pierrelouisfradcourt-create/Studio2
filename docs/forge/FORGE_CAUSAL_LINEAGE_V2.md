# FORGE_CAUSAL_LINEAGE_V2 — Les quatre lignées causales de la Forge

**Statut** : PROPOSED
**Auteur** : Pierre, 2026-08-06.
**Objectif** : formaliser la continuité causale de la Forge à travers les agents, les
modèles, les escalades, les sessions et les mutations.

> La Forge n'est pas alignée parce qu'un agent **comprend**.
> Elle est alignée parce que la **causalité survit au remplacement de l'agent**.

Aucun agent n'est un cerveau isolé destiné à disparaître avec son contexte.
Chaque agent est un **nœud temporaire dans une chaîne de transmission**.

> **Annexe de mesure** : `docs/forge/WHY_LINEAGE_PROPOSAL_V1.md` porte les chiffres
> relevés sur la session `pacman` V1/V2 (2026-08-05/06) et le câblage minimal chiffré.
> Ce document-ci est la doctrine ; celui-là est le chantier. Ne pas les fusionner.

---

## Vue globale

```
                    INTENTION HUMAINE
                           |
                           v
                 +-------------------+
                 |  INTENT LINEAGE   |
                 | Pourquoi le projet|
                 | existe            |
                 +-------------------+
                           |
                           v
                 Cohérence projet
                           |
                           v
                 +-------------------+
                 | ACTIVATION        |
                 | LINEAGE           |
                 | Pourquoi cette    |
                 | tâche existe      |
                 | maintenant        |
                 +-------------------+
                           |
                           v
                    Agent Worker
                           |
                           v
                 Travail + preuve
                           |
                           v
                 +-------------------+
                 | RETURN LINEAGE    |
                 | Pourquoi réveiller|
                 | le parent         |
                 +-------------------+
                           |
                           v
                 Agent parent /
                 orchestrateur
                           |
                           v
                 +-------------------+
                 | PERSISTENCE       |
                 | LINEAGE           |
                 | Ce qui survit     |
                 | après disparition |
                 +-------------------+
```

---

## 1. Intent Lineage — pourquoi ce projet existe ?

Maintient la **cohérence globale du projet**. Vient de l'intention humaine initiale.
Porte : finalité · identité · invariants · limites de transformation acceptables ·
direction stratégique.

Répond à : *cette action est-elle compatible avec le projet ?*

**Exemple.** Projet : une Forge produisant des jeux data-driven sans casser les invariants.
Un agent propose : « pour simplifier l'équilibrage, on remplace les créatures historiques
par des chars futuristes ». Techniquement : code plus simple, tests verts, production plus
rapide. Mais l'identité est détruite et l'intention humaine violée.
**La tâche réussit. Le projet échoue.**

**Garde-fou** : ne doit jamais être réécrit par un enfant. Il est *attribué*, *sourcé*,
*transmis* — et enrichi uniquement par le niveau autorisé.

> *Mesure (annexe §0bis)* : exigé par `s0-contrat.yaml` SEUL, 1 contrat sur ~13.
> Il naît à s0 et n'est propagé nulle part.

## 2. Activation Lineage — pourquoi cette tâche démarre maintenant ?

Maintient la **cohérence locale d'une action**. Une tâche ne doit jamais être :

```
BUG → ACTION
```

Elle doit être :

```
PROBLÈME MESURÉ → ORACLE → CAUSE RACINE → CONTEXTE CHARGÉ → ACTION → PREUVE
```

**Exemple.** Mauvais : « corriger le placement des assets ». Correct : « `check_placement`
détecte une divergence entre `repo_map.yaml` et la wiremap. Cause racine : la table des
racines n'était pas chargée par `s4-archi`. Action : charger `repo_map.yaml` avant la
décision d'architecture. Preuve : `manifest.sources` contient le fichier avec son `sha256`. »

### Différence essentielle — WHY ≠ CONTRAINTE

| | Exemple |
|---|---|
| **WHY** (le sens) | « le projet doit rester data-driven » |
| **CONTRAINTE** (la réalité) | « `repo_map.yaml` contient exactement 11 racines autorisées » |

Le premier est une intention. Le second est une **réalité vérifiable**.

> *Mesure* : le champ `reason` du Context Manifest porte cette lignée. 9 dispatches, 9 vides.

## 3. Return Lineage — pourquoi réveiller le parent ?

> **Aucun worker ne meurt seul.**

Un worker n'a pas pour rôle seulement d'exécuter : il doit **transmettre la causalité de
son travail**. La boucle normale :

```
Agent parent  →  Mission + WHY activation + Contraintes
                          ↓
Worker        →  Travail + Observation + Preuve
                          ↓
Retour parent →  Résultat + Pourquoi + Preuve + Apprentissage
```

**En succès**, il ne dit pas « terminé ». Il transmet : *j'ai réalisé X · pourquoi cette
action existait : Y · preuve : Z · conséquence : la condition demandée est satisfaite.*

**En échec**, il ne dit pas « impossible ». Il transmet : *la tâche existait pour Y ·
j'ai essayé A, B, C · résultat : échec · cause probable : D · je réveille le parent car E.*

**Sans Return Lineage**, le parent ne récupère qu'un fichier, une erreur, un log — et perd
le raisonnement, les essais, la causalité.

> *Mesure (annexe)* : champ `final_report`, 21 contrats — « ce qu'il a fait » exigé 12 fois,
> « la preuve » 16 fois, **« pourquoi » 0 fois**.

## 4. Persistence Lineage — qu'est-ce qui survit après la disparition d'un agent ?

La survie doit résister au changement d'agent · de modèle · à l'escalade · à une nouvelle
session · à la compression de contexte.

| Survit | Disparaît |
|---|---|
| fichiers écrits · manifest signé · audit · preuves | compréhension temporaire · architecture pensée mais non écrite · décisions restées dans le contexte |

### Persister ne suffit pas — il faut une identité stable

Un artefact peut survivre et **perdre son lien avec la réalité**. `mutation_triage.json`
survit ; ses ancres `name@line` ne correspondent plus après modification. Le texte existe,
**la référence est morte**.

```
Persistance + Identité stable = Lignée exploitable
```

---

## Interaction des quatre lignées

Une action valide répond aux quatre questions :

1. Pourquoi le projet existe ? → **Intent**
2. Pourquoi cette tâche existe ? → **Activation**
3. Pourquoi cet agent revient vers son parent ? → **Return**
4. Qu'est-ce qui restera après lui ? → **Persistence**

## Critère de validation double

Avant toute action :

- **Cohérence projet** — cette action reste-t-elle fidèle à l'intention humaine ?
- **Cohérence tâche** — répond-elle au problème mesuré, avec la bonne preuve ?

Une action n'est valide que si **les deux** réponses sont positives.

## Application aux workflows parallèles

Lorsqu'un input humain lance plusieurs génomes :

```
Input humain
   ├── Genome A → agents → retour
   ├── Genome B → agents → retour
   └── Genome C → agents → retour
```

Chaque branche devient une **expérience**. Elle doit conserver son intention, sa raison
d'activation, ses résultats et ses apprentissages. Sinon le système accumule seulement des
tentatives. Avec les lignées causales :

```
Hypothèse → Expérience → Résultat → Lesson → Mutation suivante
```

## Règle finale

Aucun agent n'est autorisé à disparaître avec une partie de l'histoire. Chaque agent
transmet : ce qu'il a fait · pourquoi il l'a fait · ce qu'il a appris · pourquoi le niveau
supérieur ou inférieur doit agir ou continuer.

La Forge devient une organisation apprenante **non parce que chaque agent est intelligent,
mais parce que la causalité collective survit aux agents**.

## Clarification — la lignée se termine proprement

Le niveau supérieur ou inférieur agit ou continue **uniquement si** :

- une cause non résolue persiste ;
- une preuve manque ou contredit l'état attendu ;
- une opportunité d'apprentissage ou de correction existe ;
- ou si la chaîne causale n'est pas encore fermée.

**Sinon, la lignée se termine proprement, sans action supplémentaire.**

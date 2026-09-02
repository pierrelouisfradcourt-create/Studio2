# FORGE — ARCHITECTURE CIBLE FONCTIONNELLE

*2026-09-01 · **DOCUMENTED_ONLY** · aucun code, aucun déplacement, aucune suppression, aucun test
exécuté. Dépôt source à `feeb29cb`, non touché.*
*Runtime réel : **Claude Opus 5** (`GPT-5.6-Codex` demandé, indisponible — `fallback` déclaré).*

Critère directeur : **OPTIMAL, pas MINIMAL.** Une capacité reste si elle apporte une valeur
démontrée à la création, même si elle grossit le système. Une capacité sort du **chemin
obligatoire** si elle n'est utile que dans certains contextes — sortir du chemin obligatoire n'est
pas être supprimée.

---

## 1 · Principes

**P1 — Le workflow est piloté par le jeu, pas par une file.** Une vision entre ; la Forge
constitue les capacités nécessaires, les fait travailler sur un objet commun, arbitre, construit,
mesure.

**P2 — L'objet central est le jeu, matérialisé par un `GAME_BLUEPRINT`.** Aujourd'hui l'objet
central est *le run* : 13 artefacts se succèdent et l'optimisation devient « est-ce que l'étape
suivante passe ? ». Demain les spécialistes amendent **le même objet**.

**P3 — Les capacités sont chargées à la demande.** Aucune n'est traversée par principe.

**P4 — Une capacité obligatoire doit avoir une raison écrite.** Trois seulement le sont (§4).

**P5 — Intention et observation ne fusionnent jamais.** Le Blueprint porte l'intention ; EVIDENCE
porte le mesuré ; la divergence se rend visible, elle ne se corrige pas en silence.

**P6 — Les garde-fous survivent au changement de forme.** Contrat validé avant tout spawn ·
oracles déterministes non-LLM · verdict signé re-vérifié · HumanGate seul juge de valeur ·
`NO_CLAIM_ALLOWED`. Chacun est né d'un incident réel : ils ne se renégocient pas parce qu'on change
la topologie.

**P7 — Le premier build est le vrai jeu.** Incomplet en contenu, jamais jetable en architecture.

---

## 2 · `GAME_BLUEPRINT` — l'objet central

Un artefact unique et **vivant**, lu et amendé par tous les spécialistes.

```
GAME_BLUEPRINT
├── identity          projet · genre · référence commerciale · rang (si le rail s'applique)
├── vision            fantasy · expérience joueur visée · audience · sensation recherchée
├── research          ← §6 : attentes, frustrations, abandons, références, différenciation
├── understanding     ← §7/§8 : World Scan (le marché) · Prisme (les mécanismes des références)
├── gameplay          core loop · actions · buts · échec · progression · contenu
├── systems           les nombres : économie, courbes, coûts, pressions, fenêtres
├── design_metrics    les CIBLES mesurables (session, décision, difficulté, économie, lisibilité)
├── ux                affordances · lisibilité · feedback · onboarding · états d'erreur
├── art               identité visuelle · mood · composition · personnages · environnement · UI
├── technical         plateforme · moteur · input · performance · contraintes d'architecture
├── constraints       must_have · must_not_have · scope · budget
├── feature_map       exigence → capacité → PREUVE ATTENDUE          ← §9
├── wiremap           fonction → fichier → PREUVE RÉELLE → statut     ← §9
└── decisions         arbitrages du Director, avec leur raison et leur date
```

**Ce qui existe déjà et sert de socle** : `FORGE_PROJECT_INPUT_V0` (Brief, entrée canonique
ratifiée 2026-08-29 — 10 champs dont `provenance` **par champ**, source absente = FAIL) et
`FORGE_DESIGN_FREEDOM_SPEC_V0` (N1–N9, ratifiée 2026-08-30).

**Ce que le Brief n'a pas** : `design_metrics`, `art`, `ux`, `technical`, `research`,
`understanding`. Le Brief dit *ce qu'on cherche* ; le Blueprint dit *ce qu'est le jeu*.

**Ce qui est déjà produit mais dispersé en sorties d'étapes** — à rapatrier comme **sections** du
Blueprint, pas à réinventer : `charter.yaml`, `art_bible.md`, `economy.json`, `loop.json`,
`featuremap.json`, `wiremap.json`, `gm_worldscan.json`, `prisme.json`, `design_state.json`,
`story_bible.json`.

### Propriété — qui écrit quoi
C'est ici qu'on empêche le spaghetti de revenir.

| section | écrit par | amendable par | gardien |
|---|---|---|---|
| `vision` · `constraints.must_not_have` · `scope` | **Pierre seul** | personne | HumanGate |
| `design_metrics` (les **cibles**) | **Pierre** | System Design propose des **valeurs**, jamais les cibles | règle de variance |
| `research` · `understanding` | capacités de recherche | Director valide la pertinence | traçabilité des sources |
| `gameplay` · `systems` · `ux` · `art` · `technical` | le spécialiste du domaine | Director arbitre | Red Team conteste |
| `feature_map` · `wiremap` | dérivés, jamais saisis à la main | — | couverture bidirectionnelle (§9) |
| `decisions` | **Director seul** | — | daté, motivé |
| **jugement de valeur sur le jeu** | **personne** | — | **Pierre joue** |

---

## 3 · Fable — Game Director

**Pas une étape.** Fable ne figure dans aucun ordre et ne doit jamais y figurer.

```
comprendre l'intention → décider ce qu'il faut savoir → constituer l'équipe
→ faire travailler les spécialistes sur LE MÊME Blueprint → arbitrer les conflits
→ autoriser le build → faire mesurer → présenter à Pierre
```

**Ce qui existe déjà** : `contracts/orchestrator.yaml`, dont l'en-tête grave
*« Pierre → session Claude à contexte propre → agent orchestrateur → workers »*, et `roles.yaml`
qui distingue `orchestrator` (**la session**, résolue par aucun code) de `run_orchestrator`
(l'agent). Le rôle est déjà nommé et déjà séparé de l'exécution.

**Ce qui manque** : Fable ne compose rien. Aujourd'hui un humain choisit un `profile` sur la ligne
de commande. Le Director doit choisir **des capacités**, pas un assemblage pré-écrit.

**Ce que Fable ne fait jamais** : écrire du code de jeu · rendre un verdict d'oracle · juger si le
jeu est bon · écrire dans `vision` ou `must_not_have`.

---

## 4 · Modèle de capacités dynamiques

Une capacité = **une responsabilité permanente** + un contrat + une preuve de ce qu'elle produit.
Pas une position dans une file.

```
                         GAME_BLUEPRINT
                               │
                         FABLE / DIRECTOR
                               │
   ┌──────────┬────────────┬───┴────┬───────────┬──────────┬──────────┐
   ▼          ▼            ▼        ▼           ▼          ▼          ▼
RECHERCHE  GAMEPLAY     SYSTEM     UX          ART       TECH       RED TEAM
  genre     DESIGN      DESIGN                 DIR       ARCHI      (contradiction)
   │          │            │        │           │          │          │
World Scan  ────────── travaillent sur le MÊME Blueprint ──────────── conteste
Prisme      ──────────           arbitrage Director        ──────────
   │                                   │
   └── KB (consultable) ───────────────┘
                                       ▼
                            BUILD ORCHESTRATOR  (§10)
                                       ▼
                                   VRAI JEU
                                       ▼
                        MEASURE · QA · RED TEAM  (§11)
                                       ▼
                              HUMAN PLAYTEST
```

### Les trois seules capacités obligatoires — et leur raison
| capacité | pourquoi obligatoire |
|---|---|
| **Compréhension du genre** (§6) | concevoir sans savoir pourquoi les joueurs *abandonnent* ce genre, c'est concevoir à l'aveugle |
| **QA mécanique + verdict signé** | un jeu non mesuré n'est pas un jeu livré. `ADR-002` |
| **HumanGate** | seul producteur de vérité de valeur |

Tout le reste est **à la demande** : World Scan, Prisme, KB, Red Team, QA visuelle, Observer,
Story Bible, chaîne asset.

### État mesuré des capacités
| capacité | ce qui l'incarne | statut |
|---|---|---|
| Recherche genre | `s2-worldscan` (déclare `run: WebSearch, WebFetch`, `skill: world-scan`) | IMPLEMENTED |
| Gameplay Design | `s0-contrat` (charter) · `s3-decompo` | IMPLEMENTED |
| **System Design** | `economy.json`, `loop.json` — **sorties sans propriétaire** | **PASSIVE — rôle à créer** |
| **UX** | — | **NOT_FOUND** |
| Art Direction | `s2.5-artbible` (profil mono-étape) · `redteam-artdirector` | IMPLEMENTED |
| Narration / GM | `s2.6-story-bible` · `s2.7-gm-worldscan` (2 profils mono-étape) | IMPLEMENTED |
| Tech Architecture | `s4-archi` · `s5-wiremap` | IMPLEMENTED |
| Build | `s9-build` ×4 (html · standard · godot · godot-standard) | IMPLEMENTED |
| QA mécanique | `s10a` · `s10s` · mutation · solvabilité | TESTED |
| QA visuelle | `s10d` · `product_oracle_godot` (capture GPU) | IMPLEMENTED |
| QA design | `s1-prisme` (1 agent) | IMPLEMENTED |
| Red Team | `s6-redteam-plan` (profil `review`) · `s11-redteam-code` | IMPLEMENTED · **indépendance BLOCKED** |
| Verdict / preuve | `s12-verdict` · `verify_run` · HMAC | TESTED |
| Observation | `TOOLS/observer/` | IMPLEMENTED |

**Deux trous mesurés** : **UX n'existe nulle part** (ni étape, ni contrat, ni oracle) et **System
Design n'est pas un rôle**. Ce sont exactement les deux endroits où se fabrique le « mécaniquement
valide mais pas un jeu » — critère OPTIMAL : **ici on ajoute**.

---

## 5 · Communication entre agents

Aujourd'hui la communication est **un passage de relais** : chaque étape lit l'artefact de la
précédente. Un désaccord ne peut donc s'exprimer qu'en aval, trop tard.

Cible — **trois canaux, aucun implicite** :

| canal | ce qu'il transporte | forme | garde |
|---|---|---|---|
| **Amendement** | un spécialiste modifie SA section du Blueprint | écriture tracée : auteur · section · raison | il ne peut écrire que sa section (§2) |
| **Question** | un spécialiste a besoin d'une décision d'un autre | question adressée, avec sa raison | **reste ouverte** — un freeze avec question ouverte est interdit |
| **Objection** | un spécialiste conteste une décision | objection horodatée, **conservée même si rejetée** | ne bloque pas, ne disparaît pas |

**Ce qui existe déjà et le prouve faisable** : `design_questions.json` (matérialisé pour la
première fois au RUN 1, 2 questions ART→GM répondues) · les objections conservées dans les
verdicts (`HUMANGATE_READY_WITH_OBJECTION`) · la doctrine ratifiée de **complétion mutuelle
Art ↔ GM** (« le jeu émerge de l'échange ; pas de freeze avec question ouverte »).

**Arbitrage** : le Director tranche, inscrit la décision dans `decisions` avec sa raison. Une
décision non écrite n'existe pas.

---

## 6 · Recherche de genre — le départ

**Toute création commence par comprendre le terrain.** Ce n'est pas une étape `s1` : c'est une
**précondition de connaissance** que le Director doit satisfaire avant de concevoir.

```
RESEARCH
├── attentes des joueurs          ├── critiques presse
├── frustrations récurrentes      ├── mécaniques appréciées / rejetées
├── POURQUOI LES JOUEURS          ├── problèmes UX · difficulté · progression
│   ABANDONNENT ce genre          ├── jeux de référence · succès · flops
└── éléments différenciants       └── opportunités
```

La question la plus utile n'est pas « quels sont les meilleurs tower defense ? » mais
**« pourquoi les joueurs les abandonnent-ils ? »** — c'est elle qui produit des `must_not_have`.

**Le résultat alimente le Blueprint** (`research`), il ne devient pas un rapport oublié.

### ⚠ Deux réserves que je dois poser
**(a) Conflit avec un verrou actif.** `00_CURRENT_CONTEXT.md`, « Verrous actifs (Pierre,
2026-08-29) », verbatim : *« **World Scan : hors périmètre** (scission Modèle 3 = recommandation
d'audit, non ouverte) »* et *« **R8** (premier `gm_worldscan.json` réel conforme) : **BLOQUÉ**
jusqu'à signal — préalable de toute décision de topologie World Scan »*. Faire de la recherche le
départ obligatoire **contredit un verrou que tu as posé**. Je ne le lève pas : à trancher.

**(b) « Obligatoire » réintroduit une station par la porte de derrière.** Résolution proposée :
la recherche est obligatoire **par genre non encore étudié**, et son résultat est **capitalisé dans
la KB**. Un second tower defense ne re-cherche pas : il consulte. La précondition porte sur *l'état
de la connaissance*, pas sur *chaque run*. Sans cela, on a remplacé `s0` par `s-research`.

---

## 7 · World Scan — capacité, pas étape

Répond à : **« que se passe-t-il actuellement dans ce genre / ce marché ? »** — concurrents,
tendances, conventions, innovations, critiques, opportunités.

Existe : `s2-worldscan` + `s2.7-gm-worldscan`, deux profils mono-étape (`gm_worldscan`,
`amont_only`, `amont_narratif`), un oracle `check_worldscan.mjs`, un worker Qwen calibré et validé.
**Rien à construire — seulement à débrancher du chemin obligatoire.**

⚠ Sous le verrou (a) ci-dessus.

---

## 8 · Prisme — rétro-ingénierie et détection d'angles morts

Répond à une **autre** question : **« comment ces jeux fonctionnent-ils réellement ? »**

```
référence → boucles → mécaniques → progression → économie → UX
          → feedback → difficulté → contenu → rétention
```

Et surtout : **« qu'aurions-nous oublié si nous ne l'avions pas étudié ? »** C'est sa fonction la
plus précieuse — **détecteur de zones d'ombre du design**.

Existe : `s1-prisme` (1 agent, **ACTIF**), `prisme.json`, `check_prisme.mjs`. Le **panel
multi-lentilles** (`panel.py`, `prisme/merge_prisme.mjs`) est gelé, jamais branché : `--charter`
jamais passé, `panel.LENSES` jamais alimenté. **Le Prisme survit, le panel non.**

**Lien mesuré et structurant** : `s3-decompo` exige que chaque feuille cite l'`id` **exact** d'une
exigence de `prisme.json` (`source_ref`). Le Prisme n'est donc pas décoratif — **il est la source
des exigences traçables**. Le supprimer casserait la couverture de §9.

---

## 9 · Feature Map / Wiremap / Décomposition — **mesuré, verdict clair**

### Décomposition : sa responsabilité EST démontrée
Contrat `s3-decompo` : *« Produire l'arbre Système→Feature→capacité ; **chaque FEUILLE porte sa
preuve attendue** »*, avec deux **règles dures** :
> `source_ref` cite l'`id` EXACT d'une exigence de `prisme.json` — **une feuille qui n'en cite
> aucune est une invention non déclarée, et une exigence que nulle feuille ne porte est une
> omission silencieuse.**

Ce n'est pas un terme vague. C'est **la couverture bidirectionnelle exigence ↔ capacité**, et
c'est le mécanisme anti-spaghetti le plus fort de toute la chaîne actuelle.
→ **La « décomposition » disparaît comme mot ; sa sortie EST la Feature Map.**

### Feature Map et Wiremap ne se recouvrent pas — mesure
Comparaison des artefacts réels de `p2_alpha`, `card_engine`, `chain_probe_v1` :

```
FEUILLE de featuremap (s3-decompo)          ENTRÉE de wiremap (s5-wiremap)
{ id: "cap_e2_clic_entree",                 { feature: "R1 objectif terminal affiché…",
  capacite: "ENTREE : le joueur agit…",       fonction: "currentObjective",
  source_ref: "E2",            ← exigence     fichiers: ["economy.mjs"],      ← réel
  expected_proof: {                           preuve: "logic.test.mjs 'R1…' : égalité
    kind: "bot_action",                                de chaîne EXACTE… e2e.mjs vérifie…",
    statement: "Depuis main.tscn, un bot…" }  couvre: ["currentObjective"],
}                                             statut: "IMPLEMENTED", version, implemented_at }
        ↑ LA PREUVE ATTENDUE                          ↑ LA PREUVE RÉELLE
```

| | Feature Map | Wiremap |
|---|---|---|
| question | **QUOI** doit exister, et **quelle preuve on attend** | **COMMENT** c'est relié, et **quelle preuve existe** |
| ancre | exigence Prisme (`source_ref`) | fonction + fichier réels |
| moment | avant le build | pendant / après le build |
| porte un statut | non | **oui** (`IMPLEMENTED`, `version`, `implemented_at`) |
| ids partagés (p2_alpha) | 26 ids | 25 entrées — **intersection : 0** |

**Verdict : conservation distincte.** Ce sont les deux extrémités d'une chaîne de traçabilité.
Les fusionner détruirait la distinction *attendu / réel*, qui est exactement ce que ce studio
passe son temps à défendre.

### ⚠ Le vrai défaut n'est ni l'un ni l'autre — c'est la jointure
**0 identifiant en commun.** Rien ne relie mécaniquement `expected_proof` (Feature Map) à `preuve`
(Wiremap). La chaîne existe en deux moitiés qui ne se parlent pas.

C'est le même défaut que `TRANSITION_INTEGRITY NOT_FOUND` du Shadow Audit, à une autre jointure :
non pas gel→build, mais **besoin→implémentation**. Et cela explique mécaniquement le finding de
PAIRE 2 : *« économie = canon Cookie Clicker, interdit du Brief violé, non gardé par oracle »* — le
`must_not_have` du Brief n'est jamais devenu une feuille, donc jamais une preuve attendue, donc
jamais un oracle.

> **Critère OPTIMAL : ici on ajoute, on ne retire pas.** La jointure
> `feature_map.expected_proof ↔ wiremap.preuve` est la capacité manquante la plus rentable
> identifiée par cette passe.

---

## 10 · Build Orchestrator et architecture

**Hypothèse à tester, retenue :** l'architecture technique n'est **pas** une étape fixe. Elle est
**dérivée du Blueprint** et déclenchée quand le Build Orchestrator reçoit assez de design pour
construire.

```
Blueprint (gameplay · systems · ux · art · technical · constraints · feature_map)
        │
        ▼
BUILD ORCHESTRATOR
        ├── Technical Architect   → wiremap (squelette + relations)
        ├── Builders spécialisés  → le vrai jeu
        └── condition de démarrage : le design est-il suffisant ?
```

**Condition de démarrage — mesurable, pas au jugé** : toute exigence du Prisme est portée par au
moins une feuille de Feature Map, et toute feuille porte un `expected_proof`. C'est **la règle dure
de `s3-decompo`, promue en porte d'entrée du build**. Elle existe déjà ; elle change seulement de
rôle : de contrôle d'étape à **critère de suffisance du design**.

Ce que ça résout : l'architecte reçoit **la réalité du jeu à construire**, pas un artefact abstrait
hérité d'une étape précédente.

---

## 11 · QA · Evidence · Human Playtest

**Séparation stricte, déjà ratifiée dans ce studio :**

```
QA + MEASURE  →  « voici ce que le jeu FAIT réellement »       (jamais « c'est bon »)
HUMAN         →  « j'ai envie d'y jouer / je n'ai pas envie »  (jamais mécanique)
```

| couche | ce qu'elle produit | existe |
|---|---|---|
| QA mécanique | reçus d'oracle signés · mutation · solvabilité | TESTED |
| QA visuelle | capture GPU réelle (fenêtre Godot obligatoire) | IMPLEMENTED |
| QA design | conformité aux `design_metrics` du Blueprint | **PARTIEL — la mesure existe, la cible n'est pas déclarée** |
| Red Team | contradiction, **advisory, jamais juge du code** | IMPLEMENTED, indépendance BLOCKED |
| Evidence | `verdict.json` signé HMAC, re-vérifié `AUTHENTIQUE` | TESTED |
| Human Playtest | le seul jugement de valeur | HumanGate |

⚠ **`design_metrics` héritent d'une règle déjà ratifiée** : *toute métrique qui classe, génère ou
calibre doit prouver qu'elle porte une information variable* (≥2 valeurs distinctes non triviales).
Sinon on refabrique `ticks == plus-court-chemin` : une métrique qui validait le moteur et ne
mesurait pas ce que son nom promettait. **Une métrique de design qui ne distingue pas deux jeux est
un faux confort.**

---

## 12 · Boucle de rework

```
VRAI JEU → MEASURE/QA → HUMAN PLAYTEST
                              ├── VALIDÉ  → release
                              └── REWORK  → Director
                                            │
                                   amende le BLUEPRINT (pas le code directement)
```

**La boucle passe par le Blueprint, jamais par un patch direct du jeu.** Sinon le Blueprint devient
faux et l'objet central redevient le run.

---

## 13 · Critère de sortie

Une boucle sans critère de sortie redevient la spirale sous un autre nom. Mesuré : Pacman a pris
**8 run_dirs** ; Kitten Clicker a échoué le HumanGate « jeu complet » après **11 runs** ; Breakout
V2 n'est clos qu'avec **3 flags acceptés en l'état**.

Proposition — **quatre conditions, toutes nécessaires** :
1. **Couverture** : toute exigence portée par une feuille, toute feuille par une preuve réelle
   (la jointure de §9 est verte).
2. **Métriques** : les `design_metrics` du Blueprint sont mesurées et dans leurs bandes, ou l'écart
   est **explicitement accepté** par Pierre.
3. **Objections** : aucune objection ouverte non tranchée ; une objection rejetée reste consignée.
4. **Jugement** : Pierre a joué et dit oui.

Et un **critère d'arrêt distinct du critère de qualité** — règle déjà ratifiée : *un défaut adjacent
ne devient pas automatiquement le prochain lot*. Le rework traite ce qui a fait échouer 1–4, pas ce
qu'on a remarqué en passant.

---

## 14 · Mapping préliminaire EXISTANT → CIBLE

`KEEP` · `REUSE` (recyclé sous un autre rôle) · `ADD` · `REMOVE` (du V2, pas du dépôt source) ·
`UNKNOWN`. **Aucune suppression exécutée par cette passe.**

| existant | consommateur mesuré | devient | décision |
|---|---|---|---|
| `dispatch.ORDER` (13) + `PROFILES` (19) | `driver.py:348` | le Director compose ; les 5 profils mono-étape sont déjà des capacités nommées | **REPLACE** |
| 28 contrats, 17 champs | `load_contract` + porte fail-closed | **chartes de rôle** — un contrat l'est déjà | **KEEP — le socle** |
| `s0-contrat` | driver | section `gameplay` du Blueprint | REUSE |
| `s2-worldscan` (`WebSearch`/`WebFetch`) | profils `amont_*` | capacité Recherche + World Scan | REUSE |
| `s1-prisme` + `prisme.json` | driver, **source des `source_ref`** | capacité Prisme / angles morts | **KEEP** |
| `s3-decompo` → `featuremap.json` | s5, oracles | section `feature_map` | **KEEP** (mot « décomposition » abandonné) |
| `s5-wiremap` → `wiremap.json` | `s10c`, `s10s`, builder | section `wiremap` | **KEEP** |
| **jointure `expected_proof ↔ preuve`** | **0 identifiant partagé** | porte de suffisance du build | **ADD** |
| `s2.5-artbible` · `s2.6` · `s2.7` | profils mono-étape | Art Direction · Narration · GM | REUSE |
| `s4-archi` | driver | Technical Architect sous Build Orchestrator | REUSE |
| `s9-build` ×4 | driver | Builders | KEEP |
| oracles (`s10a/b/c/d/s`, mutation, solvabilité) | `gate.forge_gate` | QA mécanique et visuelle | KEEP |
| `s6-redteam-plan` · `s11-redteam-code` | driver | Red Team, advisory | KEEP |
| `s12-verdict` · `verify_run` · HMAC | `gate` | Evidence | KEEP |
| KB `knowledge_base/` | contract · kb_proposal · driver · preflight · observer | capacité consultable + **capitalisation de la recherche** (§6b) | KEEP |
| boucle d'apprentissage | driver | la seule boucle qui tourne vraiment (18/326) | KEEP |
| `TOOLS/observer/` | humain, lien Forge prouvé | preuve runtime | KEEP |
| `escalate.py` | driver | politique de tier | KEEP |
| `.claude/` | runtime Claude Code | porte d'entrée réelle | KEEP ⚠ **câblage jamais testé** |
| **UX** | — | rôle + section Blueprint | **ADD** |
| **System Design** | `economy.json`/`loop.json` orphelins | rôle propriétaire des nombres | **ADD** |
| panel Prisme multi-lentilles (8 f.) | **aucun** (`--charter` jamais passé) | — | REMOVE |
| île MCTS / candidate_selector (17 f.) | **0 appelant** | remplacée par le Director | REMOVE |
| `wiremap_nav` (2 f.) | 0 | — | REMOVE |
| `control_plane` | 3 fn/9, 1 import bloquant `contract.py:76` | résolution de rôle interne à la Forge | REMOVE du V2 |
| `council` / Qwen | `runtime.py`, import paresseux | red-team indépendante = capacité à concevoir si un profil l'exige | REMOVE |
| 7 CLI de protocole de paires | 0 dans V2 | servaient l'**expérience sur le workflow**, pas la fabrication | REMOVE |
| `reference_guard` | driver, 11 réf. — **349 diffs/run, DRIFT n'atteint aucune décision** | ? | **UNKNOWN** |
| chaîne asset (`asset_geometry`, `asset_producer`) | **hors du fermé transitif** de `run_real` | capacité à la demande | **UNKNOWN** |
| rail des 25 nœuds | `RAIL_REGISTER.md` | plan de portefeuille **ou** carte de compétences ? | **UNKNOWN** |

---

## 15 · Inconnues et décisions restantes

| # | question | pourquoi elle bloque |
|---|---|---|
| **Q1** | **Où vit le contrat d'un agent composé dynamiquement ?** `ADR-002` impose « aucun sous-agent sans contrat validé », porte fail-closed. Un agent composé à la volée n'a pas de contrat pré-écrit. | **le garde-fou le plus fragile** — il s'évapore par glissement, pas par décision |
| **Q2** | Le verrou « World Scan hors périmètre » + R8 BLOQUÉ — la recherche obligatoire le contredit | §6(a) |
| **Q3** | La recherche est-elle obligatoire **par genre** (capitalisée en KB) ou **par run** ? | par run = on a remplacé une station par une autre |
| **Q4** | Qui pose les `design_metrics`, et comment prouve-t-on leur variance ? | une métrique qui ne distingue pas deux jeux est un faux confort |
| **Q5** | UX et System Design : rôles à créer, ou absences assumées ? | les deux trous où naît le « valide mais pas un jeu » |
| **Q6** | Le rail de 25 nœuds reste-t-il le plan ? Tower Defense y est au rang 9, derrière un jalon 0 bloquant | un rail est un pipeline à l'échelle du portefeuille |
| **Q7** | `reference_guard` · chaîne asset | UNKNOWN, à mesurer avant décision |

### Contrôles de validation demandés
| contrôle | résultat |
|---|---|
| cohérence interne | OK — chaque section renvoie à une mesure ou déclare UNKNOWN |
| **absence de workflow linéaire obligatoire** | OK **sous réserve Q3** — la recherche obligatoire est le seul point où une station pourrait se réintroduire ; §6(b) propose la parade |
| chaque capacité obligatoire a une raison | OK — 3 obligatoires, raisons écrites (§4) |
| Feature Map / Wiremap / décomposition | **mesuré** : responsabilités distinctes, 0 id partagé → conservation distincte ; « décomposition » abandonné comme mot, sa sortie est la Feature Map |
| garde-fous conservés | OK — P6 : contrat, oracles non-LLM, verdict signé, HumanGate, NO_CLAIM |
| rework a un critère de sortie | OK — 4 conditions nécessaires (§13) |

---

```
status_by_surface:
  architecture_target:            DOCUMENTED_ONLY
  existing_capabilities_mapping:  DOCUMENTED_ONLY
  implementation:                 BLOCKED
  runtime_validation:             BLOCKED
  featuremap_wiremap_overlap:     TESTED          # 3 runs comparés, 0 id partagé
  decomposition_responsibility:   TESTED          # règle dure lue au contrat
  research_capability:            IMPLEMENTED     # s2-worldscan déclare WebSearch/WebFetch
  ux_role:                        NOT_FOUND
  system_design_role:             NOT_FOUND
  expected_proof_join:            NOT_FOUND       # la capacité manquante la plus rentable
  dynamic_agent_contract (Q1):    BLOCKED
```
`software_verdict: OK` (document) · `evidence_verdict: MECHANICAL_VALIDATION_ONLY` ·
`claim_verdict: NO_CLAIM_ALLOWED` · `no_global_ready_verdict: true`

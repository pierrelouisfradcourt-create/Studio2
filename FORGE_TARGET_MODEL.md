# FORGE — MODÈLE CIBLE

*2026-09-01 · **DOCUMENTED_ONLY** · aucun code, aucun déplacement, aucune suppression, aucun test
exécuté. Dépôt source à `feeb29cb`, non touché.*
*Runtime réel : **Claude Opus 5** (`GPT-5.6-Codex` indisponible — `fallback` déclaré).*
*Ce document **remplace** `FORGE_TARGET_ARCHITECTURE.md`, qui devient un brouillon superflu.*

Critère : **OPTIMAL, pas MINIMAL.** Sortir du chemin obligatoire ≠ être supprimé.

---

## 1 · Mission exacte de la Forge

> **Transformer une vision humaine en jeu réel, vérifiable, le plus vite possible — sans jamais
> confondre ce que le jeu est censé être avec ce qu'il fait réellement.**

Ce que la Forge **n'est pas** : un pipeline, un daemon, un orchestrateur autonome, un juge de la
valeur du jeu. Claude Code l'appelle ; Pierre juge ; elle fabrique et elle mesure.

Trois choses qu'elle doit produire à chaque fois : **un jeu réel**, **la preuve de ce qu'il fait**,
**la trace de ce qui a été décidé et pourquoi**.

---

## 2 · Objet central — `GAME_BLUEPRINT`

Aujourd'hui l'objet central est *le run* : 13 artefacts se succèdent, et l'optimisation devient
« est-ce que l'étape suivante passe ? ». Demain, **un seul objet, vivant, que tous amendent**.

```
GAME_BLUEPRINT
├── identity        projet · genre · référence commerciale
├── vision          fantasy · expérience visée · audience · sensation recherchée
├── research        attentes · frustrations · POURQUOI ILS ABANDONNENT · références · différenciation
├── understanding   World Scan (le marché) · Prisme (les mécanismes des références)
├── gameplay        core loop · actions · buts · échec · progression · contenu
├── systems         les nombres : économie, courbes, coûts, pressions, fenêtres
├── design_metrics  les CIBLES mesurables (session · décision · difficulté · économie · lisibilité)
├── ux              affordances · lisibilité · feedback · onboarding · états d'erreur
├── art             identité · mood · composition · personnages · environnement · UI
├── technical       plateforme · moteur · input · performance · contraintes
├── constraints     must_have · must_not_have · scope · budget
├── feature_map     exigence → unité constructible → PREUVE ATTENDUE
├── wiremap         fonction → fichier → PREUVE RÉELLE → statut
├── questions       questions ouvertes entre spécialistes (jamais silencieuses)
└── decisions       arbitrages du Director : quoi · pourquoi · quand
```

**Socle existant** : `FORGE_PROJECT_INPUT_V0` (Brief, entrée ratifiée 2026-08-29, `provenance` par
champ — source absente = FAIL) + `FORGE_DESIGN_FREEDOM_SPEC_V0` (N1–N9, ratifiée 2026-08-30).
**Manquent au Brief** : `research`, `understanding`, `systems`, `design_metrics`, `ux`, `art`,
`technical`. Le Brief dit *ce qu'on cherche* ; le Blueprint dit *ce qu'est le jeu*.

**Déjà produits, à rapatrier comme sections** (pas à réinventer) : `charter.yaml`, `art_bible.md`,
`economy.json`, `loop.json`, `featuremap.json`, `wiremap.json`, `prisme.json`, `gm_worldscan.json`,
`story_bible.json`, `design_questions.json`, `design_state.json`.

### Propriété — qui écrit quoi
| section | écrit | amendable par | gardien |
|---|---|---|---|
| `vision` · `must_not_have` · `scope` | **Pierre seul** | personne | HumanGate |
| `design_metrics` (les **cibles**) | **Pierre** | System Design propose des **valeurs** | preuve de variance |
| `research` · `understanding` | capacités de recherche | Director juge la pertinence | traçabilité des sources |
| `gameplay` `systems` `ux` `art` `technical` | le spécialiste du domaine | tous **par question ou objection** | Red Team |
| `feature_map` · `wiremap` | dérivés, jamais saisis | — | couverture bidirectionnelle (§9) |
| `questions` · `decisions` | tous / **Director seul** | — | aucune question effacée |
| **valeur du jeu** | **personne** | — | **Pierre joue** |

---

## 3 · Responsabilités de Fable — Game Director

**Fable ne figure dans aucun ordre et ne doit jamais y figurer.**

| responsabilité | ce que ça veut dire concrètement |
|---|---|
| **Comprendre l'intention** | lire la vision, identifier ce qu'il faut *savoir* avant de concevoir |
| **Décider ce qu'il faut savoir** | KB suffisante ? sinon Research. Références à disséquer ? sinon pas de Prisme |
| **Constituer l'équipe** | choisir **les capacités**, pas un assemblage pré-écrit |
| **Faire travailler sur le même objet** | tous amendent le Blueprint, personne ne passe un relais |
| **Arbitrer** | trancher les objections, inscrire la décision **avec sa raison** dans `decisions` |
| **Juger la suffisance du design** | autoriser le build quand la porte de §10 est verte |
| **Faire mesurer** | déclencher QA / oracles / Observer |
| **Présenter à Pierre** | le jeu, ses mesures, les écarts, les objections conservées |

**Ce que Fable ne fait jamais** : écrire du code de jeu · rendre un verdict d'oracle · juger si le
jeu est bon · écrire dans `vision` ou `must_not_have` · effacer une question ouverte.

**Existe déjà** : `contracts/orchestrator.yaml` grave *« Pierre → session Claude à contexte propre
→ agent orchestrateur → workers »* ; `roles.yaml` distingue `orchestrator` (**la session**, résolue
par aucun code) de `run_orchestrator` (l'agent). **Le rôle est nommé et déjà séparé de l'exécution.**
**Manque** : la composition. Aujourd'hui un humain choisit un `profile` en ligne de commande.

---

## 4 · Capacités disponibles

Une capacité = **responsabilité permanente** + contrat + preuve de ce qu'elle produit.

| capacité | question à laquelle elle répond | incarnée par | statut |
|---|---|---|---|
| **Research** | que veulent / que fuient les joueurs de ce genre ? | `s2-worldscan` (`run: WebSearch, WebFetch`, `skill: world-scan`) | IMPLEMENTED |
| **World Scan** | que se passe-t-il dans ce marché ? | `s2-worldscan` · `s2.7-gm-worldscan` · `check_worldscan.mjs` | IMPLEMENTED |
| **Prisme** | comment ces jeux fonctionnent-ils vraiment ? qu'aurions-nous oublié ? | `s1-prisme` · `prisme.json` · `check_prisme.mjs` | IMPLEMENTED |
| **Gameplay Design** | quelle boucle, quelles actions, quel échec ? | `s0-contrat` (charter) | IMPLEMENTED |
| **System Design** | quels **nombres** produisent cette sensation ? | `economy.json` `loop.json` — **sorties sans propriétaire** | **PASSIVE — rôle à créer** |
| **UX** | le joueur comprend-il ce qu'il voit et ce qu'il peut faire ? | — | **NOT_FOUND** |
| **Art Direction** | à quoi ça ressemble, et pourquoi ? | `s2.5-artbible` · `redteam-artdirector` | IMPLEMENTED |
| **Narration / GM** | quel monde, quelle voix ? | `s2.6-story-bible` · `s2.7-gm-worldscan` | IMPLEMENTED |
| **Technical Architecture** | comment le jeu est-il structuré pour être construit ? | `s4-archi` · `s5-wiremap` | IMPLEMENTED |
| **Build** | fabriquer le vrai jeu | `s9-build` ×4 (html · standard · godot · godot-standard) | IMPLEMENTED |
| **QA mécanique** | que fait le code, réellement ? | `s10a` · `s10s` · mutation · solvabilité | TESTED |
| **QA visuelle** | que voit-on à l'écran, réellement ? | `s10d` · `product_oracle_godot` (capture GPU) | IMPLEMENTED |
| **Red Team** | qu'est-ce qui ne tient pas ? | `s6-redteam-plan` · `s11-redteam-code` | IMPLEMENTED · indépendance BLOCKED |
| **Evidence** | qu'est-ce qui est prouvé, signé, re-vérifiable ? | `s12-verdict` · `verify_run` · HMAC | TESTED |
| **Observation** | qu'a fait le run, vraiment ? | `TOOLS/observer/` | IMPLEMENTED |
| **KB** | qu'avons-nous déjà appris ? | `knowledge_base/` (50 entrées, 7 `validated`) | IMPLEMENTED |

**14 capacités sur 16 existent déjà.** Les deux manquantes — **UX** et **System Design** — sont
exactement les deux endroits où se fabrique le « mécaniquement valide mais pas un jeu ».
Critère OPTIMAL : **ici on ajoute**.

---

## 5 · Rôles dynamiques

**Le piège à éviter, nommé** : remplacer `s0 → s12` par `agent A → agent B → agent C` serait le
même pipeline repeint.

Ce qui rend le modèle dynamique, en trois propriétés :

1. **Composition** — Fable choisit les capacités selon le Blueprint. Un jeu sans narration n'appelle
   pas la Narration. Un genre déjà étudié n'appelle pas Research.
2. **Simultanéité** — les capacités convoquées travaillent **en même temps sur le même objet**, pas
   en file. Gameplay et Art peuvent écrire dans la même passe.
3. **Réversibilité** — une capacité peut être **rappelée** après que d'autres ont parlé. Il n'y a pas
   de « on est passé à l'étape suivante ».

**Preuve que le mécanisme existe déjà** : `dispatch.PROFILES` contient **19 profils, de 1 à 19
étapes**, dont **cinq mono-capacité** — `artbible`, `gm_worldscan`, `story_bible`, `review`,
`oracle_only`. Et le code dit pourquoi, verbatim : `micro` — *« Proportionnalité : pas de red-team
ni de design. **Évite la cérémonie 13 étapes sur 78 lignes** »* ; `proof_only` — *« **REMESURER SANS
RECONSTRUIRE** : rafraîchir un reçu exigeait un profil porteur d'un BUILDER — on reconstruisait le
jeu pour remplacer un certificat »*.

> **L'appel de capacité unique existe déjà. Il s'appelle un profil mono-étape.** Ce qui manque
> n'est pas le mécanisme, c'est le Director qui compose au lieu d'un humain qui choisit un profil.

---

## 6 · Communication inter-agents

Aujourd'hui : **passage de relais**. Chaque étape lit l'artefact de la précédente ; un désaccord ne
peut s'exprimer qu'en aval, trop tard.

Cible — **trois canaux, aucun implicite** :

| canal | transporte | forme | règle |
|---|---|---|---|
| **Amendement** | un spécialiste modifie **sa** section | auteur · section · raison | il ne peut écrire que sa section (§2) |
| **Question** | besoin d'une décision d'un autre | question adressée, avec sa raison | **reste ouverte** — freeze avec question ouverte interdit |
| **Objection** | contestation d'une décision | horodatée, **conservée même rejetée** | ne bloque pas, ne disparaît jamais |

C'est le `↕` : *« ce gameplay impose de changer l'architecture »* → *« possible, mais ça détruit la
métrique X »* → le System Designer révise les nombres → Fable tranche et inscrit la décision.

**Existe déjà et prouve la faisabilité** : `design_questions.json` (matérialisé au RUN 1 — 2
questions ART→GM répondues) · objections conservées dans les verdicts
(`HUMANGATE_READY_WITH_OBJECTION`) · doctrine ratifiée de **complétion mutuelle Art ↔ GM** :
*« le jeu émerge de l'échange ; pas de freeze avec question ouverte »*.

---

## 7 · Cycle Design → Build → Measure → Rework

```
        VISION ──▶ [savoir ?] ──▶ BLUEPRINT ──▶ FABLE
                                                  │
                    ┌──────────┬──────────┬───────┴───┬──────────┐
                    ↕          ↕          ↕           ↕          ↕
                GAMEPLAY   SYSTEMS   UX / ART      TECH      RED TEAM
                    ↕          ↕          ↕           ↕          ↕
                    └──────────┴────┬─────┴───────────┴──────────┘
                                    ↕   (amendement · question · objection)
                            porte de suffisance (§10)
                                    ▼
                            BUILD ORCHESTRATOR ──▶ VRAI JEU
                                                      ▼
                              MEASURE · QA · OBSERVER · RED TEAM
                                                      ▼
                                            HUMAN PLAYTEST
                                       ┌──────────────┴──────────────┐
                                    VALIDÉ                        REWORK
                                                                     │
                                              amende le BLUEPRINT ───┘
                                                  (jamais le code seul)
```

**Le rework passe par le Blueprint.** Patcher le jeu sans amender le Blueprint rend le Blueprint
faux, et l'objet central redevient le run.

---

## 8 · Research · World Scan · Prisme

**Aucun des trois n'est une étape.** Ce sont des outils que le Director appelle.

```
VISION
  ▼
« que savons-nous déjà de ce genre ? »
  ├── KB suffisante ────────────────▶ utiliser
  └── non ──▶ RESEARCH (web) ──▶ avis joueurs · presse · concurrents · flops
                                 attentes · frustrations · POURQUOI ILS ABANDONNENT
                                        ▼
                                       KB          ← capitalisé, pas un rapport oublié
  ▼
« faut-il comprendre en profondeur les références ? »
  └── oui ──▶ PRISME : boucles · mécaniques · progression · économie · UX · feedback
                       difficulté · contenu · rétention
                       et surtout : QU'AURIONS-NOUS OUBLIÉ ?
```

**Research** : la question la plus utile n'est pas « quels sont les meilleurs tower defense ? » mais
**« pourquoi les joueurs les abandonnent-ils ? »** — c'est elle qui produit des `must_not_have`.

**Prisme** : détecteur de **zones d'ombre du design**. Et il n'est pas décoratif — `s3-decompo`
exige que chaque unité constructible cite l'`id` **exact** d'une exigence de `prisme.json`. Le
Prisme est **la source des exigences traçables** ; le retirer casserait la couverture de §9.

**Condition de connaissance, pas condition de run** : obligatoire **par genre non encore étudié**,
capitalisé en KB. Un second tower defense consulte au lieu de chercher. Sans cette nuance, on a
remplacé `s0` par `s-research`.

> ⚠ **Verrou actif à lever ou confirmer.** `00_CURRENT_CONTEXT.md`, « Verrous actifs (Pierre,
> 2026-08-29) », verbatim : *« **World Scan : hors périmètre** »* et *« **R8** : **BLOQUÉ** jusqu'à
> signal »*. Faire de la recherche le départ contredit ce verrou. Je ne le lève pas.

---

## 9 · Feature Map vs Wiremap — et la décomposition

### La décomposition n'est plus une étape
Sa fonction utile — **transformer une vision/feature en unités constructibles et vérifiables** —
devient une fonction du **Director + System Designer**, et son résultat **nourrit la Feature Map**.

```
Blueprint ──▶ Director + spécialistes ──▶ features ──▶ unités constructibles ──▶ Wiremap
```
et non plus `étape Décomposition → étape Feature Map`.

**Ce qu'il ne faut surtout pas perdre en la dissolvant** — la règle dure de `s3-decompo`, verbatim :
> *« `source_ref` cite l'`id` EXACT d'une exigence de `prisme.json` — **une feuille qui n'en cite
> aucune est une invention non déclarée, et une exigence que nulle feuille ne porte est une omission
> silencieuse.** »*

C'est **la couverture bidirectionnelle exigence ↔ unité**. Elle survit comme **invariant du
Blueprint**, plus comme contrôle d'étape.

### Les deux ne se recouvrent pas — mesuré
Artefacts réels de `p2_alpha`, `card_engine`, `chain_probe_v1` :

```
feature_map (avant build)                    wiremap (pendant / après)
  id: "cap_e2_clic_entree"                     feature: "R1 objectif terminal affiché…"
  capacite: "ENTREE : le joueur agit…"         fonction: "currentObjective"      ← réel
  source_ref: "E2"          ← exigence         fichiers: ["economy.mjs"]         ← réel
  expected_proof: {kind, statement}            preuve: "logic.test.mjs 'R1…' égalité EXACTE…"
        ↑ LA PREUVE ATTENDUE                   statut: "IMPLEMENTED" · version · implemented_at
                                                     ↑ LA PREUVE RÉELLE
```

| | Feature Map | Wiremap |
|---|---|---|
| question | **QUOI** le jeu doit contenir pour réaliser la vision | **COMMENT** le jeu réel est structuré |
| ancre | exigence Prisme | fonction + fichier réels |
| moment | avant le build | pendant / après |
| statut | non | **oui** (`IMPLEMENTED`, `version`, `implemented_at`) |
| ids (p2_alpha) | 26 | 25 — **intersection : 0** |

**Conservation distincte.** Les fusionner détruirait la distinction *attendu / réel* — celle que ce
studio passe son temps à défendre.

### ⚠ La jointure manquante — la capacité la plus rentable identifiée
```
BLUEPRINT REQUIREMENT ──▶ FEATURE ──▶ WIREMAP IMPLEMENTATION ──▶ EXPECTED PROOF ──▶ ACTUAL PROOF
                                   ╲___________ 0 identifiant partagé ___________╱
```
La chaîne existe **en deux moitiés qui ne se parlent pas**. Même défaut que
`TRANSITION_INTEGRITY NOT_FOUND`, à une autre jointure : **besoin → implémentation**.

Et cela explique mécaniquement le finding de PAIRE 2 — *« économie = canon Cookie Clicker, interdit
du Brief violé, non gardé par oracle »* : le `must_not_have` n'est jamais devenu une unité, donc
jamais une preuve attendue, donc jamais un oracle. C'est exactement
*« on avait prévu ça quelque part »* devenu *« on a oublié de le construire »*.

---

## 10 · Build Orchestrator et architecture

**L'architecture n'est pas une étape fixe.** Elle est **dérivée du Blueprint** et déclenchée quand
le Build Orchestrator reçoit assez de design.

```
Blueprint (gameplay · systems · ux · art · technical · constraints · feature_map)
        ▼
BUILD ORCHESTRATOR
   ├── Technical Architect  → wiremap (structure + relations réelles)
   ├── Builders             → le vrai jeu
   └── PORTE DE SUFFISANCE  → mesurable, pas au jugé
```

**Porte de suffisance** — la règle dure de `s3-decompo` promue en condition d'entrée du build :
*toute exigence portée par au moins une unité ; toute unité portant un `expected_proof`*. Elle
existe déjà ; elle change de rôle, de contrôle d'étape à **critère de suffisance du design**.

L'architecte reçoit ainsi **la réalité du jeu à construire**, pas un artefact abstrait hérité d'une
étape précédente.

**Le premier build est le vrai jeu.** Incomplet en contenu, jamais jetable en architecture.

---

## 11 · KB · Oracles · Observer · Evidence

| | rôle | règle qui le protège |
|---|---|---|
| **KB** | mémoire de ce qui a été **appris et ratifié** ; capitalise la Research | *une proposition sous `proposals/` n'est **jamais** servie — seules son identité et son état « non ratifiée » le sont. Servir son contenu court-circuiterait le HumanGate.* (verbatim du code) |
| **Oracles** | ce que le code **fait**, mesuré sans LLM | déterministes non-LLM ; le `software_verdict` ne vient QUE de reçus vérifiés |
| **Observer** | ce que le **run** a fait | lien Forge prouvé ; sorties à réancrer sur `EVIDENCE/` |
| **Evidence** | mémoire des **faits observés**, signée et re-vérifiable | HMAC + `verify_run` → `AUTHENTIQUE` ou refus ; `RUN_INDEX` append-only |

**Boucle de connaissance — fermée et exercée** : `learning_hook` → `learning_memory`
(`cause` est un **champ**, pas de la prose) → `kb_proposal` **propose-only** → `catalog.json` →
injection contrôlée. Quatre **statuts dans un seul magasin**, jamais quatre dossiers.
Goulot mesuré : **18 ratifiées sur 326**. Le point de friction est humain.

---

## 12 · Garde-fous — dérivés, pas décidés à l'avance

Tu avais raison de refuser que « où vit le contrat d'un agent dynamique » soit tranché comme un
problème isolé. **Une fois §3–§6 posés, la réponse se mesure.**

### Ce que la porte valide réellement — mesuré
`hook_guard.check_spawn` ne lit **aucun fichier de contrat**. Il lit un marqueur
`FORGE_DISPATCH:<etape>:<run_id>[:<attempt>]` dans le prompt de spawn, et le confronte au
**journal d'audit des dispatches** :
```
count == 1  → allow
count == 0  → refus (aucun dispatch enregistré pour cette clé)
count >= 2  → refus (ambiguïté / rejeu)
```

**L'invariant réel n'est donc pas « il existe un fichier YAML »**, c'est :
> **un spawn n'est autorisé que s'il correspond à exactement UN dispatch préalablement enregistré.**

### Conséquence — la composition dynamique ne casse pas le garde-fou
Un rôle composé par Fable satisfait la porte s'il :
1. **remplit les 13 champs Critiques** (`role`, `capability_role`, `exigences_cognitives`,
   `memoire`, `mandatory_read`, `objectif`, `in_scope`, `out_of_scope`, `permissions`, `gardeFou`,
   `success_criteria`, `tests_oracles`, `output_contract`) — c'est ce qui rend un contrat
   *activable* ;
2. **passe par `prepare_dispatch`**, qui valide et **enregistre** ;
3. **est spawné une seule fois** avec le marqueur correspondant.

Le fichier sur disque est un **détail d'implémentation**, pas l'invariant. Q1 est donc **dérivée,
pas ouverte** : le contrat vit là où `prepare_dispatch` le valide et l'enregistre.

⚠ Réserve honnête : je l'ai **lu**, je ne l'ai pas **exécuté** sur un contrat composé
dynamiquement. C'est une déduction de lecture, à confirmer par un test au moment du patch.

### Les garde-fous conservés, sans négociation
Contrat validé avant tout spawn (fail-closed) · oracles déterministes non-LLM · red-team
**advisory, jamais juge du code** · verdict signé HMAC re-vérifié · **HumanGate seul juge de
valeur** · `claim_verdict: NO_CLAIM_ALLOWED` · propose-only sur toute écriture durable ·
*une preuve provient du mécanisme qui a agi, sinon `AUTO_ATTESTED`*.

---

## 13 · Critère de sortie

Mesuré : Pacman **8 run_dirs** · Kitten Clicker **11 runs** puis FAIL « jeu complet » · Breakout V2
clos avec **3 flags acceptés en l'état**. Une boucle sans critère de sortie redevient la spirale.

**Quatre conditions, toutes nécessaires :**
1. **Couverture** — toute exigence portée par une unité, toute unité par une preuve réelle : la
   jointure de §9 est verte.
2. **Métriques** — les `design_metrics` sont mesurées et dans leurs bandes, **ou** l'écart est
   explicitement accepté par Pierre.
3. **Objections** — aucune objection ouverte non tranchée ; une objection rejetée reste consignée.
4. **Jugement** — Pierre a joué et dit oui.

Et un **critère d'arrêt distinct du critère de qualité**, règle déjà ratifiée : *un défaut adjacent
ne devient pas automatiquement le prochain lot*. Le rework traite ce qui a fait échouer 1–4.

⚠ `design_metrics` héritent d'une règle ratifiée : *toute métrique qui classe, génère ou calibre
doit prouver qu'elle porte une information variable*. Sinon on refabrique
`ticks == plus-court-chemin` — une métrique qui validait le moteur sans mesurer ce que son nom
promettait. **Une métrique qui ne distingue pas deux jeux est un faux confort.**

---

## 14 · Mapping vers l'ancien Studio

| ancien élément | consommateur mesuré | nouvelle fonction | action |
|---|---|---|---|
| `dispatch.ORDER` (13) | `driver.py:348` | — | **RETIRER** — le workflow imposé |
| `dispatch.PROFILES` (19) | `driver.py:348` | 5 mono-capacité = déjà des appels de capacité | **REMPLACER** par composition dynamique |
| 28 contrats, 17 champs | `load_contract` + porte | **chartes de rôle** | **CONSERVER — le socle** |
| `s0-contrat` | driver | section `gameplay` | recycler |
| `s2-worldscan` (`WebSearch`/`WebFetch`) | profils `amont_*` | capacités Research + World Scan | recycler |
| `s1-prisme` + `prisme.json` | driver · **source des `source_ref`** | capacité Reverse Engineering | **conserver** |
| `s3-decompo` | s5, oracles | **dissoute** : fonction Director/System Design ; sa règle dure devient invariant du Blueprint | **fusionner** dans Blueprint/Feature Map |
| `featuremap.json` | s5, oracles | section `feature_map` | conserver, repositionner |
| `s5-wiremap` → `wiremap.json` | `s10c`, `s10s`, builder | contrat de construction réel | **conserver** |
| **jointure `expected_proof ↔ preuve`** | **0 id partagé** | porte de suffisance + critère de sortie | **CONSTRUIRE** |
| `s2.5` · `s2.6` · `s2.7` | profils mono-étape | Art Direction · Narration · GM | recycler |
| `s4-archi` | driver | sous Build Orchestrator | **déplacer conceptuellement** |
| `s9-build` ×4 | driver | workers de construction | conserver |
| oracles `s10a/b/c/d/s` · mutation · solvabilité | `gate.forge_gate` | validation mécanique | conserver |
| `s6` · `s11` red-team | driver | contradiction, advisory | conserver |
| `s12-verdict` · `verify_run` · HMAC | `gate` | Evidence | conserver |
| KB `knowledge_base/` | contract · kb_proposal · driver · preflight · observer | mémoire + capitalisation Research | conserver |
| boucle d'apprentissage | driver | seule boucle qui tourne (18/326) | conserver |
| `TOOLS/observer/` | lien Forge prouvé | observation du jeu réel | conserver / rebrancher sur EVIDENCE |
| `escalate.py` | driver | politique de tier | conserver |
| `.claude/` | runtime Claude Code | porte d'entrée | conserver ⚠ câblage non testé |
| **UX** | — | rôle + section | **AJOUTER** |
| **System Design** | `economy.json`/`loop.json` orphelins | propriétaire des nombres | **AJOUTER** |
| panel Prisme multi-lentilles (8 f.) | **aucun** (`--charter` jamais passé) | — | retirer du V2 |
| île MCTS / candidate_selector (17 f.) | **0 appelant** | remplacée par le Director | retirer du V2 |
| `wiremap_nav` (2 f.) | 0 | — | retirer du V2 |
| `control_plane` | 3 fn/9, import bloquant `contract.py:76` | résolution de rôle interne | hors V2 |
| `council` / Qwen | `runtime.py`, paresseux | capacité à redéfinir si un profil l'exige | hors V2 |
| 7 CLI de protocole de paires | 0 dans V2 | servaient l'**expérience sur le workflow** | retirer du V2 |
| `reference_guard` | 11 réf. — 349 diffs/run, DRIFT sans effet | ? | **UNKNOWN** |
| chaîne asset | hors du fermé transitif de `run_real` | capacité à la demande | **UNKNOWN** |
| rail des 25 nœuds | `RAIL_REGISTER.md` | plan **ou** carte de compétences ? | **UNKNOWN** |

---

## 15 · Conserver · adapter · remplacer · retirer

| | éléments |
|---|---|
| **CONSERVER tel quel** | 28 contrats (17 champs) · oracles · verdict signé + `verify_run` · KB et sa règle de service · boucle d'apprentissage · Observer · builders · `escalate` · `.claude` |
| **ADAPTER** | `s2-worldscan` → Research/World Scan à la demande · `s1-prisme` → Reverse Engineering · `featuremap`/`wiremap` → sections du Blueprint · `s4-archi` → sous Build Orchestrator · Observer → sorties vers EVIDENCE |
| **REMPLACER** | `ORDER` + `PROFILES` → composition dynamique par Fable · Brief → `GAME_BLUEPRINT` |
| **FUSIONNER** | `s3-decompo` → fonction Director/System Design ; sa règle dure → invariant de couverture |
| **AJOUTER** | rôle **UX** · rôle **System Design** · **jointure `expected_proof ↔ actual_proof`** · `design_metrics` avec preuve de variance |
| **RETIRER du V2** | panel Prisme (8) · île MCTS (17) · `wiremap_nav` (2) · 7 CLI de protocole |
| **HORS V2** | `control_plane` · `council` · `openclaw` · anciennes lanes |
| **UNKNOWN** | `reference_guard` · chaîne asset · statut du rail |

---

## 16 · Questions encore ouvertes

| # | question | pourquoi elle compte |
|---|---|---|
| **Q1** | Verrou « World Scan hors périmètre » + R8 BLOQUÉ — la Research en départ le contredit | §8 · je ne lève pas un verrou de Pierre |
| **Q2** | Research obligatoire **par genre** (capitalisée KB) ou **par run** ? | par run = on a remplacé une station par une autre |
| **Q3** | Qui pose les `design_metrics`, et comment prouve-t-on leur variance ? | une métrique qui ne distingue pas deux jeux est un faux confort |
| **Q4** | UX et System Design : rôles à créer, ou absences assumées ? | les deux trous où naît le « valide mais pas un jeu » |
| **Q5** | Le rail de 25 nœuds reste-t-il le plan ? | Tower Defense y est au rang 9, derrière un jalon 0 bloquant |
| **Q6** | `reference_guard` · chaîne asset | UNKNOWN, mesurer avant décision |
| **Q7** | La déduction de §12 tient-elle à l'exécution ? | lue, pas testée sur un contrat composé dynamiquement |
| ~~Q0~~ | ~~où vit le contrat d'un agent dynamique~~ | **DÉRIVÉE** — §12 : là où `prepare_dispatch` le valide et l'enregistre |

---

### Contrôles de validation
| contrôle | résultat |
|---|---|
| cohérence interne | OK — chaque section renvoie à une mesure ou déclare UNKNOWN |
| **pas de workflow linéaire obligatoire** | OK **sous réserve Q2** — seul point où une station peut se réintroduire |
| capacités obligatoires justifiées | OK — 3 seulement : compréhension du genre · QA+verdict · HumanGate |
| Feature Map / Wiremap / décomposition | **mesuré** : 0 id partagé → distinctes ; décomposition dissoute, sa règle dure conservée |
| garde-fous conservés | OK — §12, invariant de porte mesuré |
| rework a un critère de sortie | OK — 4 conditions nécessaires (§13) |
| **pas de pipeline repeint** | OK — composition · simultanéité · réversibilité (§5), et le `↕` de §6 |

```
status_by_surface:
  architecture_target:            DOCUMENTED_ONLY
  existing_capabilities_mapping:  DOCUMENTED_ONLY
  implementation:                 BLOCKED
  runtime_validation:             BLOCKED
  gate_invariant (§12):           TESTED       # lu dans hook_guard.check_spawn
  featuremap_wiremap_overlap:     TESTED       # 3 runs, 0 id partagé
  decomposition_responsibility:   TESTED       # règle dure lue au contrat
  research_capability:            IMPLEMENTED  # s2-worldscan déclare WebSearch/WebFetch
  ux_role:                        NOT_FOUND
  system_design_role:             NOT_FOUND
  expected_proof_join:            NOT_FOUND
```
`software_verdict: OK` (document) · `evidence_verdict: MECHANICAL_VALIDATION_ONLY` ·
`claim_verdict: NO_CLAIM_ALLOWED` · `no_global_ready_verdict: true`

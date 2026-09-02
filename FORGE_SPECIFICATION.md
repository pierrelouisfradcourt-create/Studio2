# FORGE — SPÉCIFICATION CIBLE

*2026-09-01 · **DOCUMENTED_ONLY** · aucun code, aucun patch, aucun déplacement, aucune suppression,
aucun renommage. Dépôt source à `feeb29cb`, non touché.*

**Règle de conception** : *ne rien reconstruire que le vieux Studio sait déjà faire correctement.*
**Règle d'opération** : *on ne déplace jamais un fichier du vieux Studio — on le **copie**.*

---

## Principe directeur *(figé)*

> La Forge n'est plus une succession d'étapes qui transforme un brief en jeu.
> C'est un **environnement de capacités collaboratives** qui transforme une **vision** en jeu,
> avec **Fable** comme directeur et le **`GAME_BLUEPRINT`** comme objet partagé.

Pas de `ORDER` central. **Mais l'absence d'ordre n'est pas l'absence de règles** : l'ordre imposé
est remplacé par des **règles de coordination** (§7, §8, §14).

---

## ⚠ Une inversion à trancher — et pourquoi les deux intuitions sont justes

Ta séquence dit `FEATURE MAP → WIREMAP → TECH ARCHITECT`. La chaîne actuelle fait l'inverse, et
c'est **écrit dans le contrat** :
```
s5-wiremap  mandatory_read : « blueprint.yaml produit par l'étape 4 »
            permissions    : « read: repo + blueprint + featuremap »
            out_of_scope   : « ne décide pas l'ownership (c'est l'archi) »
```
La wiremap **lit** l'architecture aujourd'hui. Et l'artefact mesuré le confirme — une entrée de
`wiremap.json` porte `fonction · fichiers · preuve · statut · version · implemented_at` : **c'est
une carte d'implémentation**, elle ne peut pas précéder les modules.

**Mais ce que tu décris sous le mot « wiremap » est autre chose** — tu l'écrivais toi-même :
`Spawn → Enemy → Path → Tower detects → Target → Attack → Damage → Death → Reward → Upgrade →
nouvelle décision`. **C'est un flux de jeu, pas une carte de fichiers.** Et lui peut, et doit,
précéder l'architecture.

**Résolution : deux objets, deux noms.** Les deux intuitions sont justes, elles portent sur deux
choses différentes.

| objet | contenu | moment | existe ? |
|---|---|---|---|
| **`GAME_FLOW`** | relations entre éléments de jeu : quel événement produit quel effet, quelle décision rouvre quelle boucle | **avant** l'architecture | **NOT_FOUND** — proche de `loop.json`, mais `loop.json` est une projection de `prisme.json`, pas un flux conçu |
| **`IMPLEMENTATION_MAP`** *(ex-`wiremap.json`)* | `feature · fonction · fichiers · preuve · couvre · statut` | **après** l'architecture | **IMPLEMENTED**, consommé par `s10c` et `s10s` |

Séquence qui satisfait les deux :
```
DESIGN → FEATURE MAP → GAME_FLOW → TECH ARCHITECTURE → IMPLEMENTATION_MAP → BUILD
              ↕            ↕              ↕                    ↕
              └────────────┴──────────────┴────────────────────┘   bidirectionnel
```
L'architecte reçoit **ce que le jeu doit contenir** (Feature Map) **et comment ça circule**
(Game Flow) — il n'invente plus le design pour pouvoir construire. Et il peut répondre
*« cette feature est impossible / coûteuse / contradictoire »*.

---

## 1 · Objet central — `GAME_BLUEPRINT`

Objet **vivant**, versionné, avec historique des décisions. Jamais figé à l'entrée.

```
GAME_BLUEPRINT
├── vision                fantasy · sensation recherchée · audience
├── genre_context         ← Research (§9)
├── player_experience
├── gameplay              core_loop · actions · goals · failure · progression
├── features[]            feature · rationale · requirement_refs · expected_proof
├── systems               les nombres
├── economy
├── ux
├── art_direction
├── technical_direction
├── design_metrics        les CIBLES (posées par Pierre)
├── game_flow             ← relations entre éléments (§10)
├── constraints           must_have · must_not_have · scope · budget
├── decisions[]           arbitrages : quoi · pourquoi · qui · quand
└── open_questions[]      questions et objections en cours (§7)
```

**À ne pas confondre** : `ARCHITECTURE_CONTRACT` (ex-`blueprint.json`, produit par `s4-archi`)
contient `modules · deps_interdites · ownership · responsabilites`. Deux objets, deux noms.
*Renommage enregistré, non exécuté.*

**Réutilisé du vieux Studio** : `FORGE_PROJECT_INPUT_V0` (entrée canonique, `provenance` par champ,
entrées alternatives interdites, pré-vol fail-closed **avant toute dépense LLM**) ·
`context_manifest` (empreinte sha256 du Blueprint au manifeste d'exécution).

---

## 2 · Mission de Fable

| responsabilité | règle |
|---|---|
| comprendre l'intention | reformuler, faire confirmer par Pierre |
| décider ce qu'il faut savoir | Research systématique (§9), Prisme si les références doivent être disséquées |
| **composer l'équipe** | choisir les capacités selon le Blueprint — §3 |
| faire converger | arbitrer questions et objections, inscrire chaque décision **avec sa raison** |
| autoriser le build | quand la porte de suffisance est verte (§10) |
| faire mesurer | déclencher QA, oracles, Observer |
| présenter | le jeu, ses mesures, ses écarts, ses objections conservées |

**Jamais** : écrire du code de jeu · rendre un verdict d'oracle · juger si le jeu est bon · écrire
dans `vision`/`must_not_have`/`design_metrics` · effacer une question ouverte.

**Réutilisé** : `orchestrator.yaml` (*« Pierre → session Claude à contexte propre → agent
orchestrateur → workers »*) · `roles.yaml` (sépare `orchestrator` = **la session** de
`run_orchestrator` = l'agent) · la boucle du `driver` · `escalate.py` (haiku→sonnet→opus).
**À construire** : la composition (aujourd'hui `self.order = order_for_profile(profile)`).

---

## 3 · Catalogue des capacités

| capacité | question | source réutilisée |
|---|---|---|
| **Research** | que veulent, que fuient les joueurs de ce genre ? | `s2-worldscan` (`run: WebSearch, WebFetch`) |
| **Prisme** | comment les références fonctionnent ? qu'oublierions-nous ? | `s1-prisme` · `prisme.json` |
| **Gameplay** | quelle boucle, quelles actions, quel échec ? | `s0-contrat` → charter |
| **System Design** | quels nombres produisent cette sensation ? | `loop_spec.mjs` · `game_master_schema.mjs` (projections **pures**) |
| **UX** | le joueur comprend-il ce qu'il voit et peut faire ? | **aucune — à construire** |
| **Art Direction** | à quoi ça ressemble, pourquoi ? | `s2.5-artbible` + `redteam-artdirector` |
| **Narrative** | quel monde, quelle voix ? | `s2.6-story-bible` · `s2.7-gm-worldscan` |
| **Feature Definition** | quelles unités vérifiables ? | `s3-decompo` (dissoute en capacité) |
| **Tech Architecture** | quels modules, quelles dépendances interdites ? | `s4-archi` → `ARCHITECTURE_CONTRACT` |
| **Implementation Map** | où et comment le jeu réel contient cela ? | `s5-wiremap` |
| **Build** | fabriquer le vrai jeu | `s9-build` ×4 |
| **QA mécanique** | que fait le code ? | `oracle` · `static_oracles` · `standard_oracles` · `mutation` |
| **QA visuelle** | que voit-on à l'écran ? | `product_oracle_godot` (capture GPU) |
| **QA design** | les métriques sont-elles atteintes ? | **aucune — à construire** |
| **Red Team** | qu'est-ce qui ne tient pas ? | `s6` · `s11` · advisory |
| **Evidence** | qu'est-ce qui est prouvé ? | `verdict` HMAC · `verify_run` |
| **Observer** | qu'a fait le run ? | `TOOLS/observer/` |
| **KB** | qu'avons-nous déjà appris ? | `knowledge_base/` + `kb_proposal` propose-only |

**Équipes selon le projet** — la Forge reste riche, le projet choisit ce qu'il en utilise :
```
tower defense  Research · Prisme · Gameplay · Systems · UX · Art · Archi · Build · QA
petit puzzle   Research · Gameplay · UX · Archi · Build · QA
jeu narratif   Research · Prisme · Narrative · Gameplay · UX · Art · Archi · Build · QA
```

---

## 4 · Quand une capacité peut être appelée

**Aucune n'est appelée par position.** Trois déclencheurs, et trois seulement :

| déclencheur | exemple |
|---|---|
| **convocation de Fable** | *« UX, le gameplay vient de changer — réévalue »* |
| **question adressée** (§7) | Gameplay demande à UX si le placement reste possible pendant une vague |
| **notification d'amendement** | une section dont je dépends a changé ⇒ je réévalue mes conséquences |

**Trois capacités obligatoires, et leur raison :**
1. **Research** — §9 : aucun projet ne commence sans vérifier le terrain réel, même légèrement.
2. **QA + verdict signé** — un jeu non mesuré n'est pas un jeu livré (ADR-002).
3. **HumanGate** — seul producteur de vérité de valeur.

---

## 5 · Ce qu'une capacité peut lire

**Le vocabulaire existe déjà** — champ `permissions` du contrat, forme réelle mesurée :
```
read: repo + blueprint + featuremap.  write: la WireMap uniquement.
create: WireMap.  run: aucun.  delete: aucun.
```
et `mandatory_read` = **précondition dure** (sources à lire avant toute action).

**Règle cible** : une capacité lit **tout le Blueprint** — la vision partagée est le point du
modèle. Ce qui est restreint, c'est l'écriture (§6), jamais la lecture.
`mandatory_read` reste la liste des sources **obligatoires** avant d'agir.

---

## 6 · Ce qu'une capacité peut produire

| capacité | écrit | ne touche jamais |
|---|---|---|
| Research | `genre_context` | tout le reste |
| Prisme | exigences tracées (ancres `requirement_refs`) | le design |
| Gameplay | `gameplay` | `systems`, `ux`, `art` |
| System Design | `systems`, `economy` | les **cibles** `design_metrics` |
| UX | `ux` | — |
| Art | `art_direction`, `asset_requests` | — |
| Narrative | narration, `gm_worldscan` | — |
| Feature Definition | `features[]` | — |
| Tech Architecture | `ARCHITECTURE_CONTRACT` | le design |
| Implementation Map | la carte d'implémentation | le Blueprint |
| Build | le jeu réel | le Blueprint |
| QA / Red Team | reçus, objections | tout le reste |
| Fable | `decisions[]` | toute section de spécialiste |
| **Pierre** | `vision` · `must_not_have` · `scope` · **cibles** `design_metrics` | — |

**Jamais écrits par un agent — invariant mesuré à conserver tel quel :**
```
run_real.py:2372  « loop.json est une PROJECTION DÉTERMINISTE de prisme.json. deriveLoopSpec
                    est une fonction PURE — AUCUN LLM n'écrit jamais ce fichier. Si un agent
                    tentait de l'écrire, ce serait IGNORÉ. »   + vérification sha256 au build
```
Idem `economy.json` (projection de `gm_worldscan.json`). **Les nombres du jeu sont dérivés, pas
rédigés.**

---

## 7 · Comment une capacité communique

**Une capacité ne modifie jamais le travail d'une autre.** Elle lui adresse un message. Trois
types, aucun autre.

```yaml
type: QUESTION
from: gameplay
to: ux
subject: tower_placement
question: >
  Le placement doit-il rester possible pendant une vague ?
reason:
  - impacte le rythme
  - impacte la lisibilité
  - impacte l'architecture input
blocking: true
```
```yaml
type: OBJECTION
from: architecture
to: gameplay
subject: enemy_pathing
claim: >
  La mécanique proposée nécessite une topologie dynamique incompatible
  avec l'architecture actuelle.
severity: blocking
```
```yaml
type: PROPOSAL
from: art
to: director
subject: enemy_readability
proposal: >
  Augmenter la différenciation des silhouettes.
evidence: [reference_game_03, visual_test_07]
```

**Règles :**
- une **question** reste ouverte jusqu'à réponse — *pas de freeze avec question ouverte* ;
- une **objection rejetée est conservée**, elle cesse de bloquer sans disparaître ;
- **Fable arbitre** et inscrit la décision dans `decisions[]` ;
- tout amendement d'une section **notifie** les capacités qui en dépendent.

**Réutilisé** : `design_questions.json` (matérialisé au RUN 1, 2 questions ART→GM répondues) ·
les objections conservées dans les verdicts (`HUMANGATE_READY_WITH_OBJECTION`) · la doctrine
ratifiée de **complétion mutuelle Art ↔ GM**.
**À construire** : la **notification**. Aujourd'hui c'est un passage de relais — un désaccord ne
peut s'exprimer qu'en aval, trop tard.

---

## 8 · Comment une capacité demande un rework

```
capacité  ──OBJECTION/PROPOSAL──▶  FABLE  ──amende──▶  GAME_BLUEPRINT
                                     │
                                     └──convoque──▶  les capacités concernées
```
**Le rework passe toujours par le Blueprint.** Patcher le jeu sans amender le Blueprint rend le
Blueprint faux — et l'objet central redevient le run.

Une capacité ne relance jamais le build elle-même. Elle remonte, Fable décide.

---

## 9 · Comment Research et Prisme alimentent le design

**Research est systématique** — au démarrage de **chaque** projet, même légèrement.

```
VISION → GENRE / SOUS-GENRE → RESEARCH → GENRE INSIGHT → GAME_BLUEPRINT.genre_context
                                 ├── joueurs · avis
                                 ├── presse spécialisée
                                 ├── jeux de référence
                                 ├── critiques récurrentes
                                 ├── attentes
                                 ├── frustrations
                                 └── flops / erreurs fréquentes
```
Profondeur variable, **jamais nulle** : genre neuf ⇒ recherche profonde ; genre déjà étudié ⇒
KB + complément ciblé. **La KB capitalise** pour que le 2ᵉ tower defense ne refasse pas le travail.

**Prisme ensuite, si les références doivent être disséquées :**
```
JEUX DE RÉFÉRENCE → PRISME → game patterns → attentes du genre → ANGLES MORTS → Blueprint
```
**Le croisement est le produit le plus utile** :
```
RESEARCH  « les joueurs détestent X »
   +
PRISME    « X vient de la mécanique Y »
   ↓
DECISION  « notre jeu évite / modifie Y »   → constraints.must_not_have
```

⚠ **Verrou actif** : `00_CURRENT_CONTEXT.md` — *« World Scan : hors périmètre »* et *« R8 :
BLOQUÉ jusqu'à signal »*. Research systématique le contredit. **Je ne le lève pas.**

---

## 10 · Feature Map → Game Flow → Architecture → Implementation Map → Build

```
FEATURE MAP           ce que le jeu doit avoir      requirement_refs + expected_proof
      ↕
GAME_FLOW             comment ça circule            événement → effet → décision
      ↕
TECH ARCHITECTURE     modules · deps_interdites · ownership     (ARCHITECTURE_CONTRACT)
      ↕
IMPLEMENTATION MAP    feature → fonction → fichiers → preuve → statut
      ↓
BUILD                 le vrai jeu
```
**Toutes les flèches sont bidirectionnelles.** L'architecte peut dire *« impossible / coûteux /
contradictoire »* et remonter — il **n'invente jamais** une décision de design pour continuer.

**Porte de suffisance du build — mesurable, pas au jugé.** C'est la règle dure de `s3-decompo`,
promue de contrôle d'étape en condition d'entrée :
> *« `requirement_refs` cite l'`id` EXACT d'une exigence — une feature qui n'en cite aucune est une
> **invention non déclarée**, une exigence que nulle feature ne porte est une **omission
> silencieuse**. »* + toute feature porte un `expected_proof`.

**L'invariant fondamental de la Forge** — plus important que toute étape :
```
requirement → feature → implementation → expected_proof → actual_proof
```
État mesuré : `featuremap` 26 ids · `wiremap` 25 entrées · **intersection 0**. La chaîne existe en
deux moitiés qui ne se parlent pas. **C'est la construction n°1.**

---

## 11 · Comment les métriques pilotent le design

```
VISION → DESIGN → METRICS → BUILD → MEASURE → COMPARE → REWORK → FABLE
```
Les `design_metrics` sont des **cibles posées par Pierre**, pas des mesures d'audit. Elles
descendent en paramètres des projections déterministes, et QA mesure l'écart.

```
QA     : « décision significative toutes les 5-12 s : NON ATTEINT (mesuré 21 s) »
FABLE  : « Gameplay et Systems réévaluent ce point »
→ Gameplay ↔ Systems ↔ Tech → nouvelle implémentation
```

⚠ **Règle héritée, non négociable** : *toute métrique qui classe, génère ou calibre doit prouver
qu'elle porte une information variable* (≥2 valeurs distinctes non triviales). Sinon on refabrique
`ticks == plus-court-chemin` — une métrique qui validait le moteur sans mesurer ce que son nom
promettait. **Une métrique qui ne distingue pas deux jeux est un faux confort.**

**Manque mesuré** : le chaînon `design_metrics → paramètres`. Aujourd'hui `prisme → loop.json` et
`gm_worldscan → economy.json` existent ; rien ne relie une intention chiffrée à ces projections.

---

## 12 · Comment QA produit l'évidence

| couche | dit | jamais |
|---|---|---|
| QA mécanique | ce que le code fait | si c'est bon |
| QA visuelle | ce qu'on voit à l'écran | si c'est beau |
| QA design | si les métriques sont atteintes | si le jeu est amusant |
| Red Team | ce qui ne tient pas — **advisory** | juge du code |

`gate.forge_gate` : oracle vert ⇒ verdict signé OK ; rouge, absent ou injouable ⇒ FAIL/BLOCKED.
*« L'appelant NE DOIT PAS poursuivre au-delà d'une porte non-OK. »* `verify_run` re-vérifie et rend
`AUTHENTIQUE` ou refuse. Le `software_verdict` ne provient **que** de reçus d'oracle vérifiés.
Invariant : *une preuve provient du mécanisme qui a réalisé l'action, sinon `AUTO_ATTESTED`*.

**Réutilisé tel quel** : ≈5 800 lignes d'oracles déterministes non-LLM, 14 tests `oracle` +
13 `mutation`, dont `mutation.py` — *« le MÉTA-oracle : tes tests attrapent-ils vraiment un bug ? »*.
**À construire** : QA design (les métriques n'existent pas encore).

---

## 13 · Comment HumanGate intervient

Pierre reçoit : **le jeu jouable** · ce qu'il fait, mesuré · les écarts · **les objections
conservées**. Il tranche merge / reject / freeze, et peut **accepter un écart explicitement** —
c'est une décision, pas un contournement.

Vocabulaire unique `OK / FAIL / BLOCKED`. Trois verdicts toujours séparés :
`software_verdict` · `evidence_verdict` · `claim_verdict: NO_CLAIM_ALLOWED`.

**Manque mesuré** : `decision-log.md` est **absent du V2**. Le gate peut produire un verdict, il
n'a pas où inscrire la décision.

---

## 14 · Comment le système sait qu'il peut arrêter le rework

**Quatre conditions, toutes nécessaires :**
1. **Couverture** — toute exigence portée par une feature ; toute feature reliée à une preuve
   réelle (l'invariant de §10 est vert).
2. **Métriques** — dans leurs bandes, **ou** écart explicitement accepté par Pierre.
3. **Objections** — aucune ouverte non tranchée ; une objection rejetée reste consignée.
4. **Jugement** — Pierre a joué et dit oui.

Et un **critère d'arrêt distinct du critère de qualité**, règle déjà ratifiée : *un défaut adjacent
ne devient pas automatiquement le prochain lot*. Le rework traite ce qui a fait échouer 1–4.

Repère mesuré, pour calibrer : Pacman **8 run_dirs** · Kitten Clicker **11 runs** puis FAIL
« jeu complet » · Breakout V2 clos avec **3 flags acceptés en l'état**.

---

## 15 · Anciennes capacités réutilisées, et sous quelle forme

**Copiées, jamais déplacées.** Le vieux Studio reste intact et devient une bibliothèque de pièces.

| réutilisé tel quel | forme dans la nouvelle Forge |
|---|---|
| oracles (≈5 800 l., 27 tests) | QA mécanique et visuelle, appelées à la demande |
| `verdict` HMAC + `verify_run` | Evidence — signature et re-vérification `AUTHENTIQUE` |
| porte de spawn (`hook_guard`, 28 tests) | inchangée — invariant *un spawn ⇔ un dispatch enregistré*, **compatible nativement avec la composition dynamique** |
| KB + règle de service | *« une proposition n'est jamais servie »* — inchangée |
| boucle d'apprentissage | inchangée — la seule boucle qui tourne (18/326) |
| projections déterministes | `loop_spec.mjs`, `game_master_schema.mjs` + verrou anti-écriture LLM |
| `s1-prisme`, `s2.5`, `s2.6`, `s2.7`, `s6`, `s11` | capacités appelées à la demande |
| 4 builders + squelette gelé | workers du Build Orchestrator |
| Observer (40 f.) | observation, sorties réancrées sur `EVIDENCE/` |
| 17 champs de contrat | **charte de rôle** — un contrat l'est déjà |

| transformé | de → vers |
|---|---|
| Brief | → `GAME_BLUEPRINT` vivant |
| `driver` + `PROFILES` | → composition dynamique par Fable |
| `s3-decompo` | → capacité **Feature Definition** ; sa règle dure → invariant du Blueprint |
| `s4-archi` | → Tech Architecture, déclenchée après Feature Map + Game Flow |
| `s5-wiremap` | → **Implementation Map**, après architecture |
| `blueprint.json` | → `ARCHITECTURE_CONTRACT` |

| construit | pourquoi |
|---|---|
| **UX** | `\bUX\b` : 2 contrats, et seulement comme *chose observée chez les concurrents* |
| **jointure `expected ↔ actual`** | 26 ids vs 25, **intersection 0** |
| **`GAME_FLOW`** | n'existe pas — `loop.json` est une projection, pas un flux conçu |
| **chaînon `design_metrics → projections`** | la moitié aval existe, l'amont non |
| **notification entre capacités** | aujourd'hui passage de relais |
| **`decision-log`** | destination absente du V2 |

| retiré du chemin | preuve |
|---|---|
| `dispatch.ORDER` (13) | le workflow imposé lui-même |
| panel Prisme multi-lentilles (8 f.) | `--charter` jamais passé |
| île MCTS / candidate_selector (17 f.) | **0 appelant** |
| `wiremap_nav` (2 f.) · contrat `s10d` | 0 consommateur · absent des 19 profils |
| `reference_guard` | **0 consommateur de décision** — 349 diffs/run sans destinataire |
| 7 CLI de protocole de paires | servaient l'expérience sur le workflow |
| `control_plane` · `council` · `openclaw` | ancien Studio |

**Six constructions neuves. Aucune n'est un framework** : un rôle (UX), un objet (`GAME_FLOW`),
un anneau (la jointure), un chaînon (métriques), une notification, un fichier (decision-log).

---

## Questions ouvertes

| # | question |
|---|---|
| Q1 | `GAME_FLOW` : objet neuf, ou extension de `loop.json` en levant son statut de projection ? |
| Q2 | Verrou *« World Scan hors périmètre »* + R8 — Research systématique le contredit |
| Q3 | Qui prouve la variance d'une `design_metric` avant qu'elle devienne une cible ? |
| Q4 | La notification : mécanisme runtime, ou discipline du Director ? |
| Q5 | Rail = catalogue de compétences (résolu) — mais qui décide du prochain jeu ? |

```
status_by_surface:
  specification:              DOCUMENTED_ONLY
  wiremap_ordering_conflict:  TESTED      # s5 mandatory_read: blueprint de l'étape 4
  permissions_vocabulary:     TESTED      # read/write/create/run/delete mesuré
  deterministic_projections:  TESTED      # verrou anti-écriture LLM + sha256
  coverage_invariant:         TESTED      # règle dure s3-decompo
  spawn_gate_compatibility:   TESTED      # un spawn ⇔ un dispatch enregistré
  game_flow:                  NOT_FOUND
  ux · metrics_chain · join · notification · decision_log:  NOT_FOUND
  implementation:             BLOCKED
```
`software_verdict: OK` (document) · `evidence_verdict: MECHANICAL_VALIDATION_ONLY` ·
`claim_verdict: NO_CLAIM_ALLOWED` · `no_global_ready_verdict: true`

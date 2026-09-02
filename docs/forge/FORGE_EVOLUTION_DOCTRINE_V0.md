# FORGE — DOCTRINE D'ÉVOLUTION V0

> **Statut** : PROPOSED — non commité. Issu des sessions du 2026-07-29 (Pierre × Fable).
> **Objet** : les règles qui gouvernent **comment la Forge change**. Pas comment elle fabrique.
> **Ce document ne prescrit aucun chantier.** Les chantiers vivent dans un charter daté ;
> la doctrine leur survit.
> `claim_verdict: NO_CLAIM_ALLOWED`

## Carte des documents

| Document | Responsabilité | Durée de vie |
|---|---|---|
| **celui-ci** | règles d'évolution : témoin, preuve, mutation, adoption | permanente |
| `docs/fvl/FVL_PHASE_0_5_CHARTER.md` | le chantier en cours : rendre l'expérience fiable | jusqu'à sa clôture |
| `docs/fvl/FVL_GAP_ANALYSIS.md` | mesure de recouvrement FVL ↔ V1 (Phase 0) | figée |
| `docs/fvl/FVL_PROVENANCE_ADDENDUM_V0.md` | **SUPERSEDED** — trace de raisonnement, deux erreurs corrigées depuis | archive, ne plus lire comme source |

---

## 0. Finalité

> **L'objectif n'est pas d'optimiser une chaîne existante une fois. L'objectif est de construire
> une Forge capable d'apprendre de ses propres écarts de production.**
> *(Ratifié Pierre, 2026-07-29 — énoncé directeur de tout ce document.)*

Conséquence de lecture : chaque règle qui suit doit se juger à cette aune. Une règle qui améliore
un run sans améliorer la capacité à apprendre d'un run est hors sujet ici — elle appartient à un
charter, pas à la doctrine.

### 0.1 Les quatre couches *(ratifié Pierre, 2026-07-29)*

| Couche | Contenu | Portée temporelle | Mutabilité | Écrite par |
|---|---|---|---|---|
| **Run** | ce qui s'est passé | un run | **immuable**, signée | la chaîne |
| **Failure event** | ce qui a échoué, et comment on l'a analysé | plusieurs runs | append-only, repliée à la lecture | l'analyse d'un run, puis les expériences |
| **Lesson** | ce que l'histoire suggère | plusieurs générations | **statut** révisable, jamais le passé | proposée depuis les failure events |
| **Doctrine** | les règles qui empêchent la Forge de se tromper sur son propre apprentissage | permanente | ratification humaine | **Pierre — aucun écrivain mécanique** |

Deux invariants tombent de ce tableau :

- **L'écriture ne remonte jamais.** Un run n'écrit pas une leçon ; une leçon n'écrit pas la
  doctrine. Chaque couche est alimentée par celle du dessous, jamais par celle du dessus. C'est la
  règle de dépendance à sens unique de l'architecture, appliquée au temps.
- **La doctrine est la seule couche sans écrivain mécanique.** C'est précisément ce qui empêche la
  Forge de réécrire les règles qui la jugent — le dernier cran du garde-fou dont §2.2 énumère les
  trois premiers.

---

## 1. Le témoin

Un laboratoire a besoin d'un témoin stable. Sans témoin, chaque amélioration peut simplement
déplacer la ligne de mesure.

### 1.0 Typologie des génomes

| Type | Rôle | Mutable | Comparable |
|---|---|---|---|
| **témoin gelé** — Pong | non-régression, ligne de mesure fixe | **non** | référence |
| **génome historique** — Snake V1 (chaîne Opus) | a servi à **découvrir les défauts** ; sa valeur est archivistique, pas métrique | non | à personne |
| **génome industriel** — Snake V2 | premier génome capable de **produire plusieurs jeux** et donc de fournir assez de données à la boucle | oui | aux runs de sa génération |
| **troisième génome** | **condition de généralisation** — voir §7 | oui | — |

> Le génome historique n'est pas un brouillon : c'est l'instrument qui a révélé les défauts que ce
> document existe pour corriger. On l'archive, on ne le compare pas, on ne le supprime pas.

Corollaire de la ligne « génome industriel » : la capacité à produire **plusieurs** jeux n'est pas
un objectif de productivité — c'est la condition d'existence du corpus. Sans plusieurs jeux, `scope:
generalized` reste inassertable (§7) et le Niveau 2 n'a rien à lire.

### 1.1 `reference_protected` — invariant

```yaml
reference_protected:
  - games/pong/**
  - tests/**
```

Protection **indépendante des contrats d'agents** · modification refusée ou soumise à ratification
explicite · trace obligatoire si une dérogation existe.

**Périmètre minimal ratifié (Pierre, 2026-07-29)** — trois éléments, pas un de plus. Pas de
gouvernance complète avant de relancer une calibration :

| Élément | Ce qu'il apporte | Complétude |
|---|---|---|
| protection du témoin | refus sur le chemin principal d'écriture | partielle |
| **détection de modification** | empreinte des arbres protégés, vérifiée à l'ouverture et à la clôture d'un run | **complète** |
| dérogation humaine explicite | la modification reste possible, jamais silencieuse | — |

> Ne pas confondre le minimal et l'optionnel : la **détection** est celle qui porte la complétude
> (§1.2). Une protection sans détection laisse passer tout ce qui écrit hors des outils de session.

**Constat du 2026-07-29** : ce gel n'était que documentaire. Vérifié sur trois surfaces — la liste
`deny` des permissions (qui couvre les commandes destructrices et la lecture des `.env`), la garde
de spawn, la garde git : aucune ne mentionne `games/pong/**` ni `tests/**`, pourtant déclarée
« ZONE PROTÉGÉE — aucun agent ne modifie ces fichiers ». Aucune écriture indue n'a été cherchée ni
observée : c'est une **absence de garantie**, pas un incident.

### 1.2 Aucun mécanisme unique ne suffit

| Surface d'écriture | Couverte par | Ce qui lui échappe |
|---|---|---|
| outils d'édition de session | entrée `deny` | tout ce qui écrit via un processus |
| commandes shell | garde `PreToolUse` (patron existant côté git) | un sous-processus lancé plus loin |
| sous-processus (build, exécuteur, scripts) | **rien** | — |

> La seule couche **complète** est une **empreinte de référence** : hachage des arbres protégés,
> vérifié à l'ouverture et à la clôture d'un run. C'est de la détection, pas de la prévention —
> mais c'est la seule qui ne dépende d'aucun chemin d'écriture, donc la seule conforme à la
> cinquième règle d'usine (*une garde est indépendante de l'état courant*).

Forme de la dérogation : réutiliser le précédent `.claude/HUMAN_GIT_OVERRIDE.json`, déjà dans la
liste `deny` — un fichier de ratification que la session ne peut pas s'auto-écrire.

---

## 2. Trois sources de progression, trois régimes de preuve

| Source | Produit | Régime |
|---|---|---|
| journal d'erreurs + leçons | des motifs récurrents | **déclaratif** — saisi par un agent ou un humain |
| troisième cerveau | de la connaissance accumulée | **mémoire** — oriente, ne mesure pas |
| branches d'expériences | un écart attribuable à une variable | **mécanique** — la seule qui prouve |

> **Les deux premières engendrent des hypothèses ; la troisième seule les valide.** Une leçon
> récurrente n'est jamais la preuve qu'une mutation marche — c'est la raison de l'essayer.

Même frontière que dans la chaîne de fabrication : la red-team lève des drapeaux, elle ne juge pas
le code.

### 2.1 Le journal d'erreurs est un objet de première classe *(ratifié Pierre, 2026-07-29)*

Pas un log technique : la **mémoire d'apprentissage**. Il conserve le cycle entier, pas le symptôme.

```yaml
failure_event:
  erreur_observee: ...
  etape_de_detection: ...        # JAMAIS la cause (§4.0)
  causes_suspectees: [ ... ]     # plusieurs, non tranchées d'emblée
  niveaux_de_mutation_proposes: [ ... ]
  experience_associee: ...       # identité de branche (§4.2 R2)
  verdict_oracle: ...
  lesson: { texte: ..., statut: validee | rejetee }
```

> La question n'est pas « quel bug est arrivé », mais **« comment la Forge a appris à mieux choisir
> son intervention »**.

#### Écart mesuré avec l'existant

Une entrée de journal vaut aujourd'hui `{error, etape, project, run_id, ts}` — **cinq champs, tous
du côté du symptôme**. Ils couvrent les deux premières lignes de la structure ci-dessus ; les cinq
autres n'existent pas. Ce n'est donc pas une extension du journal, c'est **un autre objet**, dont
l'actuel devient l'en-tête.

Plus révélateur : une **leçon de méthode** est enregistrée aujourd'hui comme une erreur ordinaire —
son texte vit dans le champ nommé `error`, avec `project: "_global_"` et `run_id: "_method_"`. La
mémoire d'apprentissage a littéralement la forme d'une mémoire de symptômes.

Et il en découle un défaut vérifiable : **ces leçons n'ont ni statut, ni réfutation, ni péremption.**
Une leçon écrite une fois est relue au pré-mortem de tous les projets, indéfiniment. Rien ne permet
de dire « on a cru cela, l'expérience l'a démenti ». Le champ `statut` de la structure ci-dessus est
donc l'ajout le plus important de la liste, et le moins coûteux.

#### Conséquence structurelle : le premier objet Forge qui vit plus longtemps qu'un run

Un `failure_event` s'écrit dans le temps — erreur détectée, puis hypothèses, puis expérience, puis
verdict, puis leçon. Ces moments peuvent être séparés par plusieurs runs. Or **tout le reste de la
Forge est immuable et borné à un run** : reçus, verdicts, manifestes, lignes d'audit.

Deux formes possibles, et une seule tient :

| Forme | Effet |
|---|---|
| enregistrement **mutable**, mis à jour au fil du cycle | écrase les hypothèses abandonnées |
| **événements append-only** clés par `failure_id`, repliés à la lecture | conserve tout, y compris ce qu'on a cru à tort |

> **La seconde, et pour une raison de fond** : la trace d'une attribution *révisée* est exactement
> la donnée qui apprend à mieux attribuer. Écraser `cause: exécution` par `cause: connaissance`
> détruit la leçon au moment où elle se forme. C'est aussi la forme que prennent déjà tous les
> journaux du dépôt — rien de neuf à inventer, seulement une clé de regroupement.

**Une mauvaise hypothèse reste visible.** La branche perdante et la cause réfutée ne sont pas des
déchets : ce sont les données qui apprennent à diagnostiquer. Une Forge qui efface ses erreurs
d'attribution ne peut pas apprendre à mieux attribuer.

### 2.2 La leçon est un autre objet, avec une autre temporalité *(ratifié Pierre, 2026-07-29)*

> **Une erreur appartient à un run. Une leçon appartient à l'histoire de la Forge.** Elles n'ont
> donc pas le même cycle de vie, et ne peuvent pas partager le même contenant.

**Mesure de l'écart** : aujourd'hui une leçon vit dans le journal d'erreurs, distinguée uniquement
par une valeur magique dans un champ (`project: "_global_"`, `run_id: "_method_"`). Le contenant
run-scopé sert de mémoire historique par convention de nommage. C'est la confusion de temporalité,
rendue visible dans le stockage.

```yaml
lesson:
  lesson_id: ...
  statement: ...
  status: candidate | validated | weakened | rejected | deprecated
  evidence_count: ...
  supporting_runs: [ ... ]
  counter_examples: [ ... ]
  generation: ...          # la génération de génome où elle a été apprise
```

#### Les transitions se font par preuve, jamais par avis

| Transition | Déclencheur |
|---|---|
| `candidate → validated` | N runs à l'appui, zéro contre-exemple (N est une décision, pas un réglage) |
| `validated → weakened` | **le premier** contre-exemple |
| `weakened → rejected` | les contre-exemples l'emportent |
| n'importe lequel `→ deprecated` | le contexte auquel elle s'appliquait n'existe plus |

Chaque transition cite le `failure_id` ou l'expérience qui la provoque. Une leçon ne monte ni ne
descend sur une impression.

#### `deprecated` ≠ `rejected` — et les générations en sont la première cause

Une leçon *rejetée* était **fausse**. Une leçon *dépréciée* était **vraie, dans un monde qui
n'existe plus**. La distinction n'est pas cosmétique : le principal producteur de dépréciation est
le **changement de génération** (§5).

> **Problème imminent, à ne pas découvrir après coup** : toutes les leçons accumulées sur la chaîne
> Opus sont aujourd'hui relues au pré-mortem de tout projet, sans marqueur de génération. Quand V2
> arrivera, elle héritera de leçons portant sur des défauts qu'elle aura précisément supprimés.
> D'où le champ `generation` : un changement de génération doit **signaler les leçons à réexaminer**,
> pas les emporter en silence ni les conserver aveuglément.

#### Le biais qui gonflera les `validated`, et où le corriger

`evidence_count` croît avec l'**attention**, pas avec la vérité : on enregistre un run à l'appui
parce qu'on cherchait un appui ; personne ne va vérifier spontanément qu'un run récent contredit
une leçon ancienne. Sans correctif, toute leçon dérive vers `validated`.

Le correctif est gratuit, et il est situé : **la moisson des contre-exemples se fait au point
d'usage.** Une leçon injectée au pré-mortem d'un run doit être confrontée au résultat de ce run —
c'est le seul moment où quelqu'un la regarde et où la donnée est là. Un audit séparé, lui, ne se
fera jamais.

#### Le troisième cran du même garde-fou

| Niveau | Ce qui est interdit |
|---|---|
| run | un agent ne prononce pas son propre verdict |
| expérience | une mutation ne déclare pas son gain (§6.1) |
| **histoire** | **une leçon ne se déclare pas vraie** |

La Forge peut proposer une règle. Elle ne peut jamais s'auto-décerner sa vérité. C'est la même
frontière, remontée d'un cran à chaque fois que l'horizon s'allonge.

> **Ce que §2.1 et §2.2 changent vraiment** : la Forge commence à mémoriser ses **erreurs de
> raisonnement**, pas seulement ses erreurs d'exécution. Une leçon n'est pas un fait — c'est une
> **hypothèse historique avec une durée de vie**.

### 2.3 Périmètre minimal en V2 — le mécanisme, pas le moteur *(ratifié Pierre, 2026-07-29)*

| Dans V2 (minimum) | Après les premiers génomes industriels |
|---|---|
| `failure_id` stable | scoring |
| événements append-only | probabilités |
| lien vers l'expérience | sélection automatique |
| statut de leçon | MCTS complet |
| génération | — |
| preuves associées | — |

> Le risque évité est nommé : reconstruire une usine avant d'avoir validé la boucle
> d'apprentissage.

**Une précision de câblage, sans quoi cinq des six items sont passifs.** Ces six éléments sont
tous du côté de l'**écriture** — sauf un. Le `statut` n'a de sens que si quelqu'un le lit :

> **Le seul changement de lecture exigé par le minimum : le pré-mortem filtre sur le statut et
> affiche la génération.** Sans lui, une leçon `rejected` continuerait d'être injectée dans chaque
> run, et le marqueur de génération serait écrit sans jamais être vu. La mémoire resterait un
> historique décoratif au lieu d'une couche active.

#### Politique d'injection au pré-mortem — RATIFIÉE (Pierre, 2026-07-29)

| Cas | Traitement |
|---|---|
| même génération | injection normale |
| génération différente | **injection visible, marquée à réexaminer** |
| leçon `rejected` | **jamais injectée comme contrainte** |
| leçon `deprecated` | conservée comme **historique**, pas comme règle active |

> L'objectif n'est pas de nettoyer le passé, c'est de **ne pas laisser le passé piloter aveuglément
> le présent**.

**Un `failure_event` de V2 sera structurellement incomplet, et c'est normal.** À ce stade il n'y a
pas encore d'expérience : `experience_associee`, `verdict_oracle` et `lesson` n'ont pas de
producteur avant V3. Ils doivent donc être **déclarés vides**, jamais absents — la règle des trois
états s'applique ici comme au contrat d'agent. Sinon un lecteur futur ne pourra pas distinguer
« pas encore d'expérience » de « champ qui n'a jamais existé ».

#### Les trois états, version « données historiques » — RATIFIÉE

| État | Sens |
|---|---|
| valeur présente | l'information existe |
| **explicitement vide** | non applicable, ou **pas encore produit** |
| absent | **uniquement** si l'enregistrement précède réellement le champ |

Le troisième cas est le piège : il n'est légitime que s'il est **vérifiable**, sinon « absent »
redevient l'oubli qu'on avait interdit. Le mécanisme existe déjà dans le dépôt — les manifestes
portent `"schema": "forge.context_manifest.v1"`. La règle se complète donc d'elle-même :

> **`absent` n'est acceptable qu'en dessous d'une version de schéma déclarée.** Au-dessus, c'est un
> oubli. Ce qui rend la distinction mécanique au lieu de l'abandonner au jugement du lecteur.

#### Limite du pré-mortem en V2 — RATIFIÉE

Trois gestes, pas un de plus : **récupérer les leçons pertinentes · appliquer les filtres ·
afficher le contexte.** La décision reste humaine ou agentique.

**Le pré-mortem observe l'histoire ; il ne l'interprète pas** *(ratifié Pierre, 2026-07-29)* :
sélection par champs structurés · aucune génération de pertinence par LLM · aucune reformulation
qui pourrait changer le sens · aucune priorisation automatique.

> Y déroger reviendrait à **introduire un agent caché dans la boucle de mesure** — un juge que
> personne n'aurait nommé, présent dans chaque run.

Trois précisions qui rendent cette limite tenable plutôt que pieuse :

- **La pertinence est un filtre structurel, jamais sémantique.** Domaine, génération, statut — des
  comparaisons, pas des jugements. Le jour où « pertinent » voudrait dire « ce qui a l'air de
  s'appliquer », le pré-mortem serait devenu un moteur de raisonnement sans que personne ne l'ait
  décidé.
- **Le pré-mortem doit rester déterministe et non-LLM — et ce n'est pas seulement de l'hygiène.**
  Il est injecté dans **chaque** run. S'il raisonnait, il introduirait de la variance dans tous les
  runs, y compris ceux de calibration : la bande de bruit mesurée à l'étape 4 mesurerait alors en
  partie les hésitations du pré-mortem. Un sélecteur de leçons non déterministe rendrait la
  Forge **non mesurable** au moment précis où l'on cherche à la mesurer.

- **Le corpus de leçons fait partie du tronc, donc du gel.** Conséquence non évidente de « le
  pré-mortem appartient à l'environnement expérimental » : deux runs aux contrats identiques mais
  séparés par l'ajout d'une leçon ne reçoivent **pas le même pré-mortem**. Le corpus doit donc être
  gelé avec le reste pendant la calibration — sinon la bande de bruit mesure aussi la croissance du
  corpus.
  **Et c'est déjà détectable** : le manifeste d'exécution enregistre `premortem_sha256`. Contrôle
  de validité de la calibration, gratuit : *tous les runs de calibration doivent porter le même
  `premortem_sha256`.* S'ils divergent, la bande de bruit est contaminée et il faut la refaire.

> La frontière tient en une ligne : **V2 rend la Forge observable, versionnable et capable
> d'apprendre. Elle ne la rend pas capable de choisir ses propres mutations.** C'est ce qui évite
> de recréer une usine à gaz sous prétexte de construire l'anti-usine à gaz.

---

## 3. Observé ≠ déclaré

Chaque paramètre du génome d'exécution porte son niveau de provenance :

```yaml
<champ>:
  value: ...
  provenance: observed | declared
```

`observed` = mesuré sur l'exécution réelle. `declared` = lu dans une configuration dont rien ne
prouve qu'elle soit appliquée.

> **Règle** : *un axe de mutation doit être `observed`. Muter un champ `declared` ne produit pas
> une expérience, mais du bruit signé.*

Une mutation qui change l'empreinte déclarée sans rien changer à l'exécution est un générateur
parfait de faux positifs : l'expérience se déclare légitimement différente, la métrique bouge au
gré du bruit, et l'écart est imputé à l'hypothèse.

**Cas mesuré (2026-07-29)** : `reasoning` est déclaré par modèle dans `roles.yaml`, et aucun
lecteur n'existe dans `scripts/` ni `control_plane/` — les seules occurrences vivent dans la lane
gelée `studioV2`. Muter « la profondeur de raisonnement » avant de la rendre effective serait
exactement ce cas.

---

## 4. L'espace de mutation

> **Énoncé gravé** *(Pierre, 2026-07-29)* : **l'arbre de recherche n'est pas là pour essayer des
> variantes de workflow au hasard. Il sert à choisir OÙ muter, après classification d'une erreur.**
>
> Corollaire, et c'est le point le plus important de ce document avec le §0 : **le lieu de
> détection n'est pas la cause.** Une Forge qui l'oublie apprendra à corriger ses symptômes — et
> elle le fera avec méthode, ce qui la rendra plus difficile à détromper.

Deux axes distincts, à ne jamais confondre : **ce qu'on mute** (l'artefact) et **pourquoi on le
mute** (la cause racine). Le second commande le premier.

```
Agent          ├── prompt · skill · modèle
Knowledge      ├── WorldScan · KB
Architecture   ├── WireMap · Workflow
Validation     ├── Prisme · Oracle
```

### 4.0 Taxonomie des causes racines *(ratifiée Pierre, 2026-07-29)*

Une erreur détectée n'est pas forcément une erreur du dernier maillon.

| Cause | Énoncé | Niveau de mutation |
|---|---|---|
| **connaissance** | la Forge **ne savait pas** | WorldScan — collecte, sources, questions de recherche |
| **mémoire** | elle savait, mais n'a pas **conservé ou exploité** | KB — schéma, liens, agents qui la lisent, règles d'usage |
| **transmission** | l'information existait, elle n'est pas **passée** au bon agent au bon moment | contrats, `output_contract`, chaînes de transmission |
| **systémique** | le workflow **permet** cette classe d'erreur | WireMap / squelette — structure, dépendances, invariants |
| **conception** | le **choix de design** est en cause | Architect — règles de conception, Prisme, critères produit |
| **exécution** | le plan était bon, l'**implémentation** a échoué | Worker — modèle, skill, tests, agent codeur |

#### L'anti-pattern, et son précédent daté dans ce dépôt

`bug gameplay → changer le codeur`, alors que la cause vit en amont.

Ce n'est pas une hypothèse : le journal d'erreurs en porte un cas, `chesscolor`, étape
`s11-redteam-code` — *« le product_snapshot disait (col+rangée) pair → sombre, mais la vraie règle
d'échecs est impair → sombre. Le code est correct, la SPEC amont était fausse. »* Une erreur de
**connaissance**, détectée à l'étape d'**exécution**. Classée sur son lieu de détection, elle
aurait produit une mutation de l'agent codeur — sur du code correct.

> **L'anti-pattern n'est pas une paresse de raisonnement, c'est un gradient économique.** Muter le
> worker est rapide et bon marché ; muter le WorldScan ou les règles de conception est lent et
> cher. Le niveau le moins coûteux à changer est donc celui que tout le monde accuse.

Deux règles en découlent :

- **Le lieu de détection n'est jamais la cause.** Déduire `cause_level` du champ `etape` du journal
  automatiserait précisément l'anti-pattern. Le journal enregistre aujourd'hui `{error, etape,
  project, run_id, ts}` — l'étape de **détection** seule ; il lui manque un champ de cause, qui
  doit être posé, jamais inféré.
- **Deux mutations infructueuses au même niveau font remonter l'attribution d'un cran.** Sans cette
  règle, le gradient économique produit un bricolage indéfini au niveau le moins cher.

#### La classification est elle-même une hypothèse

Attribuer une cause racine est un **jugement**, pas une mesure. Il ne peut donc pas être traité
comme un fait — et il n'a pas besoin de l'être, parce que **l'expérience le falsifie** : si l'on
mute le niveau accusé et que la classe d'erreur ne recule pas, c'est l'attribution qui était
fausse.

Conséquence sur l'enregistrement : une expérience porte **deux** hypothèses distinctes —
l'attribution de cause et la mutation choisie. Sans cette séparation, un résultat nul sera toujours
imputé à la mutation, jamais au diagnostic, et la Forge n'apprendra jamais à mieux attribuer.

```yaml
experiment:
  cause_attribution: { level: ..., status: hypothesis | confirmed | refuted }
  mutation:          { hypothesis: ..., expected_metric: ... }
```

### 4.1 Versionnabilité réelle des niveaux de mutation

Une taxonomie n'est exploitable que si chaque niveau est **mutable et versionné séparément**.

| Niveau | Versionnable | Preuve |
|---|---|---|
| transmission — contrats | **oui** | `contract_sha256` + `sha256` par source |
| exécution — worker | **oui** (dès 0.5.d) | contrat + modèle réellement exécuté |
| mémoire — KB | partiel | `catalog_brick_ids_snapshot` enregistre les **identifiants** de briques par run, pas leur contenu |
| systémique — WireMap / workflow | partiel | empreintes par fichier · nom de profil + `git_head` global |
| conception — Prisme / Architect | **non** | aucune empreinte |
| connaissance — WorldScan | **non** | aucune empreinte |

**Deux sur six pleinement, deux partiels, deux absents.** Les deux absents sont précisément les
deux niveaux les plus en amont — c'est-à-dire ceux que l'anti-pattern conduit déjà à ne jamais
accuser. Tant que ce chiffre ne monte pas, une attribution en amont ne peut pas être testée : la
mutation correspondante ne serait ni traçable, ni comparable.

### 4.2 Causes multiples et branches concurrentes *(ratifié Pierre, 2026-07-29)*

Une erreur a **plusieurs causes candidates**. Trancher tôt fabriquerait exactement ce que la
taxonomie doit empêcher : une grille rigide qui se trompe elle-même avec assurance.

```
Erreur : boucle joueur faible
  A → WorldScan   manque d'analyse marché
  B → KB          pattern mal stocké
  C → Architect   mauvaise boucle gameplay
  D → Worker      implémentation incomplète
```

Les expériences tranchent. La classification devient **probabiliste**, et les probabilités se
mettent à jour :

```
Erreur → classification probabiliste des causes → branches de mutation ciblées
       → expériences contrôlées → mise à jour des probabilités → leçon → génome suivant
```

C'est la forme aboutie de l'idée d'arbre : les causes candidates sont les branches, une expérience
est une descente, la mise à jour des probabilités est la remontée, et la mémoire des branches déjà
testées est l'arbre lui-même. La règle artisanale du §4.0 — *deux mutations infructueuses au même
niveau font remonter l'attribution* — n'en est qu'une approximation à la main.

Quatre règles pour que la version probabiliste ne redevienne pas une usine à gaz :

**R1 — On compare chaque branche au tronc, jamais deux branches entre elles.**
Une branche a un seul delta vis-à-vis du tronc ; deux branches en ont deux l'une par rapport à
l'autre. Le classement se fait sur les écarts Δ(branche, tronc), jamais sur une mesure directe
A contre B.

**R2 — Une branche a une identité, sinon « déjà testé » est indétectable.**
`identité = (empreinte du tronc, cause attribuée, delta calculé)`. Sans cette clé, la mémoire des
branches dégénère en journal de prose, et la même hypothèse sera réessayée sans qu'on le sache.

**R3 — Une probabilité de cause est un compteur, pas une mesure.**
Avec un corpus de quelques expériences, toute probabilité est dominée par son a priori — et
paraît objective précisément parce qu'elle est chiffrée. Donc : conserver des **comptages**
(tentées / confirmées / réfutées) et ne dériver une probabilité qu'à la lecture, **toujours
affichée avec son n**. Un « 0,7 » sans « n = 3 » est une affirmation déguisée.

**R4 — L'éventail est borné, et il contient au moins un candidat amont.**
Le nombre de branches par erreur est une décision, jamais un comportement émergent : chaque
branche est un run complet. Et sans quota d'amont, la sélection par valeur attendue reproduira le
gradient économique du §4.0 avec des chiffres à la place de l'intuition — les probabilités ne
soignent pas le gradient, seule une sélection consciente du coût le fait.

> **La branche perdante est la donnée principale, pas un échec.** C'est elle qui met à jour la
> probabilité de cause. Ce point clôt la question ouverte §10.4 : ce qu'on fait d'une branche
> perdante, c'est l'enregistrer avec son identité R2 — sans quoi l'arbre ne mémorise que ses
> succès et ré-explore indéfiniment ce qui a déjà échoué.

Ce que ceci **n'autorise pas** : lancer des branches sans ratification. Le générateur d'hypothèses
propose l'éventail ; l'exécution reste une décision. La Forge peut proposer une hypothèse, elle ne
peut pas écrire sa propre preuve (§6.1) — ni décider seule de dépenser N runs pour la chercher.

### 4.3 La boucle complète

```
Erreur → classification de la cause racine → choix du niveau de mutation
       → hypothèse isolée → expérience → leçon → génome suivant
```

> C'est aussi le garde-fou anti-usine-à-gaz : *on n'ajoute pas une couche parce qu'une erreur
> apparaît, on identifie la couche responsable.* Une nouvelle couche ne se justifie que si aucun
> niveau existant ne porte la cause — et cette absence se démontre, elle ne se suppose pas.

### 4.4 Version 1 de la boucle — une carte de routage, pas un moteur

*(Ratifié Pierre, 2026-07-29 : rester simple.)*

| Dans la V1 | Hors V1 |
|---|---|
| journal d'erreurs **structuré** (avec un champ de cause, distinct de l'étape de détection) | moteur probabiliste |
| classification de cause racine, posée à la main | générateur d'hypothèses |
| mutations ciblées, une à la fois | branches concurrentes automatiques |
| leçons qui renforcent les bonnes décisions | mise à jour arithmétique des probabilités |

La taxonomie du §4.0 y sert de **carte de routage** : `connaissance → WorldScan · mémoire → KB ·
transmission → contrats/livrables · système → WireMap/workflow · conception → Architect/Prisme ·
exécution → Worker`.

**Ce que la V1 conserve du dessin probabiliste, et pourquoi ce n'est pas un travail à refaire :**

| Règle du §4.2 | Sort en V1 |
|---|---|
| R1 — comparer au tronc, jamais deux branches entre elles | **conservée telle quelle**, elle est gratuite |
| R2 — identité de branche `(tronc, cause, delta)` | **conservée, et essentielle** : c'est elle qui rend « déjà testé » détectable, avec ou sans probabilités |
| R3 — compteurs, pas probabilités | **satisfaite par construction** : la V1 ne calcule rien, elle compte |
| R4 — éventail borné, au moins un candidat amont | dégradée en règle de conduite : celui qui pose l'hypothèse doit **envisager** un candidat amont, et le dire |

> Autrement dit : **la V1 est la version probabiliste sans l'arithmétique.** Même modèle de
> données, aucune inférence par-dessus. Passer plus tard au probabiliste sera un ajout de lecture,
> pas une reprise du socle.

**La boucle doit se mesurer elle-même.** L'objectif annoncé est économique — *ne pas brûler des
runs en changeant le mauvais étage*. C'est donc mesurable, et avec deux compteurs seulement :

- **taux d'attribution correcte** : mutations dont la classe d'erreur visée a effectivement reculé ;
- **coût des mutations infructueuses** : runs dépensés sur des attributions réfutées ;
- **ratio modifier / ajouter** : mutations qui **modifient un niveau existant** contre mutations qui
  **créent un niveau nouveau**.

Le troisième répond à la question d'usine — *quand la Forge progresse, est-ce parce qu'elle apprend
ou parce qu'elle accumule des couches ?* C'est le `reuse_ratio` des briques de jeu, retourné vers
l'usine elle-même : là il mesure ce qu'on réemploie plutôt que de recréer, ici ce qu'on corrige
plutôt que d'empiler.

**Nuance de lecture, sans laquelle il condamnerait les fondations** *(Pierre, 2026-07-29)* : un
ratio d'ajout élevé est **normal en phase d'exploration**. Il ne devient un signal négatif que
lorsque le **même type de problème revient** et qu'on continue d'ajouter au lieu de modifier.

Il ne se lit donc jamais seul. Trois grandeurs le qualifient :

| Croisement | Ce qu'il distingue |
|---|---|
| fréquence de la même `failure_class` | première occurrence (ajouter est légitime) ou récurrence |
| nombre de leçons déjà liées à cette classe | on savait déjà, ou on découvre |
| nombre de mutations déjà tentées sur cette classe | on a déjà essayé de corriger, ou pas encore |

> **Règle de lecture** : le ratio d'ajout ne se lit qu'**à récurrence constante**. Ajouter à la
> première occurrence d'une classe d'erreur est une fondation. Ajouter à la troisième, après deux
> mutations déjà tentées, est une dérive. Sans ce croisement, une phase de fondation serait
> interprétée comme une dérive — et l'indicateur découragerait exactement le travail qu'il est
> censé protéger.

Sans ces deux chiffres, on aurait une boucle qui améliore la Forge sans savoir si la boucle
elle-même fonctionne — précisément le reproche que cette doctrine adresse au reste du système. Ils
sont soumis à la même discipline que toute métrique : prouver leur variance avant de servir à
décider quoi que ce soit.

### 4.2 Enregistrement de couverture

Chaque expérience inscrit la famille mutée dans un **enregistrement de couverture** de l'espace —
un artefact, pas un souvenir.

> **Aucune conclusion sur la Forge entière ne peut venir d'une seule famille explorée.** Un espace
> exploré à 1/4 qui le dit est une information ; un espace exploré à 1/4 qui se tait est une
> conclusion trop large en préparation.

---

## 5. Générations et lignée

```yaml
lineage:
  generation: <n>
  parent_run_id: ...
  comparable_to: <run_id> | aucun
```

Un changement de **sémantique d'exécution** ouvre une génération. Une génération n'est pas une
version : elle déplace la ligne de mesure.

> **La comparaison inter-génération est refusée par défaut ; la comparaison intra-génération est
> la norme.** Sans ce garde-fou, les chiffres de la génération précédente resteront disponibles,
> donc un jour comparés — de bonne foi, et à tort.

### 5.1 Deux empreintes, jamais une

```
graph_declared_hash  = profil + [(etape, contract_sha256)] ordonné + roles_sha256
graph_execution_hash = le précédent + modèles réellement exécutés + tentatives + dérogations
```

`roles_sha256` appartient à la **déclaration** : la résolution rôle → modèle vit dans un fichier
versionné, donc un échange de modèle voulu est une autre expérience, pas un autre déroulement.

Tout écart d'exécution porte une qualification :

```yaml
execution_difference:
  type: intended | incident
```

Sans ce champ, une mutation délibérée (Claude → Qwen) et une panne silencieuse (repli quand LM
Studio est absent) produisent la même trace — et la Forge apprendrait une causalité fausse.

### 5.2 Invariant de branche

```
Deux runs sont comparables SI ET SEULEMENT SI :
  même objectif · mêmes contraintes · même dossier de preuve de départ
  ET exactement un delta entre leurs graphes.
```

**Le delta est calculé, jamais déclaré.** Déclaré par un humain, rien ne garantit qu'une seconde
chose n'a pas bougé.

---

## 6. Règles de mutation

### 6.1 Forme

Réutiliser le cycle d'expérience éprouvé, sans nouveau système :

```
Hypothèse → Contrat modifié → Red-team → Expérience → Oracle → Conclusion limitée
```

Une mutation **déclare** son hypothèse et sa métrique attendue **avant** l'expérience :

```yaml
hypothesis: ...
expected_metric: ...
```

Elle n'écrit **jamais** son delta.

> **Principe** : *la Forge peut proposer une hypothèse ; elle ne peut pas écrire sa propre preuve.*

Même frontière que dans la chaîne, remontée d'un cran : au niveau du run, un agent ne prononce pas
son verdict ; au niveau de l'expérience, une mutation ne prononce pas son gain.

### 6.2 Rendre un axe possible ≠ choisir une valeur sur cet axe

| Geste | Nature | Où il va |
|---|---|---|
| instrumenter l'observation | neutre | socle, non mesuré (preuve de neutralité exigée) |
| rendre un paramètre effectif | **mutation** | une hypothèse, mesurée |
| choisir une valeur sur un axe déjà effectif | **mutation** | une hypothèse, mesurée, **une à la fois** |

Preuve de neutralité d'une instrumentation : rejouer le témoin et obtenir le **même verdict** et
la **même empreinte déclarée**, avec des champs en plus et rien d'autre. Le gabarit existe — la
mission de télémétrie d'échec est explicitement « advisory strict : seule l'observation
s'enrichit ».

### 6.3 Une variable, pas une famille

Une hypothèse porte sur **un** rôle, **un** skill, **un** paramètre. « Réduire Opus partout » n'est
pas une hypothèse : c'en est une par rôle. Cas mesuré : dans le profil `standard_godot`, le
producteur et la red-team de code résolvent tous deux vers Opus — les changer ensemble rendrait
l'écart inattribuable, y compris à leur interaction.

---

### 6.4 Calibrer avant de comparer

Entre « le socle est prêt » et « la première mutation », il manque un objet qui n'est ni de
l'instrumentation, ni une mutation : **les runs de calibration**.

Rejouer la même chaîne déclarée ne redonne pas les mêmes chiffres — un exécutant LLM n'est pas
déterministe. Sans savoir de combien une métrique bouge **quand rien ne change**, aucun écart
mesuré plus tard n'est interprétable.

| Objet | Ce qu'il établit |
|---|---|
| répétitions du même `graph_declared_hash` sur le témoin | la **bande de bruit** de chaque métrique retenue |
| sortie attendue | « sur N runs identiques, la métrique M varie de ±X » |

> **Règle d'adoption qui en découle** : *une mutation dont l'effet ne sort pas de la bande de bruit
> mesurée n'a rien démontré.* Elle n'est ni adoptée, ni rejetée : elle est `UNKNOWN`, et le coût de
> la conclusion est de refaire l'expérience, pas de trancher.

C'est le jumeau de la règle de variance déjà ratifiée : la variance prouve qu'une métrique **mesure
quelque chose** ; la dispersion dit **à partir de quelle amplitude** ce quelque chose est lisible.
Une métrique sans bande de bruit connue peut valider n'importe quelle mutation.

---

## 7. Adoption et rejet

| Portée de conclusion | Condition |
|---|---|
| **succès local** | la mutation améliore sa métrique sur son terrain d'origine |
| **amélioration de la Forge** | la même mutation tient sur un **second terrain**, jamais avant |

```yaml
conclusion:
  scope: local | generalized
```

`generalized` est **inassertable** tant qu'un seul génome a été testé. C'est `NO_CLAIM_ALLOWED`
transposé du run à l'expérience : on ne s'auto-décerne pas une généralisation.

### 7.1 Les quatre critères de sélection

réduction des erreurs · coût supplémentaire · complexité ajoutée · stabilité sur d'autres projets.

Le quatrième exige n ≥ 3 génomes. Il y en a deux, et Pong est gelé : le corpus réellement mutable
est **n = 1**. Ce critère reste indisponible jusqu'à un troisième génome — ce qui distingue
« cette mutation a marché sur Snake » de « cette mutation marche ».

### 7.2 Ne pas chercher la généralisation trop tôt

L'ordre n'est pas négociable : **savoir mesurer un changement sur un tronc stable, puis seulement
multiplier les génomes.** Multiplier les génomes d'abord produit un corpus **non interprétable** —
on aurait des chiffres venus de plusieurs terrains sans savoir, sur aucun d'eux, quelle amplitude
est significative.

> Une Forge qui cherche à optimiser avant de savoir mesurer n'apprend pas : elle collectionne des
> impressions chiffrées.

---

## 8. Les deux niveaux d'évolution

**Niveau 1 — dirigée** : `observation → hypothèse humaine → mutation → expérience → comparaison`.
**Niveau 2 — assistée** : `erreur classifiée → générateur d'hypothèses → branches → oracle → sélection`.

| Fondation | Niveau 1 | Niveau 2 |
|---|---|---|
| provenance rebranchée sur son run | **indispensable** | indispensable |
| coût réel + modèle réellement exécuté | **indispensable** | indispensable |
| empreintes déclarée + exécutée (avec `roles_sha256`) | **indispensable** | indispensable |
| lignée de run (parent + delta calculé) | utile | **indispensable** |
| reçu déclarant couvert / non couvert | non requis | **indispensable** |
| étape d'apparition d'une erreur | non requis | **indispensable** |
| versionnement du prisme et du worldscan | requis si on les mute | **indispensable** |

> **Règle d'arbitrage** : en cas de doute sur l'appartenance d'une fondation, elle va au Niveau 2.
> Le Niveau 1 n'accepte que ce sans quoi une comparaison serait **impossible**, jamais ce qui la
> rendrait **meilleure**.

### 8.1 Le contrefactuel — « une détection aurait été possible »

C'est la question qui fonde le Niveau 2 : *à quel endroit de la chaîne l'erreur aurait-elle pu
être détectée moins cher ?* Elle ne s'observe pas au moment du run ; elle se **reconstruit** quand
un défaut est attribué à une étape amont.

Elle n'a de réponse que si **chaque reçu déclare son périmètre couvert ET non couvert**.

Précédent mesuré : un reçu `{"couvertes": [], "passed": true}` a rendu un défaut visible ; réduit
à `passed: true`, il l'aurait rendu indémontrable pour toujours. Corollaire général : *quand un
oracle ignore une valeur au lieu de la refuser, il fabrique du vert.*

### 8.2 Trois natures d'erreur, une seule attribuable

| Nature | Trace | Attribuable automatiquement |
|---|---|---|
| détectée par un oracle | reçu signé | **oui** |
| détectée puis saisie au journal | ligne déclarative | non |
| **ignorée** | aucune | non — contrefactuel dérivé |

---

## 9. Simplifier — le triage, et son piège

L'arbre de triage du studio place **supprimer** juste après **ne rien faire**, et bien avant
*améliorer* et *créer*. L'instrumentation fournit le critère qui manquait : ce qui reste noir après
instrumentation est ce qui n'a aucun effet observable.

| Classe | Signature | Décision |
|---|---|---|
| **A — producteur** | produit une donnée observée | garder, instrumenter |
| **B — garde préventive** | produit du **silence quand tout va bien** | garder **si** une sonde à défaut injecté prouve qu'elle refuse ; sinon, théâtre → supprimer |
| **C — déclaratif pur** | ni donnée, ni refus | candidat à la suppression |

> **Le piège** : une garde qui n'a jamais rien bloqué ressemble exactement à du code mort. C'est
> pourtant la raison pour laquelle rien n'a mal tourné. La méthode de falsification existe déjà :
> les **sondes à défauts injectés**. Une garde qui ne refuse pas un défaut injecté n'est pas une
> garde.

Second garde-fou : rien ne se supprime sans recherche de consommateurs. Le mode de panne inverse —
un lecteur qu'on n'avait pas vu — est documenté plusieurs fois dans ce studio.

Et une distinction à ne jamais confondre : **archiver un historique ≠ supprimer du mort**.

---

## 10. Questions ouvertes de doctrine

1. **Conserve-t-on le texte des prompts**, ou seulement leur empreinte ? Sans le texte, deux
   branches sont comparables mais muettes sur le *pourquoi*.
2. **Où tournent les branches ?** Pong est gelé, Snake est seul mutable. Sur Snake re-forgé, sur
   une copie, ou sur un troisième génome créé pour ça ?
3. **Quel troisième génome, et quand ?** Sans lui, `scope: generalized` reste inassertable.
4. ~~Que fait-on d'une branche perdante ?~~ **TRANCHÉ (§4.2)** : on l'enregistre avec son identité
   `(empreinte du tronc, cause attribuée, delta)` — c'est elle qui met à jour la probabilité de
   cause. Reste ouvert en revanche : **quelle largeur d'éventail** par erreur, et **quel quota
   d'exploration amont** imposer contre le gradient économique.
5. **Où passe la frontière du graphe ?** Le delta « une seule hypothèse » est vérifiable pour ce
   que le graphe couvre ; pas pour ce qui vit à côté (contenu d'un fichier de connaissances).
6. **Qui possède la lignée ?** Aujourd'hui personne : deux runs d'un même projet ne se connaissent
   pas.

---

## Rapport de charter

- **software_verdict: OK** — doctrine extraite et consolidée. Aucune modification de la V1, aucun
  code, aucune migration. Fichier créé, PROPOSED, non commité.
- **evidence_verdict: MECHANICAL_VALIDATION_ONLY** — les constats datés (gel non mécanique,
  `reasoning` sans lecteur, 1 sur 5, corpus n = 1, double résolution Opus) proviennent de
  vérifications exécutées le 2026-07-29, détaillées dans le charter Phase 0.5 §1.
- **claim_verdict: NO_CLAIM_ALLOWED** — aucune affirmation que cette doctrine produise une Forge
  qui apprend. Elle énonce des conditions nécessaires.

**SKIPPED_VALIDATION**

- *§1.2 (couverture des surfaces d'écriture)* — analyse, non mesurée : aucun test n'a vérifié
  qu'un sous-processus échappe effectivement aux gardes existantes.
- *§3 (`reasoning` sans lecteur)* — absence vérifiée sur `scripts/` et `control_plane/`, lane
  `studioV2` exclue. Lire « aucun lecteur mécanique trouvé », pas « le champ n'a aucun effet ».
- *§4.1 (« 1 sur 5 »)* — établi par lecture ; aucune tentative de produire une empreinte de prisme
  ou de worldscan pour vérifier qu'aucune n'existe ailleurs sous un autre nom.
- *§9 (classe B)* — méthode proposée, jamais appliquée : aucune garde n'a été soumise à une sonde
  à défaut injecté dans ces sessions.
- *Toutes les règles de ce document* — statut : **doctrine PROPOSED**. Aucune n'est implémentée,
  aucune n'est vérifiée par un mécanisme. Elles décrivent ce qui devrait tenir, pas ce qui tient.

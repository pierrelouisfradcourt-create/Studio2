# Forge V0 — Godot comme premier backend certifié (Étape 0)

- **Date** : 2026-07-21
- **Statut** : PROPOSED — ratification HumanGate (Pierre) requise
- **Lane** : FORGE
- **Source** : session de brainstorming Pierre ↔ Claude, 2026-07-21 (arbre curriculum initial Gemini + protocole de connaissance ChatGPT, tous deux amendés après audit du repo)
- **claim_verdict** : NO_CLAIM_ALLOWED

---

## 1. Problème

Le studio veut un curriculum de 10 jeux où chaque jeu est une session d'entraînement
supervisée par une référence externe, et où chaque mécanique acquise enrichit une
bibliothèque propriétaire. L'objectif réel n'est pas de produire 10 jeux : c'est de
construire **une Forge capable d'apprendre**, et de le **mesurer**.

Trois questions ouvertes bloquaient le démarrage :

1. Quel runtime pour les briques ? (l'arbre initial est en GDScript, toute la chaîne de
   preuve de la Forge est en JS/Python)
2. Qu'est-ce qui fait qu'une mécanique est « acquise » plutôt que seulement écrite ?
3. Comment absorber du capital open source sans copier-coller ni contamination de licence ?

## 2. Constat d'audit (ce qui existe déjà)

Audit exécuté sur le repo avant toute décision. Résultats vérifiés, pas supposés :

| Composant | État réel |
|---|---|
| `knowledge_base/catalog.json` | 3 `entry_type` : `asset` (19), `brick` (9), `role` (2). Le `brick` porte déjà `source`, `provenance_url`, `license`, `dependencies`, `parameters`, `genre_compatible`, `invariants`, `proof_of_use`, `tests`, `tier`, `affordances`. |
| `runtime: "godot"` | **Déjà une valeur admise** de `BRICK_SPEC` et `ASSET_SPEC` (`kb-validate.mjs` l. 187, 199). |
| `static_oracles.py` | `.gd` **déjà** dans `SOURCE_EXTS` ; regex GDScript déterministes présentes. Archi + WireMap fonctionnent sur Godot sans modification. |
| `mutation.py` | Moteur de mutation **texte brut**, langage-agnostique. N'a besoin que d'une commande de test à exécuter. |
| `verify_run.py` / `verdict.py` | HMAC + sha256 + git_head, agnostiques par construction. |
| `games/chess_tcg/` | Harnais Godot headless **existant et vert (83/83)** : `core/` GDScript pur sans dépendance de scène, `tests/run_tests.gd` en `--headless --script`, exit 0/1, **garde anti-faux-vert** (`EXPECTED_ASSERTS`). |
| Binaire | `Godot_v4.6.3-stable_win64_console.exe` présent sur le poste. |
| Gate mutation | **« 100 % ou survivant justifié »** via `mutation_triage.json` (pas un seuil en pourcentage). |

**Conséquence** : le chantier d'infrastructure Godot que l'on redoutait n'existe pas.
Godot est déjà un citoyen partiel de la chaîne de preuve.

## 3. Décisions ratifiées (Pierre, 2026-07-21)

- **D1** — Godot devient le **premier backend d'exécution certifié** de la Forge.
- **D2** — Le contrat `role` reste **la frontière stable**. Ce qui est certifié est une
  **capacité mesurée**, jamais un fichier ni un moteur.
- **D3** — **Aucun portage Unity/Unreal maintenant**, aucune double implémentation.
- **D4** — Les contrats restent **ouverts aux futurs runtimes sans les implémenter**.
- **D5** — M01 est une **preuve de chaîne complète**, pas un objectif de production de jeu.
- **D6** — Gate de certification = **preuve mécanique + preuve d'usage**. La joute
  d'origine est un **capteur advisory**, jamais bloquant.

## 4. Concept central : substituabilité certifiée

Le terme « portabilité » est explicitement **rejeté** : il suggère une opération de
migration future, donc une dette. Le concept retenu est la **substituabilité certifiée**.

Définition opérationnelle :

> Un rôle déclare une capacité (`requires`) et une **bande de difficulté mesurable**
> (`difficulty_target`) sur une distribution de seeds fixée (`simulation_config`).
> Une implémentation est **substituable** à une autre si, soumise à la **même
> `simulation_config` avec les mêmes seeds**, sa bande mesurée retombe dans la bande
> déclarée. La substituabilité est alors **prouvée par mesure**, jamais affirmée.

Ce que ça garantit concrètement :

- `role.yaml` ne contient **aucune mention de moteur** (vérifié sur
  `knowledge_base/roles/pursuer-mobile.yaml` : `requires`, `difficulty_target`,
  `simulation_config` sont du vocabulaire de domaine pur).
- `fulfilled_by` est **déjà une liste** dans le schéma. Ajouter un backend = ajouter une
  entrée et relancer la même mesure. Aucune refonte de la Forge.
- La décision de substituer devient une **décision de preuve** (la bande tient / ne tient
  pas), pas une décision d'architecture.

**Portée honnête de cette garantie** : la substituabilité certifiée prouve l'équivalence
*comportementale sur la bande mesurée*. Elle ne prouve rien sur le rendu, le feel, ni les
performances. C'est une propriété de la logique, pas du jeu.

## 5. Ouverture aux futurs runtimes — fail-closed

D4 crée un risque direct : déclarer un point d'extension non implémenté, c'est le mode de
panne documenté du studio (*déclaré ≠ exécuté*). La règle est donc :

- Le contrat de rôle accepte un champ `simulation_runtime` (valeurs nommées : `node`,
  `godot`, réservées : `unity`, `unreal`).
- **Seuls `node` et `godot` sont implémentés.** Toute autre valeur produit
  `INVALID_CONTRACT` avec un message explicite : *« runtime reconnu par le schéma, non
  implémenté par l'exécuteur »*.
- Aucun code mort, aucun stub. L'ouverture vit dans le **schéma et la documentation**,
  jamais dans une branche d'exécution vide.

## 6. Cycle de certification d'une brique

```
référence externe ─┐
                   ├─→ rôle (contrat, sans moteur)
intention design ──┘         ↓
                       brique .gd (runtime: godot)
                             ↓
                    run_tests.gd headless (exit 0)
                             ↓
        gate mutation « 100% ou survivant justifié »
                  + role_sim : bande dans la bande
                             ↓
                consommée par un artefact jouable
                   dont la solvabilité est prouvée
                             ↓
                  proof_of_use rempli → tier: validated
                             ↓
                  verdict signé HMAC → HumanGate (Pierre)
```

**Gate = mécanique + usage.** La preuve mécanique seule est refusée : le studio a déjà
constaté deux fois qu'un oracle vert ne prouve pas un jeu bon, et que des briques
certifiées peuvent n'être jamais appliquées en jeu réel.

**La joute d'origine reste advisory.** Motif : si elle devient bloquante, elle devient un
goulot d'étranglement que l'on contournera, et elle contredit la règle
« advisory jamais juge du code ».

## 7. Périmètre de l'étape 0

**Une seule mécanique : M01 — navigation en grille.**

Choix motivé par le levier, pas par la difficulté : étape 01 du curriculum ; corpus open
source sérieux disponible (A*, pathfinding sur grille) ; et `games/chess_tcg/core/moves.gd`
fait déjà du déplacement en grille dans le repo, ce qui fournit un point de comparaison
interne gratuit pour le capteur de joute.

**M01 est une preuve de chaîne, pas un jeu** (D5). Le critère de succès est
*« la chaîne brick → implémentation → simulation headless → oracle → verdict →
certification a tourné de bout en bout et produit un reçu vérifiable »*. Un Pac-Maze
jouable et beau n'est **pas** un critère de succès de l'étape 0.

### Livrables

| Id | Livrable | Nature |
|---|---|---|
| A1 | `godot_trial.mjs` — adaptateur spawn `Godot --headless`, retourne `{succeeded, ticks}` par seed | Neuf, mince. `role_sim.mjs` **non modifié**. |
| A2 | Amendement `kb-validate.mjs` | Modification ciblée (détail §8) |
| A3 | `solvability_godot.mjs` — bot déterministe headless, condition de victoire vérifiée | **Seul vrai code neuf** |
| A4 | Entrée `oracles.json` + variante Godot de `s9-build.yaml` | Configuration |
| B1 | `role-grid-navigator.yaml` + brique `sys-grid-nav-godot` certifiée | Le sujet du test |
| C1 | Protocole de capital externe (détail §9) | Doctrine + arborescence |
| E1 | Journal de métrique d'apprentissage (détail §10) | Instrumentation |

### Hors périmètre — explicite

Portage Unity/Unreal · double implémentation · jeux 02→10 · nouveau format
`mechanics_learned.yaml` (on **étend** `brick`, on ne crée pas de 4ᵉ couche) · refonte de
`role_sim.mjs` · production d'un jeu Pac-Maze fini.

## 8. Amendements techniques requis

### A1 — `role_sim.mjs` : couplage JS à l'exécution

**Constat vérifié** (l. 199-212) : le contrat est générique, mais l'exécution fait
`await import(moduleUrl)` et exige un export `runTrial(seed, cfg)`. C'est un `import()`
ESM natif — il ne peut charger qu'un module `.mjs`. Une brique Godot ne peut pas fournir
ce `runTrial`.

**Correctif retenu** : un adaptateur `.mjs` qui expose `runTrial(seed, cfg)` et fait un
`subprocess` vers `Godot --headless`, parsant le résultat sur stdout. `role_sim.mjs` reste
**inchangé** — il continue de ne connaître aucune mécanique ni aucun moteur. Le couplage
Godot vit dans un module de scénario, exactement là où le schéma le prévoit déjà.

Contraintes de l'adaptateur : déterminisme (même seed → même sortie), timeout explicite,
exit code vérifié, stdout **et** stderr capturés, chemin du binaire Godot résolu par
configuration repo-relative (jamais un chemin absolu utilisateur en dur).

### A2 — `kb-validate.mjs` : deux angles morts

**(a) R6 bloque le cas d'usage.** L. 372 : `runtime === "godot"` force `path` **et**
`tests` à `null` (règle « manifest-only » héritée des assets 3D). En l'état, une brique
Godot **ne peut pas** avoir de sha256 ni de fichier de tests référencé — c'est-à-dire ne
peut pas être certifiée.

Amendement : distinguer deux cas aujourd'hui confondus.
- *asset 3D / modèle non ingéré* → manifest-only, règle **inchangée**.
- *code GDScript testable* → `path` + `tests` + `sha256` **autorisés et exigés**, aligné
  sur le traitement des `system` non-godot (l. 377).

**(b) R10 est aveugle au GDScript.** Les motifs d'impureté (l. 74-92) sont du JS pur
(`Math.random`, `process.env`, `fetch`, `window`, `require('fs')`). Une brique GDScript
non déterministe passerait la garde de pureté **sans être vue**.

Amendement : liste de motifs GDScript — `randi`, `randf`, `randomize`, `randi_range`,
`OS.get_*`, `Time.get_*`, `FileAccess`, `DirAccess`, `HTTPRequest`, `Engine.get_frames_*`.
Même structure à deux passes (brut / dé-commenté) que l'existant.

**Note de rigueur** : ces deux amendements touchent un fichier durci par red-team
(v2, 2026-07-12). Toute modification doit passer la suite `kb-validate.test.mjs`
existante **sans assouplir une règle existante** — on ouvre un cas légitime, on ne
desserre pas une garde.

### A3 — solvabilité Godot

Seul composant sans cousin dans le repo. Décline R9 (« un bot gagne ») pour un projet
Godot : charge la logique pure en `--headless`, fait jouer un bot déterministe seedé,
vérifie la condition de victoire. Doit produire un reçu de la même forme que les autres
oracles pour entrer dans le verdict signé.

## 9. Protocole de capital externe

Règle non négociable :

```
source externe → analyse → connaissance propriétaire → réimplémentation Forge
```

et **jamais** :

```
dépôt trouvé → copier-coller → KB
```

Arborescence :

```
external_sources/
├── studied/            source_reference.yaml + analysis.md   (aucun code importé)
├── imported_code/      license.txt + attribution.md          (code réellement copié — exceptionnel)
└── extracted_knowledge/                                      (→ alimente brick/role)
```

**Ce que les gardes existantes couvrent déjà** (vérifié dans `kb-validate.mjs`) :
licences en liste fermée SPDX (R2) ; GPL **interdite sur du code** car elle contaminerait
un jeu distribué (R4) ; détection d'un marqueur GPL/LGPL/AGPL **dans le contenu** d'un
module déclaré permissif (R4-contenu) ; `provenance_url` obligatoire pour un pattern (R3) ;
patterns `advisory_only` — cités, **jamais injectés comme code** (R5/R11) ; code sans
provenance rejeté sauf marqueur exact `ORIGINAL — aucune inspiration externe citee` (R3).

**Ce qui reste à ajouter** : le champ `learned_from: {game, reference}` sur `brick`, pour
enregistrer *de quel jeu du curriculum et de quelle référence commerciale* la mécanique
est issue. C'est l'unique extension de schéma de l'étape 0.

## 10. Métrique d'apprentissage

Exigence de Pierre : prouver que la Forge apprend, pas le raconter. Trois nombres
enregistrés **à chaque brique certifiée** :

| Métrique | Source | Lecture |
|---|---|---|
| **taux de réutilisation** | `reuse_ratio.mjs` (existe déjà) | combien de briques KB consommées au lieu de réinventer |
| **itérations jusqu'au vert** | compteur d'escalade du driver | combien de passes oracle avant certification |
| **delta de joute** | capteur advisory, quand une référence existe | implémentation Forge vs implémentation dérivée, même contrat, mêmes seeds |

Sur 3 mécaniques : une tendance. Sur 10 : une courbe. **C'est la courbe qui est le
livrable du curriculum**, pas le nombre de briques.

**Limite honnête** : sur une seule mécanique (étape 0), ces trois nombres n'ont **aucune
valeur statistique**. Ils établissent la ligne de base et prouvent que l'instrumentation
enregistre réellement. Aucune conclusion sur l'apprentissage ne peut être tirée à
l'étape 0 — et aucune ne sera écrite.

## 11. Risques identifiés

| Risque | Mitigation |
|---|---|
| L'adaptateur Godot est lent (spawn par seed × 300 essais) | Mesurer avant d'optimiser ; si nécessaire, un seul spawn exécutant N seeds en batch |
| Assouplir R6 ouvre une faille de validation | Aucune règle existante desserrée ; suite `kb-validate.test.mjs` verte exigée ; red-team du diff avant ratification |
| M01 dérive vers « faire un Pac-Man » | D5 est un critère de refus explicite : le succès est le reçu de chaîne, pas le jeu |
| La joute advisory est ignorée puis oubliée | Elle alimente la métrique §10 ; une brique sans joute est certifiable mais marquée sans point de comparaison |
| Godot devient un lock-in de fait malgré D2 | §4 : la substituabilité est mesurée par `role_sim` ; si un rôle ne peut pas être exprimé sans le moteur, c'est un signal de conception, à remonter en HumanGate |

## 12. Critères de succès de l'étape 0

L'étape 0 est réussie si, et seulement si :

1. `role-grid-navigator.yaml` valide sans mention de moteur.
2. `sys-grid-nav-godot` passe `run_tests.gd` headless (exit 0, garde anti-faux-vert active).
3. Gate mutation : 100 % de mutants tués, ou survivants justifiés dans `mutation_triage.json`.
4. `role_sim` via l'adaptateur Godot mesure une bande **dans** la bande déclarée.
5. Solvabilité prouvée sur l'artefact consommateur (un bot gagne).
6. `proof_of_use` rempli, `tier: validated`, `kb-validate` PASS.
7. Verdict signé HMAC, re-vérifié mécaniquement par `verify_run.py` (exit 0).
8. Les trois métriques §10 sont enregistrées.

Tout critère rouge = étape 0 non franchie. Pas de succès partiel déclaré.

---

## Verdicts

```
software_verdict: BLOCKED   (spec de conception — aucun code exécuté à ce stade)
evidence_verdict: MECHANICAL_VALIDATION_ONLY
claim_verdict: NO_CLAIM_ALLOWED
```

**Note d'évidence** : les constats du §2 proviennent de lectures de fichiers et de `grep`
exécutés le 2026-07-21 (chemins et numéros de ligne cités). Ils n'ont **pas** été
re-vérifiés par exécution des oracles concernés. Aucune affirmation de fonctionnement
n'est faite dans ce document.

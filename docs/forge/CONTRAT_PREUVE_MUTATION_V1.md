# CONTRAT DE PREUVE DE MUTATION — V1 (FIGÉ)

**Statut : V1 FIGÉ — ratifié par Pierre le 2026-07-28.** Aucune implémentation à ce stade.
Ce document est **canonique** : il consolide et remplace, pour toute décision,
`CONTRAT_PREUVE_MUTATION_V1_PROPOSED.md` et `CONTRAT_PREUVE_MUTATION_V1_COMPLEMENT.md`
(conservés comme traces d'élaboration, non comme références).

**Changement de niveau ratifié** (verbatim Pierre) : « on ne corrige pas un oracle par exception
jeu, on corrige le modèle de preuve ».

`claim_verdict: NO_CLAIM_ALLOWED`.

---

## 0. Les deux preuves, définitivement séparées (décision 1)

| Preuve | Question à laquelle elle répond | Commande |
|---|---|---|
| **Mutation** | « mes tests détectent-ils des changements invalidants ? » | `proof.mutation.command` — **dédiée** |
| **Solvabilité** | « le jeu reste-t-il jouable ? » | commande d'oracle du jeu (`oracles.json`) |

**La mutation ne réutilise JAMAIS l'oracle complet par défaut.** Si `proof.mutation.command`
manque alors que le descripteur existe ⇒ `BLOCKED`. Pas de repli implicite : c'est ce repli qui
a produit le défaut d'origine.

*Fait mesuré qui fonde la séparation (Snake, 2026-07-28)* : 64 mutants × 0,27 s (commande dédiée)
≈ **17 s**, contre 64 × 13,3 s (oracle complet, 50 essais de solvabilité par mutant) ≈ **14 min**.
Facteur 50 — et les 50 parties rejouées ne prouvent rien sur la logique mutée.

---

## 1. Emplacement du descripteur (décision 2)

**`<jeu>/00_CHARTER/game_contract.yaml`, clé `proof:`.** La vérité du jeu reste dans le jeu.

`oracles.json` **peut référencer** des capacités (il porte déjà `cwd`, `command`, et depuis le
28-07 un bloc `solvability`) mais **ne devient jamais propriétaire du contrat de preuve**.

---

## 2. Schéma `proof` (V1)

```yaml
proof:
  schema_version: 1
  runtime: godot                     # DOIT appartenir à `runtimes:` du même fichier
  mutation:
    categories_mutables: [system, entity]
    categories_exclues:  [system.adapter, test.unit, test.oracle,
                          asset.sprite, asset.audio, asset.font,
                          godot.project_root, godot.project_tests]
    command: ["<bin:godot>", "--headless", "--path", ".", "--script", "res://tests/run_tests.gd"]
    cwd: "games/snake"               # relatif à la racine du dépôt
    binary_ref: godot                # résolu par godot_bin.mjs — jamais un chemin machine
    expects_exit_zero: true
    budget:
      max_mutants: 200
      timeout_per_mutant_s: 30
      total_timeout_s: 900
      cost_class: engine             # process | engine
    seals:
      wrapper:      []
      test_scripts: ["tests/run_tests.gd"]     # relatif au jeu, NON VIDE
  solvability:
    entry: "solvability.gd"
    max_ticks: 5000
    trials: 50
    trial_timeout_ms: 60000
```

**Règles de forme — toutes mécaniquement vérifiables, toutes bloquantes :**
1. `runtime` ∈ `runtimes:` du même fichier.
2. Toute catégorie citée existe dans `repo_map.yaml`.
3. `categories_mutables ∩ categories_exclues = ∅`.
4. **Leur union couvre toutes les catégories présentes dans la wiremap** (règle anti-oubli, §5).
5. Chemins **relatifs** uniquement — aucun chemin absolu ni utilisateur.
6. `command` sans chemin machine : le binaire vient de `binary_ref`.
7. `cwd` existe et est dans le dépôt.
8. `budget.max_mutants` et `timeout_per_mutant_s` obligatoires si `cost_class: engine`.
9. `seals.test_scripts` non vide — sinon la chaîne de preuve est rompue par construction.
10. Descripteur **absent** ⇒ régime historique (§6), jamais un blocage.

---

## 3. Scellement — la chaîne complète (décision 3)

But ratifié : pouvoir répondre après coup à **« quelle preuve exacte a produit ce verdict ? »**

On scelle, dans cet ordre : **déclaration du jeu · commande demandée · commande réellement
exécutée · wrapper · scripts de test · paramètres · version du runtime · résultat brut.**

```jsonc
"proof_chain": {
  "schema_version": 1,
  "runtime_declare": "godot",
  "command_declaree": ["<bin:godot>", "--headless", "--path", ".", "--script", "res://tests/run_tests.gd"],
  "command_executee": ["C:/…/Godot_v4.6.3…console.exe", "--headless", "…"],
  "declaration_conforme": true,          // false ⇒ le gate REFUSE
  "cwd_execute": "games/snake",
  "binaire": {"ref": "godot", "version": "4.6.3.stable.official.7d41c59c4"},
  "wrapper_sha256": {},
  "test_scripts_sha256": {"tests/run_tests.gd": "…"},
  "parametres": {"max_mutants": 200, "timeout_per_mutant_s": 30, "total_timeout_s": 900},
  "resultat_brut_sha256": "…",
  "resultat_brut_path": "lab/forge_evidence/mutation_<run_id>.raw.txt"
}
```

**Invariant central (décision Pierre) : le reçu reflète ce qui a TOURNÉ, pas ce qui était prévu.**
`command_declaree` et `command_executee` sont **deux champs distincts** ; leur divergence est
portée par `declaration_conforme: false` et **refusée par le gate**. Un descripteur est une
intention ; seul l'exécuté fait preuve. La `version` du runtime est **mesurée à l'exécution**,
jamais recopiée.

### 3.1 Référence symbolique de binaire `<bin:name>` — RÈGLE (ratifiée Pierre 2026-07-28)

Cette règle était auparavant seulement **illustrée par un exemple** du §3 ; elle est ici une
règle de plein droit, car une égalité littérale entre déclaration et exécution rejetterait
toute résolution de binaire légitime.

1. Une déclaration de la forme **`<bin:name>`** est une **référence symbolique autorisée** dans
   `proof.mutation.command` (et elle seule — aucun chemin machine n'est admis, règle de forme 6).
2. Elle **doit être résolue vers un binaire réel au moment de l'exécution** (pour `godot` :
   `scripts/forge/godot_bin.mjs`, qui lit `GODOT_BIN` puis `godot.config.json`, tous deux hors
   dépôt et non versionnés).
3. Le reçu conserve **les trois** :
   - la **déclaration originale** (`command_declaree`, symbole inclus) ;
   - la **résolution effective** (`command_executee`, chemin réel) ;
   - la **preuve que la résolution correspond au symbole demandé** — `binaire: {ref, version}`,
     la `version` étant mesurée à l'exécution.
4. **Portée stricte de la tolérance** : seule la substitution du **token portant le symbole**
   est admise. Tout autre écart entre déclaration et exécution (argument ajouté, retiré,
   réordonné, fichier de test échangé) reste un **rejet** — `declaration_conforme: false`.

Autrement dit : le symbole autorise l'indirection de *chemin machine*, jamais l'indirection de
*ce qui est exécuté*.

`code_sha256` (existant) est conservé tel quel : aucun reçu déjà produit ne devient invalide.

---

## 4. Budget (décision 4)

| Paramètre | Valeur ratifiée | Base mesurée |
|---|---|---|
| `max_mutants` | **200** | besoin réel Snake = 64 ⇒ marge ×3 |
| `timeout_per_mutant_s` | **30** | mesuré 0,27 s ⇒ marge ×100 |
| `total_timeout_s` | **900** | 64 × 0,27 ≈ 17 s ⇒ marge ×50 |

**Dépassement ⇒ `BLOCKED` explicite. Jamais un résultat partiel présenté comme preuve.**
Le reçu porte `mutants_generes` **et** `mutants_executes` : s'ils diffèrent, le gate refuse.

**Anti-piège du dénominateur** — le reçu porte un compteur **par fichier**, pas seulement global.
Mesuré sur Snake : `state.gd` porte 40 des 64 mutants (62 %), et **5 fichiers en génèrent 0**.
Un fichier à 0 mutant est **NON_MESURE**, jamais « 100 % couvert » : un agrégat afficherait
« 100 % » alors que 5 fichiers n'ont rien prouvé.

---

## 5. `NON_APPLICABLE` — tranché (décision 5)

**Pas de « skip » générique.** `passed: true` n'est accordé que si la raison est **contractuelle
ET prouvée**. Trois cas, mécaniquement distinguables :

| Situation | Détection mécanique | Verdict |
|---|---|---|
| **Le jeu ne possède pas ce système** — catégorie déclarée dans `categories_mutables`, mais **aucune ligne de la wiremap ne la porte** | catégorie ∈ déclaration ∧ absente de la wiremap | **NON_APPLICABLE, `passed: true`** — déclaré *et* prouvé par la carte |
| **Catégorie oubliée dans la déclaration** — catégorie **présente dans la wiremap**, absente des deux listes | catégorie ∈ wiremap ∧ ∉ (mutables ∪ exclues) | **BLOCKED** (règle de forme 4) |
| **Catégorie déclarée mais impossible à mesurer** — présente, mutable, mais aucune mesure possible (commande en échec, baseline rouge, scellement impossible, ou **0 mutant sur toute la catégorie**) | mesure tentée, aucun résultat exploitable | **BLOCKED** |

**Niveau fichier vs niveau catégorie — à ne pas confondre** : un *fichier* isolé à 0 mutant est
`NON_MESURE` et rapporté comme tel (§4) ; si **toute une catégorie déclarée mutable** ne produit
aucun mutant, elle tombe dans le 3ᵉ cas ⇒ **BLOCKED**.

Récapitulatif des issues possibles, aucune ne produisant de vert silencieux :
`NON_APPLICABLE` (vert déclaré et prouvé) · `NON_MESURE` (fichier, `passed: false`) ·
`BLOCKED` (oubli, impossibilité, dépassement de budget, divergence déclaration/exécution) ·
`FAIL` (survivants non triés — gate historique inchangé : « 100 % ou survivant justifié »).

---

## 6. Migration (décisions 1 et 6)

Critère : **l'activité, pas l'ancienneté.**

| Cas | Règle | Effet |
|---|---|---|
| **Nouveau jeu** (première wiremap) | descripteur **obligatoire** | absent ⇒ `BLOCKED` |
| **Jeu legacy gelé** | **ancien régime conservé à l'identique** | branche `deprecated` **nommée** + liste explicite des jeux qui en dépendent |
| **Retour en production** | **migration obligatoire avant le run** | pas de descripteur ⇒ `BLOCKED` |

**PONG N'EST PAS MIGRÉ (décision 6, ferme).** Il reste le témoin gelé ; aucune modification, même
purement déclarative, sans gate dédiée. Verbatim Pierre : « on ne touche pas au juge pendant
qu'on refait le tribunal. » Pong passe donc par le **régime historique**, qui doit rester
**strictement inchangé** — c'est l'objet des tests de coexistence (§7).

État mesuré du parc : 2 jeux ont une wiremap (pong, snake) · 2 ont un `game_contract.yaml`
(pong, snake) · 9 ont un `mutation_triage.json`. La dette de migration est donc **bornée à 1 jeu**
(snake), Pong étant explicitement hors migration.

---

## 7. Tests de coexistence — exigés AVANT toute implémentation (décision 7)

Trois preuves, à produire **avant** de brancher le driver :

1. **Snake avec `proof.mutation` → nouveau chemin.** Le descripteur est lu ; périmètre par
   catégorie ; commande dédiée ; `proof_chain` scellée dans le reçu.
2. **Pong sans descripteur → ancien chemin inchangé.** Même périmètre qu'aujourd'hui, même
   `detail` de reçu, aucun champ nouveau exigé. Toute divergence = régression.
3. **Témoin Pong 72/72 inchangé**, exit 0, `git status games/pong/` vide.

Ces trois preuves sont la **condition d'entrée** de l'implémentation, pas sa conclusion.

---

## 8. Ordre d'exécution ratifié

```
① figer le contrat V1        ← CE DOCUMENT
② tests de coexistence       ← avant tout branchement
③ brancher le driver         ← seulement après ② vert
```

**La prochaine étape n'est pas du code Snake.**

---

## 9. Hors périmètre

`product_oracle` (advisory, mis de côté par décision Pierre) · la carte Snake
(`observable_by_player` rouge depuis la garde du 28-07 — « on corrige d'abord l'instrumentation,
puis on remet les données au format du contrat ») · `repo_map.yaml` (table figée, lue jamais
écrite) · le seuil du gate mutation (inchangé) · toute migration de Pong.

---
software_verdict: OK (spécification figée ; aucun code) ·
evidence_verdict: MECHANICAL_VALIDATION_ONLY · claim_verdict: NO_CLAIM_ALLOWED

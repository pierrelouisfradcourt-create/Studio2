# Analyse — Dépôt manquant de la brique `game_loop` (run `pong_r2`)

Date : 2026-07-27. Source : mission Forge `FORGE_DISPATCH:v2-analyse-depot-game-loop`.
Portée : LECTURE seule (dépôt entier), ÉCRITURE limitée à ce fichier. Aucun changement de
contrat, oracle, catalogue, verdict ou `state.json`. Le dépôt de la brique n'est PAS exécuté
ici — cette mission mesure, elle ne répare pas.

```
software_verdict: OK
evidence_verdict: MECHANICAL_VALIDATION_ONLY
claim_verdict: NO_CLAIM_ALLOWED
```

---

## Résumé en une phrase

`game_loop` n'est **pas prouvée** par le reçu signé de `pong_r2` (oracle code = `FAIL`,
receipt mutation = `FAIL`) et n'a **jamais été déposée** dans `knowledge_base/catalog.json`
parce que le seul code dont c'est le rôle — `studio_link.propose_brick`
(`scripts/forge/studio_link.py:563`) — n'a **aucun appelant** : ni automatique (absent de
`driver.py`, 0 occurrence), ni manuel (`lab/reports/forge_brick_proposals.jsonl` n'existe pas
sur disque, pour aucun projet, jamais), ni contractuel (aucun contrat sous
`scripts/forge/contracts/` ne mentionne `propose_brick`).

---

## 1. `game_loop` est-elle PROUVÉE ? — NON, par le reçu signé lui-même

Source primaire : `lab/forge_runs/pong/verdict.json` (signé HMAC, `hmac` l.6, vérifié par
`verify_run` — `s12-verdict` = `OK` dans `lab/forge_runs/pong/state.json`, donc l'agrégat
lui-même est authentique, ce n'est pas une question de falsification).

- `verdict.json` l.276 : `"software_verdict": "FAIL"`, l.3 : `"decision": "BLOCKED"`.
- `verdict.json` l.184-187 : `oracles.code.status = "FAIL"`.
- `verdict.json` l.38-159 (`oracles.code.detail.mutation.receipt`) : `"status": "FAIL"`,
  `"killed": 58`, `"survived": 68`, `"total": 126`, `"triaged_survivors": []` — 68 mutants
  survivants, **zéro triés/justifiés**.
- `lab/forge_runs/pong/state.json` : `s10a-oracle-code` = `FAIL` (2 tentatives),
  `s9-build-standard` = `OK` (2 tentatives — le build a été retenté, l'oracle a rougi les
  deux fois), `run_status: DONE`. Le run n'est pas resté bloqué en infrastructure : il est
  allé au bout et a rendu un FAIL honnête.

Par la règle du studio (« preuve d'exécution, pas d'existence », `CLAUDE.md`) : le fichier
`games/pong/05_SYSTEMS/game_loop/loop.mjs` existe et compile, mais le gate mécanique qui est
censé PROUVER son comportement (mutation testing) est rouge sur l'ensemble des fichiers
logiques du run. La réponse mécanique, au niveau du reçu signé qui fait foi pour HumanGate,
est donc **NON PROUVÉE**.

### Nuance factuelle (n'change pas le verdict ci-dessus, l'explique)

`lab/forge_runs/pong/evidence/mutation_pong_r2.json`, `mutation_result.per_file` (l.183-224)
donne le détail PAR FICHIER que le reçu agrégé n'expose pas :

| Fichier | killed/total | % |
|---|---|---|
| `05_SYSTEMS/game_loop/loop.mjs` | 14/15 | 93 % |
| `05_SYSTEMS/game_state/state.mjs` | 29/29 | 100 % |
| `05_SYSTEMS/input/input.mjs` | 15/17 | 88 % |
| 7× `06_RUNTIME/adapters/presentation/*.mjs` | 0/65 (chacun 0 tué) | 0 % |

Arithmétique vérifiée : 14+29+15 = 58 tués sur les 3 fichiers « système » (61 mutants,
95 %) ; les 7 adaptateurs de présentation portent 65 des 68 survivants (0 % tué sur chacun).
`loop.mjs` lui-même contribue **1 seul** survivant non trié sur 15 mutants — mais le gate
mutation du driver (`scripts/forge/driver.py:824-855`, `_run_code_oracle`) traite
`logic_files` comme **un seul lot** : `receipt.receipt.status != "OK"` fait tomber
`s10a-oracle-code` en `FAIL` globalement (driver.py l.839-841), sans distinction par fichier
ni par brique. Il n'existe **aucun mécanisme de preuve mutation scopé à une seule brique** —
c'est un fait du gate actuel, pas une opinion sur ce qu'il devrait mesurer.

Une analyse sœur de ce même run (`docs/audit/ANALYSE_PERIMETRE_LOGIC_FILES_2026-07-26.md`,
mission `v3-analyse-perimetre-logic-files`) documente indépendamment la même arithmétique et
sa cause (les adaptateurs de présentation entrent dans `logic_files` par un filtre générique
jamais spécialisé pour les exclure) — corroboration croisée, pas une hypothèse isolée de cette
mission.

**Conclusion du point 1** : `game_loop` n'est pas prouvée par le reçu signé (FAIL global,
0 survivant trié). `loop.mjs` pris isolément affiche un score de mutation fort (93 %, 1
survivant non trié), mais le studio n'a aujourd'hui aucun instrument qui transforme ce fait
en preuve PAR BRIQUE recevable pour un dépôt — voir §4.

---

## 2. Cause du dépôt manquant — UNE des trois, avec preuve d'appelant

### Élimination des deux autres causes (preuve négative)

- **« Rien produit »** — FAUX. `games/pong/05_SYSTEMS/game_loop/loop.mjs` (132 lignes) et ses
  tests (`07_TESTS/unit/loop.test.mjs`, cité dans `verdict.json` l.55 et l.138) existent sur
  disque, avec sha256 vérifiés dans le reçu mutation (`verdict.json` l.43).
- **« Absence d'enregistrement » comme fait isolé** — c'est la SYMPTÔME observé
  (`knowledge_base/catalog.json` interrogé mécaniquement : `entry_type=="brick"` → 10
  entrées, aucune nommée `game_loop`/`sys-game-loop`/toute variante — commande :
  `python -c "import json; d=json.load(open('knowledge_base/catalog.json',encoding='utf-8')); print([e['brick_id'] for e in d['entries'] if e.get('entry_type')=='brick'])"`
  → `['pat-damage-floor', 'pat-full-reachability', 'pat-zone-of-control', 'sys-damage-floor',
  'sys-reachability', 'sys-pursuer-mobile', 'sys-evader-basic', 'sys-guardian-zoc',
  'sys-pursuer-continuous', 'sys-grid-nav-m01']`). Mais ce n'est pas la CAUSE — c'est la
  conséquence directe de la cause ci-dessous.

### Cause retenue : défaut du pipeline de dépôt — **implémenté et non branché**

Le code dont c'est explicitement le rôle existe :

- `scripts/forge/studio_link.py:563-599`, fonction `propose_brick(run_id, project, brick_id,
  kind, function, path, ...)`. Commentaire d'origine (`studio_link.py:552-561`) : audit
  2026-07-23 constate « un jeu forgé n'a AUCUN moyen de déposer une brique dans la
  bibliothèque » ; `propose_brick` est construit comme correctif — PROPOSE-ONLY (écrit
  `lab/reports/forge_brick_proposals.jsonl`, ne touche jamais `catalog.json`), la promotion
  restant 100 % humaine par ratification Pierre du 2026-07-23.
- CLI exposée : `studio_link.py:701` (sous-commande `brick`) et `:765` (dispatch).
- Testée : `scripts/forge/tests/test_studio_link.py:115-140`
  (`test_propose_brick_is_propose_only_and_never_writes_catalog`,
  `test_propose_brick_default_path_is_forge_reports_not_knowledge_base`).

Recherche d'appelant réelle (garde-fou : preuve d'appel ou preuve d'absence) :

- `grep -n "propose_brick" scripts/forge/driver.py` → **0 résultat**. Le driver, qui exécute
  intégralement `pong_r2` du build au verdict signé (`_run_deterministic`, `_run_code_oracle`,
  `_run_standard_oracle`, `_run_verdict`), n'appelle `propose_brick` à **aucune** étape —
  ni après `s9-build-standard` (build terminé), ni après `s10a-oracle-code`, ni après
  `s12-verdict` (verdict signé, même FAIL).
- `grep -rln "propose_brick" scripts/forge/` → seulement 3 fichiers : la définition + CLI
  (`studio_link.py`), sa lecture en aval par `pending_review.mjs` (qui consomme le fichier de
  propositions pour l'afficher à Pierre, ne le produit pas), et ses tests unitaires. Aucun
  script d'orchestration (`driver.py`, `dispatch.py`, `escalate.py`, `verdict.py`) n'y fait
  référence.
- `grep -n "propose_brick" scripts/forge/contracts/*.yaml` → **0 résultat**. Aucun contrat
  d'agent (`s9-build-standard.yaml`, `s10s-oracle-standard`, `s11-redteam-code`,
  `s12-verdict`) n'instruit un agent d'invoquer `propose_brick`, même manuellement.
- `scripts/forge/contracts/s9-build-standard.yaml:53` : « Le builder ne modifie jamais
  `catalog.json` (propose-only). » et `:74` (`out_of_scope`) : « Ne touche PAS … à
  `knowledge_base/catalog.json` » — le SEUL agent en contact avec le code produit est
  explicitement interdit d'écrire au catalogue, et n'est mandaté nulle part pour proposer.
- Preuve d'absence d'exécution, même manuelle, pour CE run et pour TOUS les runs passés :
  `Glob("lab/reports/*brick*")` → aucun fichier. `DEFAULT_BRICK_PROPOSALS` résout à
  `lab/reports/forge_brick_proposals.jsonl` (`studio_link.py:49`) — ce chemin n'existe pas
  sur disque, ce qui signifie que `propose_brick` n'a **jamais été exécuté une seule fois**
  dans ce dépôt, pour aucun projet, depuis sa création (commit `74f3dd0`,
  `git log -S "def propose_brick" -- scripts/forge/studio_link.py`).
- Confirmation croisée côté mécanisme du gate lui-même : `scripts/forge/driver.py:987-1015`
  (`_run_standard_oracle`) calcule `deposited = sorted(set(catalog_now.keys()) -
  set(snapshot))` — un différentiel **du catalogue réel au démarrage vs à l'oracle**. Comme
  rien n'écrit jamais `catalog.json` en dehors d'une édition humaine directe (recherche
  élargie : aucun `writeFileSync`/`json.dump` visant `catalog.json` trouvé dans
  `scripts/` ni `knowledge_base/` — seuls des LECTEURS : `search.mjs`, `asset_request.mjs`,
  `kb-validate.mjs` [validateur, ne modifie rien], `fill_usage_examples.mjs`,
  `learning_hook.py`/`learning_metrics.mjs` [explicitement advisory, commentaire
  `learning_hook.py:22` : « aucune brique n'est fabriquée à partir d'un jeu »]), ce
  différentiel est **structurellement toujours vide** pour tout run tant qu'aucun humain n'a
  édité le catalogue entre le snapshot et l'oracle. `check_budget` (l.243,
  `standard_oracles.py`) traduit alors mécaniquement toute promesse `adds` non déposée en
  `promis_non_depose` — exactement le volet rouge observé (`verdict.json` l.197-199).

**Verdict de cause, sans ambiguïté** : le mécanisme de dépôt existe en code
(`propose_brick`) mais est **implémenté et non branché** — aucun appelant automatique
(driver) et aucun appelant manuel n'a jamais été exercé (fichier de sortie inexistant), et
aucun contrat n'en fait une obligation pour quelque agent que ce soit. Ce n'est ni « rien
produit » (le code de la brique existe) ni un pipeline qui aurait échoué en silence
(« branché et silencieux » — il n'est simplement pas branché, il n'y a rien à observer
échouer).

---

## 3. Composant qui devrait porter le dépôt

- **Fonction existante, jamais appelée** : `scripts/forge/studio_link.py:563`
  (`propose_brick`).
- **Point de câblage naturel absent** : `scripts/forge/driver.py`, méthode `_run_verdict`
  (l.1054-1122) — c'est le point où le driver connaît déjà `budget.adds` (via
  `game_contract`), le statut final de `s10a-oracle-code`, et le chemin des fichiers
  produits (`logic_files` du reçu mutation). Aucun appel à `propose_brick` n'y existe
  aujourd'hui.
- **Écart qualifié** (garde-fou du contrat, 3 valeurs possibles) : **« implémenté et non
  branché »** — ni « jamais implémenté » (le code existe et est testé), ni « branché et
  silencieux » (il n'y a pas de branchement à observer échouer).

---

## 4. Correction recommandée — chiffrée, NON implémentée

Deux volets distincts, à ne pas fusionner (une variable à la fois, cf. règle du studio) :

### 4a. Brancher le dépôt (ferme la cause structurelle)

- Ajouter, dans `ForgeDriver._run_verdict` (`driver.py`, après l'écriture de `verdict.json`,
  avant ou après `verify_run`), un appel best-effort à `studio_link.propose_brick` pour
  chaque `brick_id` de `budget.adds` **dont le statut code final est `OK`** (jamais pour un
  run FAIL/BLOCKED — proposer une brique non prouvée serait fabriquer une fausse promesse à
  l'envers). Patron identique à `propose_ledger_entry` déjà appelé nulle part non plus dans
  driver.py — vérifier au passage si CE branchement-là est voulu ou si le mécanisme entier
  des `propose_*` est intentionnellement CLI-only (point à trancher par Pierre, cf. §5).
- Périmètre : 1 fonction modifiée (`_run_verdict`), ~10-15 lignes (garde `if final code ==
  OK`, boucle sur `adds`, appel best-effort try/except comme `_journal_error`/
  `record_telemetry` déjà présents dans la même méthode), + 2-3 tests
  (`test_standard_step_wiring.py` ou nouveau fichier) vérifiant l'appel sur run vert et
  l'ABSENCE d'appel sur run FAIL/BLOCKED.
- Coût estimé : petit (< 1h agent), risque bas (best-effort, ne peut pas dégrader un verdict
  existant — même garantie que `record_telemetry`).

### 4b. Rendre `game_loop` prouvable en tant que brique isolée (ferme la cause de fond du §1)

- Le gate mutation actuel ne peut PAS aujourd'hui produire une preuve « cette brique
  précise est prouvée » — il ne connaît que « tous les fichiers logiques du run,
  ensemble ». Déposer `game_loop` sur la seule foi du 93 %/1-survivant de `loop.mjs` isolé
  reviendrait à fabriquer une preuve que le gate signé ne porte pas.
- Recommandation : traiter ce point APRÈS arbitrage de
  `docs/audit/ANALYSE_PERIMETRE_LOGIC_FILES_2026-07-26.md` (mission sœur, même run, question
  adjacente : faut-il exclure `system.adapter` de `logic_files`, ou lui donner sa propre
  preuve type `bot_action`/`pixel`). Un dépôt de `game_loop` avant cet arbitrage serait
  prématuré : soit le gate mutation change de périmètre (et le reçu FAIL actuel devient
  obsolète), soit il ne change pas (et `game_loop` reste embarquée dans un lot qui doit
  d'abord retrouver un mutation `OK` global, ce qui exige de traiter les 65 survivants
  adaptateurs).
- Coût estimé : dépend de l'arbitrage (hors périmètre chiffrable ici).

**Aucun des deux volets n'est implémenté par cette mission.**

---

## SKIPPED_VALIDATION

`SKIPPED_VALIDATION: aucun`. Toutes les sources requises (`game_contract.yaml`,
`standard_oracles.py`, `verdict.json`, `driver.py`, `knowledge_base/`) ont été lues
intégralement ou par recherche ciblée exhaustive (grep repo-wide sur les noms candidats de
dépôt, `git log -S` sur `propose_brick`, glob direct sur le fichier de sortie attendu).
Aucune commande d'oracle n'a été exécutée (hors périmètre — mission de mesure, pas de
preuve logicielle nouvelle).

---

## Contrat de sortie

```json
{
  "resume_1_phrase": "game_loop n'est ni prouvée (reçu signé FAIL) ni déposée (catalog.json inchangé) parce que le dépositaire propose_brick existe mais n'a aucun appelant, automatique ou manuel.",
  "brique_prouvee": {
    "reponse": "NON",
    "preuves": [
      "lab/forge_runs/pong/verdict.json:276 software_verdict=FAIL",
      "lab/forge_runs/pong/verdict.json:184-187 oracles.code.status=FAIL",
      "lab/forge_runs/pong/verdict.json:38-159 mutation.receipt.status=FAIL, survived=68/126, triaged_survivors=[]",
      "lab/forge_runs/pong/evidence/mutation_pong_r2.json:184-187 loop.mjs=14/15 tués (93%, 1 survivant non trié) — nuance factuelle, pas une preuve OK au niveau du gate agrégé"
    ]
  },
  "cause": {
    "laquelle": "défaut du pipeline de dépôt — implémenté et non branché",
    "fichier_ligne": "scripts/forge/studio_link.py:563 (propose_brick, jamais appelé) ; scripts/forge/driver.py (0 occurrence de propose_brick, grep exhaustif)",
    "preuve": "grep -n propose_brick scripts/forge/driver.py -> 0 résultat ; Glob lab/reports/*brick* -> 0 fichier (jamais exécuté, aucun projet) ; grep propose_brick scripts/forge/contracts/*.yaml -> 0 résultat (aucun mandat contractuel)"
  },
  "mecanisme_de_depot": {
    "existe": true,
    "statut": "implémenté et non branché",
    "composant_attendu": "scripts/forge/driver.py::_run_verdict (point de câblage naturel absent) appelant scripts/forge/studio_link.py::propose_brick"
  },
  "correction_recommandee": {
    "perimetre": "4a: ForgeDriver._run_verdict + ~10-15 lignes + 2-3 tests. 4b: hors périmètre chiffrable, dépend de l'arbitrage ANALYSE_PERIMETRE_LOGIC_FILES_2026-07-26",
    "cout_estime": "4a: < 1h agent, risque bas (best-effort). 4b: indéterminé, gate par Pierre",
    "non_implementee": true
  },
  "rapport_path": "docs/audit/ANALYSE_DEPOT_GAME_LOOP_2026-07-26.md",
  "git_status_final": "seul docs/audit/ANALYSE_DEPOT_GAME_LOOP_2026-07-26.md ajouté par cette mission ; le dépôt porte par ailleurs des changements concurrents d'autres sessions (hors périmètre de cette mission, non touchés)",
  "skipped_validation": [],
  "software_verdict": "OK",
  "evidence_verdict": "MECHANICAL_VALIDATION_ONLY",
  "claim_verdict": "NO_CLAIM_ALLOWED"
}
```

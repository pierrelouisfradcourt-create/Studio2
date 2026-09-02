# SAS 3 — `EXPECTED_PROOF` ↔ `ACTUAL_PROOF` : l'anneau

*2026-09-02 · **INSTRUCTION UNIQUEMENT** · aucun code, aucun fichier du dépôt source modifié.
Dépôt source `feeb29cb`, 89 lignes de statut.*

---

## 0 · Correction de la prémisse — la jointure n'est pas à inventer

J'ai porté pendant plusieurs sas la mesure *« 26 identifiants attendus vs 25 réels, intersection
0 »*. **Elle était fausse par choix de champ** : je comparais les noms de features des deux côtés,
alors que la jointure ne passe pas par là.

> `contracts/s5-wiremap.yaml`, `output_contract`, verbatim :
> *« chaque ligne porte en plus `couvre: ["<id de capacité>"]`, **NON VIDE**, citant l'`id`
> **EXACT** d'une capacité (feuille) de `featuremap.json`. **Sans ce champ, le delta attendu-vs-réel
> n'est calculable par personne** : une carte qui ne dit pas ce qu'elle réalise ne se confronte à
> aucun plan. »*

**La jointure est spécifiée, nommée, et son oracle existe** :
`check_wiremap_contract.mjs --featuremap` — *« toute capacité portée par ≥1 ligne, aucun `couvre`
fantôme »*. Sas 3 ne construit donc rien : **il mesure pourquoi une jointure spécifiée ne tient
pas.**

---

## 1 · La mesure — 12 runs portant les deux artefacts

| run | cap. id | lignes | `couvre` rempli | `couvre` = id réel | orphelins | capacités non couvertes |
|---|---|---|---|---|---|---|
| auto_battler_i1 | 0 | 25 | 0 | 0 | 0 | — |
| auto_battler_i2 | 0 | 13 | 0 | 0 | 0 | — |
| auto_battler_i2_5 | 0 | 53 | 0 | 0 | 0 | — |
| card_engine | 0 | 39 | 0 | 0 | 0 | — |
| chain_probe_v1 | 19 | 13 | **13** | **0** | 15 | **19 / 19** |
| p1_beta | 20 | 15 | **15** | **0** | 13 | **20 / 20** |
| **p1_beta_E1** | 20 | 22 | 22 | **20** | 0 | **0** ✅ |
| p2_alpha | 26 | 25 | **25** | **0** | 27 | **26 / 26** |
| p2_beta | 15 | 13 | **13** | **0** | 16 | **15 / 15** |
| p3_alpha | 23 | 20 | **20** | **0** | 21 | **23 / 23** |
| **pacman** | 62 | 67 | 67 | **62** | 0 | **0** ✅ |
| tower_defense_sonde | 55 | 55 | **55** | **0** | 47 | **55 / 55** |

### Trois régimes, pas un
```
2 runs   jointure TENUE            p1_beta_E1 · pacman
6 runs   couvre REMPLI, IDS FAUX   100 % d'orphelins — noms de fonctions au lieu d'ids de capacité
4 runs   couvre ABSENT             génération antérieure : 0 capacité identifiée
```

> **Le mode dominant n'est pas l'oubli, c'est le remplissage sans référent.** `couvre` est présent,
> **non vide** — donc formellement conforme à la lettre du contrat — et cite `["currentObjective"]`,
> un nom de fonction. **La forme est satisfaite, la jointure est vide.**
> C'est R8 mot pour mot : *un consommateur ne se trouve pas à la forme du nom.* Un `couvre` n'est
> pas une couverture parce qu'il s'appelle `couvre`.

---

## 2 · L'oracle fonctionne. Personne ne lit son verdict.

```
node check_wiremap_contract.mjs lab/forge_runs/p1_beta/wiremap.json --featuremap …/featuremap.json
  exit = 1
  FAIL couverture: capacite 'cap_goal_terminal_hud' … n'est portee par aucune ligne (omission silencieuse)
  … 20 fois
  stats: 0 sur 20 capacite(s) couverte(s)
```
```
state.json  →  s5-wiremap : statut = OK        (p1_beta ET p2_alpha)
```

**L'oracle rend `exit 1` et nomme la faute avec le vocabulaire même du contrat. L'étape est OK.**

Chaîne de consommation, mesurée :
```
check_wiremap_contract.mjs
  └─ importé UNIQUEMENT par repair_step.mjs        (0 appel dans driver.py)
       └─ run_real.py:3357   mesure = run_repair_step(...)
            └─ res["repair"] = mesure              ← ENREGISTRÉ
                                                     jamais de res["blocked"]
```
Et sur les runs concernés, `detail.repair` est **absent** : la mesure n'a même pas été consignée.

> **Ce n'est pas une jointure manquante. C'est un oracle sans exécuteur de verdict** — le motif que
> ce studio a déjà nommé (*« un test non appelé par un oracle n'existe pas »*, *« une vérification
> peut être verte sans avoir eu lieu »*). La porte de suffisance existe : **elle n'est branchée sur
> rien.**

---

## 3 · Le second maillon, non mesuré jusqu'ici : `preuve` n'est pas une preuve

L'anneau a **deux** maillons, et le sas 3 ne peut pas n'en traiter qu'un.

```
capacité.expected_proof  ──(1)──  ligne de wiremap        `couvre`
ligne de wiremap         ──(2)──  reçu d'oracle signé      ???
```

Maillon (1) : spécifié, outillé, non tenu — §1 et §2.
Maillon (2) : le champ `preuve` d'une ligne de wiremap est **du texte écrit par l'agent** —
*« e2e.mjs: getElementById('objective')… »*. C'est une **allégation de preuve**, pas un reçu. Rien
ne relie une ligne de wiremap au reçu d'oracle qui l'établirait.

### Ce que déclarent les 271 capacités mesurées
```
expected_proof.kind :  bot_action 80 · visual 79 · oracle 74 · mutation 7
                       (+ 31 capacités en prose seule, sans `kind` — génération card_engine)
```
`ORDER` exécute `s10a-oracle-code`, `s10b-oracle-archi`, `s10c-oracle-wiremap`.
**`s10d-oracle-visual` n'est pas dans l'ORDER** — et c'est le contrat que le contrôle d'orphelins a
classé SORTANT.

> **79 preuves attendues de type `visual`, et le seul contrat d'oracle visuel est hors chaîne.**
> Ce n'est pas un défaut d'exécution : c'est un `kind` déclarable auquel **aucune famille d'oracle
> ne répond**. Une preuve attendue qu'aucun mécanisme ne peut rendre est une promesse, pas une
> exigence.

---

## 4 · Ce que sas 3 doit faire trancher — et rien d'autre

| # | question | nature | mon avis |
|---|---|---|---|
| **J-1** | **Qui consomme le verdict de `check_wiremap_contract` ?** Aujourd'hui : personne. | branchement | le brancher **advisory d'abord** (surface dans `state.json` + reçu), gate dur en décision séparée — c'est le chemin 2026-07-26, et N-2 vient d'en payer le prix inverse |
| **J-2** | **`couvre` rempli avec des ids fantômes** : faute d'agent, ou contrat trop faible ? | contrat | le contrat dit « id EXACT » ; il est **respecté à la lettre et violé au fond**. Durcir la *vérification*, pas la prose : c'est déjà ce que l'oracle sait faire |
| **J-3** | **Quelle est l'unité de la jointure** — capacité (240 en portent un id) ou règle Rn (172) ? | schéma | **la capacité** : `expected_proof` est portée par la capacité, pas par la règle. Joindre plus haut perdrait ce qu'on veut prouver |
| **J-4** | **`kind: visual`** — 79 attentes, aucune famille d'oracle dans l'ORDER. | gouvernance | **ne pas fabriquer un oracle pour faire un chiffre.** Soit `visual` cesse d'être un `kind` déclarable, soit il reçoit un répondant nommé. Trancher avant de mesurer la suffisance |
| **J-5** | **Maillon (2)** : une ligne de wiremap doit-elle citer le **reçu** qui l'établit ? | schéma | oui à terme — mais **après** J-1. Une jointure de plus sur une jointure non branchée n'ajouterait qu'une déclaration |

### Ce que je ne recommande pas
**Ne pas réparer les 6 runs.** Ce sont des **preuves du défaut**, et les corriger effacerait la seule
population sur laquelle mesurer si un branchement advisory change quelque chose. *(Règle déjà
ratifiée : ne pas nettoyer avant la cause.)*

---

## 5 · État
```
status_by_surface:
  preflight_head:            TESTED   # feeb29cb, 89 lignes
  join_is_specified:         TESTED   # s5-wiremap output_contract, verbatim
  join_measured_12_runs:     TESTED   # 2 tenues · 6 ids fantômes · 4 absentes
  oracle_works:              TESTED   # exit 1, « omission silencieuse », 0/20
  oracle_verdict_unconsumed: TESTED   # 0 appel driver ; res["repair"] enregistré, jamais bloquant
  step_ok_despite_failure:   TESTED   # s5-wiremap OK sur p1_beta et p2_alpha
  expected_proof_kinds:      TESTED   # bot_action 80 · visual 79 · oracle 74 · mutation 7
  visual_has_no_oracle:      TESTED   # s10d hors ORDER, contrat classé SORTANT
  link_to_receipts:          NOT_FOUND # maillon (2) : `preuve` est une allégation
  decisions_J1_J5:           BLOCKED   # arbitrage Pierre
  implementation:            BLOCKED
```
`software_verdict: OK` (instruction) · `evidence_verdict: MECHANICAL_VALIDATION_ONLY` ·
`claim_verdict: NO_CLAIM_ALLOWED` · `no_global_ready_verdict: true`

**Q2 / R8 : non touchée.** Aucun run réparé, aucun contrat modifié, aucun oracle branché.

---

## 6 · Passe systématique sur le motif « produit mais perdu » (2026-09-02, après J-1)

Ma formule *« 6ᵉ occurrence »* était une lecture de commentaire. Vérifiée : **15 clés posées sur
`res` par `run_real`, confrontées à ce que `driver.py` lit et recopie.**

| clé | lue par le driver | dans `detail` | verdict |
|---|---|---|---|
| `design_questions_check` · `economy_check` · `findings_note` · `loop_check` · `markdown_check` · `yaml_check` · `transient_retries` · `reason` · **`join_check`** | oui | oui | fermées |
| `findings` · `spawn_link` | oui | non | **consommées ailleurs** (verdict, registre de spawn) — pas une perte |
| **`repair`** | **non** | **non** | **PERDUE — 0 consommateur dans tout `scripts/forge`** |
| `salvageable` · `salvage_path` | non | non | **PERDUES** — seule une note en prose survit dans `reason` |
| `task_id` | non | non | atteint la télémétrie par une autre écriture ; **le commentaire de `run_real.py:3319` affirme « visible aussi dans le détail d'étape » — c'est faux** |

> **`repair` est la plus lourde, et elle touche J-2 de plein fouet.** La boucle de réparation est
> précisément le mécanisme censé corriger un `couvre` fautif — et **son reçu n'est lu par personne**.
> C'est pourquoi `detail.repair` était absent des runs mesurés au §2 : non pas parce que la
> réparation n'a pas tourné, mais parce que **rien ne recopie son résultat**.

```
motif « produit mais perdu » :  6 fermées · 3 ouvertes (repair · salvage · task_id)
```

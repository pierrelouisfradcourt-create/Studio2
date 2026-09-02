# J-4 — `expected_proof.kind` → FAMILLE D'ORACLE : ce qui existe réellement

*2026-09-02 · **MESURE UNIQUEMENT** · aucun code, aucun fichier du dépôt source modifié.
HEAD `feeb29cb`. Population : 12 runs, **240 feuilles adressables** portant un `expected_proof`.*

**Question posée** : pour chaque `kind`, quelle famille existe **réellement dans l'ORDER**, produit
**quel reçu**, permet **quelle observation** ? Et : **que fait-on des 79 `visual` ?**

---

## 1 · La table, mesurée

| `kind` | n | famille réelle | dans l'`ORDER` / câblée ? | reçu produit | observation |
|---|---|---|---|---|---|
| `bot_action` | **80** | garde e2e + solvabilité (`check_e2e_harness`, `check_solvability_wired`) | **oui** — s10a | `oracles.code.detail.e2e {passed, raisons}` · `oracle_measures.solvabilite` | un bot joue une partie et gagne |
| `oracle` | **74** | oracle code / archi / wiremap | **oui** — s10a/b/c | `oracles.{code,archi,wiremap}` signés HMAC | assertions déterministes non-LLM |
| `mutation` | **7** | preuve de mutation | **oui** — s10a | `oracles.code.detail.mutation {receipt, signature}` | la suite tue-t-elle les mutants |
| **`visual`** | **79** | **deux capacités existent** — voir §2 | **une câblée, une hors ORDER** | **rien, sur les 8 runs concernés** | — |
| *(aucun `kind`)* | *31* | — | — | — | vocabulaire antérieur (`card_engine`) |

**Trois `kind` sur quatre ont une famille câblée qui produit un reçu.** Le problème est entier sur
le quatrième — et il n'est pas celui que j'annonçais.

---

## 2 · `visual` — ni « mal nommé », ni « sans producteur ». Une quatrième réponse.

Tes trois hypothèses étaient : capacité existante **mal nommée** · capacité existante **hors
ORDER** · exigence **sans producteur de preuve**. La mesure en donne une quatrième, et plus
précise : **il existe DEUX capacités visuelles distinctes, et aucune ne produit quoi que ce soit
pour ces 79 feuilles — pour deux raisons différentes.**

### (A) `product_oracle.check_visual_capture` — volet 3c : **existante ET câblée**
```
driver.py:79    from forge.product_oracle import run_product_oracle
driver.py:395   self.product_oracle_runner = product_oracle_runner or run_product_oracle
product_oracle.py:463  def check_visual_capture(...)
    « APPELLE capture_browser.mjs et capture_godot.mjs (existants, jamais réimplémentées) »
```
Elle est dans la chaîne. **Mais son producteur est côté JEU** :
`<jeu>/06_RUNTIME/adapters/presentation/capture_browser.mjs` (ou `capture_godot.mjs`).

```
jeux du dépôt portant un adaptateur de capture :   pong   (2 fichiers)  — et lui seul
jeux portant des feuilles `visual` (8 runs)    :   0 sur 8 en portent un
   chain_probe_v1 · p1_beta · p1_beta_E1 · p2_alpha · p2_beta · p3_alpha · pacman · tower_defense_sonde
```

> **Le volet existe, il est appelé, et il n'a rien à appeler.** C'est le motif *« validateur sans
> producteur »* (ratifié 2026-07-30) — **inversé** : ici le validateur est câblé, et c'est le
> producteur, côté jeu, qui n'est jamais fabriqué. Le seul jeu qui porte un adaptateur, `pong`, ne
> déclare **aucune** feuille `visual`.

### (B) `s10d-oracle-visual` + `scripts/quality_sensor/` — existante, **hors ORDER, 0 appelant**
```
scripts/quality_sensor/   collect.mjs · sensor.mjs · analysis.mjs (+ tests)
appelants hors du dossier lui-même :  0
```
Le contrat le dit lui-même, verbatim : *« cette étape est **HORS chaîne de promotion** (absente de
CHAIN/ORDER, non câblée au driver). Aucun test de chaîne ne la couvre. »*
Et sa base probante, telle que ratifiée : *« familles A1/A2/A3/A5 prouvées sur défauts
**SYNTHÉTIQUES**, sur **Breakout uniquement**, **sans généralisation** »*, seuils v0 figés.

> **Deux capacités visuelles coexistent sans se connaître.** L'une est branchée et sans producteur ;
> l'autre a un producteur et n'est branchée nulle part.

### Où vivent les 79
```
JS / HTML  68        chain_probe_v1 12 · p1_beta 12 · p1_beta_E1 12 · p2_alpha 8 · p2_beta 9 · p3_alpha 8 · tower_defense_sonde 7
Godot      11        pacman
```
**86 % des attentes visuelles portent sur des jeux web.** La chaîne de capture GPU Godot — prouvée
fonctionnelle en 2026-08-10 — ne concernerait que **11** d'entre elles. Traiter `visual` comme un
sujet Godot serait une erreur de population.

---

## 3 · Ce que J-4 permet de fermer dans J-5 — et ce qu'il ne permet pas

Ton modèle : `kind → famille → reçu → reçu observable pour CE run → actual_proof`.

```
bot_action  80   famille ✔  reçu ✔  observable ✔      → rattachable
oracle      74   famille ✔  reçu ✔  observable ✔      → rattachable
mutation     7   famille ✔  reçu ✔  observable ✔      → rattachable
visual      79   famille ✔(3c) reçu ✘  observable ✘   → NON rattachable
─────────────────────────────────────────────────────────────────────
161 / 240 rattachables (67 %)   ·   79 restent sans reçu possible
```

Et le rappel que tu as posé, qui reste vrai des 161 : **un reçu par famille et par run ne prouve
pas individuellement une feuille.** Il autorise un *rattachement*, pas une attribution. Prétendre
l'inverse fabriquerait 161 preuves à partir de 4 reçus.

---

## 4 · Trois décisions

| # | question | mon avis |
|---|---|---|
| **V-1** | **`visual` reste-t-il un `kind` déclarable ?** | **oui.** 79 attentes réelles ne deviennent pas fausses parce que la chaîne ne sait pas les honorer. Les supprimer effacerait le constat au lieu de le traiter — et le constat est précieux : *79 exigences déclarées ont un type de preuve dont la chaîne d'exécution n'est pas établie* |
| **V-2** | **Que fait-on du volet 3c sans producteur ?** | **le nommer, pas le réparer maintenant.** Le manque est un **artefact de jeu** (`capture_browser.mjs`), pas un oracle à écrire. Exiger cet adaptateur relèverait du contrat de build — décision distincte, et il faudrait d'abord vérifier sur `pong` que le volet rend quelque chose d'utile |
| **V-3** | **Que fait-on de `s10d` / `quality_sensor` ?** | **ne pas le brancher.** Sa base probante est explicitement non généralisable (Breakout, défauts synthétiques). Le brancher pour « avoir une famille visuelle » serait exactement la famille artificielle que tu refuses. Le laisser hors ORDER, et le dire dans le contrat |

### Conséquence pour J-5
J-5 peut se fermer **partiellement** : le rattachement `kind → famille → reçu` est ratifiable pour
**161 feuilles sur 240**. Les 79 `visual` restent **`NOT_MEASURED`** — un état honnête, pas un
échec — jusqu'à une décision séparée sur l'adaptateur de capture côté jeu.
**`actual_proof` reste non constructible en tant que preuve par feuille.**

```
status_by_surface:
  kind_to_family_table:      TESTED   # 4 kinds, 240 feuilles
  three_families_wired:      TESTED   # bot_action · oracle · mutation → reçus réels
  visual_3c_wired:           TESTED   # driver.py:79/395, product_oracle.py:463
  visual_producer_absent:    TESTED   # 1 jeu porte un capture_*.mjs (pong) ; 0 des 8 concernés
  s10d_out_of_order:         TESTED   # 0 appelant ; contrat le déclare hors chaîne
  visual_population_is_web:  TESTED   # 68 web / 11 godot
  attachable_ratio:          TESTED   # 161 / 240
  V1_V2_V3:                  BLOCKED  # arbitrage Pierre
  implementation:            BLOCKED
```
`software_verdict: OK` (mesure) · `evidence_verdict: MECHANICAL_VALIDATION_ONLY` ·
`claim_verdict: NO_CLAIM_ALLOWED` · `no_global_ready_verdict: true`

**Q2 / R8 : non touchée.** Aucune famille créée, aucun run réparé, aucun advisory transformé en gate.

---

## 5 · DÉCISION J-4 — ratifiée Pierre, 2026-09-02

```
V-1  RATIFIÉ      `visual` reste un expected_proof.kind légitime
                  on ne corrige pas le modèle en supprimant l'exigence
V-2  REFORMULÉ    vérifier la VALEUR PROBANTE réelle du volet 3c sur `pong`,
                  READ-ONLY, sans modifier le pipeline — AVANT toute fabrication
                  d'adaptateurs côté jeux
V-3  RATIFIÉ      ne pas brancher s10d / quality_sensor
```

### Pourquoi V-2 passe par `pong` d'abord — la raison, telle que posée
> *« Si le consommateur branché (`check_visual_capture`) ne produit pas une observation
> suffisamment déterministe/exploitable, fabriquer son producteur partout ne ferait que déplacer
> le problème. »*

Si le volet est probant, la construction est **côté jeu** (`GAME_BUILD → capture_browser.mjs →
check_visual_capture → receipt visual`), **jamais une nouvelle famille d'oracle**.

### Ce que V-3 empêche, nommément
La tentation naturelle était : *« il manque `visual` dans l'ORDER, donc ajoutons `s10d` »*. J-4
fournit la preuve contraire : on aurait branché une capacité dont la base expérimentale se limite à
des défauts **synthétiques** sur **Breakout**, alors que **68 des 79** attentes `visual` portent sur
des jeux **web**. **Réparation cosmétique du graphe, refusée.**

### Le caveat conservé, mot pour mot
> **rattachable ≠ prouvé.** Un reçu de famille ne permet pas de fabriquer 161 `actual_proof`
> individuels. **`actual_proof` n'est pas la prochaine construction.**

Il manque la granularité qui répondrait à : *« ce reçu de famille prouve quoi, exactement, parmi
les feuilles couvertes ? »* — et c'est là que J-3 devient central : **240 feuilles adressables**,
pas 360 lignes.

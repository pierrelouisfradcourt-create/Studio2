# Lot 6 — Le contrat de re-convocation : identité de section et acquittement structuré

*Spec validée par Pierre le 2026-09-04 (4 corrections intégrées). V2 `C:\Users\Studio-Dev\Desktop\Studio2`,
HEAD au moment de la rédaction : `bc23133` (Lot 5). Aucun code écrit avant le plan. NO_CLAIM_ALLOWED.*

## 1. Le problème, établi par le Lot 5

Deux défauts mesurés sur le dépôt, pas supposés.

**Les identifiants d'une section ne survivent pas à une re-convocation.** Trois convocations réelles de
`decompose` sur le même projet ont produit trois schémas d'identité :

| run | ids de `capacites[].id` |
|---|---|
| `runm_breakout` (baseline) | `R1c1_hud_objectif_nonvide` … `R9c1_window_game_expose` |
| `lot2_decompose_probe` | `R1` … `R10` |
| `lot5_transport_probe` | `CAP_objectif_hud` … `CAP_window_game` |

La `wiremap` cite ces ids dans `features[].couvre[]` (baseline : les dix ids longs). Un renommage en amont
transforme donc une jointure JOINED en VOID avec dix fantômes, sans qu'aucun mécanisme ne l'empêche ni ne
désigne le responsable. Rien ne contraint la stabilité : le contrat `s3-decompo` n'en parle pas, la tâche
par défaut dit « features numérotées R1..Rn » (`run_real.py:3644`), et la capacité ne relit jamais sa propre
production. Pire, `director.diagnose_join` impute toute anomalie de jointure à `wiremap` (`director.py:219-231`),
alors que la cause peut être un renommage par `decompose`.

**L'acquittement d'une objection n'est pas mesuré.** `director._consumption` cherche la sous-chaîne de l'id du
message dans l'artefact et la restitution (`consumption._contains_ref`). Résultats réels :

| décision | capacité | statut | fichiers vérifiés |
|---|---|---|---|
| `D-v2_breakout_slice_r1-4` | wiremap | `consumed` | trouvé dans `s5-wiremap.txt` (prose) |
| `D-v2_breakout_slice_r1-8` et `-9` | builder | `not_consumed` | `[]` — aucun fichier vérifiable |
| `D-lot3_director_probe-2` | wiremap | `not_consumed` | `None` |

Citer un identifiant dans sa prose ne prouve pas qu'on a corrigé quoi que ce soit, et une capacité n'a aucun
moyen formel de contester une objection fausse.

**Racine commune** : la re-convocation n'a pas de contrat. Une capacité rappelée ne reçoit ni sa production
précédente ni un canal de réponse.

## 2. Ce que le Lot 6 construit

Deux contrats déterministes, deux modules neufs et petits, branchés dans `invoke_capability` et lus par le
Director.

```
Lot 6
├── Contrat de re-convocation           (le cadre : une capacité rappelée relit et répond)
├── Contrat d'identité   → forge/identity.py
│   ├── production précédente injectée au prompt
│   ├── clé d'identité canonique par section (registre)
│   ├── comparaison kept / added / retired
│   ├── contrôle des références AVAL (y compris sur un retrait déclaré)
│   └── refus d'écriture ciblé
├── Contrat d'acquittement → forge/acknowledgement.py
│   ├── fence dédiée ```acquittement```
│   ├── validation message / run / capacité
│   ├── applied · partial · rejected
│   ├── effet mesuré (applied sans effet ⇒ claimed_without_effect)
│   └── non-acquittement explicite
└── Preuve : tests déterministes + UNE re-convocation réelle de decompose
```

**Hors périmètre, déclaré** : aucun nouvel état du Director, aucune modification des oracles ni du verdict,
aucune infrastructure nouvelle. La preuve `main.tscn` exigée par `check_decompo.mjs` même pour un jeu web
(trouvée par la sonde du Lot 5) reste un problème de lignée, traité séparément.

## 3. Contrat d'identité

### 3.1 Déclaration au registre

Chaque section écrite par une capacité gagne un bloc `identity` dans `forge/capability_registry.yaml`,
au niveau de la section (pas de la capacité — une section a UNE identité, quel que soit son écrivain) :

```yaml
identity:
  feature_map:
    key: "systemes[].features[].capacites[].id"
    referenced_by:
      - {section: "wiremap.design", path: "features[].couvre[]"}
      - {section: "wiremap.built",  path: "features[].couvre[]"}
  architecture_contract:
    key: "modules[]"
    referenced_by:
      # référence INTRA-section : deps_interdites cite des noms de modules par paires
      - {section: "architecture_contract", path: "deps_interdites[][]"}
  wiremap.design:
    key: UNKNOWN               # cf. 3.2 — mesuré par le Lot 6, jamais deviné
    referenced_by: []
```

**Principe : une section, UNE clé d'identité canonique.** Pas deux clés possibles.

### 3.2 Mesure préalable obligatoire (`wiremap`)

La clé d'identité de `wiremap.design` est **UNKNOWN** et doit être établie par mesure avant d'être déclarée.
Le dépôt porte deux formes acceptées en production :

- `_validate_wiremap` (`run_real.py:1160`) : `features[]` avec `feature`, `fonction`, `fichiers`, `preuve` ;
- `_validate_wiremap_v2` (`run_real.py:1197`, `schema_version == 2`) : `lines[]` avec `id`, `fichiers`, `couvre`.

La baseline `runm_breakout/wiremap.json` utilise la forme `features[]`. Le Lot 6 lit le contrat `s5-wiremap`,
les deux validateurs et `check_wiremap_contract.mjs` pour déterminer quelle clé est réellement l'identité
stable — et si la réponse diffère selon `schema_version`, c'est un constat à écrire, pas à masquer. Tant que
la mesure n'a pas tranché, `wiremap.design.key` reste `UNKNOWN` et le contrat d'identité ne s'applique pas à
cette section : un `UNKNOWN` honnête vaut mieux qu'une clé devinée.

### 3.3 Production précédente injectée

Quand `invoke_capability` est appelée avec `attempt > 1` sur une section déjà écrite par cette capacité, le
prompt reçoit, après les sections lues et avant le pré-mortem :

```
## TA PRODUCTION PRÉCÉDENTE — <section> v<N> (content_sha256=<sha>)
```json
{ … contenu de la section … }
```
RÈGLE D'IDENTITÉ : les identifiants de cette section sont cités en aval. Conserve chaque `<key>` à
l'identique — ne renomme jamais. Une entrée qui doit disparaître se déclare dans
`identity.retired: [{"id": "<id>", "reason": "<pourquoi>"}]` à la racine de ton artefact, et seulement si
plus rien en aval ne la cite. Ajouter de nouvelles entrées est libre.
```

Le bloc est tronqué par `_truncate_preserve_terminal_json` au-delà de `UPSTREAM_MAX_CHARS`, comme les sections
lues.

`identity.retired` est une clé de premier niveau de l'artefact. Les validateurs de production la tolèrent
(`_validate_featuremap` ne contrôle que `systemes`), et elle est **conservée** dans l'artefact comme dans la
section écrite : la déclaration de retrait appartient à la production qui la fait. `extract_ids` ne parcourt
que le chemin de la clé d'identité et ne la confond donc jamais avec une entrée.

### 3.4 Vérification avant écriture

`identity.compare(before, after, key, downstream_refs)` rend un rapport déterministe :

```python
{"kept": [...], "added": [...], "retired_declared": [...], "dropped": [...],
 "renamed_suspected": [...],          # dropped ∧ added de cardinalité égale — informatif, jamais un verdict
 "referenced_dropped": [...]}         # ids disparus ET encore cités en aval
```

**Règle de refus (correction 1 de Pierre)** : un identifiant absent de la nouvelle version est accepté
**seulement si** il est déclaré dans `identity.retired` **et** qu'aucune référence aval ne le cite encore.
Un retrait déclaré mais toujours référencé est refusé au même titre qu'un renommage implicite — sinon on
transforme simplement un renommage silencieux en suppression déclarée.

| cas | résultat |
|---|---|
| id conservé | `kept`, écriture autorisée |
| id nouveau | `added`, écriture autorisée |
| id absent, déclaré `retired`, plus aucune référence aval | `retired_declared`, écriture autorisée |
| id absent, déclaré `retired`, **référence aval présente** | `referenced_dropped` ⇒ **refus** |
| id absent, non déclaré, référence aval présente | `referenced_dropped` ⇒ **refus** |
| id absent, non déclaré, aucune référence aval | `dropped` ⇒ écriture autorisée, rapport conservé |

Un refus produit un problème K7 `ID_REFERENCED_DROPPED`, producteur `identity_check`, `path` = la section,
`suggested_action` = `reconvoke`. La section du Blueprint reste **intacte** (aucune écriture), l'artefact
matérialisé reste sur disque pour inspection, le spawn_link est écrit en `HALTED`. Le rapport d'identité
entre dans `result["identity"]` et dans la mesure de la décision du Director.

### 3.5 Réaction du Director

Sur `ID_REFERENCED_DROPPED`, le Director objecte **à l'écrivain de la section** (pas à `wiremap` par défaut) :
la responsabilité vient du `path` du problème, pas de `diagnose_join`. Le message liste les identifiants à
conserver et leurs références aval. La re-convocation qui suit reçoit la production précédente (3.3) et le
message (contrat 2). Les compteurs existants `no_effect` / `no_progress` bornent la boucle ; aucun nouvel
état n'est introduit.

### 3.6 Libellé de tâche

`default_task_by_step` pour `s3-decompo` dit aujourd'hui « features numérotées R1..Rn », ce qui invite au
renommage à chaque convocation. Le libellé devient : identifiants **stables et lisibles**, conservés d'une
convocation à l'autre. C'est une correction de cause, pas un ajout de règle.

## 4. Contrat d'acquittement

### 4.1 Forme

Toute capacité qui reçoit un message du Director termine sa restitution par un bloc dédié — dernier bloc
seul, même extraction que la fence `design_questions` (`run_real.py:1953-1994`) :

````
```acquittement
{"message_id": "AMD-…", "action": "applied", "changes": ["…"], "reason": "…"}
```
````

`action` ∈ `applied` · `partial` · `rejected`. `changes` : liste des modifications réellement faites
(vide si `rejected`). `reason` : obligatoire pour `partial` et `rejected`.

Le bloc MESSAGE DU DIRECTOR (`director.py:570-571`) dicte ce format au lieu de « cite l'identifiant ».

### 4.2 Jugement mécanique

`acknowledgement.judge(block, message, capability, run_id, effect)` rend un statut, jamais un jugement de
valeur :

| statut | condition |
|---|---|
| `acknowledged` | `message_id` valide (message ouvert, adressé à cette capacité, ce run) et `action` ∈ {`applied`, `partial`} avec effet mesuré ≠ `NO_EFFECT` |
| `claimed_without_effect` | `action` = `applied` mais l'effet mesuré par le Director est `NO_EFFECT` |
| `rejected` | `action` = `rejected` avec `reason` non vide |
| `unknown_message` | `message_id` inconnu, clos, adressé à une autre capacité ou à un autre run |
| `not_acknowledged` | aucun bloc, bloc illisible, ou `action` hors énumération |

**Un message ne peut être acquitté qu'une fois** : un second acquittement du même `message_id` dans le même
run est refusé en `unknown_message` (le message n'est plus ouvert). C'est la même discipline append-only que
le journal d'amendements, qui refuse déjà un `id` en double.

La recherche de sous-chaîne (`consumption._contains_ref`) disparaît du chemin d'acquittement. Le module
`consumption` n'est pas modifié : il garde ses autres usages.

### 4.3 Le désaccord (correction 3 de Pierre)

`rejected` ne devient pas directement une question. Il produit **deux objets distincts**, dans cet ordre :

1. **un désaccord structuré** : un message de type `objection` au journal, `from: <capacité>`,
   `to: ["director"]`, `in_reply_to: <message_id>`, `run_id: <run>`, portant la `reason` de la capacité.
   Le type `objection` existe déjà (`amendment_log.MESSAGE_TYPES`) ; seul le sens de circulation change.
2. **une question ouverte** : une entrée append-only dans la section `questions` du Blueprint, référençant
   l'id du désaccord, `blocking: false`, `to: ["director", "pierre"]`.

Trois choses restent ainsi distinguables pour l'arbitrage futur : la question initiale, l'objection du
Director, et la réponse négative de la capacité.

## 5. Interfaces

```python
# forge/identity.py
load_identity(path=None) -> dict                      # bloc `identity` du registre
identity_of(section: str, registry_doc=None) -> dict | None   # {key, referenced_by} ; None si UNKNOWN
extract_ids(content, key: str) -> list[str]           # navigation "a[].b[].c" déterministe
downstream_ids(blueprint: dict, refs: list[dict]) -> set[str]
compare(before, after, *, key, downstream: set[str], retired: list[dict]) -> dict
ID_REFERENCED_DROPPED = "ID_REFERENCED_DROPPED"

# forge/acknowledgement.py
extract_block(output: str) -> tuple[dict | None, str]  # dernier fence ```acquittement```
judge(block, *, message, capability, run_id, effect, already_acknowledged: set[str]) -> dict
disagreement_message(block, *, capability, run_id, message) -> dict   # objection inverse
question_entry(block, *, capability, run_id, disagreement_id) -> dict # entrée `questions`
ACKNOWLEDGED = "acknowledged" ; CLAIMED_WITHOUT_EFFECT = "claimed_without_effect"
REJECTED = "rejected" ; UNKNOWN_MESSAGE = "unknown_message" ; NOT_ACKNOWLEDGED = "not_acknowledged"
```

**Répartition des rôles, sans ambiguïté.** `invoke_capability` ne gagne **aucun paramètre** : elle tient déjà
le Blueprint et connaît `sp["writes"]`, donc elle dérive elle-même la production précédente
(`blueprint["sections"][<section>]`, si `version > 0`). C'est délibéré : la version comparée par
`identity.compare` est exactement celle qui sera écrasée, jamais une copie transmise par un tiers — une seule
source de vérité. Elle **applique** le contrat d'identité (elle seule est au point d'écriture) et **extrait**
le bloc d'acquittement, puis rend `result["identity"]` (rapport) et `result["acknowledgement_block"]`
(bloc extrait ou `None`, avec son diagnostic d'extraction).

Elle ne **juge** jamais l'acquittement : le statut dépend de l'effet mesuré, que seul le Director connaît.
Le Director appelle `judge` après `effect_of`, écrit le statut dans la mesure de sa décision, et fournit
`already_acknowledged` depuis son propre état (`director_state.json`, les `message_id` déjà acquittés dans
ce run). Le Director n'a donc rien de neuf à transmettre en entrée : il lit deux champs de plus en sortie.

## 6. Preuve

**Tests déterministes** (`forge/tests/test_reconvocation_lot6.py`), sur la forme de production réelle
(Blueprint importé de la baseline, sorties réelles d'agents, aucun appel LLM) :

- identité : les trois schémas d'ids réellement observés sont extraits correctement ; un renommage cité en
  aval est refusé, la section reste intacte ; un retrait déclaré sans référence aval est accepté ; un retrait
  déclaré **encore cité** est refusé (correction 1) ; un ajout est libre ; `wiremap.design` en `UNKNOWN`
  n'applique aucune règle ;
- acquittement : les **cinq** statuts (`acknowledged`, `claimed_without_effect`, `rejected`,
  `unknown_message`, `not_acknowledged`) ; un **second acquittement du même message est refusé** ;
  `rejected` produit un désaccord au journal **et** une question dans le Blueprint, distincts de l'objection
  du Director ;
- Director : sur `ID_REFERENCED_DROPPED`, l'objection va à l'écrivain de la section ; la re-convocation
  reçoit la production précédente et le message ; la boucle reste bornée par les compteurs existants.

**Une re-convocation réelle** de `decompose` sur le Blueprint du Lot 5 (`GAME_BLUEPRINT.lot5_probe.json`,
`feature_map` v3, ids `CAP_*`), avec objection d'identité : les ids doivent être conservés et le bloc
d'acquittement présent. Coût attendu de l'ordre de 1,6 $. Preuve déposée sous
`EVIDENCE/runs/lot6_identity_probe/` et `EVIDENCE/reports/lot6_reconvocation/`.

**Régression** : suites des Lots 2 à 5 vertes, T0 complet inchangé (2 511 verts / 42 échecs, population V1
classée au Lot 0).

## 7. Ce que ce lot ne prouve pas

- La qualité des identifiants choisis par l'agent : le contrat impose la stabilité, jamais la pertinence.
- Que `rejected` ait raison : le désaccord est transporté et arbitré par Pierre, jamais tranché par un
  mécanisme.
- L'identité de `wiremap.design` tant que la mesure 3.2 n'a pas tranché.
- La preuve `main.tscn` de `check_decompo.mjs` : hors périmètre, déclarée au registre.

```
software_verdict: OK · evidence_verdict: MECHANICAL_VALIDATION_ONLY · claim_verdict: NO_CLAIM_ALLOWED
no_global_ready_verdict: true
```

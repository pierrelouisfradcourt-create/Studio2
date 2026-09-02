# J-5 — `preuve` DÉCLARÉE → REÇU RÉELLEMENT OBSERVÉ

*2026-09-02 · **MESURE UNIQUEMENT** · aucun code, aucun fichier du dépôt source modifié.
HEAD `feeb29cb`. Population : les **12 runs** portant featuremap + wiremap, **360 lignes**.
Unité de référence : la **feuille** (J-3, U-1 ratifiée).*

---

## 0 · Ce qui vérifie `preuve` aujourd'hui — et ce que ça vérifie vraiment

`static_oracles.check_wiremap` (étape **s10c**, dans l'`ORDER`, et son `passed` décide le statut du
pas — c'est un **gate dur**) fait exactement deux choses sur `preuve` :

```python
preuve_str = str(feat.get("preuve", ""))
if not preuve_str.strip():
    preuves_absentes.append(name)          # (1) le champ est-il NON VIDE ?
else:
    for tok in _PREUVE_GD.findall(preuve_str):   # (2) les fichiers cités existent-ils ?
        ...
_PREUVE_GD = re.compile(r"[\w./-]+\.gd\b")       #     ... uniquement s'ils finissent en .gd
```

> **(1) est universel et dur : une prose non vide suffit.**
> **(2) ne s'applique qu'à un seul langage.**

---

## 1 · La mesure qui tranche — 656 fichiers cités par `preuve`

| extension | vérifiée par `_PREUVE_GD` | existe dans `games/<run>/` | n |
|---|---|---|---|
| `.gd` | **oui** | oui | **258** |
| `.gd` | oui | non | **0** |
| `.mjs` | **non** | oui | 221 |
| `.mjs` | **non** | **non** | **92** |
| `.json` | non | oui | 66 |
| `.html` | non | oui / non | 8 / 2 |
| `.md` | non | **non** | 7 |
| `.js` · `.tscn` | non | non / oui | 1 / 1 |

```
vérifiés (.gd)   258   dont introuvables :   0
JAMAIS vérifiés  398   dont introuvables : 102     (26 %)
```

> **Là où la vérification s'applique, la donnée est parfaite : 0 fichier manquant sur 258.**
> **Là où elle ne s'applique pas, un quart des citations désignent des fichiers qui n'existent pas.**

Ce n'est pas une vérification fausse. C'est une vérification **bornée à un langage**, et personne
n'avait mesuré la borne. `godot_oracle.mjs` est cité **66 fois** et n'existe nulle part.

---

## 2 · Le fond : `preuve` ne peut pas citer son reçu, parce qu'aucun reçu n'existe à sa granularité

```
verdict.json → oracles : { archi · code · standard · wiremap }        4 reçus PAR RUN
   chacun : {oracle_id, run_id, status, evidence_path, evidence_sha256, detail, ts}
   detail.e2e             {passed, raisons}
   detail.mutation        {receipt, signature}
   detail.oracle_measures {mecanique, solvabilite}
```

**Aucun identifiant de feuille, aucun identifiant de ligne, nulle part.** Les reçus sont par
**famille d'oracle**, jamais par capacité.

```
240 feuilles adressables  ·  360 lignes  ·  4 reçus par run
```

> Demander à une ligne de « citer le reçu qui l'établit » est aujourd'hui **impossible** : l'objet
> à citer n'existe pas. `preuve` reste donc structurellement une **allégation** — non pas par
> négligence d'agent, mais parce que la chaîne ne produit rien de plus fin qu'un reçu par famille.

Et ce que le gate dur exige — une prose non vide — **est satisfait par n'importe quelle phrase.**
Les 96 lignes à `preuve` vide relevées sur l'ensemble des wiremaps du dépôt ne sont pas dans cette
population de 12 runs : ici, **0 ligne vide sur 360**. Le champ est toujours rempli. Il n'est
presque jamais vérifiable.

---

## 3 · Trois décisions

| # | question | mesure à l'appui | mon avis |
|---|---|---|---|
| **P-1** | **Étendre la vérification d'existence au-delà de `.gd` ?** | 398 tokens non vérifiés, **102 introuvables** ; l'extension réutilise l'oracle existant, aucun composant neuf | **oui — mais ADVISORY d'abord.** `check_wiremap.passed` est un **gate dur** : étendre le motif transformerait 102 constats en échecs durs du jour au lendemain, sur des runs qu'on a décidé de ne pas réparer. Mesurer, publier le chiffre, puis décider du gate — c'est le chemin 2026-07-26, et N-2 en a payé le prix inverse |
| **P-2** | **Une ligne doit-elle citer le reçu qui l'établit ?** | impossible en l'état : 4 reçus par run, 0 identifiant de feuille ou de ligne | **pas sous cette forme.** Créer un reçu par ligne (360) serait un composant neuf lourd, contraire à la règle anti-couches. **Le lien réaliste est par FAMILLE** : `expected_proof.kind` (feuille) → famille d'oracle → reçu du run. Il existe déjà des deux côtés — il n'est simplement jamais rapproché. **Mais il bute sur `kind: visual`, qui n'a aucune famille : c'est J-4.** |
| **P-3** | **`preuve` non vide comme gate dur : on garde ?** | universel, dur, satisfait par n'importe quelle phrase | **garder, sans lui prêter de vertu.** Il empêche le champ vide, rien d'autre. Le nommer honnêtement dans le contrat évite qu'un `passed` s'y lise comme une preuve vérifiée |

### La conséquence de P-2, à énoncer clairement
> **J-5 ne peut pas se refermer avant J-4.** Le seul lien praticable entre une preuve attendue et un
> reçu réel passe par `expected_proof.kind` — et **79 feuilles sur 240 déclarent `visual`**, un
> `kind` auquel aucune famille d'oracle ne répond dans l'`ORDER`. Ton ordre J-5 → J-4 tient pour la
> **mesure** ; pour la **fermeture**, J-4 est un préalable, pas une suite.

### Ce que J-5 ne fait pas
Aucun code · ne répare aucun run · ne touche pas `_PREUVE_GD` · ne transforme aucun advisory en
gate · ne crée aucun reçu.

```
status_by_surface:
  preuve_check_is_hard_gate:  TESTED   # static_oracles.check_wiremap.passed, s10c dans l'ORDER
  check_scope_is_one_language:TESTED   # _PREUVE_GD = r"[\w./-]+\.gd\b"
  656_tokens_measured:        TESTED   # 258 vérifiés (0 manquant) · 398 non vérifiés (102 manquants)
  receipts_granularity:       TESTED   # 4 reçus/run, 0 identifiant de feuille ou de ligne
  line_cannot_cite_receipt:   TESTED   # l'objet à citer n'existe pas
  kind_to_family_link:        NOT_FOUND # existe des deux côtés, jamais rapproché
  P1_P2_P3:                   BLOCKED   # arbitrage Pierre
  implementation:             BLOCKED
```
`software_verdict: OK` (mesure) · `evidence_verdict: MECHANICAL_VALIDATION_ONLY` ·
`claim_verdict: NO_CLAIM_ALLOWED` · `no_global_ready_verdict: true`

**Q2 / R8 : non touchée.**

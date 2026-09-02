# Asset Learning Loop V1

> **Date** : 2026-08-06 (spec) · **mise à jour le même jour : IMPLÉMENTÉE**
> **Statut** : `analyze_batch.py` existe, consomme réellement les `generation_report.json`,
> et ses leçons ratifiées contraignent le dispatcher. 17 tests.
> **Reste hors mécanique** : le cycle `APPLIED` / `REFUTED` (§ *Ce qui reste à construire*).
> `claim_verdict: NO_CLAIM_ALLOWED`

## Le trou que cette boucle ferme

`generation_report.json` est écrit à chaque asset produit (6 fichiers existent aujourd'hui
dans `knowledge_base/assets/props3d/`). **Personne ne le relit.** Chaque lot repart donc de
zéro : rien ne rend un lot différent du précédent autrement que par la main qui écrit les
specs.

La boucle manquante :

```
generation_report (n)  ──┐
verdicts oracle (n)    ──┼──►  analyse de lot  ──►  asset_lesson  ──►  spec du lot (n+1)
manifestes HumanGate   ──┘                              │
                                                        └──►  vérification au lot (n+1)
```

Question à laquelle la boucle doit savoir répondre, et qu'aucun mécanisme ne peut
répondre aujourd'hui :

> **« Pourquoi le prochain lot est différent du précédent ? »**

## Ce qui existe déjà et n'a pas à être refait

| brique | état | rôle dans la boucle |
|---|---|---|
| `generation_report.json` | **écrit** par `build_asset.py` | entrée : paramètres et objets produits |
| rapport d'oracle (`ASSET_GEOMETRY_REPORT`) | **produit** par `oracle.py` | entrée : défauts mesurés |
| `<asset>.glb.geometry.json` | **écrit** au HumanGate | entrée : ce qu'un humain a dû expliquer |
| `kb.proposal.v1` | **écrit** par `propose_asset.py` | entrée : ce qui a été ratifié ou refusé |
| `asset_lesson.schema.json` | **spécifié seulement** | sortie de l'analyse de lot |
| analyse de lot | **absent** | ← la seule pièce à construire |

## Le schéma `asset_lesson`

Défini dans `scripts/forge/asset_producer/asset_lesson.schema.json`. Six champs portants :

`asset_type` · `generation` · `defauts_detectes` · `cause_racine` · `correction_recommandee`
· `impact_prochain_lot`

Trois choix qui ne sont pas cosmétiques :

1. **`cause_racine.couche`** est une énumération fermée
   (`spec` · `producteur` · `oracle` · `manifeste` · `kb` · `runtime`). Distinguer
   `producteur` et `oracle` est le cœur : un lot qui bloque peut signaler un producteur
   fautif **ou** un oracle mal réglé. Confondre les deux mène à desserrer un seuil pour
   faire passer un lot — la panne la plus probable de cette boucle.
2. **`impact_prochain_lot.attendu`** s'écrit **avant** le lot suivant. Sinon la leçon se
   confirme toujours après coup.
3. **`status: REFUTED`** est un état **normal**. Une leçon qui ne peut pas être réfutée
   n'apprend rien.

## Leçon de référence — tirée du lot réel du 2026-08-06

Elle n'est pas inventée : elle décrit ce qui s'est réellement passé, et sert de gabarit.

```json
{
  "schema_version": "1.0",
  "lesson_id": "asset.variantes_exclusives_non_declarees",
  "batch_id": "props3d-2026-08-06",
  "asset_type": "chest",
  "generation": 1,
  "defauts_detectes": [{
    "oracle": "scripts/forge/asset_geometry/oracle.py",
    "check": "all_meshes_declared",
    "verdict": "BLOCKED",
    "assets": ["gen_chest_01"],
    "detail": "2 etats de couvercle mutuellement exclusifs, aucun role declare"
  }],
  "cause_racine": {
    "couche": "oracle",
    "enonce": "La branche 'part de sommets >= 10%' classait MAIN automatiquement les 2 etats (33% chacun). Le defaut n'etait pas dans le producteur : il etait dans le seuil, aveugle aux variantes des lors qu'un asset a peu de meshes."
  },
  "correction_recommandee": {
    "cible": "oracle.py — asymetrie de la declaration",
    "action": "Une variante annoncee par le producteur perd le droit au classement MAIN automatique.",
    "interdit": "Abaisser main_share_threshold : le seuil protege tous les assets, pas seulement celui-ci."
  },
  "impact_prochain_lot": {
    "change": "Tout asset multi-etats bloquera tant qu'un humain n'aura pas declare les roles.",
    "verification": "Rejouer le lot : gen_chest_01 BLOCKED, les 5 autres OK.",
    "attendu": "1 BLOCKED / 5 OK"
  },
  "status": "APPLIED"
}
```

Résultat effectivement observé après correction : **1 `BLOCKED`, 5 `OK`** — conforme à
`attendu`. C'est ce qui rend le lot 2 différent du lot 1.

## État réel de la boucle

| étape | état | où |
|---|---|---|
| 1. analyse de lot → `asset_lesson` en `CANDIDATE` | **FAIT** | `analyze_batch.py` |
| 2. ratification HumanGate `CANDIDATE → VALIDATED` | **FAIT** | `--valider … --par` **ou** proposition `kb.proposal.v1` |
| 3. la leçon devient une contrainte sur le lot suivant | **FAIT** | `batch_constraints.json` → `asset_dispatch.check_batch_constraints()` |
| 4. vérification de `attendu` → `APPLIED` / `REFUTED` | **FAIT** | `verify_lesson()` / `--classer` |

### Les cinq statuts

| statut | sens | contraint le lot suivant ? |
|---|---|---|
| `CANDIDATE` | dérivée d'un lot, **aucune ratification humaine** | non |
| `VALIDATED` | ratifiée, effet pas encore mesuré | **oui** |
| `APPLIED` | ratifiée **et** effet mesuré conforme à `attendu` | **oui** — la retirer rouvrirait le défaut |
| `REFUTED` | des runs pertinents existent, l'effet ne s'est **pas** produit | non — la contrainte tombe |
| `INSUFFICIENT_DATA` | aucun run pertinent depuis la ratification | statut de mesure, pas de leçon |

`INSUFFICIENT_DATA` est un verdict à part entière : confondre « pas encore vérifié » avec
« réfuté » ferait mentir la boucle dans les deux sens.

### Deux garde-fous non négociables

1. **`validated_at_ts`** — seuls les runs **postérieurs** à la ratification comptent. Sans
   cet horodatage, une leçon se confirmerait rétroactivement sur les runs qui l'ont
   motivée.
2. **`REFUTED` est un état normal.** Une leçon qui ne peut pas être réfutée n'apprend
   rien. La contre-épreuve est testée : un run qui *échappe* à la contrainte réfute la
   leçon et retire son effet.

### La ratification passe par la porte commune

`--proposer <lesson_id>` dépose la leçon comme **`kb.proposal.v1`**, dans
`knowledge_base/proposals/`, exactement comme une ingestion d'asset. Même schéma, même
répertoire, même geste :

```
python -m scripts.forge.kb_proposal --apply lesson.<id> --ratifie-par "<humain>"
```

Une leçon qui contraint la production mérite la même autorité qu'une entrée de
bibliothèque : un seul endroit où un humain signe.

## Une signature humaine ne se simule jamais

**Règle ratifiée Pierre, 2026-08-06, née d'un incident réel dans cette session.**

Pour démontrer que la boucle changeait bien le lot suivant, une leçon a été validée
`--par "Pierre (demo)"` — une signature qu'il n'avait pas donnée. La ratification a été
**retirée** (leçon repassée en `CANDIDATE`, contraintes recalculées à vide) et le geste
rendu **mécaniquement impossible** : `valider()` refuse tout signataire portant un
marqueur de simulation (`demo`, `test`, `factice`, `placeholder`…).

**La règle porte sur l'état réel, pas sur le geste en soi** (précision du 2026-08-06) :
simuler une signature dans un **bac à sable** est la manière *correcte* de tester la
boucle — c'est ce que font tous les tests. La première version de la garde bloquait
partout, y compris là où son propre message recommandait d'aller : incohérence corrigée.

```
LESSONS_DIR == lab/forge_evidence/asset_lessons/   → signature simulée REFUSÉE
LESSONS_DIR ailleurs (bac à sable)                 → signature simulée AUTORISÉE
```

**Limite assumée** : ce filtre attrape les marqueurs *explicites*. Il ne distingue pas un
nom plausible mais faux — aucune garde locale ne le peut. Il ferme la panne observée, il
ne prouve pas l'authenticité d'une signature.

## État réel au gel V1 (2026-08-06)

```
assets ingeres en bibliotheque : 0        (catalogue identique a HEAD)
propositions                   : 8 PROPOSED, 0 appliquee, 0 decideur
lecons                         : 2 CANDIDATE, 0 VALIDATED, 0 APPLIED
contraintes actives            : aucune
```

La boucle est **prouvée**, elle ne **contraint rien** aujourd'hui : aucune leçon n'a été
ratifiée. C'est l'état honnête d'un mécanisme qui attend une signature humaine, pas un
mécanisme inerte.

**Formulation à ne jamais employer** : « Asset Library prête production ». La formulation
juste est : *preuves disponibles sur le périmètre testé* — 9 assets, tous des primitives
paramétrées, 3 défauts réels trouvés et fermés.

## Problème identifié pour V1.1 — `variant_contract`

Le défaut le plus structurant trouvé pendant V1, **non corrigé** :

| couche | nomme les variantes |
|---|---|
| `asset_spec_author` (Qwen) | librement, dans la langue de la demande (`ferme`, `ouvert`) |
| `build_asset.py` | en dur, selon l'archétype (`_lid_closed`, `_lid_open`) |
| `variants_match_geometry` | exige une correspondance exacte |

Rien ne déclare la correspondance. Conséquence mesurée : une demande **correctement
comprise** (« un coffre avec un état fermé et un état ouvert ») produit un asset qui
**échoue**. Ce n'est pas une faiblesse du modèle — c'est un contrat manquant entre deux
couches.

Cas conservé comme pièce à conviction : `knowledge_base/assets/_failed_cases/gen_barrel_wood/`.

Classé **V1 LIMITATION → V1.1 CANDIDATE**. Ne pas le lire comme une fonctionnalité.

## Limites assumées de la spécification

- Une leçon par lot suppose des lots homogènes. Un lot mélangeant 7 archétypes produira
  des leçons trop générales pour être actionnables — c'est une raison de garder les lots
  petits et thématiques, pas une raison d'élargir le schéma.
- La boucle ne mesure que ce que les oracles voient : elle n'apprendra **jamais** qu'un
  asset est laid. La qualité artistique reste hors mécanique, comme partout ailleurs.
- Rien ici ne relève du MCTS. La sélection de trajectoire est explicitement hors périmètre.

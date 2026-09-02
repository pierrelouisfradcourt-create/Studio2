# MEMORY_PROPOSAL_ASSET_LIBRARY_V1

> **Date** : 2026-08-06 · **Statut** : **PROPOSITION — NON ÉCRITE EN MÉMOIRE**
> Rien de ce document n'est dans `memory/`. Les écritures durables sont propose-only,
> ratifiées par Pierre (ADR-002).
> `claim_verdict: NO_CLAIM_ALLOWED`

Faits durables issus du chantier Asset Library V1, proposés pour la mémoire permanente.
Chacun est **mesuré**, pas déduit. Si tu ratifies, ils deviennent des fiches `memory/`.

---

## 1. Le producteur n'est jamais son propre juge

**Fait** : une campagne de mesure faite *avec Blender* a rapporté une géométrie parasite
(`Icosphere`, 42 sommets) présente dans les 8 assets de référence, et un `min = −1.0`
uniforme. C'était **faux** : cette géométrie est créée par l'importeur glTF de Blender,
dans une collection `glTF_not_exported`. Le parseur indépendant ne l'a jamais vue.

**Pourquoi ça compte** : l'outil de production mesurait son propre environnement en
croyant mesurer l'asset. Ce n'est pas une question de confiance, c'est une question de
périmètre d'observation.

**Comment l'appliquer** : toute mesure servant de preuve est refaite par un outil qui n'a
pas produit l'artefact.

---

## 2. Un oracle doit accepter la référence connue-bonne

**Fait** : un oracle mesurant la bounding box du *fichier entier* aurait recalé les 8
KayKit comme « enterrés d'un mètre ». Le corpus a falsifié l'oracle naïf **avant** qu'il
soit écrit.

**Comment l'appliquer** : un corpus de falsification contient toujours la référence du
studio, pas seulement des cas fabriqués. Renforce `oracle_must_accept_reference`.

---

## 3. La KB est propose-only, sans exception d'asset

**Fait** : le premier lot a été écrit **directement** dans `catalog.json`. Annulé, le
catalogue restauré à l'octet près, l'écriture directe remplacée par `kb.proposal.v1` +
`--apply --ratifie-par`. La porte existante (`kb_proposal.apply_proposal`) était **déjà
générique** — aucune ligne à y changer.

**Comment l'appliquer** : avant de créer une porte d'écriture, vérifier si elle existe.
Ici elle existait et je ne l'avais pas cherchée.

---

## 4. Qwen : runtime réel, worker non autonome

**Fait** : `asset_spec_author` est appelé réellement depuis LM Studio (HTTP direct,
sans agent), résolu par le registry, tracé par reçus HMAC vérifiés.

**Limite mesurée** : aucune vérification sémantique de l'archétype choisi. « piédestal »
→ `platform` : plausible, jamais vérifié. Le modèle est fiable en **transformation**, pas
en **rappel** — cohérent avec `qwen_recall_vs_transform`.

**Formulation à ne jamais employer** : « worker autonome complet ».

---

## 5. La boucle de leçons, et ses cinq statuts

**Fait** : `CANDIDATE → VALIDATED → APPLIED | REFUTED`, plus `INSUFFICIENT_DATA`.

Deux garde-fous non négociables :
- `validated_at_ts` — seuls les runs **postérieurs** comptent, sinon une leçon se
  confirme rétroactivement sur les runs qui l'ont motivée ;
- `REFUTED` est un état **normal** — une leçon qui ne peut pas être réfutée n'apprend rien.

Une leçon `APPLIED` **garde** sa contrainte : la retirer parce qu'elle a marché
rouvrirait le défaut qu'elle ferme.

---

## 6. Une signature humaine ne se simule jamais dans l'état réel

**Fait** : une leçon a été validée `--par "Pierre (demo)"` pour démontrer un effet — une
signature qu'il n'avait pas donnée. Retirée, et rendue mécaniquement impossible.

**Précision qui compte** : la règle porte sur l'**état réel du dépôt**. Simuler une
signature en bac à sable est la manière *correcte* de tester la boucle. La première
version de la garde bloquait partout, y compris là où son propre message envoyait.

---

## 7. Une déclaration ne peut que durcir, jamais assouplir

**Fait** : la déclaration du producteur (`metadata.json`) est utilisée **sans** devenir
une autorité. Annoncer des `variants` retire le droit au classement automatique et crée
une obligation de correspondance géométrique.

**Comment l'appliquer** : quand une donnée non fiable doit servir à quelque chose, ne lui
laisser produire que des contraintes supplémentaires.

---

## 8. Le prochain problème est nommé : `variant_contract`

**Fait mesuré** : Qwen nomme les variantes librement (`ferme`, `ouvert`), `build_asset.py`
nomme ses meshes en dur (`_lid_closed`, `_lid_open`), et `variants_match_geometry` exige
une correspondance exacte. Rien ne déclare le mapping.

**Conséquence** : une demande **correctement comprise** produit un asset qui échoue. Ce
n'est pas une faiblesse de modèle — c'est un contrat manquant entre deux couches que la
Forge a elle-même écrites.

Pièce à conviction : `knowledge_base/assets/_failed_cases/gen_barrel_wood/`.

---

## 9. Trois défauts, trois exécutions réelles

Aucun des défauts fermés pendant ce chantier n'a été trouvé par relecture :

| défaut | trouvé par |
|---|---|
| `variants` avalées par le seuil de part de sommets | production d'un coffre réel |
| `origin_rule` désactivant le check de pivot en silence | rédaction d'un manifeste réel |
| variantes déclarées sans géométrie | sortie réelle de Qwen |

**Comment l'appliquer** : faire tourner la chaîne sur un cas réel trouve ce qu'aucune
revue ne trouve. Renforce `proof_never_replaces_product_run`.

---

## Ratification

Si tu ratifies, ces 9 faits deviennent des fiches `memory/` (une par fait, liées entre
elles). Sinon ce document reste une proposition inerte : **rien n'est écrit en mémoire
aujourd'hui**.

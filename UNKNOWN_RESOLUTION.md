# UNKNOWN — résolution

*2026-09-01 · **DOCUMENTED_ONLY** · aucun code, aucune suppression, aucun renommage.
Dépôt source à `feeb29cb`, non touché.*

Grille appliquée à chacun : **bloque le modèle cible ?** · **capacité à conserver ?** ·
**legacy à laisser derrière ?** · **inutile / sans consommateur ?**

Et pour chacun la question qui tranche vraiment — **quelle décision du nouveau Studio dépend de
cette capacité ?** Aucune ⇒ on ne la réimplémente pas par réflexe.

---

## U1 · `reference_guard` — **résolu : aucune décision n'en dépend**

**Mesure directe.** Occurrences de `reference_guard` / `reference_baseline` / `DRIFT` dans les
modules qui **décident** :
```
verdict.py     0        verify_run.py  0        gate.py  0        oracle.py  0
```
Ce qu'il produit : une empreinte comparée à une baseline, et un statut parmi
`CLEAN · AUTORISE · DRIFT · INCOMPLET · ERROR · NO_BASELINE`. Le code le qualifie lui-même
d'`advisory_check`. Sa baseline vit dans `lab/forge_evidence/reference_baseline.json`.

| grille | réponse |
|---|---|
| bloque le modèle cible ? | **non** |
| capacité à conserver ? | **non en l'état** |
| legacy à laisser derrière ? | oui — reste dans l'ancien Studio |
| inutile / sans consommateur ? | **11 références de code, 0 consommateur de décision** |

> **349 diffs à chaque run depuis le 2026-07-31, et pas une seule décision ne s'en saisit.**
> Ce n'est pas une capacité en panne, c'est une **mesure sans destinataire**.

**Décision proposée : ne pas migrer.** Si le nouveau modèle veut détecter la dérive d'une
référence, la question à poser est *« quelle décision doit changer quand la référence dérive ? »* —
et on construira alors le consommateur **avant** le capteur. Réimplémenter le capteur d'abord
serait refaire l'erreur : un instrument qui mesure dans le vide.

**Verdict : `RETIRE` (legacy).** Non supprimé du dépôt source.

---

## U2 · Rail des 25 nœuds — **résolu : catalogue, pas file**

Le rail est aujourd'hui **un pipeline à l'échelle du portefeuille** : chaque jeu dépose une
compétence pour le suivant, l'ordre est une contrainte, et *« le rail ne démarre pas sans le
jalon 0 »*.

Or le modèle cible dit l'inverse : **une vision entre, la Forge compose les capacités
nécessaires**. Un rail imposé rétablirait exactement la linéarité qu'on retire d'un cran plus bas.

| grille | réponse |
|---|---|
| bloque le modèle cible ? | **oui, s'il reste un plan imposé** — un plan de production séquentiel contredit la composition dynamique |
| capacité à conserver ? | **oui, comme catalogue** — l'arbre de compétences reste une carte utile |
| legacy à laisser derrière ? | son **ordre** et son **jalon 0 bloquant** |
| inutile ? | non — mais sa colonne statut est périmée sur 5 nœuds (Pacman, Bomberman, Tetris, Tower Defense, Card Game ont du code alors qu'ils sont `◇ CIBLE`) |

**Décision proposée : le rail devient un CATALOGUE DE COMPÉTENCES**, pas une file de production.
```
avant   nœud 9 = Tower Defense, on ne peut y aller qu'après 0..8
après   Tower Defense a besoin de PATHFINDING ; PATHFINDING est-il acquis ?
        ├── oui, brique KB validated → réutiliser
        └── non → le jeu la déposera
```
La **loi d'empilement** survit — *« nouveau jeu = compétences acquises + 1 delta »* — mais comme
**mesure du risque**, pas comme permission de démarrer. Un jeu à 3 deltas est un jeu risqué, ce
n'est plus un jeu interdit.

**Conséquence directe** : Tower Defense n'est plus « au rang 9 derrière un jalon 0 ». Il devient
un jeu dont on mesure les compétences manquantes. **C'est ce qui débloque ton intention initiale.**

**Verdict : `ADAPT` — conserver l'arbre, retirer l'ordre.**

---

## U3 · Chaîne asset — **résolue : câblée, et sa « lacune » est correcte**

L'audit du 2026-08-28 notait : *« les contrats asset sont écrits MAIS `asset_dispatch.py` ne les
charge pas et `asset_producer` est absent de `models[].roles` »*. **Mesure d'aujourd'hui — la
première moitié est périmée, la seconde est un choix juste :**

```
asset_dispatch.py:57   ETAPE      = "s-asset-produce"      ← les contrats SONT référencés
asset_dispatch.py:62   ETAPE_SPEC = "s-asset-spec"

get_model_for_role('asset_spec_author') -> qwen2.5-14b-instruct [lmstudio]   ← résout
get_model_for_role('asset_producer')    -> None                              ← NE RÉSOUT PAS
```
Et `roles.yaml:243` explique pourquoi, verbatim : *« DÉCLARATION DE L'EXISTANT (2026-08-06). Ce
runtime a réellement produit 6 assets avant d'être déclaré ici. »* Son `implementation` est
`blender 5.1.1 --background`.

> **`asset_producer` n'est pas un rôle de modèle — c'est un sous-processus Blender déterministe.**
> Il ne doit *pas* résoudre vers un LLM. L'absence est correcte.

| grille | réponse |
|---|---|
| bloque le modèle cible ? | non |
| capacité à conserver ? | **oui, à la demande** — un jeu 2D n'en a pas besoin |
| legacy ? | non |
| sans consommateur ? | non — mais **hors du fermé transitif de `run_real`** : aucun run n'en dépend |

**Verdict : `REUSE` en capacité optionnelle.** Elle respecte déjà l'invariant qui compte :
*« ne juge jamais sa propre production, le verdict appartient à un mesureur indépendant »*.

---

## U4 · `s10d-oracle-visual` — **résolu : contrat sans chemin d'exécution**

```
's10d-oracle-visual' dans ORDER   : False
's10d-oracle-visual' dans PROFILES: AUCUN
```
Le contrat existe, le module existe, **aucun profil ne peut l'invoquer**. C'est un contrat sans
appelant — le même motif que le panel Prisme (`--charter` jamais passé).

**Mais la QA visuelle, elle, existe** — par une autre route : `product_oracle_godot.py`
(1 056 lignes, capture GPU réelle) est appelé via `standard_oracles.check_observable_coverage`.

| grille | réponse |
|---|---|
| bloque le modèle cible ? | non — la capacité est couverte ailleurs |
| capacité à conserver ? | **la capacité oui, ce contrat non** |
| legacy ? | le contrat `s10d` |
| sans consommateur ? | **oui — 0 profil** |

**Verdict : `RETIRE` le contrat `s10d`, `REUSE` `product_oracle_godot`.** Ne pas confondre la
capacité (vivante) avec son contrat orphelin.

---

## U5 · Indépendance de la red-team — **résolu : périmètre étroit**

```
REDTEAM_INDEPENDENT_PROFILES = ("full_content",)      ← UN SEUL profil
```
La perte de `council`/Qwen n'affecte donc **qu'un profil sur 19**. Partout ailleurs la red-team
tourne déjà sans exigence d'indépendance. Et la dégradation est honnête par construction : le
`reviewer` réel restitué est `claude-blind (fallback)`, **jamais le nom Qwen**.

| grille | réponse |
|---|---|
| bloque le modèle cible ? | **non** — sauf si un jeu exige `full_content` |
| capacité à conserver ? | **oui, à reconstruire plus tard** comme capacité explicite |
| legacy ? | `council.py` oui — l'adaptateur, pas la capacité |
| sans consommateur ? | non |

**Verdict : `UNKNOWN → REBUILD différé`.** Aucun import de `council`. Si le modèle cible veut une
contradiction indépendante, on écrira un adaptateur LM Studio **dans la nouvelle Forge**, avec une
interface explicite — le jour où un jeu l'exige, pas avant.

---

## Synthèse

| # | UNKNOWN | résolution | bloque le modèle ? |
|---|---|---|---|
| U1 | `reference_guard` | **RETIRE (legacy)** — 0 consommateur de décision | non |
| U2 | rail 25 nœuds | **ADAPT** — catalogue de compétences, plus une file | **oui s'il reste un plan** → résolu |
| U3 | chaîne asset | **REUSE** optionnelle — câblée, absence de rôle correcte | non |
| U4 | `s10d-oracle-visual` | **RETIRE** le contrat · **REUSE** `product_oracle_godot` | non |
| U5 | red-team indépendante | **REBUILD différé** — 1 profil sur 19 concerné | non |

**Un seul UNKNOWN bloquait réellement le modèle : le rail.** Il est résolu en le requalifiant de
plan imposé en catalogue de compétences — ce qui, au passage, **débloque Tower Defense**.

Deux constats méritent d'être retenus au-delà de ces cinq cas :
- **U1 et U4 sont le même motif** — un mécanisme construit, correct, testé, et **sans destinataire**.
  C'est le mode de panne dominant de ce studio, pas la panne technique.
- **U3 corrige un audit antérieur** : ce qui était noté comme un câblage manquant est soit fait,
  soit un choix juste. **Une dette mesurée il y a un mois n'est pas une dette aujourd'hui.**

```
status_by_surface:
  unknown_resolution:        DOCUMENTED_ONLY
  reference_guard_consumers: TESTED     # 0 dans verdict/verify_run/gate/oracle
  s10d_profile_presence:     TESTED     # absent de ORDER et des 19 profils
  asset_role_resolution:     TESTED     # asset_spec_author résout, asset_producer non (correct)
  redteam_independence_scope:TESTED     # 1 profil : full_content
  rail_requalification:      DOCUMENTED_ONLY
```
`software_verdict: OK` (document) · `evidence_verdict: MECHANICAL_VALIDATION_ONLY` ·
`claim_verdict: NO_CLAIM_ALLOWED` · `no_global_ready_verdict: true`

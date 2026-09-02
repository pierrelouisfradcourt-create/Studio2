# ADJUDICATION RED-TEAM — `S10D_CONTRACT_PROPOSAL.md` v1 → v2

- **Date** : 2026-07-12
- **Contexte** : Pierre a ratifié le contrat proposé ; le chemin déclaré du document exige
  le red-team avant toute exécution. Trois relecteurs adversariaux indépendants
  (méthodologie F-M*, technique-vs-code F-T*, doctrine F-D*) — **21 findings bruts**,
  tous adjugés ci-dessous (exigence : épuisement des objections vérifiables).
- **Conséquence de gouvernance** : les corrections qui MODIFIENT les critères E1
  (F-M1/M2/M3/M5/M6/M7, F-T1/T4/T5) rendent la version amendée ≠ la version ratifiée.
  → **E1 n'est PAS exécutée** ; les critères v2 retournent à Pierre pour re-ratification.
  Le YAML du contrat (substance ratifiée inchangée : advisory, déterministe, A1/A2/A3/A5,
  seuils v0, Option A) est créé et validé mécaniquement.

## Dispositions (finding par finding)

### Sérieux

| # | Titre | Disposition | Correction appliquée (v2) |
|---|---|---|---|
| F-M1 | E1 déjà « connue » : rapports capteur antérieurs existants sur les 2 cibles (`lab/forge_sensors/breakout/`, `.../menagerie_tactics/`, commit `3ac10cc`) | **CONFIRMÉ** | E1 requalifiée **« expérience confirmatoire d'intégration »** ; les runs antérieurs sont déclarés dans le doc ; la conclusion autorisée est réduite en conséquence (§6 v2) |
| F-M2 / F-T1 | « Hash identique sur 2 runs » : périmètre indéfini + valeurs légitimement instables (B1-B3 temps réel `collect.mjs:182-190`, A6 à mi-seuil `:311-321`, A3 frame animée, chemins absolus dans `artifact`) | **CONFIRMÉ** | **Hash canonique défini d'avance** : projection `{sensor, version, advisory, game, run.seed, run.mode, run.input_sequence}` + observations A1/A2/A5 `(id, outcome, measured)` + A3 `(id, outcome)` ; A6/B/A4 et `artifact` EXCLUS ; extraction par dépouilleur déterministe zéro-paramètre (gabarit `depouille.mjs` P1.1). UN re-run technique documenté autorisé. Un échec du critère = un résultat, jamais un retuning |
| F-M3 / F-T4 | Critère d'inertie vacueux (Option A) et non opérationnalisé ; « verdict.json avec/sans s10d » inexécutable (aucun `verdict.json` sous `lab/forge_runs/breakout/` ; celui de menagerie vit dans le worktree) | **CONFIRMÉ** | Clause « avec/sans verdict.json » **supprimée** du YAML. Remplacée par : manifeste sha256 récursif AVANT/APRÈS E1 des **deux arbres** `lab/forge_runs/` (repo principal ET worktree menagerie), identité octet exigée. Faible puissance sous Option A **avouée dans le doc** (contrôle de non-nuisance, pas une preuve forte) |
| F-M4 | Classification TP/FP post-hoc, pas de contrôle propre au genre menagerie | **PARTIEL** | Règle de classification **pré-enregistrée** (§6 v2 : un signal est FP si le screenshot-artefact cité le contredit selon la définition de sa métrique ; jugement Pierre consigné signal par signal). Le volet est **déclaré observationnel non contrôlé** — aucune claim de détection n'en sera dérivée. Réfuté sur « ajouter une sonde-contrôle appariée » : hors périmètre (créer des sondes menagerie = nouvelle expérience de détection, pas E1-intégration ; serait requis AVANT toute claim de détection future) |
| F-M5 | SUCCÈS atteignable à vide (tout `metric_unavailable` = succès formel) | **CONFIRMÉ** | Critère de **couverture minimale** ajouté : chaque famille A1/A2/A3/A5 émet ≥1 observation `measured` non-null sur CHAQUE cible, sinon INVALIDE technique (un re-run borné, second échec = INVALIDE) |
| F-M6 / F-T6 | Cibles non gelées ni pinnées ; menagerie = worktree non mergé supprimable, encodé en dur (`collect.mjs:149`) | **CONFIRMÉ** | Gel sha256 des fichiers de chaque jeu cible AVANT E1, identité entre run 1 et run 2 ; commit du worktree pinné dans l'évidence ; worktree absent/divergent = précondition INVALIDE (déclarée) |
| F-M7 | Re-runs non bornés, E1 rejouable discrètement, « ≥2 jeux » ouvert | **CONFIRMÉ** | Liste de cibles **exactement fermée** : {breakout, menagerie_tactics} ; E1 **one-shot** (nouvel essai = nouveau protocole ratifié) ; chaque re-run technique borné à UN, documenté |
| F-D2 | Option B contredit l'invariant « jamais câblé driver » déclaré non négociable ; l'invariant §3 contenait sa propre clause d'échappement ; le driver n'a aucun concept d'étape annexe (`driver.py:386-388`) | **CONFIRMÉ** | **Option B retirée du document** (et l'exception retirée de l'énoncé §3). Toute proposition de câblage = document séparé post-E1 avec son propre cycle |
| F-D7 | E1 exige des écritures (logs P0, sha, résultats) interdites par les permissions du contrat ; exécutant non nommé | **CONFIRMÉ** | §6 v2 : **exécutant E1 = orchestrateur, HORS contrat s10d** ; évidence sous `lab/forge_sensors/_e1_evidence/` (pattern `_p11_evidence/`, jamais écrasée) ; `S10D_E1_RESULTS.md` écrit par l'orchestrateur |
| F-T2 | A6 émise AVEC outcome jugé par le capteur intouchable, non traitée comme B | **CONFIRMÉ** | §3 v2 : A6 « émise par le capteur avec outcome, HORS évaluation et HORS hash canonique » (même statut que B) — cohérent avec « capteur appelé, jamais réécrit » |
| F-T5 | E1 écraserait l'évidence P1 committée (`collect.mjs:262` écrit au chemin fixe) | **CONFIRMÉ** | Doc v2 : `lab/forge_sensors/breakout|menagerie_tactics/` déclarés **sorties vivantes** ; l'évidence FIGÉE de P1/P1.1 = `_p11_evidence/`, `_probe_*` et le commit `3ac10cc` (git). L'invariant « jamais écrasée » est précisé sur ces artefacts-là |

### Mineurs

| # | Titre | Disposition | Correction appliquée (v2) |
|---|---|---|---|
| F-M8 | Raccourcis « capteur prouvé » sans qualificatifs dans le YAML permanent ; « référence sha » indéfinie | **CONFIRMÉ** | YAML : « prouvé sur défauts synthétiques Breakout (P1_1_RESULTS.md), sans généralisation » ; gardeFou : shas relevés en début de run, re-vérifiés en fin (auto-contenu) |
| F-D1 | Tout dispatch via `prepare_dispatch` APPEND dans `lab/forge_evidence/dispatch_audit.jsonl` (`dispatch.py:29,104-110`) — write hors périmètre déclaré | **CONFIRMÉ** | Déclaré dans le doc : en Option A, E1 lance `collect.mjs` DIRECTEMENT (aucun dispatch, aucun write d'audit) ; un futur dispatch contractualisé de s10d devra déclarer ce write |
| F-D4 | `software_verdict: (aucun)` contredit la RESTITUTION_RULE injectée (OK/FAIL/BLOCKED) | **CONFIRMÉ** | YAML v2 : software_verdict porte sur **l'EXÉCUTION du capteur** (OK = rapport produit + invariants de format tenus ; FAIL = capteur en échec ; BLOCKED = préconditions absentes/sha divergent) — « ne porte JAMAIS sur la qualité du jeu » inscrit dans le contrat |
| F-D8 / F-T7 | « 16 champs » : `contract.py:41-59` = 17 clés YAML ; SCHEMA.md dit « 16 champs / 10 catégories » | **CONFIRMÉ** (terminologique) | Libellé : « SCHEMA.md (16 champs / 17 clés YAML) » |
| F-T3 | « Port e2e partagé 4503 » faux pour cette paire (breakout 4503, menagerie 4531/4533) ; vraie collision = capteur-menagerie 4531 vs e2e-menagerie 4531 | **CONFIRMÉ** | Justification corrigée ; exigence séquentielle maintenue |
| F-T8 | Rôle `deterministic` documenté « 10a/10b/10c + 12 » dans roles.yaml, s10d s'y greffe | **PARTIEL** | Mention ajoutée dans `delegation_context` du contrat. roles.yaml non modifié (moindre modification ; MAJ du commentaire = candidate au même commit si Pierre veut) |
| F-T9 | `check.mjs` accepte des rapports périmés (`check.mjs:26`, aucun contrôle de fraîcheur) | **CONFIRMÉ** | Protocole v2 : les 5 `collect.mjs p1_probe_*` sont **re-exécutés** aux deux bornes (avant/après E1), puis `check.mjs` exit 0 |
| F-T10 | Aucun test n'activera jamais s10d (CHAIN figée ; tests = zone protégée) | **CONFIRMÉ** | Commande de validation manuelle documentée dans l'en-tête du YAML + exécutée à la livraison (preuve ci-dessous). Ajout d'un test « annexes advisory » = incrément futur, **gate Pierre** (zone protégée `.claude/rules/tests.md`) |

### Angles négatifs propres (aucun finding)

- **F-D3** — fuite advisory→gate : zéro lecteur de `lab/forge_sensors/` dans `scripts/forge/` et `autopilot.py` ; `is_clean_pass` (`verdict.py:196-218`) ne lit que les reçus code/archi/wiremap.
- **F-D5** — footgun préfixe : aucun nouveau (vocabulaires disjoints).
- **F-D6** — `capability_role: deterministic` résout `non-llm` (`roles.yaml:58-63`), même chemin que s10a-c/s12.

### Prémisses re-vérifiées exactes (relecteur technique, par exécution)

YAML §4 activable (`validate_contract` + `build_dispatch_payload` → OK, runtime `non-llm`) ·
CONFIGS breakout+menagerie présents · commande fixtures exacte · 19/19 tests cœur pur re-exécutés ·
écritures capteur limitées à `lab/forge_sensors/<jeu>/` (exhaustif) · aucun timestamp dans le rapport ·
P0 re-prouvable sur les deux cibles (playwright résolu, worktree présent).

## Bilan

21 findings : **18 confirmés/partiels → corrigés dans v2** · **3 angles vérifiés propres** ·
0 finding écarté sans preuve. Aucun finding n'invalide la substance ratifiée (advisory,
déterministe, A1/A2/A3/A5 seuils v0, Option A, aucune fuite vers le chemin de preuve) —
ils durcissent le protocole E1 et corrigent des prémisses factuelles.

```
software_verdict: (aucun — adjudication documentaire)
evidence_verdict: MECHANICAL_VALIDATION_ONLY
claim_verdict: NO_CLAIM_ALLOWED
```

# CONTRAT `s10d-oracle-visual` (couche 1 déterministe, advisory) — v2 red-teamée

- **Date** : 2026-07-12 (v2 — v1 du même jour durcie par red-team : 21 findings, 18 corrigés,
  annexe d'adjudication `S10D_REDTEAM_ADJUDICATION.md`)
- **Statut** : **contrat RATIFIÉ (Pierre, 2026-07-12) — YAML créé (§7 livrable 1).**
  **E1 : critères AMENDÉS par le red-team → RE-RATIFICATION PIERRE REQUISE avant exécution**
  (les critères exécutés doivent être ceux ratifiés — jamais une version que le gate n'a pas vue).
- **Parent** : `FORGE_2_DESIGN.md` §5 M3 · `P1_1_RESULTS.md` (preuve fondatrice) ·
  `P1_MECHANICAL_CONTRACT.md` (invariants advisory reconduits)
- **Périmètre** : couche 1 déterministe UNIQUEMENT, advisory, hors pipeline de preuve.
  Couche 2 (juge multimodal) HORS périmètre. Palette HORS périmètre (attend M5 art bible — P2).
  **Aucun câblage driver** (l'ex-« Option B » v1 est RETIRÉE — F-D2 : elle contredisait un
  invariant non négociable ; tout câblage futur = document séparé post-E1, cycle complet).

---

## 1. Ce sur quoi on s'appuie (acquis, rien de plus)

Démontré par P1.1 (formulation ratifiée Pierre 2026-07-12) : *A1/A2/A3/A5 détectent des
défauts **synthétiques** connus, orthogonaux à P0, **sur Breakout**, sans FP observé dans cette
expérience.* Non démontré : généralisation inter-genres, défauts subtils, absence de FP à
grande échelle, tout ce qui touche au fun. Cet incrément ne livre PAS un « oracle visuel » :
il livre l'existence contractuelle de l'étape s10d (runtime = le capteur P1.1) et une
expérience confirmatoire d'intégration.

**Déclaration de préexistence (F-M1)** : des rapports capteur existent DÉJÀ pour les deux
cibles E1 (`lab/forge_sensors/breakout/` et `.../menagerie_tactics/`, évidence P1 committée
`3ac10cc`). E1 n'est donc PAS une découverte : c'est une **expérience confirmatoire**
(reproductibilité + non-nuisance, sous critères durcis figés d'avance). Sa conclusion
maximale autorisée est réduite en conséquence (§6).

## 2. Hypothèse expérimentale (unique, confirmatoire)

> L'étape s10d, bornée par contrat et nourrie exclusivement des familles A1/A2/A3/A5 aux
> seuils v0 figés, s'exécute sur les deux jeux forgés verts P0 en produisant un rapport
> advisory reproductible (au sens du hash canonique §6), sans aucun effet mesurable sur
> le chemin de preuve, avec couverture de mesure complète et comptabilité FP honnête.

C'est une hypothèse d'**intégration inoffensive**, pas de détection. La détection sur
vrais jeux reste une question ouverte qu'E1 documente sans la trancher.

## 3. Invariants (reconduits de `P1_MECHANICAL_CONTRACT.md`, non négociables — sans clause d'échappement)

- **P0 gelé.** La SEULE écriture sous `scripts/forge/` : le fichier de contrat
  `contracts/s10d-oracle-visual.yaml` (données déclaratives — neutralité prouvée : chaîne
  d'étapes EN DUR dans `dispatch.py:32-49` et `driver.py`, chargement par nom exact
  `contract.py:112`, aucun scan du dossier au runtime ; le test capstone ne vérifie que
  les manquants, `test_contract_chain.py:39-41`).
- s10d **ne touche pas** `software_verdict` d'un run forge, `decision`, `is_clean_pass()`,
  ni aucun reçu/verdict. Aucun pass/fail de qualité, aucun score global.
- **Aucun LLM dans le chemin.** `capability_role: deterministic` → `non-llm`
  (`roles.yaml:58-63`, même résolution que s10a-c/s12).
- **Capteur appelé, jamais réécrit** : `scripts/quality_sensor/` est le runtime. Toute
  modification du capteur = hors périmètre, retour à Pierre. Idem
  `mutation.py`/`static_oracles.py`.
- **Familles évaluées : A1/A2/A3/A5 uniquement.** A4 = signal brut non jugé. **A6 et B1-B4 :
  émises par le capteur inchangé (A6 porte un outcome, `collect.mjs:316-321`) mais HORS
  évaluation et HORS hash canonique** (F-T2 — même statut : présentes au rapport,
  jamais comptées). Pas de nouvelle métrique.
- **Seuils figés v0** : A1 < 4.5:1 · A2 < 24 px · A3 > 0.92 · A5 > 0. Aucun retuning
  post-hoc ; un défaut raté à cause d'un seuil = un résultat.
- Vocabulaire d'observation UNIQUE : `signal_detected` / `signal_absent` /
  `metric_unavailable`. Sorties sous `lab/forge_sensors/<jeu>/`, jamais promues en mémoire.
- **Évidence figée vs sorties vivantes (F-T5)** : l'évidence FIGÉE de P1/P1.1 =
  `lab/forge_sensors/_p11_evidence/`, `_probe_*` et le commit `3ac10cc` — jamais écrasée.
  `lab/forge_sensors/breakout/` et `.../menagerie_tactics/` sont des **sorties vivantes**
  (chemin fixe `collect.mjs:262`) : un run E1 les réécrit, c'est déclaré et normal.
- Non-régression capteur : les 5 `collect.mjs p1_probe_*` **re-exécutés** puis
  `fixtures/p1/check.mjs` exit 0 (F-T9 : check sans re-collect accepte des rapports périmés).

## 4. Contrat YAML (schéma SCHEMA.md — 16 champs / 17 clés YAML)

Fichier : `scripts/forge/contracts/s10d-oracle-visual.yaml` (créé — §7 livrable 1,
validation mécanique : `load_contract` + `build_dispatch_payload` OK, runtime `non-llm` ;
commande de validation manuelle documentée dans l'en-tête du fichier — F-T10, aucun test
de chaîne ne le couvre, l'ajout à `CHAIN` = zone protégée, gate Pierre).

Points de contrat durcis en v2 :
- `memoire` : qualificatifs P1.1 inline (« défauts synthétiques, Breakout, sans
  généralisation ») — F-M8.
- `final_report` : **software_verdict porte sur l'EXÉCUTION du capteur** — OK = rapport
  produit + invariants de format tenus · FAIL = capteur en échec · BLOCKED = préconditions
  absentes/sha divergent — et « ne porte JAMAIS sur la qualité du jeu » (F-D4, cohérent
  avec la RESTITUTION_RULE injectée `contract.py:62-69`).
- `gardeFou` : gel auto-contenu — shas du capteur relevés en début de run, re-vérifiés en
  fin ; divergence → BLOCKED documenté, jamais silencieux (F-M8).
- `permissions` : write UNIQUEMENT `lab/forge_sensors/<jeu>/`. **Déclaré (F-D1)** : tout
  dispatch futur via `prepare_dispatch` APPEND dans `lab/forge_evidence/dispatch_audit.jsonl`
  (`dispatch.py:104-110`) ; en E1 le capteur est lancé DIRECTEMENT (aucun dispatch, aucun
  write d'audit).
- `delegation_context` : annexe advisory hors chaîne de promotion ; greffe sur le rôle
  `deterministic` documenté pour s10a-c/s12 (F-T8).

## 5. Point d'attache : AUCUN (décidé)

s10d n'est PAS câblé au driver. Le contrat existe ; l'étape se lance manuellement
(`node scripts/quality_sensor/collect.mjs <jeu>`). Zéro modification de `driver.py`
(qui n'a d'ailleurs aucun concept d'étape annexe non-bloquante — `driver.py:386-388`
traite toute étape déterministe non câblée comme BLOCKED). Doctrine « capteur = advisory,
hors pipeline » reconduite sans exception.

## 6. Expérience E1 — confirmatoire, one-shot (critères v2 figés AVANT — RE-RATIFICATION REQUISE)

- **Exécutant (F-D7)** : l'orchestrateur, HORS contrat s10d. Évidence E1 sous
  `lab/forge_sensors/_e1_evidence/` (pattern `_p11_evidence/`, jamais écrasée) ;
  `S10D_E1_RESULTS.md` écrit par l'orchestrateur.
- **Cibles (liste EXACTEMENT fermée — F-M7)** : `breakout` et `menagerie_tactics`. Aucun
  ajout/retrait après ratification. E1 est **one-shot** : un ÉCHEC ne se rejoue pas —
  nouvel essai = nouveau protocole ratifié.
- **Préconditions (INVALIDE si absentes)** : worktree
  `.claude/worktrees/forge-menagerie-tactics` présent, commit pinné dans l'évidence
  (F-M6/F-T6 : dépendance hors master déclarée — `collect.mjs:149` l'encode en dur) ;
  fixtures re-collectées + `check.mjs` exit 0.
- **Gels** :
  - capteur : sha256 `sensor.mjs`/`analysis.mjs`/`collect.mjs` avant, identiques après ;
  - **jeux cibles (F-M6)** : sha256 de chaque fichier des deux jeux AVANT E1, identiques
    entre le run 1 et le run 2 de reproductibilité ;
  - fixtures : re-collect + check exit 0 avant ET après (F-T9).
- **P0 re-prouvé** : `run-oracle.mjs` exit 0 sur chaque cible, logs conservés, exécution
  **séquentielle** — justification exacte (F-T3) : la config capteur menagerie utilise le
  port 4531 (`collect.mjs:152`) = le port e2e de menagerie (`e2e.mjs:16` du worktree) ;
  breakout e2e = 4503. UN re-run environnemental documenté autorisé par cible (règle P1.1 §4).
- **SUCCÈS (tous requis)** :
  1. **Reproductibilité au hash canonique (F-M2/F-T1)** : 2 runs même seed par cible →
     projection canonique identique. Projection figée ICI : `{sensor, version, advisory,
     game, run.seed, run.mode, run.input_sequence}` + observations A1/A2/A5
     `(id, outcome, measured)` + A3 `(id, outcome)` — A3 `measured` exclu (variance pixel
     ±0.0006 documentée P1.1), A6/B/A4 exclus (F-T2), `artifact` exclu (chemins absolus).
     Extraction par dépouilleur déterministe zéro-paramètre (gabarit `depouille.mjs` P1.1),
     écrit AVANT le premier run. UN re-run technique documenté par cible.
  2. **Couverture minimale (F-M5)** : chaque famille A1/A2/A3/A5 émet ≥1 observation
     `measured` non-null sur CHAQUE cible ; sinon INVALIDE technique (un re-run borné,
     second échec = INVALIDE).
  3. **Non-nuisance (F-M3/F-T4)** : manifeste sha256 récursif des DEUX arbres
     `lab/forge_runs/` (repo principal ET worktree menagerie) avant/après E1 : identité
     octet. **Aveu de puissance** : sous ce contrat sans câblage, c'est un contrôle de
     non-nuisance à faible puissance (le capteur n'écrit que sous `lab/forge_sensors/` par
     construction — vérifié exhaustivement `collect.mjs:264,276,352,370-371`) — il borne,
     il ne prouve pas grand-chose : dit honnêtement.
  4. **Comptabilité FP (F-M4, règle pré-enregistrée)** : chaque `signal_detected` du
     périmètre est confronté à son artefact screenshot ; il est classé FP si l'artefact
     contredit la définition de sa métrique, vrai positif si Pierre confirme un défaut
     perceptible correspondant ; jugement consigné signal par signal. Volet **observationnel
     non contrôlé** (pas de sonde-contrôle appariée au genre menagerie) : purement
     descriptif, AUCUNE claim de détection n'en sera dérivée. Pas de seuil chiffré de FP
     (le fixer maintenant serait sans base ; le fixer après serait du tuning).
- **ÉCHEC** : critère 1, 3 ou invariant de format violé (hors re-run borné).
- **INVALIDE (liste fermée)** : gel sha rompu (capteur ou jeux), fixtures rouges, P0 non
  re-prouvé, précondition worktree absente, couverture non atteinte après re-run borné.
  → Retour à Pierre.
- **Conclusion maximale autorisée si SUCCÈS** : « l'intégration contractuelle de s10d est
  confirmée inoffensive et reproductible sur les deux cibles déjà connues » — RIEN sur la
  détection, rien de généralisable (E1 est confirmatoire — §1).

## 7. Livrables (dans l'ordre)

1. `scripts/forge/contracts/s10d-oracle-visual.yaml` — **FAIT** (validé mécaniquement).
2. Rien d'autre côté code (le runtime existe : capteur P1.1).
3. **Re-ratification Pierre des critères E1 v2 (§6)** → puis exécution E1 +
   `docs/forge/S10D_E1_RESULTS.md` (gabarit `P1_1_RESULTS.md`).
4. MAJ `FORGE_2_DESIGN.md` §8 après E1.

## Rapport de charter

```
software_verdict: OK — YAML créé, validé par contract.py (load_contract +
  build_dispatch_payload → runtime non-llm), suite de tests forge verte (preuve au rapport de session)
evidence_verdict: MECHANICAL_VALIDATION_ONLY
claim_verdict: NO_CLAIM_ALLOWED
advisory_only: true
statut: contrat RATIFIÉ + YAML livré · E1 EN ATTENTE de re-ratification des critères v2
```

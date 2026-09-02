# MISSION s10s→DRIVER — branchement de l'oracle STANDARD dans la boucle (BROUILLON)

Date : 2026-07-26 · Statut : **BROUILLON — À RATIFIER PAR PIERRE avant tout spawn**
(go-brouillon Pierre 2026-07-26, JALON 0 décision ④ : « Oui pour le brouillon. Non pour
le spawn »). Le contrat YAML ci-dessous n'entre dans `scripts/forge/contracts/` qu'à la
ratification — tant qu'il vit dans ce document, la porte `prepare_dispatch` ne peut pas
le charger, donc aucun agent ne peut être dispatché dessus.
`claim_verdict: NO_CLAIM_ALLOWED`.

## OBJECTIF (une phrase, falsifiable)
Après cette mission, toute exécution de `s10s-oracle-standard` passe par la boucle du
driver — compteur `attempts` incrémenté, télémétrie écrite (y compris échec, post-M1),
FAIL déclenchant le retry borné du builder — et il devient IMPOSSIBLE qu'un `status`
s10s apparaisse dans `state.json` avec `attempts:0`.

## CONTEXTE VÉRIFIÉ (re-dérivé des sources primaires le 2026-07-26 — à re-vérifier par l'exécutant)
- `lab/forge_runs/pong/state.json` : `s10s-oracle-standard: status=FAIL, attempts=0`
  (profil standard) — un statut a été écrit SANS que la boucle d'attempts tourne.
- `lab/forge_runs/pong_verif/state.json` : `s10s-oracle-standard: status=OK, attempts=1`
  — le chemin correct existe et fonctionne.
- `driver.py` connaît pourtant s10s : `_run_deterministic` l.630, reçu l.1001, prédicat
  de retry l.1218-1223 (« son FAIL doit déclencher le retry du builder »).
- Table de confiance §4.2 : `state.json` ment sur le dénombrement (detail écrasé, pas un
  append) — le diagnostic ne doit PAS s'appuyer sur state.json seul.
- Roadmap V1 §6 item 6 : « sans quoi le profil standard reste ininterprétable ».

## TRAVAIL DEMANDÉ (ordre imposé)
1. **DIAGNOSTIC D'ABORD** : établir par lecture du code (et rejeu à coût nul si possible)
   quel chemin a pu écrire `FAIL/attempts:0` dans le run pong — chemin hors-boucle,
   écriture manuelle, ou bug du compteur. Le rapport nomme le chemin exact
   (fichier:ligne). Interdit de coder avant d'avoir prouvé la cause.
2. **CORRECTION MINIMALE** : fermer ce chemin — toute écriture d'un statut s10s passe
   par la boucle driver (attempt++, télémétrie, halt/retry). Pas de refonte.
3. **PREUVE POSITIVE** : rejouer s10s sur les données pong via le driver → `attempts≥1`
   et une ligne de télémétrie (outcome OK ou HALT selon résultat réel).
4. **PREUVE NÉGATIVE** : un test qui échoue si un statut s10s peut être posé sans
   incrément d'attempts (le test encode l'invariant, pas l'implémentation du jour).

## CONTRAINTES
- Périmètre : `scripts/forge/driver.py`, `scripts/forge/tests/`. `standard_oracles.py`
  INTOUCHÉ (c'est le juge — le modifier est la faute la plus grave, cf. contrat s10s).
- ADVISORY sur la chaîne de verdict : `verdict.py`, `gate.py`, `verify_run.py` intouchés.
- DÉPENDANCE : cette mission part du driver.py POST-M1 (télémétrie d'échec en place) —
  ne pas la lancer tant que M1 n'est pas contre-vérifiée et acceptée.
- TDD strict, RED/GREEN collés · tests isolés tmp_path · encoding utf-8 · pas de
  commit/push (gate Pierre) · une variable à la fois : AUCUN autre branchement
  (compteur append §6.5, motif d'échec §6.4) dans cette mission.

## PREUVE EXIGÉE
- Suite complète `scripts/forge/tests/` : référence post-M1 (à relever au lancement),
  zéro régression + nouveaux tests comptés.
- Diagnostic sourcé (fichier:ligne du chemin fautif) + diff minimal.
- Rejeu pong : `attempts≥1` montré dans un state.json de rejeu (jamais réécrire
  `lab/forge_runs/pong/state.json` — archive, append-only par doctrine RUN_INDEX).
- `git status --porcelain` : rien hors périmètre.

## RAPPORT
software_verdict / evidence_verdict: MECHANICAL_VALIDATION_ONLY /
claim_verdict: NO_CLAIM_ALLOWED · section skipped_validation explicite.

---

## CONTRAT D'AGENT PROPOSÉ (à copier dans `scripts/forge/contracts/s10s-branchement-driver.yaml` à la ratification)

```yaml
# Contrat d'agent Forge — mission s10s→driver (outillage, hors chaîne s0-s12)
# Statut : BROUILLON dans docs/forge/MISSION_S10S_DRIVER_DRAFT.md — n'existe dans
# contracts/ qu'après ratification Pierre. Dispatch hors profil (allow_unprofiled assumé).

role: >-
  Ingénieur outillage Forge senior, discipline TDD stricte. Point de vue : un oracle qui
  peut être court-circuité n'est pas un oracle — ta mission rend le chemin hors-boucle
  de s10s impossible, pas seulement improbable.
capability_role: forge_toolsmith
exigences_cognitives: >-
  Diagnostic de chemin de code AVANT toute écriture (cause prouvée fichier:ligne, jamais
  supposée) ; raisonnement sur invariants (preuve négative par test) ; rétro-compat state.json.
memoire: >-
  pong/state.json montre s10s FAIL/attempts:0 (profil standard) alors que pong_verif
  montre OK/attempts:1 — le chemin correct existe, un chemin hors-boucle aussi.
  driver.py connaît s10s : _run_deterministic l.630, reçu l.1001, prédicat retry
  l.1218-1223. state.json ment sur le dénombrement (table de confiance §4.2) — ne pas
  s'y fier seul. Cette mission part du driver POST-M1 (télémétrie d'échec en place).
mandatory_read:
  - docs/forge/MISSION_S10S_DRIVER_DRAFT.md
  - scripts/forge/driver.py (_run_deterministic, _run_standard_oracle, prédicat l.1218-1223)
  - lab/forge_runs/pong/state.json (archive — LECTURE SEULE)
  - lab/forge_runs/pong_verif/state.json (chemin correct — LECTURE SEULE)
  - scripts/forge/tests/conftest.py (isolation tmp_path)
objectif: >-
  Toute exécution de s10s-oracle-standard passe par la boucle driver (attempt++,
  télémétrie y compris échec, FAIL => retry borné du builder) ; un statut s10s avec
  attempts:0 devient impossible, prouvé par test négatif. Ordre imposé : diagnostic
  sourcé => correction minimale => preuve positive (rejeu pong attempts>=1) => preuve
  négative (test d'invariant).
in_scope: >-
  scripts/forge/driver.py · scripts/forge/tests/. RIEN d'autre.
out_of_scope: >-
  standard_oracles.py INTOUCHÉ (le juge). verdict.py, gate.py, verify_run.py intouchés.
  Zones gelées intouchées. lab/forge_runs/pong/state.json JAMAIS réécrit (archive).
  Aucun autre branchement de la roadmap (§6.4, §6.5) — une variable à la fois.
permissions: >-
  read: dépôt entier. write/create: UNIQUEMENT scripts/forge/driver.py et
  scripts/forge/tests/**. run: pytest (.venv312), rejeu driver sur données pong copiées
  dans un répertoire de travail, git status/diff (lecture). delete: aucun.
  INTERDIT: git commit/push/checkout, écriture dans lab/forge_runs/pong/.
gardeFou: >-
  (1) Diagnostic prouvé AVANT le premier Edit — le rapport cite fichier:ligne du chemin
  fautif. (2) Correction MINIMALE, pas de refonte de la boucle. (3) Le test négatif
  encode l'invariant « pas de statut sans attempt », pas l'implémentation du jour.
  (4) Tests isolés tmp_path, encoding utf-8. (5) Rejeu pong sur COPIE, jamais sur
  l'archive. (6) Doute de périmètre => STOP et question dans le rapport.
success_criteria: >-
  (a) cause de FAIL/attempts:0 nommée fichier:ligne avec preuve ; (b) rejeu pong via
  driver => attempts>=1 + ligne télémétrie ; (c) test négatif présent et RED sur
  l'ancien code (montré), GREEN sur le nouveau ; (d) zéro régression sur la suite
  post-M1 (référence relevée au lancement) ; (e) git diff ne touche que driver.py + tests.
tests_oracles: >-
  .venv312/Scripts/python.exe -m pytest scripts/forge/tests/ -q · git status --porcelain ·
  rejeu driver sur copie des données pong · sorties RED/GREEN réelles collées.
final_report: >-
  software/evidence/claim séparés, claim_verdict: NO_CLAIM_ALLOWED, OK/FAIL/BLOCKED
  uniquement. Contenu : diagnostic sourcé · RED/GREEN collés · critères (a)→(e) un par
  un · git status/diff finaux · section skipped_validation explicite.
output_contract: >-
  {resume_1_phrase, diagnostic: {fichier_ligne, preuve}, red_output, green_output,
  criteres_a_e: [{critere, preuve}], rejeu_pong, git_status_final, git_diff_stat,
  fichiers_modifies: [], skipped_validation: [], software_verdict, evidence_verdict:
  MECHANICAL_VALIDATION_ONLY, claim_verdict: NO_CLAIM_ALLOWED}.
skill: aucun
plugin: aucun
delegation_context: >-
  JALON 0 décision ④ (vue H-bis) — brouillon go Pierre 2026-07-26, spawn SOUMIS À
  RATIFICATION. En amont : M1 télémétrie d'échec (dépendance dure). En aval : profil
  standard interprétable, learning étape 2 débloquée, réveil DR-04 possible.
```

# V2_VALIDATION — l'oracle honnête du Studio V2

*2026-09-02 · établi après l'étape 9. **Aucun test supprimé.** Chaque échec porte une catégorie et
une raison identifiable.*

Trois catégories, et trois seulement :

```
PASS                        la propriété est vérifiée en V2
INTENTIONALLY_OUT_OF_SCOPE  le test porte sur un artefact V1 que nous avons décidé de ne pas migrer
BLOCKED                     le test porte sur une propriété encore requise, mais non satisfaite
```

> **Règle : aucun test n'est supprimé pour faire passer le compteur.** S'il est V1-only, il est
> classé. S'il teste une propriété encore requise, il est réparé. S'il révèle une dépendance
> manquante, il reste `BLOCKED`.

---

## A · `lab/agent_policy` — **fermé : HORS PÉRIMÈTRE V2**

Mesure de la chaîne de consommation en V2 :
```
declaration_readers.mjs        appelants : 0
   mentions restantes : son propre test · un commentaire de wiremap_nav.mjs · son propre manifeste
wiremap_nav.mjs                appelants : 0        (déjà classé SORTANT au contrôle d'orphelins)
declaration_watchlist.json     lu par : declaration_readers.mjs, et lui seul
```

> **La chaîne est refermée sur elle-même.** `declaration_readers.mjs` est un capteur qui mesure des
> déclarations et que **personne n'appelle** dans le chemin d'exécution V2. Sa dépendance à
> `lab/agent_policy` n'est donc pas active.

**Décision : `lab/agent_policy` reste hors périmètre V2. Aucune copie provisoire.** Le capteur, lui,
est conservé (règle : conservation jusqu'à preuve d'inutilité) — mais il est **orphelin**, et c'est
écrit ici plutôt que découvert plus tard.

## B · `lab/workflow_lab` — **fermé : hors périmètre, avec une nuance**

Les 5 références se répartissent en deux natures :
```
2  commentaires de PROVENANCE   « Promu depuis lab/workflow_lab/WFL-02/shared/… »   -> historique
3  règle de REFUS               run_real._STEP_DISALLOWED :
                                "Read(lab/workflow_lab/**/control/**)"              (Pierre 2026-07-22)
```

> La troisième n'est pas un chemin dont V2 a besoin : c'est un **interdit**. Il ne peut que
> sur-refuser, jamais sous-refuser — **le conserver est sans risque, le retirer en aurait un.**

**Décision : hors périmètre comme surface, garde conservée telle quelle.**
⚠ **À retenir** : si une branche de contrôle est un jour créée en V2 sous un autre chemin,
**cet interdit ne la couvrira pas** et devra être re-pointé.

## C · `games/` → `GAMES/` — **fait, et l'assertion tient**

Traité comme `lab/` : chemins migrés, constats datés préservés.
```
418 remplacements · 93 fichiers   (.py .mjs .json .yaml .gd)
games/ ACTIF restant : 0
games/ dans les .md  : 3   — conservés, trace historique
```

**Un piège évité, et c'est la raison de ne pas remplacer aveuglément :**
```python
data.get("games")    # clé de SCHÉMA du manifeste worldscan — RIEN à voir avec le dossier
```
La renommer aurait cassé le contrat de `s2-worldscan`. Seules les **formes de chemin** ont été
migrées ; la clé de schéma est intacte, vérifié après coup.

---

## D · Les 56 échecs, classés

| n | cause mesurée | catégorie | traitement |
|---|---|---|---|
| **51** | `FileNotFoundError` — run_dirs V1 (`p1_alpha`, `kitten_clicker`, `pong_r2`…), `.claude/tasks.json`, corpus `lab/` | `INTENTIONALLY_OUT_OF_SCOPE` | artefacts non migrés **par décision**. Les tests restent, déclarés |
| **6** | `git hash-object` échoue — **V2 n'est pas un dépôt git** | **`BLOCKED`** | voir ci-dessous : c'est une décision, pas un oubli |
| **3** | `assert 'scripts/council.py' in set()` · `claude_proxy.py` | `INTENTIONALLY_OUT_OF_SCOPE` | hors périmètre ratifié |
| **2** | `périmètre citant des chemins absents : ['EVIDENCE/bundles/asset_lessons', …]` | `BLOCKED` *(léger)* | surfaces qui n'existeront qu'après le premier run d'assets — **pas un défaut, un état** |
| **~19** | binaires/environnement absents (Blender, Godot), harnais e2e de jeux non migrés | à trancher | **lesquels sont réellement requis par une capacité V2 ?** |

### Le groupe git — la question à trancher, pas à contourner
Six tests (`evidence_seal_*`, `commit_scope_guard`, `reference_guard`) scellent des preuves via
`git hash-object`. V2 **n'est pas un dépôt git**.

> Ce n'est pas « un vieux test à ignorer ». Ou bien **V2 exige git** — et alors la validation doit
> l'initialiser, et ces 6 tests redeviennent des oracles ; ou bien **V2 n'exige pas git** — et alors
> le sceau de preuve doit reposer sur autre chose, ce qui est un **changement de mécanisme de
> preuve**, pas un reclassement de test.

**Je ne tranche pas : `git init` en V2 est un acte structurel et durable.** Il reste `BLOCKED`.

---

## E/F · Validation ciblée — état actuel

```
PASS
  forge.* importables .......................... 50 / 50
  REPO_ROOT · CONTRACTS_DIR · FORGE_ROLES ...... résolus
  KB_CATALOG · oracles.json · standard/ ........ résolus
  knowledge_base ............................... 50 entrées · 26 propositions
  contrats d'agent ............................. 28 lus
  .claude/settings.json ........................ 7 références, 0 fantôme
  TOOLS/observer ............................... 43 entrées
  GAMES/pong capture_browser ................... status=OK (volet mesuré)
  lots de session en V2 ........................ 67 tests verts
  games/ actif ................................. 0
  lab/ actif ................................... 0  (55 résidus, tous classés)

BLOCKED
  dépôt git V2 ................................. décision Pierre
  binaires Blender / Godot ..................... quelles capacités V2 les exigent ?
  EVIDENCE/bundles/asset_lessons ............... n'existera qu'au premier run d'assets

INTENTIONALLY_OUT_OF_SCOPE
  54 tests ancrés sur des artefacts V1 non migrés — déclarés, jamais supprimés
```

```
status_by_surface:
  A_agent_policy:      TESTED   # 0 appelant -> hors périmètre, sans copie
  B_workflow_lab:      TESTED   # 2 provenance + 3 interdit -> garde conservée
  C_games_actif_zero:  TESTED   # 418 migrations, clé de schéma intacte
  D_classification:    TESTED   # 56 répartis, 0 supprimé
  E_git_v2:            BLOCKED  # décision structurelle
  F_suite_complete:    BLOCKED  # après E, pas avant
```
`software_verdict: OK` · `evidence_verdict: MECHANICAL_VALIDATION_ONLY` ·
`claim_verdict: NO_CLAIM_ALLOWED` · `no_global_ready_verdict: true`

**Pacman** : `00_CHARTER/` · `09_WIREMAP/` — absents du HEAD, non copiés, non reconstitués.
**Q2 / R8 : intactes.**

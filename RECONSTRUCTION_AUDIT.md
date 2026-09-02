# AUDIT DE RECONSTRUCTION — Studio V2

- **Date** : 2026-09-01
- **SOURCE_REPO** : `C:\TACTICAL_CHESS_STUDIO` · `master` · HEAD `d6c2510c`
- **TARGET** : `C:\Users\Studio-Dev\Desktop\Studio`
- **Runtime réel** : Claude Opus 5 (Claude Code). `GPT-5.6-Codex` demandé, **indisponible** dans
  cette session — signalé conformément à `report_actual_runtime: true`.
- `claim_verdict: NO_CLAIM_ALLOWED` · aucun verdict global ready/not-ready.

```
Studio/
├── MASTER_SCHEMA.html      1 fichier    — un seul document maître
├── FORGE/                  468 fichiers — une seule Forge (forge/ + control_plane/ + openclaw/)
├── knowledge_base/         129 fichiers — une seule KB
├── GAMES/                  BLOCKED      — aucun jeu : pas de planning ratifié
├── TOOLS/                  41 fichiers  — observer/ + fiche des outils externes
├── .claude/                28 fichiers  — la porte (exception mécanique, cf. §5)
├── PROVENANCE.md
└── RECONSTRUCTION_AUDIT.md
```
**669 fichiers** au total, contre **7 685** suivis dans le repo source (**8,7 %**).

---

## 1. Ce qui a été prouvé avant d'être copié

| surface | producteur | consommateur | preuve d'exécution | dernière activité | statut |
|---|---|---|---|---|---|
| **Forge** `scripts/forge/` | `run_real.py` → `ForgeDriver` | `dispatch` → `contract` → `runtime` → `oracles` → `verdict` → `verify_run` | 12 `verdict.json` signés HMAC ; `verify_run` exit 0 `AUTHENTIQUE` ; **un run est en cours pendant cet audit** (§7) | **2026-09-01** | IMPLEMENTED |
| ancienne factory `studio/factory/` | — | 1 seul : `scripts/cockpit_server.py:85` | aucune | 2026-06-27 | PASSIVE |
| ancienne factory `studio_core/` | — | **0 importeur Python** | aucune | 2026-06-26 | PASSIVE / orphelin |
| **KB** `knowledge_base/` | `kb_proposal.py` (propose-only) | `contract.py`, `driver.py`, `preflight.py`, `search_usage.mjs`, `reuse_ratio.mjs`, `learning_metrics.mjs`, `scripts/observer/` | `catalog.json` 65 Ko, 18 entrées `provenance_internal` (leçons ratifiées) | 2026-08-31 | IMPLEMENTED |
| `llm-lego/library/*-knowledge-base.json` | — | `llm-lego/knowledge-validate.mjs` seulement | aucune | 2026-07-24 | PASSIVE |
| `lab/agent_registry/`, `lab/agent_policy/` | — | lane STUDIO **gelée** | — | — | legacy de fait |

**Conclusion appliquée** : une seule Forge copiée, une seule KB copiée. Les concurrentes ne sont
pas dans le V2 — et ne sont pas supprimées de la source.

## 2. La boucle de connaissance — vérifiée, pas supposée

La cible demandée était :
`Observation → Lesson candidate → HumanGate → Ratified knowledge → Controlled injection`.

Elle **existe et a déjà tourné 18 fois** (mesure du 2026-09-01 au handoff) :

| maillon | mécanisme réel copié | emplacement V2 |
|---|---|---|
| Observation | `forge/learning_hook.py`, `forge/studio_link.py`, `TOOLS/observer/` | FORGE + TOOLS |
| Lesson candidate | `forge/learning_memory.py` — `lesson.v2` : `cause` est un **champ**, pas de la prose | FORGE |
| HumanGate | `forge/gate.py` + `forge/kb_proposal.py` **propose-only** → `knowledge_base/proposals/` | FORGE + knowledge_base |
| Connaissance ratifiée | `knowledge_base/catalog.json` (une fiche n'y entre que ratifiée) | knowledge_base |
| Injection contrôlée | `forge/contract.py` — `KB_CATALOG` = source unique servie aux agents ; une proposition **n'est jamais servie** | FORGE |

Aucun répertoire `LESSONS/`, `MEMORY/` ou `KNOWLEDGE/` n'a été créé : les quatre états sont des
**statuts dans un seul magasin**, pas quatre dossiers. C'est déjà la simplification demandée.

Goulot mesuré, non résolu : **18 ratifiées sur 326 leçons**. Le point de friction est humain.

## 3. ✅ RÉSOLU — `KB/` renommé en `knowledge_base/` (2026-09-01, décision Pierre)

Le conflit initial : `forge/contract.py:310` fait `KB_CATALOG = REPO_ROOT / "knowledge_base" /
"catalog.json"`, et **167 références** à ce nom existent dans le code Forge hors tests. Avec un
dossier nommé `KB/`, la Forge du V2 ne trouvait pas sa KB (`existe ? False`).

Option retenue par Pierre, la moins chère des trois : **renommer le dossier**. Aucune ligne de
code touchée — le code fait autorité (« si les docs contredisent le code, le code gagne »).
Écartées : jonction NTFS (couplage invisible, `déclaré ≠ exécuté`) et patch de la constante
(modification de code → gate + non-régression).

Vérifié après renommage, exécuté dans le V2 :
```
REPO_ROOT      : C:\Users\Studio-Dev\Desktop\Studio
KB_CATALOG     : ...\Studio\knowledge_base\catalog.json   existe : True
KB_PROPOSALS   : ...\Studio\knowledge_base\proposals      existe : True
catalogue lu   : 50 entrées          propositions : 26 fichiers .yaml
kb_proposal.DEFAULT_KB_ROOT : existe True   ·   kb-validate.mjs : True
forge.driver   : import OK
```
Le catalogue est **lu et parsé**, pas seulement trouvé. La surface KB passe de BLOCKED à OK.

## 4. Ce qui a été vérifié mécaniquement

| contrôle | commande | résultat |
|---|---|---|
| Fidélité des copies | `cmp` sur chaque fichier | **637 comparés, 0 différence** |
| Cohérence du paquet Forge | `import forge.{contract,dispatch,driver,verdict,verify_run,run_real}` depuis `FORGE/` | **import OK** |
| Résolution des modèles | `control_plane.registry.get_model_for_role('director')` | `qwen2.5-14b-instruct` / provider `lmstudio` — **lu depuis `FORGE/openclaw/`** |
| Chemin KB | `forge.contract.KB_CATALOG.exists()` | **True** après renommage (§3) |

Le nid `FORGE/forge/` n'est pas cosmétique : il préserve le nom de paquet `forge` et fait
résoudre `REPO_ROOT` (`parents[2]`) sur la racine du Studio V2. Vérifié.

## 5. Exception à la structure en 5 surfaces : `.claude/`

Une seule, et elle est mécanique. La porte de la Forge (`pretool_forge_guard.py`, fail-closed,
invariant ADR-002 « aucun sous-agent sans contrat validé ») n'est exécutée par Claude Code que
si elle se trouve dans `.claude/` à la racine du dossier de travail. La placer sous `TOOLS/` la
rendrait **inerte tout en ayant l'air présente**. 28 fichiers : `settings.json`, 5 hooks Forge/git,
`skills/forge/skill.md`, 17 types d'agent, 4 fichiers de règles.

## 6. NOT COPIED — et pourquoi (aucune archive dans le V2)

| écarté | volume | raison |
|---|---:|---|
| `lab/` | 3 779 | sorties de runtime : 95 run_dirs, 47 dossiers d'évidence, rapports |
| `games/` | 1 253 | **BLOCKED** — pas de planning ratifié (`GAMES/PLAN_STATUS.md`) |
| `docs/` sauf le master schema | 534 | 3 propositions de master schema concurrentes, ~40 docs `PROPOSED`, audits datés |
| `00_STUDIO_CONTROL/` | 289 | génération de docs précédente ; ses 2 points d'entrée pointent vers **5 fichiers absents** |
| `studio_brain/` | 60 | anciens handoffs / context docs — exclus par la mission |
| `scripts/` hors forge+observer | 641 | lane STUDIO gelée, couche council/cockpit gelée, expérimentations |
| `llm-lego/` | 352 | laboratoire séparé, sans consommateur Forge |
| `src/`, `ml/`, `tests/`, `bench/`, `tools/` | ~340 | **ROCKY — abandonné**, exclu par décision |
| `studio/`, `studio_core/`, `governance/`, `memory_core/`, `schemas/` | ~150 | anciennes factories et control-plane sans consommateur vivant |
| `contracts/archive/` (dans forge) | 36 | archive explicite — pas d'archive dans le V2 |
| `catalog.broken.json` | 1 | fichier cassé nommé comme tel |
| `requirements.txt` | 1 | décrit la lane ML (torch/pandas/numpy) et **ne contient même pas PyYAML**, seule dépendance tierce réelle de la Forge |

Aucune suppression dans le repo source. « Non copié » ≠ « supprimé ».

## 7. ⚠ Le repo source a changé pendant la mission — pas par moi

`git status` : **69 lignes avant → 70 après**. La ligne nouvelle est `?? games/p3_alpha/`.

Preuve que ce n'est pas cette mission :
- 14 fichiers de jeu écrits dans `games/p3_alpha/` entre **14:20:56 et 14:24:55**
  (`economy.js`, `engine.js`, `render.js`, `harness.js`, `e2e.mjs`, `solvability.mjs`…).
- `lab/forge_runs/p3_alpha/` écrit à **14:30:39** : `state.json`, `run.log`,
  `context/prompt_s9-build_a3.txt`, `s9-build.manifest.jsonl` — **une étape s9-build, tentative 3**.
- **12 processus `claude.exe` + 4 `node.exe`** actifs à la mesure.
- Mes seules écritures sont sorties vers le Bureau ; mes seuls appels Python sont deux
  `python -c "import ..."` avec `PYTHONDONTWRITEBYTECODE=1`, dont le cwd était le V2.

**Un run Forge d'une autre session tourne en ce moment sur `p3_alpha`.** Le handoff l'annonçait
(« rouge `p3_alpha` hors périmètre, autre session »). L'invariant `status_before == status_after`
est donc **violé par un tiers**, pas par cette mission — et il ne pouvait pas être tenu.

Conséquence à connaître : `HEAD` n'a pas bougé, mais le working tree est vivant. Toute mesure
prise ici porte l'instant `2026-09-01 ~14:30`, pas « l'état du dépôt ».

## 8. UNKNOWN / BLOCKED

| sujet | statut | pourquoi |
|---|---|---|
| Planning de développement des jeux | **BLOCKED** | curriculum PROPOSED jamais ratifié (0 occurrence au decision-log) ; `P5-jeu-test` `etat: BLOQUE` |
| Import de tout jeu | **BLOCKED** | dépend du planning |
| Chemin `KB/` vs `knowledge_base/` | **RÉSOLU 2026-09-01** | renommé ; catalogue lu, 50 entrées (§3) |
| `FORGE_SYSTEM_CONTRACT.yaml` comme MASTER SCHEMA exécutable | **BLOCKED** | statut `PROPOSED` alors que du code de production le lit |
| Suite de tests du V2 | **UNKNOWN** | 237 fichiers de test copiés, **jamais exécutés** (§9) |
| Sort de `studio/factory/`, `studio_core/` dans la source | **BLOCKED** | preuve d'inutilité ≠ autorisation de suppression |

## 9. skipped_validation

- **Aucune suite de tests exécutée**, ni dans la source ni dans le V2. Dans la source : une passe
  pytest y écrit `__pycache__`/`.pytest_cache` (interdit). Dans le V2 : la suite référence des
  chemins repo (`knowledge_base/`, `lab/`, `games/`) absents ou renommés — un résultat rouge ne
  dirait rien sur la Forge, seulement sur le déménagement. **Le V2 n'est pas prouvé exécutable.**
- `studio_selfaudit.mjs` non lancé : il **réécrit** `docs/forge/STUDIO_STATUS.generated.md`.
- Aucun run Forge lancé — et un run tiers occupe déjà la machine (§7).
- Volume en octets non mesuré (`du` dépasse 2 min sur `node_modules`/`target`/`.venv312`).

## 10. RISKS

1. **Le V2 n'est toujours pas prouvé exécutable.** §3 est levé (la Forge trouve et lit sa KB),
   mais aucune suite de tests n'a tourné : rien d'autre n'est identifié comme cassé, rien n'est
   prouvé vert.
2. **`.claude/hooks` + `FORGE/forge` : câblage à vérifier.** Le guard fait
   `from forge.hook_guard import ...` ; il faut que `FORGE/` soit sur le `sys.path` du V2.
   Non testé — la porte pourrait échouer **fail-closed** (refus systématique), ce qui est le bon
   sens du défaut, mais bloquerait tout spawn.
3. **`.claude/settings.json` copié tel quel** : ses `permissions.allow` visent
   `studio_core/**` et `studio/openclaw-workspace/**`, absents du V2. Inoffensif, mais c'est de
   la configuration morte dès le premier jour.
4. **Le repo source est vivant** (§7) : toute reprise doit re-mesurer, pas se fier à cet audit.
5. **`openclaw/providers.yaml` décrit des services de la lane gelée** (autopilot:7331,
   openclaw:18789, canvas:8766). Le registry n'en lit que `models[].roles` et `provider`, mais le
   fichier raconte une infrastructure qui n'est plus celle du studio.
6. **`git` absent du V2** : 669 fichiers sans historique ni protection. Un `git init` est un
   geste Pierre, pas une initiative d'agent.

---
```
software_verdict: OK        (5 surfaces créées · 637 copies vérifiées bit-à-bit · paquet Forge importable)
evidence_verdict: MECHANICAL_VALIDATION_ONLY
claim_verdict:    NO_CLAIM_ALLOWED
```
Aucun verdict global ready / not-ready. Le V2 est **assemblé et vérifié en fidélité**, il n'est
**pas prouvé exécutable** : voir §3, §9 et §10.

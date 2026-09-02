# TOOLS — outils dont l'utilité actuelle est démontrée

Règle appliquée : **un outil n'est copié que si son consommateur ou son producteur est prouvé
dans le workflow Forge.** `scripts/` du repo source contient 681 fichiers ; 40 ont été copiés.

## Copiés

### `observer/` — 40 fichiers · source `scripts/observer/`
```
name:          Observer
source:        C:\TACTICAL_CHESS_STUDIO\scripts\observer\
purpose:       mesure du workflow réel (événements, faits, vues, cockpit, drifts, fiches agents)
consumer:      lit lab/forge_runs/, lab/reports/, knowledge_base/ ; produit lab/reports/observer/**
used_by:       lien Forge prouvé -> `from forge.anonymize_session_paths import ...`
required_for:  P0/P3/P4 du planning ratifié (planning.yaml) ; c'est l'instrument qui a
               mesuré les drifts cités dans GAMES/PLAN_STATUS.md
status:        IMPLEMENTED · dernier commit 2026-08-20
copy_candidate: OUI
evidence:      import direct d'un module Forge + 20 références à knowledge_base dans
               system_roadmap.py / pedagogy.py / system_artefacts.py / command.py
```

### Gate de pilotage — `../.claude/` (28 fichiers)
Le garde-fou de la Forge **ne peut pas vivre ailleurs** : Claude Code ne lit les hooks que
dans `.claude/` à la racine du dossier de travail. C'est la seule exception à la structure
en 5 surfaces, et elle est mécanique, pas esthétique.

| fichier | rôle | preuve |
|---|---|---|
| `.claude/settings.json` | déclare les hooks + permissions deny | `PreToolUse` sur `Task`/`Agent` -> `pretool_forge_guard.py` |
| `.claude/hooks/pretool_forge_guard.py` | **la porte** — aucun sous-agent Forge sans contrat validé, fail-closed | ADR-002 ; `from forge.hook_guard import hook_decision` |
| `.claude/hooks/posttool_forge_executed.py` | trace d'exécution après spawn | pendant du guard |
| `.claude/hooks/pretool_agent_classify.py` | classification d'agent au spawn | déclaré dans settings.json |
| `.claude/hooks/pretool_git_guard.py` | garde git | déclaré dans settings.json |
| `.claude/hooks/agent_authority_allowlist_v0.json` | table d'autorité lue par le guard | `self.allowlist_path` |
| `.claude/skills/forge/skill.md` | surface de **pilotage** de la Forge | `FORGE_SYSTEM_CONTRACT.yaml` : « Interface de pilotage » |
| `.claude/agents/` (17) | types d'agent = l'autorité (doctrine ratifiée) | lus par le guard (`self.agents_dir`) |
| `.claude/rules/` (4) | règles par surface (rust, python-ml, godot, tests) | chargées par le runtime |

**Non copiés depuis `.claude/hooks/`** : `pre-commit`, `validate-commit-msg`,
`session-start.sh`, `subagent-*.sh`, `post-compact.sh`, `stop-failure.sh`,
`instructions-validate.sh` — hooks de session/git liés au repo source et à son historique,
sans rôle dans la fabrication d'un jeu.

## Non copiés — outils **externes**, à installer, pas à migrer

Ce ne sont pas des fichiers du repo : ce sont des binaires et des services. Leur présence est
une **précondition d'exécution** du Studio V2, pas un objet de copie.

| outil | rôle prouvé | où c'est câblé |
|---|---|---|
| **`claude` CLI (headless)** | **le seul exécuteur LLM des étapes Forge** — `claude -p --output-format json` | `forge/run_real.py:79` (`shutil.which("claude")`) ; timeouts + kill d'arborescence FIR-01 |
| **LM Studio** (`127.0.0.1:1234`) | héberge Qwen2.5 — worker World Scan, red-team s11 indépendante, specs asset | `FORGE/openclaw/providers.yaml` -> `control_plane.registry` |
| **Qwen2.5-14B-instruct** | modèle des rôles `director` / `charter_generation` | `FORGE/openclaw/capabilities.yaml` (vérifié : `get_model_for_role('director')` -> `qwen2.5-14b-instruct`, provider `lmstudio`) |
| **Playwright** | harness e2e + oracle produit (capture réelle) | `forge/driver.py`, `forge/product_oracle.py`, `forge/static_oracles.py` |
| **Godot 4.6.3** | runtime des jeux 3D/2D + capture GPU | contrats `s9-build-godot*.yaml` ; **fenêtre GPU obligatoire** (`--headless` rend une texture nulle) |
| **Node.js** | exécute tous les oracles `.mjs` et `node --test` | KB : `kb-validate.mjs`, `search.mjs` ; Forge : `studio_selfaudit.mjs`, `solvability_*.mjs` |
| **Python 3.12 + PyYAML** | runtime de la Forge | voir ci-dessous |

### Dépendances Python réelles de la Forge — **mesurées, pas héritées**
Scan des `import` de `scripts/forge/*.py` : hors bibliothèque standard, **une seule** dépendance
tierce → **`yaml` (PyYAML)**. Plus les paquets internes `forge` et `control_plane`.

> Constat : `requirements.txt` du repo source liste `torch`, `pandas`, `numpy`, `sympy`,
> `networkx`, `Jinja2`… — ce sont les dépendances de la **lane ROCKY (ML)**, et il **ne
> contient même pas PyYAML**. Ce fichier n'a donc pas été copié : il ne décrit pas la Forge.

## Non copiés — le reste de `scripts/` (641 fichiers)

| écarté | raison |
|---|---|
| `scripts/studioV2/` (89) | lane STUDIO **gelée** par ratification (2026-07-19) |
| `scripts/council*.py`, `scripts/cockpit_server.py`, `scripts/canvas_gateway.py`, `scripts/claude_proxy.py`, `scripts/director.py`, `scripts/autopilot*`… | couche kaizen/council/cockpit — gelée au triage v2 ; `cockpit_server.py` est de plus le **seul consommateur** de l'ancienne factory `studio/factory/` |
| `scripts/phase*_tests/`, `scripts/quality_sensor/`, `scripts/uxpilote/` | expérimentations sans consommateur Forge |
| `scripts/rocky_play.py`, `bench/`, `tools/` (Stockfish, UCI) | **ROCKY — abandonné**, hors périmètre par décision |
| `scripts/sync_memory.py`, `scripts/studio_meta.py`, `scripts/ingest_event.py`, `scripts/state_validator.py`… | alimentent le control-plane de la lane gelée |

---
`claim_verdict: NO_CLAIM_ALLOWED` — cette fiche établit des liens de consommation mesurés,
elle ne prouve pas qu'un outil fonctionne dans le V2.

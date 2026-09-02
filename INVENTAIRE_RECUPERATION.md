# INVENTAIRE DE RÉCUPÉRATION V1 → V2

*2026-09-02 · **MESURE UNIQUEMENT** · aucun fichier copié, aucun fichier modifié.
Source : `C:\TACTICAL_CHESS_STUDIO`, HEAD **`58095ba9`** (2026-09-02 13:34) — celui qui porte les
huit lots. Cible : `C:\Users\Studio-Dev\Desktop\Studio`.*

> **Principe** : on ne migre pas le passé ; on migre ce qui doit continuer à vivre.
> **Et : ce qui existe et fonctionne se copie, ne se reconstruit pas.**

---

## 0 · Le point de départ n'est pas une page blanche

**V2 contient déjà une copie partielle**, faite avant les audits. Mesuré :

| surface V2 | fichiers | état |
|---|---|---|
| `FORGE/forge/` | 463 | copie **datée** — voir §1 |
| `FORGE/control_plane/` | 2 | **à retirer** (exclu par décision) |
| `knowledge_base/` | 129 | 12 manquants |
| `TOOLS/` | 41 | `README.md` + `observer/` |
| `.claude/` | 28 | **incohérent — voir §3, c'est le point dangereux** |
| `GAMES/` | 2 | deux documents, **aucun jeu** |
| `EVIDENCE/` | — | **absente** |

L'inventaire n'est donc pas « quoi copier » mais **« qu'est-ce qui est déjà là, est-ce à jour, et
qu'est-ce qui manque ou ne devrait pas y être »**.

---

## 1 · `FORGE/forge/` — la copie est datée d'avant `feeb29cb`

```
463 fichiers en V2   ·   800 en V1 (dont __pycache__ et .pytest_cache)
451 identiques au bit près
 12 DIVERGENTS
 44 manquants (hors __pycache__)
```

### Les 12 divergents
| fichier | origine de l'écart |
|---|---|
| `contract.py` · `contracts/SCHEMA.md` · `driver.py` · `run_real.py` · `verify_run.py` · `product_oracle.py` · 3 tests | **les huit lots de cette session** — présents au HEAD `58095ba9` |
| `dispatch.py` · `oracles.json` | **autre session, NON COMMITÉS** — n'existent qu'en arbre de travail |
| **`pair_preflight.py`** | **la copie V2 est antérieure à `feeb29cb`** — ce fichier a changé dans ce commit |

> `pair_preflight.py` date la copie : **V2 vient d'un HEAD antérieur au 2026-09-01**. Toute
> hypothèse « V2 = V1 moins ce qu'on a exclu » est fausse.

### Les 44 manquants
| catégorie | n | décision |
|---|---|---|
| modules et tests des huit lots (`amendment_log` · `emitter` · `consumption` + 5 tests) | 8 | **à copier** — ils sont au HEAD |
| `tests/test_micro_sonde_profile.py` · `tests/test_mutation_path_repo_relative.py` | 2 | 1 vient de l'autre session (non commité) · 1 à vérifier |
| `contracts/archive/` | 26 | **ne pas copier** — archive |
| `.pytest_cache/` | 5 | **ne pas copier** — bruit |
| `blender.config.json` · `godot.config.json` | 2 | **à copier, mais PAS tels quels** — §5 |
| **`.forge_key`** | 1 | ⛔ **NE JAMAIS COPIER.** V2 génère la sienne, jamais versionnée |

---

## 2 · `knowledge_base/` — 12 manquants, tous récents

```
V2 129   ·   V1 141
manquants : 10 propositions `forge.*.yaml` (autre session, NON COMMITÉES) + catalog.broken.json + 1
```
**À copier** : les propositions **au HEAD** seulement. `catalog.broken.json` : **ne pas copier**
(son nom dit ce qu'il est). Rappel R7 : une proposition n'est jamais servie — seul le catalogue
ratifié l'est.

---

## 3 · ⚠ `.claude/` — LE point dangereux de l'inventaire

`V2/.claude/settings.json` **déclare des hooks qui n'existent pas en V2** :

```
déclarés par settings.json          présents en V2/.claude/hooks
  pretool_forge_guard.py       ✔      pretool_forge_guard.py
  pretool_agent_classify.py    ✔      pretool_agent_classify.py
  posttool_forge_executed.py   ✔      posttool_forge_executed.py
  pretool_git_guard.py         ✔      pretool_git_guard.py
  session-start.sh             ✘
  subagent-start.sh            ✘
  subagent-stop.sh             ✘
  stop-failure.sh              ✘
  pre-compact.sh               ✘
  post-compact.sh              ✘
```

> **Une configuration qui référence six exécutables absents a été copiée telle quelle.** Elle n'a
> jamais tourné en V2 — mais elle ferait croire, à la lecture, que la chaîne de gardes est en place.
> C'est exactement le motif que ce studio a appris à ne pas croire : **déclaré ≠ exécuté.**

Manquent aussi : **38 skills sur 39** (seul `forge` est là), `pre-commit` et `validate-commit-msg`
(hooks git), `launch.json`, 3 `templates/`.
**Présents et complets** : les **17 agents**.

`settings.local.json` et `HUMAN_GIT_OVERRIDE.json` : **ne pas copier** — local au poste et à V1.

**À copier** : les 10 hooks manquants · les skills **réellement invoquées** (routing de `CLAUDE.md`
+ legacy gelés à écarter) · `launch.json`.
**À vérifier après copie, en une commande** : chaque `command` de `settings.json` pointe un fichier
qui existe.

---

## 4 · Ce qui est déjà bon — et ce qui ne doit pas rester

| surface | verdict |
|---|---|
| `TOOLS/observer/` | **conserver** — Observer est identifié comme outil nécessaire |
| **`FORGE/control_plane/`** | ⛔ **RETIRER de V2** — 2 fichiers ; Control Plane exclu par décision |
| `FORGE/openclaw/` | déjà retiré lors d'une passe précédente — rien à faire |
| `EVIDENCE/` | **à créer** — surface cible de `J1` (journal d'amendements) |

---

## 5 · Ce qu'il faudra corriger à l'arrivée — déjà mesuré, rien de neuf

| # | correction | volume mesuré |
|---|---|---|
| A | constantes de chemin `parents[N]` → relatives au paquet | **9 occurrences / 6 fichiers**, dont 3 `sys.path` |
| B | surfaces `lab/forge_runs`, `lab/forge_evidence`, `games/` → `EVIDENCE/`, `GAMES/` | **18 occurrences / 13 fichiers** |
| C | `REPO_ROOT = parents[2]` → `parents[1]` (layout L1 : `Studio/forge/`) | ~40 décréments |
| D | isolation des tests | 43 / 68 |
| E | `godot.config.json` porte un **chemin absolu vers le Bureau** | 1 valeur, à externaliser |
| F | générer un `.forge_key` **propre à V2**, jamais versionné | 1 |

**Rappel du layout ratifié** : `Studio/forge/`, pas `Studio/FORGE/forge/` — mesuré comme le seul
des deux à satisfaire les 7 critères (`FORGE/forge/` donne *pytest vert / exécution réelle cassée*).
**La copie actuelle est au mauvais emplacement.**

---

## 6 · Jeux — proposition, décision à toi

Volume total `games/` : **291 Mo**. Les jeux du rail : **~17 Mo**.

| rail | jeu V1 | fichiers | pourquoi |
|---|---|---|---|
| 1 PONG `FROZEN_HUMAN` | `pong` | 130 | **benchmark de régression** — et **le seul jeu portant `capture_browser.mjs` / `capture_godot.mjs`**, mesurés verts (W-2) |
| 2 SNAKE `CLOSED_WITH_OBJECTION` | `snake` | 230 | l'objection est une donnée, elle voyage avec le jeu |
| 3 BREAKOUT `CLOSED` | `breakout` + `breakout_v2` | 15 + 269 | deux lignées : à trancher |
| 4 TETRIS `CIBLE` | `tetris` | 173 | le code existe déjà |
| 6 PAC-MAN `CIBLE` | `pacman` | 557 | verdict signé, ratifié ; **et l'un des 2 runs à jointure TENUE** |
| 7 BOMBERMAN `CIBLE` | `bomberman_3d` | 254 | 88 fichiers zone tests ratifiée |
| — GRID NAV `FAIT` | `p5_gridnav` · `grid_nav_probe` | 10 | petits, déjà faits |
| 5 COOKIE CLICKER | **aucun dossier de ce nom** | — | `INFERENCE / claim: BLOCKED` — **ne pas résoudre par ressemblance de nom (R8)** |

**Non repris** : les 28 autres dossiers de `games/` (probes, `_legacy`, `_r1`/`_r2`, `p*_alpha/beta`
de campagne). **Q5 — qui décide du prochain jeu — reste ouverte** ; ce tableau ne la tranche pas.

---

## 7 · Ce qui n'est pas repris, sans discussion
`autopilot.py` et lane STUDIO · `scripts/studioV2/` · Control Plane · OpenClaw · council ·
anciennes factories · MASTER_DOCS et archives · Rocky (`src/`, `ml/`, `bench/`) · `lab/` (sauf les
preuves qui deviennent `EVIDENCE/`) · `.forge_key` · caches.

---

## 8 · L'ordre que je propose — et rien avant ta validation

```
1. retirer FORGE/control_plane/                         (2 fichiers)
2. déplacer FORGE/forge/ → forge/                       (layout L1 ratifié)
3. rafraîchir les 12 divergents depuis le HEAD 58095ba9 — sauf dispatch.py et
   oracles.json, NON COMMITÉS : ils restent à leur version du HEAD
4. copier les 10 fichiers manquants légitimes (3 modules + 5 tests + 2 configs)
5. .claude : les 10 hooks, les skills utiles, launch.json — puis VÉRIFIER que
   chaque `command` de settings.json pointe un fichier existant
6. knowledge_base : les propositions au HEAD
7. créer EVIDENCE/ ; générer un .forge_key propre à V2
8. copier les jeux retenus (~17 Mo)
9. corriger A→F
10. valider V2 par des contrôles CIBLÉS (imports, chemins, un test par surface),
    JAMAIS en rejouant la suite de V1
```

```
status_by_surface:
  v2_is_not_empty:          TESTED   # 463 fichiers déjà copiés
  copy_predates_feeb29cb:   TESTED   # pair_preflight.py
  divergents:               TESTED   # 12, dont 2 non commités
  missing:                  TESTED   # 44, dont 8 légitimes
  settings_references_ghosts: TESTED # 6 hooks déclarés, absents
  layout_is_wrong:          TESTED   # FORGE/forge/ au lieu de forge/
  games_volume:             TESTED   # 291 Mo total, ~17 Mo retenus
  cookie_clicker:           NOT_FOUND # ne pas résoudre par le nom (R8)
  copie:                    BLOCKED  # aucune, en attente de validation
```
`software_verdict: OK` (inventaire) · `evidence_verdict: MECHANICAL_VALIDATION_ONLY` ·
`claim_verdict: NO_CLAIM_ALLOWED` · `no_global_ready_verdict: true`

**Aucun fichier copié, déplacé, supprimé ou renommé. Q2 / R8 : non touchée.**

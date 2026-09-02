# RÉCUPÉRATION V1 → V2 · EXÉCUTION DES ÉTAPES 1 À 10

*2026-09-02 · source **`58095ba9`** · **V1 non modifié** (vérifié après coup : seuls les 4 fichiers
de l'autre session restent en écart, comme avant).*

```
V2 : 16 Mo — forge 472 · GAMES 618 · knowledge_base 130 · .claude 62 · TOOLS 41 · EVIDENCE · control_plane 2
```

---

## ⚠ La correction qui compte : `control_plane` n'était PAS excluable

**Mon inventaire était faux sur ce point, et tu as ratifié l'étape 1 sur cette base.**

J'ai retiré `FORGE/control_plane/` (2 fichiers) comme prévu. La première validation d'import a
immédiatement échoué :

```
forge/contract.py:76   from control_plane.registry import get_model_for_role, get_provider_for_role
                       ModuleNotFoundError: No module named 'control_plane'
```

Mesure faite ensuite : `control_plane.registry` est **une dépendance vivante de la Forge**, pas un
résidu.

```
contract.py:666   resolve_runtime -> get_model_for_role(...)      ADR-002 gate 1, « jamais de modèle en dur »
contract.py:691   get_provider_for_role(...)
repair_dispatch.py · asset_producer/asset_dispatch.py · run_real.py:788 (get_reasoning_for_model)
```

> **Ce qui est exclu, c'est la LANE Control Plane** — l'application, son UI, son plan. **Pas
> `control_plane/registry.py`, que la Forge importe pour résoudre ses runtimes.** J'avais confondu
> les deux, et mon audit précédent sur `openclaw` (dont le chemin par défaut n'est effectivement
> jamais pris) m'avait rendu trop confiant.

**Les 2 fichiers ont été restaurés depuis le HEAD** (`__init__.py`, `registry.py`). Si tu veux
malgré tout les sortir, c'est un **lot séparé** : déplacer `registry.py` dans le paquet et corriger
6 fichiers — une modification de code, pas une correction de chemin.

---

## Ce que chaque étape a donné

| # | étape | résultat |
|---|---|---|
| 1 | retirer `control_plane` | fait **puis annulé** — voir ci-dessus |
| 2 | layout L1 | `FORGE/forge/` → **`forge/`**. ⚠ `FORGE` et `forge` **collisionnent sur Windows** (casse) : passage par un nom temporaire. `IO_CONTRACT.md` déplacé à la racine → `FORGE_IO_CONTRACT.md` |
| 3+4 | synchroniser depuis `58095ba9` | **472 fichiers écrits depuis le HEAD**, pas depuis l'arbre de travail. Vérifié : **0 divergent, 0 résidu**. `contracts/archive/` (26) et `.pytest_cache` exclus |
| 5 | `.claude` | **6 références fantômes retirées** de `settings.json` · **31 skills** copiées, **8 exclues** · `launch.json` + 3 templates · **vérification mécanique : 7 références, 0 fantôme** |
| 6 | KB | **130 fichiers au HEAD**, 0 résidu. Catalogue lu : **50 entrées**, 26 propositions |
| 7 | `EVIDENCE/` + clé | surface créée (`amendments/` + README) · `.forge_key` **générée pour V2** (`os.urandom(32)`, même primitive que `verdict`) · `.gitignore` posé |
| 8 | jeux | **618 fichiers, 4 Mo** (et non 17) — copiés **depuis le HEAD**, donc **sans les caches `.godot/` ni les `*.gd.uid`** |
| 9 | chemins | **A/C fait et validé · groupe B NON FAIT** — voir plus bas |
| 10 | validation ciblée | résultats ci-dessous |

### Étape 5 — pourquoi 6 hooks ont été retirés et non récupérés
Mesurés : les six hooks shell référencés (`session-start`, `subagent-start/stop`, `stop-failure`,
`pre-compact`, `post-compact`) parlent tous de surfaces que V2 n'a pas — `IMPROVEMENT_LEDGER`,
`lab/`, `ELO`, `cargo`, `.venv312`. **Les récupérer aurait réimporté les lanes V1 dans V2.**
Les 4 hooks Python (gardes ADR-002) étaient déjà là et sont conservés.

**8 skills exclues** : `autoloop` · `tick` · `sprint-plan` · `sprint-status` · `imp-readiness` ·
`council` (legacy gelés ratifiés 2026-07-19) · `monitor` (autopilot) · `openclaw-install` (OpenClaw).
Les 31 autres sont copiées — dont plusieurs citent encore `cargo` ou `IMPROVEMENT_LEDGER` dans leur
prose : **listées, non supprimées** (règle : conservation jusqu'à preuve d'inutilité).

### Étape 8 — ce qui n'a pas été copié, et pourquoi
`games/pacman/00_CHARTER/` et `games/pacman/09_WIREMAP/` sont **non suivis** en V1 : contenu réel,
jamais commité. **Non copiés** (garde-fou 1). Ils existent, ils sont nommés ici, à toi de décider.
Le reste des écarts disque/HEAD était **des artefacts ignorés** (`.godot/`, `*.gd.uid`) — d'où
4 Mo au lieu de 17.

`blender.config.json` et `godot.config.json` **ne sont pas au HEAD** (fichiers d'environnement
local, chemins absolus vers le Bureau). **Non copiés** — même régime que `.forge_key` : V2
configurera les siens.

---

## Étape 9 — fait, et ce qui reste

**Fait et validé :**
```
parents[2] -> parents[1]   22 occurrences · 21 fichiers   (racine forge/)
parents[3] -> parents[2]    4 occurrences ·  4 fichiers   (asset_producer/)
parents[3] -> parents[2]   69 occurrences · 63 fichiers   (tests/)
"scripts"/"forge" -> "forge" et sys.path : 46 occurrences
"scripts/forge/" -> "forge/" : 726 occurrences (code, docs, contrats)
```

**⚠ Groupe B non fait — et mon inventaire le sous-estimait d'un facteur ~60.**
J'annonçais *« 18 occurrences / 13 fichiers »*. Mesuré dans `forge/` :

| motif | occurrences | fichiers |
|---|---|---|
| `lab/forge_evidence` | 243 | 55 |
| `games/` | 378 | 92 |
| `lab/forge_runs` | 172 | 87 |
| `lab/reports` | 154 | 41 |
| `"games"` / `'games'` | 64 | 35 |
| `lab/forge_briefs` · `lab/chains` | 15 | 10 |

> **~1 100 occurrences.** Je ne lance pas un remplacement de masse là-dessus sans que la
> correspondance soit ratifiée. `TOPOLOGY.md` §121-124 propose : `EVIDENCE/runs/<projet>/` ·
> `EVIDENCE/bundles/` · `EVIDENCE/reports/` · `EVIDENCE/RUN_INDEX.md`. **Ce n'est pas encore une
> décision, et `lab/forge_briefs` / `lab/chains` n'y ont pas de destination.**

---

## Étape 10 — validation ciblée, ce qui passe déjà

```
import forge.<module>            50 / 50 modules importables
REPO_ROOT                        C:\Users\Studio-Dev\Desktop\Studio          ✔
CONTRACTS_DIR · FORGE_ROLES · KB_CATALOG · DEFAULT_KEY_FILE
oracles.json · standard/                                                     ✔ tous résolus
knowledge_base                   catalogue 50 entrées · 26 propositions      ✔
contrats d'agent                 28 lus · consumption_evidence 0/28 (attendu) ✔
.claude/settings.json            7 références, 0 fantôme                      ✔
TOOLS/observer                   43 entrées                                   ✔
GAMES/pong                       capture_browser.mjs + capture_godot.mjs      ✔
capture Pong EN V2               status=OK passed=True
                                 mesurés ['browser'] · non mesurés ['godot']  ✔
```

> **La dernière ligne est la démonstration de W-2** : V2 n'a pas de binaire Godot configuré. Avant
> le découplage, ce volet aurait rendu `NOT_MEASURED` et `passed=False`. Il rend `OK` sur ce qui a
> été mesuré, en disant ce qui ne l'a pas été.

**Pas encore validé** : exécution d'un run réel (dépend du groupe B), la suite de tests V2
(dépend du groupe B), Godot en V2 (pas de config locale).

```
status_by_surface:
  v1_untouched:          TESTED   # HEAD 58095ba9, seuls les 4 fichiers de l'autre session en écart
  sync_from_head:        TESTED   # 472 fichiers, 0 divergent, 0 résidu
  control_plane_needed:  TESTED   # ModuleNotFoundError -> dépendance vivante, restaurée
  claude_no_ghosts:      TESTED   # 7 références résolues
  paths_A_C:             TESTED   # 95 décréments + 772 préfixes, 6 chemins clés résolus
  imports_L1:            TESTED   # 50/50
  pong_capture_v2:       TESTED   # OK sur le volet mesuré
  group_B:               BLOCKED  # ~1100 occurrences, correspondance à ratifier
  run_reel:              BLOCKED  # dépend du groupe B
```
`software_verdict: OK` · `evidence_verdict: MECHANICAL_VALIDATION_ONLY` ·
`claim_verdict: NO_CLAIM_ALLOWED` · `no_global_ready_verdict: true`

**Q2 / R8 : non touchée.**

# Lot 8 — Nettoyer le journal d'erreurs : Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Retirer de `EVIDENCE/reports/error_journal/html.jsonl` les 313 entrées produites par des tests, en conservant les 13 entrées réelles octet pour octet, et prouver que le pré-mortem des projets réels est inchangé.

**Architecture:** Aucun code, aucun module, aucun script versionné. Un geste unique de réécriture de fichier, appliqué par une commande citée verbatim ici et dans le message de commit, suivi d'une régénération de l'index par le mécanisme de production. La cause a été supprimée au Lot 7 : la pollution ne peut pas se reformer, un outil permanent n'aurait pas d'usage.

**Tech Stack:** Python 3.12 (`.venv` de Studio2) pour le tri et la régénération d'index ; git pour la conservation des lignes retirées.

**Spec:** `docs/superpowers/specs/2026-09-04-lot8-nettoyage-journaux-design.md`.

## Global Constraints

- Dépôt : `C:\Users\Studio-Dev\Desktop\Studio2`. V1 en lecture seule. `git -C` nomme toujours son cwd.
- Aucun commit sans GO explicite de Pierre. Aucun push sans GO séparé. Un GO = une commande.
- **Ce lot RETIRE de la donnée d'un artefact versionné.** Il ne s'exécute que dans cet ordre : empreinte avant → tri → vérification → écriture. Si une seule vérification de la Task 2 échoue, **ne pas écrire le fichier** et remonter à Pierre.
- **Jamais `git checkout`, `git restore` ni `git stash`** sur ce dépôt (garde mécanique, et la leçon `feedback_git_checkout_uncommitted_forge_work`). La réécriture se fait par écriture de fichier, pas par une opération git.
- **Ne pas toucher** aux autres artefacts de preuve (`EVIDENCE/bundles/**`, `knowledge_base/learning_curve.jsonl`) : mesurés propres, hors périmètre.
- **Ne pas régénérer l'index à la main** : `studio_link.write_journal_index()` est le producteur, et c'est lui qui doit écrire.
- `encoding="utf-8"` explicite partout ; `PYTHONIOENCODING=utf-8` sur toute commande qui imprime du texte du journal (la console est en cp1252 — déjà rencontré sur ce lot).

## État de départ, mesuré (2026-09-04, HEAD `3f457fa`)

```
html.jsonl (arbre de travail) : 326 lignes  = 313 test (projet `jeu`) + 13 réelles (`runm_breakout`)
html.jsonl (versionné HEAD)   : 247 lignes
INDEX.generated.md            : annonce 326 entrées pour le domaine `html`
récupérabilité                : git show 3f457fa:EVIDENCE/reports/error_journal/html.jsonl -> 247 lignes
```

Empreinte du pré-mortem AVANT (capturée, à rejouer identique après) :

| projet | lignes | sha256 |
|---|---:|---|
| `runm_breakout` | 5 | `15cb8ceb5c126467d304d546b779b00bde770680340dffd9652da01f31aef726` |
| `v2_breakout_slice` | 0 | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `jeu` | 5 | `86b9a05755ae725489205adc9b71effbec36e5d8cb2f7b29aa9ff8783f7fd469` |

---

### Task 1: Figer l'empreinte d'avant

**Files:**
- Create: `EVIDENCE/reports/lot8_nettoyage/premortem_avant.json`
- Create: `EVIDENCE/reports/lot8_nettoyage/journal_avant.stats.json`

**Interfaces:**
- Produces: deux fichiers de mesure qui serviront de référence à la Task 3. Aucun n'est modifié ensuite.

- [ ] **Step 1: Capturer le pré-mortem de trois projets**

```bash
mkdir -p EVIDENCE/reports/lot8_nettoyage
PYTHONIOENCODING=utf-8 .venv/Scripts/python.exe - <<'EOF' > EVIDENCE/reports/lot8_nettoyage/premortem_avant.json
import hashlib, json
from forge import studio_link as SL
out = {}
for projet in ("runm_breakout", "v2_breakout_slice", "jeu"):
    lignes = SL.premortem(projet, domain="html")
    out[projet] = {"n": len(lignes),
                   "sha256": hashlib.sha256("\n".join(lignes).encode("utf-8")).hexdigest(),
                   "lignes": lignes}
print(json.dumps(out, ensure_ascii=False, indent=1))
EOF
cat EVIDENCE/reports/lot8_nettoyage/premortem_avant.json | head -20
```

Expected: `runm_breakout` n=5 sha `15cb8ceb…`, `v2_breakout_slice` n=0 sha `e3b0c442…`, `jeu` n=5 sha `86b9a057…`. **Si une empreinte diffère de la spec, s'arrêter** : le fichier a bougé depuis la mesure, il faut re-mesurer avant de trier.

- [ ] **Step 2: Capturer les comptes du journal**

```bash
PYTHONIOENCODING=utf-8 .venv/Scripts/python.exe - <<'EOF' > EVIDENCE/reports/lot8_nettoyage/journal_avant.stats.json
import collections, json
from pathlib import Path
J = Path("EVIDENCE/reports/error_journal/html.jsonl")
runs = {p.name for p in Path("EVIDENCE/runs").iterdir() if p.is_dir()}
briefs = {p.name for p in Path("EVIDENCE/briefs").iterdir() if p.is_dir()}
games = {p.name for p in Path("GAMES").iterdir() if p.is_dir()}
par_projet = collections.Counter()
reel = test = 0
for l in J.read_text(encoding="utf-8").splitlines():
    if not l.strip():
        continue
    p = json.loads(l).get("project")
    par_projet[p] += 1
    if p in runs or p in briefs or p in games:
        reel += 1
    else:
        test += 1
print(json.dumps({"total": reel + test, "reel": reel, "test": test,
                  "par_projet": dict(par_projet),
                  "critere": "projet sans run NI brief NI dossier GAMES/ = test"},
                 ensure_ascii=False, indent=1))
EOF
cat EVIDENCE/reports/lot8_nettoyage/journal_avant.stats.json
```

Expected: `total 326, reel 13, test 313`. **Si les comptes diffèrent de la spec, s'arrêter et re-mesurer.**

---

### Task 2: Trier et vérifier — SANS écrire le journal

**Files:**
- Create: `EVIDENCE/reports/lot8_nettoyage/html.jsonl.propose` (candidat, pas encore la cible)

**Interfaces:**
- Produces: le fichier candidat + quatre vérifications qui doivent TOUTES passer avant la Task 3.

- [ ] **Step 1: Produire le candidat**

C'est LA commande du lot. Elle est reproduite verbatim dans le message de commit.

```bash
PYTHONIOENCODING=utf-8 .venv/Scripts/python.exe - <<'EOF'
import json
from pathlib import Path
J = Path("EVIDENCE/reports/error_journal/html.jsonl")
OUT = Path("EVIDENCE/reports/lot8_nettoyage/html.jsonl.propose")
runs = {p.name for p in Path("EVIDENCE/runs").iterdir() if p.is_dir()}
briefs = {p.name for p in Path("EVIDENCE/briefs").iterdir() if p.is_dir()}
games = {p.name for p in Path("GAMES").iterdir() if p.is_dir()}

gardees, retirees = [], []
for ligne in J.read_text(encoding="utf-8").splitlines():
    if not ligne.strip():
        continue
    projet = json.loads(ligne).get("project")
    # CRITÈRE (spec §4) : une entrée est RÉELLE si son projet a laissé une trace sur disque.
    (gardees if (projet in runs or projet in briefs or projet in games) else retirees).append(ligne)

OUT.write_text("\n".join(gardees) + "\n", encoding="utf-8", newline="\n")
print(f"gardées {len(gardees)} | retirées {len(retirees)}")
EOF
```

Expected: `gardées 13 | retirées 313`.

- [ ] **Step 2: Vérifier que les lignes gardées sont IDENTIQUES à l'original**

```bash
PYTHONIOENCODING=utf-8 .venv/Scripts/python.exe - <<'EOF'
from pathlib import Path
orig = [l for l in Path("EVIDENCE/reports/error_journal/html.jsonl").read_text(encoding="utf-8").splitlines() if l.strip()]
cand = [l for l in Path("EVIDENCE/reports/lot8_nettoyage/html.jsonl.propose").read_text(encoding="utf-8").splitlines() if l.strip()]
attendues = [l for l in orig if '"project": "runm_breakout"' in l or '"project":"runm_breakout"' in l]
assert cand == attendues, "les lignes conservées ne sont pas celles d'origine, à l'octet près"
assert all(l in orig for l in cand), "une ligne du candidat n'existe pas dans l'original"
print(f"OK : {len(cand)} lignes conservées, identiques à l'original, dans le même ordre")
EOF
```

Expected: `OK : 13 lignes conservées…`. **Ce test interdit toute réécriture accidentelle** (reformatage JSON, réordonnancement) : on retire, on ne transforme pas.

- [ ] **Step 3: Vérifier que le candidat est du JSONL valide**

```bash
PYTHONIOENCODING=utf-8 .venv/Scripts/python.exe -c "
import json
from pathlib import Path
n = 0
for l in Path('EVIDENCE/reports/lot8_nettoyage/html.jsonl.propose').read_text(encoding='utf-8').splitlines():
    if l.strip():
        json.loads(l); n += 1
print('JSONL valide :', n, 'lignes')
"
```

Expected: `JSONL valide : 13 lignes`.

- [ ] **Step 4: Vérifier la récupérabilité de ce qui sera retiré**

```bash
git -C "C:/Users/Studio-Dev/Desktop/Studio2" show 3f457fa:EVIDENCE/reports/error_journal/html.jsonl | wc -l
```

Expected: `247`. Les 79 lignes non versionnées (ajoutées par les sessions des Lots 5 à 7 et par le rouge du Lot 7) ne sont récupérables **que** dans l'arbre de travail actuel : le message de commit doit le dire, plutôt que de laisser croire que tout est dans git.

**Si l'une des quatre vérifications échoue, ne pas passer à la Task 3.**

---

### Task 3: Écrire, régénérer l'index, prouver la non-régression

**Files:**
- Modify: `EVIDENCE/reports/error_journal/html.jsonl`
- Modify: `EVIDENCE/reports/error_journal/INDEX.generated.md`
- Create: `EVIDENCE/reports/lot8_nettoyage/premortem_apres.json`

- [ ] **Step 1: Remplacer le journal par le candidat**

```bash
PYTHONIOENCODING=utf-8 .venv/Scripts/python.exe -c "
from pathlib import Path
src = Path('EVIDENCE/reports/lot8_nettoyage/html.jsonl.propose')
dst = Path('EVIDENCE/reports/error_journal/html.jsonl')
dst.write_text(src.read_text(encoding='utf-8'), encoding='utf-8', newline='\n')
print('écrit :', dst, dst.stat().st_size, 'octets')
"
wc -l EVIDENCE/reports/error_journal/html.jsonl
```

Expected: 13 lignes.

- [ ] **Step 2: Régénérer l'index PAR LE PRODUCTEUR**

```bash
PYTHONIOENCODING=utf-8 .venv/Scripts/python.exe -c "
from forge import studio_link as SL
print('index écrit :', SL.write_journal_index())
"
grep -E "^\| html " EVIDENCE/reports/error_journal/INDEX.generated.md
```

Expected: la ligne `html` annonce **13** entrées (et non 326).

- [ ] **Step 3: Rejouer l'empreinte du pré-mortem et la comparer**

```bash
PYTHONIOENCODING=utf-8 .venv/Scripts/python.exe - <<'EOF' > EVIDENCE/reports/lot8_nettoyage/premortem_apres.json
import hashlib, json
from forge import studio_link as SL
out = {}
for projet in ("runm_breakout", "v2_breakout_slice", "jeu"):
    lignes = SL.premortem(projet, domain="html")
    out[projet] = {"n": len(lignes),
                   "sha256": hashlib.sha256("\n".join(lignes).encode("utf-8")).hexdigest(),
                   "lignes": lignes}
print(json.dumps(out, ensure_ascii=False, indent=1))
EOF
PYTHONIOENCODING=utf-8 .venv/Scripts/python.exe - <<'EOF'
import json
from pathlib import Path
D = Path("EVIDENCE/reports/lot8_nettoyage")
av = json.loads((D / "premortem_avant.json").read_text(encoding="utf-8"))
ap = json.loads((D / "premortem_apres.json").read_text(encoding="utf-8"))
for projet in ("runm_breakout", "v2_breakout_slice"):
    assert av[projet]["sha256"] == ap[projet]["sha256"], \
        f"RÉGRESSION : le pré-mortem de {projet} a changé ({av[projet]['n']} -> {ap[projet]['n']} lignes)"
    print(f"{projet:20s} INCHANGÉ ({ap[projet]['n']} lignes, sha {ap[projet]['sha256'][:16]}…)")
assert ap["jeu"]["n"] == 0, "le projet de test devait tomber à 0 ligne"
print(f"{'jeu':20s} {av['jeu']['n']} -> 0 ligne (seul changement attendu, voulu)")
EOF
```

Expected: les deux projets réels INCHANGÉS, `jeu` à 0. **Un écart sur `runm_breakout` arrête le lot** : cela signifierait qu'une entrée réelle a été retirée.

- [ ] **Step 4: T0 complet**

```bash
.venv/Scripts/python.exe -m pytest forge/tests/ -m "not gpu_window" -q -p no:cacheprovider \
  --deselect forge/tests/test_observer_integration_real.py 2>&1 | tail -3
```

Expected: 2549 verts / 42 échecs, population identique à celle du Lot 7 (comparer les lignes `FAILED`). Un test qui rougirait après nettoyage dépendrait de données de test dans un journal de production — ce serait un défaut à part entière, à remonter à Pierre, pas à contourner.

Vérifier aussi que la suite n'a **rien réécrit** dans le journal (garde du Lot 7) :

```bash
wc -l EVIDENCE/reports/error_journal/html.jsonl   # doit encore afficher 13
```

- [ ] **Step 5: Handoff et fiche de commit**

Mettre à jour `00_CURRENT_CONTEXT.md` : le bloc Lot 7 gagne la clôture du Lot 8 (326 → 13, pré-mortem réel inchangé), et la ligne « reste un lot de nettoyage dédié » disparaît. **Compte de lignes vérifié après édition**, jamais annoncé (erreur commise au Lot 6).

Périmètre du commit : `EVIDENCE/reports/error_journal/html.jsonl`, `EVIDENCE/reports/error_journal/INDEX.generated.md`, `EVIDENCE/reports/lot8_nettoyage/`, `00_CURRENT_CONTEXT.md`, la spec et le plan. Retirer le fichier candidat `html.jsonl.propose` du périmètre **ou** l'y garder comme trace du geste — le décider explicitement et le dire, ne pas laisser un fichier orphelin par inadvertance.

Message proposé :

```
chore(v2): Lot 8 — nettoyage du journal d'erreurs : 313 entrées de test retirées, 13 entrées réelles conservées à l'octet près (pré-mortem des projets réels inchangé)
```

Rapporter : les comptes avant/après, les deux empreintes de pré-mortem identiques, le commit et le chemin où les lignes retirées restent récupérables, et le fait que 79 lignes n'étaient pas versionnées.

---

## Self-review

- **Couverture de la spec** : §1 comptes (Task 1) · §2 empreinte pré-mortem (Tasks 1 et 3) · §3 périmètre d'un seul fichier (contrainte globale) · §4 critère mécanique (Task 2 step 1, commenté dans le code) · §5 option A, réécriture + index par le producteur (Task 3 steps 1-2) · §6 les cinq preuves (Tasks 1-2-3) · §7 limites (rappelées dans la fiche de commit).
- **Placeholders** : aucun ; chaque étape porte sa commande exacte et son attendu chiffré.
- **Ordre de sûreté** : le journal n'est écrit qu'à la Task 3, après quatre vérifications qui peuvent toutes arrêter le lot. Le candidat est produit dans un fichier séparé, jamais en place.
- **Trois pièges nommés** : (1) ne jamais reformater les lignes conservées — le test d'identité octet pour octet l'interdit ; (2) ne jamais écrire l'index à la main — c'est `write_journal_index` qui produit ; (3) `PYTHONIOENCODING=utf-8` sur toute commande qui imprime du journal, la console étant en cp1252.

# Lot 6 — Contrat de re-convocation : Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Qu'une capacité rappelée sur une section qu'elle a déjà écrite conserve les identifiants cités en aval, et réponde à l'objection du Director dans un champ structuré et mesurable, au lieu d'une sous-chaîne dans sa prose.

**Architecture:** Deux modules déterministes neufs et petits — `forge/identity.py` (clé d'identité par section, comparaison avant/après, contrôle des références aval, refus d'écriture) et `forge/acknowledgement.py` (fence dédiée, cinq statuts, désaccord structuré). Tous deux branchés dans `forge/capability.py` au point d'écriture, et lus par `forge/director.py` qui seul connaît l'effet mesuré. Aucun nouvel état du Director, aucune modification des oracles ni du verdict.

**Tech Stack:** Python 3.12 (`.venv` de Studio2), PyYAML, pytest, node pour `check_decompo.mjs`.

**Spec:** `docs/superpowers/specs/2026-09-04-lot6-reconvocation-design.md` (validée Pierre, 4 corrections intégrées).

## Global Constraints

- Dépôt : `C:\Users\Studio-Dev\Desktop\Studio2`. V1 (`C:\TACTICAL_CHESS_STUDIO`) en lecture seule. `git -C` nomme toujours son cwd.
- Aucun commit sans GO explicite de Pierre. Aucun push. Un GO = une commande.
- Aucun appel LLM dans les tests. La re-convocation réelle (Task 7) coûte ~1,6 $ et n'est lancée qu'une fois, en dernier.
- `software_verdict` vient UNIQUEMENT des reçus d'oracle : ne toucher ni `verdict.py` ni `verify_run.py`.
- Interpréteur : `.venv/Scripts/python.exe`. Tests : `.venv/Scripts/python.exe -m pytest <fichier> -q -p no:cacheprovider -m "not gpu_window"`.
- `encoding="utf-8"` explicite sur tout accès fichier. Chemins repo-relatifs dans les artefacts.
- Ne jamais toucher `EVIDENCE/runs/runm_breakout/`, `v2_breakout_slice_r1/`, `lot5_transport_probe/`.
- Un `UNKNOWN` honnête ne se comble jamais par une valeur devinée (règle du studio, appliquée en Task 1).

---

### Task 1: Mesure de l'identité `wiremap`, bloc `identity` au registre, extraction des ids

**Files:**
- Create: `forge/identity.py`
- Create: `forge/tests/test_reconvocation_lot6.py`
- Modify: `forge/capability_registry.yaml` (bloc `identity`, après le bloc `transport`)
- Create: `EVIDENCE/reports/lot6_reconvocation/identity_measurement.md`

**Interfaces:**
- Produces: `identity.load_identity(path=None) -> dict` · `identity.identity_of(section, doc=None) -> dict | None` (`None` si `key: UNKNOWN`) · `identity.extract_ids(content, key) -> list[str]` · `identity.ID_REFERENCED_DROPPED`.

- [ ] **Step 1: Mesurer la clé d'identité de `wiremap.design` (lecture seule, aucune supposition)**

Lire et consigner, sans écrire de code : `forge/contracts/s5-wiremap.yaml` (`output_contract`), `run_real._validate_wiremap` (l.1160) et `_validate_wiremap_v2` (l.1197), `forge/check_wiremap_contract.mjs` (quel champ il joint), et les wiremaps réelles :

```bash
.venv/Scripts/python.exe - <<'EOF'
import json
from pathlib import Path
for p in ("EVIDENCE/runs/runm_breakout/wiremap.json",
          "EVIDENCE/runs/v2_breakout_slice_r1/wiremap.json"):
    d = json.loads(Path(p).read_text(encoding="utf-8"))
    print(p, "| schema_version", d.get("schema_version"), "| clés racine", sorted(d.keys()))
    for shape in ("features", "lines"):
        if isinstance(d.get(shape), list) and d[shape]:
            print("   ", shape, "->", sorted(d[shape][0].keys()))
EOF
grep -n "features\|lines\|couvre\|\.id\b" forge/check_wiremap_contract.mjs | head -20
```

Écrire le constat dans `EVIDENCE/reports/lot6_reconvocation/identity_measurement.md` : quelle clé `check_wiremap_contract.mjs` joint réellement, si la réponse diffère selon `schema_version`, et la conclusion — soit une clé canonique nommée, soit `UNKNOWN` maintenu avec la raison. **Les deux issues sont acceptables ; une clé devinée ne l'est pas.**

- [ ] **Step 2: Write the failing tests**

```python
"""Lot 6 (spec 2026-09-04, GO Pierre) — contrat de re-convocation : identité de section et
acquittement structuré.

Forme de production réelle : Blueprint importé de la baseline M ter, feature_maps réellement produites
par les trois convocations de `decompose` (baseline, lot2, lot5), wiremap réelle de la baseline.
Aucun appel LLM. NO_CLAIM_ALLOWED.
"""
from __future__ import annotations

import json
import shutil
from pathlib import Path

import pytest

from forge import blueprint as bp
from forge import identity as idt
from forge.blueprint_import import import_run_dir

_REPO_ROOT = Path(__file__).resolve().parents[2]
_RUN_DIR = _REPO_ROOT / "EVIDENCE" / "runs" / "runm_breakout"
_BRIEF = _REPO_ROOT / "EVIDENCE" / "briefs" / "runm_breakout" / "project_brief.yaml"
_FM_BASELINE = _RUN_DIR / "featuremap.json"
_FM_LOT5 = _REPO_ROOT / "EVIDENCE" / "runs" / "lot5_transport_probe" / "featuremap.json"

pytestmark = [
    pytest.mark.skipif(not (_RUN_DIR / "state.json").exists(), reason="baseline M ter absente"),
    pytest.mark.skipif(shutil.which("node") is None, reason="node absent"),
]

_FM_KEY = "systemes[].features[].capacites[].id"


@pytest.fixture
def blueprint():
    return import_run_dir(_RUN_DIR, brief_path=_BRIEF, project="runm_breakout")


def _fm(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


# --- Task 1 : registre et extraction ------------------------------------------------------------


def test_le_registre_declare_une_cle_d_identite_canonique_par_section():
    doc = idt.load_identity()
    assert doc["feature_map"]["key"] == _FM_KEY
    for section, decl in doc.items():
        assert isinstance(decl.get("key"), str) and decl["key"], section
        for ref in decl.get("referenced_by") or []:
            assert set(ref) == {"section", "path"}, section


def test_wiremap_sans_cle_mesuree_ne_gouverne_rien():
    """Un UNKNOWN honnête : identity_of rend None, aucune règle ne s'applique (spec §3.2)."""
    doc = idt.load_identity()
    decl = idt.identity_of("wiremap.design", doc)
    assert decl is None or isinstance(decl["key"], str) and decl["key"] != "UNKNOWN"


def test_les_trois_schemas_d_ids_reellement_produits_sont_extraits():
    baseline = idt.extract_ids(_fm(_FM_BASELINE), _FM_KEY)
    lot5 = idt.extract_ids(_fm(_FM_LOT5), _FM_KEY)
    assert baseline[0] == "R1c1_hud_objectif_nonvide" and len(baseline) == 10
    assert lot5[0] == "CAP_objectif_hud" and len(lot5) == 10
    assert set(baseline).isdisjoint(lot5), "les deux runs ont bien renommé toutes les entrées"


def test_extract_ids_ignore_la_declaration_de_retrait_et_ne_leve_jamais():
    content = {"identity": {"retired": [{"id": "R9c1", "reason": "fusionnée"}]},
               "systemes": [{"features": [{"capacites": [{"id": "A"}, {"pas_d_id": 1}]}]}]}
    assert idt.extract_ids(content, _FM_KEY) == ["A"]
    assert idt.extract_ids({}, _FM_KEY) == []
    assert idt.extract_ids(None, _FM_KEY) == []
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `.venv/Scripts/python.exe -m pytest forge/tests/test_reconvocation_lot6.py -q -p no:cacheprovider`
Expected: FAIL — `ModuleNotFoundError: No module named 'forge.identity'`.

- [ ] **Step 4: Add the `identity` block to the registry**

Insérer dans `forge/capability_registry.yaml`, après le bloc `transport` et avant `capabilities:` (remplacer la valeur de `wiremap.design.key` par la clé mesurée en Step 1, ou laisser `UNKNOWN` avec la raison) :

```yaml
# ------------------------------------------------------------------------------------------
# Lot 6 (2026-09-04, GO Pierre) — IDENTITÉ : une section = UNE clé d'identité canonique.
# `key` : chemin de navigation vers l'identifiant stable d'une entrée. `referenced_by` : qui cite
# ces identifiants en aval (section + chemin). Une re-convocation ne renomme jamais un identifiant
# cité ; un retrait se déclare dans `identity.retired` de l'artefact ET n'est accepté que si plus
# rien en aval ne le cite (spec §3.4). `key: UNKNOWN` = non mesuré : aucune règle ne s'applique.
identity:
  feature_map:
    key: "systemes[].features[].capacites[].id"
    referenced_by:
      - {section: "wiremap.design", path: "features[].couvre[]"}
      - {section: "wiremap.built",  path: "features[].couvre[]"}
  architecture_contract:
    key: "modules[]"
    referenced_by:
      # référence INTRA-section : deps_interdites cite des noms de modules par paires
      - {section: "architecture_contract", path: "deps_interdites[][]"}
  wiremap.design:
    key: UNKNOWN     # mesuré en Task 1 step 1 — remplacer par la clé constatée, ou garder avec la raison
    referenced_by: []
```

- [ ] **Step 5: Write `forge/identity.py` (extraction seule)**

```python
"""Identité d'une section du GAME_BLUEPRINT (Lot 6, spec 2026-09-04, GO Pierre).

UNE question, deux réponses déterministes :
  * `identity_of(section)` — la clé d'identité canonique déclarée au registre, ou None si la section
    n'en a pas de mesurée (`UNKNOWN` : aucune règle ne s'applique, jamais une clé devinée) ;
  * `compare(...)` — ce qui a été gardé, ajouté, retiré, et ce qui a DISPARU alors que l'aval le cite.

Ce module ne lit ni ne modifie un verdict, n'appelle aucun modèle, n'écrit aucun fichier. Il ne décide
pas non plus de refuser : il MESURE, et `forge.capability` applique la règle. NO_CLAIM_ALLOWED.
"""
from __future__ import annotations

from pathlib import Path

import yaml

REGISTRY_PATH = Path(__file__).resolve().parent / "capability_registry.yaml"
UNKNOWN = "UNKNOWN"
ID_REFERENCED_DROPPED = "ID_REFERENCED_DROPPED"
RETIRED_KEY = "identity"          # <artefact>.identity.retired = [{id, reason}]


def load_identity(path: Path | None = None) -> dict:
    doc = yaml.safe_load(Path(path or REGISTRY_PATH).read_text(encoding="utf-8")) or {}
    return doc.get("identity") or {}


def identity_of(section: str, doc: dict | None = None) -> dict | None:
    """Déclaration d'identité d'une section, ou None si absente ou non mesurée (UNKNOWN)."""
    decl = (doc if doc is not None else load_identity()).get(section)
    if not isinstance(decl, dict) or decl.get("key") in (None, "", UNKNOWN):
        return None
    return decl


def _walk(node, steps: list[str]) -> list:
    """Navigation déterministe : 'a[].b[].c' — '[]' descend dans une liste, un nom dans un dict."""
    if not steps:
        return [node] if node is not None else []
    step, rest = steps[0], steps[1:]
    if step == "[]":
        return [] if not isinstance(node, list) else [v for item in node for v in _walk(item, rest)]
    if not isinstance(node, dict) or step not in node:
        return []
    return _walk(node[step], rest)


def _parse(key: str) -> list[str]:
    steps: list[str] = []
    for part in str(key).split("."):
        name, _, brackets = part.partition("[")
        if name:
            steps.append(name)
        steps += ["[]"] * brackets.count("]")
    return steps


def extract_ids(content, key: str) -> list[str]:
    """Identifiants présents, dans l'ordre de lecture. Jamais d'exception : une structure inattendue
    rend une liste vide (l'absence de mesure ne se déguise pas en absence d'identifiants)."""
    return [str(v) for v in _walk(content, _parse(key)) if isinstance(v, (str, int)) and str(v)]


def declared_retired(content) -> list[dict]:
    """Retraits déclarés par la production elle-même : <artefact>.identity.retired."""
    block = content.get(RETIRED_KEY) if isinstance(content, dict) else None
    items = (block or {}).get("retired") if isinstance(block, dict) else None
    return [i for i in (items or []) if isinstance(i, dict) and i.get("id")]
```

- [ ] **Step 6: Run the tests**

Run: `.venv/Scripts/python.exe -m pytest forge/tests/test_reconvocation_lot6.py -q -p no:cacheprovider`
Expected: `4 passed`.

---

### Task 2: Comparaison, références aval, règle de refus

**Files:**
- Modify: `forge/identity.py` (ajout de `downstream_ids`, `compare`)
- Modify: `forge/tests/test_reconvocation_lot6.py`

**Interfaces:**
- Produces: `identity.downstream_ids(blueprint, refs) -> set[str]` · `identity.compare(before, after, *, key, downstream, retired) -> dict` avec les clés `kept, added, retired_declared, dropped, renamed_suspected, referenced_dropped, ok`.

- [ ] **Step 1: Write the failing tests**

```python
# --- Task 2 : comparaison et règle de refus -------------------------------------------------------


def _cmp(before_ids, after_ids, *, downstream=(), retired=()):
    def tree(ids):
        return {"systemes": [{"features": [{"capacites": [{"id": i} for i in ids]}]}]}
    return idt.compare(tree(before_ids), tree(after_ids), key=_FM_KEY,
                       downstream=set(downstream), retired=[{"id": r, "reason": "test"} for r in retired])


def test_un_renommage_cite_en_aval_est_refuse():
    r = _cmp(["A", "B"], ["A", "Z"], downstream={"A", "B"})
    assert r["referenced_dropped"] == ["B"] and r["ok"] is False
    assert r["added"] == ["Z"] and r["kept"] == ["A"]
    assert r["renamed_suspected"] == [("B", "Z")]   # informatif, jamais un verdict


def test_un_retrait_declare_sans_reference_aval_est_accepte():
    r = _cmp(["A", "B"], ["A"], downstream={"A"}, retired=["B"])
    assert r["retired_declared"] == ["B"] and r["referenced_dropped"] == [] and r["ok"] is True


def test_un_retrait_declare_ENCORE_cite_est_refuse():
    """Correction 1 de Pierre : déclarer un retrait ne suffit pas — sinon un renommage implicite
    devient une suppression déclarée."""
    r = _cmp(["A", "B"], ["A"], downstream={"A", "B"}, retired=["B"])
    assert r["referenced_dropped"] == ["B"] and r["ok"] is False
    assert "B" not in r["retired_declared"]


def test_un_retrait_non_declare_sans_reference_aval_passe_mais_reste_au_rapport():
    r = _cmp(["A", "B"], ["A"], downstream={"A"})
    assert r["dropped"] == ["B"] and r["ok"] is True and r["retired_declared"] == []


def test_un_ajout_est_toujours_libre():
    r = _cmp(["A"], ["A", "B", "C"], downstream={"A"})
    assert r["added"] == ["B", "C"] and r["ok"] is True


def test_les_references_aval_sont_lues_dans_le_blueprint_reel(blueprint):
    """La wiremap de la baseline cite les 10 ids de la feature_map dans features[].couvre[]."""
    refs = [{"section": "wiremap.design", "path": "features[].couvre[]"}]
    ids = idt.downstream_ids(blueprint, refs)
    fm_ids = set(idt.extract_ids(blueprint["sections"]["feature_map"]["content"], _FM_KEY))
    assert ids and ids == fm_ids
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `.venv/Scripts/python.exe -m pytest forge/tests/test_reconvocation_lot6.py -q -p no:cacheprovider -k "renommage or retrait or ajout or references_aval"`
Expected: FAIL — `AttributeError: module 'forge.identity' has no attribute 'compare'`.

- [ ] **Step 3: Implement**

Ajouter à `forge/identity.py` :

```python
def downstream_ids(blueprint: dict, refs: list[dict]) -> set[str]:
    """Identifiants réellement cités en aval, d'après les chemins déclarés au registre."""
    out: set[str] = set()
    for ref in refs or []:
        section, _, entry = str(ref.get("section", "")).partition(".")
        meta = (blueprint.get("sections") or {}).get(section) or {}
        content = meta.get("content")
        if entry:
            sub = content.get(entry) if isinstance(content, dict) else None
            content = sub.get("content") if isinstance(sub, dict) else None
        out.update(extract_ids(content, ref.get("path", "")))
    return out


def compare(before, after, *, key: str, downstream: set[str], retired: list[dict]) -> dict:
    """Rapport d'identité entre deux versions d'une section. MESURE — le refus est appliqué par
    l'appelant (`forge.capability`), qui seul est au point d'écriture.

    Règle (spec §3.4, correction 1 de Pierre) : un identifiant absent de `after` n'est accepté que
    s'il n'est PLUS cité en aval. Un retrait déclaré mais encore référencé est refusé au même titre
    qu'un renommage implicite."""
    before_ids, after_ids = extract_ids(before, key), extract_ids(after, key)
    b, a = list(dict.fromkeys(before_ids)), list(dict.fromkeys(after_ids))
    declared = {str(r["id"]) for r in (retired or [])}
    kept = [i for i in b if i in a]
    added = [i for i in a if i not in b]
    absents = [i for i in b if i not in a]
    referenced_dropped = [i for i in absents if i in (downstream or set())]
    retired_declared = [i for i in absents if i in declared and i not in referenced_dropped]
    dropped = [i for i in absents if i not in declared and i not in referenced_dropped]
    # Informatif : autant d'absents que d'ajouts => un renommage est PROBABLE. Jamais un verdict.
    renamed = list(zip(absents, added)) if absents and len(absents) == len(added) else []
    return {"key": key, "kept": kept, "added": added, "retired_declared": retired_declared,
            "dropped": dropped, "renamed_suspected": renamed,
            "referenced_dropped": referenced_dropped, "ok": not referenced_dropped}
```

- [ ] **Step 4: Run the tests**

Run: `.venv/Scripts/python.exe -m pytest forge/tests/test_reconvocation_lot6.py -q -p no:cacheprovider`
Expected: `10 passed`.

---

### Task 3: Branchement dans `invoke_capability` — production précédente au prompt, refus d'écriture

**Files:**
- Modify: `forge/capability.py` (imports ; dict `result` ; assemblage du prompt ; avant `_write_owned_section`)
- Modify: `forge/tests/test_reconvocation_lot6.py`

**Interfaces:**
- Produces: `result["identity"]` (rapport de `compare`, ou `None` si section neuve ou clé UNKNOWN) ; problème K7 `ID_REFERENCED_DROPPED` (producteur `identity_check`) ; section du Blueprint **intacte** en cas de refus.

- [ ] **Step 1: Write the failing tests**

```python
# --- Task 3 : branchement au point d'écriture -----------------------------------------------------


from forge import capability as cap   # noqa: E402  (import groupé en tête du fichier réel)

_S3_OUTPUT = _RUN_DIR / "artifacts" / "s3-decompo.txt"


def _executor_returning(fm: dict, calls: list | None = None):
    payload = "Rapport.\n\n```json\n" + json.dumps(fm, ensure_ascii=False) + "\n```\n"

    def executor(prompt, sp, pl):
        if calls is not None:
            calls.append({"prompt": prompt, "etape": sp["etape"]})
        return {"ok": True, "output": payload, "tokens": 0, "duration_s": 0.0, "cost_usd": 0.0}
    return executor


def _renamed(fm: dict) -> dict:
    out = json.loads(json.dumps(fm))
    n = 0
    for s in out["systemes"]:
        for f in s["features"]:
            for c in f["capacites"]:
                n += 1
                c["id"] = f"RENOMME_{n}"
    return out


def test_la_reconvocation_recoit_sa_production_precedente(blueprint, tmp_path):
    calls: list = []
    fm = blueprint["sections"]["feature_map"]["content"]
    res = cap.invoke_capability("decompose", blueprint, tmp_path / "run", run_id="lot6-t3", attempt=2,
                                executor=_executor_returning(fm, calls), audit_path=tmp_path / "a.jsonl")
    assert res["ok"], res["problems"]
    prompt = calls[0]["prompt"]
    assert "## TA PRODUCTION PRÉCÉDENTE — feature_map v1" in prompt
    assert "R1c1_hud_objectif_nonvide" in prompt
    assert "identity.retired" in prompt and "RÈGLE D'IDENTITÉ" in prompt
    assert res["identity"]["ok"] is True and res["identity"]["added"] == []


def test_une_section_neuve_n_a_pas_de_production_precedente(blueprint, tmp_path):
    neuf = json.loads(json.dumps(blueprint))
    neuf["sections"]["feature_map"] = bp.empty_section("feature_map")
    calls: list = []
    res = cap.invoke_capability("decompose", neuf, tmp_path / "run", run_id="lot6-t3b", attempt=1,
                                executor=_executor_returning(_fm(_FM_BASELINE), calls),
                                audit_path=tmp_path / "a.jsonl")
    assert res["ok"] and res["identity"] is None
    assert "TA PRODUCTION PRÉCÉDENTE" not in calls[0]["prompt"]


def test_un_renommage_cite_par_la_wiremap_refuse_l_ecriture_et_laisse_la_section_intacte(blueprint, tmp_path):
    avant = (blueprint["sections"]["feature_map"]["version"],
             blueprint["sections"]["feature_map"]["content_sha256"])
    fm = _renamed(blueprint["sections"]["feature_map"]["content"])
    res = cap.invoke_capability("decompose", blueprint, tmp_path / "run", run_id="lot6-t3c", attempt=2,
                                executor=_executor_returning(fm), audit_path=tmp_path / "a.jsonl")
    assert res["ok"] is False
    pb = [p for p in res["problems"] if p["code"] == idt.ID_REFERENCED_DROPPED]
    assert len(pb) == 1 and pb[0]["producer"] == "identity_check" and pb[0]["path"] == "feature_map"
    assert pb[0]["suggested_action"] == "reconvoke"
    assert len(res["identity"]["referenced_dropped"]) == 10
    # la section n'a PAS bougé ; l'artefact reste sur disque pour inspection
    apres = (blueprint["sections"]["feature_map"]["version"],
             blueprint["sections"]["feature_map"]["content_sha256"])
    assert apres == avant
    assert (tmp_path / "run" / "featuremap.json").exists()
    link = [json.loads(l) for l in (tmp_path / "run" / "context" / "spawn_links.jsonl")
            .read_text(encoding="utf-8").splitlines() if l.strip()][-1]
    assert link["status"] == "HALTED"


def test_un_retrait_declare_et_libere_est_accepte(blueprint, tmp_path):
    """La wiremap ne cite plus l'id retiré : le retrait déclaré passe."""
    b = json.loads(json.dumps(blueprint))
    wm = b["sections"]["wiremap"]["content"]
    cible = "R9c1_window_game_expose"
    for f in wm["design"]["content"]["features"]:
        f["couvre"] = [c for c in (f.get("couvre") or []) if c != cible]
    fm = json.loads(json.dumps(b["sections"]["feature_map"]["content"]))
    for s in fm["systemes"]:
        for f in s["features"]:
            f["capacites"] = [c for c in f["capacites"] if c["id"] != cible]
    fm["identity"] = {"retired": [{"id": cible, "reason": "capacité fusionnée dans R1c1"}]}
    res = cap.invoke_capability("decompose", b, tmp_path / "run", run_id="lot6-t3d", attempt=2,
                                executor=_executor_returning(fm), audit_path=tmp_path / "a.jsonl")
    assert res["ok"], res["problems"]
    assert res["identity"]["retired_declared"] == [cible] and res["identity"]["referenced_dropped"] == []
    assert b["sections"]["feature_map"]["version"] == 2
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `.venv/Scripts/python.exe -m pytest forge/tests/test_reconvocation_lot6.py -q -p no:cacheprovider -k "production_precedente or section_neuve or renommage_cite or retrait_declare_et_libere"`
Expected: FAIL — `KeyError: 'identity'`.

- [ ] **Step 3: Implement**

Import en tête de `forge/capability.py` :

```python
from forge import identity as idt     # Lot 6 : contrat d'identité de section
```

Dans le dict `result` initial, ajouter :

```python
        # Lot 6 : rapport d'identité (None = section neuve ou clé non mesurée)
        "identity": None,
```

Dans l'assemblage du prompt, **après** le bloc `bp_section` et **avant** le pré-mortem :

```python
    # Lot 6 (spec §3.3) : la production précédente de CETTE section, dérivée du Blueprint lui-même —
    # une seule source de vérité : la version comparée plus bas est exactement celle qui sera écrasée.
    section_name = sp["writes"].split(".")[0] if sp.get("writes") else None
    id_decl = idt.identity_of(sp["writes"], None) if sp.get("writes") else None
    prev_meta = (blueprint["sections"].get(section_name) or {}) if section_name else {}
    prev_content = prev_meta.get("content") if prev_meta.get("version", 0) > 0 else None
    if prev_content is not None and id_decl is not None:
        body = json.dumps(prev_content, ensure_ascii=False, indent=1)
        if len(body) > UPSTREAM_MAX_CHARS:
            body = _truncate_preserve_terminal_json(body)
        parts.append(
            f"## TA PRODUCTION PRÉCÉDENTE — {sp['writes']} v{prev_meta['version']} "
            f"(content_sha256={prev_meta['content_sha256']})\n"
            f"```json\n{body}\n```\n"
            f"RÈGLE D'IDENTITÉ : les identifiants de cette section ({id_decl['key']}) sont cités en "
            "aval. Conserve chacun À L'IDENTIQUE — ne renomme jamais. Une entrée qui doit disparaître "
            'se déclare dans `identity.retired: [{"id": "<id>", "reason": "<pourquoi>"}]` à la racine '
            "de ton artefact, et SEULEMENT si plus rien en aval ne la cite. Ajouter est libre.")
```

Juste **avant** l'appel à `_write_owned_section` du chemin JSON (bloc « 6. écriture de LA section possédée ») :

```python
    # Lot 6 (spec §3.4) : le contrat d'identité s'applique au point d'écriture, jamais avant.
    if prev_content is not None and id_decl is not None:
        rapport = idt.compare(prev_content, data, key=id_decl["key"],
                              downstream=idt.downstream_ids(blueprint, id_decl.get("referenced_by") or []),
                              retired=idt.declared_retired(data))
        result["identity"] = rapport
        if not rapport["ok"]:
            result["problems"].append(_problem(
                idt.ID_REFERENCED_DROPPED, "identity_check",
                f"identifiants encore cités en aval et absents de la nouvelle version : "
                f"{', '.join(rapport['referenced_dropped'])}",
                path=sp["writes"], action="reconvoke"))
            return _finish(result, t0)
```

- [ ] **Step 4: Run the tests**

Run: `.venv/Scripts/python.exe -m pytest forge/tests/test_reconvocation_lot6.py forge/tests/test_transport_lot5.py forge/tests/test_capability_lot2.py -q -p no:cacheprovider`
Expected: tous verts.

---

### Task 4: `forge/acknowledgement.py` — fence dédiée et cinq statuts

**Files:**
- Create: `forge/acknowledgement.py`
- Modify: `forge/tests/test_reconvocation_lot6.py`

**Interfaces:**
- Produces: `acknowledgement.extract_block(output) -> tuple[dict | None, str]` · `judge(block, *, message, capability, run_id, effect, already_acknowledged) -> dict` · constantes `ACKNOWLEDGED, CLAIMED_WITHOUT_EFFECT, REJECTED, UNKNOWN_MESSAGE, NOT_ACKNOWLEDGED, ACTIONS`.

- [ ] **Step 1: Write the failing tests**

```python
# --- Task 4 : acquittement, cinq statuts ----------------------------------------------------------


from forge import acknowledgement as ack   # noqa: E402

_MSG = {"id": "AMD-x-1", "type": "objection", "from": "director", "to": ["decompose"],
        "subject": "s", "reason": "r", "issued_at": "2026-09-04T00:00:00Z", "run_id": "lot6-t4"}


def _out(block: dict | None) -> str:
    if block is None:
        return "Rapport sans acquittement.\n"
    return "Rapport.\n\n```acquittement\n" + json.dumps(block, ensure_ascii=False) + "\n```\n"


def _judge(block, *, effect="CHANGED", capability="decompose", run_id="lot6-t4", deja=()):
    return ack.judge(block, message=_MSG, capability=capability, run_id=run_id, effect=effect,
                     already_acknowledged=set(deja))


def test_applied_avec_effet_est_acquitte():
    b, _ = ack.extract_block(_out({"message_id": "AMD-x-1", "action": "applied", "changes": ["ids conservés"]}))
    r = _judge(b)
    assert r["status"] == ack.ACKNOWLEDGED and r["message_id"] == "AMD-x-1" and r["action"] == "applied"


def test_applied_sans_effet_est_une_pretention_sans_effet():
    b, _ = ack.extract_block(_out({"message_id": "AMD-x-1", "action": "applied", "changes": ["rien"]}))
    assert _judge(b, effect="NO_EFFECT")["status"] == ack.CLAIMED_WITHOUT_EFFECT


def test_partial_avec_effet_est_acquitte_et_garde_sa_raison():
    b, _ = ack.extract_block(_out({"message_id": "AMD-x-1", "action": "partial",
                                   "changes": ["2 sur 3"], "reason": "la 3e dépend de la wiremap"}))
    r = _judge(b)
    assert r["status"] == ack.ACKNOWLEDGED and r["reason"].startswith("la 3e")


def test_rejected_avec_raison_est_un_desaccord():
    b, _ = ack.extract_block(_out({"message_id": "AMD-x-1", "action": "rejected",
                                   "changes": [], "reason": "l'oracle impose main.tscn sur un jeu web"}))
    assert _judge(b)["status"] == ack.REJECTED


def test_rejected_sans_raison_n_est_pas_un_acquittement():
    b, _ = ack.extract_block(_out({"message_id": "AMD-x-1", "action": "rejected", "changes": []}))
    assert _judge(b)["status"] == ack.NOT_ACKNOWLEDGED


def test_message_inconnu_autre_capacite_ou_autre_run():
    b, _ = ack.extract_block(_out({"message_id": "AMD-INCONNU", "action": "applied"}))
    assert _judge(b)["status"] == ack.UNKNOWN_MESSAGE
    b2, _ = ack.extract_block(_out({"message_id": "AMD-x-1", "action": "applied"}))
    assert _judge(b2, capability="wiremap")["status"] == ack.UNKNOWN_MESSAGE
    assert _judge(b2, run_id="autre_run")["status"] == ack.UNKNOWN_MESSAGE


def test_un_second_acquittement_du_meme_message_est_refuse():
    b, _ = ack.extract_block(_out({"message_id": "AMD-x-1", "action": "applied"}))
    assert _judge(b, deja={"AMD-x-1"})["status"] == ack.UNKNOWN_MESSAGE


def test_absence_de_bloc_bloc_illisible_et_action_inconnue():
    b, why = ack.extract_block(_out(None))
    assert b is None and "aucun fence" in why
    assert _judge(b)["status"] == ack.NOT_ACKNOWLEDGED
    b2, why2 = ack.extract_block("Rapport.\n\n```acquittement\npas du json\n```\n")
    assert b2 is None and why2
    b3, _ = ack.extract_block(_out({"message_id": "AMD-x-1", "action": "vu"}))
    assert _judge(b3)["status"] == ack.NOT_ACKNOWLEDGED


def test_le_dernier_bloc_seul_fait_foi():
    out = (_out({"message_id": "AMD-x-1", "action": "rejected", "reason": "brouillon"})
           + _out({"message_id": "AMD-x-1", "action": "applied", "changes": ["final"]}))
    b, _ = ack.extract_block(out)
    assert b["action"] == "applied"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `.venv/Scripts/python.exe -m pytest forge/tests/test_reconvocation_lot6.py -q -p no:cacheprovider -k "applied or partial or rejected or message_inconnu or second_acquittement or absence_de_bloc or dernier_bloc"`
Expected: FAIL — `ModuleNotFoundError: No module named 'forge.acknowledgement'`.

- [ ] **Step 3: Implement**

```python
"""Acquittement structuré d'un message du Director (Lot 6, spec 2026-09-04, GO Pierre) — K4.

Remplace la recherche de sous-chaîne (`consumption._contains_ref`) sur le chemin d'acquittement :
citer un identifiant dans sa prose ne prouve pas qu'on a corrigé quelque chose. La capacité répond
dans une fence dédiée, et le jugement est MÉCANIQUE :

    acknowledged            message valide, action applied|partial, effet mesuré != NO_EFFECT
    claimed_without_effect  action applied mais le Director n'a mesuré AUCUN effet
    rejected                désaccord motivé — transporté, jamais tranché ici
    unknown_message         id inconnu, adressé à une autre capacité, un autre run, ou déjà acquitté
    not_acknowledged        aucun bloc, bloc illisible, action hors énumération, rejected sans raison

Ce module ne lit ni ne modifie un verdict, n'appelle aucun modèle, n'écrit aucun fichier.
NO_CLAIM_ALLOWED.
"""
from __future__ import annotations

import json
import re

FENCE = re.compile(r"^```acquittement[ \t]*\r?\n(.*?)^```", re.S | re.M)

ACKNOWLEDGED = "acknowledged"
CLAIMED_WITHOUT_EFFECT = "claimed_without_effect"
REJECTED = "rejected"
UNKNOWN_MESSAGE = "unknown_message"
NOT_ACKNOWLEDGED = "not_acknowledged"
ACTIONS = ("applied", "partial", "rejected")
NO_EFFECT = "NO_EFFECT"          # même vocabulaire que forge.director.effect_of


def extract_block(output: str) -> tuple[dict | None, str]:
    """(bloc, diagnostic) — SEUL le dernier fence ```acquittement``` fait foi (même règle que
    `run_real._extract_design_questions_block` : un fence antérieur est un brouillon)."""
    blocks = FENCE.findall(output or "")
    if not blocks:
        return None, "aucun fence ```acquittement"
    raw = blocks[-1]
    try:
        candidat = json.loads(raw)
    except ValueError as exc:
        return None, f"fence présent mais JSON illisible : {exc}"
    if not isinstance(candidat, dict):
        return None, f"fence présent mais ce n'est pas un objet ({type(candidat).__name__})"
    return candidat, ""


def judge(block, *, message: dict | None, capability: str, run_id: str, effect: str | None,
          already_acknowledged: set[str] | None = None) -> dict:
    """Statut d'un acquittement. Ne lève jamais. `effect` vient du Director (`effect_of`)."""
    out = {"status": NOT_ACKNOWLEDGED, "message_id": None, "action": None,
           "changes": [], "reason": "", "effect": effect}
    if not isinstance(block, dict):
        out["reason"] = "aucun bloc d'acquittement recevable"
        return out
    mid = str(block.get("message_id") or "")
    action = str(block.get("action") or "").strip().lower()
    out.update({"message_id": mid or None, "action": action or None,
                "changes": [str(c) for c in (block.get("changes") or []) if str(c)],
                "reason": str(block.get("reason") or "")})
    attendu = (message or {}).get("id")
    destinataires = [str(x) for x in ((message or {}).get("to") or [])]
    if (not attendu or mid != attendu or capability not in destinataires
            or (message or {}).get("run_id") not in (None, run_id)
            or mid in (already_acknowledged or set())):
        out["status"] = UNKNOWN_MESSAGE
        return out
    if action not in ACTIONS:
        return out                       # NOT_ACKNOWLEDGED : action hors énumération
    if action == "rejected":
        out["status"] = REJECTED if out["reason"].strip() else NOT_ACKNOWLEDGED
        return out
    if action == "applied" and effect == NO_EFFECT:
        out["status"] = CLAIMED_WITHOUT_EFFECT
        return out
    out["status"] = ACKNOWLEDGED
    return out
```

- [ ] **Step 4: Run the tests**

Run: `.venv/Scripts/python.exe -m pytest forge/tests/test_reconvocation_lot6.py -q -p no:cacheprovider`
Expected: tous verts.

---

### Task 5: Le désaccord — objection inverse et question ouverte

**Files:**
- Modify: `forge/acknowledgement.py` (ajout de `disagreement_message`, `question_entry`)
- Modify: `forge/tests/test_reconvocation_lot6.py`

**Interfaces:**
- Produces: `disagreement_message(judgment, *, capability, run_id, message) -> dict` (type `objection`, `from` capacité, `to` `["director"]`, `in_reply_to`) · `question_entry(judgment, *, capability, run_id, disagreement_id) -> dict` (entrée append-only de la section `questions`).

- [ ] **Step 1: Write the failing tests**

```python
# --- Task 5 : le désaccord (correction 3 de Pierre) ------------------------------------------------


from forge.amendment_log import MESSAGE_TYPES, append_message, read_messages, validate_message  # noqa: E402


def _rejected_judgment():
    b, _ = ack.extract_block(_out({"message_id": "AMD-x-1", "action": "rejected", "changes": [],
                                   "reason": "l'oracle impose main.tscn sur un jeu web"}))
    return _judge(b)


def test_un_desaccord_est_une_objection_en_sens_inverse_recevable_par_le_journal(tmp_path):
    d = ack.disagreement_message(_rejected_judgment(), capability="decompose", run_id="lot6-t5", message=_MSG)
    assert d["type"] == "objection" and d["type"] in MESSAGE_TYPES
    assert d["from"] == "decompose" and d["to"] == ["director"]
    assert d["in_reply_to"] == "AMD-x-1" and d["run_id"] == "lot6-t5"
    assert validate_message(d) == []
    append_message(d, journal_dir=tmp_path / "amendments")
    lu = read_messages(tmp_path / "amendments")[-1]
    assert lu["in_reply_to"] == "AMD-x-1" and lu["from"] == "decompose"


def test_les_trois_objets_restent_distinguables(tmp_path):
    """Question initiale, objection du Director, réponse négative de la capacité : trois choses."""
    from forge import director as dr
    state = dr.new_state("lot6-t5", "runm_breakout")
    objection_director = dr._objection(state, "decompose", dr.JOIN_GHOST_COVERAGE,
                                       {"regime": "VOID"}, {"last_effect": "CHANGED"})
    desaccord = ack.disagreement_message(_rejected_judgment(), capability="decompose",
                                         run_id="lot6-t5", message=_MSG)
    assert objection_director["from"] == "director" and objection_director["to"] == ["decompose"]
    assert desaccord["from"] == "decompose" and desaccord["to"] == ["director"]
    assert "in_reply_to" not in objection_director and desaccord["in_reply_to"] == "AMD-x-1"
    q = ack.question_entry(_rejected_judgment(), capability="decompose", run_id="lot6-t5",
                           disagreement_id=desaccord["id"])
    assert q["blocking"] is False and q["from"] == "decompose"
    assert set(q["to"]) == {"director", "pierre"} and q["evidence_ref"] == [desaccord["id"]]


def test_la_question_est_appendue_a_la_section_questions(blueprint):
    q = ack.question_entry(_rejected_judgment(), capability="decompose", run_id="lot6-t5",
                           disagreement_id="AMD-d-1")
    avant = list(blueprint["sections"]["questions"]["content"] or [])
    bp.write_section(blueprint, "questions", avant + [q], writer="decompose",
                     source={"path": None, "sha256": None, "status": "JOURNAL", "run_id": "lot6-t5"})
    assert blueprint["sections"]["questions"]["content"][-1]["id"] == q["id"]
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `.venv/Scripts/python.exe -m pytest forge/tests/test_reconvocation_lot6.py -q -p no:cacheprovider -k "desaccord or trois_objets or section_questions"`
Expected: FAIL — `AttributeError: module 'forge.acknowledgement' has no attribute 'disagreement_message'`.

- [ ] **Step 3: Implement**

Ajouter à `forge/acknowledgement.py` :

```python
from forge.amendment_log import new_message_id


def _now() -> str:
    from datetime import datetime, timezone
    return datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def disagreement_message(judgment: dict, *, capability: str, run_id: str, message: dict) -> dict:
    """Le DÉSACCORD : une objection en sens INVERSE (capacité -> director), distincte de l'objection
    du Director et de la question initiale (spec §4.3, correction 3 de Pierre). Le type `objection`
    existe déjà au journal ; seul le sens de circulation change."""
    issued = _now()
    return {
        "id": new_message_id(f"desaccord {capability} {run_id}", issued),
        "type": "objection", "from": capability, "to": ["director"],
        "in_reply_to": message.get("id"), "run_id": run_id,
        "subject": f"DÉSACCORD sur {message.get('id')} : {message.get('subject', '')}"[:200],
        "reason": judgment.get("reason") or "(aucune raison transmise)",
        "impact": [], "evidence_ref": [str(message.get("id"))], "blocking": False,
        "issued_at": issued,
    }


def question_entry(judgment: dict, *, capability: str, run_id: str, disagreement_id: str) -> dict:
    """La QUESTION ouverte qui suit le désaccord : arbitrage par le Director puis Pierre. Non
    bloquante — un désaccord ne gèle pas le run, il se tranche."""
    issued = _now()
    return {
        "id": new_message_id(f"arbitrage {capability} {run_id}", issued),
        "type": "question", "from": capability, "to": ["director", "pierre"],
        "run_id": run_id, "about": judgment.get("message_id"),
        "why": judgment.get("reason") or "(aucune raison transmise)",
        "evidence_ref": [disagreement_id], "blocking": False, "issued_at": issued,
    }
```

- [ ] **Step 4: Run the tests**

Run: `.venv/Scripts/python.exe -m pytest forge/tests/test_reconvocation_lot6.py -q -p no:cacheprovider`
Expected: tous verts.

---

### Task 6: Director — jugement, désaccord, objection au bon écrivain, libellé de tâche

**Files:**
- Modify: `forge/capability.py` (extraction du bloc dans `result`)
- Modify: `forge/director.py` (`_step_convoke` : `judge`, désaccord, question ; `_next_identity_action`)
- Modify: `forge/run_real.py:3644` (libellé `s3-decompo`)
- Modify: `forge/tests/test_reconvocation_lot6.py`

**Interfaces:**
- Produces: `result["acknowledgement_block"] = {"block": dict | None, "diagnostic": str}` ; mesure de décision enrichie de `acknowledgement` ; `state["acknowledged"]` (ids déjà acquittés) ; objection d'identité adressée à l'écrivain de la section.

- [ ] **Step 1: Write the failing tests**

```python
# --- Task 6 : le Director juge, transporte et objecte au bon écrivain -------------------------------


def test_le_resultat_porte_le_bloc_extrait_sans_le_juger(blueprint, tmp_path):
    fm = blueprint["sections"]["feature_map"]["content"]
    payload = ("Rapport.\n\n```json\n" + json.dumps(fm, ensure_ascii=False) + "\n```\n"
               + _out({"message_id": "AMD-x-1", "action": "applied", "changes": ["ids conservés"]}))
    res = cap.invoke_capability("decompose", blueprint, tmp_path / "run", run_id="lot6-t6", attempt=2,
                                executor=lambda p, s, pl, _o=payload: {
                                    "ok": True, "output": _o, "tokens": 0,
                                    "duration_s": 0.0, "cost_usd": 0.0},
                                audit_path=tmp_path / "a.jsonl")
    assert res["ok"]
    assert res["acknowledgement_block"]["block"]["action"] == "applied"
    assert res["acknowledgement_block"]["diagnostic"] == ""
    assert "status" not in res["acknowledgement_block"], "invoke n'a pas à juger (spec §5)"


def test_la_politique_impute_le_refus_d_identite_a_l_ecrivain_de_la_section(blueprint):
    """Le responsable vient du REGISTRE (qui écrit cette section), jamais de diagnose_join — qui
    dirait `wiremap` — ni du champ `writer` (encore `importer` après un refus). Test de POLITIQUE :
    `next_action` est une fonction pure de (blueprint, state, mesure)."""
    from forge import director as dr
    state = dr.new_state("lot6-t6b", "runm_breakout")
    state["last_problems"] = [{"code": idt.ID_REFERENCED_DROPPED, "producer": "identity_check",
                               "path": "feature_map",
                               "message": "identifiants encore cités en aval : R1c1_hud_objectif_nonvide"}]
    action = dr.next_action(blueprint, state, dr.measure(blueprint))
    assert action["code"] == idt.ID_REFERENCED_DROPPED and action["kind"] == "reconvoke"
    assert action["capability"] == "decompose", "l'objection va à l'écrivain, pas à wiremap"
    assert blueprint["sections"]["feature_map"]["writer"] == "importer"   # le piège évité
    assert "R1c1_hud_objectif_nonvide" in json.dumps(action["message"], ensure_ascii=False)
    assert action["message"]["from"] == "director" and action["message"]["to"] == ["decompose"]


def test_le_director_journalise_le_desaccord_et_ouvre_la_question(blueprint, tmp_path):
    """L'exécuteur lit l'id du message DANS LE PROMPT (le Director l'y écrit) et le rejette —
    même chemin qu'un agent réel, aucun identifiant deviné par le test."""
    import re

    from forge import director as dr
    fm = blueprint["sections"]["feature_map"]["content"]

    def executor(prompt, sp, pl):
        m = re.search(r"MESSAGE DU DIRECTOR — \w+ (AMD-[^\s\n]+)", prompt)
        bloc = _out({"message_id": m.group(1) if m else "AUCUN", "action": "rejected", "changes": [],
                     "reason": "l'oracle impose main.tscn sur un jeu web"})
        return {"ok": True, "output": "Rapport.\n\n```json\n" + json.dumps(fm, ensure_ascii=False)
                + "\n```\n" + bloc, "tokens": 0, "duration_s": 0.0, "cost_usd": 0.0}

    d = dr.Director(blueprint, tmp_path / "run", run_id="lot6-t6c", executor=executor,
                    audit_path=tmp_path / "a.jsonl", journal_dir=tmp_path / "amendments")
    d.state["last_problems"] = [{"code": idt.ID_REFERENCED_DROPPED, "producer": "identity_check",
                                 "path": "feature_map", "message": "ids cités en aval : R1c1_hud_objectif_nonvide"}]
    r = d.step()
    assert r["decision"]["measure"]["acknowledgement"]["status"] == ack.REJECTED
    desaccords = [m for m in read_messages(tmp_path / "amendments")
                  if m.get("from") == "decompose" and m.get("to") == ["director"]]
    assert len(desaccords) == 1 and desaccords[0]["in_reply_to"] == r["action"]["message"]["id"]
    questions = blueprint["sections"]["questions"]["content"] or []
    assert any(q.get("evidence_ref") == [desaccords[0]["id"]] for q in questions)


def test_un_message_ne_peut_etre_acquitte_deux_fois_dans_un_run(blueprint, tmp_path):
    """Le second acquittement du même message tombe en unknown_message (spec §4.2)."""
    from forge import director as dr
    state = dr.new_state("lot6-t6d", "runm_breakout")
    state["acknowledged"] = ["AMD-x-1"]
    b, _ = ack.extract_block(_out({"message_id": "AMD-x-1", "action": "applied"}))
    r = ack.judge(b, message=_MSG, capability="decompose", run_id="lot6-t4", effect="CHANGED",
                  already_acknowledged=set(state["acknowledged"]))
    assert r["status"] == ack.UNKNOWN_MESSAGE


def test_le_libelle_s3_n_invite_plus_au_renommage():
    from forge.run_real import default_task_by_step
    t = default_task_by_step("p", ".", profile="full")["s3-decompo"]
    assert "R1..Rn" not in t
    assert "stable" in t.lower()
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `.venv/Scripts/python.exe -m pytest forge/tests/test_reconvocation_lot6.py -q -p no:cacheprovider -k "bloc_extrait or ecrivain_de_la_section or journalise_le_desaccord or libelle_s3"`
Expected: FAIL — `KeyError: 'acknowledgement_block'`.

- [ ] **Step 3: Implement in `capability.py`**

Import : `from forge import acknowledgement as ack`. Dans le dict `result` initial : `"acknowledgement_block": None,`. Après `result["next_reason"] = ...` :

```python
    # Lot 6 (spec §4.1) : extraction SEULE — le statut dépend de l'effet, que seul le Director connaît.
    blk, why = ack.extract_block(output)
    result["acknowledgement_block"] = {"block": blk, "diagnostic": why}
```

- [ ] **Step 4: Implement in `director.py`**

Constante et politique — après `NO_PROGRESS_REPEATED` :

```python
ID_REFERENCED_DROPPED = idt.ID_REFERENCED_DROPPED   # import : from forge import identity as idt
```

Dans `next_action`, **avant** la porte de suffisance (après la boucle des sections absentes) :

```python
    # Lot 6 : un refus d'identité vise l'ÉCRIVAIN de la section (le `path` du problème), jamais
    # `wiremap` par défaut comme le ferait diagnose_join.
    for p in state.get("last_problems") or []:
        if p.get("code") != ID_REFERENCED_DROPPED:
            continue
        section = str(p.get("path") or "")
        # L'écrivain vient du REGISTRE (qui `writes` cette section), jamais du champ `writer` du
        # Blueprint : après un refus, `writer` porte encore l'auteur de la version précédente
        # (`importer` sur un Blueprint fraîchement importé) — ce serait imputer à la mauvaise partie.
        capability = next((n for n in (registry or cap.load_registry())
                           if cap.spec(n, registry)["writes"] == section), None)
        key = _signal_key(section, capability or "?")
        if key in state.get("accepted", []):
            continue
        sig = _sig(state, key)
        if sig["no_effect"] >= MAX_NO_EFFECT:
            return _halt_question(state, ID_REFERENCED_DROPPED, capability or "?",
                                  f"identité de {section} non rétablie après {sig['no_effect']} convocations",
                                  options=["accept", "revert", "skip"], signal=key)
        return {"kind": "reconvoke", "capability": capability, "code": ID_REFERENCED_DROPPED,
                "signal": key, "path": section, "measure": {"referenced_dropped": p.get("message")},
                "reason": f"identifiants cités en aval supprimés de {section}",
                "message": _objection_identity(state, capability or "?", section, p)}
```

Objection dédiée, à côté de `_objection` :

```python
def _objection_identity(state: dict, capability: str, section: str, problem: dict) -> dict:
    issued = _now()
    return {
        "id": new_message_id(f"{ID_REFERENCED_DROPPED} {capability} {state['run_id']}", issued),
        "type": "objection", "from": "director", "to": [capability], "run_id": state["run_id"],
        "subject": f"{ID_REFERENCED_DROPPED} : des identifiants de {section} cités en aval ont disparu",
        "reason": (f"{problem.get('message')}. Reprends ta production précédente et CONSERVE ces "
                   "identifiants à l'identique. Un retrait ne se déclare que si plus rien en aval ne "
                   "le cite. Réponds par un bloc ```acquittement```."),
        "impact": [section, "porte de suffisance"], "evidence_ref": [f"decisions.jsonl#{state['steps']}"],
        "blocking": False, "issued_at": issued,
    }
```

Dans `_step_convoke`, après le calcul de `effect` / `progress` et **avant** `self._decide(...)` :

```python
        # Lot 6 : le Director juge l'acquittement (il connaît l'effet), transporte le désaccord.
        jugement = None
        if action.get("message"):
            blk = (res.get("acknowledgement_block") or {}).get("block")
            jugement = ack.judge(blk, message=action["message"], capability=capability,
                                 run_id=self.run_id, effect=effect,
                                 already_acknowledged=set(self.state.setdefault("acknowledged", [])))
            if jugement["status"] in (ack.ACKNOWLEDGED, ack.CLAIMED_WITHOUT_EFFECT, ack.REJECTED):
                self.state["acknowledged"].append(jugement["message_id"])
            if jugement["status"] == ack.REJECTED:
                desaccord = ack.disagreement_message(jugement, capability=capability,
                                                     run_id=self.run_id, message=action["message"])
                try:
                    append_message(desaccord, journal_dir=self.journal_dir)
                except Exception:  # noqa: BLE001 — le désaccord ne casse jamais le run
                    desaccord = None
                if desaccord is not None:
                    q = ack.question_entry(jugement, capability=capability, run_id=self.run_id,
                                           disagreement_id=desaccord["id"])
                    courant = list(self.blueprint["sections"]["questions"].get("content") or [])
                    bp.write_section(self.blueprint, "questions", courant + [q], writer=capability,
                                     source={"path": None, "sha256": None, "status": "JOURNAL",
                                             "run_id": self.run_id})
```

et, dans le `measure=` de `self._decide(...)`, remplacer `"consumption": self._consumption(action.get("message"), res)` par :

```python
                     "acknowledgement": jugement, "consumption": self._consumption(action.get("message"), res),
```

Imports à compléter en tête de `director.py` : `from forge import acknowledgement as ack`, `from forge import identity as idt`, `from forge.amendment_log import append_message` (les autres existent déjà).

- [ ] **Step 5: Implement the task wording in `run_real.py`**

Remplacer (l.3644) :

```python
            f"Décompose le projet '{project}' en features numérotées R1..Rn (une ligne "
            "par règle de jeu : nom, comportement observable, condition de preuve). "
            "Texte seul, aucun fichier écrit."
```

par :

```python
            f"Décompose le projet '{project}' en features (une ligne par règle de jeu : nom, "
            "comportement observable, condition de preuve). Donne à chaque capacité un identifiant "
            "STABLE et lisible : il sera cité en aval par la WireMap, et une re-convocation doit le "
            "conserver à l'identique. Texte seul, aucun fichier écrit."
```

- [ ] **Step 6: Run the tests**

Run: `.venv/Scripts/python.exe -m pytest forge/tests/test_reconvocation_lot6.py forge/tests/test_transport_lot5.py forge/tests/test_slice_lot4.py forge/tests/test_director_lot3.py forge/tests/test_capability_lot2.py -q -p no:cacheprovider -m "not gpu_window"`
Expected: tous verts.

---

### Task 7: Suite complète, re-convocation réelle, handoff, fiche de commit

**Files:**
- Create (par la sonde) : `EVIDENCE/runs/lot6_identity_probe/`, `EVIDENCE/reports/lot6_reconvocation/`
- Modify: `00_CURRENT_CONTEXT.md`

- [ ] **Step 1: Full suite + T0**

Run: `.venv/Scripts/python.exe -m pytest forge/tests/ -m "not gpu_window" -q -p no:cacheprovider --deselect forge/tests/test_observer_integration_real.py`
Expected: les Lots 2 à 6 verts ; total attendu ≈ 2 511 verts + les nouveaux ; les 42 échecs restent EXACTEMENT la population V1 classée au Lot 0 (comparer la liste `FAILED` à celle du Lot 5, aucun fichier neuf dedans).

- [ ] **Step 2: One real re-convocation (proof b)**

Le Blueprint du Lot 5 porte `feature_map` v3 avec les ids `CAP_*` et une `wiremap.design` qui cite les ids longs de la baseline : la re-convocation doit donc CONSERVER les `CAP_*` (ce sont eux qui sont dans la section) et l'objection d'identité est le cas nominal si l'agent renomme.

```bash
mkdir -p EVIDENCE/reports/lot6_reconvocation
cp EVIDENCE/reports/lot5_transport/GAME_BLUEPRINT.lot5_probe.json EVIDENCE/reports/lot6_reconvocation/GAME_BLUEPRINT.lot6_in.json
.venv/Scripts/python.exe -m forge.capability invoke decompose \
  --blueprint EVIDENCE/reports/lot6_reconvocation/GAME_BLUEPRINT.lot6_in.json \
  --run-id lot6_identity_probe --attempt 2 \
  --out EVIDENCE/reports/lot6_reconvocation/GAME_BLUEPRINT.lot6_probe.json \
  > EVIDENCE/reports/lot6_reconvocation/invoke_decompose_probe.stdout.txt 2>&1
```

Vérifier mécaniquement :

```bash
.venv/Scripts/python.exe - <<'EOF'
import json
from pathlib import Path
rd = Path("EVIDENCE/runs/lot6_identity_probe")
res = json.loads((rd / "capability_result_decompose_a2.json").read_text(encoding="utf-8"))
print("ok", res["ok"], "| identity", json.dumps(res["identity"], ensure_ascii=False)[:400])
print("problems", [p["code"] for p in res["problems"]])
print("acquittement", res["acknowledgement_block"])
print("cost", res["cost"], "| model_used", res["model_used"])
prompt = Path(res["prompt_file"]).read_text(encoding="utf-8")
print("production précédente injectée :", "## TA PRODUCTION PRÉCÉDENTE" in prompt)
print("ids attendus dans le prompt :", "CAP_objectif_hud" in prompt)
EOF
```

Les deux issues sont des preuves valides et se consignent telles quelles : ids conservés (`identity.ok == True`, section v4) **ou** refus `ID_REFERENCED_DROPPED` avec section intacte. Une troisième issue (aucun rapport d'identité) serait un défaut de câblage à corriger.

- [ ] **Step 3: Update the handoff** (`00_CURRENT_CONTEXT.md`, ≤ 100 lignes) : bloc Lot 6 — clé d'identité mesurée pour `wiremap` (ou UNKNOWN motivé), refus `ID_REFERENCED_DROPPED`, cinq statuts d'acquittement, désaccord distinct de l'objection, résultat de la sonde, tests.

- [ ] **Step 4: Fiche de commit pour Pierre (aucun commit sans GO)**

Périmètre : `forge/identity.py`, `forge/acknowledgement.py`, `forge/capability.py`, `forge/director.py`, `forge/capability_registry.yaml`, `forge/run_real.py`, `forge/tests/test_reconvocation_lot6.py`, `docs/superpowers/specs/2026-09-04-lot6-reconvocation-design.md`, `docs/superpowers/plans/2026-09-04-lot6-reconvocation.md`, `EVIDENCE/reports/lot6_reconvocation/`, `EVIDENCE/runs/lot6_identity_probe/`, `00_CURRENT_CONTEXT.md`. Message proposé :

```
feat(v2): Lot 6 — contrat de re-convocation : identité de section (refus ID_REFERENCED_DROPPED) et acquittement structuré (5 statuts, désaccord distinct)
```

---

## Self-review

- **Couverture de la spec** : §3.1 registre (T1) · §3.2 mesure `wiremap` UNKNOWN (T1 step 1) · §3.3 production précédente (T3) · §3.4 comparaison et refus, correction 1 incluse (T2, T3) · §3.5 objection à l'écrivain (T6) · §3.6 libellé (T6) · §4.1 fence (T4) · §4.2 cinq statuts + double acquittement (T4) · §4.3 désaccord puis question, correction 3 (T5) · §5 répartition des rôles, invoke n'a aucun paramètre neuf (T3, T6) · §6 preuve, correction 4 incluse (T4, T7).
- **Placeholders** : aucun. `UNKNOWN` pour `wiremap.design` est une décision de Pierre avec procédure de résolution, pas un trou.
- **Cohérence des noms** : `load_identity`, `identity_of`, `extract_ids`, `declared_retired`, `downstream_ids`, `compare`, `ID_REFERENCED_DROPPED`, `extract_block`, `judge`, `disagreement_message`, `question_entry`, `ACKNOWLEDGED`/`CLAIMED_WITHOUT_EFFECT`/`REJECTED`/`UNKNOWN_MESSAGE`/`NOT_ACKNOWLEDGED`, `result["identity"]`, `result["acknowledgement_block"]`, `state["acknowledged"]` — identiques entre tâches, tests et spec.
- **Trois fragilités corrigées pendant la rédaction, à ne pas réintroduire** : (1) l'écrivain d'une section vient du REGISTRE, jamais du champ `writer` du Blueprint — après un refus il vaut encore `importer` ; (2) la politique se teste sur `next_action` (fonction pure), jamais en pilotant un `Director` complet dont la première action serait `gate_open` ; (3) un exécuteur factice qui doit citer un identifiant de message le LIT dans le prompt, il ne le devine pas.

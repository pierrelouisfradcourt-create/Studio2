# Lot 5 — Transport et propriétaires : Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Que `invoke_capability` cesse de réintroduire « déclaré ≠ exécuté » : chaque mécanisme de production perdu par le Lot 2 a un propriétaire nommé au registre, les mesures qui mentaient mesurent la cible, les trois lignées de preuve et le pré-mortem voyagent avec la convocation, et les trois réserves du commit `523bd07` sont fermées ou explicitement assignées.

**Architecture:** Aucun mécanisme nouveau. `forge/capability.py` réutilise les fonctions de production de `run_real` / `context_manifest` / `studio_link` / `driver` (import, jamais recopie) ; `forge/capability_registry.yaml` gagne un bloc `transport` (propriétaire par mécanisme) et un `timeout_policy` par capacité ; `forge/director.py` transmet le retour du matérialiseur et le `run_id` des objections ; `forge/build_orchestrator.py` filtre le dossier par `run_id`. Tout est prouvé par `forge/tests/test_transport_lot5.py` sur la forme de production réelle (Blueprint importé de la baseline, sorties réelles d'agents), sans appel LLM, puis par UNE re-convocation réelle.

**Tech Stack:** Python 3.12 (`.venv` de Studio2), PyYAML, pytest (`-m "not gpu_window"`), node pour `check_decompo.mjs`.

## Global Constraints

- Dépôt : `C:\Users\Studio-Dev\Desktop\Studio2` (V2). V1 (`C:\TACTICAL_CHESS_STUDIO`) en lecture seule. Nommer le cwd sur chaque commande git (`git -C`).
- Aucun commit sans GO explicite de Pierre ; un GO = une commande. Aucun push.
- Aucun appel LLM dans les tests. La re-convocation réelle (Task 8) coûte ~1,4 $ et n'est lancée qu'une fois, en dernier.
- `software_verdict` vient UNIQUEMENT des reçus d'oracle : rien ici ne touche `verdict.py` ni `verify_run.py`.
- Vocabulaire : OK / FAIL / BLOCKED. Rapport final : software_verdict · evidence_verdict: MECHANICAL_VALIDATION_ONLY · claim_verdict: NO_CLAIM_ALLOWED.
- Interpréteur : `.venv/Scripts/python.exe` de Studio2. Commande de test : `.venv/Scripts/python.exe -m pytest forge/tests/test_transport_lot5.py -q -p no:cacheprovider`.
- `encoding="utf-8"` explicite sur tout `open()`/`read_text`/`write_text`. Chemins relatifs au repo root dans les artefacts.
- Ne jamais toucher `EVIDENCE/runs/runm_breakout/` ni `EVIDENCE/runs/v2_breakout_slice_r1/`.

---

### Task 1: Registre — bloc `transport` (propriétaires) et `timeout_policy` par capacité

**Files:**
- Modify: `forge/capability_registry.yaml` (en-tête l.1-27 ; chaque capacité l.31-240)
- Modify: `forge/capability.py:76-158` (`load_registry`, `spec`)
- Create: `forge/tests/test_transport_lot5.py`

**Interfaces:**
- Produces: `capability.load_transport(path: Path | None = None) -> dict` (mécanisme → `{owner, status, proof|reason}`) ; `capability.TRANSPORT_OWNERS = ("invoke", "director", "driver", "pierre")` ; `capability.TRANSPORT_STATUSES = ("carried", "director", "deferred", "dropped")` ; `spec(name)["timeout_policy"] == {"timeout_s": float, "launch": "attached"|"detached", ...}`.

- [ ] **Step 1: Write the failing tests**

```python
"""Lot 5 (plan V2, GO Pierre 2026-09-04) — transport et propriétaires.

Ce que ces tests prouvent (forme de production réelle : Blueprint importé de la baseline M ter,
sorties réelles d'agents, matérialiseurs et validateurs de run_real, oracle check_decompo.mjs ;
aucun appel LLM) :
  - chaque mécanisme de production identifié comme perdu par l'audit du 2026-09-03 a un
    propriétaire nommé au registre ; ce qui est déclaré `carried` par `invoke` est réellement
    présent dans le résultat ou sur disque ;
  - le manifest de dispatch d'une convocation mesure les SECTIONS DU BLUEPRINT lues (jamais
    l'ancienne table d'amont) ; le manifest d'exécution, le spawn_link et la lignée RETURN sont
    écrits ; le modèle MESURÉ est rendu distinct du modèle déclaré ;
  - le pré-mortem et le retour du matérialiseur atteignent le prompt de re-convocation ; un
    échec de convocation est journalisé dans le run ;
  - timeout_policy par capacité consommée ; prepare_build ne touche jamais forge/oracles.json ;
  - les objections portent leur run_id et le dossier HumanGate ne liste que celles du run.
NO_CLAIM_ALLOWED.
"""
from __future__ import annotations

import hashlib
import json
import shutil
from pathlib import Path

import pytest

from forge import blueprint as bp
from forge import build_orchestrator as bo
from forge import capability as cap
from forge import director as dr
from forge.amendment_log import append_message, read_messages
from forge.blueprint_import import import_run_dir

_REPO_ROOT = Path(__file__).resolve().parents[2]
_RUN_DIR = _REPO_ROOT / "EVIDENCE" / "runs" / "runm_breakout"
_BRIEF = _REPO_ROOT / "EVIDENCE" / "briefs" / "runm_breakout" / "project_brief.yaml"
_S3_OUTPUT = _RUN_DIR / "artifacts" / "s3-decompo.txt"

pytestmark = [
    pytest.mark.skipif(not (_RUN_DIR / "state.json").exists() or not _S3_OUTPUT.exists(),
                       reason="baseline M ter absente"),
    pytest.mark.skipif(shutil.which("node") is None, reason="node absent"),
]

# Les 22 pertes de l'audit (LOSS_RISKS_FOR_LOT2, 2026-09-03) + les 3 réserves du commit 523bd07,
# sous leur identifiant de registre. Un mécanisme absent du registre = un propriétaire manquant.
AUDIT_MECHANISMS = (
    "prompt_contract", "prompt_task", "restitution_rule", "premortem", "project_brief_bible_s0",
    "materialize_feedback", "escalation_ladder", "provider_routing", "timeout_policy",
    "execution_manifest", "dispatch_sources_blueprint", "return_reason", "spawn_link",
    "model_measured", "telemetry", "next_reason", "error_journal", "lessons_failure_events",
    "raw_output_persisted", "repair_and_annex_materializers", "executor_diagnostic",
    "cost_cumulative", "freeze_and_design_gates", "add_dir", "persistent_state_resume",
    "subentry_provenance", "oracles_json_global_registration", "objections_by_run_id",
)


@pytest.fixture
def blueprint():
    return import_run_dir(_RUN_DIR, brief_path=_BRIEF, project="runm_breakout")


def _fake_executor(output: str | None = None, *, model_used=None, calls: list | None = None, ok: bool = True,
                   reason: str = ""):
    text = output if output is not None else _S3_OUTPUT.read_text(encoding="utf-8")

    def executor(prompt, sp, payload):
        if calls is not None:
            calls.append({"prompt": prompt, "model": payload.model, "etape": sp["etape"]})
        res = {"ok": ok, "output": text, "tokens": 12, "duration_s": 1.5, "cost_usd": 0.01,
               "returncode": 0, "process_state": "MODEL_REACHED", "stderr_tail": "", "timeout": False,
               "session_id": "sess-test", "tools_used": {"Read": 2}}
        if model_used is not None:
            res["model_used"] = model_used
        if not ok:
            res["reason"] = reason
        return res
    return executor


# --- Task 1 : registre --------------------------------------------------------------------------


def test_chaque_mecanisme_perdu_a_un_proprietaire_nomme():
    transport = cap.load_transport()
    manquants = [m for m in AUDIT_MECHANISMS if m not in transport]
    assert not manquants, f"mécanismes sans propriétaire au registre : {manquants}"
    for name, decl in transport.items():
        assert decl["owner"] in cap.TRANSPORT_OWNERS, name
        assert decl["status"] in cap.TRANSPORT_STATUSES, name
        if decl["status"] in ("deferred", "dropped"):
            assert decl.get("reason"), f"{name}: deferred/dropped sans raison écrite"
        else:
            assert decl.get("proof"), f"{name}: carried/director sans preuve nommée"


def test_timeout_policy_declaree_par_capacite():
    reg = cap.load_registry()
    for name in reg:
        pol = cap.spec(name, reg)["timeout_policy"]
        assert float(pol["timeout_s"]) > 0, name
        assert pol["launch"] in ("attached", "detached"), name
    assert cap.spec("builder", reg)["timeout_policy"] == {
        "timeout_s": 5400, "launch": "detached",
        "note": "leçon Lot 4 : un builder borné à 9 min par le plafond Bash 10 min a été tué deux fois ; lancer détaché"}
    assert cap.spec("decompose", reg)["timeout_policy"]["timeout_s"] == 1800
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `.venv/Scripts/python.exe -m pytest forge/tests/test_transport_lot5.py -q -p no:cacheprovider -k "proprietaire or timeout_policy"`
Expected: FAIL — `AttributeError: module 'forge.capability' has no attribute 'load_transport'` puis `KeyError: 'timeout_policy'`.

- [ ] **Step 3: Add the `transport` block and `timeout_policy` to the registry**

Insérer dans `forge/capability_registry.yaml`, après la ligne `schema: CAPABILITY_REGISTRY/v0` (l.27) et avant `capabilities:` :

```yaml
# ------------------------------------------------------------------------------------------
# Lot 5 (2026-09-04, GO Pierre) — TRANSPORT : ce que la convocation emporte de la chaîne de
# production (audit 2026-09-03, LOSS_RISKS_FOR_LOT2 : 22 mécanismes + 3 réserves du commit 523bd07).
# Chaque mécanisme a UN propriétaire : invoke (forge.capability) · director (forge.director) ·
# driver (reste au chemin ORDER, non transporté) · pierre (geste humain sous GO).
# status : carried (présent dans invoke, preuve = champ du résultat ou fichier du run) · director
# (porté par le Director, preuve nommée) · deferred (déclaré, pas encore porté — dit, jamais tu) ·
# dropped (perdu volontairement, raison écrite). Un test impose : tout mécanisme de l'audit est ici.
transport:
  prompt_contract:            {owner: invoke,   status: carried,  proof: "result.prompt_file (13 sections du contrat)"}
  prompt_task:                {owner: invoke,   status: carried,  proof: "result.prompt_file (TÂCHE CONCRÈTE, default_task_by_step)"}
  restitution_rule:           {owner: invoke,   status: carried,  proof: "result.prompt_file (RESTITUTION_RULE via payload.prompt)"}
  premortem:                  {owner: invoke,   status: carried,  proof: "result.premortem_lines ; section PRÉ-MORTEM du prompt"}
  project_brief_bible_s0:     {owner: invoke,   status: deferred, reason: "s0-contrat non invocable v0 ; brief/bible = sections identity/vision/constraints du Blueprint"}
  materialize_feedback:       {owner: director, status: carried,  proof: "result.feedback_applied ; section RETOUR DU MATÉRIALISEUR à la re-convocation"}
  escalation_ladder:          {owner: director, status: director, proof: "decisions.jsonl (kind build, model_override) ; ESC-1 builder seul"}
  provider_routing:           {owner: invoke,   status: deferred, reason: "route_step non porté : les capacités lmstudio (redteam_plan) ne sont pas invocables v0"}
  timeout_policy:             {owner: invoke,   status: carried,  proof: "result.timeout_s = capabilities.<nom>.timeout_policy.timeout_s"}
  execution_manifest:         {owner: invoke,   status: carried,  proof: "context/<etape>.manifest.jsonl kind=execution"}
  dispatch_sources_blueprint: {owner: invoke,   status: carried,  proof: "context/<etape>.manifest.jsonl kind=dispatch sources[].role=blueprint_section"}
  return_reason:              {owner: invoke,   status: carried,  proof: "context/<etape>.return.manifest.jsonl ; result.return_reason"}
  spawn_link:                 {owner: invoke,   status: carried,  proof: "context/spawn_links.jsonl (schéma forge.spawn_link.v1, attestation self)"}
  model_measured:             {owner: invoke,   status: carried,  proof: "result.model_used (mesuré au flux) ≠ result.model (déclaré)"}
  telemetry:                  {owner: director, status: deferred, reason: "forge_telemetry.jsonl n'est écrit que par le driver ; le coût vit dans decisions.jsonl"}
  next_reason:                {owner: invoke,   status: carried,  proof: "result.next_reason (ForgeDriver._parse_next_reason)"}
  error_journal:              {owner: invoke,   status: carried,  proof: "<run_dir>/error_journal.jsonl (studio_link.record_error) relu par le pré-mortem suivant"}
  lessons_failure_events:     {owner: director, status: deferred, reason: "promotion des leçons et FailureEvent non portées hors driver"}
  raw_output_persisted:       {owner: invoke,   status: carried,  proof: "result.output_file = artifacts/<etape>.txt"}
  repair_and_annex_materializers: {owner: invoke, status: deferred, reason: "réparation Qwen, jointure, markdown/yaml/loop/economy/design_questions : capacités prisme/s0/GM non invocables v0"}
  executor_diagnostic:        {owner: invoke,   status: carried,  proof: "result.executor_diagnostic (returncode, process_state, stderr_tail, timeout, transient_retries)"}
  cost_cumulative:            {owner: director, status: director, proof: "HUMANGATE_DOSSIER cost_usd_llm = somme des decisions.jsonl"}
  freeze_and_design_gates:    {owner: director, status: deferred, reason: "gel des règles porté par build_orchestrator.prepare_build ; gate design (design_questions) et post-gate artbible non portés"}
  add_dir:                    {owner: director, status: carried,  proof: "Director passe add_dir=GAMES/<projet> au builder (Lot 4)"}
  persistent_state_resume:    {owner: director, status: director, proof: "director_state.json + decisions.jsonl (Lot 3)"}
  subentry_provenance:        {owner: invoke,   status: carried,  proof: "result.blueprint_inputs[].entry_sha256 (sha de la sous-entrée lue, pas du composite)"}
  oracles_json_global_registration: {owner: pierre, status: dropped, reason: "R3 : prepare_build n'écrit que l'oracles.json du run ; toute entrée dans forge/oracles.json est un geste HumanGate sous GO (réserve 1 du commit 523bd07)"}
  objections_by_run_id:       {owner: director, status: carried,  proof: "objections émises avec run_id ; HUMANGATE_DOSSIER objections_autres_runs (réserve 3)"}
```

Puis ajouter, dans CHAQUE capacité, après la ligne `escalation:` :

```yaml
    timeout_policy: {timeout_s: 1800, launch: attached}
```

sauf `builder` :

```yaml
    timeout_policy: {timeout_s: 5400, launch: detached, note: "leçon Lot 4 : un builder borné à 9 min par le plafond Bash 10 min a été tué deux fois ; lancer détaché"}
```

- [ ] **Step 4: Expose transport and timeout_policy in `capability.py`**

Après `REGISTRY_SCHEMA = "CAPABILITY_REGISTRY/v0"` (l.55) :

```python
TRANSPORT_OWNERS = ("invoke", "director", "driver", "pierre")
TRANSPORT_STATUSES = ("carried", "director", "deferred", "dropped")
DEFAULT_TIMEOUT_POLICY = {"timeout_s": DEFAULT_STEP_TIMEOUT_S, "launch": "attached"}
```

Remplacer `load_registry` (l.76-83) par :

```python
def _load_registry_document(path: Path | None = None) -> dict:
    data = yaml.safe_load(Path(path or REGISTRY_PATH).read_text(encoding="utf-8")) or {}
    if data.get("schema") != REGISTRY_SCHEMA:
        raise CapabilityError(f"registre : schema {data.get('schema')!r} != {REGISTRY_SCHEMA!r}")
    return data


def load_registry(path: Path | None = None) -> dict:
    caps = _load_registry_document(path).get("capabilities")
    if not isinstance(caps, dict) or not caps:
        raise CapabilityError("registre : `capabilities` absent ou vide")
    return caps


def load_transport(path: Path | None = None) -> dict:
    """Lot 5 — propriétaire de chaque mécanisme de production emporté ou non par la convocation."""
    transport = _load_registry_document(path).get("transport")
    if not isinstance(transport, dict) or not transport:
        raise CapabilityError("registre : `transport` absent ou vide (Lot 5)")
    for name, decl in transport.items():
        if not isinstance(decl, dict) or decl.get("owner") not in TRANSPORT_OWNERS \
                or decl.get("status") not in TRANSPORT_STATUSES:
            raise CapabilityError(f"registre : transport {name!r} mal déclaré (owner/status)")
    return transport
```

Dans `spec()` (l.102-158), ajouter avant `"reads":` :

```python
        "timeout_policy": dict(decl.get("timeout_policy") or DEFAULT_TIMEOUT_POLICY),
```

- [ ] **Step 5: Run the tests**

Run: `.venv/Scripts/python.exe -m pytest forge/tests/test_transport_lot5.py -q -p no:cacheprovider -k "proprietaire or timeout_policy"`
Expected: `2 passed`.

Run aussi : `.venv/Scripts/python.exe -m pytest forge/tests/test_capability_lot2.py -q -p no:cacheprovider` → `11 passed` (le registre consolidé reste égal aux tables).

---

### Task 2: Fidélité du résultat — sha de sous-entrée, modèle mesuré, diagnostic, next_reason

**Files:**
- Modify: `forge/capability.py:173-199` (`_render_blueprint_inputs`), `:291-312` (résultat initial), `:364-372` (après l'exécuteur), `:390-398` (après `output`)
- Test: `forge/tests/test_transport_lot5.py`

**Interfaces:**
- Produces: `result["blueprint_inputs"][i]["entry_sha256"]`, `result["model_used"]` (list[str] | None), `result["model_measured"]` (bool), `result["executor_diagnostic"]` (dict), `result["next_reason"]` (str).

- [ ] **Step 1: Write the failing tests**

```python
# --- Task 2 : fidélité du résultat --------------------------------------------------------------


def test_le_resultat_porte_le_modele_mesure_et_la_provenance_des_sous_entrees(blueprint, tmp_path):
    res = cap.invoke_capability("decompose", blueprint, tmp_path / "run", run_id="lot5-t2", attempt=1,
                                executor=_fake_executor(model_used=["claude-opus-4-8"]),
                                audit_path=tmp_path / "audit.jsonl")
    assert res["ok"], res["problems"]
    assert res["model"] == "claude-opus-4-8"
    assert res["model_used"] == ["claude-opus-4-8"] and res["model_measured"] is True
    assert res["executor_diagnostic"]["process_state"] == "MODEL_REACHED"
    assert res["executor_diagnostic"]["tools_used"] == {"Read": 2}
    assert isinstance(res["next_reason"], str)
    shas = {i["section"]: i["entry_sha256"] for i in res["blueprint_inputs"]}
    # trois sous-entrées de `understanding` : trois contenus distincts, trois shas distincts
    assert len({shas["understanding.prisme"], shas["understanding.worldscan"],
                shas["understanding.product_snapshot"]}) == 3
    assert shas["understanding.prisme"] == bp.content_sha256(
        blueprint["sections"]["understanding"]["content"]["prisme"]["content"])


def test_sans_flux_mesure_le_modele_reste_declare_et_dit_non_mesure(blueprint, tmp_path):
    res = cap.invoke_capability("decompose", blueprint, tmp_path / "run", run_id="lot5-t2b", attempt=1,
                                executor=_fake_executor(), audit_path=tmp_path / "audit.jsonl")
    assert res["ok"]
    assert res["model_used"] is None and res["model_measured"] is False
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `.venv/Scripts/python.exe -m pytest forge/tests/test_transport_lot5.py -q -p no:cacheprovider -k "mesure"`
Expected: FAIL — `KeyError: 'model_used'`.

- [ ] **Step 3: Implement**

Dans `_render_blueprint_inputs` (l.173-199), remplacer l'`inputs.append(...)` par :

```python
        inputs.append({"section": ref, "version": meta["version"],
                       "content_sha256": meta["content_sha256"],
                       "entry_sha256": bp.content_sha256(content)})
```

Dans le dict `result` initial (l.301-310), ajouter les clés :

```python
        "model_used": None, "model_measured": False, "executor_diagnostic": None, "next_reason": "",
```

Après `res = ex(prompt, sp, payload) or {}` (l.365), ajouter :

```python
    mesure = res.get("model_used")
    result["model_used"] = list(mesure) if isinstance(mesure, (list, tuple)) else (mesure or None)
    result["model_measured"] = bool(result["model_used"])
    result["executor_diagnostic"] = {k: res.get(k) for k in (
        "returncode", "process_state", "stderr_tail", "timeout", "transient_retries", "session_id", "tools_used")}
```

Après `output = str(res.get("output") or "")` (l.390), ajouter :

```python
    result["next_reason"] = ForgeDriver._parse_next_reason(output)
```

et l'import en tête (après `from forge.escalate import ...`) :

```python
from forge.driver import ForgeDriver, SPAWN_LINK_SCHEMA
```

- [ ] **Step 4: Run the tests**

Run: `.venv/Scripts/python.exe -m pytest forge/tests/test_transport_lot5.py forge/tests/test_capability_lot2.py -q -p no:cacheprovider`
Expected: tous verts.

---

### Task 3: Le manifest de dispatch mesure les sections du Blueprint (L8)

**Files:**
- Modify: `forge/context_manifest.py:338-407` (`build_dispatch_manifest_record`, `append_dispatch_manifest`)
- Modify: `forge/dispatch.py:539-551` (signature `prepare_dispatch`) et `:627-631` (appel du manifest)
- Modify: `forge/capability.py:331-353` (ordre : lectures Blueprint AVANT la porte)
- Test: `forge/tests/test_transport_lot5.py`

**Interfaces:**
- Produces: `prepare_dispatch(..., sources_override: list[dict] | None = None)` ; `append_dispatch_manifest(..., sources_override=None)` ; `build_dispatch_manifest_record(..., sources_override=None)`. Un enregistrement de source Blueprint : `{"path": "blueprint:<section>", "role": "blueprint_section", "exists": True, "sha256": <entry_sha256>, "version": <int>}`.

- [ ] **Step 1: Write the failing test**

```python
# --- Task 3 : le manifest mesure la cible ---------------------------------------------------------


def _manifest_lines(run_dir: Path, etape: str) -> list[dict]:
    p = run_dir / "context" / f"{etape}.manifest.jsonl"
    return [json.loads(l) for l in p.read_text(encoding="utf-8").splitlines() if l.strip()]


def test_le_manifest_de_dispatch_cite_les_sections_lues_et_jamais_l_ancienne_table(blueprint, tmp_path):
    res = cap.invoke_capability("decompose", blueprint, tmp_path / "run", run_id="lot5-t3", attempt=1,
                                executor=_fake_executor(), audit_path=tmp_path / "audit.jsonl")
    assert res["ok"]
    dispatch = [r for r in _manifest_lines(tmp_path / "run", "s3-decompo") if r["kind"] == "dispatch"][0]
    roles = [s["role"] for s in dispatch["sources"]]
    assert "upstream" not in roles, "le manifest mesure encore _UPSTREAM_BY_STEP"
    bps = [s for s in dispatch["sources"] if s["role"] == "blueprint_section"]
    assert {s["path"] for s in bps} == {f"blueprint:{i['section']}" for i in res["blueprint_inputs"]}
    assert all(s["exists"] and s["sha256"] and s["version"] >= 1 for s in bps)
    assert roles[0] == "contract" and roles[-1] == "registry"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `.venv/Scripts/python.exe -m pytest forge/tests/test_transport_lot5.py -q -p no:cacheprovider -k "ancienne_table"`
Expected: FAIL — `AssertionError: le manifest mesure encore _UPSTREAM_BY_STEP`.

- [ ] **Step 3: Implement in `context_manifest.py`**

Signature de `build_dispatch_manifest_record` (l.338-345) : ajouter `sources_override: list[dict] | None = None,` après `reason`. Remplacer la ligne `sources = resolve_dispatch_sources(etape, contract, run_dir=run_dir, caps_path=caps_path)` par :

```python
    if sources_override is not None:
        # Lot 5 (L8) : l'appelant SAIT d'où vient le contexte (sections du Blueprint) — la table
        # amont d'ORDER ne mesure pas cette convocation. Contrat + mandatory_read + registre
        # restent mesurés ; les sources fournies prennent la place des `upstream`.
        base = resolve_dispatch_sources(etape, contract, run_dir=None, caps_path=caps_path)
        sources = base[:-1] + [dict(s) for s in sources_override] + base[-1:]
    else:
        sources = resolve_dispatch_sources(etape, contract, run_dir=run_dir, caps_path=caps_path)
```

Signature de `append_dispatch_manifest` (l.385-391) : ajouter `sources_override: list[dict] | None = None,` et le passer : `model_executed=model_executed, reason=reason, sources_override=sources_override,`.

- [ ] **Step 4: Implement in `dispatch.py`**

Signature de `prepare_dispatch` (l.539-551) : ajouter `sources_override: list | None = None,` après `contracts_dir`. Dans l'appel (l.627-630) : `caps_path=caps_path, model_executed=model_executed, reason=reason, sources_override=sources_override,`.

- [ ] **Step 5: Reorder in `capability.py`**

Remplacer le bloc « 1. la porte » + « 2. le prompt » (l.331-360) par :

```python
    # 1. le contexte, depuis le Blueprint — AVANT la porte, pour que le manifest le mesure (L8)
    projections = _materialize_reads(blueprint, sp["reads"], run_dir)
    bp_section, inputs = _render_blueprint_inputs(blueprint, sp["reads"])
    result["blueprint_inputs"] = inputs
    result["projections"] = projections
    sources_override = [{"path": f"blueprint:{i['section']}", "role": "blueprint_section", "exists": True,
                         "sha256": i["entry_sha256"], "version": i["version"]} for i in inputs]

    # 2. la porte — un dispatch signé, puis la même vérification que le hook
    payload = prepare_dispatch(
        sp["etape"], run_id, audit_path=audit_path, run_dir=run_dir, profile=None,
        attempt=attempt, reason={"signal": "convocation", "by": "forge.capability", "capability": name},
        model_executed=model_override, sources_override=sources_override,
    )
    result["audit"]["prepared"] = True
    result["model"] = payload.model
    result["model_executed"] = model_override or payload.model
    if model_override:   # escalade (portee : cette etape seule, ESC-1) : le payload porte le modele reel
        payload = dataclass_replace(payload, model=model_override)
    allowed, why = check_spawn(payload.prompt, audit_path=audit_path)
    result["audit"]["spawn_allowed"] = allowed
    if not allowed:
        result["problems"].append(_problem(SPAWN_REFUSED, "hook_guard.check_spawn", why))
        return _finish(result, t0)

    # 3. le prompt
    task_text = task if task is not None else default_task_by_step(
        project or blueprint.get("project", ""), src_root_rel, profile="full").get(sp["etape"], "")
    parts = [payload.prompt, f"## TÂCHE CONCRÈTE ({run_id} / {sp['etape']})\n{task_text}"]
    if bp_section:
        parts.append(bp_section)
    prompt = "\n\n".join(parts)
    result["prompt_file"] = _persist_final_prompt(run_dir, sp["etape"], attempt, prompt)
```

- [ ] **Step 6: Run the tests**

Run: `.venv/Scripts/python.exe -m pytest forge/tests/test_transport_lot5.py forge/tests/test_capability_lot2.py forge/tests/test_context_manifest.py forge/tests/test_dispatch.py -q -p no:cacheprovider`
Expected: tous verts (les tests d'égalité `_UPSTREAM_BY_STEP` de `test_context_manifest.py` restent verts : la table n'est pas modifiée, seulement contournée quand `sources_override` est fourni).

---

### Task 4: Trois lignées de preuve — manifest d'exécution, spawn_link, RETURN_REASON (L7, L9, L10)

**Files:**
- Modify: `forge/capability.py` (imports ; avant l'exécuteur ; après `output` ; `_finish`)
- Test: `forge/tests/test_transport_lot5.py`

**Interfaces:**
- Produces: `context/<etape>.manifest.jsonl` gagne une ligne `kind=execution` ; `context/<etape>.return.manifest.jsonl` (kind `return`) ; `context/spawn_links.jsonl` (schéma `forge.spawn_link.v1`, mêmes clés que le driver) ; `result["return_reason"]` (dict), `result["lineage"] = {"execution_manifest": bool, "return_manifest": bool, "spawn_link": bool}`.

- [ ] **Step 1: Write the failing test**

```python
# --- Task 4 : trois lignées de preuve ------------------------------------------------------------


def test_une_convocation_ecrit_execution_manifest_spawn_link_et_return(blueprint, tmp_path):
    run_dir = tmp_path / "run"
    res = cap.invoke_capability("decompose", blueprint, run_dir, run_id="lot5-t4", attempt=1,
                                executor=_fake_executor(model_used=["claude-opus-4-8"]),
                                audit_path=tmp_path / "audit.jsonl")
    assert res["ok"]
    kinds = [r["kind"] for r in _manifest_lines(run_dir, "s3-decompo")]
    assert kinds == ["dispatch", "execution"]
    execution = _manifest_lines(run_dir, "s3-decompo")[1]
    prompt = Path(res["prompt_file"]).read_text(encoding="utf-8")
    assert execution["final_prompt_sha256"] == hashlib.sha256(prompt.encode("utf-8")).hexdigest()
    assert execution["tools_effective"] == ["Read"]
    ret = (run_dir / "context" / "s3-decompo.return.manifest.jsonl").read_text(encoding="utf-8")
    ret_rec = json.loads(ret.splitlines()[-1])
    assert ret_rec["kind"] == "return" and ret_rec["reason"]["status"] in ("DISCOVERED", "NOT_DISCOVERED", "NOT_TRANSMITTED")
    assert res["return_reason"] == ret_rec["reason"]
    links = [json.loads(l) for l in (run_dir / "context" / "spawn_links.jsonl").read_text(encoding="utf-8").splitlines() if l.strip()]
    assert len(links) == 1
    link = links[0]
    assert link["schema"] == "forge.spawn_link.v1" and link["status"] == "OK" and link["attestation"] == "self"
    assert link["model_declared"] == "claude-opus-4-8" and link["model_used"] == ["claude-opus-4-8"]
    assert link["prompt_sha256"] == execution["final_prompt_sha256"]
    assert link["artifact_sha256"] == res["artifact_sha256"] and link["tools_effective"] == ["Read"]
    assert res["lineage"] == {"execution_manifest": True, "return_manifest": True, "spawn_link": True}


def test_un_echec_d_executeur_laisse_un_spawn_link_halted(blueprint, tmp_path):
    run_dir = tmp_path / "run"
    res = cap.invoke_capability("decompose", blueprint, run_dir, run_id="lot5-t4b", attempt=1,
                                executor=_fake_executor(ok=False, reason="claude -p is_error: simulé"),
                                audit_path=tmp_path / "audit.jsonl")
    assert not res["ok"]
    links = [json.loads(l) for l in (run_dir / "context" / "spawn_links.jsonl").read_text(encoding="utf-8").splitlines() if l.strip()]
    assert links[-1]["status"] == "HALTED" and links[-1]["artifact_path"] is None
```

- [ ] **Step 2: Run test to verify it fails**

Run: `.venv/Scripts/python.exe -m pytest forge/tests/test_transport_lot5.py -q -p no:cacheprovider -k "lignee or spawn_link or execution_manifest"`
Expected: FAIL — `assert ['dispatch'] == ['dispatch', 'execution']`.

- [ ] **Step 3: Implement**

Imports en tête de `capability.py` (compléter le bloc `from forge.run_real import (...)`) :

```python
    _build_spawn_link_upstream,
    _derive_disallowed,
    _extract_return_reason,
```

et ajouter :

```python
from forge import context_manifest
```

Constante après `DEFAULT_TIMEOUT_POLICY` :

```python
SPAWN_LINK_ATTESTATION_NOTE = ("auto-attesté (chemin B headless) : cette ligne est écrite par forge.capability "
                               "qui exécute la convocation, aucun observateur tiers ne l'a constatée")
_SPAWN_LINK_UPSTREAM_KEYS = ("contract_path", "contract_sha256", "prompt_file", "prompt_sha256",
                             "tools_effective", "tools_disallowed_count",
                             "model_declared", "model_requested", "model_used")
```

Fonction utilitaire, avant `invoke_capability` :

```python
def _append_spawn_link(run_dir: Path, run_id: str, etape: str, attempt: int, status: str,
                       upstream: dict, artifact: Path | None) -> bool:
    """Le joint spawn_links.jsonl — MÊME schéma et MÊMES clés que ForgeDriver._append_spawn_link."""
    try:
        ligne = {
            "schema": SPAWN_LINK_SCHEMA, "run_id": run_id, "etape": etape, "attempt": attempt,
            "ts": time.time(), "status": status,
            "artifact_path": str(artifact) if artifact is not None else None,
            "artifact_sha256": bp.file_sha256(artifact) if artifact is not None else None,
            "verdict_ref": None,   # une convocation n'a pas de verdict : la QA du Director le rendra
            "attestation": "self", "attestation_note": SPAWN_LINK_ATTESTATION_NOTE,
            "claim_verdict": "NO_CLAIM_ALLOWED",
        }
        for cle in _SPAWN_LINK_UPSTREAM_KEYS:
            ligne[cle] = upstream.get(cle)
        path = Path(run_dir) / "context" / "spawn_links.jsonl"
        path.parent.mkdir(parents=True, exist_ok=True)
        with open(path, "a", encoding="utf-8") as fh:
            fh.write(json.dumps(ligne, ensure_ascii=False, sort_keys=True) + "\n")
        return True
    except Exception:  # noqa: BLE001 — capteur, jamais un blocage
        return False
```

Dans le dict `result` initial, ajouter :

```python
        "return_reason": None, "lineage": {"execution_manifest": False, "return_manifest": False, "spawn_link": False},
```

Après `result["prompt_file"] = _persist_final_prompt(...)` et avant l'exécuteur :

```python
    tools = tuple(sp["tools"])
    try:
        context_manifest.append_execution_manifest(
            run_id, sp["etape"], run_dir, prompt, model=payload.model, premortem_section=None,
            tools_effective=tools, tools_disallowed_count=len(_derive_disallowed(tools)))
        result["lineage"]["execution_manifest"] = True
    except Exception:  # noqa: BLE001 — advisory, jamais bloquant
        pass
```

Après le bloc `result["executor_diagnostic"] = ...` (Task 2) :

```python
    upstream = _build_spawn_link_upstream(run_dir, sp["etape"], prompt, result["prompt_file"],
                                          model_declared=result["model"], model_requested=payload.model, res=res)
    result["_spawn_link_upstream"] = upstream
```

Après `result["next_reason"] = ...` (Task 2) :

```python
    if res.get("ok"):
        reason = _extract_return_reason(output)
        result["return_reason"] = reason
        try:
            context_manifest.append_return_manifest(run_id, sp["etape"], run_dir, reason)
            result["lineage"]["return_manifest"] = True
        except Exception:  # noqa: BLE001
            pass
```

Remplacer `_finish` (l.~478-481) par :

```python
def _finish(result: dict, t0: float) -> dict:
    result["duration_s"] = round(time.monotonic() - t0, 3)
    upstream = result.pop("_spawn_link_upstream", None)
    if upstream is not None:   # un exécuteur a tourné : le joint est écrit, succès comme échec
        art = Path(result["artifact"]) if result.get("artifact") else None
        result["lineage"]["spawn_link"] = _append_spawn_link(
            Path(result["_run_dir"]), result["run_id"], result["etape"], result["attempt"],
            "OK" if result["ok"] else "HALTED", upstream, art)
    result.pop("_run_dir", None)
    return result
```

et, au début de `invoke_capability`, juste après `run_dir = Path(run_dir)`, mémoriser le run_dir dans le résultat : ajouter la clé `"_run_dir": str(run_dir),` dans le dict `result` initial (elle est retirée par `_finish`).

Note : `premortem_section=None` ici est remplacé en Task 5 par la vraie section.

- [ ] **Step 4: Run the tests**

Run: `.venv/Scripts/python.exe -m pytest forge/tests/test_transport_lot5.py forge/tests/test_capability_lot2.py forge/tests/test_director_lot3.py -q -p no:cacheprovider`
Expected: tous verts.

---

### Task 5: Pré-mortem, retour du matérialiseur, journal d'erreurs du run (L1, L3, L14)

**Files:**
- Modify: `forge/capability.py` (signature `invoke_capability`, assemblage du prompt, `_finish`)
- Modify: `forge/director.py:541-576` (`_step_convoke` : calcul et passage de `feedback`)
- Test: `forge/tests/test_transport_lot5.py`

**Interfaces:**
- Produces: `invoke_capability(..., premortem: list[str] | None = None, feedback: dict | None = None)` ; `capability.default_premortem(project: str, run_dir: Path, limit: int = 8) -> list[str]` ; `result["premortem_lines"]` (int), `result["feedback_applied"]` (bool) ; `<run_dir>/error_journal.jsonl` alimenté sur échec (producteur ≠ registre).

- [ ] **Step 1: Write the failing tests**

```python
# --- Task 5 : pré-mortem, retour du matérialiseur, journal du run ----------------------------------


def test_le_premortem_et_le_retour_du_materialiseur_atteignent_le_prompt(blueprint, tmp_path):
    run_dir = tmp_path / "run"
    calls: list = []
    res = cap.invoke_capability("decompose", blueprint, run_dir, run_id="lot5-t5", attempt=2,
                                executor=_fake_executor(calls=calls), audit_path=tmp_path / "audit.jsonl",
                                premortem=["[s3-decompo] tentative 1 : sortie sans bloc json"],
                                feedback={"attempt": 1, "reason": "s3-decompo: artefact featuremap.json non matérialisable — aucun bloc ```json```"})
    assert res["ok"]
    prompt = calls[0]["prompt"]
    assert "## PRÉ-MORTEM (erreurs des runs passés)" in prompt
    assert "- [s3-decompo] tentative 1 : sortie sans bloc json" in prompt
    assert "## RETOUR DU MATÉRIALISEUR — tentative 1 (ta sortie précédente a été REFUSÉE)" in prompt
    assert "non matérialisable" in prompt
    assert res["premortem_lines"] == 1 and res["feedback_applied"] is True
    execution = [r for r in _manifest_lines(run_dir, "s3-decompo") if r["kind"] == "execution"][0]
    assert execution["premortem_sha256"] is not None


def test_un_echec_est_journalise_dans_le_run_et_relu_par_la_convocation_suivante(blueprint, tmp_path):
    run_dir = tmp_path / "run"
    audit = tmp_path / "audit.jsonl"
    res1 = cap.invoke_capability("decompose", blueprint, run_dir, run_id="lot5-t5b", attempt=1,
                                 executor=_fake_executor(output="Rien de matérialisable ici."), audit_path=audit)
    assert not res1["ok"] and res1["problems"][0]["code"] == cap.ARTIFACT_NOT_MATERIALIZABLE
    journal = run_dir / "error_journal.jsonl"
    lines = [json.loads(l) for l in journal.read_text(encoding="utf-8").splitlines() if l.strip()]
    assert len(lines) == 1 and lines[0]["etape"] == "s3-decompo" and lines[0]["project"] == "runm_breakout"
    assert cap.ARTIFACT_NOT_MATERIALIZABLE in lines[0]["error"]
    calls: list = []
    res2 = cap.invoke_capability("decompose", blueprint, run_dir, run_id="lot5-t5b", attempt=2,
                                 executor=_fake_executor(calls=calls), audit_path=audit)
    assert res2["ok"] and res2["premortem_lines"] >= 1
    assert cap.ARTIFACT_NOT_MATERIALIZABLE in calls[0]["prompt"]


def test_le_director_transmet_le_retour_du_materialiseur_a_la_reconvocation(blueprint, tmp_path):
    partial = json.loads(json.dumps(blueprint))
    for s in ("feature_map", "architecture_contract", "wiremap"):
        partial["sections"][s] = bp.empty_section(s)
    outputs = ["Rien de matérialisable ici.", _S3_OUTPUT.read_text(encoding="utf-8")]
    calls: list = []

    def executor(prompt, sp, payload):
        calls.append({"capability": sp["name"], "prompt": prompt})
        return {"ok": True, "output": outputs[min(len(calls) - 1, 1)], "tokens": 0, "duration_s": 0.0, "cost_usd": 0.0}

    d = dr.Director(partial, tmp_path / "run", run_id="lot5-t5c", executor=executor,
                    audit_path=tmp_path / "audit.jsonl", journal_dir=tmp_path / "amendments")
    d.step()
    d.step()
    assert [c["capability"] for c in calls] == ["decompose", "decompose"]
    assert "RETOUR DU MATÉRIALISEUR" not in calls[0]["prompt"]
    assert "## RETOUR DU MATÉRIALISEUR — tentative 1" in calls[1]["prompt"]
    assert partial["sections"]["feature_map"]["version"] == 1 and partial["sections"]["feature_map"]["writer"] == "decompose"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `.venv/Scripts/python.exe -m pytest forge/tests/test_transport_lot5.py -q -p no:cacheprovider -k "premortem or journalise or materialiseur"`
Expected: FAIL — `TypeError: invoke_capability() got an unexpected keyword argument 'premortem'`.

- [ ] **Step 3: Implement in `capability.py`**

Import : `from forge import studio_link`.

Fonction avant `invoke_capability` :

```python
def default_premortem(project: str, run_dir: Path, limit: int = 8) -> list[str]:
    """Le pré-mortem d'une convocation : journal studio du projet (+ leçons globales) puis journal
    LOCAL du run (les échecs des convocations précédentes de CE run). Best-effort, jamais bloquant."""
    lines: list[str] = []
    try:
        lines += studio_link.premortem(project, domain="html")
    except Exception:  # noqa: BLE001
        pass
    local = Path(run_dir) / "error_journal.jsonl"
    if local.exists():
        try:
            lines += studio_link.premortem(project, journal_path=local)
        except Exception:  # noqa: BLE001
            pass
    return list(dict.fromkeys(lines))[-limit:]
```

Signature de `invoke_capability` : ajouter `premortem: list[str] | None = None, feedback: dict | None = None,` après `model_override`. Dans le dict `result` initial : `"premortem_lines": 0, "feedback_applied": False,`.

Dans l'assemblage du prompt (Task 3, bloc « 3. le prompt »), après `if bp_section: parts.append(bp_section)` :

```python
    pm = premortem if premortem is not None else default_premortem(project or blueprint.get("project", ""), run_dir)
    premortem_section = None
    if pm:
        premortem_section = "## PRÉ-MORTEM (erreurs des runs passés)\n" + "\n".join(f"- {p}" for p in pm)
        parts.append(premortem_section)
    result["premortem_lines"] = len(pm)
    if feedback:
        parts.append(f"## RETOUR DU MATÉRIALISEUR — tentative {feedback.get('attempt')} "
                     "(ta sortie précédente a été REFUSÉE)\n"
                     f"{feedback.get('reason')}\n"
                     "Corrige la FORME demandée ; le fond de ta sortie précédente reste valable.")
        result["feedback_applied"] = True
```

Dans l'appel `append_execution_manifest` (Task 4) : remplacer `premortem_section=None` par `premortem_section=premortem_section`.

Dans `_finish`, avant `result.pop("_run_dir", None)` :

```python
    if not result["ok"] and result.get("_run_dir"):
        first = next((p for p in result["problems"] if p.get("producer") != "capability_registry"), None)
        if first is not None:
            try:
                studio_link.record_error(result["run_id"], result["etape"] or "?",
                                         f"{first['code']}: {first['message']}", result.get("_project") or "",
                                         journal_path=Path(result["_run_dir"]) / "error_journal.jsonl")
            except Exception:  # noqa: BLE001
                pass
    result.pop("_project", None)
```

et dans le dict `result` initial : `"_project": project or blueprint.get("project", ""),`.

- [ ] **Step 4: Implement in `director.py` (`_step_convoke`)**

Après `attempt = self.state["convocations"][etape]` (l.552), ajouter :

```python
        feedback = None
        for p in self.state.get("last_problems") or []:
            if p.get("code") in (cap.ARTIFACT_NOT_MATERIALIZABLE, cap.ARTIFACT_INVALID) \
                    and p.get("path") == action["path"] and attempt > 1:
                feedback = {"attempt": attempt - 1, "reason": p.get("message")}
```

et dans l'appel `cap.invoke_capability(...)` (l.574-577) ajouter `feedback=feedback,`.

- [ ] **Step 5: Run the tests**

Run: `.venv/Scripts/python.exe -m pytest forge/tests/test_transport_lot5.py forge/tests/test_capability_lot2.py forge/tests/test_director_lot3.py forge/tests/test_slice_lot4.py -q -p no:cacheprovider`
Expected: tous verts.

---

### Task 6: `timeout_policy` consommée ; `prepare_build` ne touche jamais `forge/oracles.json` (réserves 2 et 1)

**Files:**
- Modify: `forge/capability.py` (signature `timeout_s`, résultat)
- Test: `forge/tests/test_transport_lot5.py`

**Interfaces:**
- Produces: `invoke_capability(..., timeout_s: float | None = None)` — `None` ⇒ `spec["timeout_policy"]["timeout_s"]` ; `result["timeout_s"]` (float).

- [ ] **Step 1: Write the failing tests**

```python
# --- Task 6 : réserves 1 et 2 -----------------------------------------------------------------------


def test_le_timeout_vient_du_registre_sauf_intention_explicite(blueprint, tmp_path):
    res = cap.invoke_capability("decompose", blueprint, tmp_path / "run", run_id="lot5-t6", attempt=1,
                                executor=_fake_executor(), audit_path=tmp_path / "audit.jsonl")
    assert res["timeout_s"] == 1800.0
    res2 = cap.invoke_capability("decompose", blueprint, tmp_path / "run2", run_id="lot5-t6b", attempt=1,
                                 executor=_fake_executor(), audit_path=tmp_path / "audit2.jsonl", timeout_s=42)
    assert res2["timeout_s"] == 42.0


def test_prepare_build_n_ecrit_que_l_oracles_json_du_run(blueprint, tmp_path):
    global_cfg = _REPO_ROOT / "forge" / "oracles.json"
    before = hashlib.sha256(global_cfg.read_bytes()).hexdigest()
    project = "_pytest_lot5_oracles"
    game_dir = _REPO_ROOT / "GAMES" / project
    try:
        prep = bo.prepare_build(blueprint, tmp_path / "run", project)
        local = json.loads((tmp_path / "run" / "oracles.json").read_text(encoding="utf-8"))
        assert local == {project: {"cwd": f"GAMES/{project}", "command": ["node", "run-oracle.mjs"]}}
        assert prep["oracle_config"] == str(tmp_path / "run" / "oracles.json")
        assert hashlib.sha256(global_cfg.read_bytes()).hexdigest() == before
        assert project not in json.loads(global_cfg.read_text(encoding="utf-8"))
    finally:
        shutil.rmtree(game_dir, ignore_errors=True)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `.venv/Scripts/python.exe -m pytest forge/tests/test_transport_lot5.py -q -p no:cacheprovider -k "timeout_vient or prepare_build"`
Expected: `test_le_timeout_vient...` FAIL — `KeyError: 'timeout_s'` ; `test_prepare_build...` PASS (garde R3 déjà vraie, désormais testée).

- [ ] **Step 3: Implement**

Signature : `timeout_s: float = DEFAULT_STEP_TIMEOUT_S` devient `timeout_s: float | None = None`. Juste après `sp = spec(name, registry)` :

```python
    effective_timeout = float(timeout_s if timeout_s is not None else sp["timeout_policy"]["timeout_s"])
    result["timeout_s"] = effective_timeout
```

et remplacer `timeout_s=timeout_s` dans la lambda de `_default_executor` par `timeout_s=effective_timeout`. Ajouter `"timeout_s": None,` au dict `result` initial.

- [ ] **Step 4: Run the tests**

Run: `.venv/Scripts/python.exe -m pytest forge/tests/test_transport_lot5.py -q -p no:cacheprovider`
Expected: tous verts.

---

### Task 7: Objections avec `run_id` ; dossier HumanGate filtré (réserve 3)

**Files:**
- Modify: `forge/director.py:353-388` (`_objection`, `_objection_oracles`)
- Modify: `forge/build_orchestrator.py:203-262` (`humangate_dossier`)
- Test: `forge/tests/test_transport_lot5.py`

**Interfaces:**
- Produces: messages d'objection avec `"run_id": <run_id>` ; `humangate_dossier` rend `objections_conservees` (du run seul) et `objections_autres_runs` (int) ; ligne Markdown correspondante.

- [ ] **Step 1: Write the failing tests**

```python
# --- Task 7 : réserve 3 -------------------------------------------------------------------------------


def test_une_objection_porte_son_run_id():
    state = dr.new_state("lot5-t7", "runm_breakout")
    view = {"regime": "VOID", "capacites": 10, "capacites_couvertes": 0, "lignes_sans_couvre": 0, "couverture_fantome": 9}
    m = dr._objection(state, "wiremap", dr.JOIN_GHOST_COVERAGE, view, {"last_effect": "CHANGED"})
    assert m["run_id"] == "lot5-t7"
    m2 = dr._objection_oracles(dict(state, last_problems=[{"producer": "s10a", "code": "X", "message": "m"}]), {})
    assert m2["run_id"] == "lot5-t7"


def test_le_dossier_ne_liste_que_les_objections_du_run(blueprint, tmp_path):
    journal_dir = tmp_path / "amendments"
    mine = {"id": "AMD-1-mine", "type": "objection", "from": "director", "to": ["wiremap"], "subject": "s1",
            "reason": "r", "issued_at": "2026-09-04T00:00:00Z", "run_id": "lot5-t7b"}
    other = {"id": "AMD-2-other", "type": "objection", "from": "director", "to": ["builder"], "subject": "s2",
             "reason": "r", "issued_at": "2026-09-04T00:00:01Z", "run_id": "autre_run"}
    legacy = {"id": "AMD-3-legacy", "type": "objection", "from": "director", "to": ["builder"], "subject": "s3",
              "reason": "r", "issued_at": "2026-09-04T00:00:02Z"}
    for m in (mine, other, legacy):
        append_message(m, journal_dir=journal_dir)
    state = dr.new_state("lot5-t7b", "runm_breakout")
    coverage = {"design": {"regime": "JOINED"}, "built": {"regime": "JOINED"}}
    dossier = bo.humangate_dossier(blueprint, tmp_path / "run", state, None, coverage, read_messages(journal_dir))
    assert [m["id"] for m in dossier["objections_conservees"]] == ["AMD-1-mine"]
    assert dossier["objections_autres_runs"] == 2
    md = (tmp_path / "run" / "HUMANGATE_DOSSIER.md").read_text(encoding="utf-8")
    assert "AMD-1-mine" in md and "AMD-2-other" not in md
    assert "2 objection(s) d'autres runs ou sans run_id, non listées" in md
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `.venv/Scripts/python.exe -m pytest forge/tests/test_transport_lot5.py -q -p no:cacheprovider -k "run_id or objections_du_run"`
Expected: FAIL — `KeyError: 'run_id'`.

- [ ] **Step 3: Implement in `director.py`**

Dans `_objection` (l.353-368), après `"id": new_message_id(...), "type": "objection",` ajouter `"run_id": state["run_id"],`. Idem dans `_objection_oracles` (l.370-388).

- [ ] **Step 4: Implement in `build_orchestrator.py`**

Dans `humangate_dossier`, avant `dossier = {`, ajouter :

```python
    run_id = director_state.get("run_id")
    mine = [m for m in journal_messages if m.get("run_id") == run_id]
    autres = len(journal_messages) - len(mine)
```

Remplacer la ligne `"objections_conservees": [...]` par :

```python
        "objections_conservees": [{k: m.get(k) for k in ("id", "type", "from", "to", "subject", "run_id")} for m in mine],
        "objections_autres_runs": autres,
```

Remplacer la ligne `"## Objections conservées", *objections_md, "",` par :

```python
          "## Objections conservées (run seul)", *objections_md,
          f"- {autres} objection(s) d'autres runs ou sans run_id, non listées", "",
```

- [ ] **Step 5: Run the tests**

Run: `.venv/Scripts/python.exe -m pytest forge/tests/test_transport_lot5.py forge/tests/test_director_lot3.py forge/tests/test_slice_lot4.py -q -p no:cacheprovider`
Expected: tous verts.

---

### Task 8: Rapport d'audit dans `docs/`, suite complète, re-convocation réelle, handoff, fiche de commit

**Files:**
- Create: `docs/forge/AUDIT_V2_CAPABILITIES_SKILLS_MODELS_20260903.md` (copie du rapport, en-tête de provenance)
- Modify: `00_CURRENT_CONTEXT.md` (bloc Lot 5)
- Create (par la sonde) : `EVIDENCE/runs/lot5_transport_probe/`, `EVIDENCE/reports/lot5_transport/`

- [ ] **Step 1: Copy the audit report with a provenance header**

```bash
python - <<'EOF'
from pathlib import Path
src = Path(r"C:\Users\STUDIO~2\AppData\Local\Temp\claude\C--TACTICAL-CHESS-STUDIO\99b05a34-eb66-4201-8fcc-bfdc67fc331c\scratchpad\FINAL_AUDIT_V2_CAPABILITIES_20260903.md")
dst = Path("docs/forge/AUDIT_V2_CAPABILITIES_SKILLS_MODELS_20260903.md")
head = ("<!-- Source : audit parallèle lecture seule du 2026-09-03, session Fable, HEAD V2 7e494fd → 3481089 ;"
        " déposé dans docs/ le 2026-09-04 sur décision Pierre (GO Lot 5). Aucune ligne modifiée depuis. -->\n\n")
dst.write_text(head + src.read_text(encoding="utf-8"), encoding="utf-8", newline="\n")
print(dst, dst.stat().st_size)
EOF
```

- [ ] **Step 2: Run the full lot suite**

Run: `.venv/Scripts/python.exe -m pytest forge/tests/test_transport_lot5.py forge/tests/test_capability_lot2.py forge/tests/test_director_lot3.py forge/tests/test_slice_lot4.py forge/tests/test_context_manifest.py forge/tests/test_dispatch.py forge/tests/test_amendment_log.py -q -p no:cacheprovider -m "not gpu_window"`
Expected: tous verts. Noter le compte exact.

- [ ] **Step 3: One real re-convocation (proof b)**

Run (détaché, ~5 min, ~1,4 $) :

```bash
.venv/Scripts/python.exe -m forge.capability invoke decompose --blueprint EVIDENCE/reports/lot2_capability/GAME_BLUEPRINT.lot2_probe.json --run-id lot5_transport_probe --out EVIDENCE/reports/lot5_transport/GAME_BLUEPRINT.lot5_probe.json > EVIDENCE/reports/lot5_transport/invoke_decompose_probe.stdout.txt 2>&1
```

Puis vérifier mécaniquement :

```bash
python - <<'EOF'
import json
from pathlib import Path
rd = Path("EVIDENCE/runs/lot5_transport_probe")
kinds = [json.loads(l)["kind"] for l in (rd/"context/s3-decompo.manifest.jsonl").read_text(encoding="utf-8").splitlines() if l.strip()]
disp = [json.loads(l) for l in (rd/"context/s3-decompo.manifest.jsonl").read_text(encoding="utf-8").splitlines() if l.strip()][0]
links = [json.loads(l) for l in (rd/"context/spawn_links.jsonl").read_text(encoding="utf-8").splitlines() if l.strip()]
ret = json.loads((rd/"context/s3-decompo.return.manifest.jsonl").read_text(encoding="utf-8").splitlines()[-1])
print("kinds", kinds)
print("sources roles", sorted({s["role"] for s in disp["sources"]}))
print("spawn_link model_used", links[-1]["model_used"], "status", links[-1]["status"])
print("return", ret["reason"])
res = json.loads((rd/"capability_result_decompose_a1.json").read_text(encoding="utf-8")) if (rd/"capability_result_decompose_a1.json").exists() else None
print("model_used", res and res.get("model_used"), "premortem_lines", res and res.get("premortem_lines"), "cost", res and res.get("cost"))
EOF
```

Attendu : `kinds ['dispatch', 'execution']` ; rôles sans `upstream`, avec `blueprint_section` ; `model_used ['claude-opus-4-8']` ; `return` ∈ {DISCOVERED, NOT_DISCOVERED, NOT_TRANSMITTED}.

- [ ] **Step 4: Update the handoff** (`00_CURRENT_CONTEXT.md`, bloc « Session 2026-09-03 → 04 ») : ajouter 4 lignes : Lot 5 fait (transport au registre : N carried / N director / N deferred / N dropped ; L8 et L11 corrigés ; lignées écrites ; pré-mortem et feedback ; timeout_policy ; dossier filtré), sonde réelle (coût, modèle mesuré), tests (compte), réserves 1 et 3 fermées, réserve 2 fermée par le registre.

- [ ] **Step 5: Fiche de commit pour Pierre (pas de commit sans GO)**

Lister : fichiers modifiés/ajoutés, résultat des tests, résultat de la sonde, message de commit proposé :

```
feat(v2): Lot 5 — transport et propriétaires : 28 mécanismes au registre, manifest sur les sections du Blueprint, lignées execution/return/spawn_link, pré-mortem et retour du matérialiseur, timeout_policy, dossier filtré par run_id ; audit 2026-09-03 déposé dans docs/forge
```

---

## Self-review

- Spec coverage : registre + propriétaires (T1) · L8 (T3) · L11, L13, L17, L22 (T2) · L7, L9, L10 (T4) · L1, L3, L14 (T5) · réserve 2 et réserve 1 (T6, T1 `dropped/pierre`) · réserve 3 (T7) · rapport dans docs/, sonde réelle, handoff (T8). L5, L12, L16, L19, L2 : déclarés `deferred` avec raison (T1), pas implémentés — voulu.
- Placeholders : aucun ; chaque étape porte son code et sa commande.
- Cohérence des noms : `load_transport`, `TRANSPORT_OWNERS`, `TRANSPORT_STATUSES`, `DEFAULT_TIMEOUT_POLICY`, `default_premortem`, `_append_spawn_link`, `sources_override`, clés de résultat `model_used / model_measured / executor_diagnostic / next_reason / return_reason / lineage / premortem_lines / feedback_applied / timeout_s / blueprint_inputs[].entry_sha256` — identiques entre tâches et tests.

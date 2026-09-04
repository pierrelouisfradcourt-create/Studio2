"""Lot 2 (plan V2 2026-09-03, GO Pierre) — CAPABILITY_REGISTRY (K2) + invoke_capability (K3, K7).

Forme de production réelle : le Blueprint importé depuis la baseline M ter (Lot 1), l'exécuteur
factice rend la SORTIE RÉELLE de l'agent s3 de cette baseline (`artifacts/s3-decompo.txt`), la
matérialisation et le validateur sont ceux de `run_real`, l'oracle est `check_decompo.mjs`.

Ce que ces tests prouvent :
  - le registre est une CONSOLIDATION fidèle : artifact == _ARTIFACT_BY_STEP, tools ==
    _effective_step_tools, modèle == roles.yaml, chaque étape LLM de ORDER a une entrée ;
  - une convocation `decompose` sur le Blueprint : porte (dispatch signé, check_spawn count==1),
    prompt assemblé DEPUIS les sections (version + sha), feature_map écrite en v2 par `decompose`,
    reçus spawn_prepared/authorized/executed, aucune autre section modifiée ;
  - la re-convocation (attempt 2) n'est pas un rejeu refusé ;
  - un échec d'exécuteur, une sortie non matérialisable, une capacité verrouillée (Q2), une
    section requise absente : refus nommé, producteur nommé, Blueprint intact ;
  - Q7 (FORGE_TARGET_MODEL §12) : un contrat COMPOSÉ hors forge/contracts passe la porte, et le
    hook l'autorise avec count == 1 — EXÉCUTÉ, plus seulement lu.

Aucun appel LLM réel ici (cf. preuve (b) du lot, hors pytest). NO_CLAIM_ALLOWED.
"""
from __future__ import annotations

import json
import shutil
from pathlib import Path

import pytest

from forge import blueprint as bp
from forge import capability as cap
from forge.blueprint_import import import_run_dir
from forge.contract import load_contract, resolve_runtime
from forge.dispatch import DETERMINISTIC, ORDER, prepare_dispatch
from forge.hook_guard import check_spawn
from forge.run_real import _ARTIFACT_BY_STEP, _effective_step_tools

_REPO_ROOT = Path(__file__).resolve().parents[2]
_RUN_DIR = _REPO_ROOT / "EVIDENCE" / "runs" / "runm_breakout"
_BRIEF = _REPO_ROOT / "EVIDENCE" / "briefs" / "runm_breakout" / "project_brief.yaml"
_S3_OUTPUT = _RUN_DIR / "artifacts" / "s3-decompo.txt"

pytestmark = pytest.mark.skipif(
    not (_RUN_DIR / "state.json").exists() or not _S3_OUTPUT.exists(),
    reason="baseline M ter absente — ce lot se prouve sur la forme de production réelle",
)


@pytest.fixture
def blueprint():
    return import_run_dir(_RUN_DIR, brief_path=_BRIEF, project="runm_breakout")


def _fake_executor_from_baseline(calls: list | None = None):
    output = _S3_OUTPUT.read_text(encoding="utf-8")

    def executor(prompt, sp, payload):
        if calls is not None:
            calls.append({"prompt": prompt, "model": payload.model, "etape": sp["etape"]})
        return {"ok": True, "output": output, "tokens": 0, "duration_s": 0.0, "cost_usd": 0.0}
    return executor


def _snapshot(blueprint: dict) -> dict:
    return {s: (m["version"], m["content_sha256"]) for s, m in blueprint["sections"].items()}


# --- registre --------------------------------------------------------------------------------


def test_le_registre_consolide_les_tables_de_run_real_sans_les_contredire():
    reg = cap.load_registry()
    for name in reg:
        sp = cap.spec(name, reg)
        etape = sp["etape"]
        assert sp["artifact"] == _ARTIFACT_BY_STEP.get(etape), name
        assert sp["tools"] == list(_effective_step_tools(etape)), name
        assert sp["model_policy"]["model"] == resolve_runtime(load_contract(etape)), name
        assert sp["mission"], f"{name}: mission (objectif du contrat) vide"
        assert sp["escalation"] in ("aucun", "builder_ladder"), name
        if sp["kind"] != "oracle":
            assert sp["writes"], f"{name}: une capacité LLM possède une section"


def test_chaque_etape_llm_de_order_a_une_capacite():
    couvertes = {cap.spec(n)["etape"] for n in cap.load_registry()}
    for etape in ORDER:
        if etape in DETERMINISTIC:
            continue
        assert etape in couvertes, f"étape {etape} sans capacité au registre"


def test_seul_le_builder_s_escalade():
    reg = cap.load_registry()
    ladders = {n for n in reg if cap.spec(n, reg)["escalation"] == "builder_ladder"}
    assert ladders == {"builder"}
    assert cap.spec("redteam_code", reg)["escalation"] == "aucun"   # ESC-1


# --- convocation hors LLM, forme réelle ------------------------------------------------------


def test_decompose_travaille_sur_le_blueprint_et_n_ecrit_que_sa_section(blueprint, tmp_path):
    before = _snapshot(blueprint)
    audit = tmp_path / "audit.jsonl"
    calls: list = []
    res = cap.invoke_capability("decompose", blueprint, tmp_path / "run", run_id="lot2-t",
                                attempt=1, executor=_fake_executor_from_baseline(calls), audit_path=audit)
    assert res["ok"], res["problems"]
    assert res["section_written"] == "feature_map" and res["section_version"] == 2
    fm = blueprint["sections"]["feature_map"]
    assert fm["writer"] == "decompose" and fm["version"] == 2
    assert fm["source"]["sha256"] == bp.file_sha256(tmp_path / "run" / "featuremap.json")
    # aucune autre section touchée
    after = _snapshot(blueprint)
    assert {s for s in after if after[s] != before[s]} == {"feature_map"}
    # le prompt vient du Blueprint : en-tête, sections lues avec leur sha, tâche par défaut
    prompt = calls[0]["prompt"]
    assert "## GAME_BLUEPRINT — sections lues" in prompt
    for inp in res["blueprint_inputs"]:
        assert inp["content_sha256"] in prompt
    assert {i["section"] for i in res["blueprint_inputs"]} >= {"gameplay", "understanding.prisme"}
    assert "FORGE_DISPATCH:s3-decompo:lot2-t" in prompt
    assert calls[0]["model"] == cap.spec("decompose")["model_policy"]["model"]
    # projections pour les oracles legacy
    assert (tmp_path / "run" / "prisme.json").exists() and (tmp_path / "run" / "charter.yaml").exists()
    # l'oracle déclaré a tourné et parle en codes K7 avec producteur mécanique
    assert res["validator_receipt"]["name"] == "check_decompo.mjs"
    for pb in res["problems"]:
        assert pb["producer"] == "check_decompo.mjs" and pb["code"].startswith("DECOMPO_")
    # MESURÉ sur la sortie réelle de l'agent s3 (2026-09-03) : l'oracle rend ok=False, 9/10
    # exigences couvertes, et 2 feuilles d'action joueur sans preuve bot_action — le signal que le
    # Director du Lot 3 consommera existe, avec un producteur mécanique.
    assert res["validator_receipt"]["ok"] is False
    assert res["validator_receipt"]["stats"]["exigences_couvertes"] == 9
    assert [pb["code"] for pb in res["problems"]] == ["DECOMPO_LOOP_NO_ENTRY", "DECOMPO_LOOP_NO_ENTRY"]


def test_la_porte_est_traversee_et_prouvee(blueprint, tmp_path):
    audit = tmp_path / "audit.jsonl"
    res = cap.invoke_capability("decompose", blueprint, tmp_path / "run", run_id="lot2-porte",
                                attempt=1, executor=_fake_executor_from_baseline(), audit_path=audit)
    assert res["audit"] == {"prepared": True, "spawn_allowed": True, "authorized": True, "executed": True}
    events = [json.loads(l)["event"] for l in audit.read_text(encoding="utf-8").splitlines() if l.strip()]
    assert events == ["spawn_prepared", "spawn_authorized", "spawn_executed"]
    # le même marqueur, revérifié par la fonction du hook : exactement UN dispatch
    prompt = Path(res["prompt_file"]).read_text(encoding="utf-8")
    assert check_spawn(prompt, audit_path=audit) == (True, "dispatch validé s3-decompo/lot2-porte#1")


def test_la_reconvocation_est_une_tentative_distincte_jamais_un_rejeu(blueprint, tmp_path):
    audit = tmp_path / "audit.jsonl"
    ex = _fake_executor_from_baseline()
    r1 = cap.invoke_capability("decompose", blueprint, tmp_path / "run", run_id="lot2-re",
                               attempt=1, executor=ex, audit_path=audit)
    r2 = cap.invoke_capability("decompose", blueprint, tmp_path / "run", run_id="lot2-re",
                               attempt=2, executor=ex, audit_path=audit)
    assert r1["ok"] and r2["ok"]
    assert (r1["section_version"], r2["section_version"]) == (2, 3)
    assert r2["audit"]["spawn_allowed"] is True


def test_un_echec_d_executeur_laisse_le_blueprint_intact(blueprint, tmp_path):
    before = _snapshot(blueprint)
    res = cap.invoke_capability(
        "decompose", blueprint, tmp_path / "run", run_id="lot2-ko", attempt=1,
        executor=lambda p, s, pl: {"ok": False, "reason": "claude -p is_error: simulé"},
        audit_path=tmp_path / "audit.jsonl")
    assert not res["ok"]
    assert [pb["code"] for pb in res["problems"]] == [cap.EXECUTOR_FAILED]
    assert res["problems"][0]["producer"] == "executor"
    assert _snapshot(blueprint) == before


def test_une_sortie_non_materialisable_est_refusee_par_le_validateur_de_production(blueprint, tmp_path):
    before = _snapshot(blueprint)
    res = cap.invoke_capability(
        "decompose", blueprint, tmp_path / "run", run_id="lot2-bad", attempt=1,
        executor=lambda p, s, pl: {"ok": True, "output": "Voici ma décomposition en prose, sans bloc."},
        audit_path=tmp_path / "audit.jsonl")
    assert not res["ok"]
    assert res["problems"][0]["code"] == cap.ARTIFACT_NOT_MATERIALIZABLE
    assert res["problems"][0]["producer"] == "run_real._validate_featuremap"
    assert _snapshot(blueprint) == before


def test_une_capacite_verrouillee_ne_depense_rien(blueprint, tmp_path):
    calls: list = []
    res = cap.invoke_capability("worldscan", blueprint, tmp_path / "run", run_id="lot2-q2",
                                executor=_fake_executor_from_baseline(calls), audit_path=tmp_path / "a.jsonl")
    assert not res["ok"] and calls == []
    assert res["problems"][0]["code"] == cap.CAPABILITY_LOCKED
    assert "Q2" in res["problems"][0]["message"]
    assert res["audit"]["prepared"] is False


def test_une_section_requise_absente_refuse_avant_toute_depense(blueprint, tmp_path):
    calls: list = []
    vierge = bp.new_blueprint("vide")
    res = cap.invoke_capability("decompose", vierge, tmp_path / "run", run_id="lot2-vide",
                                executor=_fake_executor_from_baseline(calls), audit_path=tmp_path / "a.jsonl")
    assert not res["ok"] and calls == []
    codes = {pb["code"] for pb in res["problems"]}
    assert codes == {cap.BLUEPRINT_SECTION_ABSENT}
    assert {pb["path"] for pb in res["problems"]} == {"gameplay", "understanding.prisme"}


# --- Q7 : contrat composé hors forge/contracts, même porte ------------------------------------


def test_q7_un_contrat_compose_passe_la_porte_et_le_hook_compte_un_dispatch(tmp_path):
    src = _REPO_ROOT / "forge" / "contracts"
    composed = tmp_path / "contracts"
    composed.mkdir()
    shutil.copy(src / "roles.yaml", composed / "roles.yaml")
    texte = (src / "s3-decompo.yaml").read_text(encoding="utf-8")
    texte = texte.replace("Décomposition Fonctionnelle (étape 3).", "Design Breakdown (capacité composée, test Q7).")
    (composed / "cx-breakdown.yaml").write_text(texte, encoding="utf-8")
    audit = tmp_path / "audit.jsonl"
    payload = prepare_dispatch("cx-breakdown", "lot2-q7", audit_path=audit, run_dir=tmp_path / "run",
                               profile=None, attempt=1, contracts_dir=composed)
    assert "Design Breakdown (capacité composée, test Q7)." in payload.prompt
    assert check_spawn(payload.prompt, audit_path=audit) == (True, "dispatch validé cx-breakdown/lot2-q7#1")
    # deux préparations du même triplet => ambiguïté, refus : l'invariant tient aussi ici
    prepare_dispatch("cx-breakdown", "lot2-q7", audit_path=audit, run_dir=tmp_path / "run",
                     profile=None, attempt=1, contracts_dir=composed)
    allowed, why = check_spawn(payload.prompt, audit_path=audit)
    assert allowed is False and "2 dispatches" in why

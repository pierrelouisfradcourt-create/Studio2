"""Lot 3 (plan V2 2026-09-03, GO Pierre) — Director v0 : politique déterministe, mesure d'effet,
réaction à une régression, journal de décisions, émetteur branché, reprise sur réponse humaine.

Forme de production réelle : Blueprint importé de la baseline M ter ; exécuteurs factices qui
rendent des SORTIES RÉELLES de la baseline (artefact agent s5, wiremap.json final) ou une variante
mesurable (une wiremap dont les `couvre` citent des identifiants inexistants => fantômes).

Ce que ces tests prouvent :
  - la politique est une table état -> action, sans LLM, et ne rend jamais une suite pré-écrite :
    deux Blueprints différents => deux suites de convocations différentes, aucune égale à un profil ;
  - l'effet d'une convocation est CALCULÉ par le Director (sha avant/après, couverture avant/après) :
    CHANGED · NO_EFFECT · REGRESSED ;
  - réaction à une régression : objection émise (journal append-only + trace du run), acquittement
    mesuré sur l'artefact désigné par le registre, re-convocation UNE fois avec le message dans la
    tâche, puis HALT question à Pierre (options accept / revert) ;
  - deux NO_EFFECT consécutifs => HALT (critère d'arrêt) ;
  - K8 : la réponse `revert` de Pierre restaure la version antérieure ; `accept` ouvre la porte ;
  - JOINED => gate_open ; les décisions sont journalisées (decisions.jsonl + section decisions) ;
  - le Director n'écrit jamais vision / constraints / identity ; une demande d'escalade de l'agent
    est consignée, jamais exécutée.
NO_CLAIM_ALLOWED.
"""
from __future__ import annotations

import json
import shutil
from pathlib import Path

import pytest

from forge import blueprint as bp
from forge import director as dr
from forge.amendment_log import read_messages
from forge.blueprint_import import import_run_dir
from forge.dispatch import PROFILES

_REPO_ROOT = Path(__file__).resolve().parents[2]
_RUN_DIR = _REPO_ROOT / "EVIDENCE" / "runs" / "runm_breakout"
_BRIEF = _REPO_ROOT / "EVIDENCE" / "briefs" / "runm_breakout" / "project_brief.yaml"

pytestmark = [
    pytest.mark.skipif(not (_RUN_DIR / "state.json").exists(), reason="baseline M ter absente"),
    pytest.mark.skipif(shutil.which("node") is None, reason="node absent : couverture NOT_MEASURED"),
]


@pytest.fixture
def full():
    return import_run_dir(_RUN_DIR, brief_path=_BRIEF, project="runm_breakout")


@pytest.fixture
def partial(full):
    """Blueprint sans feature_map, architecture ni wiremap : la conception reste à faire."""
    b = json.loads(json.dumps(full))
    for s in ("feature_map", "architecture_contract", "wiremap"):
        b["sections"][s] = bp.empty_section(s)
    return b


def _fenced(obj) -> str:
    return "Rapport.\n\n```json\n" + json.dumps(obj, ensure_ascii=False) + "\n```\n"


def _wiremap_agent_s5() -> str:          # sortie RÉELLE de l'agent s5 : lignes sans couvre (EMPTY_FORM)
    return (_RUN_DIR / "artifacts" / "s5-wiremap.txt").read_text(encoding="utf-8")


def _wiremap_joined() -> str:             # wiremap.json final RÉEL : couvre complets (JOINED)
    return _fenced(json.loads((_RUN_DIR / "wiremap.json").read_text(encoding="utf-8")))


def _wiremap_ghost() -> str:              # même wiremap, couvre réécrits vers des ids inexistants
    wm = json.loads((_RUN_DIR / "wiremap.json").read_text(encoding="utf-8"))
    for f in wm["features"]:
        f["couvre"] = [f"GHOST_{i}" for i, _ in enumerate(f.get("couvre") or ["x"])]
    return _fenced(wm)


def _executor(script: dict, calls: list | None = None):
    """script : capacité -> liste de sorties (consommées dans l'ordre) ; dernière répétée."""
    counters: dict[str, int] = {}

    def ex(prompt, sp, payload):
        outs = script[sp["name"]]
        i = min(counters.get(sp["name"], 0), len(outs) - 1)
        counters[sp["name"]] = i + 1
        if calls is not None:
            calls.append({"capability": sp["name"], "prompt": prompt, "attempt": i + 1})
        return {"ok": True, "output": outs[i], "tokens": 0, "duration_s": 0.0, "cost_usd": 0.0}
    return ex


def _director(b, tmp_path, script, calls=None):
    return dr.Director(b, tmp_path / "run", run_id="lot3", executor=_executor(script, calls),
                       audit_path=tmp_path / "audit.jsonl", journal_dir=tmp_path / "journal")


# --- politique -------------------------------------------------------------------------------


def test_politique_convoke_selon_l_etat_pas_selon_un_ordre(full, partial, tmp_path):
    st = dr.new_state("lot3", "p")
    assert dr.next_action(partial, st, dr.measure(partial))["capability"] == "decompose"
    a = dr.next_action(full, st, dr.measure(full))
    assert (a["kind"], a["capability"], a["code"]) == ("convoke", "wiremap", dr.JOIN_LINES_WITHOUT_COUVRE)


def test_deux_blueprints_deux_suites_aucune_egale_a_un_profil(full, partial, tmp_path):
    fm_txt = (_RUN_DIR / "artifacts" / "s3-decompo.txt").read_text(encoding="utf-8")
    archi_txt = _fenced(json.loads((_RUN_DIR / "blueprint.json").read_text(encoding="utf-8")))
    script = {"decompose": [fm_txt], "architect": [archi_txt], "wiremap": [_wiremap_joined()]}
    calls_a: list = []
    dr.Director(full, tmp_path / "A", run_id="A", executor=_executor(script, calls_a),
                audit_path=tmp_path / "a.jsonl", journal_dir=tmp_path / "ja").run(max_steps=6)
    calls_b: list = []
    dr.Director(partial, tmp_path / "B", run_id="B", executor=_executor(script, calls_b),
                audit_path=tmp_path / "b.jsonl", journal_dir=tmp_path / "jb").run(max_steps=6)
    seq_a = [c["capability"] for c in calls_a]
    seq_b = [c["capability"] for c in calls_b]
    assert seq_a == ["wiremap"]
    assert seq_b == ["decompose", "architect", "wiremap"]
    assert seq_a != seq_b
    etapes = {"decompose": "s3-decompo", "architect": "s4-archi", "wiremap": "s5-wiremap"}
    for seq in (seq_a, seq_b):
        assert tuple(etapes[c] for c in seq) not in {tuple(v) for v in PROFILES.values()}


# --- effet et réaction -----------------------------------------------------------------------


def test_changed_puis_gate_open_quand_la_jointure_est_faite(full, tmp_path):
    d = _director(full, tmp_path, {"wiremap": [_wiremap_joined()]})
    out = d.run(max_steps=4)
    assert [r["action"]["kind"] for r in out] == ["convoke", "gate_open"]
    assert out[0]["effect"] == dr.CHANGED
    assert out[0]["decision"]["measure"]["after"]["design"]["regime"] == "JOINED"
    assert d.state["status"] == "GATE_OPEN"


def test_no_effect_deux_fois_puis_halt(full, tmp_path):
    d = _director(full, tmp_path, {"wiremap": [_wiremap_agent_s5()]})   # identique à l'existant
    out = d.run(max_steps=5)
    assert [r["effect"] for r in out[:2]] == [dr.NO_EFFECT, dr.NO_EFFECT]
    assert out[2]["action"]["kind"] == "halt" and out[2]["action"]["code"] == dr.NO_EFFECT_REPEATED
    assert d.state["pending_question"]["to"] == "pierre"
    assert "accept" in d.state["pending_question"]["options"]


def test_regression_objection_reconvocation_puis_halt_revert(full, tmp_path):
    """Le run_dir vit sous EVIDENCE/runs/ (fixture dédiée, supprimée en `finally`) : la trace de
    notification (`knowledge_trace.mjs write`) REFUSE toute écriture hors de cette zone — c'est
    la garde R3, on l'exerce au lieu de la contourner."""
    run_dir = _REPO_ROOT / "EVIDENCE" / "runs" / "_pytest_lot3_regression"
    shutil.rmtree(run_dir, ignore_errors=True)
    calls: list = []
    d = dr.Director(full, run_dir, run_id="_pytest_lot3_regression", executor=_executor(
        {"wiremap": [_wiremap_ghost(), _wiremap_ghost()]}, calls),
        audit_path=tmp_path / "audit.jsonl", journal_dir=tmp_path / "journal")
    try:
        _assert_regression_flow(d, calls, run_dir, tmp_path)
    finally:
        shutil.rmtree(run_dir, ignore_errors=True)


def _assert_regression_flow(d, calls, run_dir, tmp_path):
    out = d.run(max_steps=5)
    kinds = [r["action"]["kind"] for r in out]
    assert kinds == ["convoke", "reconvoke", "halt"]
    # 1re convocation : fantômes apparus => REGRESSED, calculé par le Director
    assert out[0]["effect"] == dr.REGRESSED
    assert any("fantômes 0 -> " in r for r in out[0]["decision"]["measure"]["effect_reasons"])
    # réaction : objection émise au journal (hors run_dir) + trace dans le run, message dans la tâche
    msg = out[1]["action"]["message"]
    assert msg["type"] == "objection" and msg["to"] == ["wiremap"]
    journal = read_messages(tmp_path / "journal")
    assert [m["id"] for m in journal] == [msg["id"]]
    assert (run_dir / "knowledge_trace.json").exists()
    assert out[1]["decision"]["notified"].get("trace_path")
    assert msg["id"] in calls[1]["prompt"]
    # acquittement mesuré sur l'artefact désigné par le registre — jamais no_evidence_declared
    cons = out[1]["decision"]["measure"]["consumption"]
    assert cons["declared_by"] == "capability_registry" and cons["status"] in ("consumed", "not_consumed")
    # 2e régression (ou absence d'effet) => HALT, question à Pierre avec revert
    assert out[2]["action"]["code"] in (dr.REGRESSION_DETECTED, dr.NO_EFFECT_REPEATED)
    q = d.state["pending_question"]
    assert "revert" in q["options"] or "accept" in q["options"]
    # K8 : réponse structurée de Pierre => restauration de la version antérieure, jointure revenue
    (run_dir / dr.ANSWERS_FILE).write_text(
        json.dumps({q["id"]: {"answer": "revert", "by": "pierre", "ts": "2026-09-03T00:00:00Z"}}), encoding="utf-8")
    rec = d.apply_answers()
    assert rec["kind"] == "revert"
    wm = d.blueprint["sections"]["wiremap"]
    assert wm["writer"] == "director" and wm["source"]["status"] == "RESTORED" and wm["source"]["authorized_by"] == "pierre"
    assert dr.measure(d.blueprint)["coverage"]["design"]["couverture_fantome"] == 0
    assert d.state["pending_question"] is None


def test_accept_ouvre_la_porte_sur_decision_inscrite(full, tmp_path):
    d = _director(full, tmp_path, {"wiremap": [_wiremap_agent_s5()]})
    d.run(max_steps=5)
    q = d.state["pending_question"]
    (tmp_path / "run" / dr.ANSWERS_FILE).write_text(
        json.dumps({q["id"]: {"answer": "accept", "by": "pierre", "ts": "2026-09-03T00:00:00Z"}}), encoding="utf-8")
    r = d.step()
    assert r["action"]["kind"] == "gate_open" and r["action"]["code"] == "SUFFICIENCY_ACCEPTED_BY_PIERRE"
    kinds = [json.loads(l)["kind"] for l in (tmp_path / "run" / dr.DECISIONS_FILE).read_text(encoding="utf-8").splitlines()]
    assert "accept_gap" in kinds and kinds[-1] == "gate_open"


def test_une_reponse_non_signee_par_pierre_n_est_pas_appliquee(full, tmp_path):
    d = _director(full, tmp_path, {"wiremap": [_wiremap_agent_s5()]})
    d.run(max_steps=5)
    q = d.state["pending_question"]
    (tmp_path / "run" / dr.ANSWERS_FILE).write_text(
        json.dumps({q["id"]: {"answer": "accept", "by": "agent", "ts": "x"}}), encoding="utf-8")
    assert d.apply_answers() is None
    assert d.step()["action"]["kind"] == "halt"


# --- journal, propriété, K7 ------------------------------------------------------------------


def test_les_decisions_sont_journalisees_en_champs_structures(full, tmp_path):
    d = _director(full, tmp_path, {"wiremap": [_wiremap_joined()]})
    d.run(max_steps=4)
    lines = [json.loads(l) for l in (tmp_path / "run" / dr.DECISIONS_FILE).read_text(encoding="utf-8").splitlines()]
    assert len(lines) == d.state["steps"] == len(d.blueprint["sections"]["decisions"]["content"]) - 1  # +1 import
    for rec in lines:
        assert rec["by"] == "director" and rec["signal"] and rec["kind"]
        if rec["kind"] in ("convoke", "reconvoke"):
            assert rec["effect"] in (dr.CHANGED, dr.NO_EFFECT, dr.REGRESSED)
            assert set(rec["measure"]) >= {"before", "after", "before_section_sha", "after_section_sha", "effect_reasons"}
    assert (tmp_path / "run" / dr.STATE_FILE).exists()


def test_le_director_n_ecrit_jamais_les_sections_de_pierre(full, tmp_path):
    before = {s: full["sections"][s]["version"] for s in ("identity", "vision", "constraints", "gameplay")}
    d = _director(full, tmp_path, {"wiremap": [_wiremap_ghost(), _wiremap_ghost()]})
    d.run(max_steps=5)
    assert {s: d.blueprint["sections"][s]["version"] for s in before} == before


def test_une_demande_d_escalade_de_l_agent_est_consignee_jamais_executee(full, tmp_path):
    out = "ESCALATE_REQUEST: trop gros pour moi\n" + _wiremap_joined()
    d = _director(full, tmp_path, {"wiremap": [out]})
    r = d.step()
    assert r["result"]["requests"] == [{"kind": "escalation", "reason": "trop gros pour moi", "producer": "agent"}]
    assert all(pb["producer"] != "agent" for pb in r["result"]["problems"])
    assert r["decision"]["measure"]["requests"][0]["kind"] == "escalation"
    assert d.step()["action"]["kind"] == "gate_open"   # la demande n'a pas changé la politique

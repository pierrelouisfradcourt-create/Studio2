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


def _manifest_lines(run_dir: Path, etape: str) -> list[dict]:
    p = run_dir / "context" / f"{etape}.manifest.jsonl"
    return [json.loads(l) for l in p.read_text(encoding="utf-8").splitlines() if l.strip()]


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


# --- Task 3 : le manifest mesure la cible ---------------------------------------------------------


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

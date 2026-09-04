"""Lot 4 (plan V2 2026-09-03, GO Pierre, D4) — le slice vertical : porte de suffisance -> build ->
oracles -> verdict signé -> dossier HumanGate, conduit par le Director, avec réaction à un oracle rouge.

Forme de production réelle : Blueprint importé de la baseline ; le builder FACTICE copie le jeu réel
de la baseline (`GAMES/runm_breakout/`) sous un projet-fixture de GAMES/ et écrit la wiremap.json
réelle ; les ORACLES et le VERDICT sont RÉELS (exécuteurs du driver, HMAC, verify_run) — c'est ce
qui coûte ~1 s ici, et c'est ce qui prouve.

Ce que ces tests prouvent :
  - après gate_open, le Director convoque le builder, puis rend les oracles, puis le verdict, puis le
    dossier HumanGate ; la suite RÉELLE des étapes n'égale aucun profil ORDER ;
  - le verdict est signé et `verify_run` rend AUTHENTIQUE ; `software_verdict` vient des reçus ;
  - un oracle rouge déclenche la re-convocation du builder au tier supérieur, avec objection, bornée
    par MAX_ESCALATIONS, puis HALT vers Pierre ;
  - `progress` (IMPROVED / NONE) est rendu sans changer le contrat `effect` ;
  - K4 : l'acquittement cherche aussi dans la restitution texte de l'agent.
Le projet-fixture sous GAMES/ et son run_dir sont supprimés en `finally`. NO_CLAIM_ALLOWED.
"""
from __future__ import annotations

import json
import shutil
from pathlib import Path

import pytest

from forge import blueprint as bp
from forge import director as dr
from forge.blueprint_import import import_run_dir
from forge.dispatch import PROFILES

_REPO_ROOT = Path(__file__).resolve().parents[2]
_RUN_DIR = _REPO_ROOT / "EVIDENCE" / "runs" / "runm_breakout"
_BRIEF = _REPO_ROOT / "EVIDENCE" / "briefs" / "runm_breakout" / "project_brief.yaml"
_GAME = _REPO_ROOT / "GAMES" / "runm_breakout"
_FIXTURE = "_pytest_lot4_slice"

pytestmark = [
    pytest.mark.skipif(not (_RUN_DIR / "state.json").exists() or not (_GAME / "run-oracle.mjs").exists(),
                       reason="baseline M ter (run + jeu) absente"),
    pytest.mark.skipif(shutil.which("node") is None, reason="node absent"),
]


def _fenced(obj) -> str:
    return "Rapport.\n\n```json\n" + json.dumps(obj, ensure_ascii=False) + "\n```\n"


def _joined_wiremap() -> dict:
    return json.loads((_RUN_DIR / "wiremap.json").read_text(encoding="utf-8"))


def _blueprint_gate_open(project: str) -> dict:
    """Blueprint importé, wiremap.design remplacée par la wiremap JOINED : la porte s'ouvre d'emblée."""
    b = import_run_dir(_RUN_DIR, brief_path=_BRIEF, project=project)
    wm = json.loads(json.dumps(b["sections"]["wiremap"]["content"]))
    wm["design"] = {"source": {"path": None, "sha256": None, "status": "TEST", "run_id": "t"},
                    "content": _joined_wiremap()}
    wm.pop("built", None)
    bp.write_section(b, "wiremap", wm, writer="wiremap", source={"path": None, "sha256": None, "status": "TEST"})
    return b


def _copy_game(dst: Path) -> None:
    if dst.exists():
        shutil.rmtree(dst)
    shutil.copytree(_GAME, dst, ignore=shutil.ignore_patterns("node_modules", "__pycache__"))


def _fake_builder(project: str, *, break_game: bool = False, calls: list | None = None, ack: bool = False):
    """Copie le jeu réel de la baseline sous GAMES/<fixture>, écrit run_dir/wiremap.json (post_artifact).
    `break_game` : casse une règle de logique pour faire rougir l'oracle réel."""
    def ex(prompt, sp, payload):
        if calls is not None:
            calls.append({"capability": sp["name"], "model": payload.model, "prompt": prompt})
        if sp["name"] != "builder":
            raise AssertionError(f"capacité inattendue convoquée : {sp['name']}")
        dst = _REPO_ROOT / "GAMES" / project
        _copy_game(dst)
        if break_game:
            engine = dst / "engine.mjs"
            engine.write_text(engine.read_text(encoding="utf-8") + "\nexport const __CASSE = 1; throw new Error('casse volontaire');\n",
                              encoding="utf-8")
        # le builder « tient la WireMap à jour » : il écrit wiremap.json dans le run_dir
        run_dir = Path(_current_run_dir[0])
        (run_dir / "wiremap.json").write_text(json.dumps(_joined_wiremap(), ensure_ascii=False), encoding="utf-8")
        out = "Jeu construit sous GAMES/, WireMap tenue à jour.\n"
        if ack:
            out += "Acquitté : " + " ".join(
                t for t in prompt.split() if t.startswith("AMD-")) + "\n"
        return {"ok": True, "output": out, "tokens": 0, "duration_s": 0.0, "cost_usd": 0.0}
    return ex


_current_run_dir: list = [None]


@pytest.fixture
def slice_env(tmp_path):
    project = _FIXTURE
    run_dir = _REPO_ROOT / "EVIDENCE" / "runs" / project
    shutil.rmtree(run_dir, ignore_errors=True)
    shutil.rmtree(_REPO_ROOT / "GAMES" / project, ignore_errors=True)
    _current_run_dir[0] = str(run_dir)
    try:
        yield project, run_dir, tmp_path
    finally:
        shutil.rmtree(run_dir, ignore_errors=True)
        shutil.rmtree(_REPO_ROOT / "GAMES" / project, ignore_errors=True)


def _director(project, run_dir, tmp_path, executor):
    return dr.Director(_blueprint_gate_open(project), run_dir, run_id=project, executor=executor,
                       audit_path=tmp_path / "audit.jsonl", journal_dir=tmp_path / "journal", stop_at_gate=False)


# --- le slice complet, oracles et verdict RÉELS -----------------------------------------------


def test_slice_gate_build_oracles_verdict_humangate(slice_env):
    project, run_dir, tmp_path = slice_env
    calls: list = []
    d = _director(project, run_dir, tmp_path, _fake_builder(project, calls=calls))
    out = d.run(max_steps=8)
    kinds = [r["action"]["kind"] for r in out]
    assert kinds == ["gate_open", "build", "qa", "humangate"], kinds
    assert d.state["status"] == "HUMANGATE_READY"
    # suite réelle : s9 puis les oracles puis le verdict — égale à AUCUN profil ORDER
    seq = d.state["sequence"]
    assert seq == ["s9-build", "s10a-oracle-code", "s10b-oracle-archi", "s10c-oracle-wiremap", "s12-verdict"]
    assert tuple(seq) not in {tuple(v) for v in PROFILES.values()}
    # verdict signé, authentifié, issu des reçus d'oracle
    qa = out[2]["result"]
    assert qa["statuses"] == {"s10a-oracle-code": "OK", "s10b-oracle-archi": "OK",
                              "s10c-oracle-wiremap": "OK", "s12-verdict": "OK"}, qa["details"]
    assert qa["verify_run"] == "AUTHENTIQUE"
    verdict = json.loads(Path(qa["verdict_path"]).read_text(encoding="utf-8"))
    assert verdict["software_verdict"] == "OK" and verdict["claim_verdict"] == "NO_CLAIM_ALLOWED"
    assert verdict["hmac"]
    # le build a écrit la section construite ; le gel des règles a été posé avant les oracles
    assert d.blueprint["sections"]["wiremap"]["content"]["built"]["content"]["features"]
    assert (run_dir / "wiremap_frozen.json").exists() and (run_dir / "oracles.json").exists()
    assert calls[0]["capability"] == "builder" and calls[0]["model"] == "claude-haiku-4-5-20251001"
    # dossier HumanGate : faits séparés, non prouvé écrit, aucun verdict global
    dossier = out[3]["result"]
    assert dossier["software_verdict"] == "OK" and dossier["verify_run"] == "AUTHENTIQUE"
    assert dossier["sequence_equals_profile"] is None and dossier["no_global_ready_verdict"] is True
    assert "valeur du jeu (Pierre joue)" in dossier["not_proven"]
    assert (run_dir / "HUMANGATE_DOSSIER.md").exists()
    # progress est rendu, le contrat effect est intact
    assert out[1]["effect"] in (dr.CHANGED, dr.NO_EFFECT, dr.REGRESSED)
    assert out[1]["progress"] in (dr.IMPROVED, dr.NONE)


def test_oracle_rouge_escalade_le_builder_avec_objection_puis_halt(slice_env):
    project, run_dir, tmp_path = slice_env
    calls: list = []
    d = _director(project, run_dir, tmp_path, _fake_builder(project, break_game=True, calls=calls, ack=True))
    out = d.run(max_steps=12)
    kinds = [r["action"]["kind"] for r in out]
    assert kinds[:3] == ["gate_open", "build", "qa"]
    assert out[2]["result"]["statuses"]["s10a-oracle-code"] in ("FAIL", "BLOCKED")
    # réaction : re-build au tier supérieur, avec objection portant les reçus d'oracle
    assert kinds[3] == "build" and out[3]["action"]["code"] == dr.ORACLE_RED
    assert out[3]["action"]["model_override"] == "sonnet"
    msg = out[3]["action"]["message"]
    assert msg["type"] == "objection" and msg["to"] == ["builder"] and "s10a-oracle-code" in msg["reason"]
    assert calls[1]["model"] == "sonnet"                      # portée : cette étape seule (ESC-1)
    assert out[3]["decision"]["measure"]["model_executed"] == "sonnet"
    # K4 : l'agent a cité l'identifiant dans sa restitution texte -> consumed (trouvé dans artifacts/*.txt)
    cons = out[3]["decision"]["measure"]["consumption"]
    assert cons["status"] == "consumed" and any(f.endswith(".txt") for f in cons["found_in"])
    # bornée : haiku -> sonnet -> opus puis HALT vers Pierre
    assert kinds[-1] == "halt" and out[-1]["action"]["code"] == dr.ORACLE_RED_PERSISTENT
    models = [c["model"] for c in calls]
    assert models == ["claude-haiku-4-5-20251001", "sonnet", "opus"]
    assert d.state["pending_question"]["options"] == ["accept", "requalify", "skip"]   # K8, Lot 4
    # les problèmes portés à Pierre ont un producteur mécanique
    assert all(p["producer"].startswith("s10") for p in d.state["last_problems"])


def test_progress_none_deux_fois_halt_sans_changer_effect(tmp_path):
    """Deux CHANGED sans progrès sur la porte de suffisance => HALT NO_PROGRESS_REPEATED."""
    b = import_run_dir(_RUN_DIR, brief_path=_BRIEF, project="runm_breakout")
    import re
    txt = (_RUN_DIR / "artifacts" / "s5-wiremap.txt").read_text(encoding="utf-8")
    base = json.loads(re.findall(r"```json\s*(.*?)```", txt, re.S)[-1])     # sortie agent : prose + bloc fenced
    variants = []
    for i in (1, 2):                                            # même forme (sans couvre), contenu différent
        v = json.loads(json.dumps(base))
        v["features"][0]["version"] = f"v{i + 10}"
        variants.append(_fenced(v))
    n = [0]

    def ex(prompt, sp, payload):
        out = variants[min(n[0], 1)]
        n[0] += 1
        return {"ok": True, "output": out, "tokens": 0, "duration_s": 0.0, "cost_usd": 0.0}
    d = dr.Director(b, tmp_path / "run", run_id="lot4-np", executor=ex,
                    audit_path=tmp_path / "audit.jsonl", journal_dir=tmp_path / "journal")
    out = d.run(max_steps=5)
    assert [(r["effect"], r.get("progress")) for r in out[:2]] == [(dr.CHANGED, dr.NONE), (dr.CHANGED, dr.NONE)]
    assert out[2]["action"]["kind"] == "halt" and out[2]["action"]["code"] == dr.NO_PROGRESS_REPEATED


def test_un_build_interrompu_par_timeout_qui_a_ecrit_est_repris_pour_re_jugement(slice_env):
    """FIR-02 transposé : l'exécuteur meurt au timeout mais le jeu et wiremap.json sont sur disque =>
    salvage (problème K7 EXECUTOR_TIMEOUT_SALVAGED, producteur exécuteur), section écrite, puis QA."""
    project, run_dir, tmp_path = slice_env
    inner = _fake_builder(project)

    def timed_out(prompt, sp, payload):
        inner(prompt, sp, payload)                      # le builder a travaillé et écrit...
        return {"ok": False, "reason": "claude -p timeout (540s) — arbre de process tué (FIR-01)"}
    d = _director(project, run_dir, tmp_path, timed_out)
    out = d.run(max_steps=4)
    kinds = [r["action"]["kind"] for r in out]
    assert kinds[:3] == ["gate_open", "build", "qa"], kinds
    build = out[1]["result"]
    assert build["ok"] and build.get("salvaged") is True
    assert [p["code"] for p in build["problems"]] == ["EXECUTOR_TIMEOUT_SALVAGED"]
    assert build["problems"][0]["producer"] == "executor"
    assert out[2]["result"]["statuses"]["s12-verdict"] == "OK"


def test_requalify_reprend_la_wiremap_du_run_et_rejoue_la_qa(slice_env):
    """K8 : après un HALT ORACLE_RED_PERSISTENT, la réponse `requalify` de Pierre reprend wiremap.json
    du run comme wiremap.built (source SALVAGED) et force la QA sur cette version."""
    project, run_dir, tmp_path = slice_env
    d = _director(project, run_dir, tmp_path, _fake_builder(project))
    d.run(max_steps=3)                                  # gate_open, build, qa (OK)
    # on simule l'état laissé par une escalade épuisée : question ORACLE_RED_PERSISTENT en attente
    d.state["pending_question"] = {"id": "Q-x", "code": dr.ORACLE_RED_PERSISTENT, "capability": "builder",
                                   "signal": "wiremap.built@builder", "to": "pierre",
                                   "options": ["accept", "requalify", "skip"]}
    d.state["status"] = "HALTED"
    d.state["build"]["qa"]["software_verdict"] = "FAIL"
    dr.save_state(run_dir, d.state)
    (run_dir / dr.ANSWERS_FILE).write_text(json.dumps({"Q-x": {"answer": "requalify", "by": "pierre", "ts": "t"}}),
                                           encoding="utf-8")
    rec = d.apply_answers()
    assert rec["kind"] == "requalify"
    built = d.blueprint["sections"]["wiremap"]["content"]["built"]
    assert built["source"]["status"] == "SALVAGED" and built["source"]["authorized_by"] == "pierre"
    assert d.state["build"]["qa"] is None and d.state["pending_question"] is None
    r = d.step()
    assert r["action"]["kind"] == "qa" and r["result"]["statuses"]["s12-verdict"] == "OK"

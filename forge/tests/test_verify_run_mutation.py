"""Oracle du chemin /gate (P0.3) — verify_run redescend dans la preuve mutation.

Avant P0.3, `verify_run` re-signait le verdict et re-lisait l'évidence, mais ne
re-vérifiait PAS le reçu mutation embarqué : un verdict OK de jeu restait
« AUTHENTIQUE » même si le code du jeu avait changé après la signature. P0.3 :
plus aucun chemin vers un OK ratifiable avec une preuve périmée, absente ou
invalide — y compris au moment du /gate. NO_CLAIM_ALLOWED.
"""
import json
import sys
import time
from pathlib import Path

import pytest

from forge.driver import ForgeDriver
from forge.verdict import (
    build_aggregate_verdict,
    make_signed_receipt,
    new_nonce,
    signed_aggregate_record,
)
from forge.verify_run import verify_run


def _oracle_config(tmp_path, project, exit_code=0):
    cfg = tmp_path / "oracles_test.json"
    cfg.write_text(
        json.dumps({project: {
            "cwd": str(tmp_path),
            "command": [sys.executable, "-c", f"import sys; sys.exit({exit_code})"],
        }}),
        encoding="utf-8",
    )
    return cfg


def _game_dir(tmp_path):
    g = tmp_path / "game"
    g.mkdir()
    (g / "logic.mjs").write_text("export const win = 1 >= 0;\n", encoding="utf-8")
    (g / "run-oracle.mjs").write_text(
        'import { spawn } from "node:child_process";\n'
        'spawn("node", ["e2e.mjs"]);\n', encoding="utf-8")
    (g / "e2e.mjs").write_text(
        'import { chromium } from "playwright";\n'
        'await page.click("#restart");\n'
        'const s = window.__game;\n'
        'if (window.__game.over) show("#overlay");\n', encoding="utf-8")
    (g / "logic.test.mjs").write_text("// suite\n", encoding="utf-8")
    (g / "properties.test.mjs").write_text("// suite\n", encoding="utf-8")
    return g


def _all_killed(source_path, test_argv, *, cwd, **kw):
    return {"total": 4, "killed": 4, "survived": 0, "score": 1.0, "survivors": []}


class StubExecutor:
    def __call__(self, payload, decision, context):
        return {"ok": True, "output": f"artefact {payload.etape}"}


@pytest.fixture
def offline(monkeypatch):
    monkeypatch.setattr("forge.runtime.qwen_available", lambda *a, **k: False)


def _green_game_verdict(tmp_path):
    """Produit un verdict OK de jeu via le VRAI driver (producteur légitime)."""
    run_dir = tmp_path / "run"
    g = _game_dir(tmp_path)
    key = tmp_path / "forge_test.key"
    report = ForgeDriver(
        "jeu", "jeu-1", profile="micro", is_game=True,
        executor=StubExecutor(), src_root=g,
        logic_files=["logic.mjs"], mutation_runner=_all_killed,
        mutation_baseline_runner=lambda argv, cwd: True,
        run_dir=run_dir, oracle_config=_oracle_config(tmp_path, "jeu"),
        key_file=key, audit_path=tmp_path / "audit.jsonl",
        telemetry_path=tmp_path / "t.jsonl", builder_runs_path=tmp_path / "br.jsonl",
    ).run()
    assert report["software_verdict"] == "OK"  # préalable
    return run_dir / "verdict.json", g, key


def test_verdict_jeu_vert_authentique(tmp_path, offline):
    verdict_path, g, key = _green_game_verdict(tmp_path)
    res = verify_run(verdict_path, key_file=key)
    assert res["mutation_ok"] is True
    assert res["overall"] is True


def test_code_modifie_apres_verdict_rejete_au_gate(tmp_path, offline):
    """LE trou /gate : verdict signé OK, puis le code du jeu change. verify_run
    doit REJETER (preuve périmée), pas dire AUTHENTIQUE."""
    verdict_path, g, key = _green_game_verdict(tmp_path)
    (g / "logic.mjs").write_text("export const win = false;\n", encoding="utf-8")
    res = verify_run(verdict_path, key_file=key)
    assert res["mutation_ok"] is False
    assert res["overall"] is False
    assert any("divergent" in p for p in res["mutation_problems"])


def test_triage_ajoute_apres_verdict_rejete_au_gate(tmp_path, offline):
    verdict_path, g, key = _green_game_verdict(tmp_path)
    (g / "mutation_triage.json").write_text(
        json.dumps([{"name": "x", "line": 1, "justification": "après coup"}]),
        encoding="utf-8")
    res = verify_run(verdict_path, key_file=key)
    assert res["overall"] is False
    assert any("triage" in p for p in res["mutation_problems"])


def test_jeu_bloque_sans_preuve_pas_overall_true(tmp_path, offline):
    """Finding 2 (revue P0.3) : un verdict de JEU dont le reçu code porte le
    marqueur e2e mais AUCUNE preuve mutation ne doit pas passer overall=True au
    /gate — même quand software_verdict n'est pas OK (le court-circuit status!=OK
    rendait la garde jeu-sans-preuve inatteignable)."""
    key = tmp_path / "forge_test.key"
    evidence = tmp_path / "oracle.log"
    evidence.write_text("log\n", encoding="utf-8")
    code = make_signed_receipt(
        "code", "jeu-1", "BLOCKED",
        {"returncode": -1, "e2e": {"passed": True, "raisons": []},
         "reason": "fichiers logiques inconnus"},
        evidence_path=str(evidence), ts=time.time(), key_file=key)
    archi = make_signed_receipt("archi", "jeu-1", "SKIPPED", {"reason": "p"},
                                ts=time.time(), key_file=key)
    wire = make_signed_receipt("wiremap", "jeu-1", "SKIPPED", {"reason": "p"},
                               ts=time.time(), key_file=key)
    agg = build_aggregate_verdict(
        "jeu", "jeu-1", code, archi, wire, "aucun",
        redteam_ran=False, nonce=new_nonce(), ts=time.time(), key_file=key)
    verdict_path = tmp_path / "verdict.json"
    verdict_path.write_text(
        json.dumps(signed_aggregate_record(agg, key_file=key), ensure_ascii=False),
        encoding="utf-8")

    res = verify_run(verdict_path, key_file=key)
    assert res["mutation_ok"] is False
    assert res["overall"] is False


def test_producteur_malhonnete_jeu_sans_preuve_rejete(tmp_path, offline):
    """Un verdict fabriqué avec la clé (mauvais producteur) : reçu code OK de
    JEU (garde e2e présente) mais SANS reçu mutation embarqué => REJET au gate."""
    key = tmp_path / "forge_test.key"
    evidence = tmp_path / "oracle.log"
    evidence.write_text("faux log\n", encoding="utf-8")
    code = make_signed_receipt(
        "code", "jeu-1", "OK",
        {"returncode": 0, "e2e": {"passed": True, "raisons": []}},  # jeu, sans mutation
        evidence_path=str(evidence), ts=time.time(), key_file=key)
    archi = make_signed_receipt("archi", "jeu-1", "SKIPPED", {"reason": "profil"},
                                ts=time.time(), key_file=key)
    wire = make_signed_receipt("wiremap", "jeu-1", "SKIPPED", {"reason": "profil"},
                               ts=time.time(), key_file=key)
    agg = build_aggregate_verdict(
        "jeu", "jeu-1", code, archi, wire, "aucun",
        redteam_ran=False, nonce=new_nonce(), ts=time.time(), key_file=key)
    assert agg.software_verdict == "OK"  # l'agrégat seul ne voit pas le trou
    verdict_path = tmp_path / "verdict.json"
    verdict_path.write_text(
        json.dumps(signed_aggregate_record(agg, key_file=key), ensure_ascii=False),
        encoding="utf-8")

    res = verify_run(verdict_path, key_file=key)
    assert res["mutation_ok"] is False
    assert res["overall"] is False
    assert any("sans preuve mutation" in p for p in res["mutation_problems"])

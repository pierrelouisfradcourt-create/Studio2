"""Oracle du câblage driver de la garde anti-théâtre des harnais (R1) — s10a jeu.

FORGE_V2_CONSOLIDATION.md §4-A : check_harness_no_hardcoded_flags contribue au gate
s10a AU MÊME TITRE que les gardes e2e/solvabilité (pas advisory) : un JEU dont le
harnais ÉCRIT son succès en LITTÉRAL (`passed: true`) au lieu de le CALCULER =>
reçu code FAIL avec raisons (alimente l'escalade), jamais un vert — même si
e2e/solvabilité/mutation sont par ailleurs verts. Prouve le trou fermé : avant ce
câblage, un harnais théâtral passait tous les gates verts (miroir exact de la
leçon P2 solvabilité). NO_CLAIM_ALLOWED.

NB : helpers nommés `_jeu_...` (pas `_game_dir`) pour rester HORS du shim de
conftest.py (même convention que test_driver_solvability.py).
"""
import json
import sys

import pytest

from forge.driver import ForgeDriver


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


def _jeu_avec_flag_theatral(tmp_path):
    """Mini-jeu e2e+solvabilité câblés, mais solvability.mjs ÉCRIT son succès en
    dur (`passed: true`, `allMovesLegal: true`) au lieu de le calculer — le profil
    exact du théâtre d'oracle constaté (audit P1, pattern bi-projet)."""
    g = tmp_path / "game"
    g.mkdir()
    (g / "logic.mjs").write_text("export const win = 1 >= 0;\n", encoding="utf-8")
    (g / "run-oracle.mjs").write_text(
        'import { spawn } from "node:child_process";\n'
        'spawn("node", ["e2e.mjs"]);\n'
        'spawn("node", ["solvability.mjs"]);\n',
        encoding="utf-8",
    )
    (g / "e2e.mjs").write_text(
        'import { chromium } from "playwright";\n'
        'await page.click("#restart");\n'
        'const s = window.__game;\n'
        'if (window.__game.over) show("#overlay");\n',
        encoding="utf-8",
    )
    (g / "solvability.mjs").write_text(
        "const result = { passed: true, allMovesLegal: true };\n"
        "console.log(JSON.stringify(result));\n",
        encoding="utf-8",
    )
    (g / "logic.test.mjs").write_text("// suite logique\n", encoding="utf-8")
    (g / "properties.test.mjs").write_text("// suite propriétés\n", encoding="utf-8")
    return g


def _jeu_sain(tmp_path):
    """Contrôle positif : même mini-jeu, mais le harnais CALCULE son statut."""
    g = _jeu_avec_flag_theatral(tmp_path)
    (g / "solvability.mjs").write_text(
        "const moves = [1];\n"
        "const result = { passed: moves.length > 0 };\n"
        "console.log(JSON.stringify(result));\n"
        "if (!result.passed) process.exit(1);\n",
        encoding="utf-8",
    )
    return g


def _all_killed(source_path, test_argv, *, cwd, **kw):
    return {"total": 4, "killed": 4, "survived": 0, "score": 1.0, "survivors": []}


class StubExecutor:
    def __init__(self):
        self.calls = []

    def __call__(self, payload, decision, context):
        self.calls.append((payload.etape, context.get("model_override")))
        return {"ok": True, "output": f"artefact {payload.etape}"}


@pytest.fixture
def offline(monkeypatch):
    monkeypatch.setattr("forge.runtime.qwen_available", lambda *a, **k: False)


def _kwargs(tmp_path, run_dir, exit_code=0):
    return dict(
        run_dir=run_dir,
        oracle_config=_oracle_config(tmp_path, "jeu", exit_code),
        key_file=tmp_path / "forge_test.key",
        audit_path=tmp_path / "audit.jsonl",
        telemetry_path=tmp_path / "telemetry.jsonl",
        builder_runs_path=tmp_path / "builder_runs.jsonl",
        mutation_baseline_runner=lambda argv, cwd: True,  # baseline verte stubée
    )


def _verdict(run_dir):
    return json.loads((run_dir / "verdict.json").read_text(encoding="utf-8"))


# --- rouge : harnais théâtral => reçu code FAIL, alimente l'escalade --------------

def test_jeu_harnais_theatral_fail_et_escalade(tmp_path, offline):
    """LE trou fermé : e2e câblé + solvabilité câblée + mutation verte, mais le
    harnais ÉCRIT son succès en dur => s10a FAIL avec raisons (jamais un vert), et
    le FAIL alimente la boucle d'escalade comme tout rouge mécanique."""
    run_dir = tmp_path / "run"
    g = _jeu_avec_flag_theatral(tmp_path)
    ex = StubExecutor()
    report = ForgeDriver("jeu", "jeu-1", profile="micro", is_game=True,
                         executor=ex, src_root=g,
                         logic_files=["logic.mjs"], mutation_runner=_all_killed,
                         **_kwargs(tmp_path, run_dir)).run()
    assert report["software_verdict"] == "FAIL"
    assert report["decision"] == "BLOCKED"

    state = json.loads((run_dir / "state.json").read_text(encoding="utf-8"))
    s10a = state["steps"]["s10a-oracle-code"]
    assert s10a["status"] == "FAIL"
    harness = s10a["detail"]["harness_no_hardcoded_flags"]
    assert harness["passed"] is False
    assert any("passed" in r for r in harness["raisons"])
    # e2e et solvabilité (câblage), elles, étaient vertes : c'est BIEN R1 qui gate ici
    assert s10a["detail"]["e2e"]["passed"] is True
    assert s10a["detail"]["solvability"]["passed"] is True
    # le FAIL alimente l'escalade (plusieurs tentatives s9-build, comme un rouge e2e)
    s9_calls = [c for c in ex.calls if c[0] == "s9-build"]
    assert len(s9_calls) > 1

    # exposé dans le reçu signé du verdict, comme e2e/solvabilité le sont
    code = _verdict(run_dir)["oracles"]["code"]
    assert code["status"] == "FAIL"
    assert code["detail"]["harness_no_hardcoded_flags"]["passed"] is False


# --- vert : contrôle positif (harnais sain, calcule son statut) -------------------

def test_jeu_harnais_sain_reste_vert(tmp_path, offline):
    """Un jeu dont le harnais CALCULE son statut verdit comme avant, et le reçu
    signé expose la garde comme verte (auditable à HumanGate, comme e2e/solvabilité)."""
    run_dir = tmp_path / "run"
    g = _jeu_sain(tmp_path)
    report = ForgeDriver("jeu", "jeu-1", profile="micro", is_game=True,
                         executor=StubExecutor(), src_root=g,
                         logic_files=["logic.mjs"], mutation_runner=_all_killed,
                         **_kwargs(tmp_path, run_dir)).run()
    assert report["status"] == "DONE"
    assert report["software_verdict"] == "OK"
    assert report["decision"] == "HUMANGATE_READY"
    code = _verdict(run_dir)["oracles"]["code"]
    assert code["status"] == "OK"
    assert code["detail"]["harness_no_hardcoded_flags"] == {"passed": True, "raisons": []}

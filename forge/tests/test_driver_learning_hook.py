"""Câblage driver -> forge.learning_hook (plan 4 étapes ratifié Pierre 2026-07-26, étape 1).

Vérifie QUE le driver appelle `learning_hook.record_learning_for_subject` après un
s10a-oracle-code vert sur un JEU (jamais avant, jamais sur un non-jeu, jamais sur un run
rouge), et QUE toute exception levée par le hook reste STRICTEMENT best-effort — jamais un
run déjà vert ne doit basculer FAIL/BLOCKED à cause d'un incident dans l'instrumentation
d'apprentissage (même garantie que le Context Manifest, dispatch.py::prepare_dispatch).

Renommage `record_learning_if_brick` -> `record_learning_for_subject` (LEARNING_SUBJECT_MODEL_V1,
studio_brain/decisions/PROPOSED_2026-07-26_ratifications.md) : le hook enregistre désormais
`subject:{type:'game', id:project}` pour tout run de jeu, sans exiger de correspondance
catalogue (un jeu n'est pas une brique).

`learning_hook.record_learning_for_subject` est stubée (monkeypatch) dans ces tests : la
correction réelle (shell-out vers node) est déjà couverte par
forge/tests/test_learning_hook.py — ici on vérifie uniquement le CÂBLAGE (les bons
arguments, au bon moment, jamais bloquant), pas la mesure elle-même.
"""
import json
import sys
from pathlib import Path

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


def _game_dir(tmp_path):
    """Mini-jeu satisfaisant la garde e2e structurelle (check_e2e_harness)."""
    g = tmp_path / "game"
    g.mkdir()
    (g / "logic.mjs").write_text("export const speed = 3;\nexport const win = 1 >= 0;\n",
                                 encoding="utf-8")
    (g / "run-oracle.mjs").write_text(
        'import { spawn } from "node:child_process";\n'
        'spawn("node", ["e2e.mjs"]);\n',
        encoding="utf-8",
    )
    (g / "e2e.mjs").write_text(
        'import { chromium } from "playwright";\n'
        'await page.click("#restart");\n'
        'const s = window.__game;\n'
        'if (window.__game.over) show("#overlay");\n',
        encoding="utf-8",
    )
    (g / "logic.test.mjs").write_text("// suite logique\n", encoding="utf-8")
    (g / "properties.test.mjs").write_text("// suite propriétés\n", encoding="utf-8")
    return g


def _all_killed(source_path, test_argv, *, cwd, **kw):
    return {"total": 4, "killed": 4, "survived": 0, "score": 1.0, "survivors": []}


class StubExecutor:
    def __init__(self):
        self.calls = []

    def __call__(self, payload, decision, context):
        self.calls.append(payload.etape)
        return {"ok": True, "output": f"artefact {payload.etape}"}


@pytest.fixture
def offline(monkeypatch):
    monkeypatch.setattr("forge.runtime.qwen_available", lambda *a, **k: False)


def _kwargs(tmp_path, run_dir, project="jeu", exit_code=0):
    return dict(
        run_dir=run_dir,
        oracle_config=_oracle_config(tmp_path, project, exit_code),
        key_file=tmp_path / "forge_test.key",
        audit_path=tmp_path / "audit.jsonl",
        telemetry_path=tmp_path / "telemetry.jsonl",
        builder_runs_path=tmp_path / "builder_runs.jsonl",
        mutation_baseline_runner=lambda argv, cwd: True,
    )


def test_hook_appele_apres_oracle_vert_sur_un_jeu(tmp_path, offline, monkeypatch):
    calls = []
    monkeypatch.setattr(
        "forge.learning_hook.record_learning_for_subject",
        lambda **kw: calls.append(kw) or {"recorded": False, "reason": "stub"},
    )
    run_dir = tmp_path / "run"
    g = _game_dir(tmp_path)
    report = ForgeDriver("jeu", "jeu-1", profile="micro", is_game=True,
                         executor=StubExecutor(), src_root=g, game_dir=g,
                         logic_files=["logic.mjs"], mutation_runner=_all_killed,
                         **_kwargs(tmp_path, run_dir)).run()
    assert report["software_verdict"] == "OK"
    assert len(calls) == 1
    assert calls[0]["project"] == "jeu"
    assert calls[0]["game_dir"] == g
    assert calls[0]["is_game"] is True
    assert calls[0]["oracle_iterations"] == 1


def test_hook_non_appele_si_oracle_reste_bloque(tmp_path, offline, monkeypatch):
    """I1 (test_driver_mutation.py) : ni logic_files ni wiremap.json => BLOCKED.
    Le hook d'apprentissage ne doit JAMAIS tourner sur une étape non verte."""
    calls = []
    monkeypatch.setattr(
        "forge.learning_hook.record_learning_for_subject",
        lambda **kw: calls.append(kw) or {"recorded": False, "reason": "stub"},
    )
    run_dir = tmp_path / "run"
    g = _game_dir(tmp_path)
    report = ForgeDriver("jeu", "jeu-1", profile="micro", is_game=True,
                         executor=StubExecutor(), src_root=g, game_dir=g,
                         mutation_runner=_all_killed,
                         **_kwargs(tmp_path, run_dir)).run()
    assert report["software_verdict"] == "BLOCKED"
    assert calls == []


def test_hook_non_appele_pour_un_run_non_jeu(tmp_path, offline, monkeypatch):
    calls = []
    monkeypatch.setattr(
        "forge.learning_hook.record_learning_for_subject",
        lambda **kw: calls.append(kw) or {"recorded": False, "reason": "stub"},
    )
    run_dir = tmp_path / "run"
    src = tmp_path / "src"
    src.mkdir()
    (src / "logic.mjs").write_text("export const x = 1;\n", encoding="utf-8")
    (src / "logic.test.mjs").write_text(
        "import { test } from 'node:test'; import assert from 'node:assert';\n"
        "test('ok', () => assert.equal(1, 1));\n",
        encoding="utf-8",
    )
    report = ForgeDriver("jeu", "jeu-1", profile="micro", is_game=False,
                         executor=StubExecutor(), src_root=src,
                         **_kwargs(tmp_path, run_dir)).run()
    assert report["software_verdict"] == "OK"
    assert calls == []  # is_game=False -> le driver n'appelle même pas le hook


def test_exception_dans_le_hook_najamais_de_run_deja_vert(tmp_path, offline, monkeypatch):
    """Best-effort strict (même garantie que context_manifest, dispatch.py) : une
    exception dans l'instrumentation d'apprentissage ne doit JAMAIS transformer un
    run déjà vert en échec."""
    def _boom(**kw):
        raise RuntimeError("panne simulée de l'instrumentation")

    monkeypatch.setattr("forge.learning_hook.record_learning_for_subject", _boom)
    run_dir = tmp_path / "run"
    g = _game_dir(tmp_path)
    report = ForgeDriver("jeu", "jeu-1", profile="micro", is_game=True,
                         executor=StubExecutor(), src_root=g, game_dir=g,
                         logic_files=["logic.mjs"], mutation_runner=_all_killed,
                         **_kwargs(tmp_path, run_dir)).run()
    assert report["software_verdict"] == "OK"
    assert report["decision"] == "HUMANGATE_READY"

# P0-2 ADR-003, cote PRODUCTEUR — le driver DECLARE la game-ness dans le verdict signe.
#
# Dette de preuve fermee ici. Le champ `is_game` de `AggregateVerdict` est commite
# (f035755) et `verify_run` le lit en priorite, mais RIEN ne prouvait que le driver le
# renseigne reellement : les 3 tests P0-2 deja commites appellent
# `build_aggregate_verdict` EN DIRECT, sans jamais construire de ForgeDriver. Tant que
# le producteur n'est pas prouve, le champ vaut None sur tous les verdicts produits et
# `verify_run` retombe sur l'inference historique — le defaut d'origine reste ouvert.
#
# Ces tests portent sur le VERDICT ECRIT SUR DISQUE par un run reel, jamais sur un
# appel direct a la couche verdict : c'est precisement le maillon qui manquait.
from __future__ import annotations

import json
import sys
from pathlib import Path

import pytest

from forge.driver import ForgeDriver
from forge.verify_run import verify_run


@pytest.fixture
def offline(monkeypatch):
    monkeypatch.setattr("forge.runtime.qwen_available", lambda *a, **k: False)


class StubExecutor:
    def __call__(self, payload, decision, context):
        return {"ok": True, "output": f"artefact {payload.etape}"}


def _oracle_config(tmp_path: Path, project: str) -> Path:
    cfg = tmp_path / "oracles.json"
    cfg.write_text(
        json.dumps({project: {"cwd": str(tmp_path),
                              "command": [sys.executable, "-c", "import sys; sys.exit(0)"]}}),
        encoding="utf-8")
    return cfg


def _kwargs(tmp_path: Path, run_dir: Path, project: str = "proj") -> dict:
    return dict(
        run_dir=run_dir,
        oracle_config=_oracle_config(tmp_path, project),
        key_file=tmp_path / "forge_test.key",
        audit_path=tmp_path / "audit.jsonl",
        telemetry_path=tmp_path / "telemetry.jsonl",
        builder_runs_path=tmp_path / "builder_runs.jsonl",
        mutation_baseline_runner=lambda argv, cwd: True,
    )


def _game_dir(tmp_path: Path) -> Path:
    """Mini-jeu satisfaisant la garde e2e structurelle (meme forme que
    test_driver_mutation._game_dir)."""
    g = tmp_path / "game"
    g.mkdir()
    (g / "logic.mjs").write_text("export const speed = 3;\nexport const win = 1 >= 0;\n",
                                 encoding="utf-8")
    (g / "run-oracle.mjs").write_text(
        'import { spawn } from "node:child_process";\nspawn("node", ["e2e.mjs"]);\n',
        encoding="utf-8")
    (g / "e2e.mjs").write_text(
        'import { chromium } from "playwright";\n'
        'await page.click("#restart");\n'
        'const s = window.__game;\n'
        'if (s.score !== 0) throw new Error("score");\n'
        'if (s.lives !== 3) throw new Error("lives");\n'
        'if (s.state !== "run") throw new Error("state");\n',
        encoding="utf-8")
    return g


def _all_killed(source_path, test_argv, *, cwd, **kw):
    return {"total": 4, "killed": 4, "survived": 0, "score": 1.0, "survivors": []}


def test_non_jeu_declare_false_et_non_none(tmp_path, offline):
    """Un run NON-jeu ecrit `is_game: false` — DECLARE, pas absent. La distinction
    est la substance de P0-2 : `None` laisse verify_run inferer, `False` est un fait
    signe par le producteur."""
    run_dir = tmp_path / "run"
    ForgeDriver("proj", "proj-1", profile="micro", executor=StubExecutor(),
                **_kwargs(tmp_path, run_dir)).run()
    record = json.loads((run_dir / "verdict.json").read_text(encoding="utf-8"))
    assert record["is_game"] is False
    assert record["is_game"] is not None


def test_jeu_declare_true_dans_le_verdict_ecrit(tmp_path, offline):
    """Le fait `is_game=True` passe du driver au verdict SUR DISQUE."""
    run_dir = tmp_path / "run"
    g = _game_dir(tmp_path)
    ForgeDriver("jeu", "jeu-1", profile="micro", is_game=True,
                executor=StubExecutor(), src_root=g, logic_files=["logic.mjs"],
                mutation_runner=_all_killed,
                **_kwargs(tmp_path, run_dir, project="jeu")).run()
    record = json.loads((run_dir / "verdict.json").read_text(encoding="utf-8"))
    assert record["is_game"] is True


def test_le_champ_declare_est_SIGNE_avec_le_verdict(tmp_path, offline):
    """Le champ n'est pas decoratif : il entre dans la charge utile du HMAC et le
    verdict reste verifiable. Falsifie par la negative : modifier `is_game` apres coup
    casse la signature."""
    run_dir = tmp_path / "run"
    key = tmp_path / "forge_test.key"
    ForgeDriver("proj", "proj-1", profile="micro", executor=StubExecutor(),
                **_kwargs(tmp_path, run_dir)).run()
    path = run_dir / "verdict.json"
    assert verify_run(path, key_file=key)["hmac_ok"] is True

    record = json.loads(path.read_text(encoding="utf-8"))
    record["is_game"] = True          # falsification apres signature
    path.write_text(json.dumps(record, ensure_ascii=False, sort_keys=True),
                    encoding="utf-8")
    assert verify_run(path, key_file=key)["hmac_ok"] is False, (
        "un is_game altere apres coup doit casser le HMAC — sinon le champ n'est pas signe")


def test_verdict_PARTIEL_porte_aussi_la_declaration(tmp_path, offline):
    """Second point d'appel du producteur : le verdict de perimetre PARTIAL (profil
    sans s12) porte la meme declaration que la chaine complete."""
    run_dir = tmp_path / "run"
    ForgeDriver("proj", "proj-r", profile="review", executor=StubExecutor(),
                **_kwargs(tmp_path, run_dir)).run()
    partial = run_dir / "verdict.partial.json"
    assert partial.exists(), "profil sans s12 : le verdict partiel doit exister"
    record = json.loads(partial.read_text(encoding="utf-8"))
    assert record["scope"] == "PARTIAL"
    assert record["is_game"] is False

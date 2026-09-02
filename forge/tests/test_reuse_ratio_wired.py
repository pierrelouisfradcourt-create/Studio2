"""Garde structurelle reuse_ratio (Tier 1 #2) — advisory, jamais gating."""
from pathlib import Path

from forge.static_oracles import check_reuse_ratio_wired

REPO_ROOT = Path(__file__).resolve().parents[2]


def _write(d: Path, name: str, txt: str) -> None:
    (d / name).write_text(txt, encoding="utf-8")


def test_run_oracle_absent_rejete(tmp_path):
    res = check_reuse_ratio_wired(tmp_path)
    assert res["passed"] is False
    assert any("run-oracle.mjs absent" in r for r in res["raisons"])


def test_reuse_ratio_non_cable_rejete(tmp_path):
    _write(tmp_path, "run-oracle.mjs", 'import "./logic.test.mjs";\n')
    res = check_reuse_ratio_wired(tmp_path)
    assert res["passed"] is False
    assert any("n'invoque pas reuse_ratio.mjs" in r for r in res["raisons"])


def test_mention_en_commentaire_rejetee(tmp_path):
    _write(
        tmp_path, "run-oracle.mjs",
        '// TODO: node reuse_ratio.mjs — désactivé\n'
        'console.log("reuse_ratio.mjs pas encore lancé");\n',
    )
    res = check_reuse_ratio_wired(tmp_path)
    assert res["passed"] is False


def test_reuse_ratio_cable_via_spawn_passe(tmp_path):
    _write(
        tmp_path, "run-oracle.mjs",
        'import { spawn } from "node:child_process";\n'
        'spawn("node", ["../../forge/reuse_ratio.mjs", "."]);\n',
    )
    res = check_reuse_ratio_wired(tmp_path)
    assert res["passed"] is True, res["raisons"]


def test_reuse_ratio_cable_via_import_passe(tmp_path):
    _write(tmp_path, "run-oracle.mjs", 'import "../../forge/reuse_ratio.mjs";\n')
    res = check_reuse_ratio_wired(tmp_path)
    assert res["passed"] is True, res["raisons"]


def test_kb_tactics_reel_cable_passe():
    # Câblage réel opéré en Tier 1 #2 — reference vivante mise à jour.
    res = check_reuse_ratio_wired(REPO_ROOT / "GAMES" / "kb_tactics")
    assert res["passed"] is True, res["raisons"]

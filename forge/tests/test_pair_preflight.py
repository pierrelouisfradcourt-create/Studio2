"""RUN 2 V1 — point A7 (docs/forge/RUN2_PROTOCOLE_V1_PROPOSED.md). Vérifie que
`forge.pair_preflight.check_pair_prerequisites` est MÉCANIQUEMENT bloquant :
verts réels sur le repo réel, rouges nommés sur absence simulée, mode
`run_tests` mocké vert/rouge (aucun vrai subprocess pytest dans cette suite --
`-m "not gpu_window"` n'exempte pas la lenteur d'un vrai sous-appel pytest
imbriqué)."""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT))

from forge import pair_preflight  # noqa: E402


def test_all_three_checks_green_on_real_repo():
    """Les 3 gardes C1/C2/C3 du sas R3/freeze (commit 6e5e7da) sont réellement
    présentes dans ce repo -- ce test échoue si elles sont un jour retirées
    sans que ce prérequis de paire soit mis à jour en conséquence."""
    result = pair_preflight.check_pair_prerequisites(repo_root=REPO_ROOT, run_tests=False)

    ids = {c["id"] for c in result["checks"]}
    assert {"C1_target_declared", "C2_micro_redeclaration", "C3_modification_locus_channel"} <= ids

    by_id = {c["id"]: c for c in result["checks"]}
    assert by_id["C1_target_declared"]["ok"] is True, by_id["C1_target_declared"]["detail"]
    assert by_id["C2_micro_redeclaration"]["ok"] is True, by_id["C2_micro_redeclaration"]["detail"]
    assert by_id["C3_modification_locus_channel"]["ok"] is True, by_id["C3_modification_locus_channel"]["detail"]

    assert result["ok"] is True
    assert result["raisons"] == []


def test_cli_exit_zero_on_real_repo():
    proc = subprocess.run(
        [sys.executable, "-m", "forge.pair_preflight", "--repo-root", str(REPO_ROOT)],
        cwd=str(REPO_ROOT),
        env={**__import__("os").environ, "PYTHONPATH": str(REPO_ROOT)},
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert proc.returncode == 0, proc.stdout + proc.stderr
    assert "PAIR_PREFLIGHT: OK" in proc.stdout


# --- absence simulée : C1 -------------------------------------------------


def test_c1_fails_when_method_absent(monkeypatch):
    import forge.driver as driver_mod

    monkeypatch.delattr(driver_mod.ForgeDriver, "_answer_modification_locus", raising=True)

    result = pair_preflight.check_pair_prerequisites(repo_root=REPO_ROOT, run_tests=False)
    by_id = {c["id"]: c for c in result["checks"]}

    assert by_id["C1_target_declared"]["ok"] is False
    assert "absente" in by_id["C1_target_declared"]["detail"]
    assert result["ok"] is False
    assert any("C1" in r or "modification_locus" in r for r in result["raisons"])


def test_c1_fails_when_test_file_absent(tmp_path):
    """Simule un repo où la méthode existe mais où le fichier de test dédié a
    disparu : copie le repo réel dans un dossier temporaire minimal-viable en
    ne retirant QUE le fichier de test, pour isoler la cause."""
    fake_repo = tmp_path / "fake_repo"
    (fake_repo / "forge" / "tests").mkdir(parents=True)
    # le check C1 a besoin d'importer forge.driver réel (méthode présente) --
    # on pointe repo_root vers un dossier SANS le fichier de test, tout en
    # laissant l'import forge.driver résoudre normalement (déjà importé /
    # scripts réel toujours sur sys.path via conftest).
    result = pair_preflight.check_pair_prerequisites(repo_root=fake_repo, run_tests=False)
    by_id = {c["id"]: c for c in result["checks"]}

    assert by_id["C1_target_declared"]["ok"] is False
    assert "test_r3_locus.py" in by_id["C1_target_declared"]["detail"]
    assert result["ok"] is False


# --- absence simulée : C2 -------------------------------------------------


def test_c2_fails_when_method_absent(monkeypatch):
    import forge.driver as driver_mod

    monkeypatch.delattr(driver_mod.ForgeDriver, "_maybe_run_micro_redeclarations", raising=True)

    result = pair_preflight.check_pair_prerequisites(repo_root=REPO_ROOT, run_tests=False)
    by_id = {c["id"]: c for c in result["checks"]}

    assert by_id["C2_micro_redeclaration"]["ok"] is False
    assert "absente" in by_id["C2_micro_redeclaration"]["detail"]
    assert result["ok"] is False


# --- absence simulée : C3 -------------------------------------------------


def test_c3_fails_when_constant_absent(monkeypatch):
    import forge.run_real as run_real_mod

    monkeypatch.delattr(run_real_mod, "_MODIFICATION_LOCUS_TYPES", raising=True)

    result = pair_preflight.check_pair_prerequisites(repo_root=REPO_ROOT, run_tests=False)
    by_id = {c["id"]: c for c in result["checks"]}

    assert by_id["C3_modification_locus_channel"]["ok"] is False
    assert "absente" in by_id["C3_modification_locus_channel"]["detail"]
    assert result["ok"] is False


def test_c3_fails_when_constant_incomplete(monkeypatch):
    import forge.run_real as run_real_mod

    monkeypatch.setattr(run_real_mod, "_MODIFICATION_LOCUS_TYPES", ("gm_worldscan",))

    result = pair_preflight.check_pair_prerequisites(repo_root=REPO_ROOT, run_tests=False)
    by_id = {c["id"]: c for c in result["checks"]}

    assert by_id["C3_modification_locus_channel"]["ok"] is False
    assert "incomplète" in by_id["C3_modification_locus_channel"]["detail"]
    assert result["ok"] is False


# --- mode --run-tests, subprocess pytest MOCKÉ (jamais un vrai spawn) ----


def test_run_tests_mode_green_when_subprocess_mocked_success(monkeypatch):
    captured_cmd = {}

    def fake_run(cmd, cwd=None, capture_output=None, text=None, timeout=None):
        captured_cmd["cmd"] = cmd
        return subprocess.CompletedProcess(cmd, returncode=0, stdout="3 passed\n", stderr="")

    monkeypatch.setattr(pair_preflight.subprocess, "run", fake_run)

    result = pair_preflight.check_pair_prerequisites(repo_root=REPO_ROOT, run_tests=True)
    by_id = {c["id"]: c for c in result["checks"]}

    assert by_id["run_tests_subprocess"]["ok"] is True
    assert "not gpu_window" in captured_cmd["cmd"]
    assert result["ok"] is True


def test_run_tests_mode_red_when_subprocess_mocked_failure(monkeypatch):
    def fake_run(cmd, cwd=None, capture_output=None, text=None, timeout=None):
        return subprocess.CompletedProcess(cmd, returncode=1, stdout="1 failed, 2 passed\n", stderr="")

    monkeypatch.setattr(pair_preflight.subprocess, "run", fake_run)

    result = pair_preflight.check_pair_prerequisites(repo_root=REPO_ROOT, run_tests=True)
    by_id = {c["id"]: c for c in result["checks"]}

    assert by_id["run_tests_subprocess"]["ok"] is False
    assert result["ok"] is False
    assert any(by_id["run_tests_subprocess"]["detail"] == r for r in result["raisons"])


def test_run_tests_not_requested_is_advisory_only_and_does_not_block(monkeypatch):
    """Sans --run-tests, le contrôle de présence seul suffit à ok:True -- mais
    le detail dit honnêtement qu'aucune preuve d'exécution fraîche n'a eu lieu
    (doctrine : jamais un vert par défaut déguisé en preuve d'exécution)."""
    result = pair_preflight.check_pair_prerequisites(repo_root=REPO_ROOT, run_tests=False)
    by_id = {c["id"]: c for c in result["checks"]}

    assert by_id["run_tests_subprocess"]["ok"] is True
    assert by_id["run_tests_subprocess"].get("advisory") is True
    assert "PRÉSENCE seul" in by_id["run_tests_subprocess"]["detail"] or "présence" in by_id["run_tests_subprocess"]["detail"].lower()


def test_cli_run_tests_flag_returns_nonzero_on_mocked_failure(monkeypatch):
    """Le CLI --run-tests doit sortir 1 si le check run_tests_subprocess est
    rouge -- exercé directement via _main() avec subprocess.run monkeypatché,
    jamais un vrai sous-appel pytest imbriqué."""
    def fake_run(cmd, cwd=None, capture_output=None, text=None, timeout=None):
        return subprocess.CompletedProcess(cmd, returncode=1, stdout="boom\n", stderr="")

    monkeypatch.setattr(pair_preflight.subprocess, "run", fake_run)

    rc = pair_preflight._main(["--run-tests", "--repo-root", str(REPO_ROOT)])
    assert rc == 1

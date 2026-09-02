import sys

from forge.oracle import OracleSpec, run_oracle


def _spec(tmp_path, code, returncode):
    # A cross-platform fake oracle: run this interpreter with -c.
    return OracleSpec(
        project="fake",
        cwd=tmp_path,
        command=[sys.executable, "-c", f"import sys; print({code!r}); sys.exit({returncode})"],
    )


def test_run_green_oracle_passes(tmp_path):
    result = run_oracle(_spec(tmp_path, "hello-green", 0), evidence_dir=tmp_path / "ev")
    assert result.passed is True
    assert result.returncode == 0
    assert result.evidence_path.exists()
    with open(result.evidence_path, encoding="utf-8") as fh:
        assert "hello-green" in fh.read()


def test_run_red_oracle_fails_and_still_captures(tmp_path):
    result = run_oracle(_spec(tmp_path, "boom", 1), evidence_dir=tmp_path / "ev")
    assert result.passed is False
    assert result.returncode == 1
    assert result.evidence_path.exists()


def test_run_oracle_times_out_and_is_not_passed(tmp_path):
    import sys
    slow = OracleSpec(
        project="slow",
        cwd=tmp_path,
        command=[sys.executable, "-c", "import time; time.sleep(5)"],
    )
    result = run_oracle(slow, evidence_dir=tmp_path / "ev", timeout=0.5)
    assert result.passed is False
    assert result.returncode == -2
    assert result.evidence_path.exists()

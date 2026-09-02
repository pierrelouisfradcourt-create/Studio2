import json
import sys

from forge.gate import forge_gate


def _config(tmp_path, command):
    cfg = {"fake": {"cwd": ".", "command": command}}
    path = tmp_path / "oracles.json"
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(cfg, fh)
    return path


def _exit(returncode):
    return [sys.executable, "-c", f"import sys; sys.exit({returncode})"]


def test_gate_green_is_ok_and_signed(tmp_path):
    res = forge_gate(
        "fake",
        config_path=_config(tmp_path, _exit(0)),
        key_file=tmp_path / "k",
        evidence_dir=tmp_path / "ev",
    )
    assert res.ok is True
    assert res.verdict.software_verdict == "OK"
    assert res.signature


def test_gate_red_is_not_ok(tmp_path):
    res = forge_gate(
        "fake",
        config_path=_config(tmp_path, _exit(1)),
        key_file=tmp_path / "k",
        evidence_dir=tmp_path / "ev",
    )
    assert res.ok is False
    assert res.verdict.software_verdict == "FAIL"


def test_gate_unknown_project_is_blocked(tmp_path):
    res = forge_gate(
        "missing",
        config_path=_config(tmp_path, _exit(0)),
        key_file=tmp_path / "k",
        evidence_dir=tmp_path / "ev",
    )
    assert res.ok is False
    assert res.verdict.software_verdict == "BLOCKED"


def test_gate_missing_binary_is_blocked(tmp_path):
    res = forge_gate(
        "fake",
        config_path=_config(tmp_path, ["definitely-not-a-real-binary-xyz123", "--nope"]),
        key_file=tmp_path / "k",
        evidence_dir=tmp_path / "ev",
    )
    assert res.ok is False
    assert res.verdict.software_verdict == "BLOCKED"


def test_gate_missing_config_is_blocked(tmp_path):
    res = forge_gate("fake", config_path=tmp_path / "does_not_exist.json",
                     key_file=tmp_path / "k", evidence_dir=tmp_path / "ev")
    assert res.ok is False
    assert res.verdict.software_verdict == "BLOCKED"


def test_gate_malformed_config_is_blocked(tmp_path):
    bad = tmp_path / "oracles.json"
    with open(bad, "w", encoding="utf-8") as fh:
        fh.write("{ not valid json ")
    res = forge_gate("fake", config_path=bad, key_file=tmp_path / "k", evidence_dir=tmp_path / "ev")
    assert res.ok is False
    assert res.verdict.software_verdict == "BLOCKED"

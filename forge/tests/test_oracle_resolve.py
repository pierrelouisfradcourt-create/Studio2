import json
import os

import pytest

from forge.oracle import OracleNotFound, OracleSpec, resolve_oracle


def _write_config(tmp_path):
    cfg = {"demo": {"cwd": ".", "command": ["echo", "hi"]}}
    path = tmp_path / "oracles.json"
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(cfg, fh)
    return path


def test_resolve_known_project(tmp_path):
    spec = resolve_oracle("demo", config_path=_write_config(tmp_path))
    assert isinstance(spec, OracleSpec)
    assert spec.project == "demo"
    assert spec.command == ["echo", "hi"]
    assert spec.cwd.is_absolute()


def test_resolve_unknown_project_raises(tmp_path):
    with pytest.raises(OracleNotFound):
        resolve_oracle("nope", config_path=_write_config(tmp_path))


def test_resolve_normalizes_command0_but_not_args(tmp_path):
    cfg = {"p": {"cwd": ".", "command": ["a/b/py", "scripts/x/tests/"]}}
    path = tmp_path / "oracles.json"
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(cfg, fh)
    spec = resolve_oracle("p", config_path=path)
    assert spec.command[0] == os.path.normpath("a/b/py")   # command[0] normalized
    assert spec.command[1] == "scripts/x/tests/"           # arg untouched

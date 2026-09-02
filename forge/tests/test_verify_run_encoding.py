"""P3 — robustesse encodage console de verify_run.main.

Sous console Windows cp1252, le warning de dérive git (⚠) et les puces (✗)
levaient UnicodeEncodeError → exit 1 (crash) sur un verdict AUTHENTIQUE.
Ces tests simulent un stdout/stderr réellement encodés en cp1252 (strict)
et prouvent : aucune UnicodeEncodeError ne fuit, et l'exit code sémantique
(0 authentique / 2 rejet) est préservé.
"""
from __future__ import annotations

import io
import sys

from forge import verify_run as vr


def _res(overall: bool, git_ok: bool) -> dict:
    """Résultat contrôlé couvrant TOUTES les branches de print non-ASCII."""
    return {
        "overall": overall,
        "hmac_ok": True,
        "evidence_ok": False,
        "evidence_problems": ["code: évidence altérée/absente (état.log)"],
        "mutation_ok": False,
        "mutation_problems": ["hash code divergent — preuve périmée"],
        "git_ok": git_ok,
        "git_stored": "a" * 40,
        "git_current": "b" * 40,
        "software_verdict": "OK",
        "decision": "HUMANGATE_READY",
    }


def _cp1252_streams(monkeypatch) -> tuple[io.TextIOWrapper, io.TextIOWrapper]:
    """Remplace stdout/stderr par de vrais TextIOWrapper cp1252 stricts.

    Appelé dans le CORPS du test (pas en fixture) : la capture pytest ré-assigne
    sys.stdout entre le setup des fixtures et la phase call, ce qui écraserait
    un monkeypatch posé en fixture."""
    out = io.TextIOWrapper(io.BytesIO(), encoding="cp1252", errors="strict")
    err = io.TextIOWrapper(io.BytesIO(), encoding="cp1252", errors="strict")
    monkeypatch.setattr(sys, "stdout", out)
    monkeypatch.setattr(sys, "stderr", err)
    return out, err


def _read(wrapper: io.TextIOWrapper) -> str:
    wrapper.flush()
    return wrapper.buffer.getvalue().decode("cp1252", errors="replace")


def test_warning_derive_git_ne_crashe_pas_et_exit_0(monkeypatch):
    """Verdict authentique + dérive git (⚠) : pas d'UnicodeEncodeError, exit 0."""
    out, _ = _cp1252_streams(monkeypatch)
    monkeypatch.setattr(vr, "verify_run", lambda p: _res(overall=True, git_ok=False))
    code = vr.main(["peu/importe/verdict.json"])
    assert code == 0
    texte = _read(out)
    assert "AUTHENTIQUE" in texte
    assert "TOCTOU" in texte  # le warning de dérive est bien émis, lisible


def test_rejet_avec_caracteres_non_ascii_exit_2(monkeypatch):
    """Verdict rejeté (✗ + problèmes accentués) : pas de crash, exit 2 préservé."""
    out, _ = _cp1252_streams(monkeypatch)
    monkeypatch.setattr(vr, "verify_run", lambda p: _res(overall=False, git_ok=False))
    code = vr.main(["peu/importe/verdict.json"])
    assert code == 2
    texte = _read(out)
    assert "REJET" in texte


def test_usage_sans_argument_sur_stderr_cp1252(monkeypatch):
    """Branche usage (stderr) : exit 2, aucun crash même en cp1252."""
    _, err = _cp1252_streams(monkeypatch)
    code = vr.main([])
    assert code == 2
    assert "usage" in _read(err)


def test_streams_sans_reconfigure_toleres(monkeypatch):
    """Un flux sans .reconfigure (ex. StringIO des harnais) ne fait pas crasher."""
    out = io.StringIO()
    monkeypatch.setattr(sys, "stdout", out)
    monkeypatch.setattr(sys, "stderr", io.StringIO())
    monkeypatch.setattr(vr, "verify_run", lambda p: _res(overall=True, git_ok=True))
    assert vr.main(["x.json"]) == 0
    assert "AUTHENTIQUE" in out.getvalue()

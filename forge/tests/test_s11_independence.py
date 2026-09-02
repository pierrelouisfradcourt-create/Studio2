"""Fiche 5 (sas ratifié Pierre 2026-08-30) — s11-redteam-code réellement
INDÉPENDANT, bloquant, pour le profil `full_content` UNIQUEMENT.

Mesuré 2026-08-29/30 (runs de référence kitten 8/9, TD) : `contracts/roles.yaml`
résout `redteam_code` -> claude-opus (bloc claude-local), donc `route_step`
renvoie `RUNNER_CLAUDE` pour s11 — l'indépendance n'a JAMAIS existé à cette étape.
`ForgeDriver._run_llm` court-circuite désormais CE chemin, SEULEMENT sous
`REDTEAM_INDEPENDENT_PROFILES` (aujourd'hui `("full_content",)`), en réutilisant
EXACTEMENT le mécanisme déjà prouvé à s6-redteam-plan (`forge.runtime.route_step`
/ `run_qwen_step`, sonde `qwen_available`) — aucun ping réimplémenté, aucun
changement à `contracts/roles.yaml`.

Aucun vrai LM Studio ici : `forge.driver.qwen_available` et
`forge.driver.run_qwen_step` sont monkeypatchés (module-level, comme
`offline` dans test_driver.py). NO_CLAIM_ALLOWED.
"""
import json

import pytest

import forge.driver as driver_mod
import forge.context_manifest as context_manifest_mod
import forge.run_real as run_real_mod
from forge.driver import ForgeDriver, REDTEAM_INDEPENDENT_PROFILES


def _driver_for_step(tmp_path, profile, executor=None):
    """Un ForgeDriver + un `state` minimal (steps PENDING) — sans passer par
    `run()` (trop lourd pour `full_content`, ~18 étapes) : `_run_llm` ne lit
    QUE `state["steps"][etape]`, jamais les autres étapes."""
    run_dir = tmp_path / "run"
    run_dir.mkdir(parents=True, exist_ok=True)
    d = ForgeDriver(
        "proj", "proj-1", run_dir=run_dir, profile=profile, executor=executor,
        key_file=tmp_path / "forge_test.key",
        audit_path=tmp_path / "audit.jsonl",
        telemetry_path=tmp_path / "telemetry.jsonl",
    )
    state = {
        "run_status": "RUNNING",
        "steps": {e: {"status": "PENDING", "attempts": 0} for e in d.order},
    }
    return d, state, run_dir


class ClaudeStub:
    """Exécuteur `claude` factice — trace les appels, jamais invoqué sous
    `full_content` (exigence 6 : aucun fallback)."""

    def __init__(self):
        self.calls = []

    def __call__(self, payload, decision, context):
        self.calls.append(payload.etape)
        return {"ok": True, "output": f"artefact {payload.etape}"}


class RefusingExecutor:
    """Preuve NÉGATIVE : lève si jamais appelé (aucun fallback claude-blind
    ne doit atteindre l'exécuteur sous `full_content`)."""

    def __call__(self, payload, decision, context):
        raise AssertionError(
            f"exécuteur claude appelé à {payload.etape} — fallback interdit "
            "sous full_content (exigence 6)"
        )


_QWEN_REPORT = (
    "Rapport red-team code.\n"
    "```json\n"
    '{"findings": []}\n'
    "```\n"
)


# --- exigence 1/4 : full_content + LM Studio UP -> Qwen réellement exécuté -------

def test_full_content_qwen_ok_force_runner_qwen_independent(tmp_path, monkeypatch):
    monkeypatch.setattr(driver_mod, "qwen_available", lambda *a, **k: True)
    captured_payloads = []

    def fake_run_qwen_step(payload, adapter=None):
        captured_payloads.append(payload)
        return {"ok": True, "reviewer": "qwen2.5-14b-instruct", "output": _QWEN_REPORT}

    monkeypatch.setattr(driver_mod, "run_qwen_step", fake_run_qwen_step)

    d, state, _run_dir = _driver_for_step(tmp_path, "full_content", executor=RefusingExecutor())
    ok = d._run_llm(state, "s11-redteam-code")

    assert ok is True
    entry = state["steps"]["s11-redteam-code"]
    assert entry["status"] == "OK"
    detail = entry["detail"]
    assert detail["runner"] == "qwen"
    assert detail["reviewer"] == "qwen2.5-14b-instruct"
    assert detail["qwen_ok"] is True
    assert detail["independent"] is True

    # exigence 7 : reviewer réel (jamais le modèle Claude du contrat, `payload.model`
    # résolu par roles.yaml pour `redteam_code` == "anthropic/claude-opus-4-8").
    assert len(captured_payloads) == 1
    assert captured_payloads[0].model != "anthropic/claude-opus-4-8"


# --- exigence 5 : LM Studio down -> BLOCKED + HALT, raison exacte -----------------

def test_full_content_lmstudio_down_blocks_and_halts_before_any_call(tmp_path, monkeypatch):
    monkeypatch.setattr(driver_mod, "qwen_available", lambda *a, **k: False)

    def must_not_be_called(*a, **k):
        raise AssertionError("run_qwen_step appelé alors que qwen_available()=False")

    monkeypatch.setattr(driver_mod, "run_qwen_step", must_not_be_called)

    d, state, _run_dir = _driver_for_step(tmp_path, "full_content", executor=RefusingExecutor())
    ok = d._run_llm(state, "s11-redteam-code")

    assert ok is False
    assert state["run_status"] == "HALTED"
    entry = state["steps"]["s11-redteam-code"]
    assert entry["status"] == "BLOCKED"
    assert entry["detail"]["reason"] == (
        "red-team indépendant requis (full_content) : LM Studio indisponible"
    )
    assert state["reason"] == entry["detail"]["reason"]


# --- exigence 6/8 : Qwen crash en cours d'appel -> BLOCKED, jamais de fallback ----

def test_full_content_qwen_crash_mid_call_blocks_no_fallback(tmp_path, monkeypatch):
    monkeypatch.setattr(driver_mod, "qwen_available", lambda *a, **k: True)
    monkeypatch.setattr(
        driver_mod, "run_qwen_step",
        lambda payload, adapter=None: {
            "ok": False, "reviewer": "claude-blind (fallback)",
            "attempted": "qwen2.5-14b-instruct", "reason": "call_failed",
        },
    )

    d, state, _run_dir = _driver_for_step(tmp_path, "full_content", executor=RefusingExecutor())
    ok = d._run_llm(state, "s11-redteam-code")

    assert ok is False
    assert state["run_status"] == "HALTED"
    entry = state["steps"]["s11-redteam-code"]
    assert entry["status"] == "BLOCKED"
    reason = entry["detail"]["reason"]
    assert "aucun fallback autorisé" in reason
    assert "call_failed" in reason
    # `RUNNER_CLAUDE_BLIND` (le chemin normalement emprunté par s6 sur échec Qwen)
    # ne doit JAMAIS apparaître comme runner retenu pour ce reçu — il n'y a pas
    # de reçu "OK" du tout ici (BLOCKED avant toute écriture d'artefact).
    assert "runner" not in entry["detail"]


# --- exigence 2/3 : le contexte réellement injecté à s11 ne porte pas s10 --------

def test_s11_upstream_table_excludes_s10_receipts():
    """Constat (pas une correction) : la table amont de s11-redteam-code
    (partagée par context_manifest et run_real, testée égale ailleurs) ne cite
    QUE wiremap.json — aucun verdict/reçu s10 n'y figure. Rien à retirer."""
    assert context_manifest_mod._UPSTREAM_BY_STEP["s11-redteam-code"] == ("wiremap.json",)
    assert run_real_mod._UPSTREAM_BY_STEP["s11-redteam-code"] == ("wiremap.json",)


def test_s11_prompt_injection_omits_s10_artifacts_even_if_present_on_disk(tmp_path):
    """Preuve mécanique (pas seulement la table) : même si un run_dir porte des
    artefacts nommés d'après s10 (reçu/verdict), `upstream_artifacts_section`
    pour s11-redteam-code ne les lit jamais — seul `wiremap.json` (déclaré dans
    `_UPSTREAM_BY_STEP`) peut apparaître dans la section injectée."""
    run_dir = tmp_path / "run"
    (run_dir / "artifacts").mkdir(parents=True)
    (run_dir / "wiremap.json").write_text(
        json.dumps({"features": []}), encoding="utf-8")
    # Un verdict/reçu s10 imaginaire, nommé de façon plausible : s'il fuitait
    # dans le prompt s11, ce texte-sentinelle apparaîtrait dans la section.
    (run_dir / "artifacts" / "s10a-oracle-code.txt").write_text(
        "SENTINEL_S10_RECEIPT_NE_DOIT_JAMAIS_ATTEINDRE_S11", encoding="utf-8")
    (run_dir / "verdict.json").write_text(
        json.dumps({"software_verdict": "OK", "SENTINEL": "SENTINEL_S10_RECEIPT_NE_DOIT_JAMAIS_ATTEINDRE_S11"}),
        encoding="utf-8")

    section = run_real_mod.upstream_artifacts_section("s11-redteam-code", run_dir)
    assert "wiremap.json" in section
    assert "SENTINEL_S10_RECEIPT_NE_DOIT_JAMAIS_ATTEINDRE_S11" not in section


# --- exigence 3 : profil NON listé -> comportement STRICTEMENT inchangé ----------

def test_profile_not_listed_keeps_claude_route_and_allows_fallback(tmp_path, monkeypatch):
    """`patch` porte s11-redteam-code mais n'est PAS dans
    REDTEAM_INDEPENDENT_PROFILES : le chemin normal (route_step -> RUNNER_CLAUDE,
    résolu par roles.yaml) doit rester EXACTEMENT ce qu'il était — `qwen_available`/
    `run_qwen_step` ne doivent même pas être consultés pour cette étape."""
    assert "full_content" in REDTEAM_INDEPENDENT_PROFILES
    assert "patch" not in REDTEAM_INDEPENDENT_PROFILES

    def must_not_be_called(*a, **k):
        raise AssertionError("le chemin qwen ne doit pas être consulté hors full_content")

    monkeypatch.setattr(driver_mod, "qwen_available", must_not_be_called)
    monkeypatch.setattr(driver_mod, "run_qwen_step", must_not_be_called)

    executor = ClaudeStub()
    d, state, _run_dir = _driver_for_step(tmp_path, "patch", executor=executor)
    ok = d._run_llm(state, "s11-redteam-code")

    assert ok is True
    assert executor.calls == ["s11-redteam-code"]
    entry = state["steps"]["s11-redteam-code"]
    assert entry["status"] == "OK"
    assert entry["detail"]["runner"] == "claude"
    assert "independent" not in entry["detail"]


# --- exigence 7 : reviewer réel plié dans build_aggregate_verdict via _redteam_facts --

def test_redteam_facts_relays_real_qwen_reviewer_for_full_content(tmp_path, monkeypatch):
    """`_redteam_facts` (déjà câblé vers `build_aggregate_verdict(redteam_ran=...,
    redteam_reviewer=...)`, inchangé par cette fiche) doit lire le reçu RÉEL
    laissé par le chemin forcé — preuve que le câblage aval reçoit bien
    {runner: qwen, reviewer: <réel>, qwen_ok: True}."""
    monkeypatch.setattr(driver_mod, "qwen_available", lambda *a, **k: True)
    monkeypatch.setattr(
        driver_mod, "run_qwen_step",
        lambda payload, adapter=None: {
            "ok": True, "reviewer": "qwen2.5-14b-instruct", "output": _QWEN_REPORT,
        },
    )
    d, state, _run_dir = _driver_for_step(tmp_path, "full_content", executor=RefusingExecutor())
    assert d._run_llm(state, "s11-redteam-code") is True

    reviewer, ran, blocked, findings = d._redteam_facts(state)
    assert reviewer == "qwen2.5-14b-instruct"
    assert ran is True
    assert blocked is False
    assert findings == ()

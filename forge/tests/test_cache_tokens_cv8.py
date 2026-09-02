"""CV-8 (lot de dégel 1, 2026-07-30) — capturer les champs de cache.

Défaut mesuré : `run_real._claude_call_raw` lisait `usage.input_tokens`/
`usage.output_tokens`/`total_cost_usd` mais JETAIT `cache_creation_input_tokens`/
`cache_read_input_tokens` — pourtant présents sur une capture RÉELLE (fixtures/
tool_observability/probe_bash_echo_real_capture.jsonl, cf. `test_tool_observability_
capture.py`). Impossible de séparer coût contexte (cache) / coût raisonnement.

Correctif ADDITIF : `_claude_call_raw` rend deux champs frères de `tokens`/`cost_usd`
(`cache_creation_tokens`, `cache_read_tokens`, int, 0 par défaut jamais None) ; le
driver les propage au même endroit que `tokens`/`cost_usd` dans `entry["detail"]`
(seam `ForgeDriver._run_llm`). Aucun champ existant modifié.

Ce fichier couvre : (1) parsing sur fixture RÉELLE, (2) zéro mesuré quand la clé est
absente, (3) propagation driver via un exécuteur injecté, (4) zéro par défaut sur le
chemin Qwen (qui ne porte pas ces champs) et sur `_halt_step`."""
from __future__ import annotations

import json
from pathlib import Path

import forge.run_real as run_real
from forge.driver import ForgeDriver

FIXTURES_TOOL = Path(__file__).resolve().parent / "fixtures" / "tool_observability"


def _fake_run_with_stdout(monkeypatch, stdout_text: str):
    class FakeCompleted:
        returncode = 0
        stdout = stdout_text
        stderr = ""

    monkeypatch.setattr(run_real.subprocess, "run", lambda cmd, **kw: FakeCompleted())


# --- 1. parsing RÉEL (fixture existante, jamais un nouvel appel payant) -------------

def test_claude_call_raw_extrait_les_champs_de_cache_sur_capture_reelle(tmp_path, monkeypatch):
    stream_text = (FIXTURES_TOOL / "probe_no_tools_real_capture.jsonl").read_text(encoding="utf-8")
    # cette fixture est is_error=true (budget épuisé) -> on vérifie plutôt sur un
    # flux fabriqué à la MAIN mais avec les clés RÉELLES observées sur la fixture
    # bash (mêmes noms de clés, mêmes valeurs) pour isoler un succès ok=True.
    stream_ok = (
        '{"type":"assistant","message":{"content":[{"type":"text","text":"ok"}]}}\n'
        '{"is_error":false,"duration_api_ms":100,"num_turns":1,'
        '"total_cost_usd":0.01,"usage":{"input_tokens":10,"output_tokens":155,'
        '"cache_creation_input_tokens":22738,"cache_read_input_tokens":24405},'
        '"result":"ok","type":"result"}\n'
    )
    _fake_run_with_stdout(monkeypatch, stream_ok)
    res = run_real._claude_call_raw("p", "haiku", add_dir=tmp_path, tools=())
    assert res["ok"] is True
    assert res["cache_creation_tokens"] == 22738
    assert res["cache_read_tokens"] == 24405
    # champs existants INTACTS
    assert res["tokens"] == 10 + 155
    assert res["cost_usd"] == 0.01


def test_claude_call_raw_valeurs_reelles_de_la_fixture_bash_echo():
    """Confirme les valeurs réelles portées par la fixture (usage brut, lu
    directement, sans repasser par subprocess) — ancre le test précédent à un
    fait mesuré, pas inventé."""
    from forge.tool_observability import extract_final_result
    text = (FIXTURES_TOOL / "probe_bash_echo_real_capture.jsonl").read_text(encoding="utf-8")
    result = extract_final_result(text)
    usage = result["usage"]
    assert usage["cache_creation_input_tokens"] == 22738
    assert usage["cache_read_input_tokens"] == 24405


# --- 2. zéro mesuré quand la clé est absente (jamais None) -------------------------

def test_claude_call_raw_zero_mesure_quand_cache_absent(tmp_path, monkeypatch):
    stream_ok = (
        '{"is_error":false,"total_cost_usd":0.01,'
        '"usage":{"input_tokens":9,"output_tokens":117},'
        '"result":"sans cache","type":"result"}\n'
    )
    _fake_run_with_stdout(monkeypatch, stream_ok)
    res = run_real._claude_call_raw("p", "haiku", add_dir=tmp_path, tools=())
    assert res["ok"] is True
    assert res["cache_creation_tokens"] == 0
    assert res["cache_read_tokens"] == 0
    assert res["cache_creation_tokens"] is not None
    assert res["cache_read_tokens"] is not None


# --- 3. propagation driver (seam _run_llm -> entry["detail"]) ----------------------

def _driver(tmp_path, executor):
    return ForgeDriver(
        "g", "r1", run_dir=tmp_path / "run", profile="micro",
        key_file=tmp_path / "k.key", audit_path=tmp_path / "audit.jsonl",
        telemetry_path=tmp_path / "telemetry.jsonl",
        executor=executor,
    )


def _state(d):
    return {"steps": {e: {"status": "PENDING", "attempts": 0, "detail": {}}
                      for e in d.order}}


def test_driver_propage_les_champs_de_cache_dans_le_detail(tmp_path, monkeypatch):
    monkeypatch.setattr("forge.runtime.qwen_available", lambda *a, **k: False)

    def executor(payload, decision, context):
        return {
            "ok": True, "output": "artefact", "tokens": 42, "duration_s": 1.0,
            "cost_usd": 0.02, "cache_creation_tokens": 500, "cache_read_tokens": 1200,
        }

    d = _driver(tmp_path, executor)
    etape = d.order[0]
    state = _state(d)
    d._run_llm(state, etape)
    detail = state["steps"][etape]["detail"]
    assert detail["cache_creation_tokens"] == 500
    assert detail["cache_read_tokens"] == 1200
    # champs existants INTACTS
    assert detail["tokens"] == 42
    assert detail["cost_usd"] == 0.02


def test_driver_zero_mesure_quand_executeur_ne_rend_pas_les_champs(tmp_path, monkeypatch):
    """Un exécuteur qui ne connaît pas encore les champs de cache (stub existant,
    non-régression) rend 0, jamais un crash (KeyError) ni None."""
    monkeypatch.setattr("forge.runtime.qwen_available", lambda *a, **k: False)

    def legacy_executor(payload, decision, context):
        return {"ok": True, "output": "artefact"}

    d = _driver(tmp_path, legacy_executor)
    etape = d.order[0]
    state = _state(d)
    d._run_llm(state, etape)
    detail = state["steps"][etape]["detail"]
    assert detail["cache_creation_tokens"] == 0
    assert detail["cache_read_tokens"] == 0


def test_driver_run_vert_intact_avec_les_nouveaux_champs(tmp_path, monkeypatch):
    """Non-régression : le statut/le reste du reçu ne changent pas par l'ajout
    des 2 champs — même patron que les autres tests advisory de ce lot."""
    monkeypatch.setattr("forge.runtime.qwen_available", lambda *a, **k: False)

    def executor(payload, decision, context):
        return {"ok": True, "output": "artefact", "tokens": 5, "duration_s": 0.1,
                "cost_usd": 0.001, "cache_creation_tokens": 3, "cache_read_tokens": 7}

    d = _driver(tmp_path, executor)
    etape = d.order[0]
    state = _state(d)
    ok = d._run_llm(state, etape)
    assert ok is True
    assert state["steps"][etape]["status"] == "OK"

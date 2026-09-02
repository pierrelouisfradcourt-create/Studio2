"""Correctif « rupture 10 » — un refus de MATÉRIALISATION rejoue la même
étape au lieu de halter immédiatement.

Défaut mesuré (3 runs perdus en 2 jours : 8a, 10a, 10b) : à `s2-worldscan`
(haiku), le LLM produit une sortie (16-18 Ko) dont le bloc ```json``` est
syntaxiquement cassé (virgule manquante) ou porte une clé renommée ;
`run_real` rend `{"ok": False, "reason": "... non matérialisable — ...",
"output": <sortie brute>}` — `ForgeDriver._run_llm` haltait immédiatement
(BLOCKED) alors que l'hypothèse est CONNUE et rejouable : une sortie de forme
invalide, pas un exécuteur mort.

Ce fichier couvre `ForgeDriver.materialize_attempts_max` (défaut production 3 depuis le run 10f ; historiquement
2, injectable pour les tests) : un refus de matérialisation (`ok: False`,
`output` non vide, `reason` contenant « non matérialisable »/« non
materialisable ») re-spawn la MÊME étape jusqu'à épuisement du budget ; tout
autre échec (pas de sortie, timeout, exception, raison sans le motif) halte
immédiatement — comportement STRICTEMENT inchangé.
"""
from __future__ import annotations

from pathlib import Path

import pytest

from forge.driver import ForgeDriver, _is_materialize_refusal_reason


def _driver(tmp_path, *, executor=None, materialize_attempts_max=2):
    return ForgeDriver(
        "proj-r10", "r1", run_dir=tmp_path / "run", profile="micro",
        key_file=tmp_path / "k.key", audit_path=tmp_path / "audit.jsonl",
        telemetry_path=tmp_path / "telemetry.jsonl",
        journal_path=tmp_path / "journal.jsonl",
        failure_events_path=tmp_path / "failure_events.jsonl",
        executor=executor,
        materialize_attempts_max=materialize_attempts_max,
    )


def _state(d):
    return {"steps": {e: {"status": "PENDING", "attempts": 0, "detail": {}}
                      for e in d.order}}


@pytest.fixture
def offline(monkeypatch):
    monkeypatch.setattr("forge.runtime.qwen_available", lambda *a, **k: False)


# --- helper de détection ----------------------------------------------------

def test_detecteur_reconnait_les_deux_graphies():
    assert _is_materialize_refusal_reason(
        "worldscan.json non matérialisable — virgule manquante") is True
    assert _is_materialize_refusal_reason(
        "design_questions.json non materialisable -- aucun bloc") is True


def test_detecteur_rejette_une_raison_sans_le_motif():
    assert _is_materialize_refusal_reason("timeout claude -p") is False
    assert _is_materialize_refusal_reason("") is False
    assert _is_materialize_refusal_reason(None) is False


# --- (a) refus puis succès : re-spawn, étape OK -----------------------------

def test_refus_puis_succes_re_spawn_meme_etape(tmp_path, offline):
    calls = []

    def executor(payload, decision, context):
        calls.append(context["attempt"])
        if len(calls) == 1:
            return {"ok": False,
                    "reason": "worldscan.json non matérialisable — virgule manquante",
                    "output": "SORTIE CASSÉE 1"}
        return {"ok": True, "output": "SORTIE VALIDE", "tokens": 100,
                "duration_s": 1.0, "cost_usd": 0.02}

    d = _driver(tmp_path, executor=executor)
    etape = d.order[0]
    state = _state(d)
    ok = d._run_llm(state, etape)

    assert ok is True
    entry = state["steps"][etape]
    assert entry["status"] == "OK"
    assert entry["attempts"] == 2
    assert len(calls) == 2
    assert entry["detail"]["materialize_retries"] == [
        "worldscan.json non matérialisable — virgule manquante"
    ]

    failed_path = d.run_dir / "artifacts" / f"{etape}.failed.txt"
    assert failed_path.exists()
    assert failed_path.read_text(encoding="utf-8") == "SORTIE CASSÉE 1"

    ok_path = d.run_dir / "artifacts" / f"{etape}.txt"
    assert ok_path.read_text(encoding="utf-8") == "SORTIE VALIDE"


# --- (b) deux refus : HALTED après épuisement du budget ---------------------

def test_deux_refus_epuisent_le_budget_et_haltent(tmp_path, offline):
    calls = []

    def executor(payload, decision, context):
        calls.append(context["attempt"])
        return {"ok": False,
                "reason": "worldscan.json non matérialisable — clé renommée",
                "output": f"SORTIE CASSÉE {len(calls)}"}

    d = _driver(tmp_path, executor=executor, materialize_attempts_max=2)
    etape = d.order[0]
    state = _state(d)
    ok = d._run_llm(state, etape)

    assert ok is False
    entry = state["steps"][etape]
    assert entry["status"] == "BLOCKED"
    assert entry["attempts"] == 2
    assert len(calls) == 2
    assert state["run_status"] == "HALTED"
    assert "après 2 tentatives" in state["reason"]
    assert entry["detail"]["materialize_retries"] == [
        "worldscan.json non matérialisable — clé renommée",
        "worldscan.json non matérialisable — clé renommée",
    ]

    failed1 = d.run_dir / "artifacts" / f"{etape}.failed.txt"
    failed2 = d.run_dir / "artifacts" / f"{etape}.failed-2.txt"
    assert failed1.exists() and failed1.read_text(encoding="utf-8") == "SORTIE CASSÉE 1"
    assert failed2.exists() and failed2.read_text(encoding="utf-8") == "SORTIE CASSÉE 2"


# --- (c) refus SANS output : halt immédiat, un seul appel -------------------

def test_refus_sans_output_halte_immediatement(tmp_path, offline):
    calls = []

    def executor(payload, decision, context):
        calls.append(context["attempt"])
        return {"ok": False, "reason": "worldscan.json non matérialisable — vide"}

    d = _driver(tmp_path, executor=executor)
    etape = d.order[0]
    state = _state(d)
    ok = d._run_llm(state, etape)

    assert ok is False
    entry = state["steps"][etape]
    assert entry["status"] == "BLOCKED"
    assert entry["attempts"] == 1
    assert len(calls) == 1
    assert "materialize_retries" not in entry["detail"]


# --- (d) materialize_attempts_max=1 : comportement historique ---------------

def test_attempts_max_1_halte_immediatement(tmp_path, offline):
    calls = []

    def executor(payload, decision, context):
        calls.append(context["attempt"])
        return {"ok": False,
                "reason": "worldscan.json non matérialisable — virgule manquante",
                "output": "SORTIE CASSÉE"}

    d = _driver(tmp_path, executor=executor, materialize_attempts_max=1)
    etape = d.order[0]
    state = _state(d)
    ok = d._run_llm(state, etape)

    assert ok is False
    entry = state["steps"][etape]
    assert entry["status"] == "BLOCKED"
    assert entry["attempts"] == 1
    assert len(calls) == 1

    failed_path = d.run_dir / "artifacts" / f"{etape}.failed.txt"
    assert failed_path.exists()


# --- (e) coût additionné sur 2 tentatives ------------------------------------

def test_cout_et_tokens_additionnes_sur_deux_tentatives(tmp_path, offline):
    calls = []

    def executor(payload, decision, context):
        calls.append(context["attempt"])
        if len(calls) == 1:
            return {"ok": False,
                    "reason": "worldscan.json non matérialisable — virgule manquante",
                    "output": "SORTIE CASSÉE", "tokens": 500,
                    "duration_s": 2.0, "cost_usd": 0.05}
        return {"ok": True, "output": "SORTIE VALIDE", "tokens": 300,
                "duration_s": 1.5, "cost_usd": 0.03}

    d = _driver(tmp_path, executor=executor)
    etape = d.order[0]
    state = _state(d)
    ok = d._run_llm(state, etape)

    assert ok is True
    detail = state["steps"][etape]["detail"]
    assert detail["tokens"] == 800
    assert detail["cost_usd"] == pytest.approx(0.08)
    assert detail["duration_s"] == pytest.approx(3.5)


# --- non-régression : autre échec (pas le motif) ne retry jamais ------------

def test_echec_hors_motif_materialisation_ne_retry_jamais(tmp_path, offline):
    calls = []

    def executor(payload, decision, context):
        calls.append(context["attempt"])
        return {"ok": False, "reason": "timeout claude -p", "output": "PARTIEL"}

    d = _driver(tmp_path, executor=executor)
    etape = d.order[0]
    state = _state(d)
    ok = d._run_llm(state, etape)

    assert ok is False
    entry = state["steps"][etape]
    assert entry["attempts"] == 1
    assert len(calls) == 1
    assert "materialize_retries" not in entry["detail"]


def test_driver_ne_spawn_pas_directement_apres_correctif():
    """Garde-fou : ce correctif n'introduit aucun spawn direct dans driver.py."""
    src = Path(__file__).resolve().parents[1].joinpath("driver.py").read_text(
        encoding="utf-8")
    for mot in ("subprocess", "Popen", "os.system", "anthropic"):
        assert mot not in src, f"mot interdit trouvé dans driver.py : {mot}"

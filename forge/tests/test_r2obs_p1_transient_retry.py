"""R2-OBS · P1 — retry BORNÉ sur échec TRANSITOIRE de l'exécuteur.

Défaut mesuré (runs kitten_clicker-20260824a / 24c / 25a) : `claude -p` rend
returncode=1 en ~2 s avec sortie ET stderr VIDES, et la campagne meurt à la
PREMIÈRE tentative (state.json du run 25a : `s0-contrat` BLOCKED, attempts=1,
reason « exécuteur LLM en échec à s0-contrat: claude -p returncode=1: » — rien
après les deux-points, la boîte noire complète).

Cette signature (processus mort, aucun octet produit, aucun octet d'erreur) est
INFRASTRUCTURELLE : le modèle n'a jamais été atteint (`process_state ==
PROCESS_EXIT_NONZERO`, cf. `run_real.classify_process_state`). La rejouer est
sans effet de bord côté produit — aucun artefact n'a été écrit, aucune sortie
n'existe à préserver.

Frontière FIGÉE ici : un échec qui porte du stderr OU de la sortie n'est PAS
transitoire (le worker a parlé — c'est un dossier causal produit, pas infra) et
garde le comportement HISTORIQUE (halt immédiat côté driver).

Le retry vit dans `run_real` (autour de `_claude_call_raw`), PAS dans le driver :
c'est un ré-essai d'INFRA sous la MÊME tentative de matérialisation. La sémantique
de `attempts` du marqueur `FORGE_DISPATCH:<etape>:<run_id>:<attempts>` reste donc
strictement inchangée (un retry transitoire ne consomme jamais un tour du budget
`materialize_attempts_max`), et le reçu `transient_retries` rend le ré-essai
LISIBLE au lieu d'invisible.
"""
from __future__ import annotations

import types

import pytest

from forge import run_real


# --- harnais minimal ---------------------------------------------------------

def _payload(etape="s9-build"):
    return types.SimpleNamespace(
        etape=etape, prompt="PROMPT CONTRACTUEL", model="haiku",
        provider="anthropic", allowed_tools=(),
    )


def _context(tmp_path, attempt=1, etape="s9-build"):
    return {
        "run_id": "r2obs-1",
        "project": "proj",
        "run_dir": str(tmp_path / "run"),
        "model_override": None,
        "dispatch_marker": f"FORGE_DISPATCH:{etape}:r2obs-1:{attempt}",
        "attempt": attempt,
        "premortem": [],
        "project_bible": "",
        "materialize_feedback": None,
    }


def _transient(rc=1):
    """Retour EXACT de `_claude_call_raw` sur la signature mesurée au run 25a."""
    return {"ok": False, "reason": f"claude -p returncode={rc}: ",
            "returncode": rc, "stderr_tail": "",
            "process_state": "PROCESS_EXIT_NONZERO",
            "duration_s": 2.0, "session_id": None, "model_used": None,
            "tokens_measured": None, "tools_used": None}


def _succes():
    return {"ok": True, "output": "SORTIE DU MODELE", "tokens": 10,
            "duration_s": 3.0, "cost_usd": 0.01,
            "cache_creation_tokens": 0, "cache_read_tokens": 0,
            "returncode": 0, "stderr_tail": "", "process_state": "MODEL_REACHED",
            "session_id": "sess", "model_used": ["claude-haiku"],
            "tokens_measured": None, "tools_used": None}


# --- (a) le prédicat, isolé --------------------------------------------------

def test_predicat_reconnait_la_signature_du_run_25a():
    assert run_real._is_transient_executor_failure(_transient()) is True


def test_predicat_rejette_un_echec_qui_porte_du_stderr():
    res = _transient()
    res["stderr_tail"] = "Error: ENOENT spawn claude"
    assert run_real._is_transient_executor_failure(res) is False


def test_predicat_rejette_un_echec_qui_porte_de_la_sortie():
    res = _transient()
    res["output"] = "le modele a parle puis le process est mort"
    assert run_real._is_transient_executor_failure(res) is False


def test_predicat_rejette_un_timeout():
    res = _transient()
    res["timeout"] = True
    assert run_real._is_transient_executor_failure(res) is False


def test_predicat_rejette_un_succes():
    assert run_real._is_transient_executor_failure(_succes()) is False


def test_budget_de_retry_est_une_constante_nommee_et_bornee():
    assert run_real.TRANSIENT_EXECUTOR_RETRIES_MAX == 2


# --- (b) deux échecs transitoires puis succès : l'étape passe ----------------

def test_deux_echecs_transitoires_puis_succes(tmp_path, monkeypatch):
    appels = []

    def fake(prompt, model, *, add_dir, tools=(), timeout_s=0):
        appels.append(model)
        return _transient() if len(appels) <= 2 else _succes()

    monkeypatch.setattr(run_real, "_claude_call_raw", fake)
    executor = run_real.claude_executor(tmp_path, {}, profile="micro")
    res = executor(_payload(), None, _context(tmp_path))

    assert res["ok"] is True
    assert len(appels) == 3  # 1 tentative + 2 retries bornés
    retries = res["transient_retries"]
    assert len(retries) == 2
    assert [r["try"] for r in retries] == [1, 2]
    assert retries[0]["returncode"] == 1
    assert retries[0]["process_state"] == "PROCESS_EXIT_NONZERO"
    assert retries[0]["stderr_tail"] == "(vide)"


# --- (c) échec NON transitoire : aucun retry, comportement historique -------

def test_echec_avec_stderr_ne_declenche_aucun_retry(tmp_path, monkeypatch):
    appels = []

    def fake(prompt, model, *, add_dir, tools=(), timeout_s=0):
        appels.append(model)
        res = _transient()
        res["stderr_tail"] = "Error: ENOENT"
        res["reason"] = "claude -p returncode=1: Error: ENOENT"
        return res

    monkeypatch.setattr(run_real, "_claude_call_raw", fake)
    executor = run_real.claude_executor(tmp_path, {}, profile="micro")
    res = executor(_payload(), None, _context(tmp_path))

    assert res["ok"] is False
    assert len(appels) == 1
    assert "transient_retries" not in res


# --- (d) budget épuisé : échec rendu, reçu COMPLET des 3 tentatives ---------

def test_trois_echecs_transitoires_epuisent_le_budget(tmp_path, monkeypatch):
    appels = []

    def fake(prompt, model, *, add_dir, tools=(), timeout_s=0):
        appels.append(model)
        return _transient()

    monkeypatch.setattr(run_real, "_claude_call_raw", fake)
    executor = run_real.claude_executor(tmp_path, {}, profile="micro")
    res = executor(_payload(), None, _context(tmp_path))

    assert res["ok"] is False
    assert len(appels) == 3  # jamais plus que 1 + TRANSIENT_EXECUTOR_RETRIES_MAX
    assert [r["try"] for r in res["transient_retries"]] == [1, 2, 3]


# --- (e) le reçu atteint state.json quand l'étape finit par PASSER ----------

def test_le_recu_de_retry_atteint_le_detail_du_driver(tmp_path, monkeypatch):
    """Le driver recopie `transient_retries` dans `entry["detail"]` — même
    patron additif que `markdown_check`/`materialize_retries` : une étape sans
    retry ne gagne aucune clé."""
    from forge.driver import ForgeDriver

    monkeypatch.setattr("forge.runtime.qwen_available", lambda *a, **k: False)

    def executor(payload, decision, context):
        return {"ok": True, "output": "OK", "tokens": 1, "duration_s": 1.0,
                "cost_usd": 0.0,
                "transient_retries": [{"try": 1, "returncode": 1,
                                       "process_state": "PROCESS_EXIT_NONZERO",
                                       "stderr_tail": "(vide)", "duration_s": 2.0}]}

    d = ForgeDriver(
        "proj-r2obs", "r1", run_dir=tmp_path / "run", profile="micro",
        key_file=tmp_path / "k.key", audit_path=tmp_path / "audit.jsonl",
        telemetry_path=tmp_path / "telemetry.jsonl",
        journal_path=tmp_path / "journal.jsonl",
        failure_events_path=tmp_path / "failure_events.jsonl",
        executor=executor,
    )
    etape = d.order[0]
    state = {"steps": {e: {"status": "PENDING", "attempts": 0, "detail": {}}
                       for e in d.order}}
    assert d._run_llm(state, etape) is True
    entry = state["steps"][etape]
    assert entry["attempts"] == 1  # le retry d'INFRA ne consomme pas un attempt
    assert entry["detail"]["transient_retries"][0]["returncode"] == 1


def test_une_etape_sans_retry_ne_gagne_aucune_cle(tmp_path, monkeypatch):
    from forge.driver import ForgeDriver

    monkeypatch.setattr("forge.runtime.qwen_available", lambda *a, **k: False)

    d = ForgeDriver(
        "proj-r2obs", "r1", run_dir=tmp_path / "run", profile="micro",
        key_file=tmp_path / "k.key", audit_path=tmp_path / "audit.jsonl",
        telemetry_path=tmp_path / "telemetry.jsonl",
        journal_path=tmp_path / "journal.jsonl",
        failure_events_path=tmp_path / "failure_events.jsonl",
        executor=lambda p, d_, c: {"ok": True, "output": "OK", "tokens": 1,
                                   "duration_s": 1.0, "cost_usd": 0.0},
    )
    etape = d.order[0]
    state = {"steps": {e: {"status": "PENDING", "attempts": 0, "detail": {}}
                       for e in d.order}}
    assert d._run_llm(state, etape) is True
    assert "transient_retries" not in state["steps"][etape]["detail"]

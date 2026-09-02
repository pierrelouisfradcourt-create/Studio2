"""Fiche 3 (sas ratifié Pierre 2026-08-30) — `check_artbible.mjs` doit être
exécuté PAR LE DRIVER, plus jamais par l'agent producteur.

Défaut mesuré aux runs kitten_clicker 8/9 (profil `full_godot_content`) :
`check_artbible.mjs` n'a JAMAIS été lancé par le driver — c'était l'agent
s2.5 lui-même qui l'exécutait via `Bash(node:*)` (aucun `artbible_check` dans
`state.json.steps["s2.5-artbible"].detail`), et le reçu atterrissait à un
emplacement DIFFÉRENT d'un run à l'autre (racine du run vs `evidence/`). Pire :
le `verdict: "OK"` du reçu ne couvrait QUE la couverture besoin<->requête,
alors que `resolution_stats` disait {ok:0, blocked:16} — piège de lecture.

Ce fichier couvre `ForgeDriver._run_llm_gated`/`_run_artbible_check` : AUCUN
vrai `node` requis — `artbible_check_runner` est entièrement injecté (même
patron d'injection que `art_response_runner`/`player_loop_runner`, cf.
`test_driver_materialize_retry.py` pour le patron générique de retry).
"""
from __future__ import annotations

from pathlib import Path

import pytest

from forge.driver import ForgeDriver


def _driver(tmp_path, *, executor=None, artbible_runner=None, profile="artbible",
            materialize_attempts_max=3):
    return ForgeDriver(
        "proj-artbible-gate", "r1", run_dir=tmp_path / "run", profile=profile,
        key_file=tmp_path / "k.key", audit_path=tmp_path / "audit.jsonl",
        telemetry_path=tmp_path / "telemetry.jsonl",
        journal_path=tmp_path / "journal.jsonl",
        failure_events_path=tmp_path / "failure_events.jsonl",
        executor=executor,
        artbible_check_runner=artbible_runner,
        materialize_attempts_max=materialize_attempts_max,
    )


def _state(d):
    return {"steps": {e: {"status": "PENDING", "attempts": 0, "detail": {}}
                      for e in d.order}}


def _ok_executor(payload, decision, context):
    return {"ok": True, "output": f"OUTPUT attempt={context['attempt']}",
            "tokens": 10, "duration_s": 0.1, "cost_usd": 0.001}


@pytest.fixture
def offline(monkeypatch):
    monkeypatch.setattr("forge.runtime.qwen_available", lambda *a, **k: False)


# --- (a) check OK : reçu écrit au chemin standard + detail complet + verte --

def test_check_ok_ecrit_receipt_standard_et_etape_verte(tmp_path, offline):
    calls = []

    def artbible_runner(art_bible_path, asset_requests_path, timeout=120):
        calls.append((Path(art_bible_path), Path(asset_requests_path), timeout))
        return {
            "status": "MEASURED", "pass": True, "verdict": "OK", "findings": [],
            "coverage": {"checked": True, "missing": [], "satisfied": ["kitten_common"]},
            "resolution_stats": {"ok": 2, "blocked": 0, "total": 2},
        }

    d = _driver(tmp_path, executor=_ok_executor, artbible_runner=artbible_runner)
    etape = d.order[0]
    assert etape == "s2.5-artbible"
    state = _state(d)

    ok = d._run_llm_gated(state, etape)

    assert ok is True
    entry = state["steps"][etape]
    assert entry["status"] == "OK"
    assert len(calls) == 1
    art_bible_arg, asset_requests_arg, timeout_arg = calls[0]
    assert art_bible_arg == d.run_dir / "art_bible.md"
    assert asset_requests_arg == d.run_dir / "asset_requests.json"
    assert timeout_arg == 120

    ab = entry["detail"]["artbible_check"]
    assert ab["verdict_structure"] == "PASS"
    assert ab["executed_by"] == "driver"
    assert ab["script_verdict"] == "OK"
    assert ab["resolution_stats"] == {"ok": 2, "blocked": 0, "total": 2}
    assert ab["resolution_note"].startswith("advisory")
    assert "artbible_check_retries" not in entry["detail"]

    expected_receipt = d.run_dir / "evidence" / f"check_artbible_{d.run_id}.json"
    assert ab["receipt_path"] == str(expected_receipt)
    assert expected_receipt.exists()
    import json
    on_disk = json.loads(expected_receipt.read_text(encoding="utf-8"))
    assert on_disk["verdict"] == "OK"


# --- (b) verdict_structure FAIL puis succès : re-spawn ARMÉ, même étape -----

def test_verdict_structure_fail_respawn_meme_etape_puis_succes(tmp_path, offline):
    llm_calls = []

    def executor(payload, decision, context):
        llm_calls.append(context["attempt"])
        return {"ok": True, "output": f"OUT-{len(llm_calls)}", "tokens": 1,
                "duration_s": 0.1, "cost_usd": 0.0}

    check_calls = []

    def artbible_runner(art_bible_path, asset_requests_path, timeout=120):
        check_calls.append(1)
        if len(check_calls) == 1:
            return {
                "status": "MEASURED", "pass": False, "verdict": "FAIL",
                "findings": ["frontmatter YAML absent ou illisible"],
                "coverage": {"checked": False, "missing": [], "satisfied": []},
                "resolution_stats": {"ok": 0, "blocked": 0, "total": 0},
            }
        return {
            "status": "MEASURED", "pass": True, "verdict": "OK", "findings": [],
            "coverage": {"checked": True, "missing": [], "satisfied": []},
            "resolution_stats": {"ok": 0, "blocked": 0, "total": 0},
        }

    d = _driver(tmp_path, executor=executor, artbible_runner=artbible_runner,
                materialize_attempts_max=3)
    etape = d.order[0]
    state = _state(d)

    ok = d._run_llm_gated(state, etape)

    assert ok is True
    entry = state["steps"][etape]
    assert entry["status"] == "OK"
    assert entry["attempts"] == 2  # re-spawn : le LLM a bien été rappelé
    assert len(llm_calls) == 2
    assert len(check_calls) == 2
    assert entry["detail"]["artbible_check"]["verdict_structure"] == "PASS"
    retries = entry["detail"]["artbible_check_retries"]
    assert len(retries) == 1
    assert retries[0]["verdict_structure"] == "FAIL"
    assert "frontmatter" in retries[0]["reason"]


# --- (c) FAIL persistant : budget épuisé -> HALTED --------------------------

def test_verdict_structure_fail_persistant_epuise_le_budget_et_halte(tmp_path, offline):
    def executor(payload, decision, context):
        return {"ok": True, "output": "OUT", "tokens": 1, "duration_s": 0.1,
                "cost_usd": 0.0}

    def artbible_runner(art_bible_path, asset_requests_path, timeout=120):
        return {
            "status": "MEASURED", "pass": False, "verdict": "FAIL",
            "findings": ["section manquante : rationale"],
            "coverage": {"checked": False, "missing": [], "satisfied": []},
            "resolution_stats": {"ok": 0, "blocked": 0, "total": 0},
        }

    d = _driver(tmp_path, executor=executor, artbible_runner=artbible_runner,
                materialize_attempts_max=2)
    etape = d.order[0]
    state = _state(d)

    ok = d._run_llm_gated(state, etape)

    assert ok is False
    entry = state["steps"][etape]
    assert entry["status"] == "BLOCKED"
    assert entry["attempts"] == 2
    assert state["run_status"] == "HALTED"
    assert "check_artbible refusé" in state["reason"]
    assert entry["detail"]["artbible_check"]["verdict_structure"] == "FAIL"
    assert len(entry["detail"]["artbible_check_retries"]) == 1


# --- (d) check inexécutable (crash/timeout) : NOT_MEASURED, fail-closed -----

def test_check_inexecutable_rend_not_measured_fail_closed(tmp_path, offline):
    def executor(payload, decision, context):
        return {"ok": True, "output": "OUT", "tokens": 1, "duration_s": 0.1,
                "cost_usd": 0.0}

    def artbible_runner(art_bible_path, asset_requests_path, timeout=120):
        raise TimeoutError("node introuvable sur ce poste")

    d = _driver(tmp_path, executor=executor, artbible_runner=artbible_runner,
                materialize_attempts_max=1)
    etape = d.order[0]
    state = _state(d)

    ok = d._run_llm_gated(state, etape)

    assert ok is False
    entry = state["steps"][etape]
    assert entry["status"] == "BLOCKED"
    ab = entry["detail"]["artbible_check"]
    assert ab["verdict_structure"] == "NOT_MEASURED"
    assert "node introuvable" in ab["reason"]
    assert state["run_status"] == "HALTED"


# --- (e) resolution_stats {ok:0} + structure PASS : VERTE, stats visibles --

def test_resolution_stats_zero_ok_avec_structure_pass_reste_verte(tmp_path, offline):
    def executor(payload, decision, context):
        return {"ok": True, "output": "OUT", "tokens": 1, "duration_s": 0.1,
                "cost_usd": 0.0}

    def artbible_runner(art_bible_path, asset_requests_path, timeout=120):
        return {
            "status": "MEASURED", "pass": True, "verdict": "OK", "findings": [],
            "coverage": {"checked": True, "missing": [], "satisfied": ["a"]},
            "resolution_stats": {"ok": 0, "blocked": 16, "total": 16},
        }

    d = _driver(tmp_path, executor=executor, artbible_runner=artbible_runner)
    etape = d.order[0]
    state = _state(d)

    ok = d._run_llm_gated(state, etape)

    assert ok is True
    entry = state["steps"][etape]
    assert entry["status"] == "OK"
    ab = entry["detail"]["artbible_check"]
    assert ab["verdict_structure"] == "PASS"
    # advisory, jamais gating -- mais VISIBLE, jamais masqué (piège de lecture run 9)
    assert ab["resolution_stats"] == {"ok": 0, "blocked": 16, "total": 16}


# --- (f) verdict BLOCKED (couverture) : structure valide -> PASS advisory --

def test_verdict_blocked_couverture_traite_comme_structure_pass(tmp_path, offline):
    """Décision documentée (à arbitrer par Pierre si désaccord) : `BLOCKED`
    (couverture besoin<->requête manquante) est une question de COUVERTURE,
    pas de FORME — `verdict_structure` ne gate QUE la forme (frontmatter/
    sections/JSON). La mission ne nomme que FAIL comme gatant ; BLOCKED reste
    visible (jamais masqué) mais ne bloque pas cette gate."""
    def executor(payload, decision, context):
        return {"ok": True, "output": "OUT", "tokens": 1, "duration_s": 0.1,
                "cost_usd": 0.0}

    def artbible_runner(art_bible_path, asset_requests_path, timeout=120):
        return {
            "status": "MEASURED", "pass": False, "verdict": "BLOCKED",
            "findings": [],
            "coverage": {"checked": True,
                         "missing": [{"id": "x", "entity_role": "prop"}],
                         "satisfied": []},
            "resolution_stats": {"ok": 0, "blocked": 0, "total": 0},
        }

    d = _driver(tmp_path, executor=executor, artbible_runner=artbible_runner)
    etape = d.order[0]
    state = _state(d)

    ok = d._run_llm_gated(state, etape)

    assert ok is True
    ab = state["steps"][etape]["detail"]["artbible_check"]
    assert ab["verdict_structure"] == "PASS"
    # Décision Pierre 2026-08-30 : le BLOCKED ne disparaît jamais dans un PASS nu.
    assert ab["coverage_status"] == "BLOCKED"
    assert ab["script_verdict"] == "BLOCKED"
    assert ab["coverage"]["missing"] == [{"id": "x", "entity_role": "prop"}]


# --- (g) round 2 (-r2) : même gate, suffixe _r2 sur le reçu ------------------
#
# `_run_artbible_check`/`_artbible_receipt_path` testés directement (pas via
# `_run_llm_gated`) : le round 2 n'est dispatchable que sous le profil réel de
# la boucle de complétion mutuelle (hors périmètre de ce test, cf. contrat
# s2.5-artbible §"ALIAS D'ETAPE") — la question couverte ici est UNIQUEMENT
# le nommage du reçu et le passage au gate, pas l'activation du contrat.

def test_round2_meme_gate_suffixe_r2_sur_le_recu(tmp_path, offline):
    def artbible_runner(art_bible_path, asset_requests_path, timeout=120):
        return {"status": "MEASURED", "pass": True, "verdict": "OK",
                "findings": [], "coverage": {"checked": True, "missing": [],
                                              "satisfied": []},
                "resolution_stats": {"ok": 0, "blocked": 0, "total": 0}}

    d = _driver(tmp_path, executor=None, artbible_runner=artbible_runner)
    etape = "s2.5-artbible-r2"

    gate = d._run_artbible_check(etape)

    assert gate["verdict_structure"] == "PASS"
    expected_receipt = d.run_dir / "evidence" / f"check_artbible_{d.run_id}_r2.json"
    assert gate["receipt_path"] == str(expected_receipt)
    assert expected_receipt.exists()
    base_receipt = d.run_dir / "evidence" / f"check_artbible_{d.run_id}.json"
    assert not base_receipt.exists()


# --- (h) non-régression : étapes hors s2.5-artbible n'exécutent JAMAIS le check

def test_etape_hors_s2_5_artbible_jamais_de_check(tmp_path, offline):
    calls = []

    def artbible_runner(*a, **k):
        calls.append(1)
        return {"status": "MEASURED", "verdict": "OK"}

    d = _driver(tmp_path, executor=_ok_executor, artbible_runner=artbible_runner,
                profile="micro")
    etape = d.order[0]
    assert etape != "s2.5-artbible"
    state = _state(d)

    ok = d._run_llm_gated(state, etape)

    assert ok is True
    assert calls == []
    assert "artbible_check" not in state["steps"][etape]["detail"]


def test_driver_ne_spawn_pas_directement_apres_fiche3():
    """Garde-fou : ce correctif n'introduit aucun spawn direct dans driver.py —
    le spawn Node vit dans oracle.py (`run_check_artbible`), même invariant que
    `test_driver_materialize_retry.py::test_driver_ne_spawn_pas_directement_apres_correctif`."""
    src = Path(__file__).resolve().parents[1].joinpath("driver.py").read_text(
        encoding="utf-8")
    for mot in ("subprocess", "Popen", "os.system", "anthropic"):
        assert mot not in src, f"mot interdit trouvé dans driver.py : {mot}"

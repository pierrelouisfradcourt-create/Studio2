# P2 2026-08-15 — verdict signé des profils PARTIELS (profils sans s12-verdict).
#
# Défaut mesuré (code review 2026-08-15) : tout profil sans s12 terminait DONE
# sans AUCUN agrégat signé — plus un seul verdict signé produit depuis
# driver_smoke_v6 (2026-08-09). Correctif : `scope` sur l'agrégat (défaut FULL,
# rétro-compatible), `verdict.partial.json` écrit par le driver au passage DONE,
# MÊME signature et MÊME re-vérification que la chaîne s12. Invariant central
# figé ici : un PARTIAL ne peut JAMAIS être interprété comme un FULL
# (decision plafonnée, is_clean_pass faux, garde de cohérence verify_run).
from __future__ import annotations

import json
import time

import pytest

from forge.driver import ForgeDriver
from forge.verdict import (
    build_aggregate_verdict,
    is_clean_pass,
    make_signed_receipt,
    signed_aggregate_record,
    AggregateVerdict,
)
from forge.verify_run import verify_run


def _skipped(oracle_id: str, run_id: str, key):
    return make_signed_receipt(
        oracle_id, run_id, "SKIPPED", {"reason": "hors profil"},
        ts=time.time(), key_file=key)


def _agg_partial(tmp_path, *, standard_status: str | None = None):
    key = tmp_path / "k.key"
    run_id = "r-partial"
    std = None
    if standard_status is not None:
        std = make_signed_receipt(
            "standard", run_id, standard_status, {"volets": "6/6"},
            ts=time.time(), key_file=key)
    return build_aggregate_verdict(
        "proj", run_id,
        _skipped("code", run_id, key),
        _skipped("archi", run_id, key),
        _skipped("wiremap", run_id, key),
        "aucun (profil sans red-team)",
        redteam_ran=False, standard=std or _skipped("standard", run_id, key),
        ts=time.time(), key_file=key, scope="PARTIAL",
    ), key


def test_partial_sans_aucun_oracle_est_blocked_honnete(tmp_path):
    agg, _ = _agg_partial(tmp_path)
    assert agg.scope == "PARTIAL"
    assert agg.software_verdict == "BLOCKED"
    assert agg.decision == "BLOCKED"
    assert any("aucun oracle exécuté" in f for f in agg.humangate_flags)


def test_partial_avec_oracle_reel_ok_mais_jamais_ready(tmp_path):
    # oracle_only : s10s réel OK — le périmètre est prouvé, jamais présenté FULL.
    agg, key = _agg_partial(tmp_path, standard_status="OK")
    assert agg.software_verdict == "OK"
    assert agg.decision == "HUMANGATE_READY_WITH_OBJECTION"   # plafonné, jamais READY
    record = signed_aggregate_record(agg, key_file=key)
    assert record["scope"] == "PARTIAL"
    assert is_clean_pass(record) is False


def test_partial_oracle_fail_reste_fail(tmp_path):
    agg, _ = _agg_partial(tmp_path, standard_status="FAIL")
    assert agg.software_verdict == "FAIL"
    assert agg.decision == "BLOCKED"


def test_scope_invalide_refuse(tmp_path):
    with pytest.raises(ValueError):
        _ = build_aggregate_verdict(
            "p", "r", None, None, None, "x", redteam_ran=False, scope="DEMI")


def test_verdict_historique_sans_scope_reste_full():
    # rétro-compat : champ absent = FULL, is_clean_pass inchangé.
    ancien = {"software_verdict": "OK", "decision": "HUMANGATE_READY",
              "humangate_flags": []}
    assert is_clean_pass(ancien) is True
    assert is_clean_pass({**ancien, "scope": "PARTIAL"}) is False


def test_verify_run_rejette_un_partial_presente_comme_full(tmp_path):
    # défense en profondeur : un producteur bogué qui signerait PARTIAL +
    # HUMANGATE_READY est attrapé par la garde de cohérence.
    agg, key = _agg_partial(tmp_path, standard_status="OK")
    truque = AggregateVerdict(**{**agg.__dict__, "decision": "HUMANGATE_READY"})
    record = signed_aggregate_record(truque, key_file=key)
    p = tmp_path / "verdict.partial.json"
    p.write_text(json.dumps(record, ensure_ascii=False, sort_keys=True),
                 encoding="utf-8")
    res = verify_run(p, key_file=key)
    assert res["hmac_ok"] is True                     # authentique…
    assert res["scope"] == "PARTIAL"
    assert any("PARTIAL" in pb for pb in res["coherence_problems"])  # …mais incohérent
    assert res["overall"] is False


def test_driver_ecrit_et_verifie_le_verdict_partiel(tmp_path, monkeypatch):
    run_dir = tmp_path / "run"
    run_dir.mkdir()
    drv = ForgeDriver(
        "proj", "r-story", run_dir=run_dir, profile="story_bible",
        key_file=tmp_path / "k.key", telemetry_path=tmp_path / "telemetry.jsonl",
    )
    state = {"steps": {}}
    drv._write_partial_verdict(state)
    out = run_dir / "verdict.partial.json"
    assert out.exists()
    record = json.loads(out.read_text(encoding="utf-8"))
    assert record["scope"] == "PARTIAL"
    assert record["decision"] != "HUMANGATE_READY"
    res = verify_run(out, key_file=tmp_path / "k.key")
    assert res["hmac_ok"] is True
    # idempotence : un second passage ne réécrit pas (reprise d'un DONE).
    before = out.read_bytes()
    drv._write_partial_verdict(state)
    assert out.read_bytes() == before
    # _final_report rapporte le verdict partiel, explicitement scopé.
    monkeypatch.setattr(drv, "_reference_guard_check", lambda phase: None)
    report = drv._final_report(state)
    assert report["verdict_path"] == str(out)
    assert report["scope"] == "PARTIAL"
    assert "PARTIEL" in report["reason"]


def test_profil_complet_inchange(tmp_path):
    # un profil AVEC s12 ne passe jamais par le verdict partiel (no-op).
    run_dir = tmp_path / "run"
    run_dir.mkdir()
    drv = ForgeDriver(
        "proj", "r-full", run_dir=run_dir, profile="full",
        key_file=tmp_path / "k.key", telemetry_path=tmp_path / "telemetry.jsonl",
    )
    drv._write_partial_verdict({"steps": {}})
    assert not (run_dir / "verdict.partial.json").exists()

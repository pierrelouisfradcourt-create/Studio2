"""Oracle du coût + effort réel dans le rapport de fin de run (`ForgeDriver._final_report`).

Ferme le trou « déclaré ≠ exécuté » : le rapport humain d'un run (imprimé par
run_real.py) n'exposait ni coût (connecteur 3, `studio_link.run_cost`) ni effort
réel (escalades/pool/tentatives, déjà présents dans `state.json`).

RÈGLE DURE testée explicitement : une télémétrie ABSENTE ou VIDE doit rendre
``cost.measured == False`` + une raison lisible — jamais un « 0 token » silencieux
qui affirmerait faussement qu'un run n'a rien consommé. Un `pool_attempts` à 0
reste, lui, un vrai zéro (jamais maquillé en "non mesuré").

Aucune clé existante du rapport n'est renommée ni supprimée (d'autres lecteurs en
dépendent) : uniquement des clés ajoutées (`cost`, `effort`). NO_CLAIM_ALLOWED.
"""
import json
import sys
from pathlib import Path

import pytest

from forge.driver import ForgeDriver


def _oracle_config(tmp_path, project, exit_code=0):
    cfg = tmp_path / "oracles_test.json"
    cfg.write_text(
        json.dumps({project: {
            "cwd": str(tmp_path),
            "command": [sys.executable, "-c", f"import sys; sys.exit({exit_code})"],
        }}),
        encoding="utf-8",
    )
    return cfg


class StubExecutor:
    def __call__(self, payload, decision, context):
        return {"ok": True, "output": f"artefact {payload.etape}"}


@pytest.fixture
def offline(monkeypatch):
    monkeypatch.setattr("forge.runtime.qwen_available", lambda *a, **k: False)


_EXISTING_KEYS = (
    "run_id", "project", "profile", "status", "evidence_verdict", "claim_verdict",
    "state_path", "software_verdict", "decision", "humangate_flags", "verdict_path", "reason",
)


def test_toutes_les_cles_existantes_restent_presentes(tmp_path, offline):
    """Garde-fou anti-régression : aucun lecteur existant du rapport ne casse."""
    run_dir = tmp_path / "run"
    kw = dict(
        run_dir=run_dir,
        oracle_config=_oracle_config(tmp_path, "proj"),
        key_file=tmp_path / "forge_test.key",
        audit_path=tmp_path / "audit.jsonl",
        telemetry_path=tmp_path / "telemetry.jsonl",
        builder_runs_path=tmp_path / "builder_runs.jsonl",
        journal_path=tmp_path / "journal.jsonl",
    )
    report = ForgeDriver("proj", "proj-1", profile="micro", executor=StubExecutor(), **kw).run()
    for key in _EXISTING_KEYS:
        assert key in report, f"clé existante disparue: {key}"


def _bare_done_state(run_id="proj-1", profile="micro"):
    """État DONE minimal (proche d'un vrai state.json) — sert à exercer
    `_final_report` directement, SANS passer par `.run()` (qui écrirait lui-même
    de la télémétrie réelle via `record_telemetry` et rendrait 'absent' impossible
    à observer)."""
    return {
        "run_id": run_id, "project": "proj", "profile": profile,
        "is_game": False, "escalations": 0, "pool_attempts": 0,
        "run_status": "DONE",
        "steps": {
            "s9-build": {"status": "OK", "attempts": 1},
            "s10a-oracle-code": {"status": "OK", "attempts": 1},
            "s12-verdict": {"status": "OK", "attempts": 1, "detail": {}},
        },
    }


def test_cost_non_mesure_quand_telemetrie_absente(tmp_path):
    """Fichier de télémétrie injecté qui N'EXISTE PAS -> measured=False, reason explicite,
    jamais un 0 silencieux."""
    missing_telemetry = tmp_path / "n_existe_pas" / "telemetry.jsonl"
    assert not missing_telemetry.exists()
    d = ForgeDriver("proj", "proj-1", run_dir=tmp_path / "run", profile="micro",
                    telemetry_path=missing_telemetry)
    report = d._final_report(_bare_done_state())
    assert report["cost"]["measured"] is False
    assert report["cost"]["total_tokens"] == 0
    assert "reason" in report["cost"]
    assert "non mesur" in report["cost"]["reason"].lower()


def test_ligne_de_telemetrie_tronquee_ne_casse_pas_le_rapport(tmp_path):
    """Une ligne JSONL tronquée ne doit JAMAIS emporter le rapport d'un run réussi.

    `studio_link._read` fait un `json.loads` NU par ligne, et `forge_telemetry.jsonl`
    est écrit en APPEND par des sous-processus concurrents que le driver tue par arbre
    au timeout (FIR-01) : une ligne coupée en deux est un cas réel. Tant que rien
    n'appelait `run_cost`, la fragilité dormait ; branchée dans `_final_report`, elle
    ferait planter le rapport d'un run PAR AILLEURS RÉUSSI. Le coût est accessoire au
    verdict — il dégrade en « non mesuré », il n'emporte rien.
    """
    torn = tmp_path / "telemetry.jsonl"
    torn.write_text(
        '{"run_id": "proj-1", "tokens": 10, "duration_s": 1}\n'
        '{"run_id": "proj-1", "tok',          # <- écriture interrompue
        encoding="utf-8",
    )
    d = ForgeDriver("proj", "proj-1", run_dir=tmp_path / "run", profile="micro",
                    telemetry_path=torn)
    report = d._final_report(_bare_done_state())          # ne doit pas lever
    assert report["status"] == "DONE"
    assert report["cost"]["measured"] is False
    assert "reason" in report["cost"]


def test_cost_non_mesure_quand_telemetrie_vide(tmp_path):
    """Fichier de télémétrie qui EXISTE mais est VIDE (0 octet) -> measured=False aussi
    (la commande de fabrication distingue explicitement 'absent OU vide')."""
    empty_telemetry = tmp_path / "telemetry_vide.jsonl"
    empty_telemetry.write_text("", encoding="utf-8")
    d = ForgeDriver("proj", "proj-1", run_dir=tmp_path / "run", profile="micro",
                    telemetry_path=empty_telemetry)
    report = d._final_report(_bare_done_state())
    assert report["cost"]["measured"] is False


def test_cost_mesure_avec_de_vrais_chiffres_quand_telemetrie_presente(tmp_path, offline):
    """Le driver écrit LUI-MÊME de la télémétrie réelle pour les étapes LLM du run
    (record_telemetry, connecteur 3 déjà câblé) : measured=True, chiffres réels."""
    run_dir = tmp_path / "run"
    telemetry_path = tmp_path / "telemetry.jsonl"
    kw = dict(
        run_dir=run_dir,
        oracle_config=_oracle_config(tmp_path, "proj"),
        key_file=tmp_path / "forge_test.key",
        audit_path=tmp_path / "audit.jsonl",
        telemetry_path=telemetry_path,
        builder_runs_path=tmp_path / "builder_runs.jsonl",
        journal_path=tmp_path / "journal.jsonl",
    )
    report = ForgeDriver("proj", "proj-1", profile="micro", executor=StubExecutor(), **kw).run()
    assert report["cost"]["measured"] is True
    assert "reason" not in report["cost"]
    assert report["cost"]["calls"] >= 1  # au moins s9-build (étape LLM du profil micro)


def test_effort_reflete_escalade_et_tentatives(tmp_path, offline):
    """Un oracle rouge -> escalade -> le rapport expose escalations>0, pool_attempts,
    et l'étape s9-build dans steps_with_retries (attempts>1)."""
    run_dir = tmp_path / "run"
    kw = dict(
        run_dir=run_dir,
        oracle_config=_oracle_config(tmp_path, "proj", exit_code=1),
        key_file=tmp_path / "forge_test.key",
        audit_path=tmp_path / "audit.jsonl",
        telemetry_path=tmp_path / "telemetry.jsonl",
        builder_runs_path=tmp_path / "builder_runs.jsonl",
        journal_path=tmp_path / "journal.jsonl",
    )
    report = ForgeDriver("proj", "proj-1", profile="micro", executor=StubExecutor(),
                         pool_size=1, **kw).run()
    assert report["software_verdict"] == "FAIL"
    assert report["effort"]["escalations"] >= 1
    assert report["effort"]["attempts_total"] >= 2
    assert report["effort"]["steps_with_retries"].get("s9-build", 0) > 1


def test_pool_non_mesure_quand_builder_runs_absent(tmp_path):
    """Fichier builder_runs injecté qui N'EXISTE PAS (ex. worktree neuf où
    EVIDENCE/bundles est gitignoré) -> pool.measured=False, reason explicite,
    JAMAIS un pool_saves=0 silencieux qui affirmerait faussement que le pool n'a
    rien sauvé."""
    missing_builder_runs = tmp_path / "n_existe_pas" / "builder_runs.jsonl"
    assert not missing_builder_runs.exists()
    d = ForgeDriver("proj", "proj-1", run_dir=tmp_path / "run", profile="micro",
                    builder_runs_path=missing_builder_runs)
    report = d._final_report(_bare_done_state())
    assert report["pool"]["measured"] is False
    assert report["pool"]["pool_saves"] == 0
    assert "reason" in report["pool"]
    assert "non mesur" in report["pool"]["reason"].lower()


def test_pool_non_mesure_quand_builder_runs_vide(tmp_path):
    """Fichier builder_runs qui EXISTE mais est VIDE (0 octet) -> measured=False aussi."""
    empty = tmp_path / "builder_runs_vide.jsonl"
    empty.write_text("", encoding="utf-8")
    d = ForgeDriver("proj", "proj-1", run_dir=tmp_path / "run", profile="micro",
                    builder_runs_path=empty)
    report = d._final_report(_bare_done_state())
    assert report["pool"]["measured"] is False


def test_ligne_de_builder_runs_tronquee_ne_casse_pas_le_rapport(tmp_path):
    """Une ligne JSONL tronquée dans forge_builder_runs.jsonl (même cause que la
    télémétrie : écriture concurrente tuée par arbre au timeout) ne doit JAMAIS
    emporter le rapport d'un run PAR AILLEURS RÉUSSI — le pool dégrade en « non
    mesuré », il n'emporte rien."""
    torn = tmp_path / "builder_runs.jsonl"
    torn.write_text(
        '{"task_id": "proj-1", "strategy": "pool_retry", "oracle_result": "OK", '
        '"cost_estimated": 0.01}\n'
        '{"task_id": "proj-1", "strat',          # <- écriture interrompue
        encoding="utf-8",
    )
    d = ForgeDriver("proj", "proj-1", run_dir=tmp_path / "run", profile="micro",
                    builder_runs_path=torn)
    report = d._final_report(_bare_done_state())          # ne doit pas lever
    assert report["status"] == "DONE"
    assert report["pool"]["measured"] is False
    assert "reason" in report["pool"]


def test_pool_mesure_avec_de_vraies_lignes_presentes(tmp_path):
    """Fichier builder_runs PRÉSENT avec de vraies tentatives -> measured=True,
    chiffres réels agrégés par `studio_link.pool_stats` (pool_saves, coût évité,
    répartition par builder)."""
    b = tmp_path / "builder_runs.jsonl"
    b.write_text(
        '{"task_id": "proj-1", "builder_id": "haiku", "strategy": "tier_attempt", '
        '"oracle_result": "FAIL", "cost_estimated": 0.01}\n'
        '{"task_id": "proj-1", "builder_id": "haiku", "strategy": "pool_retry", '
        '"oracle_result": "OK", "cost_estimated": 0.012}\n',
        encoding="utf-8",
    )
    d = ForgeDriver("proj", "proj-1", run_dir=tmp_path / "run", profile="micro",
                    builder_runs_path=b)
    report = d._final_report(_bare_done_state())
    assert report["pool"]["measured"] is True
    assert "reason" not in report["pool"]
    assert report["pool"]["attempts"] == 2
    assert report["pool"]["pool_saves"] == 1
    assert abs(report["pool"]["escalations_avoided_cost_usd"] - 0.012) < 1e-9


def test_pool_ne_casse_jamais_un_run_reussi_bout_en_bout(tmp_path, offline):
    """Bout-en-bout : un run RÉEL réussi (profil micro, oracle vert) écrit lui-même
    ses tentatives s9-build dans builder_runs_path (record_builder_run, déjà câblé) —
    le rapport final expose un `pool` mesuré, cohérent, et n'emporte JAMAIS le
    software_verdict du run (coût/pool restent accessoires)."""
    run_dir = tmp_path / "run"
    kw = dict(
        run_dir=run_dir,
        oracle_config=_oracle_config(tmp_path, "proj", exit_code=0),
        key_file=tmp_path / "forge_test.key",
        audit_path=tmp_path / "audit.jsonl",
        telemetry_path=tmp_path / "telemetry.jsonl",
        builder_runs_path=tmp_path / "n_existe_pas" / "builder_runs.jsonl",
        journal_path=tmp_path / "journal.jsonl",
    )
    report = ForgeDriver("proj", "proj-1", profile="micro", executor=StubExecutor(), **kw).run()
    assert report["software_verdict"] == "OK"
    # le driver a lui-même créé le fichier (record_builder_run, s9-build) : mesuré,
    # pas un artefact du chemin "absent au départ".
    assert report["pool"]["measured"] is True
    assert report["pool"]["attempts"] >= 1


def test_pool_attempts_zero_est_un_vrai_zero_pas_un_non_mesure(tmp_path, offline):
    """Un run qui passe du premier coup : pool_attempts=0 est un FAIT (aucune
    re-tentative), pas un 'non mesuré' — contrairement au coût, l'effort vient
    toujours de state.json (jamais d'un journal externe absent)."""
    run_dir = tmp_path / "run"
    kw = dict(
        run_dir=run_dir,
        oracle_config=_oracle_config(tmp_path, "proj", exit_code=0),
        key_file=tmp_path / "forge_test.key",
        audit_path=tmp_path / "audit.jsonl",
        telemetry_path=tmp_path / "telemetry.jsonl",
        builder_runs_path=tmp_path / "builder_runs.jsonl",
        journal_path=tmp_path / "journal.jsonl",
    )
    report = ForgeDriver("proj", "proj-1", profile="micro", executor=StubExecutor(), **kw).run()
    assert report["software_verdict"] == "OK"
    assert report["effort"]["pool_attempts"] == 0
    assert report["effort"]["escalations"] == 0
    assert report["effort"]["steps_with_retries"] == {}

"""Tests du routeur `observer.routing` (mission P2, 2026-08-08).

Chaque regle de la loi de routage porte un test POSITIF (le champ source qui la
fonde est present -> la destination attendue) et un test NEGATIF (le champ est
absent -> PAS cette destination, repli sur REVIEW_REQUIRED sauf autre regle
fondee). Un test verifie explicitement qu'aucune destination hors des 8
autorisees n'est jamais retournee, et qu'un fichier totalement inconnu tombe
sur REVIEW_REQUIRED — jamais une inference sur son nom.

Ces tests sont des fixtures SYNTHETIQUES (loi 1 de la mission) : ils prouvent
que la regle est implementee correctement. Le rejeu sur le run reel
(`driver_smoke_v4_20260807`, `pacman`, `breakout_v2`, `pacman-v6`) est fait a
part, en executant `scripts/observer/cli.py` — voir le rapport de mission,
jamais reconstruit ici a partir d'un fixture.
"""

from __future__ import annotations

from observer import routing


EMPTY_SETS = {
    "evidence_paths": set(),
    "signed_manifest_paths": set(),
    "reference_guard_paths": set(),
    "lesson_paths": set(),
    "humangate_flag_paths": set(),
    "product_roots": (),
}


def _route(path: str, **overrides):
    kwargs = dict(EMPTY_SETS)
    kwargs.update(overrides)
    return routing.route_file(path, **kwargs)


# --------------------------------------------------------------------------- #
# Destinations fermees
# --------------------------------------------------------------------------- #


def test_destinations_closed_set():
    assert routing.DESTINATIONS == {
        "PRODUCT",
        "EVIDENCE",
        "LESSON",
        "DECISION_INPUT",
        "KNOWLEDGE_INPUT",
        "NEXT_RUN_INPUT",
        "ARCHIVE",
        "REVIEW_REQUIRED",
    }


def test_route_file_never_returns_a_destination_outside_the_closed_set():
    cases = [
        _route("evidence/oracle_x.log", evidence_paths={"evidence/oracle_x.log"}),
        _route("context/s9.manifest.jsonl", signed_manifest_paths={"context/s9.manifest.jsonl"}),
        _route("reference_guard.jsonl", reference_guard_paths={"reference_guard.jsonl"}),
        _route("context/s9.manifest.jsonl", lesson_paths={"context/s9.manifest.jsonl"}),
        _route("verdict.json", humangate_flag_paths={"verdict.json"}),
        _route("wiremap_v2_frozen.json"),
        _route("reference_protected.yaml"),
        _route("src/logic.mjs", product_roots={"lab/forge_runs/x/src"}),
        _route("run.log"),
    ]
    for decision in cases:
        assert decision["destination"] in routing.DESTINATIONS


# --------------------------------------------------------------------------- #
# EVIDENCE — verdict.oracles.*.evidence_path
# --------------------------------------------------------------------------- #


def test_evidence_rule_positive_evidence_path():
    d = _route(
        "lab/forge_runs/x/evidence/oracle_x.log",
        evidence_paths={"lab/forge_runs/x/evidence/oracle_x.log"},
    )
    assert d["destination"] == routing.EVIDENCE
    assert "evidence_path" in d["field"]


def test_evidence_rule_negative_absent_from_evidence_paths():
    d = _route("lab/forge_runs/x/evidence/oracle_x.log", evidence_paths=set())
    assert d["destination"] != routing.EVIDENCE
    assert d["destination"] == routing.REVIEW_REQUIRED


# --------------------------------------------------------------------------- #
# EVIDENCE — manifeste HMAC verifie
# --------------------------------------------------------------------------- #


def test_evidence_rule_positive_signed_manifest():
    d = _route(
        "lab/forge_runs/x/context/s9-build.manifest.jsonl",
        signed_manifest_paths={"lab/forge_runs/x/context/s9-build.manifest.jsonl"},
    )
    assert d["destination"] == routing.EVIDENCE


def test_evidence_rule_negative_manifest_not_signed():
    d = _route("lab/forge_runs/x/context/s9-build.manifest.jsonl", signed_manifest_paths=set())
    assert d["destination"] == routing.REVIEW_REQUIRED


# --------------------------------------------------------------------------- #
# EVIDENCE — reference_guard.jsonl
# --------------------------------------------------------------------------- #


def test_evidence_rule_positive_reference_guard():
    d = _route(
        "lab/forge_runs/x/reference_guard.jsonl",
        reference_guard_paths={"lab/forge_runs/x/reference_guard.jsonl"},
    )
    assert d["destination"] == routing.EVIDENCE


def test_evidence_rule_negative_reference_guard_absent():
    d = _route("lab/forge_runs/x/reference_guard.jsonl", reference_guard_paths=set())
    assert d["destination"] == routing.REVIEW_REQUIRED


# --------------------------------------------------------------------------- #
# LESSON — manifest.reason.problem / root_cause
# --------------------------------------------------------------------------- #


def test_lesson_rule_positive():
    d = _route(
        "lab/forge_runs/x/context/s9-build.manifest.jsonl",
        lesson_paths={"lab/forge_runs/x/context/s9-build.manifest.jsonl"},
    )
    assert d["destination"] == routing.LESSON


def test_lesson_rule_negative_reason_empty():
    # reason={"action": "...", "status": "NOT_TRANSMITTED"} (mesure reelle sur
    # driver_smoke_v4) ne fournit ni problem ni root_cause -> pas de LESSON.
    d = _route("lab/forge_runs/x/context/s9-build.manifest.jsonl", lesson_paths=set())
    assert d["destination"] == routing.REVIEW_REQUIRED


# --------------------------------------------------------------------------- #
# DECISION_INPUT — verdict.humangate_flags
# --------------------------------------------------------------------------- #


def test_decision_input_rule_positive():
    d = _route("lab/forge_runs/x/verdict.json", humangate_flag_paths={"lab/forge_runs/x/verdict.json"})
    assert d["destination"] == routing.DECISION_INPUT


def test_decision_input_rule_negative_flags_empty():
    d = _route("lab/forge_runs/x/verdict.json", humangate_flag_paths=set())
    assert d["destination"] == routing.REVIEW_REQUIRED


# --------------------------------------------------------------------------- #
# NEXT_RUN_INPUT — wiremap*_frozen.json / reference_protected.yaml
# --------------------------------------------------------------------------- #


def test_next_run_input_rule_positive_wiremap_frozen():
    d = _route("lab/forge_runs/pacman/wiremap_v2_frozen.json")
    assert d["destination"] == routing.NEXT_RUN_INPUT


def test_next_run_input_rule_negative_wiremap_not_frozen():
    d = _route("lab/forge_runs/pacman/wiremap.json")
    assert d["destination"] == routing.REVIEW_REQUIRED


def test_next_run_input_rule_positive_reference_protected():
    d = _route("lab/forge_evidence/reference_protected.yaml")
    assert d["destination"] == routing.NEXT_RUN_INPUT


# --------------------------------------------------------------------------- #
# PRODUCT — sous le src_root observe (cwd du test.result node:test)
# --------------------------------------------------------------------------- #


def test_product_rule_positive_under_observed_cwd():
    d = _route(
        "lab/forge_runs/driver_smoke_v4_20260807/src/logic.mjs",
        product_roots={"lab/forge_runs/driver_smoke_v4_20260807/src"},
    )
    assert d["destination"] == routing.PRODUCT


def test_product_rule_negative_outside_observed_cwd():
    d = _route(
        "lab/forge_runs/driver_smoke_v4_20260807/oracles_override.json",
        product_roots={"lab/forge_runs/driver_smoke_v4_20260807/src"},
    )
    assert d["destination"] == routing.REVIEW_REQUIRED


# --------------------------------------------------------------------------- #
# REVIEW_REQUIRED — defaut obligatoire, cas explicitement attendus
# --------------------------------------------------------------------------- #


def test_unknown_file_falls_back_to_review_required():
    d = _route("lab/forge_runs/x/some_never_seen_file.bin")
    assert d["destination"] == routing.REVIEW_REQUIRED
    assert d["field"] is None


def test_expected_review_required_cases_from_the_mission():
    # Les 3 cas explicitement attendus par la mission : jamais classes ailleurs
    # par une inference sur le nom.
    for path in (
        "lab/forge_runs/driver_smoke_v4_20260807/artifacts/s9-build.txt",
        "lab/forge_runs/driver_smoke_v4_20260807/run.log",
        "lab/forge_runs/driver_smoke_v4_20260807/oracles_override.json",
    ):
        d = _route(path)
        assert d["destination"] == routing.REVIEW_REQUIRED


# --------------------------------------------------------------------------- #
# Priorite des regles — EVIDENCE avant PRODUCT quand les deux pourraient matcher
# --------------------------------------------------------------------------- #


def test_evidence_takes_priority_over_product_when_both_match():
    path = "lab/forge_runs/x/src/logic.mjs"
    d = _route(
        path,
        evidence_paths={path},
        product_roots={"lab/forge_runs/x/src"},
    )
    assert d["destination"] == routing.EVIDENCE


# --------------------------------------------------------------------------- #
# route_run_files — assemblage a partir d'evenements (dicts serialises)
# --------------------------------------------------------------------------- #


def _ev(kind, path, run_id="r1", proof="MECHANICAL", payload=None):
    return {
        "kind": kind,
        "run_id": run_id,
        "proof": proof,
        "source": {"path": path},
        "payload": payload or {},
    }


def test_route_run_files_integration_synthetic_run():
    repo_root = "C:/REPO"
    events = [
        _ev(
            "oracle.result",
            "lab/forge_runs/x/verdict.json",
            payload={"evidence_path": "C:/REPO/lab/forge_runs/x/evidence/oracle_x.log"},
        ),
        _ev("run.artifact_present", "lab/forge_runs/x/evidence/oracle_x.log"),
        _ev(
            "dispatch.context_manifest",
            "lab/forge_runs/x/context/s9.manifest.jsonl",
            proof="SIGNED",
        ),
        _ev(
            "verdict.signed",
            "lab/forge_runs/x/verdict.json",
            payload={"humangate_flags": ["archi non verifiee"]},
        ),
        _ev("test.result", "lab/forge_runs/x/evidence/oracle_x.log", payload={"cwd": "lab/forge_runs/x/src"}),
        _ev("run.artifact_present", "lab/forge_runs/x/src/logic.mjs"),
        _ev("run.artifact_present", "lab/forge_runs/x/run.log"),
        # evenement d'un AUTRE run : ne doit jamais apparaitre dans le routage de r1
        _ev("run.artifact_present", "lab/forge_runs/x/_run2/state.json", run_id="r2"),
    ]

    routed = routing.route_run_files(events, "r1", repo_root)
    by_path = {r["path"]: r for r in routed}

    assert by_path["lab/forge_runs/x/evidence/oracle_x.log"]["destination"] == routing.EVIDENCE
    assert by_path["lab/forge_runs/x/context/s9.manifest.jsonl"]["destination"] == routing.EVIDENCE
    assert by_path["lab/forge_runs/x/verdict.json"]["destination"] == routing.DECISION_INPUT
    assert by_path["lab/forge_runs/x/src/logic.mjs"]["destination"] == routing.PRODUCT
    assert by_path["lab/forge_runs/x/run.log"]["destination"] == routing.REVIEW_REQUIRED
    # 100% des fichiers presents dans les evenements de CE run recoivent une entree
    assert "lab/forge_runs/x/_run2/state.json" not in by_path
    for entry in routed:
        assert entry["destination"] in routing.DESTINATIONS


# --------------------------------------------------------------------------- #
# open_flags_of / archive_candidate
# --------------------------------------------------------------------------- #


def test_open_flags_of_reads_last_verdict_humangate_flags():
    run = {"verdict": {"humangate_flags": ["a", "b"]}}
    assert routing.open_flags_of(run) == ["a", "b"]


def test_open_flags_of_empty_when_no_verdict():
    assert routing.open_flags_of({"verdict": None}) == []


def test_archive_candidate_positive_terminal_no_reader_with_age():
    run = {"run_id": "r1", "run_status": "DONE"}
    proposal = routing.archive_candidate(run, has_reader=False, age_days=42.0)
    assert proposal is not None
    assert proposal["run_id"] == "r1"
    assert "42.0" in proposal["justification"] or proposal["preuve"]["age_days"] == 42.0


def test_archive_candidate_negative_when_has_reader():
    run = {"run_id": "r1", "run_status": "DONE"}
    assert routing.archive_candidate(run, has_reader=True, age_days=42.0) is None


def test_archive_candidate_negative_when_not_terminal():
    run = {"run_id": "r1", "run_status": "RUNNING"}
    assert routing.archive_candidate(run, has_reader=False, age_days=42.0) is None


def test_archive_candidate_negative_when_age_unknown():
    run = {"run_id": "r1", "run_status": "DONE"}
    assert routing.archive_candidate(run, has_reader=False, age_days=None) is None

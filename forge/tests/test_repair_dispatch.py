"""Tests du passage du runtime `repair_runtime` par la porte de dispatch.

Aucun modèle n'est appelé, aucune réparation n'est exécutée : on teste la TRACE, pas
le réparateur (celui-ci a ses propres tests Node, inchangés).
"""
from __future__ import annotations

import json
from pathlib import Path

import pytest

from forge import repair_dispatch
from forge.audit import EVENT_EXECUTED, EVENT_PREPARED, verify_audit_line

MESURE = {
    "STATUS": "REPARE",
    "WORKER": "qwen2.5-14b-instruct",
    "STEP": "s2-worldscan",
    "ORACLE": "check_worldscan",
    "PROBLEMS_BEFORE": 2,
    "PROBLEMS_AFTER": 0,
    "TOKENS": 70,
    "CYCLES": 1,
    "ALLOWED_FIELDS": ["games[0].retention_answer", "games[1].retention_answer"],
    "FIELDS_CHANGED": ["games[0].retention_answer", "games[1].retention_answer"],
    "REGRESSION": [],
}


def _lignes(path: Path) -> list[dict]:
    return [json.loads(x) for x in path.read_text(encoding="utf-8").splitlines() if x.strip()]


def test_le_runtime_est_resolu_par_le_registry_jamais_en_dur():
    """Le modèle vient de roles.yaml — jamais d'une constante du code."""
    modele, provider = repair_dispatch.resolve_runtime()
    assert modele == "qwen2.5-14b-instruct"
    assert provider == "lmstudio"
    src = Path(repair_dispatch.__file__).read_text(encoding="utf-8")
    assert "qwen" not in src.lower(), "aucun modèle en dur dans le module de dispatch"


def test_runtime_non_declare_rend_vide_jamais_une_valeur_devinee(tmp_path):
    vide = tmp_path / "roles.yaml"
    vide.write_text("version: '1.0'\nmodels: []\n", encoding="utf-8")
    assert repair_dispatch.resolve_runtime(vide) == ("", "")


def test_announce_ecrit_un_recu_SIGNE_verifiable(tmp_path):
    audit = tmp_path / "dispatch_audit.jsonl"
    assert repair_dispatch.announce("s2-worldscan", "jeu-run1", attempt=0, audit_path=audit)

    lignes = _lignes(audit)
    assert len(lignes) == 1
    rec = lignes[0]
    assert rec["event"] == EVENT_PREPARED
    assert rec["capability_role"] == "repair_runtime"
    assert rec["model"] == "qwen2.5-14b-instruct"
    assert rec["run_id"] == "jeu-run1"
    # C'est la MÊME signature que la porte : elle doit se vérifier avec le MÊME lecteur.
    assert verify_audit_line(rec) is True


def test_record_ecrit_le_recu_executed_ET_la_trace_repair_result(tmp_path):
    audit = tmp_path / "dispatch_audit.jsonl"
    resultats = tmp_path / "repair_results.jsonl"

    enreg = repair_dispatch.record(
        "s2-worldscan", "jeu-run1", MESURE, input_hash="aaa", output_hash="bbb",
        evidence_ref="EVIDENCE/runs/jeu", audit_path=audit, results_path=resultats,
    )

    rec = _lignes(audit)[0]
    assert rec["event"] == EVENT_EXECUTED
    assert verify_audit_line(rec) is True

    assert enreg == _lignes(resultats)[0]
    for champ in ("run_id", "runtime_id", "root_problem_id", "capability_id", "mutation_id",
                  "input_hash", "output_hash", "allowed_fields", "written_fields",
                  "oracle_before", "oracle_after", "evidence_ref"):
        assert champ in enreg, f"champ de contrat manquant : {champ}"
    assert enreg["runtime_id"] == "repair_runtime"
    assert enreg["capability_id"] == "targeted_field_repair"
    # root_problem et mutation viennent du CATALOGUE, pas d'une constante recopiée
    assert enreg["mutation_id"] == "REPAIR-LOOP-V1"
    assert enreg["root_problem_id"] == "REPAIR_NON_CONVERGENCE"
    assert enreg["entrypoint"] == "forge/repair_step.mjs"


def test_les_verdicts_oracle_sont_DERIVES_des_compteurs_jamais_declares():
    """0 problème => OK. Le réparateur n'a pas le droit de dire qu'il a réussi."""
    ok = repair_dispatch.build_result("s2-worldscan", "r", MESURE,
                                      input_hash="a", output_hash="b", evidence_ref="")
    assert (ok["oracle_before"], ok["oracle_after"]) == ("FAIL", "OK")

    echec = repair_dispatch.build_result(
        "s2-worldscan", "r", {**MESURE, "PROBLEMS_AFTER": 2, "STATUS": "ESCALADE"},
        input_hash="a", output_hash="b", evidence_ref="")
    assert (echec["oracle_before"], echec["oracle_after"]) == ("FAIL", "FAIL")

    inconnu = repair_dispatch.build_result(
        "s2-worldscan", "r", {}, input_hash="", output_hash="", evidence_ref="")
    assert (inconnu["oracle_before"], inconnu["oracle_after"]) == ("", ""), \
        "sans compteur, on ne devine pas un verdict"


def test_allowed_fields_et_written_fields_sont_DISTINCTS():
    """« 2 écrits » ne doit pas se confondre avec « 2 écrits sur 5 permis »."""
    r = repair_dispatch.build_result(
        "s2-worldscan", "r",
        {**MESURE, "FIELDS_CHANGED": ["games[0].retention_answer"]},
        input_hash="a", output_hash="b", evidence_ref="")
    assert len(r["allowed_fields"]) == 2
    assert len(r["written_fields"]) == 1


def test_quality_not_proven_est_constant():
    for mesure in (MESURE, {**MESURE, "PROBLEMS_AFTER": 0, "STATUS": "OK_SANS_REPARATION"}):
        r = repair_dispatch.build_result("s2-worldscan", "r", mesure,
                                         input_hash="a", output_hash="b", evidence_ref="")
        assert r["quality_not_proven"] is True


def test_aucun_score_aucune_recompense_aucun_classement():
    r = repair_dispatch.build_result("s2-worldscan", "r", MESURE,
                                     input_hash="a", output_hash="b", evidence_ref="")
    brut = json.dumps(r).lower()
    for interdit in repair_dispatch.FORBIDDEN_KEYS:
        assert f'"{interdit}' not in brut, f"champ interdit dans la trace : {interdit}"


def test_capacites_embarquees_tracees_depuis_le_bloc_QUALITE():
    """Alignement 2026-08-04 : les deux détecteurs tournent DÉJÀ dans phaseQualite.
    Leur exécution doit laisser une empreinte, sinon elle est indiscernable de rien."""
    r = repair_dispatch.build_result("s2-worldscan", "r", {**MESURE, "QUALITE": {
        "SEMANTIC_SIGNAL_BEFORE": "FAIL", "SEMANTIC_SIGNAL_AFTER": "PASS",
        "SIGNAUX_AVANT": {"DISCRIMINANCE": 2}, "SIGNAUX_APRES": {"DISCRIMINANCE": 0},
        "CROSS_FIELD_BEFORE": "PASS", "CROSS_FIELD_AFTER": "PASS",
    }}, input_hash="a", output_hash="b", evidence_ref="")
    caps = {x["capability_id"]: x for x in r["embedded_capabilities"]}
    assert set(caps) == {"duplicate_content_detection", "cross_field_copy_detection"}
    assert all(x["runtime_role"] == "deterministic" for x in caps.values()), \
        "la detection est du code deterministe — aucun modele n intervient"
    assert caps["duplicate_content_detection"]["signals_before"] == {"DISCRIMINANCE": 2}
    assert caps["duplicate_content_detection"]["verdict_after"] == "PASS"


def test_pas_de_phase_qualite_rend_une_liste_VIDE_jamais_un_rien_detecte():
    """« ne pas détecter » et « ne pas s'exécuter » sont deux faits différents."""
    r = repair_dispatch.build_result("s2-worldscan", "r", MESURE,
                                     input_hash="a", output_hash="b", evidence_ref="")
    assert r["embedded_capabilities"] == []


def test_file_sha256_sur_fichier_absent_rend_vide_sans_lever(tmp_path):
    assert repair_dispatch.file_sha256(tmp_path / "nexiste.pas") == ""
    f = tmp_path / "a.json"
    f.write_bytes(b"{}")
    assert len(repair_dispatch.file_sha256(f)) == 64


@pytest.mark.parametrize("appel", [
    lambda p: repair_dispatch.announce("s2-worldscan", "r", audit_path=p / "nope" / "x.jsonl"),
    lambda p: repair_dispatch.record("s2-worldscan", "r", MESURE, input_hash="", output_hash="",
                                     audit_path=p / "nope" / "x.jsonl",
                                     results_path=p / "ok" / "r.jsonl"),
])
def test_la_trace_ne_leve_JAMAIS(tmp_path, appel):
    """Une preuve n'est pas un gate : elle dégrade, elle ne casse pas la réparation."""
    appel(tmp_path)  # ne doit pas lever


def test_le_module_ne_repare_rien():
    """Garde d'architecture : aucune logique de réparation n'a migré ici."""
    src = Path(repair_dispatch.__file__).read_text(encoding="utf-8")
    code = "\n".join(l for l in src.splitlines() if not l.strip().startswith("#"))
    for interdit in ("fetch(", "localhost", "temperature", "FIELD_TO_REPAIR", "subprocess"):
        assert interdit not in code, f"« {interdit} » n'a rien à faire dans la trace"

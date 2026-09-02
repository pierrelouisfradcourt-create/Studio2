"""Oracle du reçu mutation signé (P0.2) — la preuve que I1/I2 sont fermés.

Un reçu mutation lie le verdict du gate mutation (`check_mutation_gate`, jamais
réimplémenté) au run (run_id), au CODE testé (sha256 des fichiers logiques ET
des fichiers de tests) et au triage (sha256 de mutation_triage.json). Toute
divergence à la vérification => refus. NO_CLAIM_ALLOWED.
"""
import json
from dataclasses import asdict
from pathlib import Path

from forge.mutation_proof import (
    emit_mutation_receipt,
    logic_files_from_wiremap,
    run_mutation_for_game,
    verify_mutation_receipt,
)


def _game(tmp_path):
    g = tmp_path / "game"
    g.mkdir()
    (g / "logic.mjs").write_text("export const ok = 1 >= 0;\n", encoding="utf-8")
    (g / "logic.test.mjs").write_text("// tests\n", encoding="utf-8")
    return g


def _all_killed(source_path, test_argv, *, cwd, **kw):
    return {"total": 4, "killed": 4, "survived": 0, "score": 1.0, "survivors": []}


def _one_survivor(source_path, test_argv, *, cwd, **kw):
    return {"total": 4, "killed": 3, "survived": 1, "score": 0.75,
            "survivors": [{"name": "ge->gt", "line": 1}]}


def _baseline_ok(test_argv, cwd):
    return True


def _emit(tmp_path, g, runner=_all_killed, run_id="run-1", baseline=_baseline_ok):
    result = run_mutation_for_game(g, ["logic.mjs"], runner=runner,
                                   baseline_runner=baseline)
    return emit_mutation_receipt(run_id, g, ["logic.mjs"], result,
                                 key_file=tmp_path / "key",
                                 evidence_dir=tmp_path / "evidence")


# --- cas normal : preuve valide -------------------------------------------------

def test_emission_puis_verification_ok(tmp_path):
    g = _game(tmp_path)
    sr = _emit(tmp_path, g)
    assert sr.receipt.status == "OK"
    assert sr.receipt.detail["code_sha256"]["logic.mjs"]
    # les fichiers de TESTS sont aussi scellés (affaiblir la suite après la
    # preuve casserait la fraîcheur)
    assert "logic.test.mjs" in sr.receipt.detail["code_sha256"]
    check = verify_mutation_receipt(asdict(sr.receipt), sr.signature, "run-1", g,
                                    key_file=tmp_path / "key")
    assert check["passed"], check["raisons"]


# --- chaque refus exigé par P0.2 -------------------------------------------------

def test_refus_preuve_absente(tmp_path):
    g = _game(tmp_path)
    check = verify_mutation_receipt(None, "", "run-1", g, key_file=tmp_path / "key")
    assert not check["passed"]


def test_refus_run_id_incoherent(tmp_path):
    g = _game(tmp_path)
    sr = _emit(tmp_path, g)
    check = verify_mutation_receipt(asdict(sr.receipt), sr.signature, "AUTRE-run", g,
                                    key_file=tmp_path / "key")
    assert not check["passed"]
    assert any("run_id" in r for r in check["raisons"])


def test_refus_signature_alteree(tmp_path):
    g = _game(tmp_path)
    sr = _emit(tmp_path, g)
    d = asdict(sr.receipt)
    d["status"] = "OK"
    d["detail"] = dict(d["detail"], total=999)  # falsification du contenu
    check = verify_mutation_receipt(d, sr.signature, "run-1", g,
                                    key_file=tmp_path / "key")
    assert not check["passed"]
    assert any("provenance" in r for r in check["raisons"])


def test_refus_hash_code_divergent(tmp_path):
    g = _game(tmp_path)
    sr = _emit(tmp_path, g)
    (g / "logic.mjs").write_text("export const ok = 1 > 0;\n", encoding="utf-8")
    check = verify_mutation_receipt(asdict(sr.receipt), sr.signature, "run-1", g,
                                    key_file=tmp_path / "key")
    assert not check["passed"]
    assert any("divergent" in r for r in check["raisons"])


def test_refus_tests_affaiblis_apres_preuve(tmp_path):
    """Affaiblir la SUITE après la preuve = preuve périmée (même sceau que le code)."""
    g = _game(tmp_path)
    sr = _emit(tmp_path, g)
    (g / "logic.test.mjs").write_text("// assertions supprimées\n", encoding="utf-8")
    check = verify_mutation_receipt(asdict(sr.receipt), sr.signature, "run-1", g,
                                    key_file=tmp_path / "key")
    assert not check["passed"]


def test_refus_triage_modifie_apres_preuve(tmp_path):
    """Un triage écrit/modifié APRÈS la preuve (justification a posteriori) = refus."""
    g = _game(tmp_path)
    sr = _emit(tmp_path, g)
    (g / "mutation_triage.json").write_text(
        json.dumps([{"name": "ge->gt", "line": 1, "justification": "a posteriori"}]),
        encoding="utf-8")
    check = verify_mutation_receipt(asdict(sr.receipt), sr.signature, "run-1", g,
                                    key_file=tmp_path / "key")
    assert not check["passed"]
    assert any("triage" in r for r in check["raisons"])


def test_survivant_non_justifie_donne_un_recu_fail(tmp_path):
    """Le juge reste check_mutation_gate : survivant non trié => reçu FAIL, jamais OK."""
    g = _game(tmp_path)
    sr = _emit(tmp_path, g, runner=_one_survivor)
    assert sr.receipt.status == "FAIL"
    check = verify_mutation_receipt(asdict(sr.receipt), sr.signature, "run-1", g,
                                    key_file=tmp_path / "key")
    assert not check["passed"]  # un reçu non-OK ne vaut jamais preuve verte


def test_total_zero_jamais_vert(tmp_path):
    """total==0 (rien muté) => jamais un vert (doctrine check_mutation_gate)."""
    g = _game(tmp_path)

    def _empty(source_path, test_argv, *, cwd, **kw):
        return {"total": 0, "killed": 0, "survived": 0, "score": 1.0, "survivors": []}

    sr = _emit(tmp_path, g, runner=_empty)
    assert sr.receipt.status == "FAIL"


# --- P0.3 : baseline verte obligatoire ---------------------------------------------

def test_baseline_rouge_recu_fail_jamais_vert(tmp_path):
    """Une suite déjà ROUGE sur le code NON muté « tue » tout mutant
    artificiellement (returncode != 0 pour tous). 100% de score avec une suite
    cassée = preuve invalide => reçu FAIL, jamais OK."""
    g = _game(tmp_path)
    sr = _emit(tmp_path, g, baseline=lambda argv, cwd: False)
    assert sr.receipt.status == "FAIL"
    assert sr.receipt.detail["baseline_ok"] is False
    check = verify_mutation_receipt(asdict(sr.receipt), sr.signature, "run-1", g,
                                    key_file=tmp_path / "key")
    assert not check["passed"]


def test_refus_recu_sans_baseline(tmp_path):
    """Un reçu sans le champ baseline_ok (format antérieur / résultat forgé à la
    main) n'est jamais accepté comme preuve verte (hypothèse inconnue = refus)."""
    g = _game(tmp_path)
    result = {"total": 4, "killed": 4, "survived": 0, "survivors": []}  # sans baseline
    sr = emit_mutation_receipt("run-1", g, ["logic.mjs"], result,
                               key_file=tmp_path / "key",
                               evidence_dir=tmp_path / "evidence")
    assert sr.receipt.status == "FAIL"  # dès l'émission : pas de baseline => pas de vert


# --- durcissements post-revue adversariale (2026-07-11) ---------------------------

def test_refus_commande_de_test_indirecte_sans_fichier_scelle(tmp_path):
    """`npm test`/`pytest` ne nomment aucun fichier => la suite n'est pas scellée
    => la fraîcheur n'est pas prouvable => refus (jamais un vert silencieux)."""
    g = _game(tmp_path)
    result = run_mutation_for_game(g, ["logic.mjs"], test_argv=["npm", "test"],
                                   runner=_all_killed, baseline_runner=_baseline_ok)
    sr = emit_mutation_receipt("run-1", g, ["logic.mjs"], result,
                               key_file=tmp_path / "key",
                               evidence_dir=tmp_path / "evidence")
    check = verify_mutation_receipt(asdict(sr.receipt), sr.signature, "run-1", g,
                                    key_file=tmp_path / "key")
    assert not check["passed"]
    assert any("scellé" in r or "scelle" in r for r in check["raisons"])


def test_refus_empreinte_vide_fichier_illisible(tmp_path):
    """Un fichier logique déclaré mais ABSENT est scellé '' à l'émission ; ''==''
    à la vérification ne doit JAMAIS passer (hypothèse inconnue = refus)."""
    g = _game(tmp_path)
    result = run_mutation_for_game(g, ["fantome.mjs"], runner=_all_killed,
                                   baseline_runner=_baseline_ok)
    sr = emit_mutation_receipt("run-1", g, ["fantome.mjs"], result,
                               key_file=tmp_path / "key",
                               evidence_dir=tmp_path / "evidence")
    check = verify_mutation_receipt(asdict(sr.receipt), sr.signature, "run-1", g,
                                    key_file=tmp_path / "key")
    assert not check["passed"]
    assert any("fantome.mjs" in r for r in check["raisons"])


def test_scelle_le_harnais_e2e_quand_present(tmp_path):
    """run-oracle.mjs et e2e.mjs font partie du code jugé : présents, ils sont
    scellés — les échanger après la preuve invalide la preuve."""
    g = _game(tmp_path)
    (g / "run-oracle.mjs").write_text("import('e2e.mjs');\n", encoding="utf-8")
    (g / "e2e.mjs").write_text("// harnais\n", encoding="utf-8")
    sr = _emit(tmp_path, g)
    sealed = sr.receipt.detail["code_sha256"]
    assert "run-oracle.mjs" in sealed
    assert "e2e.mjs" in sealed
    (g / "e2e.mjs").write_text("// harnais remplacé\n", encoding="utf-8")
    check = verify_mutation_receipt(asdict(sr.receipt), sr.signature, "run-1", g,
                                    key_file=tmp_path / "key")
    assert not check["passed"]


# --- sélection des fichiers logiques (formule skill.md, portée en code) -----------

def test_logic_files_depuis_wiremap_exclut_tests_et_non_mjs():
    wiremap = {"features": [
        {"feature": "R1", "fichiers": ["game.mjs", "logic.test.mjs"]},
        {"feature": "R2", "fichiers": ["level.mjs", "style.css", "game.mjs"]},
    ]}
    assert logic_files_from_wiremap(wiremap) == ["game.mjs", "level.mjs"]

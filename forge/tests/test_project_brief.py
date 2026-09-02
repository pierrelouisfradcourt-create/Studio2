"""FORGE_PROJECT_INPUT_V0 (ratifié Pierre 2026-08-29) : `check_project_brief`,
oracle déterministe non-LLM de `EVIDENCE/briefs/<projet>/project_brief.yaml` —
l'entrée UNIQUE d'un projet (hiérarchie : spec normative -> Brief -> s0 -> charter).

Même doctrine que `check_charter` (docstring imité) : FAIL honnête avec raisons,
jamais d'exception. Aucun LLM, aucun subprocess claude dans ce fichier.
"""
import copy

import yaml

import forge.run_real as run_real
from forge.static_oracles import check_project_brief


def _valid_brief() -> dict:
    return {
        "projet": "kitten_clicker",
        "intention": "apprendre a calibrer un clicker minimal, boucle courte",
        "contraintes": {
            "normative_refs": [
                {"spec": "FORGE_DESIGN_FREEDOM_SPEC_V0", "rules": ["N1", "N2", "N6"]},
            ],
            "project_specific": {
                "techniques": ["web/HTML, aucune dépendance externe"],
                "experimentales": ["boucle de complétion mutuelle art<->gm"],
            },
        },
        "cible": "web/HTML",
        "references_autorisees": [
            {"ref": "Cookie Clicker", "source": "Pierre 2026-08-29"},
        ],
        "criteres_sortie": ["jeu jouable 2 minutes sans crash"],
        "libertes_deleguees": ["choix des couleurs", "nommage des entités"],
        "provenance": {"projet": "Pierre 2026-08-29", "intention": "Pierre 2026-08-29"},
    }


# --- brief valide ---------------------------------------------------------------

def test_valid_brief_passes():
    rep = check_project_brief(_valid_brief())
    assert rep["passed"] is True
    assert rep["raisons"] == []


# --- entrée malformée : FAIL honnête, jamais d'exception -------------------------

def test_malformed_not_a_mapping_fails_honestly():
    rep = check_project_brief(["not", "a", "dict"])
    assert rep["passed"] is False
    assert any("n'est pas un mapping" in r for r in rep["raisons"])


# --- champs requis absents/vides : FAIL nommé -------------------------------------

def test_missing_projet_fails():
    brief = _valid_brief()
    del brief["projet"]
    rep = check_project_brief(brief)
    assert rep["passed"] is False
    assert any("'projet' absent ou vide" in r for r in rep["raisons"])


def test_empty_intention_fails():
    brief = _valid_brief()
    brief["intention"] = "   "
    rep = check_project_brief(brief)
    assert rep["passed"] is False
    assert any("'intention' absent ou vide" in r for r in rep["raisons"])


def test_missing_cible_fails():
    brief = _valid_brief()
    del brief["cible"]
    rep = check_project_brief(brief)
    assert rep["passed"] is False
    assert any("'cible' absent ou vide" in r for r in rep["raisons"])


def test_missing_contraintes_fails():
    brief = _valid_brief()
    del brief["contraintes"]
    rep = check_project_brief(brief)
    assert rep["passed"] is False
    assert any("'contraintes' absent ou vide" in r for r in rep["raisons"])


def test_empty_contraintes_fails():
    brief = _valid_brief()
    brief["contraintes"] = {}
    rep = check_project_brief(brief)
    assert rep["passed"] is False
    assert any("'contraintes' absent ou vide" in r for r in rep["raisons"])


def test_missing_provenance_fails():
    brief = _valid_brief()
    del brief["provenance"]
    rep = check_project_brief(brief)
    assert rep["passed"] is False
    assert any("'provenance' absent ou vide" in r for r in rep["raisons"])


def test_missing_criteres_sortie_fails():
    brief = _valid_brief()
    del brief["criteres_sortie"]
    rep = check_project_brief(brief)
    assert rep["passed"] is False
    assert any("'criteres_sortie' absent ou vide" in r for r in rep["raisons"])


def test_empty_criteres_sortie_fails():
    brief = _valid_brief()
    brief["criteres_sortie"] = []
    rep = check_project_brief(brief)
    assert rep["passed"] is False
    assert any("'criteres_sortie' absent ou vide" in r for r in rep["raisons"])


def test_missing_libertes_deleguees_fails():
    brief = _valid_brief()
    del brief["libertes_deleguees"]
    rep = check_project_brief(brief)
    assert rep["passed"] is False
    assert any("'libertes_deleguees' absent ou vide" in r for r in rep["raisons"])


def test_empty_libertes_deleguees_fails():
    brief = _valid_brief()
    brief["libertes_deleguees"] = []
    rep = check_project_brief(brief)
    assert rep["passed"] is False
    assert any("'libertes_deleguees' absent ou vide" in r for r in rep["raisons"])


def test_missing_references_autorisees_fails():
    brief = _valid_brief()
    del brief["references_autorisees"]
    rep = check_project_brief(brief)
    assert rep["passed"] is False
    assert any("'references_autorisees' absent ou n'est pas une liste" in r
               for r in rep["raisons"])


# --- contraintes : clé venue de nulle part ----------------------------------------

def test_unknown_key_in_contraintes_fails():
    brief = _valid_brief()
    brief["contraintes"]["budget_max"] = 42
    rep = check_project_brief(brief)
    assert rep["passed"] is False
    assert any("venue de nulle part" in r for r in rep["raisons"])


def test_unknown_key_in_contraintes_names_the_key():
    brief = _valid_brief()
    brief["contraintes"]["mystere"] = ["x"]
    rep = check_project_brief(brief)
    assert rep["passed"] is False
    assert any("mystere" in r and "venue de nulle part" in r for r in rep["raisons"])


# --- normative_refs : spec inconnue, règle mal formée -----------------------------

def test_unknown_normative_spec_fails():
    brief = _valid_brief()
    brief["contraintes"]["normative_refs"] = [
        {"spec": "SPEC_INEXISTANTE_V9", "rules": ["N1"]},
    ]
    rep = check_project_brief(brief)
    assert rep["passed"] is False
    assert any("hors du registre connu" in r for r in rep["raisons"])


def test_malformed_rule_id_fails():
    brief = _valid_brief()
    brief["contraintes"]["normative_refs"] = [
        {"spec": "FORGE_DESIGN_FREEDOM_SPEC_V0", "rules": ["regle-2"]},
    ]
    rep = check_project_brief(brief)
    assert rep["passed"] is False
    assert any("mal formé" in r for r in rep["raisons"])


def test_empty_rules_fails():
    brief = _valid_brief()
    brief["contraintes"]["normative_refs"] = [
        {"spec": "FORGE_DESIGN_FREEDOM_SPEC_V0", "rules": []},
    ]
    rep = check_project_brief(brief)
    assert rep["passed"] is False
    assert any("'contraintes.normative_refs[0].rules' absent ou vide" in r
               for r in rep["raisons"])


def test_missing_project_specific_sub_lists_fails():
    brief = _valid_brief()
    brief["contraintes"]["project_specific"] = {"techniques": ["x"]}
    rep = check_project_brief(brief)
    assert rep["passed"] is False
    assert any("project_specific.experimentales' absent" in r for r in rep["raisons"])


# --- references_autorisees : source absente, fog explicite -----------------------

def test_reference_without_source_fails():
    brief = _valid_brief()
    brief["references_autorisees"] = [{"ref": "Cookie Clicker"}]
    rep = check_project_brief(brief)
    assert rep["passed"] is False
    assert any("references_autorisees[0].source' absent ou vide" in r
               for r in rep["raisons"])


def test_reference_without_ref_fails():
    brief = _valid_brief()
    brief["references_autorisees"] = [{"source": "Pierre 2026-08-29"}]
    rep = check_project_brief(brief)
    assert rep["passed"] is False
    assert any("references_autorisees[0].ref' absent ou vide" in r
               for r in rep["raisons"])


def test_empty_references_without_fog_fails():
    brief = _valid_brief()
    brief["references_autorisees"] = []
    rep = check_project_brief(brief)
    assert rep["passed"] is False
    assert any("expliquant le fog" in r for r in rep["raisons"])


def test_empty_references_with_fog_humangate_passes():
    brief = _valid_brief()
    brief["references_autorisees"] = []
    brief["provenance"]["references_autorisees"] = (
        "FOG_HUMANGATE Pierre 2026-08-29 : aucune référence de genre, expérience pure")
    rep = check_project_brief(brief)
    assert rep["passed"] is True
    assert rep["raisons"] == []


def test_empty_references_with_unrelated_provenance_text_fails():
    brief = _valid_brief()
    brief["references_autorisees"] = []
    brief["provenance"]["references_autorisees"] = "aucune reference pour l'instant"
    rep = check_project_brief(brief)
    assert rep["passed"] is False
    assert any("expliquant le fog" in r for r in rep["raisons"])


# --- « à définir » n'importe où ----------------------------------------------------

def test_todo_placeholder_in_intention_fails():
    brief = _valid_brief()
    brief["intention"] = "à définir"
    rep = check_project_brief(brief)
    assert rep["passed"] is False
    assert any("« à définir »" in r for r in rep["raisons"])


def test_todo_placeholder_case_and_accent_insensitive_fails():
    brief = _valid_brief()
    brief["cible"] = "A DEFINIR"
    rep = check_project_brief(brief)
    assert rep["passed"] is False
    assert any("« à définir »" in r for r in rep["raisons"])


def test_todo_placeholder_nested_in_project_specific_fails():
    brief = _valid_brief()
    brief["contraintes"]["project_specific"]["techniques"] = ["à définir"]
    rep = check_project_brief(brief)
    assert rep["passed"] is False
    assert any("« à définir »" in r for r in rep["raisons"])


def test_todo_placeholder_in_reference_source_fails():
    brief = _valid_brief()
    brief["references_autorisees"] = [{"ref": "Cookie Clicker", "source": "à définir"}]
    rep = check_project_brief(brief)
    assert rep["passed"] is False
    assert any("« à définir »" in r for r in rep["raisons"])


def test_deepcopy_of_valid_brief_still_passes():
    # Garde-fou anti-mutation-partagée entre tests : une copie profonde du brief
    # valide doit repasser à l'identique.
    rep = check_project_brief(copy.deepcopy(_valid_brief()))
    assert rep["passed"] is True


# --- pré-vol fail-closed (project_brief_gate, run_real.main §3) -------------------
# Factorisé hors main() pour rester testable sans subprocess/argv : mêmes règles,
# aucune activation LLM dépensée dans ce fichier de test (aucun `claude -p` appelé).

def _brief_path(repo_root, project):
    return repo_root / "EVIDENCE" / "briefs" / project / "project_brief.yaml"


def test_profile_without_s0_contrat_skips_gate_entirely(tmp_path, monkeypatch):
    monkeypatch.setattr(run_real, "REPO_ROOT", tmp_path)
    # PAS de EVIDENCE/briefs/ créé du tout : si le gate touchait le disque pour
    # un profil sans s0-contrat, il lèverait — il doit rendre None sans y toucher.
    result = run_real.project_brief_gate("patch", "un_projet_quelconque")
    assert result is None


def test_profile_with_s0_contrat_and_no_brief_fails_closed(tmp_path, monkeypatch):
    monkeypatch.setattr(run_real, "REPO_ROOT", tmp_path)
    result = run_real.project_brief_gate("full_godot", "kitten_clicker")
    assert result is not None
    assert "PRE-VOL ECHOUE" in result
    assert "Brief canonique absent" in result


def test_profile_with_s0_contrat_and_valid_brief_passes(tmp_path, monkeypatch):
    monkeypatch.setattr(run_real, "REPO_ROOT", tmp_path)
    p = _brief_path(tmp_path, "kitten_clicker")
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(yaml.safe_dump(_valid_brief(), allow_unicode=True), encoding="utf-8")
    result = run_real.project_brief_gate("full_godot", "kitten_clicker")
    assert result is None


def test_profile_with_s0_contrat_and_invalid_yaml_fails_closed(tmp_path, monkeypatch):
    monkeypatch.setattr(run_real, "REPO_ROOT", tmp_path)
    p = _brief_path(tmp_path, "kitten_clicker")
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text("projet: [unclosed\n  intention: oops", encoding="utf-8")
    result = run_real.project_brief_gate("full_godot", "kitten_clicker")
    assert result is not None
    assert "PRE-VOL ECHOUE" in result
    assert "YAML invalide" in result


def test_profile_with_s0_contrat_and_incomplete_brief_fails_closed(tmp_path, monkeypatch):
    monkeypatch.setattr(run_real, "REPO_ROOT", tmp_path)
    p = _brief_path(tmp_path, "kitten_clicker")
    p.parent.mkdir(parents=True, exist_ok=True)
    incomplete = _valid_brief()
    del incomplete["criteres_sortie"]
    p.write_text(yaml.safe_dump(incomplete, allow_unicode=True), encoding="utf-8")
    result = run_real.project_brief_gate("full_godot", "kitten_clicker")
    assert result is not None
    assert "PRE-VOL ECHOUE" in result
    assert "check_project_brief FAIL" in result
    assert "criteres_sortie" in result

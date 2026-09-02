"""P1 (dispatch reel) et P2 (boucle d'amelioration) — tests.

Deux boucles longtemps restees DOCUMENTED_ONLY :
  P1 : un runtime declare dans roles.yaml mais jamais dispatche.
  P2 : des generation_report.json ecrits mais jamais relus.

Ce fichier verifie qu'elles sont branchees POUR DE VRAI :
  - le dispatcher emet des recus signes verifiables par le verificateur du studio ;
  - une lecon derivee d'un lot, une fois RATIFIEE, change le comportement du lot suivant.

La derniere assertion est la seule qui reponde a « pourquoi le prochain lot est
different du precedent ».
"""
from __future__ import annotations

import json
import shutil
from pathlib import Path

import pytest

from forge.asset_producer import analyze_batch as AB
from forge.asset_producer import asset_dispatch as AD

REPO = Path(__file__).resolve().parents[2]
PROPS = REPO / "knowledge_base" / "assets" / "props3d"


@pytest.fixture
def lecons_jetables(tmp_path, monkeypatch):
    """Isole lecons + contraintes dans un repertoire jetable (jamais l'etat du depot)."""
    d = tmp_path / "asset_lessons"
    d.mkdir()
    monkeypatch.setattr(AB, "LESSONS_DIR", d)
    monkeypatch.setattr(AB, "CONSTRAINTS_PATH", d / "batch_constraints.json")
    return d


# --------------------------------------------------------------- P2 : derivation

@pytest.mark.skipif(not (PROPS / "gen_chest_01.glb").is_file(), reason="lot absent")
def test_une_lecon_est_derivee_du_lot_reel(lecons_jetables):
    """La lecon vient des generation_report.json + du rejeu de l'oracle, pas d'un LLM."""
    obs = AB.collect(PROPS)
    assert obs, "aucun generation_report.json lu — la boucle n'aurait aucune entree"
    assert any(o["manifeste_humain"] for o in obs), \
        "le lot doit contenir au moins un asset ayant exige un manifeste HumanGate"

    lecons = AB.derive_lessons(obs, "lot-test")
    ids = {l["lesson_id"] for l in lecons}
    assert "asset.chest_exige_declaration_variantes" in ids
    l = next(l for l in lecons if l["lesson_id"] == "asset.chest_exige_declaration_variantes")
    assert l["status"] == AB.STATUS_CANDIDATE, "une lecon ne s'auto-valide jamais"
    assert l["cause_racine"]["couche"] == "spec"
    assert l["impact_prochain_lot"]["attendu"]


def test_une_lecon_candidate_ne_contraint_rien(lecons_jetables):
    """Tant qu'un humain n'a pas ratifie, la lecon n'a aucun effet."""
    lecon = {
        "lesson_id": "asset.chest_exige_declaration_variantes", "asset_type": "chest",
        "status": AB.STATUS_CANDIDATE,
        "defauts_detectes": [{"verdict": "BLOCKED"}],
    }
    c = AB.build_constraints([lecon])
    assert c["require_variants_declared"] == []
    assert c["archetypes_blocked"] == []


def test_une_lecon_validee_produit_une_contrainte(lecons_jetables):
    lecon = {
        "lesson_id": "asset.chest_exige_declaration_variantes", "asset_type": "chest",
        "status": AB.STATUS_VALIDATED,
        "defauts_detectes": [{"verdict": "BLOCKED"}],
    }
    c = AB.build_constraints([lecon])
    assert c["require_variants_declared"] == ["chest"]
    assert "asset.chest_exige_declaration_variantes" in c["derived_from"]


def test_validation_exige_un_nom(lecons_jetables):
    (lecons_jetables / "asset.x.json").write_text(json.dumps({
        "lesson_id": "asset.x", "asset_type": "chest", "status": AB.STATUS_CANDIDATE,
        "defauts_detectes": [{"verdict": "BLOCKED"}],
    }), encoding="utf-8")
    with pytest.raises(ValueError):
        AB.valider("asset.x", "")


@pytest.mark.parametrize("nom", [
    "Pierre (demo)", "test", "Pierre-TEST", "utilisateur factice", "placeholder",
])
def test_une_signature_simulee_est_refusee_dans_l_etat_reel(monkeypatch, nom):
    """Regle ratifiee Pierre 2026-08-06, nee d'un incident reel.

    Une lecon avait ete validee `--par "Pierre (demo)"` pour demontrer la boucle :
    une signature qu'il n'avait pas donnee.

    La regle porte sur l'ETAT REEL du depot. Simuler une signature dans un bac a sable
    reste la maniere CORRECTE de tester la boucle (cf.
    test_asset_lesson_lifecycle.py::test_simulation_autorisee_en_bac_a_sable) — c'est
    l'etat versionne qui ne doit jamais porter de signature fabriquee.

    Le filtre attrape les marqueurs EXPLICITES de simulation ; il ne prouve pas
    l'authenticite d'un nom plausible, et ne le pretend pas.
    """
    monkeypatch.setattr(AB, "LESSONS_DIR", AB.LESSONS_DIR_REEL)
    with pytest.raises(ValueError, match="etat reel"):
        AB.valider("asset.peu_importe", nom)


def test_aucune_lecon_du_depot_n_est_validee_par_une_signature_simulee():
    """Garde-fou permanent sur l'etat REEL du depot, pas sur une fixture."""
    d = REPO / "EVIDENCE" / "bundles" / "asset_lessons"
    if not d.is_dir():
        pytest.skip("aucune lecon dans le depot")
    for f in d.glob("asset.*.json"):
        l = json.loads(f.read_text(encoding="utf-8"))
        signataire = (l.get("validated_by") or "").lower()
        assert not any(m in signataire for m in AB.MARQUEURS_DE_SIMULATION), \
            f"{f.name} porte une signature simulee : {l.get('validated_by')!r}"


def test_une_lecon_validee_n_est_jamais_ecrasee_par_une_reanalyse(lecons_jetables):
    """Une re-analyse ne doit pas faire retomber une lecon ratifiee en CANDIDATE."""
    p = lecons_jetables / "asset.chest_exige_declaration_variantes.json"
    p.write_text(json.dumps({
        "lesson_id": "asset.chest_exige_declaration_variantes", "asset_type": "chest",
        "status": AB.STATUS_VALIDATED, "validated_by": "Pierre",
        "defauts_detectes": [{"verdict": "BLOCKED"}],
    }), encoding="utf-8")

    AB.write_lessons([{
        "lesson_id": "asset.chest_exige_declaration_variantes", "asset_type": "chest",
        "status": AB.STATUS_CANDIDATE, "defauts_detectes": [{"verdict": "BLOCKED"}],
    }])
    assert json.loads(p.read_text(encoding="utf-8"))["status"] == AB.STATUS_VALIDATED


# --------------------------------------------------------------- P2 : effet sur le lot suivant

def test_la_contrainte_change_le_lot_suivant(lecons_jetables, monkeypatch):
    """LA question : pourquoi le lot n+1 differe du lot n.

    Meme spec, deux resultats : conforme avant ratification, refusee apres.
    """
    spec = {"asset_id": "gen_chest_02", "archetype": "chest", "category": "chest",
            "size": {"w": 1.0, "d": 0.7, "h": 0.8}, "variants": [],
            "consumer": ["coffre de boss"]}

    AB.refresh_constraints()                      # aucune lecon -> aucune contrainte
    assert AD.check_batch_constraints(spec) == "", "rien ne doit bloquer sans lecon validee"

    (lecons_jetables / "asset.chest_exige_declaration_variantes.json").write_text(
        json.dumps({"lesson_id": "asset.chest_exige_declaration_variantes",
                    "asset_type": "chest", "status": AB.STATUS_VALIDATED,
                    "defauts_detectes": [{"verdict": "BLOCKED"}]}), encoding="utf-8")
    AB.refresh_constraints()

    viol = AD.check_batch_constraints(spec)
    assert viol and "variants" in viol, viol

    spec_conforme = {**spec, "variants": ["lid_closed", "lid_open"]}
    assert AD.check_batch_constraints(spec_conforme) == "", \
        "une spec qui declare ses variantes doit repasser"


def test_archetype_bloque_par_une_lecon_de_defaut(lecons_jetables):
    (lecons_jetables / "asset.crate_ground_contact.json").write_text(json.dumps({
        "lesson_id": "asset.crate_ground_contact", "asset_type": "crate",
        "status": AB.STATUS_VALIDATED, "defauts_detectes": [{"verdict": "FAIL"}],
    }), encoding="utf-8")
    AB.refresh_constraints()
    viol = AD.check_batch_constraints({"archetype": "crate", "variants": []})
    assert "bloque" in viol


def test_contraintes_illisibles_ne_bloquent_pas_la_production(monkeypatch):
    """L'amelioration ne doit jamais devenir un point de panne de la production."""
    monkeypatch.setattr(AB, "CONSTRAINTS_PATH", Path("/inexistant/x.json"))
    assert AD.check_batch_constraints({"archetype": "crate", "variants": []}) == ""


# --------------------------------------------------------------- P1 : dispatch tracable

def test_le_dispatch_bloque_avant_blender_si_la_spec_viole(tmp_path, lecons_jetables):
    """Le gate agit AVANT production : aucun .glb ne doit apparaitre."""
    (lecons_jetables / "asset.chest_exige_declaration_variantes.json").write_text(
        json.dumps({"lesson_id": "asset.chest_exige_declaration_variantes",
                    "asset_type": "chest", "status": AB.STATUS_VALIDATED,
                    "defauts_detectes": [{"verdict": "BLOCKED"}]}), encoding="utf-8")
    AB.refresh_constraints()

    spec = tmp_path / "s.json"
    spec.write_text(json.dumps({
        "asset_id": "gen_chest_99", "archetype": "chest", "category": "chest",
        "size": {"w": 1, "d": 1, "h": 1}, "variants": [], "consumer": ["x"],
    }), encoding="utf-8")
    dest = tmp_path / "out"
    dest.mkdir()

    # ISOLATION DE LA PREUVE (2026-08-19) : sans ces destinations, ce seul test
    # ajoutait 2 lignes a `EVIDENCE/bundles/dispatch_audit.jsonl` et 1 a
    # `asset_results.jsonl` — les VRAIS artefacts. `dispatch` compte SIX points
    # d emission ; un oubli sur un seul suffit a contaminer.
    code, enreg = AD.dispatch(spec, dest, run_id="test-bloque", propose=False,
                              audit_path=tmp_path / "audit.jsonl",
                              results_path=tmp_path / "res.jsonl")
    assert code == 1
    assert enreg["reason"] == "SPEC_VIOLATES_BATCH_CONSTRAINT"
    assert enreg["produced"] is False
    assert list(dest.glob("*.glb")) == [], "Blender n'aurait jamais du etre invoque"


def test_le_dispatch_n_ecrit_jamais_le_catalogue():
    src = (REPO / "forge/asset_producer/asset_dispatch.py").read_text(encoding="utf-8")
    assert "catalog_written" in src
    assert '"catalog_written": False' in src or '"catalog_written": True' not in src


def test_les_recus_du_run_reel_sont_signes_et_verifiables():
    """Preuve P1 : le run reel `asset-door-demo-01` a laisse des recus verifiables.

    Skip explicite si l'audit n'est pas dans le depot — jamais un faux vert.
    """
    audit = REPO / "EVIDENCE" / "bundles" / "dispatch_audit.jsonl"
    if not audit.is_file():
        pytest.skip("dispatch_audit.jsonl absent")
    from forge.audit import verify_audit_line

    lignes = [json.loads(l) for l in audit.read_text(encoding="utf-8").splitlines() if l.strip()]
    recus = [d for d in lignes if d.get("capability_role") == "asset_producer"]
    if not recus:
        pytest.skip("aucun recu asset_producer — le run reel n'est pas dans ce depot")

    evenements = {d["event"] for d in recus}
    assert {"spawn_prepared", "spawn_executed"} <= evenements
    for d in recus:
        assert verify_audit_line(d), f"recu non verifiable: {d.get('event')}"

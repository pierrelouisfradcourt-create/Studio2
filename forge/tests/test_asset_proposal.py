"""Ingestion d'asset par PROPOSITION (P0, 2026-08-06).

Contexte : le premier lot d'assets avait ete ecrit DIRECTEMENT dans catalog.json,
en violation de la doctrine propose-only (ADR-002). Le catalogue a ete restaure a
l'identique et l'ecriture directe remplacee par une proposition `kb.proposal.v1`,
promue par la porte deja existante `kb_proposal.apply_proposal`.

Ces tests verifient les deux moities :
  - propose_asset ne contourne JAMAIS le verdict de l'oracle, et n'ecrit JAMAIS
    le catalogue ;
  - le trajet production -> proposition -> ratification -> catalogue fonctionne
    reellement (execute sur une racine JETABLE, jamais sur le catalogue du depot).
"""
from __future__ import annotations

import json
import shutil
from pathlib import Path

import pytest

from forge.asset_producer import propose_asset as P
from forge import kb_proposal as KP

REPO = Path(__file__).resolve().parents[2]
PROPS = REPO / "knowledge_base" / "assets" / "props3d"
FIXTURES = REPO / "forge" / "asset_geometry" / "tests" / "fixtures"

pytestmark = pytest.mark.skipif(
    not (PROPS / "gen_crate_wood_01.glb").is_file(),
    reason="lot d'assets produit absent du depot",
)


def _racine_jetable(tmp_path: Path, monkeypatch) -> Path:
    """Repo factice : knowledge_base/{catalog.json, proposals/, assets/props3d/}."""
    kb = tmp_path / "knowledge_base"
    (kb / "proposals").mkdir(parents=True)
    (kb / "assets" / "props3d").mkdir(parents=True)
    (kb / "catalog.json").write_text(
        json.dumps({"catalog_version": 1, "entries": []}, indent=1), encoding="utf-8")
    monkeypatch.setattr(P, "REPO", tmp_path)
    monkeypatch.setattr(P, "KB_ROOT", kb)
    monkeypatch.setattr(P, "PROPOSALS", kb / "proposals")
    return kb


def _copier_asset(kb: Path, nom: str = "gen_crate_wood_01") -> Path:
    dst = kb / "assets" / "props3d" / f"{nom}.glb"
    shutil.copy(PROPS / f"{nom}.glb", dst)
    shutil.copy(PROPS / f"{nom}.glb.metadata.json", Path(str(dst) + ".metadata.json"))
    manifeste = PROPS / f"{nom}.glb.geometry.json"
    if manifeste.is_file():
        shutil.copy(manifeste, Path(str(dst) + ".geometry.json"))
    return dst


# ------------------------------------------------------- la proposition ne contourne rien

def test_asset_non_OK_est_refuse_pas_propose(tmp_path, monkeypatch):
    """Une proposition transporte un verdict, elle ne le remplace pas."""
    kb = _racine_jetable(tmp_path, monkeypatch)
    enterre = kb / "assets" / "props3d" / "enterre.glb"
    shutil.copy(FIXTURES / "buried.glb", enterre)
    Path(str(enterre) + ".metadata.json").write_text(json.dumps({
        "asset_id": "enterre", "category": "prop", "consumer_examples": ["x"],
    }), encoding="utf-8")

    res = P.propose([str(enterre)])
    assert res["proposes"] == []
    assert res["refuses"] and res["refuses"][0][1] == "FAIL"
    assert not list((kb / "proposals").glob("*.yaml"))


def test_asset_sans_declaration_est_refuse(tmp_path, monkeypatch):
    kb = _racine_jetable(tmp_path, monkeypatch)
    orphelin = kb / "assets" / "props3d" / "orphelin.glb"
    shutil.copy(FIXTURES / "posed_ok.glb", orphelin)

    res = P.propose([str(orphelin)])
    assert res["proposes"] == []
    assert res["refuses"][0][1] == "NO_DECLARATION"


def test_propose_n_ecrit_jamais_le_catalogue(tmp_path, monkeypatch):
    kb = _racine_jetable(tmp_path, monkeypatch)
    avant = (kb / "catalog.json").read_text(encoding="utf-8")
    P.propose([str(_copier_asset(kb))])
    assert (kb / "catalog.json").read_text(encoding="utf-8") == avant


def test_proposition_bien_formee(tmp_path, monkeypatch):
    yaml = pytest.importorskip("yaml")
    kb = _racine_jetable(tmp_path, monkeypatch)
    P.propose([str(_copier_asset(kb))])

    f = kb / "proposals" / "asset.gen_crate_wood_01.yaml"
    assert f.is_file()
    rec = yaml.safe_load(f.read_text(encoding="utf-8"))

    assert rec["schema"] == "kb.proposal.v1"
    assert rec["status"] == "PROPOSED"
    assert rec["ratification"]["statut"] == "EN_ATTENTE"
    assert rec["ratification"]["decideur"] is None

    e = rec["entree_catalogue_proposee"]
    assert e["entry_type"] == "asset" and e["format"] == "3D" and e["ingested"] is True
    assert e["geometry_status"] == "OK"
    assert e["consumer"], "pas d'asset sans consommateur"
    assert rec["preuve"]["oracle"].endswith("oracle.py")
    assert rec["preuve"]["verdict"] == "OK"


# ------------------------------------------------------- le trajet complet

def test_production_proposition_ratification_catalogue(tmp_path, monkeypatch):
    """production -> proposal -> validation humaine -> catalogue, sur racine jetable.

    C'est la preuve demandee par P0. Le catalogue du depot n'est jamais touche :
    `kb_root` pointe sur tmp_path.
    """
    pytest.importorskip("yaml")
    kb = _racine_jetable(tmp_path, monkeypatch)
    P.propose([str(_copier_asset(kb))])

    res = KP.apply_proposal("asset.gen_crate_wood_01",
                            ratifie_par="test-automatise", kb_root=kb)
    assert res is not None

    catalogue = json.loads((kb / "catalog.json").read_text(encoding="utf-8"))
    ids = [e.get("asset_id") for e in catalogue["entries"]]
    assert "asset-gen-crate-wood-01" in ids

    entree = next(e for e in catalogue["entries"]
                  if e.get("asset_id") == "asset-gen-crate-wood-01")
    assert entree["geometry_status"] == "OK"
    assert entree["ingested"] is True and entree["format"] == "3D"

    import yaml
    rec = yaml.safe_load((kb / "proposals" / "asset.gen_crate_wood_01.yaml")
                         .read_text(encoding="utf-8"))
    assert rec["status"] == "APPLIQUEE"
    assert rec["ratification"]["decideur"] == "test-automatise"


def test_ratification_exige_un_decideur(tmp_path, monkeypatch):
    """Aucune ecriture durable sans nom d'humain : jamais de defaut implicite."""
    pytest.importorskip("yaml")
    kb = _racine_jetable(tmp_path, monkeypatch)
    P.propose([str(_copier_asset(kb))])
    with pytest.raises(ValueError):
        KP.apply_proposal("asset.gen_crate_wood_01", ratifie_par="", kb_root=kb)


def test_double_application_refusee(tmp_path, monkeypatch):
    pytest.importorskip("yaml")
    kb = _racine_jetable(tmp_path, monkeypatch)
    P.propose([str(_copier_asset(kb))])
    KP.apply_proposal("asset.gen_crate_wood_01", ratifie_par="test", kb_root=kb)
    with pytest.raises(ValueError):
        KP.apply_proposal("asset.gen_crate_wood_01", ratifie_par="test", kb_root=kb)


def test_catalogue_du_depot_reste_intact_apres_les_tests():
    """Garde-fou : ces tests ne doivent jamais avoir touche le vrai catalogue."""
    reel = json.loads((REPO / "knowledge_base" / "catalog.json").read_text(encoding="utf-8"))
    gen = [e for e in reel["entries"]
           if str(e.get("asset_id", "")).startswith("asset-gen-")]
    assert gen == [], f"le catalogue du depot a ete modifie : {gen}"

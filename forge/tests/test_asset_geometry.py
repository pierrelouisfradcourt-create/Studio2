"""Asset Geometry Oracle V1 — tests.

Spec : docs/forge/ASSET_GEOMETRY_ORACLE_V1_DESIGN.md

Deux garde-fous structurent ce fichier :
  1. L'oracle DOIT accepter la reference connue-bonne du studio sur l'ancrage (8 KayKit).
     Un oracle qui recale son propre corpus de reference se mesure lui-meme.
  2. `evaluate()` ne doit JAMAIS lire un .glb : plusieurs tests lui passent un
     measurement ecrit a la main. Si un jour il ouvrait un fichier, ils casseraient.
"""
from __future__ import annotations

import json
from pathlib import Path

import pytest

from forge.asset_geometry import measure as M
from forge.asset_geometry import oracle as O

REPO = Path(__file__).resolve().parents[2]
FIXTURES = REPO / "forge" / "asset_geometry" / "tests" / "fixtures"
KAYKIT = [
    *sorted((REPO / "GAMES/chess_tcg/assets/characters/adventurers").glob("*.glb")),
    *sorted((REPO / "GAMES/chess_tcg/assets/characters/skeletons").glob("*.glb")),
]

RULES = O.load_rules()


# --------------------------------------------------------------------------- mesure

def test_fixtures_exist():
    """Sans fixtures, tout le reste de ce fichier serait un faux vert."""
    assert FIXTURES.is_dir(), f"repertoire de fixtures absent: {FIXTURES}"
    noms = {p.stem for p in FIXTURES.glob("*.glb")}
    assert noms == {"posed_ok", "floating", "buried", "pivot_center",
                    "scale_x100", "generated_like"}, noms


def test_measure_declares_gltf_y_up():
    """glTF est Y-up. Mesurer Z serait mesurer la profondeur en croyant lire la hauteur."""
    m = M.measure(FIXTURES / "posed_ok.glb")
    assert m.up_axis == "Y"
    assert m.measurement_space == "gltf_bind_pose"
    assert m.skin_evaluated is False, "la limite bind-pose doit rester declaree"


def test_measure_posed_fixture():
    m = M.measure(FIXTURES / "posed_ok.glb")
    assert len(m.mesh_nodes) == 1
    assert m.union_min[1] == pytest.approx(0.0, abs=1e-4)
    assert m.mesh_nodes[0]["has_material"] is True
    assert len(m.sha256) == 64


def test_measure_missing_file_reports_error_without_raising():
    m = M.measure(FIXTURES / "n_existe_pas.glb")
    assert m.mesh_nodes == []
    assert any("introuvable" in e for e in m.errors)


# ------------------------------------------------------------------- fixtures/verdicts

@pytest.mark.parametrize("nom,verdict_attendu,check_en_echec", [
    ("posed_ok",       O.VERDICT_OK,   None),
    ("floating",       O.VERDICT_FAIL, "ground_contact"),
    ("buried",         O.VERDICT_FAIL, "no_buried_geometry"),
    ("pivot_center",   O.VERDICT_FAIL, "pivot_at_base"),
    ("scale_x100",     O.VERDICT_FAIL, "scale_within_band"),
    ("generated_like", O.VERDICT_FAIL, "no_buried_geometry"),
])
def test_fixture_verdicts(nom, verdict_attendu, check_en_echec):
    rep = O.run(FIXTURES / f"{nom}.glb")
    assert rep.verdict == verdict_attendu, [c["detail"] for c in rep.checks]
    if check_en_echec:
        echecs = {c["name"] for c in rep.checks if c["verdict"] == O.VERDICT_FAIL}
        assert check_en_echec in echecs


def test_chaque_fixture_de_defaut_isole_son_check():
    """Une fixture qui ferait echouer 3 checks ne prouverait aucun des 3."""
    for nom, attendu in [("floating", "ground_contact"),
                         ("buried", "no_buried_geometry"),
                         ("scale_x100", "scale_within_band")]:
        rep = O.run(FIXTURES / f"{nom}.glb")
        echecs = {c["name"] for c in rep.checks if c["verdict"] == O.VERDICT_FAIL}
        assert echecs == {attendu}, f"{nom}: {echecs}"


def test_pivot_center_echoue_sur_le_pivot_pas_sur_le_sol():
    """La fixture pivot est POSEE au sol : sol et enterrement doivent passer."""
    rep = O.run(FIXTURES / "pivot_center.glb")
    par_nom = {c["name"]: c["verdict"] for c in rep.checks}
    assert par_nom["ground_contact"] == O.VERDICT_OK
    assert par_nom["no_buried_geometry"] == O.VERDICT_OK
    assert par_nom["pivot_at_base"] == O.VERDICT_FAIL


def test_cas_degrade_sans_main_est_declare_pas_silencieux():
    """Sans MAIN identifie, l'oracle retombe sur tous les noeuds ET le dit."""
    rep = O.run(FIXTURES / "generated_like.glb")
    assert rep.main_geometry_undetermined is True
    assert "ALL_NODES" in rep.anchor_basis
    assert rep.verdict == O.VERDICT_FAIL  # ne s'echappe pas par une classification vide


# ------------------------------------------------------------------- corpus reel

@pytest.mark.skipif(not KAYKIT, reason="corpus KayKit absent du depot")
def test_reference_connue_bonne_jamais_recalee_sur_l_ancrage():
    """GARDE-FOU. Les 8 KayKit sont ancres a zero : aucun check d'ancrage ne doit ceder.

    C'est le test qui empeche l'oracle de se mesurer lui-meme.
    """
    assert len(KAYKIT) == 8, [p.name for p in KAYKIT]
    for p in KAYKIT:
        rep = O.run(p)
        par_nom = {c["name"]: c for c in rep.checks}
        assert par_nom["ground_contact"]["verdict"] == O.VERDICT_OK, p.name
        assert par_nom["no_buried_geometry"]["verdict"] == O.VERDICT_OK, p.name
        assert par_nom["scale_within_band"]["verdict"] == O.VERDICT_OK, p.name
        assert rep.verdict != O.VERDICT_FAIL, (p.name, rep.reason)


@pytest.mark.skipif(not KAYKIT, reason="corpus KayKit absent du depot")
def test_variantes_modulaires_bloquent_sans_manifeste(tmp_path):
    """Knight embarque 7 variantes d'arme : geometrie sans consommateur declare.

    Mesure sur une COPIE sans sidecar : depuis que Knight.glb a recu son manifeste,
    l'original est legitimement OK. Ce test doit continuer a prouver l'etat AVANT
    declaration -- d'ou la copie, plutot qu'un assouplissement de l'assertion.
    """
    import shutil
    knight = next(p for p in KAYKIT if p.name == "Knight.glb")
    copie = tmp_path / "Knight.glb"
    shutil.copy(knight, copie)

    rep = O.run(copie)
    assert rep.verdict == O.VERDICT_BLOCKED
    assert rep.reason == "SECONDARY_GEOMETRY_WITHOUT_CONTRACT"
    inconnus = {c["name"] for c in rep.census if c["classification"] == O.CLASS_UNKNOWN}
    assert {"1H_Sword", "2H_Sword", "Round_Shield"} <= inconnus, inconnus


# ------------------------------------------------------------------- environnement

def test_environnement_producteur_absent_bloque_jamais_ok():
    m = M.measure(FIXTURES / "posed_ok.glb")
    rep = O.evaluate(
        json.loads(json.dumps(m, default=lambda o: o.__dict__)),
        RULES, producer_required=True,
        producer_state=(False, "binaire Blender absent dans Ubuntu-24.04"),
    )
    assert rep.verdict == O.VERDICT_BLOCKED
    assert rep.reason == "BLENDER_EXECUTOR_UNAVAILABLE"


def test_environnement_producteur_present_ne_bloque_pas():
    m = M.measure(FIXTURES / "posed_ok.glb")
    rep = O.evaluate(
        json.loads(json.dumps(m, default=lambda o: o.__dict__)),
        RULES, producer_required=True, producer_state=(True, "joignable"),
    )
    assert rep.verdict == O.VERDICT_OK


# ------------------------------------------------------------------- declaration

def _measurement_synthetique(min_y: float, materiau: bool = True) -> dict:
    """Measurement ecrit a la main : prouve que l'oracle ne lit aucun .glb."""
    return {
        "schema_version": "1.0", "asset_file": "synthetique.glb", "sha256": "a" * 64,
        "size_bytes": 0, "up_axis": "Y", "measurement_space": "gltf_bind_pose",
        "skin_evaluated": False, "total_vertices": 100, "root_origin": [0.0, 0.0, 0.0],
        "union_min": [0.0, min_y, 0.0], "union_max": [1.0, min_y + 1.0, 1.0],
        "errors": [],
        "mesh_nodes": [{
            "node_index": 0, "name": "corps", "mesh_name": "corps", "parent": "Rig",
            "vertices": 100, "primitives": 1, "has_material": materiau,
            "is_skinned": True, "min": [0.0, min_y, 0.0], "max": [1.0, min_y + 1.0, 1.0],
        }],
    }


def test_oracle_juge_sans_jamais_ouvrir_de_fichier():
    rep = O.evaluate(_measurement_synthetique(0.0), RULES)
    assert rep.verdict == O.VERDICT_OK


def test_declaration_producteur_contredite_par_la_mesure():
    """Blender declare un asset pose ; la mesure independante le voit enterre."""
    rep = O.evaluate(
        _measurement_synthetique(-0.10), RULES,
        declaration={"lowest_point_y": 0.0},
    )
    noms = {c["name"] for c in rep.checks if c["verdict"] == O.VERDICT_FAIL}
    assert "declaration_mismatch" in noms
    assert "no_buried_geometry" in noms


def test_declaration_conforme_a_la_mesure_passe():
    rep = O.evaluate(
        _measurement_synthetique(0.0), RULES,
        declaration={"lowest_point_y": 0.0},
    )
    par_nom = {c["name"]: c["verdict"] for c in rep.checks}
    assert par_nom["declaration_mismatch"] == O.VERDICT_OK
    assert rep.verdict == O.VERDICT_OK


def test_declaration_sans_champ_attendu_bloque():
    rep = O.evaluate(_measurement_synthetique(0.0), RULES, declaration={"autre": 1})
    par_nom = {c["name"]: c["verdict"] for c in rep.checks}
    assert par_nom["declaration_mismatch"] == O.VERDICT_BLOCKED


# ------------------------------------------------------------------- manifeste

def test_manifeste_perime_bloque_sur_sha256():
    rep = O.evaluate(
        _measurement_synthetique(0.0), RULES,
        manifest={"sha256": "b" * 64, "meshes": [{"name": "corps", "role": "main"}]},
    )
    par_nom = {c["name"]: c["verdict"] for c in rep.checks}
    assert par_nom["manifest_stale"] == O.VERDICT_BLOCKED
    assert rep.verdict == O.VERDICT_BLOCKED


def test_manifeste_a_jour_ne_bloque_pas():
    rep = O.evaluate(
        _measurement_synthetique(0.0), RULES,
        manifest={"sha256": "a" * 64, "meshes": [{"name": "corps", "role": "main"}]},
    )
    par_nom = {c["name"]: c["verdict"] for c in rep.checks}
    assert par_nom["manifest_stale"] == O.VERDICT_OK
    assert rep.verdict == O.VERDICT_OK


def test_role_declare_debloque_une_geometrie_inconnue():
    """La geometrie non expliquee bloque ; declarer son role la debloque."""
    mes = _measurement_synthetique(0.0)
    mes["mesh_nodes"].append({
        "node_index": 1, "name": "epee_variante", "mesh_name": "epee", "parent": None,
        "vertices": 3, "primitives": 1, "has_material": True, "is_skinned": False,
        "min": [0.0, 0.2, 0.0], "max": [0.1, 0.4, 0.1],
    })
    mes["total_vertices"] = 103

    avant = O.evaluate(mes, RULES)
    assert avant.verdict == O.VERDICT_BLOCKED
    assert avant.reason == "SECONDARY_GEOMETRY_WITHOUT_CONTRACT"

    apres = O.evaluate(mes, RULES, manifest={
        "sha256": "a" * 64,
        "meshes": [{"name": "corps", "role": "main"},
                   {"name": "epee_variante", "role": "variant"}],
    })
    assert apres.verdict == O.VERDICT_OK


def test_collider_declare_exclu_de_la_mesure_d_ancrage():
    """Un collider deborde legitimement le visuel : il ne doit pas declencher 'enterre'."""
    mes = _measurement_synthetique(0.0)
    mes["mesh_nodes"].append({
        "node_index": 1, "name": "col", "mesh_name": "col", "parent": None,
        "vertices": 8, "primitives": 1, "has_material": True, "is_skinned": False,
        "min": [0.0, -5.0, 0.0], "max": [1.0, 1.0, 1.0],
    })
    mes["total_vertices"] = 108
    rep = O.evaluate(mes, RULES, manifest={
        "sha256": "a" * 64,
        "meshes": [{"name": "corps", "role": "main"}, {"name": "col", "role": "collider"}],
    })
    par_nom = {c["name"]: c["verdict"] for c in rep.checks}
    assert par_nom["no_buried_geometry"] == O.VERDICT_OK
    assert any(c["name"] == "col" for c in rep.census), "le collider reste recense"


# ------------------------------------------------------------------- seuils / lineage

def test_seuil_surcharge_par_le_run_est_trace():
    """Un seuil effectif doit toujours citer sa provenance (aucun seuil implicite)."""
    base = O.evaluate(_measurement_synthetique(0.30), RULES)
    assert base.verdict == O.VERDICT_FAIL  # 0.30 > tolerance par defaut 0.01

    permissif = O.evaluate(
        _measurement_synthetique(0.30), RULES,
        overrides={"ground": {"float_tolerance": 0.5}},
    )
    ground = next(c for c in permissif.checks if c["name"] == "ground_contact")
    assert ground["verdict"] == O.VERDICT_OK
    assert ground["threshold_source"] == "asset_request"

    ground_defaut = next(c for c in base.checks if c["name"] == "ground_contact")
    assert ground_defaut["threshold_source"] == "rules.yaml"


def test_chaque_check_porte_une_expression_ancrable():
    """Persistence lineage : la preuve s'ancre sur une expression, pas sur un numero de ligne."""
    rep = O.evaluate(_measurement_synthetique(0.0), RULES)
    for c in rep.checks:
        assert c.get("expression"), f"check sans expression: {c['name']}"


def test_vocabulaire_de_verdict_ferme():
    """OK/FAIL/BLOCKED uniquement — REVIEW_REQUIRED n'existe pas (ratifie Pierre)."""
    autorises = {O.VERDICT_OK, O.VERDICT_FAIL, O.VERDICT_BLOCKED}
    for nom in ["posed_ok", "floating", "buried", "pivot_center", "scale_x100",
                "generated_like"]:
        rep = O.run(FIXTURES / f"{nom}.glb")
        assert rep.verdict in autorises
        for c in rep.checks:
            assert c["verdict"] in autorises


def test_fog_toujours_present_quand_le_jugement_aboutit():
    """La mesure mecanique n'est jamais un satisfecit visuel."""
    rep = O.evaluate(_measurement_synthetique(0.0), RULES)
    assert rep.fog and "esthetique" in rep.fog


# ------------------------------------------------------------------- boucle complete

def _copier_asset(tmp_path: Path, nom: str = "posed_ok") -> Path:
    import shutil
    dst = tmp_path / f"{nom}.glb"
    shutil.copy(FIXTURES / f"{nom}.glb", dst)
    return dst


def test_sidecar_declaration_est_reellement_charge_par_run(tmp_path):
    """Le check existait mais rien ne chargeait le fichier : un validateur sans producteur."""
    asset = _copier_asset(tmp_path)
    (tmp_path / "posed_ok.glb.metadata.json").write_text(
        json.dumps({"asset_id": "x", "lowest_point_y": 0.0}), encoding="utf-8")
    rep = O.run(asset)
    noms = {c["name"] for c in rep.checks}
    assert "declaration_mismatch" in noms, "le sidecar metadata.json n'a pas ete lu"
    assert rep.verdict == O.VERDICT_OK


def test_declaration_sidecar_mensongere_est_prise_en_defaut(tmp_path):
    """Le producteur affirme un asset pose ; la mesure independante voit qu'il flotte."""
    asset = _copier_asset(tmp_path, "floating")
    (tmp_path / "floating.glb.metadata.json").write_text(
        json.dumps({"asset_id": "menteur", "lowest_point_y": 0.0}), encoding="utf-8")
    rep = O.run(asset)
    echecs = {c["name"] for c in rep.checks if c["verdict"] == O.VERDICT_FAIL}
    assert "declaration_mismatch" in echecs
    assert rep.verdict == O.VERDICT_FAIL


def test_manifeste_sidecar_debloque_un_asset_reel(tmp_path):
    """Boucle complete sur fichier : sans manifeste BLOCKED, avec manifeste OK."""
    asset = _copier_asset(tmp_path, "generated_like")
    avant = O.run(asset)
    assert avant.verdict == O.VERDICT_FAIL  # enterre : le defaut prime

    m = M.measure(asset)
    (tmp_path / "generated_like.glb.geometry.json").write_text(json.dumps({
        "schema_version": "1.0", "sha256": m.sha256, "origin_rule": "base_center",
        "meshes": [{"name": "generated_like", "role": "main"}],
    }), encoding="utf-8")
    apres = O.run(asset)
    par_nom = {c["name"]: c["verdict"] for c in apres.checks}
    assert par_nom["all_meshes_declared"] == O.VERDICT_OK, "le role declare n'a pas ete pris"
    assert apres.verdict == O.VERDICT_FAIL, "l'enterrement reste un defaut MESURE"


def test_origin_rule_inconnu_bloque_au_lieu_de_faire_taire_le_check(tmp_path):
    """Trou d'echappement : une valeur libre dans origin_rule desactivait pivot_at_base."""
    asset = _copier_asset(tmp_path, "pivot_center")
    m = M.measure(asset)
    (tmp_path / "pivot_center.glb.geometry.json").write_text(json.dumps({
        "schema_version": "1.0", "sha256": m.sha256,
        "origin_rule": "feet_on_ground",  # plausible, mais hors enumeration fermee
        "meshes": [{"name": "pivot_center", "role": "main"}],
    }), encoding="utf-8")
    rep = O.run(asset)
    pivot = next(c for c in rep.checks if c["name"] == "pivot_at_base")
    assert pivot["verdict"] == O.VERDICT_BLOCKED
    assert "hors enumeration fermee" in pivot["detail"]


def test_toute_geometrie_unknown_porte_une_raison():
    """Un blocage muet est un blocage inexploitable : l'operateur doit savoir quoi corriger."""
    rep = O.run(FIXTURES / "generated_like.glb")
    inconnus = [c for c in rep.census if c["classification"] == O.CLASS_UNKNOWN]
    assert inconnus, "cette fixture doit produire au moins une geometrie UNKNOWN"
    for c in inconnus:
        assert c.get("unknown_reason"), f"UNKNOWN sans raison: {c['name']}"


@pytest.mark.skipif(not KAYKIT, reason="corpus KayKit absent du depot")
def test_knight_boucle_fermee_par_ses_sidecars():
    """Regression : Knight.glb + ses 2 sidecars doivent rester OK de bout en bout.

    C'est la seule preuve de la boucle complete sur un asset REEL du studio.
    """
    knight = next(p for p in KAYKIT if p.name == "Knight.glb")
    if not Path(str(knight) + ".geometry.json").is_file():
        pytest.skip("sidecar manifeste absent (non commite ?)")
    rep = O.run(knight)
    assert rep.verdict == O.VERDICT_OK, [c for c in rep.checks
                                         if c["verdict"] != O.VERDICT_OK]
    par_nom = {c["name"]: c["verdict"] for c in rep.checks}
    assert par_nom["declaration_mismatch"] == O.VERDICT_OK
    assert par_nom["all_meshes_declared"] == O.VERDICT_OK
    assert par_nom["manifest_stale"] == O.VERDICT_OK
    variantes = {c["name"] for c in rep.census
                 if c["declared_role"] == "variant"}
    assert len(variantes) == 7, variantes


# ------------------------------------------------------------------- couche runtime

def _godot_bin() -> Path | None:
    cfg = REPO / "forge" / "godot.config.json"
    if not cfg.is_file():
        return None
    p = Path(json.loads(cfg.read_text(encoding="utf-8")).get("godot_bin", ""))
    return p if p.is_file() else None


def _godot_probe(asset: Path) -> dict:
    import subprocess
    probe = REPO / "forge/asset_geometry/godot_probe/probe.gd"
    r = subprocess.run(
        [str(_godot_bin()), "--headless", "--script", str(probe), "--",
         str(asset).replace("\\", "/")],
        capture_output=True, text=True, timeout=300, cwd=str(REPO),
    )
    for line in (r.stdout or "").splitlines():
        if line.startswith("GODOT_PROBE|"):
            return json.loads(line.split("|", 1)[1])
    raise AssertionError(f"sonde Godot sans sortie exploitable: {r.stdout[-500:]}")


@pytest.mark.skipif(_godot_bin() is None, reason="binaire Godot absent (godot.config.json)")
@pytest.mark.parametrize("nom", ["posed_ok", "buried"])
def test_runtime_godot_confirme_la_mesure_intake(nom):
    """Deux executeurs INDEPENDANTS doivent tomber d'accord.

    Le parseur lit les octets du glTF ; Godot instancie la scene. S'ils divergent,
    c'est que l'un des deux ment -- et le rapport doit cesser d'etre credible.
    """
    asset = FIXTURES / f"{nom}.glb"
    m = M.measure(asset)
    g = _godot_probe(asset)

    assert g["import_ok"] is True
    assert g["mesh_instances"] == len(m.mesh_nodes)
    assert g["aabb_min_y"] == pytest.approx(m.union_min[1], abs=1e-3)
    assert g["aabb_max_y"] == pytest.approx(m.union_max[1], abs=1e-3)


@pytest.mark.skipif(_godot_bin() is None, reason="binaire Godot absent (godot.config.json)")
@pytest.mark.skipif(not KAYKIT, reason="corpus KayKit absent du depot")
def test_runtime_godot_instancie_bien_les_variantes_non_declarees():
    """Preuve runtime du defaut : Godot instancie les 7 variantes d'arme du Knight."""
    knight = next(p for p in KAYKIT if p.name == "Knight.glb")
    g = _godot_probe(knight)
    assert g["mesh_instances"] == 15
    assert {"1H_Sword", "2H_Sword", "Round_Shield", "Spike_Shield"} <= set(g["node_names"])
    assert g["aabb_min_y"] == pytest.approx(0.0, abs=1e-3)

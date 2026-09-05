"""Garde de perimetre de commit — l'index correspond-il a l'intention ?

Nee d'un incident reel (2026-08-06) : un `git add` multi-chemins a echoue sur un chemin
ignore, l'index s'est retrouve avec 382 fichiers d'un chantier voisin, et un commit
concurrent l'a emporte. L'historique annoncait alors un contenu qu'il n'avait pas.

Ces tests portent sur la fonction PURE `check()` : aucun appel a git, aucun etat de depot.
"""
from __future__ import annotations

import json
from pathlib import Path

import pytest

from forge import commit_scope_guard as G
from forge.asset_producer import analyze_batch as AB

REPO = Path(__file__).resolve().parents[2]

PERIMETRE = ["forge/asset_geometry", "docs/forge/ASSET_CONTRACT_V0.md"]


def test_index_dans_le_perimetre_est_accepte():
    ok, dehors = G.check(
        ["forge/asset_geometry/oracle.py", "docs/forge/ASSET_CONTRACT_V0.md"],
        PERIMETRE)
    assert ok and dehors == []


def test_un_seul_fichier_hors_perimetre_refuse_tout():
    """C'est exactement la panne observee : un chantier voisin emporte par megarde."""
    ok, dehors = G.check(
        ["forge/asset_geometry/oracle.py", "GAMES/pacman/main.tscn"],
        PERIMETRE)
    assert not ok
    assert dehors == ["GAMES/pacman/main.tscn"]


def test_le_prefixe_ne_deborde_pas_sur_un_voisin_de_meme_debut():
    """`forge/asset_geometry` ne doit pas autoriser `..._autre/`."""
    ok, dehors = G.check(["forge/asset_geometry_autre/x.py"], PERIMETRE)
    assert not ok, dehors


def test_le_fichier_exact_est_accepte_sans_slash():
    ok, _ = G.check(["docs/forge/ASSET_CONTRACT_V0.md"], PERIMETRE)
    assert ok


def test_les_separateurs_windows_sont_normalises():
    ok, dehors = G.check(["forge/asset_geometry/oracle.py"],
                         ["forge\\asset_geometry"])   # layout L1 (ex-`scripts\forge\...`)
    assert ok, dehors


def test_prefixe_avec_slash_final_equivaut(tmp_path):
    ok, _ = G.check(["forge/asset_geometry/oracle.py"],
                    ["forge/asset_geometry/"])
    assert ok


# ------------------------------------------------------- le perimetre declare

def test_le_perimetre_asset_library_existe_et_pointe_du_reel():
    """Un perimetre qui cite des chemins inexistants ne protege rien.

    Seule tolerance : le repertoire de lecons que la chaine cree ELLE-MEME au premier lot
    (analyze_batch.write_lessons / refresh_constraints : mkdir). Il n'est jamais cree
    artificiellement (meme constat NOT_YET_PRODUCED que TOOLS/validate_v2.py, v1_surfaces)
    et son chemin est lu chez le producteur, pas recopie ici : si le producteur est reancre
    sans que commit_scopes.json suive, ce test redevient rouge. Absent -> XFAIL visible.
    GO Pierre 2026-09-05 (U5).
    """
    scopes = G.load_scopes()
    assert "asset_library" in scopes, "perimetre asset_library absent de commit_scopes.json"
    produit_au_premier_lot = AB.LESSONS_DIR_REEL.relative_to(REPO).as_posix()
    assert produit_au_premier_lot in scopes["asset_library"], \
        "le repertoire de lecons du producteur n'est plus dans le perimetre"
    manquants = [p for p in scopes["asset_library"] if not (REPO / p).exists()]
    inattendus = [p for p in manquants if p != produit_au_premier_lot]
    assert not inattendus, f"perimetre citant des chemins absents : {inattendus}"
    if produit_au_premier_lot in manquants:
        pytest.xfail(f"NOT_YET_PRODUCED (TOOLS/validate_v2.py, v1_surfaces) : "
                     f"{produit_au_premier_lot} — cree par analyze_batch au premier lot, "
                     "jamais artificiellement")


def test_le_perimetre_couvre_le_chantier_reel():
    """Si un fichier du chantier tombe hors perimetre, la garde le refuserait a tort."""
    scopes = G.load_scopes()["asset_library"]
    attendus = [
        "forge/asset_geometry/oracle.py",
        "forge/asset_producer/qwen_spec.py",
        "knowledge_base/assets/props3d/gen_crate_wood_01.glb",
        "knowledge_base/proposals/asset.gen_chest_01.yaml",
        "EVIDENCE/bundles/asset_lessons/batch_constraints.json",
        "docs/forge/ASSET_LEARNING_LOOP_V1_SPEC.md",
    ]
    ok, dehors = G.check(attendus, scopes)
    assert ok, f"le chantier deborde son propre perimetre : {dehors}"


def test_le_perimetre_n_autorise_pas_les_chantiers_voisins():
    scopes = G.load_scopes()["asset_library"]
    voisins = ["GAMES/pacman/main.tscn", "studio_brain/00_CURRENT_CONTEXT.md",
               "forge/dispatch.py", "EVIDENCE/runs/pacman/verdict.json"]
    ok, dehors = G.check(voisins, scopes)
    assert not ok
    assert set(dehors) == set(voisins), "un chantier voisin passerait la garde"


def test_commit_scopes_est_du_json_valide():
    data = json.loads((REPO / "forge/commit_scopes.json").read_text(encoding="utf-8"))
    assert data["schema_version"] == "1.0"
    assert isinstance(data["scopes"], dict) and data["scopes"]

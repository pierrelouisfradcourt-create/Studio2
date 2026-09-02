"""Gel du jeu de règles (C1/C2) — l'auto-correction ne peut re-pointer que des
fonctions, jamais changer l'ensemble des règles (features)."""
import json
from pathlib import Path

from forge.static_oracles import (
    check_feature_set_frozen,
    frozen_features_from_wiremap,
    load_frozen_features,
)

WM = {
    "features": [
        {"feature": "R1 avance auto", "fonction": "step"},
        {"feature": "R2 saut", "fonction": "jump"},
        {"feature": "R3 collecte", "fonction": "collectCoin"},
    ]
}
FROZEN = ["R1 avance auto", "R2 saut", "R3 collecte"]


def test_extraction_features():
    assert frozen_features_from_wiremap(WM) == ["R1 avance auto", "R2 saut", "R3 collecte"]


def test_jeu_identique_passe():
    res = check_feature_set_frozen(WM, FROZEN)
    assert res["passed"] is True
    assert res["checked"] is True
    assert res["ajoutees"] == [] and res["supprimees"] == []


def test_regle_ajoutee_rejete():
    wm = {"features": WM["features"] + [{"feature": "R4 triche", "fonction": "x"}]}
    res = check_feature_set_frozen(wm, FROZEN)
    assert res["passed"] is False
    assert res["ajoutees"] == ["R4 triche"]
    assert res["supprimees"] == []


def test_regle_supprimee_rejete():
    wm = {"features": WM["features"][:2]}  # R3 collecte retirée
    res = check_feature_set_frozen(wm, FROZEN)
    assert res["passed"] is False
    assert res["supprimees"] == ["R3 collecte"]
    assert res["ajoutees"] == []


def test_reference_absente_checked_false():
    res = check_feature_set_frozen(WM, None)
    assert res["passed"] is False
    assert res["checked"] is False


def test_renommage_fonction_sans_toucher_regles_passe():
    # Le builder a renommé step->avancer : le jeu de règles est intact -> gel PASS
    # (c'est check_wiremap, séparé, qui signalera le renommage de fonction).
    wm = {"features": [
        {"feature": "R1 avance auto", "fonction": "avancer"},
        {"feature": "R2 saut", "fonction": "sauter"},
        {"feature": "R3 collecte", "fonction": "ramasser"},
    ]}
    res = check_feature_set_frozen(wm, FROZEN)
    assert res["passed"] is True


def test_reference_vide_checked_false():
    # Jeu à zéro règle (référence gelée vide) : pas d'ancre => pas un faux vert.
    res = check_feature_set_frozen({"features": []}, [])
    assert res["passed"] is False
    assert res["checked"] is False


def test_feature_vide_est_malforme():
    # Une règle sans identité (feature "") ne peut ancrer la traçabilité.
    wm = {"features": [{"feature": "R1 avance auto"}, {"feature": ""}, {"feature": "R3 collecte"}]}
    res = check_feature_set_frozen(wm, ["R1 avance auto", "", "R3 collecte"])
    assert res["passed"] is False


def test_doublon_feature_est_malforme():
    # Un doublon serait collapsé par set() et masquerait une suppression -> malformé.
    wm = {"features": [{"feature": "R1"}, {"feature": "R1"}, {"feature": "R2"}]}
    res = check_feature_set_frozen(wm, ["R1", "R2"])
    assert res["passed"] is False


def test_load_frozen_features(tmp_path):
    (tmp_path / "wiremap_frozen.json").write_text(
        json.dumps({"features": FROZEN}), encoding="utf-8"
    )
    assert load_frozen_features(tmp_path) == FROZEN


def test_load_frozen_absent_renvoie_none(tmp_path):
    assert load_frozen_features(tmp_path) is None


def test_load_frozen_json_corrompu_renvoie_none(tmp_path):
    (tmp_path / "wiremap_frozen.json").write_text("{pas du json", encoding="utf-8")
    assert load_frozen_features(tmp_path) is None


def test_load_frozen_features_non_liste_renvoie_none(tmp_path):
    (tmp_path / "wiremap_frozen.json").write_text(
        json.dumps({"features": "R1"}), encoding="utf-8"
    )
    assert load_frozen_features(tmp_path) is None

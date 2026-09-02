"""Matérialisation des artefacts amont structurés (prisme.json, featuremap.json).

Même régime que la validation de schéma F2a déjà en place pour blueprint/wiremap/
worldscan : le schéma est vérifié AVANT toute écriture, un artefact inexploitable
n'atteint jamais le disque, et l'échec porte sa raison.

Ces deux entrées de `_ARTIFACT_BY_STEP` sont ce qui rend s1-prisme et s3-decompo
MESURABLES : sans artefact déterministe, aucun oracle ne peut les juger et aucune
substitution de worker ne peut être décidée sur preuve.

    PYTHONPATH=scripts .venv312/Scripts/python.exe -m pytest \
        forge/tests/test_run_real_upstream_artifacts.py -v
"""
import json

import forge.run_real as run_real


def _bloc(payload: dict) -> str:
    return "```json\n" + json.dumps(payload, ensure_ascii=False) + "\n```"


_EXIGENCE_OK = {
    "id": "ex.clic",
    "source": "EXPECTED",
    "source_role": "joueur",
    "reference": "https://exemple.test/wiki",
    "observation": "Le clic incremente un compteur visible.",
    "enonce": "Un clic incremente le compteur d'au moins une unite.",
    "expected_proof": {"kind": "bot_action", "statement": "Un clic : compteur += gain_par_clic."},
    "destination": "s3-decompo",
}

_FEUILLE_OK = {
    "id": "cap.clic.increment",
    "capacite": "Incrementer le compteur au clic.",
    "source_ref": "ex.clic",
    "expected_proof": {"kind": "bot_action", "statement": "Un clic : compteur += gain_par_clic."},
}


def _featuremap(capacites) -> dict:
    return {
        "game_id": "cookie_clicker",
        "systemes": [{"id": "game_state", "features": [{"id": "feat.cookie", "capacites": capacites}]}],
    }


# --- la table de matérialisation ----------------------------------------------------

def test_les_deux_etapes_amont_sont_dans_la_table():
    """Sans entrée ici, l'étape ne produit que du texte libre : non mesurable."""
    assert run_real._ARTIFACT_BY_STEP["s1-prisme"] == "prisme.json"
    assert run_real._ARTIFACT_BY_STEP["s3-decompo"] == "featuremap.json"
    assert "prisme.json" in run_real._ARTIFACT_VALIDATORS
    assert "featuremap.json" in run_real._ARTIFACT_VALIDATORS


# --- prisme.json --------------------------------------------------------------------

def test_prisme_valide_ecrit_le_fichier(tmp_path):
    res = run_real._materialize_artifact(
        "s1-prisme", _bloc({"game_id": "cookie_clicker", "exigences": [_EXIGENCE_OK]}),
        tmp_path / "run")
    assert res is None
    ecrit = json.loads((tmp_path / "run" / "prisme.json").read_text(encoding="utf-8"))
    assert ecrit["exigences"][0]["id"] == "ex.clic"


def test_prisme_sans_exigences_rejete_aucun_fichier_ecrit(tmp_path):
    res = run_real._materialize_artifact(
        "s1-prisme", _bloc({"game_id": "x", "exigences": []}), tmp_path / "run")
    assert res is not None and res["ok"] is False
    assert "NON VIDE" in res["reason"]
    assert not (tmp_path / "run" / "prisme.json").exists()


def test_prisme_source_core_rejete_avant_ecriture(tmp_path):
    """Une sortie de modèle ne peut pas revendiquer CORE : l'origine d'une exigence
    CORE est `core_list` par construction (mesuré 2026-08-03). Le fichier ne doit
    même pas exister."""
    ex = dict(_EXIGENCE_OK, source="CORE")
    res = run_real._materialize_artifact(
        "s1-prisme", _bloc({"game_id": "x", "exigences": [ex]}), tmp_path / "run")
    assert res is not None and res["ok"] is False
    assert "CORE" in res["reason"]
    assert not (tmp_path / "run" / "prisme.json").exists()


def test_prisme_exigence_sans_id_rejete(tmp_path):
    ex = dict(_EXIGENCE_OK, id="  ")
    res = run_real._materialize_artifact(
        "s1-prisme", _bloc({"game_id": "x", "exigences": [ex]}), tmp_path / "run")
    assert res is not None and "id" in res["reason"]


def test_prisme_sans_bloc_json_rejete(tmp_path):
    res = run_real._materialize_artifact(
        "s1-prisme", "Voici mon prisme en prose, sans aucun bloc structure.",
        tmp_path / "run")
    assert res is not None and res["ok"] is False
    assert not (tmp_path / "run" / "prisme.json").exists()


# --- featuremap.json ----------------------------------------------------------------

def test_featuremap_valide_ecrit_le_fichier(tmp_path):
    res = run_real._materialize_artifact(
        "s3-decompo", _bloc(_featuremap([_FEUILLE_OK])), tmp_path / "run")
    assert res is None
    ecrit = json.loads((tmp_path / "run" / "featuremap.json").read_text(encoding="utf-8"))
    assert ecrit["systemes"][0]["features"][0]["capacites"][0]["id"] == "cap.clic.increment"


def test_featuremap_sans_systemes_rejete(tmp_path):
    res = run_real._materialize_artifact(
        "s3-decompo", _bloc({"game_id": "x", "systemes": []}), tmp_path / "run")
    assert res is not None and "NON VIDE" in res["reason"]
    assert not (tmp_path / "run" / "featuremap.json").exists()


def test_featuremap_systeme_sans_feature_rejete(tmp_path):
    res = run_real._materialize_artifact(
        "s3-decompo", _bloc({"game_id": "x", "systemes": [{"id": "s", "features": []}]}),
        tmp_path / "run")
    assert res is not None and "ne décompose rien" in res["reason"]


def test_featuremap_feature_sans_feuille_rejetee_avant_ecriture(tmp_path):
    """Une feature sans feuille rendrait vacuement verts les oracles d'aval :
    blueprint et wiremap mesurent leur couverture PAR RAPPORT à ces feuilles."""
    res = run_real._materialize_artifact(
        "s3-decompo", _bloc(_featuremap([])), tmp_path / "run")
    assert res is not None and res["ok"] is False
    assert "aucune preuve" in res["reason"]
    assert not (tmp_path / "run" / "featuremap.json").exists()


# --- non-régression : les 3 artefacts historiques sont intouchés --------------------

def test_les_artefacts_historiques_restent_materialises(tmp_path):
    assert run_real._ARTIFACT_BY_STEP["s2-worldscan"] == "worldscan.json"
    assert run_real._ARTIFACT_BY_STEP["s4-archi"] == "blueprint.json"
    assert run_real._ARTIFACT_BY_STEP["s5-wiremap"] == "wiremap.json"
    res = run_real._materialize_artifact(
        "s4-archi",
        _bloc({"modules": ["a", "b"], "deps_interdites": [["a", "b"]]}),
        tmp_path / "run")
    assert res is None
    assert (tmp_path / "run" / "blueprint.json").exists()

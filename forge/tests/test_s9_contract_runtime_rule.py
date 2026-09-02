# Test rouge->vert — Task 5 du lot 2026-08-22 kitten_clicker V3 (assemblage runtime).
# Verifie que le contrat s9-build-godot-standard.yaml porte desormais la regle
# d'assemblage runtime (main.tscn = point d'entree JOUABLE, runtime_alive, garde
# anti-pieces-sans-assemblage) et que tasks.json porte le texte ASSEMBLAGE OBLIGATOIRE
# pour la cle s9-build-godot-standard.
import json
from pathlib import Path

import yaml

REPO = Path(__file__).resolve().parents[2]
CONTRACT = REPO / "forge" / "contracts" / "s9-build-godot-standard.yaml"
TASKS = REPO / "EVIDENCE" / "runs" / "kitten_clicker" / "tasks.json"


def _load_contract() -> dict:
    return yaml.safe_load(CONTRACT.read_text(encoding="utf-8"))


def test_objectif_mentionne_main_tscn_point_d_entree_jouable():
    data = _load_contract()
    objectif = data["objectif"]
    assert "main.tscn" in objectif
    assert "point d'entrée JOUABLE" in objectif or "point d'entree JOUABLE" in objectif


def test_gardefou_porte_la_regle_assemblage():
    data = _load_contract()
    garde = data["gardeFou"]
    assert "PAS DE PIÈCES SANS ASSEMBLAGE" in garde or "PAS DE PIECES SANS ASSEMBLAGE" in garde


def test_success_criteria_cite_runtime_alive_et_preuve():
    data = _load_contract()
    success = data["success_criteria"]
    assert "runtime_alive" in success
    assert "res://main.tscn" in success
    assert "preuve" in success


def test_tests_oracles_cite_run_runtime_alive():
    data = _load_contract()
    assert "run_runtime_alive" in data["tests_oracles"]


def test_tasks_json_s9_porte_assemblage_obligatoire():
    data = json.loads(TASKS.read_text(encoding="utf-8"))
    task = data["s9-build-godot-standard"]
    assert "ASSEMBLAGE OBLIGATOIRE" in task
    assert "load_registries()" in task
    assert "play_sfx" in task

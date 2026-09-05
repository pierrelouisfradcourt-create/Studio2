# Test rouge->vert — Tasks 3/4 du lot 2026-08-22 kitten_clicker V4 (game loop).
# Verifie que le contrat s9-build-godot-standard.yaml porte desormais la regle de
# boucle joueur (loop.json derive du Prisme, affordances/hud groupes, garde anti-
# contournement, guidage objectif/next_goal) et que tasks.json porte les textes
# "BOUCLE JOUEUR OBLIGATOIRE" (s9) et "SUJET PLAYER" (s1) requis par le plan.
import json
from pathlib import Path

import yaml

from forge.run_real import load_tasks_file

REPO = Path(__file__).resolve().parents[2]
CONTRACT = REPO / "forge" / "contracts" / "s9-build-godot-standard.yaml"
# Fixture V1 migrée le 2026-09-05 sous `EVIDENCE/_V1_FIXTURES/` (GO Pierre) : ces
# artefacts viennent de runs V1 jamais rejoués, ils ne sont PAS des preuves V2 et
# vivent donc à l'écart de `EVIDENCE/runs/`. Voir le README de ce dossier.
TASKS = REPO / "EVIDENCE" / "_V1_FIXTURES" / "runs" / "kitten_clicker" / "tasks.json"


def _load_contract() -> dict:
    return yaml.safe_load(CONTRACT.read_text(encoding="utf-8"))


def test_objectif_mentionne_loop_json_et_groupe_affordance():
    data = _load_contract()
    objectif = data["objectif"]
    assert "loop.json" in objectif
    assert "groupe `affordance`" in objectif


def test_gardefou_porte_seules_entrees_et_guidage():
    data = _load_contract()
    garde = data["gardeFou"]
    assert "LES SEULES ENTRÉES D'UN JOUEUR" in garde or "LES SEULES ENTREES D'UN JOUEUR" in garde
    assert "GUIDAGE" in garde


def test_success_criteria_cite_player_loop_sha256_et_api():
    data = _load_contract()
    success = data["success_criteria"]
    assert "player_loop" in success
    assert "sha256" in success
    assert "api_*" in success


def test_tests_oracles_cite_run_player_loop():
    data = _load_contract()
    assert "run_player_loop" in data["tests_oracles"]


def test_tasks_json_s9_porte_boucle_joueur_obligatoire():
    data = json.loads(TASKS.read_text(encoding="utf-8"))
    task = data["s9-build-godot-standard"]
    assert "BOUCLE JOUEUR OBLIGATOIRE" in task
    assert "09_WIREMAP" in task


def test_tasks_json_s1_porte_sujet_player():
    data = json.loads(TASKS.read_text(encoding="utf-8"))
    task = data["s1-prisme"]
    assert "SUJET PLAYER" in task
    assert "loop_role" in task


def test_tasks_json_est_json_valide():
    data = json.loads(TASKS.read_text(encoding="utf-8"))
    assert isinstance(data, dict)


def test_load_tasks_file_accepte_les_cles_valides():
    tasks = load_tasks_file(TASKS)
    assert "s9-build-godot-standard" in tasks
    assert "s1-prisme" in tasks
    assert "BOUCLE JOUEUR OBLIGATOIRE" in tasks["s9-build-godot-standard"]
    assert "SUJET PLAYER" in tasks["s1-prisme"]

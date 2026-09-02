"""Gate s10a `runtime_alive` (Task 2, lot V3 assemblage runtime, 2026-08-22) :
« le runtime mort = FAIL, jamais un OK par absence ». Deux pièces sous test,
patron de `test_driver_amont_traversal_advisory.py` (`ForgeDriver.__new__`,
pas de vrai binaire Godot, pas de vrai process) :

  1. `ForgeDriver._runtime_alive_detail` — détection + activation de la sonde
     (SKIPPED motivé sans `run/main_scene`, NOT_MEASURED motivé si le runner
     injecté lève, pass-through de la mesure réelle sinon).
  2. `ForgeDriver._code_oracle_runtime_dead` — la règle d'agrégation pure
     câblée aux TROIS points de décision de `_run_code_oracle`
     (régime historique + les deux branches du régime descripteur) : un
     `runtime_alive` réellement `checked` et `passed=False` fait échouer le
     gate même si tout le reste est vert ; NOT_MEASURED/SKIPPED ne changent
     rien.
"""
from pathlib import Path

from forge.driver import ForgeDriver


def _driver_minimal(game_dir: Path) -> ForgeDriver:
    d = ForgeDriver.__new__(ForgeDriver)  # pas de __init__ : on ne teste que la méthode
    d.run_id = "r1"
    d.game_dir = game_dir
    return d


def _with_main_scene(game_dir: Path) -> Path:
    game_dir.mkdir(parents=True, exist_ok=True)
    (game_dir / "project.godot").write_text(
        '[application]\nconfig/name="g"\nrun/main_scene="res://main.tscn"\n',
        encoding="utf-8",
    )
    return game_dir


# --- _runtime_alive_detail --------------------------------------------------


def test_pas_de_main_scene_sonde_jamais_appelee_skipped(tmp_path):
    game = tmp_path / "game"
    game.mkdir()
    (game / "project.godot").write_text('[application]\nconfig/name="g"\n', encoding="utf-8")
    calls = []
    d = _driver_minimal(game)
    d.runtime_alive_runner = lambda gd: calls.append(gd) or {"status": "OK", "passed": True, "checked": True}
    r = d._runtime_alive_detail()
    assert calls == []
    assert r == {"status": "SKIPPED", "checked": False, "passed": False,
                 "reason": "pas de run/main_scene (module bibliothèque)"}


def test_project_godot_absent_est_traite_comme_module_bibliotheque(tmp_path):
    game = tmp_path / "game"
    game.mkdir()  # aucun project.godot
    calls = []
    d = _driver_minimal(game)
    d.runtime_alive_runner = lambda gd: calls.append(gd) or {"status": "OK", "passed": True, "checked": True}
    r = d._runtime_alive_detail()
    assert calls == []
    assert r["status"] == "SKIPPED" and r["checked"] is False


def test_main_scene_present_le_runner_est_appele_et_son_resultat_passe_tel_quel(tmp_path):
    game = _with_main_scene(tmp_path / "game")
    calls = []
    payload = {"status": "FAIL", "passed": False, "checked": True,
               "fails": ["aucun changement d'image apres le clic"], "payload": {},
               "mode_execution": "gpu_window", "fichier": "runtime_alive.gd"}
    d = _driver_minimal(game)
    d.runtime_alive_runner = lambda gd: calls.append(gd) or payload
    r = d._runtime_alive_detail()
    assert calls == [game]
    assert r == payload


def test_runner_qui_leve_donne_not_measured_jamais_une_exception(tmp_path):
    game = _with_main_scene(tmp_path / "game")

    def boom(gd):
        raise RuntimeError("panne fabriquée")

    d = _driver_minimal(game)
    d.runtime_alive_runner = boom
    r = d._runtime_alive_detail()  # ne doit jamais lever
    assert r["status"] == "NOT_MEASURED"
    assert r["checked"] is False and r["passed"] is False
    assert r["reason"]


# --- _code_oracle_runtime_dead ----------------------------------------------


def test_runtime_dead_quand_checked_et_non_passed():
    detail = {"runtime_alive": {"status": "FAIL", "checked": True, "passed": False}}
    assert ForgeDriver._code_oracle_runtime_dead(detail) is True


def test_runtime_dead_faux_quand_checked_et_passed():
    detail = {"runtime_alive": {"status": "OK", "checked": True, "passed": True}}
    assert ForgeDriver._code_oracle_runtime_dead(detail) is False


def test_runtime_dead_faux_quand_not_measured():
    detail = {"runtime_alive": {"status": "NOT_MEASURED", "checked": False, "passed": False}}
    assert ForgeDriver._code_oracle_runtime_dead(detail) is False


def test_runtime_dead_faux_quand_skipped():
    detail = {"runtime_alive": {"status": "SKIPPED", "checked": False, "passed": False}}
    assert ForgeDriver._code_oracle_runtime_dead(detail) is False


def test_runtime_dead_faux_quand_absent_du_detail():
    assert ForgeDriver._code_oracle_runtime_dead({}) is False


# --- câblage dans _run_code_oracle (via les trois blocs d'agrégation) ------
# Reproduit la structure des trois blocs `if status == "BLOCKED": ... elif
# (... or runtime_dead): final = "FAIL" ... else: final = "OK"` sans rejouer
# tout `_run_code_oracle` (mocker le gate complet est hors de portée de ce
# test unitaire — voir docstring du module).


def _aggregate(status, e2e_ok, solvability_passed, harness_flags_passed, runtime_alive, *, receipt_status="OK"):
    detail = {"runtime_alive": runtime_alive}
    runtime_dead = ForgeDriver._code_oracle_runtime_dead(detail)
    if status == "BLOCKED":
        return "BLOCKED"
    if (status == "FAIL" or not e2e_ok or not solvability_passed
            or not harness_flags_passed or receipt_status != "OK" or runtime_dead):
        return "FAIL"
    return "OK"


def test_final_fail_meme_si_tout_le_reste_est_vert():
    final = _aggregate("OK", True, True, True,
                        {"status": "FAIL", "checked": True, "passed": False})
    assert final == "FAIL"


def test_final_inchange_quand_not_measured():
    final = _aggregate("OK", True, True, True,
                        {"status": "NOT_MEASURED", "checked": False, "passed": False})
    assert final == "OK"


def test_final_inchange_quand_skipped():
    final = _aggregate("OK", True, True, True,
                        {"status": "SKIPPED", "checked": False, "passed": False})
    assert final == "OK"

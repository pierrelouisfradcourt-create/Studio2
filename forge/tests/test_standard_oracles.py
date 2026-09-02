"""Les 6 oracles déterministes du STANDARD Forge (`forge/standard/`).

Le livrable, ce sont les échecs : pour chaque oracle, au moins un PASS et au moins deux
FAIL ciblant des violations DIFFÉRENTES, plus les cas de robustesse (entrée vide,
non-dict, type inattendu). Aucun oracle ne lève d'exception sur une entrée malformée
(même doctrine que `static_oracles.check_architecture` / `check_charter`).

Ce module ne branche RIEN dans le driver : autonome, testé isolément.
"""
from pathlib import Path

import pytest
import yaml

from forge.standard_oracles import (
    check_budget,
    check_collisions,
    check_contract_completeness,
    check_index,
    check_line_states,
    check_placement,
)

STANDARD_DIR = Path(__file__).resolve().parents[1] / "standard"


def _write(root: Path, rel: str, code: str) -> None:
    p = root / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(code, encoding="utf-8")


# =======================================================================================
# 1. check_contract_completeness
# =======================================================================================


def _valid_game_contract(**overrides) -> dict:
    base = {
        "schema_version": 1,
        "game_id": "pong",
        "node": 1,
        "runtimes": ["rules", "browser", "godot"],
        "budget": {"reuses": [], "adds": ["game_loop"]},
        "assets": {"plan": "cc0"},
    }
    base.update(overrides)
    return base


def _valid_system_contract(**overrides) -> dict:
    base = {
        "schema_version": 1,
        "id": "game_loop",
        "category": "system",
        "provides": ["game.loop"],
        "requires": ["game.state"],
        "owner": True,
        "dependencies": [],
        "tests": ["07_TESTS/unit/game_loop.test.mjs"],
    }
    base.update(overrides)
    return base


def test_contract_completeness_game_pass():
    rep = check_contract_completeness(_valid_game_contract(), "game")
    assert rep["passed"] is True
    assert rep["violations"] == []


def test_contract_completeness_system_pass():
    rep = check_contract_completeness(_valid_system_contract(), "system")
    assert rep["passed"] is True
    assert rep["violations"] == []


def test_contract_completeness_missing_required_field_fail():
    contract = _valid_game_contract()
    del contract["node"]
    rep = check_contract_completeness(contract, "game")
    assert rep["passed"] is False
    assert any("node" in v for v in rep["violations"])


def test_contract_completeness_unknown_field_fail():
    contract = _valid_system_contract()
    contract["nouveau_champ_libre"] = "surprise"
    rep = check_contract_completeness(contract, "system")
    assert rep["passed"] is False
    assert any("nouveau_champ_libre" in v and "inconnu" in v for v in rep["violations"])


def test_contract_completeness_nested_budget_unknown_field_fail():
    contract = _valid_game_contract()
    contract["budget"]["surprise"] = True
    rep = check_contract_completeness(contract, "game")
    assert rep["passed"] is False
    assert any("budget" in v and "surprise" in v for v in rep["violations"])


def test_contract_completeness_kind_unsupported_is_explicit_violation_not_crash():
    # entity/level ne sont pas écrits par le standard v1 (SCHEMA.md §0) — doit rester
    # un FAIL propre, jamais une exception.
    rep = check_contract_completeness(_valid_game_contract(), "entity")
    assert rep["passed"] is False
    assert any("entity" in v for v in rep["violations"])


def test_contract_completeness_non_dict_input_no_crash():
    for bad in (None, [], "pong", 42):
        rep = check_contract_completeness(bad, "game")
        assert rep["passed"] is False
        assert rep["violations"]


def test_contract_completeness_wrong_type_field_fail():
    contract = _valid_game_contract(node="un")  # devrait être un int
    rep = check_contract_completeness(contract, "game")
    assert rep["passed"] is False
    assert any("node" in v for v in rep["violations"])


def test_contract_completeness_assets_plan_out_of_vocabulary_fail():
    contract = _valid_game_contract()
    contract["assets"] = {"plan": "midjourney"}  # hors {cc0, generated}
    rep = check_contract_completeness(contract, "game")
    assert rep["passed"] is False
    assert any("assets" in v and "plan" in v for v in rep["violations"])


def test_contract_completeness_real_pong_yaml_files_when_present():
    # Ancrage sur des fixtures réelles si elles existent déjà dans le worktree —
    # sinon ce test est un no-op silencieux (aucun claim non prouvé).
    candidate = STANDARD_DIR.parent.parent.parent / "GAMES" / "pong" / "00_CHARTER" / "game_contract.yaml"
    if not candidate.exists():
        pytest.skip("aucun game_contract.yaml réel dans ce worktree — test d'ancrage no-op")
    data = yaml.safe_load(candidate.read_text(encoding="utf-8"))
    rep = check_contract_completeness(data, "game")
    assert isinstance(rep["passed"], bool)


# =======================================================================================
# 2. check_budget
# =======================================================================================


def test_budget_pass_valid_reuse_and_single_add():
    contract = _valid_game_contract(budget={"reuses": ["paddle_render"], "adds": ["game_loop"]})
    library_index = {"paddle_render": {"tier": "validated"}}
    rep = check_budget(contract, ["game_loop", "paddle_render"], library_index)
    assert rep["passed"] is True
    assert rep["empilement_violee"] is False
    assert rep["reuses_invalides"] == []
    assert rep["hors_budget"] == []
    assert rep["chevauchement"] == []


def test_budget_empilement_violee_fail():
    contract = _valid_game_contract(budget={"reuses": [], "adds": ["game_loop", "collision"]})
    rep = check_budget(contract, ["game_loop", "collision"], {})
    assert rep["passed"] is False
    assert rep["empilement_violee"] is True


def test_budget_brique_hors_budget_fail():
    # CAS EXIGÉ : une brique déposée qui n'est ni dans reuses ni dans adds.
    contract = _valid_game_contract(budget={"reuses": [], "adds": ["game_loop"]})
    rep = check_budget(contract, ["game_loop", "un_fichier_non_declare"], {})
    assert rep["passed"] is False
    assert rep["hors_budget"] == ["un_fichier_non_declare"]


def test_budget_reuse_non_validated_tier_fail():
    contract = _valid_game_contract(budget={"reuses": ["draft_brick"], "adds": []})
    library_index = {"draft_brick": {"tier": "experimental"}}
    rep = check_budget(contract, ["draft_brick"], library_index)
    assert rep["passed"] is False
    assert rep["reuses_invalides"] == ["draft_brick"]


def test_budget_reuse_absent_de_bibliotheque_fail():
    contract = _valid_game_contract(budget={"reuses": ["inconnu"], "adds": []})
    rep = check_budget(contract, ["inconnu"], {})
    assert rep["passed"] is False
    assert rep["reuses_invalides"] == ["inconnu"]


def test_budget_chevauchement_reuses_adds_fail():
    contract = _valid_game_contract(budget={"reuses": ["game_loop"], "adds": ["game_loop"]})
    library_index = {"game_loop": {"tier": "validated"}}
    rep = check_budget(contract, ["game_loop"], library_index)
    assert rep["passed"] is False
    assert rep["chevauchement"] == ["game_loop"]


def test_budget_non_dict_contract_no_crash():
    rep = check_budget(None, ["x"], {})
    assert rep["passed"] is False
    assert "raison" in rep


def test_budget_missing_budget_key_no_crash():
    rep = check_budget({"game_id": "pong"}, [], {})
    assert rep["passed"] is False
    assert "raison" in rep


def test_budget_deposited_bricks_wrong_type_no_crash():
    contract = _valid_game_contract()
    rep = check_budget(contract, "game_loop", {})  # str au lieu de list -> traité comme []
    assert isinstance(rep["hors_budget"], list)
    assert rep["hors_budget"] == []  # rien à vérifier : entrée malformée neutralisée, pas de crash


def test_budget_library_index_wrong_type_no_crash():
    contract = _valid_game_contract(budget={"reuses": ["x"], "adds": []})
    rep = check_budget(contract, ["x"], "pas un dict")
    assert rep["passed"] is False
    assert rep["reuses_invalides"] == ["x"]


def test_budget_promise_add_never_deposited_fail():
    # RÉCIPROQUE EXIGÉE (décision Pierre 2026-07-23) : une brique promise dans `adds`
    # mais JAMAIS déposée est une violation. Ferme la tautologie : sans ce contrôle,
    # `budget={reuses:[], adds:[game_loop]}` avec `deposited=[]` passait au vert.
    contract = _valid_game_contract(budget={"reuses": [], "adds": ["game_loop"]})
    rep = check_budget(contract, [], {})
    assert rep["passed"] is False
    assert rep["promis_non_depose"] == ["game_loop"]
    # la direction historique reste propre : rien de déposé, donc rien hors budget.
    assert rep["hors_budget"] == []


def test_budget_promise_add_deposited_pass():
    # Contrôle positif jumeau : la même promesse, mais tenue (game_loop déposé).
    contract = _valid_game_contract(budget={"reuses": [], "adds": ["game_loop"]})
    rep = check_budget(contract, ["game_loop"], {})
    assert rep["passed"] is True
    assert rep["promis_non_depose"] == []


# =======================================================================================
# 3. check_line_states
# =======================================================================================


def _core_requirements(*ids) -> dict:
    return {"requirements": [{"id": i, "capability": i} for i in ids]}


def _line(**overrides) -> dict:
    base = {
        "id": "core.restart",
        "source": "CORE",
        "source_role": None,
        "reference": None,
        "provides": ["game.restart"],
        "requires": ["game.state"],
        "owner": True,
        "system_parent": "game_state",
        "address": "05_SYSTEMS/game_loop/",
        "state": "IMPLEMENTED",
        "reason": None,
        "until": None,
        "decider": None,
        "write_order": None,
    }
    base.update(overrides)
    return base


def test_line_states_pass_all_core_present_no_unknown():
    # REQUIRED est l'état NORMAL d'une ligne au moment du gel (SCHEMA.md §3) — IMPLEMENTED
    # y est désormais interdit (rien n'est encore fait avant build), cf.
    # test_line_states_implemented_at_freeze_fail ci-dessous pour la preuve inverse.
    wiremap = {"lines": [_line(id="core.restart", source="CORE", state="REQUIRED")]}
    rep = check_line_states(wiremap, _core_requirements("core.restart"), frozen=True)
    assert rep["passed"] is True


def test_line_states_unknown_at_freeze_fail():
    # CAS EXIGÉ : un squelette gelé contenant un UNKNOWN.
    wiremap = {"lines": [_line(id="core.restart", source="CORE", state="UNKNOWN")]}
    rep = check_line_states(wiremap, _core_requirements("core.restart"), frozen=True)
    assert rep["passed"] is False
    assert "core.restart" in rep["unknown_au_gel"]


def test_line_states_unknown_not_frozen_is_allowed():
    wiremap = {"lines": [_line(id="core.restart", source="CORE", state="UNKNOWN")]}
    rep = check_line_states(wiremap, _core_requirements("core.restart"), frozen=False)
    assert rep["unknown_au_gel"] == []
    assert rep["passed"] is True


def test_line_states_implemented_at_freeze_fail():
    # CAS EXIGÉ : au gel (avant build), rien n'est encore fait -> IMPLEMENTED interdit.
    wiremap = {"lines": [_line(id="core.restart", source="CORE", state="IMPLEMENTED")]}
    rep = check_line_states(wiremap, _core_requirements("core.restart"), frozen=True)
    assert rep["passed"] is False
    assert "core.restart" in rep["implemented_au_gel"]


def test_line_states_implemented_at_freeze_pass_when_not_frozen():
    # En brouillon (squelette pas encore gelé), IMPLEMENTED n'est pas encore jugé.
    wiremap = {"lines": [_line(id="core.restart", source="CORE", state="IMPLEMENTED")]}
    rep = check_line_states(wiremap, _core_requirements("core.restart"), frozen=False)
    assert rep["implemented_au_gel"] == []
    assert rep["passed"] is True


def test_line_states_required_after_build_fail():
    # CAS EXIGÉ : après build, tout ce qui était REQUIRED devait devenir IMPLEMENTED ou
    # BLOCKED -> un REQUIRED restant est une violation.
    wiremap = {"lines": [_line(id="core.restart", source="CORE", state="REQUIRED")]}
    rep = check_line_states(wiremap, _core_requirements("core.restart"), frozen="built")
    assert rep["passed"] is False
    assert "core.restart" in rep["required_apres_build"]


def test_line_states_required_at_freeze_is_the_normal_state():
    # Au gel (pas "built"), REQUIRED est l'état attendu -> pas de violation.
    wiremap = {"lines": [_line(id="core.restart", source="CORE", state="REQUIRED")]}
    rep = check_line_states(wiremap, _core_requirements("core.restart"), frozen=True)
    assert rep["required_apres_build"] == []
    assert rep["passed"] is True


def test_line_states_implemented_after_build_is_allowed():
    # Après build, IMPLEMENTED est le résultat normal -> pas de violation.
    wiremap = {"lines": [_line(id="core.restart", source="CORE", state="IMPLEMENTED")]}
    rep = check_line_states(wiremap, _core_requirements("core.restart"), frozen="built")
    assert rep["implemented_au_gel"] == []
    assert rep["required_apres_build"] == []
    assert rep["passed"] is True


def test_line_states_system_parent_missing_fail():
    # CAS EXIGÉ : chaque ligne doit porter system_parent (SCHEMA.md §3) — absent = violation.
    wiremap = {"lines": [_line(id="core.restart", source="CORE", state="REQUIRED", system_parent=None)]}
    rep = check_line_states(wiremap, _core_requirements("core.restart"), frozen=True)
    assert rep["passed"] is False
    assert "core.restart" in rep["system_parent_manquant"]


def test_line_states_system_parent_empty_string_fail():
    wiremap = {"lines": [_line(id="core.restart", source="CORE", state="REQUIRED", system_parent="")]}
    rep = check_line_states(wiremap, _core_requirements("core.restart"), frozen=True)
    assert rep["passed"] is False
    assert "core.restart" in rep["system_parent_manquant"]


def test_line_states_legacy_bool_frozen_still_supported():
    # Rétro-compatibilité de signature : l'ancien booléen `frozen=True/False` doit
    # continuer à fonctionner exactement comme avant (mode "frozen"/"draft").
    wiremap = {"lines": [_line(id="core.restart", source="CORE", state="REQUIRED")]}
    rep_true = check_line_states(wiremap, _core_requirements("core.restart"), frozen=True)
    rep_false = check_line_states(wiremap, _core_requirements("core.restart"), frozen=False)
    assert rep_true["passed"] is True
    assert rep_false["passed"] is True


def test_line_states_not_applicable_on_core_fail():
    # CAS EXIGÉ : un NOT_APPLICABLE posé sur une ligne CORE.
    wiremap = {"lines": [
        _line(id="core.audio", source="CORE", state="NOT_APPLICABLE", reason="jeu muet assume"),
    ]}
    rep = check_line_states(wiremap, _core_requirements("core.audio"), frozen=True)
    assert rep["passed"] is False
    assert "core.audio" in rep["not_applicable_sur_core"]


def test_line_states_not_applicable_without_reason_fail():
    wiremap = {"lines": [
        _line(id="expected.combo", source="EXPECTED", state="NOT_APPLICABLE",
              reason="", reference="wiki-pong", source_role="prisme"),
    ]}
    rep = check_line_states(wiremap, {"requirements": []}, frozen=True)
    assert rep["passed"] is False
    assert "expected.combo" in rep["not_applicable_sans_raison"]


def test_line_states_deferred_missing_until_and_decider_fail():
    wiremap = {"lines": [
        _line(id="core.audio", source="CORE", state="DEFERRED", until=None, decider=None),
    ]}
    rep = check_line_states(wiremap, _core_requirements("core.audio"), frozen=True)
    assert rep["passed"] is False
    assert "core.audio" in rep["deferred_incomplet"]


def test_line_states_deferred_with_until_and_decider_pass():
    wiremap = {"lines": [
        _line(id="core.audio", source="CORE", state="DEFERRED",
              until="node.2", decider="pierre"),
    ]}
    rep = check_line_states(wiremap, _core_requirements("core.audio"), frozen=True)
    assert rep["passed"] is True


def test_line_states_expected_without_reference_fail():
    # CAS EXIGÉ : une ligne EXPECTED sans référence externe.
    wiremap = {"lines": [
        _line(id="expected.serve_speed_up", source="EXPECTED", state="IMPLEMENTED",
              reference=None, source_role="prisme"),
    ]}
    rep = check_line_states(wiremap, {"requirements": []}, frozen=True)
    assert rep["passed"] is False
    assert "expected.serve_speed_up" in rep["expected_sans_reference"]


def test_line_states_expected_without_source_role_fail():
    wiremap = {"lines": [
        _line(id="expected.wall_bounce", source="EXPECTED", state="IMPLEMENTED",
              reference="wiki-pong", source_role=None),
    ]}
    rep = check_line_states(wiremap, {"requirements": []}, frozen=True)
    assert rep["passed"] is False
    assert "expected.wall_bounce" in rep["source_manquante"]


def test_line_states_additions_without_source_role_fail():
    wiremap = {"lines": [
        _line(id="add.combo_meter", source="ADDITIONS", state="IMPLEMENTED",
              reference=None, source_role=None),
    ]}
    rep = check_line_states(wiremap, {"requirements": []}, frozen=True)
    assert rep["passed"] is False
    assert "add.combo_meter" in rep["source_manquante"]


def test_line_states_invalid_state_value_fail():
    wiremap = {"lines": [_line(id="core.restart", source="CORE", state="DONE")]}
    rep = check_line_states(wiremap, _core_requirements("core.restart"), frozen=True)
    assert rep["passed"] is False
    assert any("core.restart" in x for x in rep["etats_invalides"])


def test_line_states_core_requirement_omitted_fail():
    # Omission silencieuse : core.exit exigé par le CORE, absent de la wiremap.
    wiremap = {"lines": [_line(id="core.restart", source="CORE", state="IMPLEMENTED")]}
    rep = check_line_states(wiremap, _core_requirements("core.restart", "core.exit"), frozen=True)
    assert rep["passed"] is False
    assert "core.exit" in rep["core_omis"]


def test_line_states_non_dict_wiremap_no_crash():
    rep = check_line_states(None, {}, frozen=True)
    assert rep["passed"] is False
    assert "raison" in rep


def test_line_states_lines_not_a_list_no_crash():
    rep = check_line_states({"lines": "pas une liste"}, {}, frozen=True)
    assert rep["passed"] is True  # aucune ligne exploitable, aucune violation détectée
    assert rep["etats_invalides"] == []


def test_line_states_line_not_a_dict_no_crash():
    rep = check_line_states({"lines": ["pas un mapping"]}, {}, frozen=True)
    assert rep["passed"] is False
    assert rep["etats_invalides"]


# =======================================================================================
# 4. check_placement
# =======================================================================================


def _repo_map() -> dict:
    return {
        "roots": {"systems": "05_SYSTEMS/"},
        "mapping": {
            "system": "05_SYSTEMS/{id}/",
            "entity.player": "02_ENTITIES/players/{id}/",
        },
    }


def test_placement_pass_coherent_address():
    wiremap = {"lines": [
        {"id": "game_loop", "category": "system", "address": "05_SYSTEMS/game_loop/"},
    ]}
    rep = check_placement(wiremap, _repo_map())
    assert rep["passed"] is True


def test_placement_missing_address_fail():
    wiremap = {"lines": [{"id": "game_loop", "category": "system", "address": ""}]}
    rep = check_placement(wiremap, _repo_map())
    assert rep["passed"] is False
    assert "game_loop" in rep["adresse_manquante"]


def test_placement_category_absent_from_table_fail():
    # Catégorie absente de la table = violation, jamais un placement par défaut.
    wiremap = {"lines": [
        {"id": "boss_ai", "category": "entity.boss.special", "address": "02_ENTITIES/bosses/boss_ai/"},
    ]}
    rep = check_placement(wiremap, _repo_map())
    assert rep["passed"] is False
    assert any("entity.boss.special" in x for x in rep["categorie_non_mappee"])


def test_placement_address_incoherent_with_category_fail():
    wiremap = {"lines": [
        {"id": "game_loop", "category": "system", "address": "06_RUNTIME/game_loop/"},
    ]}
    rep = check_placement(wiremap, _repo_map())
    assert rep["passed"] is False
    assert any("game_loop" in x for x in rep["adresse_incoherente"])


def test_placement_missing_category_fail():
    wiremap = {"lines": [{"id": "game_loop", "address": "05_SYSTEMS/game_loop/"}]}
    rep = check_placement(wiremap, _repo_map())
    assert rep["passed"] is False
    assert "game_loop" in rep["categorie_manquante"]


def test_placement_non_dict_wiremap_no_crash():
    rep = check_placement("pas un mapping", _repo_map())
    assert rep["passed"] is False
    assert "raison" in rep


def test_placement_repo_map_missing_mapping_no_crash():
    wiremap = {"lines": [{"id": "x", "category": "system", "address": "05_SYSTEMS/x/"}]}
    rep = check_placement(wiremap, {})
    assert rep["passed"] is False
    assert any("system" in v for v in rep["categorie_non_mappee"])


def test_placement_real_repo_map_yaml_loads_and_runs():
    data = yaml.safe_load(STANDARD_DIR.joinpath("repo_map.yaml").read_text(encoding="utf-8"))
    wiremap = {"lines": [{"id": "game_loop", "category": "system", "address": "05_SYSTEMS/game_loop/"}]}
    rep = check_placement(wiremap, data)
    assert rep["passed"] is True


def test_placement_system_parent_shared_by_several_lines_pass():
    # C'est le cas réel Pong : core.game_state, core.end_condition, core.restart vivent
    # tous dans le même système game_state -> même adresse dérivée, pas une incohérence.
    wiremap = {
        "systems": [{"id": "game_state", "category": "system", "allowed_deps": []}],
        "lines": [
            {"id": "core.game_state", "category": "system", "system_parent": "game_state",
             "address": "05_SYSTEMS/game_state/"},
            {"id": "core.end_condition", "category": "system", "system_parent": "game_state",
             "address": "05_SYSTEMS/game_state/"},
            {"id": "core.restart", "category": "system", "system_parent": "game_state",
             "address": "05_SYSTEMS/game_state/"},
        ],
    }
    rep = check_placement(wiremap, _repo_map())
    assert rep["passed"] is True
    assert rep["adresse_incoherente"] == []
    assert rep["system_parent_inconnu"] == []


def test_placement_system_parent_unknown_system_fail():
    # CAS EXIGÉ : system_parent qui ne désigne aucune entrée de wiremap["systems"].
    wiremap = {
        "systems": [{"id": "game_loop", "category": "system", "allowed_deps": []}],
        "lines": [
            {"id": "core.game_state", "category": "system", "system_parent": "systeme_fantome",
             "address": "05_SYSTEMS/systeme_fantome/"},
        ],
    }
    rep = check_placement(wiremap, _repo_map())
    assert rep["passed"] is False
    assert any("systeme_fantome" in x for x in rep["system_parent_inconnu"])


def test_placement_system_parent_wrong_address_derivation_fail():
    # system_parent valide mais l'adresse écrite ne dérive pas de lui (dérive de l'id de
    # la ligne à la place) -> incohérence.
    wiremap = {
        "systems": [{"id": "game_state", "category": "system", "allowed_deps": []}],
        "lines": [
            {"id": "core.restart", "category": "system", "system_parent": "game_state",
             "address": "05_SYSTEMS/core.restart/"},
        ],
    }
    rep = check_placement(wiremap, _repo_map())
    assert rep["passed"] is False
    assert any("core.restart" in x for x in rep["adresse_incoherente"])


def test_placement_system_category_not_in_repo_map_fail():
    # CAS EXIGÉ : la category d'un SYSTÈME (passe 1) doit exister dans repo_map.yaml.
    wiremap = {
        "systems": [{"id": "boss_arena", "category": "entity.boss.special", "allowed_deps": []}],
        "lines": [
            {"id": "core.game_state", "category": "system", "system_parent": "boss_arena",
             "address": "05_SYSTEMS/boss_arena/"},
        ],
    }
    rep = check_placement(wiremap, _repo_map())
    assert rep["passed"] is False
    assert any("boss_arena" in x for x in rep["systeme_categorie_non_mappee"])


def test_placement_no_system_parent_falls_back_to_line_id_for_backward_compat():
    # Wiremap sans system_parent (pré-existante) : dérivation par l'id de la ligne, comme
    # avant — aucune régression sur les cartes déjà gelées.
    wiremap = {"lines": [
        {"id": "game_loop", "category": "system", "address": "05_SYSTEMS/game_loop/"},
    ]}
    rep = check_placement(wiremap, _repo_map())
    assert rep["passed"] is True
    assert rep["system_parent_inconnu"] == []


# ---------------------------------------------------------------------------------------
# 4bis. check_placement — `fichiers[]` déclarés (schema_version: 2, trou fermé)
# ---------------------------------------------------------------------------------------


def _repo_map_with_tests() -> dict:
    return {
        "roots": {"systems": "05_SYSTEMS/", "tests": "07_TESTS/"},
        "mapping": {
            "system": "05_SYSTEMS/{id}/",
            "test.unit": "07_TESTS/unit/",
            "test.oracle": "07_TESTS/oracle/",
        },
    }


def test_placement_v2_fichiers_declared_and_well_placed_pass():
    # CAS EXIGÉ : tout déclaré et bien placé -> PASS.
    wiremap = {
        "schema_version": 2,
        "systems": [{"id": "game_loop", "category": "system", "allowed_deps": []}],
        "lines": [
            {
                "id": "core.main_loop", "category": "system", "system_parent": "game_loop",
                "address": "05_SYSTEMS/game_loop/",
                "fichiers": [
                    {"path": "05_SYSTEMS/game_loop/loop.mjs", "category": "system"},
                    {"path": "07_TESTS/unit/game_loop.test.mjs", "category": "test.unit"},
                ],
            },
        ],
    }
    rep = check_placement(wiremap, _repo_map_with_tests())
    assert rep["passed"] is True
    assert rep["categorie_fichier_non_declaree"] == []
    assert rep["categorie_fichier_non_mappee"] == []
    assert rep["fichier_adresse_incoherente"] == []


def test_placement_v2_fichier_declared_test_unit_but_placed_under_systems_fail():
    # CAS EXIGÉ : fichier déclaré category=test.unit mais posé sous 05_SYSTEMS/ (le cas
    # réel Pong : tests/oracle atterris sous 05_SYSTEMS/).
    wiremap = {
        "schema_version": 2,
        "lines": [
            {
                "id": "core.main_loop", "category": "system",
                "address": "05_SYSTEMS/game_loop/",
                "fichiers": [
                    {"path": "05_SYSTEMS/game_loop/loop.test.mjs", "category": "test.unit"},
                ],
            },
        ],
    }
    rep = check_placement(wiremap, _repo_map_with_tests())
    assert rep["passed"] is False
    assert any("core.main_loop" in x and "loop.test.mjs" in x for x in rep["fichier_adresse_incoherente"])


def test_placement_v2_fichier_bare_string_fail():
    # CAS EXIGÉ : entrée de `fichiers` restée une chaîne nue (ancien format) en
    # schema_version 2 -> le trou qu'on ferme, jamais accepté en silence.
    wiremap = {
        "schema_version": 2,
        "lines": [
            {
                "id": "core.main_loop", "category": "system",
                "address": "05_SYSTEMS/game_loop/",
                "fichiers": ["05_SYSTEMS/game_loop/loop.mjs"],
            },
        ],
    }
    rep = check_placement(wiremap, _repo_map_with_tests())
    assert rep["passed"] is False
    assert any("core.main_loop" in x for x in rep["categorie_fichier_non_declaree"])


def test_placement_v2_fichier_category_unknown_fail():
    # CAS EXIGÉ : category inconnue de la table -> jamais de placement par défaut.
    wiremap = {
        "schema_version": 2,
        "lines": [
            {
                "id": "core.main_loop", "category": "system",
                "address": "05_SYSTEMS/game_loop/",
                "fichiers": [
                    {"path": "05_SYSTEMS/game_loop/loop.mjs", "category": "widget.exotique"},
                ],
            },
        ],
    }
    rep = check_placement(wiremap, _repo_map_with_tests())
    assert rep["passed"] is False
    assert any("widget.exotique" in x for x in rep["categorie_fichier_non_mappee"])


def test_placement_v1_bare_string_fichiers_unchanged_no_violation():
    # RÉTROCOMPAT EXIGÉE : une wiremap schema_version 1 avec des fichiers en chaînes nues
    # ne subit AUCUN changement de comportement -- preuve de run passé.
    wiremap = {
        "schema_version": 1,
        "lines": [
            {
                "id": "game_loop", "category": "system",
                "address": "05_SYSTEMS/game_loop/",
                "fichiers": ["05_SYSTEMS/game_loop/loop.mjs", "05_SYSTEMS/whatever/leftover.test.mjs"],
            },
        ],
    }
    rep = check_placement(wiremap, _repo_map_with_tests())
    assert rep["passed"] is True
    assert rep["categorie_fichier_non_declaree"] == []
    assert rep["categorie_fichier_non_mappee"] == []
    assert rep["fichier_adresse_incoherente"] == []


def test_placement_v2_absent_schema_version_unchanged_no_violation():
    # Même garantie quand `schema_version` est complètement absent (pas seulement "1").
    wiremap = {
        "lines": [
            {
                "id": "game_loop", "category": "system",
                "address": "05_SYSTEMS/game_loop/",
                "fichiers": ["05_SYSTEMS/game_loop/loop.mjs"],
            },
        ],
    }
    rep = check_placement(wiremap, _repo_map_with_tests())
    assert rep["passed"] is True
    assert rep["categorie_fichier_non_declaree"] == []


def test_placement_v2_fichier_entry_non_dict_no_crash():
    # Robustesse : entrée ni chaîne ni mapping (int, None, liste) -> pas de crash.
    wiremap = {
        "schema_version": 2,
        "lines": [
            {
                "id": "game_loop", "category": "system",
                "address": "05_SYSTEMS/game_loop/",
                "fichiers": [42, None, ["nested"]],
            },
        ],
    }
    rep = check_placement(wiremap, _repo_map_with_tests())
    assert rep["passed"] is False
    assert len(rep["categorie_fichier_non_declaree"]) == 3


def test_placement_v2_fichiers_absent_no_crash():
    # Robustesse : pas de clé `fichiers` du tout -> aucune violation fichier, pas de crash.
    wiremap = {
        "schema_version": 2,
        "lines": [
            {"id": "game_loop", "category": "system", "address": "05_SYSTEMS/game_loop/"},
        ],
    }
    rep = check_placement(wiremap, _repo_map_with_tests())
    assert rep["passed"] is True
    assert rep["categorie_fichier_non_declaree"] == []


def test_placement_v2_fichier_path_empty_fail():
    # Robustesse : path vide sur une entrée-mapping par ailleurs correcte.
    wiremap = {
        "schema_version": 2,
        "lines": [
            {
                "id": "core.main_loop", "category": "system",
                "address": "05_SYSTEMS/game_loop/",
                "fichiers": [{"path": "", "category": "system"}],
            },
        ],
    }
    rep = check_placement(wiremap, _repo_map_with_tests())
    assert rep["passed"] is False
    assert any("core.main_loop" in x for x in rep["categorie_fichier_non_declaree"])


# ---------------------------------------------------------------------------------------
# 4ter. REPO_MAP_TEMPLATE_IDENTITY_V1 — identité obligatoire des gabarits d'artefacts
#       nommés (ratifié Pierre 2026-07-23).
#
#       « Un gabarit qui revendique un artefact concret doit porter un identifiant stable
#       permettant une correspondance univoque. Les motifs génériques sont réservés aux
#       catégories, pas aux preuves d'existence. »
#
#       Le livrable de cette tranche, ce sont les DEUX détections (`same_target_multiple_ids`,
#       `same_id_multiple_targets`) ET la preuve qu'une configuration légitime reste VERTE :
#       une règle qui rougit tout ne prouve rien.
# ---------------------------------------------------------------------------------------


def _repo_map_named_artifacts() -> dict:
    """Même FORME que la table réelle après la décision : `test.*`/`asset.*` portent
    `{id}` et ne se terminent pas par `/` (gabarits d'artefact nommé)."""
    return {
        "roots": {"systems": "05_SYSTEMS/", "tests": "07_TESTS/", "assets": "04_ASSETS/"},
        "mapping": {
            "system": "05_SYSTEMS/{id}/",
            "asset.audio": "04_ASSETS/audio/{id}",
            "asset.sprite": "04_ASSETS/sprites/{id}",
            "test.unit": "07_TESTS/unit/{id}",
            "test.oracle": "07_TESTS/oracle/{id}",
            "test.solvability": "07_TESTS/oracle/{id}",
        },
    }


def _wiremap_named(lines: list) -> dict:
    return {
        "schema_version": 2,
        "systems": [
            {"id": "game_loop", "category": "system", "allowed_deps": []},
            {"id": "game_state", "category": "system", "allowed_deps": []},
        ],
        "lines": lines,
    }


def test_repo_map_reel_tous_les_gabarits_test_et_asset_portent_un_id():
    """INVARIANT DE TABLE (`require_id: true`, `scope: [test.*, asset.*]`) : la règle
    ne peut pas s'appliquer si la table retombe sur un motif générique. C'est ici qu'on
    empêche la régression silencieuse de `repo_map.yaml`.

    MISE À JOUR RATIFIÉE (GO Pierre 2026-08-16) : le compte passe de 6 à 7 avec
    `asset.mesh` (décision D3, Pierre 2026-08-11 — la taxonomie d'assets était 2D
    alors que le parc produit de la 3D). Le compte en dur est VOLONTAIRE : il oblige
    toute catégorie neuve à passer par une ratification plutôt que d'entrer en
    silence. C'est le compte qui est mis à jour, PAS l'invariant — la boucle
    ci-dessous, qui exige `{id}` et refuse un gabarit de dossier, est inchangée et
    couvre `asset.mesh` comme les six autres."""
    data = yaml.safe_load(STANDARD_DIR.joinpath("repo_map.yaml").read_text(encoding="utf-8"))
    mapping = data["mapping"]
    en_scope = [c for c in mapping if c.startswith(("test.", "asset."))]
    assert len(en_scope) == 7, en_scope
    assert "asset.mesh" in en_scope, "asset.mesh doit etre dans le scope de la regle d'identite"
    for cat in en_scope:
        gabarit = mapping[cat]
        assert "{id}" in gabarit, f"{cat} : gabarit sans identité ({gabarit!r})"
        assert not gabarit.endswith("/"), f"{cat} : gabarit de dossier, pas d'artefact nommé"


def test_identity_same_target_multiple_ids_fail():
    """CAS EXIGÉ (`same_target_multiple_ids: FAIL`) — le cas réel Pong réduit à deux
    lignes : un même fichier de preuve revendiqué par deux lignes. Sans identité de
    gabarit, l'oracle ne voyait qu'un motif générique et laissait passer."""
    wiremap = _wiremap_named([
        {"id": "core.boot", "category": "system", "system_parent": "game_loop",
         "address": "05_SYSTEMS/game_loop/",
         "fichiers": [{"path": "07_TESTS/oracle/solvability.mjs",
                       "category": "test.solvability"}]},
        {"id": "core.restart", "category": "system", "system_parent": "game_state",
         "address": "05_SYSTEMS/game_state/",
         "fichiers": [{"path": "07_TESTS/oracle/solvability.mjs",
                       "category": "test.solvability"}]},
    ])
    rep = check_placement(wiremap, _repo_map_named_artifacts())
    assert rep["passed"] is False
    assert len(rep["revendications_multiples"]) == 1
    viol = rep["revendications_multiples"][0]
    # Pas de rustine « première correspondance » : le conflit est ÉNUMÉRÉ en entier.
    assert "07_TESTS/oracle/solvability.mjs" in viol
    assert "core.boot" in viol and "core.restart" in viol
    # aucun autre volet n'est perturbé — le fichier est bien placé, il est mal PARTAGÉ.
    assert rep["fichier_adresse_incoherente"] == []
    assert rep["identite_ambigue"] == []


def test_identity_same_target_deux_categories_meme_fichier_fail():
    """Variante du même sens : une seule ligne, mais deux catégories qui revendiquent
    le MÊME fichier (`test.oracle` et `test.solvability` partagent un dossier). Le
    partage de dossier reste légitime ; revendiquer le même artefact ne l'est pas."""
    wiremap = _wiremap_named([
        {"id": "core.boot", "category": "system", "system_parent": "game_loop",
         "address": "05_SYSTEMS/game_loop/",
         "fichiers": [
             {"path": "07_TESTS/oracle/solvability.mjs", "category": "test.solvability"},
             {"path": "07_TESTS/oracle/solvability.mjs", "category": "test.oracle"},
         ]},
    ])
    rep = check_placement(wiremap, _repo_map_named_artifacts())
    assert rep["passed"] is False
    assert any("test.oracle" in x and "test.solvability" in x
               for x in rep["revendications_multiples"])


def test_identity_same_id_multiple_targets_fail():
    """CAS EXIGÉ (`same_id_multiple_targets: FAIL`) — un même identifiant (`loop.test.mjs`
    en `test.unit`) désigne deux fichiers distincts : le nom ne permet plus de
    correspondance univoque."""
    wiremap = _wiremap_named([
        {"id": "core.main_loop", "category": "system", "system_parent": "game_loop",
         "address": "05_SYSTEMS/game_loop/",
         "fichiers": [{"path": "07_TESTS/unit/loop.test.mjs", "category": "test.unit"}]},
        {"id": "core.game_state", "category": "system", "system_parent": "game_state",
         "address": "05_SYSTEMS/game_state/",
         "fichiers": [{"path": "05_SYSTEMS/game_state/loop.test.mjs",
                       "category": "test.unit"}]},
    ])
    rep = check_placement(wiremap, _repo_map_named_artifacts())
    assert rep["passed"] is False
    assert len(rep["identite_ambigue"]) == 1
    viol = rep["identite_ambigue"][0]
    assert "test.unit:loop.test.mjs" in viol
    assert "07_TESTS/unit/loop.test.mjs" in viol
    assert "05_SYSTEMS/game_state/loop.test.mjs" in viol


def test_identity_configuration_legitime_reste_verte():
    """ANTI-THÉÂTRE — une carte où chaque artefact nommé est revendiqué par EXACTEMENT
    une ligne reste VERTE : plusieurs lignes déposent des tests et des assets, aucune
    ne partage un artefact. Une règle d'unicité qui rougirait ce cas ne mesurerait plus
    l'unicité mais la simple présence de fichiers `test.*`/`asset.*`."""
    wiremap = _wiremap_named([
        {"id": "core.main_loop", "category": "system", "system_parent": "game_loop",
         "address": "05_SYSTEMS/game_loop/",
         "fichiers": [
             {"path": "05_SYSTEMS/game_loop/loop.mjs", "category": "system"},
             {"path": "07_TESTS/unit/loop.test.mjs", "category": "test.unit"},
             {"path": "07_TESTS/oracle/solvability.mjs", "category": "test.solvability"},
         ]},
        {"id": "core.game_state", "category": "system", "system_parent": "game_state",
         "address": "05_SYSTEMS/game_state/",
         "fichiers": [
             {"path": "05_SYSTEMS/game_state/state.mjs", "category": "system"},
             {"path": "07_TESTS/unit/state.test.mjs", "category": "test.unit"},
         ]},
        {"id": "core.audio", "category": "system", "system_parent": "game_loop",
         "address": "05_SYSTEMS/game_loop/",
         # un même déposant peut poser PLUSIEURS artefacts nommés distincts d'une même
         # catégorie (le son, son manifeste, sa licence) : ce n'est pas une collision.
         "fichiers": [
             {"path": "04_ASSETS/audio/bounce.wav", "category": "asset.audio"},
             {"path": "04_ASSETS/audio/manifest.json", "category": "asset.audio"},
             {"path": "04_ASSETS/audio/LICENSE.txt", "category": "asset.audio"},
         ]},
    ])
    rep = check_placement(wiremap, _repo_map_named_artifacts())
    assert rep["passed"] is True, rep
    assert rep["revendications_multiples"] == []
    assert rep["identite_ambigue"] == []
    assert rep["fichier_adresse_incoherente"] == []


def test_identity_fichier_partage_hors_scope_reste_vert():
    """PORTÉE (`scope: [test.*, asset.*]`) — un fichier de SYSTÈME partagé par plusieurs
    lignes du même système (le cas normal de Pong : `loop.mjs` cité par 5 lignes) n'est
    PAS concerné : la décision porte sur les artefacts nommés, pas sur les catégories
    de dossier. Élargir la portée serait un jugement, pas cette décision."""
    wiremap = _wiremap_named([
        {"id": "core.boot", "category": "system", "system_parent": "game_loop",
         "address": "05_SYSTEMS/game_loop/",
         "fichiers": [{"path": "05_SYSTEMS/game_loop/loop.mjs", "category": "system"}]},
        {"id": "core.main_loop", "category": "system", "system_parent": "game_loop",
         "address": "05_SYSTEMS/game_loop/",
         "fichiers": [{"path": "05_SYSTEMS/game_loop/loop.mjs", "category": "system"}]},
    ])
    rep = check_placement(wiremap, _repo_map_named_artifacts())
    assert rep["passed"] is True
    assert rep["revendications_multiples"] == []


def test_identity_artefact_nomme_en_sous_dossier_incoherent():
    """Un artefact nommé vit DIRECTEMENT dans le dossier de sa catégorie : son nom est
    son identité. Un sous-dossier rouvrirait deux `player.png` distincts sous un même
    nom — exactement l'ambiguïté que la décision ferme."""
    wiremap = _wiremap_named([
        {"id": "core.render", "category": "system", "system_parent": "game_loop",
         "address": "05_SYSTEMS/game_loop/",
         "fichiers": [{"path": "04_ASSETS/sprites/hud/player.png",
                       "category": "asset.sprite"}]},
    ])
    rep = check_placement(wiremap, _repo_map_named_artifacts())
    assert rep["passed"] is False
    assert any("04_ASSETS/sprites/player.png" in x
               for x in rep["fichier_adresse_incoherente"])


def test_identity_gabarit_dossier_conserve_le_comportement_prefixe():
    """NON-RÉGRESSION — une table qui garde des gabarits de DOSSIER pour `test.*`
    (forme d'avant la décision) conserve EXACTEMENT l'ancien jugement : c'est la forme
    déclarée par la table qui commande, jamais une liste de catégories codée en dur."""
    wiremap = _wiremap_named([
        {"id": "core.boot", "category": "system", "system_parent": "game_loop",
         "address": "05_SYSTEMS/game_loop/",
         "fichiers": [{"path": "07_TESTS/oracle/solvability.mjs", "category": "test.oracle"}]},
        {"id": "core.restart", "category": "system", "system_parent": "game_state",
         "address": "05_SYSTEMS/game_state/",
         "fichiers": [{"path": "07_TESTS/oracle/solvability.mjs", "category": "test.oracle"}]},
    ])
    rep = check_placement(wiremap, _repo_map_with_tests())
    assert rep["passed"] is True
    assert rep["revendications_multiples"] == []


def test_identity_v1_wiremap_non_concernee():
    """RÉTROCOMPAT STRICTE — une wiremap `schema_version: 1` (preuve de run passé) n'est
    jugée sur aucune des deux nouvelles contraintes."""
    wiremap = {
        "schema_version": 1,
        "lines": [
            {"id": "game_loop", "category": "system", "address": "05_SYSTEMS/game_loop/",
             "fichiers": ["07_TESTS/oracle/solvability.mjs"]},
            {"id": "game_state", "category": "system", "address": "05_SYSTEMS/game_state/",
             "fichiers": ["07_TESTS/oracle/solvability.mjs"]},
        ],
    }
    rep = check_placement(wiremap, _repo_map_named_artifacts())
    assert rep["passed"] is True
    assert rep["revendications_multiples"] == []
    assert rep["identite_ambigue"] == []


def test_identity_adresse_de_ligne_inchangee_par_le_nouveau_gabarit():
    """Une LIGNE n'est pas un fichier : même quand sa catégorie porte désormais un
    gabarit d'artefact nommé, son `address` reste jugée sur le DOSSIER de la catégorie
    (comportement identique à avant la décision)."""
    wiremap = {
        "schema_version": 2,
        "lines": [{"id": "t1", "category": "test.unit", "address": "07_TESTS/unit/"}],
    }
    rep = check_placement(wiremap, _repo_map_named_artifacts())
    assert rep["passed"] is True
    assert rep["adresse_incoherente"] == []


def test_identity_chemin_dossier_declare_comme_artefact_nomme_fail():
    """Robustesse : un `path` qui se termine par « / » n'est pas un artefact nommé."""
    wiremap = _wiremap_named([
        {"id": "core.boot", "category": "system", "system_parent": "game_loop",
         "address": "05_SYSTEMS/game_loop/",
         "fichiers": [{"path": "07_TESTS/oracle/", "category": "test.oracle"}]},
    ])
    rep = check_placement(wiremap, _repo_map_named_artifacts())
    assert rep["passed"] is False
    assert any("dossier reçu" in x for x in rep["fichier_adresse_incoherente"])
    assert rep["revendications_multiples"] == []


# =======================================================================================
# 5. check_index
# =======================================================================================


def test_index_pass_all_cited_and_present(tmp_path):
    _write(tmp_path, "05_SYSTEMS/game_loop/loop.mjs", "export function tick() {}\n")
    wiremap = {"lines": [
        {"id": "game_loop", "fichiers": ["05_SYSTEMS/game_loop/loop.mjs"],
         "address": "05_SYSTEMS/game_loop/"},
    ]}
    rep = check_index(wiremap, tmp_path)
    assert rep["passed"] is True
    assert rep["orphelins"] == []
    assert rep["dossiers_orphelins"] == []


def test_index_orphan_file_not_cited_fail(tmp_path):
    # CAS EXIGÉ : un fichier de logique présent sur le disque, cité par aucune ligne.
    _write(tmp_path, "05_SYSTEMS/game_loop/loop.mjs", "export function tick() {}\n")
    _write(tmp_path, "05_SYSTEMS/game_loop/leftover.mjs", "export function ghost() {}\n")
    wiremap = {"lines": [
        {"id": "game_loop", "fichiers": ["05_SYSTEMS/game_loop/loop.mjs"],
         "address": "05_SYSTEMS/game_loop/"},
    ]}
    rep = check_index(wiremap, tmp_path)
    assert rep["passed"] is False
    assert any("leftover.mjs" in f for f in rep["orphelins"])


def test_index_missing_declared_file_fail(tmp_path):
    wiremap = {"lines": [
        {"id": "game_loop", "fichiers": ["05_SYSTEMS/game_loop/loop.mjs"], "address": "05_SYSTEMS/game_loop/"},
    ]}
    (tmp_path / "05_SYSTEMS" / "game_loop").mkdir(parents=True)
    rep = check_index(wiremap, tmp_path)
    assert rep["passed"] is False
    assert any("loop.mjs" in f for f in rep["fichiers_manquants"])


def test_index_missing_declared_address_directory_fail(tmp_path):
    wiremap = {"lines": [
        {"id": "game_loop", "fichiers": [], "address": "05_SYSTEMS/game_loop/"},
    ]}
    rep = check_index(wiremap, tmp_path)
    assert rep["passed"] is False
    assert any("game_loop" in d for d in rep["dossiers_manquants"])


def test_index_directory_not_referenced_by_anyone_fail(tmp_path):
    _write(tmp_path, "05_SYSTEMS/game_loop/loop.mjs", "export function tick() {}\n")
    _write(tmp_path, "99_STRAY/leftover.mjs", "export function ghost() {}\n")
    wiremap = {"lines": [
        {"id": "game_loop", "fichiers": ["05_SYSTEMS/game_loop/loop.mjs"],
         "address": "05_SYSTEMS/game_loop/"},
    ]}
    rep = check_index(wiremap, tmp_path)
    assert rep["passed"] is False
    assert any("99_STRAY" in d for d in rep["dossiers_orphelins"])


def test_index_test_files_excluded_from_orphan_check(tmp_path):
    _write(tmp_path, "05_SYSTEMS/game_loop/loop.mjs", "export function tick() {}\n")
    _write(tmp_path, "05_SYSTEMS/game_loop/loop.test.mjs", "test('tick', () => {});\n")
    wiremap = {"lines": [
        {"id": "game_loop", "fichiers": ["05_SYSTEMS/game_loop/loop.mjs"],
         "address": "05_SYSTEMS/game_loop/"},
    ]}
    rep = check_index(wiremap, tmp_path)
    assert rep["passed"] is True  # loop.test.mjs n'est pas exigé d'être cité


def test_index_non_dict_wiremap_no_crash(tmp_path):
    rep = check_index(None, tmp_path)
    assert rep["passed"] is False
    assert "raison" in rep


def test_index_nonexistent_src_root_no_crash():
    rep = check_index({"lines": []}, Path("chemin/qui/n/existe/pas"))
    assert rep["passed"] is True  # rien à indexer, rien de manquant déclaré
    assert rep["orphelins"] == []


def test_index_governance_dirs_excluded_from_orphan_check(tmp_path):
    # CAS EXIGÉ : 00_CHARTER/ et 09_WIREMAP/ existent, contiennent du contenu, ne sont
    # référencés par aucune address de ligne -> ce n'est PAS un dossier orphelin (faux
    # positif corrigé, cf. rapport de sondage des 6 oracles sur Pong).
    _write(tmp_path, "00_CHARTER/game_contract.yaml", "game_id: pong\n")
    _write(tmp_path, "09_WIREMAP/wiremap.json", "{}\n")
    _write(tmp_path, "05_SYSTEMS/game_loop/loop.mjs", "export function tick() {}\n")
    wiremap = {"lines": [
        {"id": "game_loop", "fichiers": ["05_SYSTEMS/game_loop/loop.mjs"],
         "address": "05_SYSTEMS/game_loop/"},
    ]}
    rep = check_index(wiremap, tmp_path)
    assert rep["passed"] is True
    assert rep["dossiers_orphelins"] == []


def test_index_non_governance_stray_dir_still_flagged_alongside_governance(tmp_path):
    # La relaxe de gouvernance ne doit PAS masquer un vrai dossier orphelin ailleurs.
    _write(tmp_path, "00_CHARTER/game_contract.yaml", "game_id: pong\n")
    _write(tmp_path, "05_SYSTEMS/game_loop/loop.mjs", "export function tick() {}\n")
    _write(tmp_path, "99_STRAY/leftover.mjs", "export function ghost() {}\n")
    wiremap = {"lines": [
        {"id": "game_loop", "fichiers": ["05_SYSTEMS/game_loop/loop.mjs"],
         "address": "05_SYSTEMS/game_loop/"},
    ]}
    rep = check_index(wiremap, tmp_path)
    assert rep["passed"] is False
    assert any("99_STRAY" in d for d in rep["dossiers_orphelins"])
    assert not any("00_CHARTER" in d for d in rep["dossiers_orphelins"])


def test_index_dir_referenced_only_by_fichiers_is_not_orphan(tmp_path):
    # CHECK_INDEX_SYMMETRY_V1 (décision Pierre 2026-07-23) : un dossier prouvé référencé
    # par un fichier cité dans `fichiers[]` (et par AUCUNE `address`) n'est PAS orphelin.
    # Faux positif mesuré sur Pong (07_TESTS/unit, 04_ASSETS/audio…) : ces dossiers
    # contiennent des fichiers réels cités, l'oracle ne testait pourtant que `address`.
    _write(tmp_path, "05_SYSTEMS/game_loop/loop.mjs", "export function tick() {}\n")
    _write(tmp_path, "07_TESTS/unit/loop.spec.mjs", "export function spec() {}\n")
    wiremap = {"lines": [
        {"id": "game_loop",
         "fichiers": ["05_SYSTEMS/game_loop/loop.mjs", "07_TESTS/unit/loop.spec.mjs"],
         "address": "05_SYSTEMS/game_loop/"},
    ]}
    rep = check_index(wiremap, tmp_path)
    # 07_TESTS et 07_TESTS/unit ne sont cités par AUCUNE address, seulement via fichiers[].
    assert rep["dossiers_orphelins"] == []


def test_index_ghost_dir_with_uncited_file_stays_orphan_anti_theatre(tmp_path):
    # GARDE-FOU ANTI-THÉÂTRE : la symétrie fichiers[]->dossier ne doit PAS rendre l'oracle
    # aveugle. Un dossier `05_SYSTEMS/ghost/` contenant un fichier NON cité (ni par une
    # address, ni par fichiers[]) doit RESTER orphelin — check_index doit le voir.
    _write(tmp_path, "05_SYSTEMS/game_loop/loop.mjs", "export function tick() {}\n")
    _write(tmp_path, "05_SYSTEMS/ghost/rogue.mjs", "export function rogue() {}\n")
    wiremap = {"lines": [
        {"id": "game_loop", "fichiers": ["05_SYSTEMS/game_loop/loop.mjs"],
         "address": "05_SYSTEMS/game_loop/"},
    ]}
    rep = check_index(wiremap, tmp_path)
    assert rep["passed"] is False
    assert any("05_SYSTEMS/ghost" in d for d in rep["dossiers_orphelins"])
    # rogue.mjs lui-même reste un orphelin fichier (double preuve : la symétrie n'a rien masqué).
    assert any("ghost/rogue.mjs" in f for f in rep["orphelins"])


def test_index_test_only_dir_exempt_from_orphan_check(tmp_path):
    # Décision Pierre 2026-07-23 : un dossier ne contenant QUE des fichiers de test
    # (même heuristique `_is_test_file` que pour les fichiers) est exempté du contrôle
    # d'orphelins — symétrique de l'exclusion déjà appliquée aux fichiers. Cas réel Pong :
    # 07_TESTS/unit ne contient que des *.test.mjs, déclarés via system_contract.tests,
    # jamais dans fichiers[].
    _write(tmp_path, "05_SYSTEMS/game_loop/loop.mjs", "export function tick() {}\n")
    _write(tmp_path, "07_TESTS/unit/loop.test.mjs", "test('tick', () => {});\n")
    _write(tmp_path, "07_TESTS/unit/state.test.mjs", "test('state', () => {});\n")
    wiremap = {"lines": [
        {"id": "game_loop", "fichiers": ["05_SYSTEMS/game_loop/loop.mjs"],
         "address": "05_SYSTEMS/game_loop/"},
    ]}
    rep = check_index(wiremap, tmp_path)
    assert rep["passed"] is True
    assert rep["dossiers_orphelins"] == []


def test_index_mixed_test_and_nontest_dir_stays_orphan_anti_theatre(tmp_path):
    # GARDE-FOU ANTI-THÉÂTRE : l'exemption ne vaut QUE si le dossier est 100% tests. Un
    # dossier mixte (un *.test.mjs LÉGITIME + un rogue.mjs non cité et non-test) doit
    # RESTER orphelin — l'exemption ne blanchit pas un dossier partiellement illégitime.
    _write(tmp_path, "05_SYSTEMS/game_loop/loop.mjs", "export function tick() {}\n")
    _write(tmp_path, "05_SYSTEMS/mixed/loop.test.mjs", "test('t', () => {});\n")
    _write(tmp_path, "05_SYSTEMS/mixed/rogue.mjs", "export function rogue() {}\n")
    wiremap = {"lines": [
        {"id": "game_loop", "fichiers": ["05_SYSTEMS/game_loop/loop.mjs"],
         "address": "05_SYSTEMS/game_loop/"},
    ]}
    rep = check_index(wiremap, tmp_path)
    assert rep["passed"] is False
    assert any("05_SYSTEMS/mixed" in d for d in rep["dossiers_orphelins"])
    # le rogue.mjs non-test reste aussi un orphelin fichier (double preuve).
    assert any("mixed/rogue.mjs" in f for f in rep["orphelins"])


def test_index_before_build_missing_declared_dir_is_not_a_violation(tmp_path):
    # CAS EXIGÉ : avant build (built=False), une address déclarée dont le dossier
    # n'existe pas encore n'est PAS une violation — rien n'est construit.
    wiremap = {"lines": [
        {"id": "game_loop", "fichiers": [], "address": "05_SYSTEMS/game_loop/"},
    ]}
    rep = check_index(wiremap, tmp_path, built=False)
    assert rep["passed"] is True
    assert rep["dossiers_manquants"] == []


def test_index_after_build_missing_declared_dir_is_a_violation(tmp_path):
    # Le même squelette, après build (built=True, valeur par défaut) : la même absence
    # redevient une violation.
    wiremap = {"lines": [
        {"id": "game_loop", "fichiers": [], "address": "05_SYSTEMS/game_loop/"},
    ]}
    rep = check_index(wiremap, tmp_path, built=True)
    assert rep["passed"] is False
    assert any("game_loop" in d for d in rep["dossiers_manquants"])


# ---------------------------------------------------------------------------------------
# 5bis. check_index — `dossiers_hors_structure` (dossier de premier niveau hors roots)
# ---------------------------------------------------------------------------------------


def _repo_map_roots() -> dict:
    return {"roots": {"systems": "05_SYSTEMS/", "tests": "07_TESTS/", "charter": "00_CHARTER/"}}


def test_index_top_level_dir_outside_roots_fail(tmp_path):
    # CAS EXIGÉ : un builder qui crée `src/` (hors structure figée) -> FAIL.
    _write(tmp_path, "05_SYSTEMS/game_loop/loop.mjs", "export function tick() {}\n")
    _write(tmp_path, "src/rogue.mjs", "export function rogue() {}\n")
    wiremap = {"lines": [
        {"id": "game_loop", "fichiers": ["05_SYSTEMS/game_loop/loop.mjs"],
         "address": "05_SYSTEMS/game_loop/"},
    ]}
    rep = check_index(wiremap, tmp_path, repo_map=_repo_map_roots())
    assert rep["passed"] is False
    assert "src" in rep["dossiers_hors_structure"]


def test_index_only_known_roots_pass(tmp_path):
    # Seul `dossiers_hors_structure` est ciblé ici — 07_TESTS/unit non cité par une
    # `address` déclencherait par ailleurs `dossiers_orphelins` (contrôle PRÉ-EXISTANT,
    # hors périmètre de ce test).
    _write(tmp_path, "05_SYSTEMS/game_loop/loop.mjs", "export function tick() {}\n")
    wiremap = {"lines": [
        {"id": "game_loop", "fichiers": ["05_SYSTEMS/game_loop/loop.mjs"],
         "address": "05_SYSTEMS/game_loop/"},
    ]}
    rep = check_index(wiremap, tmp_path, repo_map=_repo_map_roots())
    assert rep["dossiers_hors_structure"] == []


def test_index_no_repo_map_skips_hors_structure_check_backward_compat(tmp_path):
    # RÉTROCOMPAT EXIGÉE : sans `repo_map` (appelants existants), aucun changement de
    # comportement — le contrôle ne s'exécute simplement pas.
    _write(tmp_path, "05_SYSTEMS/game_loop/loop.mjs", "export function tick() {}\n")
    _write(tmp_path, "src/rogue.mjs", "export function rogue() {}\n")
    wiremap = {"lines": [
        {"id": "game_loop", "fichiers": ["05_SYSTEMS/game_loop/loop.mjs"],
         "address": "05_SYSTEMS/game_loop/"},
    ]}
    rep = check_index(wiremap, tmp_path)
    assert rep["dossiers_hors_structure"] == []


def test_index_repo_map_malformed_no_crash(tmp_path):
    _write(tmp_path, "05_SYSTEMS/game_loop/loop.mjs", "export function tick() {}\n")
    wiremap = {"lines": [
        {"id": "game_loop", "fichiers": ["05_SYSTEMS/game_loop/loop.mjs"],
         "address": "05_SYSTEMS/game_loop/"},
    ]}
    rep = check_index(wiremap, tmp_path, repo_map="pas un mapping")
    assert rep["dossiers_hors_structure"] == []


def test_index_hors_structure_only_top_level_not_nested(tmp_path):
    # Ne signale jamais un sous-dossier d'une racine connue : seul le premier niveau compte.
    _write(tmp_path, "05_SYSTEMS/game_loop/nested/deep.mjs", "export function d() {}\n")
    wiremap = {"lines": [
        {"id": "game_loop", "fichiers": ["05_SYSTEMS/game_loop/nested/deep.mjs"],
         "address": "05_SYSTEMS/game_loop/"},
    ]}
    rep = check_index(wiremap, tmp_path, repo_map=_repo_map_roots())
    assert rep["dossiers_hors_structure"] == []


# ---------------------------------------------------------------------------------------
# 5bis-mapping. check_index — un dossier hors `roots` mais préfixant un gabarit de
# `mapping` est légal (correction 2026-07-28, snake : `godot.project_tests: "tests/{id}"`
# autorise "tests" — check_placement l'acceptait déjà, check_index le rejetait faute de
# lire le mapping. Règle GÉNÉRALE dérivée du premier segment de chemin de chaque
# gabarit, pas un `if "tests"` codé en dur).
# ---------------------------------------------------------------------------------------


def _repo_map_with_mapping() -> dict:
    return {
        "roots": {"systems": "05_SYSTEMS/", "charter": "00_CHARTER/"},
        "mapping": {
            "system": "05_SYSTEMS/{id}/",
            "godot.project_tests": "tests/{id}",
            "godot.project_root": "{id}",
        },
    }


def test_index_dir_matching_mapping_template_prefix_is_legal(tmp_path):
    _write(tmp_path, "05_SYSTEMS/game_loop/loop.gd", "func tick(): pass\n")
    _write(tmp_path, "tests/run_tests.gd", "func run(): pass\n")
    wiremap = {"lines": [
        {"id": "game_loop", "fichiers": [{"path": "05_SYSTEMS/game_loop/loop.gd",
                                          "category": "system"}],
         "address": "05_SYSTEMS/game_loop/"},
        {"id": "run_tests", "fichiers": [{"path": "tests/run_tests.gd",
                                          "category": "godot.project_tests"}]},
    ]}
    rep = check_index(wiremap, tmp_path, repo_map=_repo_map_with_mapping())
    assert "tests" not in rep["dossiers_hors_structure"]
    assert rep["dossiers_hors_structure"] == []


def test_index_mapping_template_that_is_bare_id_declares_no_directory(tmp_path):
    # `godot.project_root: "{id}"` ne préfixe aucun dossier statique (le premier segment
    # EST le placeholder) : il ne doit légaliser aucun dossier de premier niveau hors
    # `roots`. Un dossier réellement hors structure reste attrapé.
    _write(tmp_path, "05_SYSTEMS/game_loop/loop.gd", "func tick(): pass\n")
    _write(tmp_path, "rogue/rogue.gd", "func r(): pass\n")
    wiremap = {"lines": [
        {"id": "game_loop", "fichiers": [{"path": "05_SYSTEMS/game_loop/loop.gd",
                                          "category": "system"}],
         "address": "05_SYSTEMS/game_loop/"},
    ]}
    rep = check_index(wiremap, tmp_path, repo_map=_repo_map_with_mapping())
    assert "rogue" in rep["dossiers_hors_structure"]


def test_index_mapping_absent_no_crash_backward_compat(tmp_path):
    # repo_map sans clé "mapping" (forme historique _repo_map_roots()) : comportement
    # inchangé, aucune régression pour les appelants qui ne déclarent pas ce champ.
    _write(tmp_path, "05_SYSTEMS/game_loop/loop.mjs", "export function tick() {}\n")
    wiremap = {"lines": [
        {"id": "game_loop", "fichiers": ["05_SYSTEMS/game_loop/loop.mjs"],
         "address": "05_SYSTEMS/game_loop/"},
    ]}
    rep = check_index(wiremap, tmp_path, repo_map=_repo_map_roots())
    assert rep["dossiers_hors_structure"] == []


# ---------------------------------------------------------------------------------------
# 5ter. check_index — `fichiers[]` en objets `{path, category}` (schema_version: 2)
#
# Correction demandée après relecture du coordinateur (2026-07-22) : `check_placement`
# ferme le trou de placement, mais `check_index` filtrait auparavant `isinstance(f, str)`
# -> une entrée objet {path,category} n'était NI comptée dans `cited_files` NI vérifiée
# pour existence -> un jeu converti au nouveau format aurait vu son code réel signalé
# `orphelins` en masse (faux positif), et un fichier déclaré-mais-absent serait passé
# inaperçu (faux négatif). `check_index` ne juge JAMAIS `category` ici — cette règle
# appartient exclusivement à `check_placement` (FORGE_SYSTEM_CONTRACT.yaml : une seule
# implémentation par règle).
# ---------------------------------------------------------------------------------------


def test_index_v2_object_fichiers_missing_from_disk_is_caught(tmp_path):
    # CAS EXIGÉ : fichiers en objets, fichier réellement absent du disque, built=True
    # -> il doit apparaître dans fichiers_manquants (avant la correction, il passait
    # inaperçu car l'entrée objet était silencieusement ignorée).
    (tmp_path / "05_SYSTEMS" / "game_loop").mkdir(parents=True)
    wiremap = {
        "schema_version": 2,
        "lines": [
            {"id": "game_loop",
             "fichiers": [{"path": "05_SYSTEMS/game_loop/loop.mjs", "category": "system"}],
             "address": "05_SYSTEMS/game_loop/"},
        ],
    }
    rep = check_index(wiremap, tmp_path, built=True)
    assert rep["passed"] is False
    assert any("loop.mjs" in f for f in rep["fichiers_manquants"])


def test_index_v2_object_fichiers_present_and_cited_no_false_orphan(tmp_path):
    # CAS EXIGÉ : c'est LE faux positif qu'on empêche -- fichiers en objets, présents ET
    # cités -> aucun orphelin (avant la correction, ce fichier réel aurait été ORPHELIN
    # car jamais ajouté à cited_files).
    _write(tmp_path, "05_SYSTEMS/game_loop/loop.mjs", "export function tick() {}\n")
    wiremap = {
        "schema_version": 2,
        "lines": [
            {"id": "game_loop",
             "fichiers": [{"path": "05_SYSTEMS/game_loop/loop.mjs", "category": "system"}],
             "address": "05_SYSTEMS/game_loop/"},
        ],
    }
    rep = check_index(wiremap, tmp_path, built=True)
    assert rep["passed"] is True
    assert rep["orphelins"] == []
    assert rep["fichiers_manquants"] == []


def test_index_bare_string_fichiers_behavior_strictly_unchanged(tmp_path):
    # RÉTROCOMPAT EXIGÉE : wiremap avec chaînes nues -> comportement strictement inchangé.
    _write(tmp_path, "05_SYSTEMS/game_loop/loop.mjs", "export function tick() {}\n")
    wiremap = {"lines": [
        {"id": "game_loop", "fichiers": ["05_SYSTEMS/game_loop/loop.mjs"],
         "address": "05_SYSTEMS/game_loop/"},
    ]}
    rep = check_index(wiremap, tmp_path, built=True)
    assert rep["passed"] is True
    assert rep["orphelins"] == []
    assert rep["fichiers_manquants"] == []


def test_index_v2_object_fichiers_robustness_no_crash(tmp_path):
    # Robustesse : entrée objet sans path, path vide, path non-chaîne -> aucune exception,
    # aucune fausse citation, et le fichier réel resterait orphelin s'il n'était pas cité
    # ailleurs (ici il n'est cité nulle part -> orphelin attendu, comportement sain).
    _write(tmp_path, "05_SYSTEMS/game_loop/loop.mjs", "export function tick() {}\n")
    wiremap = {
        "schema_version": 2,
        "lines": [
            {"id": "game_loop",
             "fichiers": [
                 {"category": "system"},          # pas de path du tout
                 {"path": "", "category": "system"},  # path vide
                 {"path": 42, "category": "system"},  # path non-chaîne
             ],
             "address": "05_SYSTEMS/game_loop/"},
        ],
    }
    rep = check_index(wiremap, tmp_path, built=True)
    assert rep["fichiers_manquants"] == []
    assert any("loop.mjs" in f for f in rep["orphelins"])


def test_index_before_build_missing_declared_file_is_not_a_violation(tmp_path):
    (tmp_path / "05_SYSTEMS" / "game_loop").mkdir(parents=True)
    wiremap = {"lines": [
        {"id": "game_loop", "fichiers": ["05_SYSTEMS/game_loop/loop.mjs"],
         "address": "05_SYSTEMS/game_loop/"},
    ]}
    rep = check_index(wiremap, tmp_path, built=False)
    assert rep["passed"] is True
    assert rep["fichiers_manquants"] == []


# =======================================================================================
# 6. check_collisions
# =======================================================================================


def _capabilities() -> dict:
    return {
        "capabilities": [
            {"id": "game.loop", "single_owner": True},
            {"id": "game.state", "single_owner": True},
            {"id": "game.restart", "single_owner": True},
            {"id": "play.score", "single_owner": True},
            {"id": "audio.cue", "single_owner": False},
        ]
    }


def test_collisions_pass_clean_wiremap():
    wiremap = {"lines": [
        {"id": "loop", "provides": ["game.loop"], "requires": ["game.state"], "owner": True},
        {"id": "state", "provides": ["game.state"], "requires": [], "owner": True},
    ]}
    rep = check_collisions(wiremap, _capabilities())
    assert rep["passed"] is True


def test_collisions_single_owner_double_provider_fail():
    # CAS EXIGÉ : deux lignes qui fournissent la même capacité single_owner.
    wiremap = {"lines": [
        {"id": "score_a", "provides": ["play.score"], "requires": [], "owner": True},
        {"id": "score_b", "provides": ["play.score"], "requires": [], "owner": False},
    ]}
    rep = check_collisions(wiremap, _capabilities())
    assert rep["passed"] is False
    assert "play.score" in rep["collisions"]


def test_collisions_unknown_identifier_fail():
    wiremap = {"lines": [
        {"id": "loop", "provides": ["game.turbo_boost"], "requires": [], "owner": True},
    ]}
    rep = check_collisions(wiremap, _capabilities())
    assert rep["passed"] is False
    assert any("game.turbo_boost" in x for x in rep["identifiants_inconnus"])


def test_collisions_requires_without_provider_is_a_hole():
    wiremap = {"lines": [
        {"id": "hud", "provides": [], "requires": ["game.restart"], "owner": False},
    ]}
    rep = check_collisions(wiremap, _capabilities())
    assert rep["passed"] is False
    assert "game.restart" in rep["trous"]


def test_collisions_double_owner_same_capability_fail():
    wiremap = {"lines": [
        {"id": "audio_a", "provides": ["audio.cue"], "requires": [], "owner": True},
        {"id": "audio_b", "provides": ["audio.cue"], "requires": [], "owner": True},
    ]}
    rep = check_collisions(wiremap, _capabilities())
    assert rep["passed"] is False
    assert "audio.cue" in rep["doubles_proprietaires"]


def test_collisions_multiple_writers_without_write_order_fail():
    # audio.cue n'est PAS single_owner (plusieurs consommateurs/producteurs sains) mais
    # deux écrivains sans write_order = ordre implicite non déterministe (incident réel).
    wiremap = {"lines": [
        {"id": "audio_a", "provides": ["audio.cue"], "requires": [], "owner": False, "write_order": None},
        {"id": "audio_b", "provides": ["audio.cue"], "requires": [], "owner": False, "write_order": None},
    ]}
    rep = check_collisions(wiremap, _capabilities())
    assert rep["passed"] is False
    assert "audio.cue" in rep["ordre_implicite"]


def test_collisions_multiple_writers_with_write_order_declared_pass():
    wiremap = {"lines": [
        {"id": "audio_a", "provides": ["audio.cue"], "requires": [], "owner": False, "write_order": 1},
        {"id": "audio_b", "provides": ["audio.cue"], "requires": [], "owner": False, "write_order": 2},
    ]}
    rep = check_collisions(wiremap, _capabilities())
    assert rep["passed"] is True
    assert rep["ordre_implicite"] == []


def test_collisions_non_dict_wiremap_no_crash():
    rep = check_collisions(None, _capabilities())
    assert rep["passed"] is False
    assert "raison" in rep


def test_collisions_capabilities_malformed_no_crash():
    wiremap = {"lines": [{"id": "loop", "provides": ["game.loop"], "requires": [], "owner": True}]}
    rep = check_collisions(wiremap, {"capabilities": "pas une liste"})
    assert rep["passed"] is False
    assert any("game.loop" in x for x in rep["identifiants_inconnus"])


def test_collisions_real_capabilities_yaml_loads_and_runs():
    data = yaml.safe_load(STANDARD_DIR.joinpath("capabilities.yaml").read_text(encoding="utf-8"))
    wiremap = {"lines": [
        {"id": "loop", "provides": ["game.loop"], "requires": ["game.state"], "owner": True},
        {"id": "state", "provides": ["game.state"], "requires": [], "owner": True},
    ]}
    rep = check_collisions(wiremap, data)
    assert rep["passed"] is True

"""Bloc produit/runtime INCONDITIONNEL (Task 4, plan
`2026-08-22-kitten-clicker-gameplay-contract.md` §T4) — `ForgeDriver._run_code_oracle`
(s10a) : `runtime_alive`, `player_loop` et `loop_bypass` sont mesurés dès que
`<game_dir>/project.godot` porte `run/main_scene`, INDÉPENDAMMENT de
`proof_descriptor_ok`/`godot_capacity_ok` (mesuré : 3 runs/3 ont sauté tout le bloc
faute de `proof:` dans le contrat, laissant un BLOCKED mutation sans que la vie du
jeu ni la boucle ne soient jamais mesurées). Le fournisseur produit Godot (les
VOLETS `product_oracle_godot_runner`) GARDE sa condition d'activation historique,
inchangée.

Même patron que `test_driver_product_oracle_godot_wiring.py` : `ForgeDriver` réel
avec runners injectés (`runtime_alive_runner`, `player_loop_runner`,
`product_oracle_godot_runner`, `mutation_runner`, `product_oracle_runner`), jamais
un vrai binaire Godot ni un vrai process.
"""
import json
import sys

import yaml

from forge.driver import ForgeDriver


def _oracle_cfg(tmp_path, project, cwd):
    cfg = tmp_path / f"oracles_{project}.json"
    cfg.write_text(json.dumps({project: {
        "cwd": str(cwd),
        "command": [sys.executable, "-c",
                    "import sys; sys.exit(0)  # 07_TESTS/oracle/solvability.mjs"],
    }}), encoding="utf-8")
    return cfg


def _standard_game_no_proof(root, *, with_main_scene=True):
    """Jeu STANDARD SANS descripteur `proof:` ET SANS oracle FORGE_ORACLE (aucune
    des deux conditions du fournisseur produit Godot) — même squelette que
    `test_driver_product_oracle_godot_wiring.py::_standard_game_no_proof`, avec un
    `project.godot` optionnel portant `run/main_scene`."""
    (root / "00_CHARTER").mkdir(parents=True)
    (root / "00_CHARTER" / "game_contract.yaml").write_text(
        yaml.safe_dump({"schema_version": 1, "game_id": "g", "node": 1,
                        "runtimes": ["rules"], "budget": {"reuses": [], "adds": []},
                        "assets": {"plan": "cc0"}}), encoding="utf-8")
    (root / "05_SYSTEMS" / "game_loop").mkdir(parents=True)
    (root / "05_SYSTEMS" / "game_loop" / "loop.mjs").write_text("export const t=1;\n",
                                                                encoding="utf-8")
    (root / "09_WIREMAP").mkdir(parents=True)
    (root / "09_WIREMAP" / "wiremap.json").write_text(json.dumps({
        "schema_version": 2,
        "lines": [{
            "id": "core.boot", "category": "system", "provides": ["game.boot"],
            "requires": [], "owner": True, "state": "IMPLEMENTED",
            "address": "05_SYSTEMS/game_loop/",
            "observable_by_player": True,
            "observable_proof": "auto_session",
            "genre_refs": ["genre.g.some_rule"],
            "fichiers": [{"path": "05_SYSTEMS/game_loop/loop.mjs", "category": "system"}],
        }],
        "genre_refusals": [],
    }), encoding="utf-8")
    (root / "01_DESIGN").mkdir(parents=True)
    (root / "01_DESIGN" / "genre_bible.json").write_text(json.dumps({
        "genre_rules": [{"id": "genre.g.some_rule", "applies_to_wiremap_line": "core.boot"}],
    }), encoding="utf-8")
    if with_main_scene:
        (root / "project.godot").write_text(
            '[application]\nconfig/name="g"\nrun/main_scene="res://main.tscn"\n',
            encoding="utf-8")
    return root


def _run_code_step(tmp_path, game_dir, *, runtime_alive_runner=None,
                    player_loop_runner=None, product_oracle_godot_runner=None):
    d = ForgeDriver(
        "g", "r1", run_dir=tmp_path / "run", profile="standard",
        is_game=True, src_root=game_dir, game_dir=game_dir,
        oracle_config=_oracle_cfg(tmp_path, "g", game_dir), key_file=tmp_path / "k.key",
        audit_path=tmp_path / "audit.jsonl",
        mutation_baseline_runner=lambda argv, cwd: True,
        mutation_runner=lambda src, argv, *, cwd, **kw: {
            "total": 2, "killed": 2, "survived": 0, "score": 1.0, "survivors": []},
        product_oracle_runner=lambda game_dir: {
            "auto_session": {"passed": True, "checked": True}},
        product_oracle_godot_runner=product_oracle_godot_runner,
        runtime_alive_runner=runtime_alive_runner,
        player_loop_runner=player_loop_runner,
    )
    state = {"steps": {e: {"status": "PENDING", "attempts": 0, "detail": {}}
                       for e in d.order}}
    d._run_deterministic(state, "s10a-oracle-code")
    return state["steps"]["s10a-oracle-code"], state


# --- (a) run/main_scene présent, ni proof: ni oracle FORGE_ORACLE ------------------


def test_main_scene_present_sans_proof_ni_capacite_les_trois_runners_sont_appeles(tmp_path):
    game = _standard_game_no_proof(tmp_path / "game", with_main_scene=True)
    runtime_calls, loop_calls, godot_calls = [], [], []

    def runtime_alive(gd):
        runtime_calls.append(gd)
        return {"status": "OK", "checked": True, "passed": True}

    def player_loop(gd, run_dir=None):
        loop_calls.append((gd, run_dir))
        return {"status": "OK", "checked": True, "passed": True}

    def godot_runner(gd):
        godot_calls.append(gd)
        return {"never": {}}

    entry, _ = _run_code_step(
        tmp_path, game,
        runtime_alive_runner=runtime_alive,
        player_loop_runner=player_loop,
        product_oracle_godot_runner=godot_runner,
    )

    assert runtime_calls == [game]
    assert loop_calls == [(game, tmp_path / "run")]
    assert godot_calls == [], "product_oracle_godot_runner reste gaté par proof+capacité"

    detail = entry["detail"]
    assert detail["runtime_alive"] == {"status": "OK", "checked": True, "passed": True}
    assert detail["player_loop"] == {"status": "OK", "checked": True, "passed": True}
    assert "loop_bypass" in detail
    assert "product_oracle_godot" not in detail

    activation = detail["product_oracle_godot_activation"]
    assert activation["active"] is False  # volets Godot toujours gatés proof+capacité
    assert activation["runtime_block"]["active"] is True
    assert activation["runtime_block"]["reason"] == "run/main_scene déclaré"


# --- (b) pas de run/main_scene : rien n'est appelé, runtime_block inactif ---------


def test_sans_main_scene_les_runners_ne_sont_jamais_appeles(tmp_path):
    game = _standard_game_no_proof(tmp_path / "game", with_main_scene=False)
    runtime_calls, loop_calls = [], []

    def runtime_alive(gd):
        runtime_calls.append(gd)
        return {"status": "OK", "checked": True, "passed": True}

    def player_loop(gd, run_dir=None):
        loop_calls.append((gd, run_dir))
        return {"status": "OK", "checked": True, "passed": True}

    entry, _ = _run_code_step(
        tmp_path, game, runtime_alive_runner=runtime_alive, player_loop_runner=player_loop)

    assert runtime_calls == []
    assert loop_calls == []
    detail = entry["detail"]
    assert detail["runtime_alive"] == {
        "status": "SKIPPED", "checked": False, "passed": False,
        "reason": "pas de run/main_scene (module bibliothèque)",
    }
    assert "player_loop" not in detail
    assert "loop_bypass" not in detail
    activation = detail["product_oracle_godot_activation"]
    assert activation["runtime_block"]["active"] is False
    assert activation["runtime_block"]["reason"] == "pas de run/main_scene"


# --- (c) player_loop FAIL checked => final == "FAIL" (gate, régime historique) ----


def test_player_loop_fail_checked_fait_echouer_le_gate_regime_historique(tmp_path):
    game = _standard_game_no_proof(tmp_path / "game", with_main_scene=True)

    def player_loop_fail(gd, run_dir=None):
        return {"status": "FAIL", "checked": True, "passed": False,
                "fails": ["affordance introuvable"]}

    entry, _ = _run_code_step(
        tmp_path, game,
        runtime_alive_runner=lambda gd: {"status": "OK", "checked": True, "passed": True},
        player_loop_runner=player_loop_fail,
    )
    assert entry["status"] == "FAIL"
    assert entry["detail"]["loop_dead"] is True


# --- (d) SKIPPED + <run_dir>/loop.json amont présent -> FAIL checked, gate --------


def test_player_loop_skipped_avec_loop_amont_fait_echouer_le_gate(tmp_path):
    game = _standard_game_no_proof(tmp_path / "game", with_main_scene=True)
    run_dir = tmp_path / "run"
    run_dir.mkdir(parents=True, exist_ok=True)
    (run_dir / "loop.json").write_text("{}", encoding="utf-8")

    def player_loop_skipped(gd, run_dir=None):
        return {"status": "SKIPPED", "checked": False, "passed": False,
                "reason": "pas de 03_WORLD/loop.json"}

    entry, _ = _run_code_step(
        tmp_path, game,
        runtime_alive_runner=lambda gd: {"status": "OK", "checked": True, "passed": True},
        player_loop_runner=player_loop_skipped,
    )
    assert entry["status"] == "FAIL"
    assert entry["detail"]["player_loop"]["status"] == "FAIL"
    assert entry["detail"]["player_loop"]["checked"] is True
    assert entry["detail"]["loop_dead"] is True


def test_player_loop_skipped_sans_loop_amont_ne_fait_pas_echouer(tmp_path):
    """Contrôle négatif de (d) : SKIPPED sans contrat amont reste SKIPPED, le gate
    n'échoue pas pour cette raison (comportement inchangé)."""
    game = _standard_game_no_proof(tmp_path / "game", with_main_scene=True)
    # aucun run_dir/loop.json créé

    def player_loop_skipped(gd, run_dir=None):
        return {"status": "SKIPPED", "checked": False, "passed": False,
                "reason": "pas de 03_WORLD/loop.json"}

    entry, _ = _run_code_step(
        tmp_path, game,
        runtime_alive_runner=lambda gd: {"status": "OK", "checked": True, "passed": True},
        player_loop_runner=player_loop_skipped,
    )
    assert entry["detail"]["player_loop"]["status"] == "SKIPPED"
    assert entry["detail"]["loop_dead"] is False

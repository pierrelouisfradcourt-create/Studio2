"""Câblage driver de l'oracle PRODUIT (n3-oracle-produit-minimal, s10a) —
`ForgeDriver._run_code_oracle` porte les 3 volets (`product_oracle.run_product_oracle`)
dans `detail["product_oracle"]`, ADVISORY : jamais un gate dur dans cette mission.

`product_oracle_runner` est injectable (même patron que `mutation_runner`) : ces
tests n'invoquent JAMAIS node/le vrai module product_oracle — la couverture
RED/GREEN réelle des 3 volets vit dans test_product_oracle.py. Ici on vérifie
uniquement le CÂBLAGE : le driver appelle le runner, porte son résultat, ne
gate jamais dessus, et ne casse jamais le pas si le runner lève.
"""
import json
import sys

from forge.driver import ForgeDriver


def _oracle_cfg(tmp_path, project, cwd, exit_code=0):
    cfg = tmp_path / f"oracles_{project}.json"
    # Le commentaire `# 07_TESTS/oracle/solvability.mjs` fait passer le câblage
    # solvabilité STANDARD (check_solvability_wired cherche la sous-chaîne dans
    # l'argv résolu) — même artifice que test_standard_wiring_corrections.py.
    cfg.write_text(json.dumps({project: {
        "cwd": str(cwd),
        "command": [sys.executable, "-c",
                    f"import sys; sys.exit({exit_code})  # 07_TESTS/oracle/solvability.mjs"],
    }}), encoding="utf-8")
    return cfg


def _standard_game(root):
    """Squelette STANDARD minimal (même helper que test_standard_wiring_corrections.py)."""
    import yaml
    (root / "00_CHARTER").mkdir(parents=True)
    (root / "00_CHARTER" / "game_contract.yaml").write_text(
        yaml.safe_dump({"schema_version": 1, "game_id": "g", "node": 1,
                        "runtimes": ["rules"], "budget": {"reuses": [], "adds": []},
                        "assets": {"plan": "cc0"}}), encoding="utf-8")
    (root / "05_SYSTEMS" / "game_loop").mkdir(parents=True)
    (root / "05_SYSTEMS" / "game_loop" / "loop.mjs").write_text("export const t=1;\n",
                                                                encoding="utf-8")
    (root / "07_TESTS" / "oracle").mkdir(parents=True)
    (root / "07_TESTS" / "oracle" / "solvability.mjs").write_text(
        "const bot = { won: 1 > 0 };\n", encoding="utf-8")
    (root / "09_WIREMAP").mkdir(parents=True)
    (root / "09_WIREMAP" / "wiremap.json").write_text(json.dumps({
        "schema_version": 2,
        "lines": [{"id": "core.boot", "category": "system", "provides": ["game.boot"],
                   "requires": [], "owner": True, "state": "IMPLEMENTED",
                   "address": "05_SYSTEMS/game_loop/",
                   "fichiers": [{"path": "05_SYSTEMS/game_loop/loop.mjs",
                                 "category": "system"}]}],
    }), encoding="utf-8")
    return root


def _run_code_step(tmp_path, game_dir, profile, *, product_oracle_runner=None):
    d = ForgeDriver(
        "g", "r1", run_dir=tmp_path / f"run_{profile}", profile=profile,
        is_game=True, src_root=game_dir, game_dir=game_dir,
        oracle_config=_oracle_cfg(tmp_path, "g", game_dir),
        key_file=tmp_path / "k.key", audit_path=tmp_path / "audit.jsonl",
        mutation_baseline_runner=lambda argv, cwd: True,
        mutation_runner=lambda src, argv, *, cwd, **kw: {
            "total": 2, "killed": 2, "survived": 0, "score": 1.0, "survivors": []},
        product_oracle_runner=product_oracle_runner,
    )
    state = {"steps": {e: {"status": "PENDING", "attempts": 0, "detail": {}}
                       for e in d.order}}
    d._run_deterministic(state, "s10a-oracle-code")
    return state["steps"]["s10a-oracle-code"]


# --- câblage : le runner est appelé et son résultat porté (profil standard) -------

def test_product_oracle_porte_dans_le_recu_profil_standard(tmp_path):
    game = _standard_game(tmp_path / "game")
    calls = []

    def fake_runner(game_dir):
        calls.append(game_dir)
        return {"browser_import_safety": {"passed": True}, "auto_session": {"passed": True},
                "visual_capture": {"status": "OK", "passed": True}}

    entry = _run_code_step(tmp_path, game, "standard", product_oracle_runner=fake_runner)
    assert calls == [game]
    assert entry["detail"]["product_oracle"] == {
        "browser_import_safety": {"passed": True}, "auto_session": {"passed": True},
        "visual_capture": {"status": "OK", "passed": True},
    }
    assert entry["status"] == "OK"


def test_product_oracle_non_appele_hors_profil_standard(tmp_path):
    """Les 3 volets assument la topologie STANDARD — un profil legacy (micro/full)
    n'a pas ce squelette et n'a rien à y mesurer : le runner n'est PAS appelé."""
    game = _standard_game(tmp_path / "game")
    calls = []

    def fake_runner(game_dir):
        calls.append(game_dir)
        return {}

    entry = _run_code_step(tmp_path, game, "micro", product_oracle_runner=fake_runner)
    assert calls == []
    assert "product_oracle" not in entry["detail"]


# --- advisory : un volet rouge ne gate JAMAIS `final` dans cette mission ----------

def test_product_oracle_rouge_ne_bloque_pas_le_pas(tmp_path):
    """Un volet produit ROUGE (score gelé, import node: atteignable...) reste
    ADVISORY : le pas s10a reste OK si tout le reste (mutation/harness/etc.) est
    vert — c'est une décision de gate dur SÉPARÉE, à prendre par Pierre plus tard."""
    game = _standard_game(tmp_path / "game")

    def all_red_runner(game_dir):
        return {
            "browser_import_safety": {"passed": False,
                                      "node_imports_atteignables": [{"specifier": "node:fs"}]},
            "auto_session": {"passed": False, "score_evolves": False, "finished": False},
            "visual_capture": {"status": "FAIL", "passed": False},
        }

    entry = _run_code_step(tmp_path, game, "standard", product_oracle_runner=all_red_runner)
    assert entry["status"] == "OK", (
        "un s10a autrement vert ne doit PAS être fait rouge par le seul oracle produit "
        f"(advisory) — detail={entry['detail']}")
    assert entry["detail"]["product_oracle"]["auto_session"]["passed"] is False


# --- best-effort : une exception dans le runner ne casse jamais le pas -----------

def test_product_oracle_exception_nest_jamais_bloquante(tmp_path):
    game = _standard_game(tmp_path / "game")

    def boom(game_dir):
        raise RuntimeError("panne fabriquée")

    entry = _run_code_step(tmp_path, game, "standard", product_oracle_runner=boom)
    assert entry["status"] == "OK"
    assert entry["detail"]["product_oracle"]["measured"] is False


# --- défaut réel (pas injecté) : le driver résout bien forge.product_oracle.run_product_oracle --

def test_defaut_reel_est_run_product_oracle():
    from forge.driver import ForgeDriver
    from forge.product_oracle import run_product_oracle
    d = ForgeDriver("g", "r1", run_dir="unused_never_created")
    assert d.product_oracle_runner is run_product_oracle

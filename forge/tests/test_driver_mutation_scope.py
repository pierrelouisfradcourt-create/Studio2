"""Intégration driver : le gate mutation (s10a-oracle-code) dérive son
périmètre de la wiremap STANDARD par CATÉGORIE (décision U-2, contrat
n2-perimetre-mutation-categorie) -- un fichier `system.adapter` n'est ni
muté, ni scellé, mais son exclusion est DÉCLARÉE (fichier, catégorie, motif)
dans le reçu signé, avec des compteurs par catégorie.
"""
import json
import sys
from pathlib import Path

from forge.driver import ForgeDriver


def _standard_game_system_plus_adapter(tmp_path) -> Path:
    game = tmp_path / "game"
    (game / "00_CHARTER").mkdir(parents=True)
    (game / "00_CHARTER" / "game_contract.yaml").write_text(
        "schema_version: 1\ngame_id: g\nnode: 1\nruntimes: [rules]\n"
        "budget: {reuses: [], adds: []}\nassets: {plan: cc0}\n", encoding="utf-8")
    (game / "05_SYSTEMS" / "game_loop").mkdir(parents=True)
    (game / "05_SYSTEMS" / "game_loop" / "loop.mjs").write_text(
        "export const t = 1 >= 0;\n", encoding="utf-8")
    (game / "06_RUNTIME" / "adapters" / "presentation").mkdir(parents=True)
    (game / "06_RUNTIME" / "adapters" / "presentation" / "draw.mjs").write_text(
        "export const noop = () => {};\n", encoding="utf-8")
    (game / "07_TESTS" / "oracle").mkdir(parents=True)
    (game / "07_TESTS" / "oracle" / "solvability.mjs").write_text(
        "const bot = { won: 1 > 0 };\n", encoding="utf-8")
    (game / "09_WIREMAP").mkdir(parents=True)
    (game / "09_WIREMAP" / "wiremap.json").write_text(json.dumps({
        "schema_version": 2,
        "lines": [
            {"id": "core.boot", "category": "system", "provides": ["game.boot"],
             "requires": [], "owner": True, "state": "IMPLEMENTED",
             "address": "05_SYSTEMS/game_loop/",
             "fichiers": [{"path": "05_SYSTEMS/game_loop/loop.mjs",
                          "category": "system"}]},
            {"id": "core.render", "category": "system.adapter", "provides": ["render.frame"],
             "requires": ["game.state"], "owner": True, "state": "IMPLEMENTED",
             "address": "06_RUNTIME/adapters/presentation/",
             "fichiers": [{"path": "06_RUNTIME/adapters/presentation/draw.mjs",
                          "category": "system.adapter"}]},
        ],
    }), encoding="utf-8")
    return game


def _oracle_cfg(tmp_path, project, cwd):
    cfg = tmp_path / f"oracles_{project}.json"
    cfg.write_text(json.dumps({project: {
        "cwd": str(cwd),
        "command": [sys.executable, "-c",
                    "import sys; sys.exit(0)  # 07_TESTS/oracle/solvability.mjs"],
    }}), encoding="utf-8")
    return cfg


def _mutation_runner_per_file(src_path, argv, *, cwd, **kw):
    """`loop.mjs` : 3/3 tués. Si jamais `draw.mjs` (adaptateur) était appelé, il
    serait 0/5 -- mais le point de la mission est qu'il ne doit MÊME PAS être
    appelé (exclu en amont du mutateur, pas seulement du score)."""
    name = Path(src_path).name
    assert name != "draw.mjs", "un fichier system.adapter ne doit JAMAIS être muté"
    return {"total": 3, "killed": 3, "survived": 0, "survivors": []}


def test_s10a_receipt_exclut_adapter_declare_et_compte_par_categorie(tmp_path):
    game = _standard_game_system_plus_adapter(tmp_path)
    d = ForgeDriver(
        "g", "r1", run_dir=tmp_path / "run", profile="standard", is_game=True,
        src_root=game, game_dir=game,
        oracle_config=_oracle_cfg(tmp_path, "g", game),
        key_file=tmp_path / "k.key", audit_path=tmp_path / "audit.jsonl",
        mutation_baseline_runner=lambda argv, cwd: True,
        mutation_runner=_mutation_runner_per_file,
    )
    state = {"steps": {e: {"status": "PENDING", "attempts": 0, "detail": {}}
                       for e in d.order}}
    d._run_deterministic(state, "s10a-oracle-code")
    entry = state["steps"]["s10a-oracle-code"]

    mutation = entry["detail"]["mutation"]
    detail = mutation["receipt"]["detail"]

    # (a) seul le fichier `system` a été soumis au mutateur -- l'adaptateur n'y
    # entre même pas (pas seulement exclu du score après coup)
    assert detail["logic_files"] == ["05_SYSTEMS/game_loop/loop.mjs"]
    assert "06_RUNTIME/adapters/presentation/draw.mjs" not in detail["code_sha256"]

    # (b) exclusion DÉCLARÉE + compteurs par catégorie
    exclues = detail["categories_exclues"]
    assert len(exclues) == 1
    assert exclues[0]["fichier"] == "06_RUNTIME/adapters/presentation/draw.mjs"
    assert exclues[0]["categorie"] == "system.adapter"
    assert exclues[0]["motif"]  # jamais silencieux

    counts = detail["compteurs_par_categorie"]
    assert counts["system"] == {"jugee": True, "fichiers": 1, "killed": 3, "total": 3}
    assert counts["system.adapter"] == {"jugee": False, "fichiers": 1}

    # le re-cadrage laisse le gate mutation VERT (100% sur la seule population
    # jugée) -- ce n'est pas un affaiblissement de la sévérité du seuil
    assert mutation["receipt"]["status"] == "OK"
    assert entry["status"] == "OK"

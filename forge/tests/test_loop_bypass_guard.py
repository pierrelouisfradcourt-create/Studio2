"""Garde anti-contournement V4 (Task 5, lot « game loop », décision Pierre
2026-08-22) : `player_loop` n'a que `InputEvent`+lecture d'écran — un volet ou
`solvability.gd` qui prouve la boucle par un AUTRE canal (Economy, api_*,
05_SYSTEMS, runtime.gd) valide un jeu que le joueur ne peut pas traverser.
Deux pièces : (1) `run_godot_product_oracle` rejette CE volet, SANS spawn ;
(2) `check_loop_bypass(game_dir)` — garde STANDALONE, mapping de violations."""
import pytest
from pathlib import Path

from forge import product_oracle_godot as pog

REPO = Path(__file__).resolve().parents[2]
# Le build du run 6 est ARCHIVÉ (fixture du défaut : volets qui appellent api_buy_kitten / Economy) ;
# `GAMES/kitten_clicker/` porte le build courant (run 7+, 0 violation) et ne vaut plus comme fixture.
KITTEN = REPO / "EVIDENCE" / "runs" / "kitten_clicker" / "_run6_20260821f" / "game_build6"

_REAL_SCENE = 'load("res://main.tscn")\n'


def _oracle_file(game_dir: Path, name: str, body: str) -> Path:
    d = game_dir / "07_TESTS" / "oracle"
    d.mkdir(parents=True, exist_ok=True)
    p = d / name
    p.write_text("extends SceneTree\n# FORGE_ORACLE\n" + _REAL_SCENE + body, encoding="utf-8")
    return p


# --- garde par volet dans run_godot_product_oracle --------------------------


def test_volet_avec_api_buy_kitten_fail_static_guard_sans_spawn(tmp_path):
    game = tmp_path / "game"
    _oracle_file(game, "cheat.gd", "func _init():\n\t_main.api_buy_kitten()\n")
    calls = []
    r = pog.run_godot_product_oracle(
        game, binary_resolver=lambda: "godot",
        runner=lambda *a, **k: calls.append(a) or {"returncode": 0, "stdout": "", "stderr": ""})
    assert calls == [], "aucun process ne doit être lancé pour un volet contournant la boucle"
    assert r["cheat"]["status"] == "FAIL"
    assert r["cheat"]["mode_execution"] == "static_guard"
    assert "api_buy_kitten" in r["cheat"]["fails"][0]


def test_mention_en_commentaire_seule_est_executee(tmp_path):
    game = tmp_path / "game"
    _oracle_file(game, "clean.gd", "# jadis on appelait api_buy_kitten() ici — retire\nfunc _init():\n\tpass\n")
    calls = []
    stdout = 'FORGE_ORACLE clean {"ok": true, "fails": []}'
    r = pog.run_godot_product_oracle(
        game, binary_resolver=lambda: "godot",
        runner=lambda *a, **k: calls.append(a) or {"returncode": 0, "stdout": stdout, "stderr": ""})
    assert len(calls) == 1, "un volet dont le token n'est qu'en commentaire doit être exécuté"
    assert r["clean"]["status"] == "OK"


def test_economy_declenche_aussi_la_garde(tmp_path):
    game = tmp_path / "game"
    _oracle_file(game, "economy_cheat.gd", "const Economy = preload(\"res://05_SYSTEMS/economy/economy.gd\")\n")
    r = pog.run_godot_product_oracle(
        game, binary_resolver=lambda: "godot",
        runner=lambda *a, **k: (_ for _ in ()).throw(AssertionError("jamais appelé")))
    assert r["economy_cheat"]["status"] == "FAIL"
    assert r["economy_cheat"]["mode_execution"] == "static_guard"


# --- check_loop_bypass standalone -------------------------------------------


def test_check_loop_bypass_passe_quand_aucun_token(tmp_path):
    game = tmp_path / "game"
    _oracle_file(game, "clean.gd", "func _init():\n\tpass\n")
    r = pog.check_loop_bypass(game)
    assert r == {"passed": True, "violations": []}


def test_check_loop_bypass_detecte_api_buy_kitten(tmp_path):
    game = tmp_path / "game"
    _oracle_file(game, "cheat.gd", "func _init():\n\t_main.api_buy_kitten()\n")
    r = pog.check_loop_bypass(game)
    assert r["passed"] is False
    assert any(v["fichier"].endswith("cheat.gd") and v["token"] == "api_buy_kitten" for v in r["violations"])


def test_check_loop_bypass_lit_aussi_solvability_racine(tmp_path):
    game = tmp_path / "game"
    game.mkdir()
    (game / "solvability.gd").write_text(
        'const Economy = preload("res://05_SYSTEMS/economy/economy.gd")\n', encoding="utf-8")
    r = pog.check_loop_bypass(game)
    assert r["passed"] is False
    assert any(v["fichier"].endswith("solvability.gd") and v["token"] == "Economy" for v in r["violations"])


# --- mesure RÉELLE sur le build du run 6 (baseline, kitten_clicker) ---------
# Vérifié par grep AVANT d'écrire ces assertions (pas une supposition) :
#   07_TESTS/oracle/main_screen_render.gd:82  -> _main.api_buy_kitten()
#   07_TESTS/oracle/core_audio.gd             -> api_buy_kitten / api_prestige / 05_SYSTEMS
#   GAMES/kitten_clicker/solvability.gd       -> Economy (+ 05_SYSTEMS)


@pytest.mark.skipif(not (KITTEN / "project.godot").exists(), reason="archive du build run 6 introuvable")
def test_check_loop_bypass_sur_run6_mesure_les_violations_connues():
    r = pog.check_loop_bypass(KITTEN)
    assert r["passed"] is False
    fichiers_violations = {Path(v["fichier"]).name: v["token"] for v in r["violations"]}
    assert "main_screen_render.gd" in fichiers_violations
    assert fichiers_violations["main_screen_render.gd"] == "api_buy_kitten"
    assert "core_audio.gd" in fichiers_violations
    assert "solvability.gd" in fichiers_violations


# --- check_economy_bypass (Lot B, T3, 2026-08-23, contrat s9 regle (14)) ----


def _gd_file(game_dir: Path, rel: str, body: str) -> Path:
    p = game_dir / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(body, encoding="utf-8")
    return p


def test_check_economy_bypass_passe_sans_05_systems(tmp_path):
    game = tmp_path / "game"
    game.mkdir()
    assert pog.check_economy_bypass(game) == {"passed": True, "violations": []}


def test_check_economy_bypass_passe_sur_constante_non_economique(tmp_path):
    game = tmp_path / "game"
    _gd_file(game, "05_SYSTEMS/misc/misc.gd", "const MIN_KITTENS: int = 6\n")
    r = pog.check_economy_bypass(game)
    assert r == {"passed": True, "violations": []}


def test_check_economy_bypass_detecte_step_dans_pricing(tmp_path):
    game = tmp_path / "game"
    _gd_file(game, "05_SYSTEMS/pricing/pricing.gd", (
        "const KITTEN_BASE: int = 5\n"
        "const KITTEN_STEP: int = 5\n"
        "const UPGRADE_BASE: int = 8\n"
        "const UPGRADE_STEP: int = 4\n"
    ))
    r = pog.check_economy_bypass(game)
    assert r["passed"] is False
    noms = {v["nom"] for v in r["violations"]}
    assert noms == {"KITTEN_STEP", "UPGRADE_STEP"}
    for v in r["violations"]:
        assert v["fichier"].endswith("pricing.gd")
        assert v["ligne"] > 0


def test_check_economy_bypass_detecte_base_click_et_passive_unit(tmp_path):
    game = tmp_path / "game"
    _gd_file(game, "05_SYSTEMS/economy/economy.gd", (
        "const BASE_CLICK: int = 10\n"
        "const PASSIVE_UNIT: float = 0.5\n"
    ))
    r = pog.check_economy_bypass(game)
    noms = {v["nom"] for v in r["violations"]}
    assert noms == {"BASE_CLICK", "PASSIVE_UNIT"}


def test_check_economy_bypass_detecte_prestige_threshold(tmp_path):
    game = tmp_path / "game"
    _gd_file(game, "05_SYSTEMS/prestige/prestige.gd", (
        "const PRESTIGE_THRESHOLD: int = 1\n"
        "const COOLDOWN_FRAMES: int = 45\n"  # pas de token economique -> pas de violation
    ))
    r = pog.check_economy_bypass(game)
    noms = {v["nom"] for v in r["violations"]}
    assert noms == {"PRESTIGE_THRESHOLD"}


def test_check_economy_bypass_mention_en_commentaire_seule_nest_pas_une_violation(tmp_path):
    game = tmp_path / "game"
    _gd_file(game, "05_SYSTEMS/x/x.gd", "# const KITTEN_STEP: int = 5 (retire)\nfunc _init():\n\tpass\n")
    assert pog.check_economy_bypass(game) == {"passed": True, "violations": []}


def test_check_economy_bypass_var_declaree_compte_aussi(tmp_path):
    game = tmp_path / "game"
    _gd_file(game, "05_SYSTEMS/x/x.gd", "var upgrade_step = 4\n")
    r = pog.check_economy_bypass(game)
    assert any(v["nom"] == "upgrade_step" for v in r["violations"])


def test_check_economy_bypass_exempte_quand_registre_economy_json_charge_et_referencee_par_dict(tmp_path):
    game = tmp_path / "game"
    _gd_file(game, "05_SYSTEMS/economy/registry.gd", (
        'const KITTEN_STEP: int = 5\n'  # nom present mais utilise comme CLE, pas comme source
        'var _data: Dictionary = {}\n'
        'func _init():\n'
        '\t_data = FileAccess.get_file_as_string("res://03_WORLD/economy.json")\n'
        'func step() -> int:\n'
        '\treturn _data["KITTEN_STEP"]\n'
    ))
    r = pog.check_economy_bypass(game)
    assert r == {"passed": True, "violations": []}


def test_check_economy_bypass_registre_charge_mais_constante_non_referencee_par_dict_reste_violation(tmp_path):
    game = tmp_path / "game"
    _gd_file(game, "05_SYSTEMS/economy/half_registry.gd", (
        'const KITTEN_STEP: int = 5\n'
        'func _init():\n'
        '\tFileAccess.open("res://03_WORLD/economy.json", FileAccess.READ)\n'
        # jamais de reference dict a KITTEN_STEP -> pas exempte
    ))
    r = pog.check_economy_bypass(game)
    assert r["passed"] is False
    assert any(v["nom"] == "KITTEN_STEP" for v in r["violations"])


def test_check_economy_bypass_economy_json_absent_du_run_dir_est_une_violation(tmp_path):
    game = tmp_path / "game"
    game.mkdir()
    r = pog.check_economy_bypass(game, economy_json=tmp_path / "run" / "economy.json")
    assert r["passed"] is False
    assert any(v["nom"] == "economy_json_absent" for v in r["violations"])


def test_check_economy_bypass_economy_json_absent_du_jeu_est_une_violation(tmp_path):
    game = tmp_path / "game"
    game.mkdir()
    run_economy = tmp_path / "run" / "economy.json"
    run_economy.parent.mkdir(parents=True, exist_ok=True)
    run_economy.write_text("{}", encoding="utf-8")
    r = pog.check_economy_bypass(game, economy_json=run_economy)
    assert r["passed"] is False
    assert any(v["nom"] == "economy_json_absent" for v in r["violations"])


def test_check_economy_bypass_economy_json_sha_egal_ne_declenche_rien(tmp_path):
    game = tmp_path / "game"
    (game / "03_WORLD").mkdir(parents=True, exist_ok=True)
    (game / "03_WORLD" / "economy.json").write_text('{"a": 1}', encoding="utf-8")
    run_economy = tmp_path / "run" / "economy.json"
    run_economy.parent.mkdir(parents=True, exist_ok=True)
    run_economy.write_text('{"a": 1}', encoding="utf-8")
    r = pog.check_economy_bypass(game, economy_json=run_economy)
    assert r == {"passed": True, "violations": []}


def test_check_economy_bypass_economy_json_sha_different_est_une_violation_alteree(tmp_path):
    game = tmp_path / "game"
    (game / "03_WORLD").mkdir(parents=True, exist_ok=True)
    (game / "03_WORLD" / "economy.json").write_text('{"a": 2}', encoding="utf-8")
    run_economy = tmp_path / "run" / "economy.json"
    run_economy.parent.mkdir(parents=True, exist_ok=True)
    run_economy.write_text('{"a": 1}', encoding="utf-8")
    r = pog.check_economy_bypass(game, economy_json=run_economy)
    assert r["passed"] is False
    assert any(v["nom"] == "economy_json_altere" for v in r["violations"])


# --- mesure REELLE sur le build du run 9 (baseline, kitten_clicker) ----------
# Baseline mesuree Lot B T3 (2026-08-23) : violations >= 4 (fige ce qui est
# MESURE, pas un nom particulier — cf. plan). Grep prealable :
#   pricing.gd   -> KITTEN_STEP, UPGRADE_STEP (contiennent STEP)
#   economy.gd   -> BASE_CLICK, PASSIVE_UNIT (BASE_CLICK exact, UNIT substring)
#   prestige.gd  -> PRESTIGE_THRESHOLD (THRESHOLD substring)

RUN9_BUILD = REPO / "EVIDENCE" / "runs" / "kitten_clicker" / "_run9_20260823a" / "game_build9"


@pytest.mark.skipif(not (RUN9_BUILD / "project.godot").exists(), reason="archive du build run 9 introuvable")
def test_check_economy_bypass_sur_run9_mesure_au_moins_4_violations():
    r = pog.check_economy_bypass(RUN9_BUILD)
    assert r["passed"] is False
    noms = {v["nom"] for v in r["violations"]}
    assert len(r["violations"]) >= 4, noms
    assert "KITTEN_STEP" in noms
    assert "UPGRADE_STEP" in noms
    assert "BASE_CLICK" in noms
    assert "PASSIVE_UNIT" in noms
    assert "PRESTIGE_THRESHOLD" in noms

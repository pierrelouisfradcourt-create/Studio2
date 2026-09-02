"""Couverture RED/GREEN du fournisseur GODOT (`forge.product_oracle_godot`) —
pendant du fournisseur WEB (`forge.product_oracle`, NON modifié, couvert par
`test_product_oracle.py`). Ces tests n'invoquent JAMAIS un vrai binaire Godot :
`binary_resolver`/`runner` sont injectés (même patron que
`test_driver_product_oracle.py` pour `mutation_runner`). NOTE DE FRAÎCHEUR : la
rédaction précédente affirmait ici que le binaire était « ABSENT de ce poste
(`godot.config.json` pointe un chemin qui n'existe plus, 2026-07-29) » — FAUX
depuis, vérifié le 2026-08-10 en exécutant le binaire déclaré. Ces tests
restent volontairement sans binaire réel : la preuve d'exécution GPU se fait
hors suite (lot L0b), la suite ne prouve que le ROUTAGE.
"""
import json

from forge.product_oracle_godot import (
    GPU_WINDOW_FLAGS,
    discover_oracle_files,
    has_godot_capacity,
    run_godot_product_oracle,
    check_economy_bypass,
)


def _oracle_gd(root, name, *, marker=True, gpu_directive=False):
    """Dépose un faux fichier `.gd` d'oracle sous `<root>/07_TESTS/oracle/`.
    `gpu_directive` ajoute la DIRECTIVE STATIQUE de mode d'exécution.

    Charge la VRAIE scène (`load("res://main.tscn")`) pour satisfaire la garde
    statique anti-gaming de Task 3 (`_VOLET_REAL_SCENE`) : cette suite mesure
    le ROUTAGE et le protocole `FORGE_ORACLE`, pas cette garde-là (couverte
    par `test_volets_load_real_scene.py`) — un volet synthétique sans ce
    chargement serait rejeté avant même d'atteindre le runner injecté."""
    oracle_dir = root / "07_TESTS" / "oracle"
    oracle_dir.mkdir(parents=True, exist_ok=True)
    body = f'# Sortie : "FORGE_ORACLE {name} {{json}}"\nextends SceneTree\n' if marker else "extends SceneTree\n"
    body += 'var _scene = load("res://main.tscn")\n'
    if gpu_directive:
        body = "# forge:run_mode = gpu_window\n" + body
    (oracle_dir / f"{name}.gd").write_text(body, encoding="utf-8")
    return oracle_dir / f"{name}.gd"


# --- discover_oracle_files / has_godot_capacity (condition (b), correction ①) -------


def test_discover_oracle_files_ne_retient_que_les_fichiers_avec_marqueur(tmp_path):
    _oracle_gd(tmp_path, "core_boot")
    _oracle_gd(tmp_path, "sans_marqueur", marker=False)
    found = discover_oracle_files(tmp_path)
    names = sorted(p.stem for p in found)
    assert names == ["core_boot"]


def test_discover_oracle_files_vide_si_dossier_absent(tmp_path):
    assert discover_oracle_files(tmp_path / "inexistant") == []
    assert has_godot_capacity(tmp_path / "inexistant") is False


def test_has_godot_capacity_vrai_si_au_moins_un_oracle(tmp_path):
    _oracle_gd(tmp_path, "core_boot")
    assert has_godot_capacity(tmp_path) is True


def test_discover_oracle_files_ordre_deterministe(tmp_path):
    _oracle_gd(tmp_path, "zeta")
    _oracle_gd(tmp_path, "alpha")
    found = discover_oracle_files(tmp_path)
    assert [p.stem for p in found] == ["alpha", "zeta"]


# --- binaire introuvable => TOUS les volets NOT_MEASURED, motivés -------------------


def test_binaire_absent_rend_tous_les_volets_not_measured_motives(tmp_path):
    _oracle_gd(tmp_path, "core_boot")
    _oracle_gd(tmp_path, "core_exit")

    def resolver_absent():
        raise FileNotFoundError("binaire Godot non configuré (poste sans installation)")

    out = run_godot_product_oracle(tmp_path, binary_resolver=resolver_absent)
    assert set(out.keys()) == {"core_boot", "core_exit"}
    for volet in out.values():
        assert volet["status"] == "NOT_MEASURED"
        assert volet["passed"] is False
        assert "binaire" in volet["reason"].lower() or "godot" in volet["reason"].lower()


def test_aucun_oracle_decouvert_rend_mapping_vide_sans_appeler_le_resolver(tmp_path):
    calls = []

    def resolver(*_a, **_kw):
        calls.append(1)
        return "fake_bin"

    out = run_godot_product_oracle(tmp_path, binary_resolver=resolver)
    assert out == {}
    assert calls == []  # pas d'oracle => jamais besoin de résoudre le binaire


# --- L0b : routage du mode d'exécution par DIRECTIVE STATIQUE, jamais par nom --------


def test_volet_avec_directive_gpu_est_route_vers_le_runner_gpu(tmp_path):
    """La directive `forge:run_mode = gpu_window` route vers `gpu_runner`, et le volet
    est RÉELLEMENT EXÉCUTÉ (l'ancien comportement le sautait sans jamais le lancer)."""
    _oracle_gd(tmp_path, "core_render_frame", gpu_directive=True)
    headless_calls, gpu_calls = [], []

    def headless(binary, game_dir, script, *, timeout_s):
        headless_calls.append(script)
        return {"returncode": 1, "stdout": _stdout_for("core_render_frame", False), "stderr": ""}

    def gpu(binary, game_dir, script, *, timeout_s):
        gpu_calls.append(script)
        return {"returncode": 0, "stdout": _stdout_for("core_render_frame", True), "stderr": ""}

    out = run_godot_product_oracle(
        tmp_path, binary_resolver=lambda: "fake_bin", runner=headless, gpu_runner=gpu)
    assert gpu_calls and not headless_calls
    assert out["core_render_frame"]["status"] == "OK"
    assert out["core_render_frame"]["passed"] is True
    assert out["core_render_frame"]["mode_execution"] == "gpu_window"


def test_sans_directive_le_volet_reste_en_headless(tmp_path):
    _oracle_gd(tmp_path, "core_boot")
    headless_calls, gpu_calls = [], []

    def headless(binary, game_dir, script, *, timeout_s):
        headless_calls.append(script)
        return {"returncode": 0, "stdout": _stdout_for("core_boot", True), "stderr": ""}

    def gpu(binary, game_dir, script, *, timeout_s):
        gpu_calls.append(script)
        return {"returncode": 0, "stdout": _stdout_for("core_boot", True), "stderr": ""}

    out = run_godot_product_oracle(
        tmp_path, binary_resolver=lambda: "fake_bin", runner=headless, gpu_runner=gpu)
    assert headless_calls and not gpu_calls
    assert out["core_boot"]["mode_execution"] == "headless"


def test_le_nom_du_volet_ne_decide_plus_du_mode(tmp_path):
    """RÉGRESSION INVERSE du comportement retiré : un volet nommé `core_render_frame`
    SANS directive n'est plus exempté d'exécution. Le nom ne décide de rien."""
    _oracle_gd(tmp_path, "core_render_frame")  # même nom qu'avant, aucune directive
    calls = []

    def runner(binary, game_dir, script, *, timeout_s):
        calls.append(script)
        return {"returncode": 0, "stdout": _stdout_for("core_render_frame", True), "stderr": ""}

    out = run_godot_product_oracle(
        tmp_path, binary_resolver=lambda: "fake_bin", runner=runner)
    assert calls, "le volet doit être exécuté : plus aucun nom n'est codé en dur"
    assert out["core_render_frame"]["mode_execution"] == "headless"


def test_marqueur_de_payload_rend_not_measured_meme_en_mode_gpu(tmp_path):
    """Le marqueur d'EXÉCUTION reste autorité sur le verdict DANS LES DEUX MODES :
    un volet lancé en fenêtre GPU qui déclare n'avoir rien mesuré n'est jamais un FAIL
    fabriqué (leçon forge.oracle_fail_vs_not_measured_marker)."""
    _oracle_gd(tmp_path, "core_render", gpu_directive=True)

    def gpu(binary, game_dir, script, *, timeout_s):
        payload = {"ok": False, "requires_gpu_window": True, "fails": ["rien à capturer"]}
        return {"returncode": 0,
                "stdout": f"FORGE_ORACLE core_render {json.dumps(payload)}", "stderr": ""}

    out = run_godot_product_oracle(
        tmp_path, binary_resolver=lambda: "fake_bin", runner=gpu, gpu_runner=gpu)
    assert out["core_render"]["status"] == "NOT_MEASURED"
    assert out["core_render"]["passed"] is False
    assert out["core_render"]["mode_execution"] == "gpu_window"
    assert "oracle_fail_vs_not_measured_marker" in out["core_render"]["reason"]


def test_marqueur_de_payload_rend_not_measured_en_headless(tmp_path):
    """Comportement Tetris INCHANGÉ par L0b : `core_render.gd` s'exécute en headless,
    déclare `requires_gpu_window`, et reste NOT_MEASURED — jamais FAIL."""
    _oracle_gd(tmp_path, "core_render")

    def runner(binary, game_dir, script, *, timeout_s):
        payload = {"ok": False, "requires_gpu_window": True, "fails": ["headless"]}
        return {"returncode": 0,
                "stdout": f"FORGE_ORACLE core_render {json.dumps(payload)}", "stderr": ""}

    out = run_godot_product_oracle(
        tmp_path, binary_resolver=lambda: "fake_bin", runner=runner)
    assert out["core_render"]["status"] == "NOT_MEASURED"
    assert out["core_render"]["mode_execution"] == "headless"


def test_gpu_runner_retombe_sur_le_runner_injecte(tmp_path):
    """Un test qui n'injecte QU'UN runner n'ouvre jamais une vraie fenêtre Godot."""
    _oracle_gd(tmp_path, "core_render_frame", gpu_directive=True)
    calls = []

    def runner(binary, game_dir, script, *, timeout_s):
        calls.append(script)
        return {"returncode": 0, "stdout": _stdout_for("core_render_frame", True), "stderr": ""}

    out = run_godot_product_oracle(
        tmp_path, binary_resolver=lambda: "fake_bin", runner=runner)
    assert calls
    assert out["core_render_frame"]["status"] == "OK"
    assert out["core_render_frame"]["mode_execution"] == "gpu_window"


def test_les_drapeaux_gpu_sont_ceux_mesures_et_jamais_headless(tmp_path):
    """Garde de non-régression sur la commande GPU : le mode GPU ne doit JAMAIS
    embarquer `--headless` (driver dummy = texture nulle, la preuve pixel disparaît)."""
    assert "--headless" not in GPU_WINDOW_FLAGS
    assert "vulkan" in GPU_WINDOW_FLAGS
    assert "--position" in GPU_WINDOW_FLAGS


# --- oracle vert / rouge (parsing de la ligne FORGE_ORACLE) -------------------------


def _stdout_for(name, ok, fails=None):
    payload = {"ok": ok, "fails": fails or []}
    return f"some godot boot noise\nFORGE_ORACLE {name} {json.dumps(payload)}\n"


def test_oracle_vert_rend_le_volet_ok(tmp_path):
    _oracle_gd(tmp_path, "core_boot")

    def runner(binary, game_dir, script, *, timeout_s):
        return {"returncode": 0, "stdout": _stdout_for("core_boot", True), "stderr": ""}

    out = run_godot_product_oracle(
        tmp_path, binary_resolver=lambda: "fake_bin", runner=runner)
    assert out["core_boot"]["status"] == "OK"
    assert out["core_boot"]["passed"] is True
    assert out["core_boot"]["fails"] == []


def test_oracle_rouge_rend_le_volet_fail(tmp_path):
    _oracle_gd(tmp_path, "core_boot")

    def runner(binary, game_dir, script, *, timeout_s):
        return {
            "returncode": 1,
            "stdout": _stdout_for("core_boot", False, ["statut initial != EN_COURS"]),
            "stderr": "",
        }

    out = run_godot_product_oracle(
        tmp_path, binary_resolver=lambda: "fake_bin", runner=runner)
    assert out["core_boot"]["status"] == "FAIL"
    assert out["core_boot"]["passed"] is False
    assert out["core_boot"]["fails"] == ["statut initial != EN_COURS"]


# --- robustesse : sortie illisible / JSON invalide / timeout / exception -----------


def test_sortie_illisible_rend_not_measured(tmp_path):
    _oracle_gd(tmp_path, "core_boot")

    def runner(binary, game_dir, script, *, timeout_s):
        return {"returncode": 1, "stdout": "boom, no forge oracle line here", "stderr": "trace"}

    out = run_godot_product_oracle(
        tmp_path, binary_resolver=lambda: "fake_bin", runner=runner)
    assert out["core_boot"]["status"] == "NOT_MEASURED"
    assert out["core_boot"]["passed"] is False


def test_json_invalide_rend_not_measured(tmp_path):
    _oracle_gd(tmp_path, "core_boot")

    def runner(binary, game_dir, script, *, timeout_s):
        return {"returncode": 0, "stdout": "FORGE_ORACLE core_boot {not-json", "stderr": ""}

    out = run_godot_product_oracle(
        tmp_path, binary_resolver=lambda: "fake_bin", runner=runner)
    assert out["core_boot"]["status"] == "NOT_MEASURED"


def test_timeout_rend_not_measured(tmp_path):
    _oracle_gd(tmp_path, "core_boot")

    def runner(binary, game_dir, script, *, timeout_s):
        return {"ok": None, "timeout": True, "returncode": None, "stdout": "", "stderr": ""}

    out = run_godot_product_oracle(
        tmp_path, binary_resolver=lambda: "fake_bin", runner=runner)
    assert out["core_boot"]["status"] == "NOT_MEASURED"
    assert "timeout" in out["core_boot"]["reason"].lower()


def test_exception_du_runner_ne_remonte_jamais(tmp_path):
    _oracle_gd(tmp_path, "core_boot")

    def boom(binary, game_dir, script, *, timeout_s):
        raise RuntimeError("panne fabriquée")

    out = run_godot_product_oracle(
        tmp_path, binary_resolver=lambda: "fake_bin", runner=boom)
    assert out["core_boot"]["status"] == "NOT_MEASURED"
    assert "panne fabriquée" in out["core_boot"]["reason"]


def test_champ_ok_absent_ou_non_booleen_rend_not_measured(tmp_path):
    _oracle_gd(tmp_path, "core_boot")

    def runner(binary, game_dir, script, *, timeout_s):
        return {"returncode": 0, "stdout": 'FORGE_ORACLE core_boot {"fails": []}', "stderr": ""}

    out = run_godot_product_oracle(
        tmp_path, binary_resolver=lambda: "fake_bin", runner=runner)
    assert out["core_boot"]["status"] == "NOT_MEASURED"


# --- check_economy_bypass est exportee par ce module (Lot B, T3, 2026-08-23) -
# Couverture detaillee : forge/tests/test_loop_bypass_guard.py.


def test_check_economy_bypass_est_importable_et_a_la_forme_attendue(tmp_path):
    r = check_economy_bypass(tmp_path)
    assert set(r.keys()) == {"passed", "violations"}
    assert r == {"passed": True, "violations": []}

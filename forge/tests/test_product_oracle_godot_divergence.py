"""Couverture RED/GREEN de l'oracle de divergence produit (P6, invariant INV-4) —
`forge.product_oracle_godot.run_divergence_oracle` et ses helpers de découverte.

Deux paliers, comme `test_asset_geometry.py` (patron `_godot_bin()`/`skipif`) :
  1. Tests INJECTÉS (`binary_resolver`/`runner` fictifs) — jamais un vrai binaire Godot,
     couvrent le parsing, la robustesse (NOT_MEASURED) et la logique de découverte.
  2. Tests RÉELS, `skipif` si le binaire Godot est absent — rejouent le CAS HISTORIQUE
     (mode Pac-Man neutralisé, reconstitué en SANDBOX hors GAMES/**) et le CAS CORRIGÉ
     (GAMES/pacman réel, jamais modifié, chargé en LECTURE SEULE) via
     EVIDENCE/bundles/DIVERGENCE_ORACLE_V1/adapters/pacman_mode_adapter.gd.
"""
import json
from pathlib import Path

import pytest

from forge.product_oracle_godot import (
    DIVERGENCE_PROBE_PATH,
    discover_divergence_manifest,
    has_divergence_capacity,
    run_divergence_oracle,
)

REPO = Path(__file__).resolve().parents[2]
EVIDENCE_DIR = REPO / "EVIDENCE" / "bundles" / "DIVERGENCE_ORACLE_V1"
ADAPTER = EVIDENCE_DIR / "adapters" / "pacman_mode_adapter.gd"
SANDBOX_DEFECT = EVIDENCE_DIR / "sandbox_v5_defect"
PACMAN_REAL = REPO / "GAMES" / "pacman"


def _manifest(root: Path, params: list) -> Path:
    oracle_dir = root / "07_TESTS" / "oracle"
    oracle_dir.mkdir(parents=True, exist_ok=True)
    path = oracle_dir / "divergence_manifest.json"
    path.write_text(json.dumps({"params": params}), encoding="utf-8")
    return path


# --- discover_divergence_manifest / has_divergence_capacity -------------------------


def test_manifeste_absent_rend_none_et_capacite_fausse(tmp_path):
    assert discover_divergence_manifest(tmp_path) is None
    assert has_divergence_capacity(tmp_path) is False


def test_manifeste_json_invalide_rend_none(tmp_path):
    oracle_dir = tmp_path / "07_TESTS" / "oracle"
    oracle_dir.mkdir(parents=True)
    (oracle_dir / "divergence_manifest.json").write_text("{not json", encoding="utf-8")
    assert discover_divergence_manifest(tmp_path) is None
    assert has_divergence_capacity(tmp_path) is False


def test_manifeste_sans_cle_params_rend_none(tmp_path):
    oracle_dir = tmp_path / "07_TESTS" / "oracle"
    oracle_dir.mkdir(parents=True)
    (oracle_dir / "divergence_manifest.json").write_text(json.dumps({"autre": 1}), encoding="utf-8")
    assert discover_divergence_manifest(tmp_path) is None


def test_manifeste_valide_donne_capacite_vraie(tmp_path):
    _manifest(tmp_path, [{"id": "mode", "adapter": "res://x.gd", "values": [0, 1]}])
    assert has_divergence_capacity(tmp_path) is True
    manifest = discover_divergence_manifest(tmp_path)
    assert manifest["params"][0]["id"] == "mode"


def test_manifeste_params_vide_rend_capacite_fausse(tmp_path):
    _manifest(tmp_path, [])
    assert has_divergence_capacity(tmp_path) is False


def test_aucun_parametre_rend_mapping_vide_sans_appeler_le_resolver(tmp_path):
    _manifest(tmp_path, [])
    calls = []

    def resolver():
        calls.append(1)
        return "fake_bin"

    out = run_divergence_oracle(tmp_path, binary_resolver=resolver)
    assert out == {}
    assert calls == []


# --- binaire introuvable => tous les volets NOT_MEASURED, motivés -------------------


def test_binaire_absent_rend_tous_les_volets_not_measured(tmp_path):
    _manifest(tmp_path, [
        {"id": "mode", "adapter": "res://x.gd", "values": [0, 1]},
        {"id": "vitesse", "adapter": "res://y.gd", "values": [1, 2]},
    ])

    def resolver_absent():
        raise FileNotFoundError("binaire Godot non configuré (poste sans installation)")

    out = run_divergence_oracle(tmp_path, binary_resolver=resolver_absent)
    assert set(out.keys()) == {"divergence_mode", "divergence_vitesse"}
    for volet in out.values():
        assert volet["status"] == "NOT_MEASURED"
        assert volet["passed"] is False


# --- déclaration incomplète => NOT_MEASURED, jamais d'exécution ---------------------


def test_adapter_manquant_rend_not_measured_sans_executer(tmp_path):
    _manifest(tmp_path, [{"id": "mode", "values": [0, 1]}])
    calls = []

    def runner(*_a, **_kw):
        calls.append(1)
        return {"returncode": 0, "stdout": "", "stderr": ""}

    out = run_divergence_oracle(tmp_path, binary_resolver=lambda: "fake_bin", runner=runner)
    assert out["divergence_mode"]["status"] == "NOT_MEASURED"
    assert "adapter" in out["divergence_mode"]["reason"]
    assert calls == []


def test_moins_de_deux_valeurs_rend_not_measured(tmp_path):
    _manifest(tmp_path, [{"id": "mode", "adapter": "res://x.gd", "values": [0]}])
    out = run_divergence_oracle(tmp_path, binary_resolver=lambda: "fake_bin",
                                 runner=lambda *a, **k: {"returncode": 0, "stdout": "", "stderr": ""})
    assert out["divergence_mode"]["status"] == "NOT_MEASURED"
    assert "values" in out["divergence_mode"]["reason"]


# --- parsing FORGE_ORACLE injecté : vert / rouge / robustesse -----------------------


def _stdout_for(param, payload_extra):
    payload = {"ok": True, "fails": []}
    payload.update(payload_extra)
    return f"boot noise\nFORGE_ORACLE divergence_{param} {json.dumps(payload)}\n"


def test_parametre_avec_divergence_reelle_et_controle_propre_rend_ok(tmp_path):
    _manifest(tmp_path, [{"id": "mode", "adapter": "res://x.gd", "values": [0, 1]}])

    def runner(binary, game_dir, script, user_args, *, timeout_s):
        assert str(script) == str(DIVERGENCE_PROBE_PATH)
        assert any(a == "--param=mode" for a in user_args)
        payload = {
            "ok": True, "fails": [],
            "controle": {"ticks": 200, "ticks_divergents": 0, "cles": []},
            "reel": {"ticks": 200, "ticks_divergents": 200, "cles": ["vies"]},
            "cout_ms": 700,
        }
        return {"returncode": 0, "stdout": f"FORGE_ORACLE divergence_mode {json.dumps(payload)}\n", "stderr": ""}

    out = run_divergence_oracle(tmp_path, binary_resolver=lambda: "fake_bin", runner=runner)
    volet = out["divergence_mode"]
    assert volet["status"] == "OK"
    assert volet["passed"] is True
    assert volet["controle"]["ticks_divergents"] == 0
    assert volet["reel"]["cles"] == ["vies"]
    assert volet["cout_ms"] == 700
    assert isinstance(volet["host_duration_ms"], int)


def test_parametre_inerte_rend_fail_avec_nom_et_cles(tmp_path):
    _manifest(tmp_path, [{"id": "mode", "adapter": "res://x.gd", "values": [0, 1]}])

    def runner(binary, game_dir, script, user_args, *, timeout_s):
        payload = {
            "ok": False,
            "fails": ["PARAMETRE INERTE: 'mode' — 0 divergence sur 200 tics"],
            "controle": {"ticks": 200, "ticks_divergents": 0, "cles": []},
            "reel": {"ticks": 200, "ticks_divergents": 0, "cles": []},
            "cout_ms": 500,
        }
        return {"returncode": 1, "stdout": f"FORGE_ORACLE divergence_mode {json.dumps(payload)}\n", "stderr": ""}

    out = run_divergence_oracle(tmp_path, binary_resolver=lambda: "fake_bin", runner=runner)
    volet = out["divergence_mode"]
    assert volet["status"] == "FAIL"
    assert volet["passed"] is False
    assert "mode" in volet["fails"][0]


def test_controle_bruite_rend_fail(tmp_path):
    """Le CONTRÔLE NÉGATIF (même valeur des deux côtés) doit trouver 0 divergence —
    s'il en trouve, la mesure elle-même est bruitée et le volet doit le dire, jamais
    prétendre que le paramètre a un effet."""
    _manifest(tmp_path, [{"id": "mode", "adapter": "res://x.gd", "values": [0, 1]}])

    def runner(binary, game_dir, script, user_args, *, timeout_s):
        payload = {
            "ok": False,
            "fails": ["CONTROLE BRUITE: 3/200 tics divergent entre deux campagnes de LA MEME valeur"],
            "controle": {"ticks": 200, "ticks_divergents": 3, "cles": ["horloge"]},
            "reel": {"ticks": 200, "ticks_divergents": 200, "cles": ["vies", "horloge"]},
            "cout_ms": 650,
        }
        return {"returncode": 1, "stdout": f"FORGE_ORACLE divergence_mode {json.dumps(payload)}\n", "stderr": ""}

    out = run_divergence_oracle(tmp_path, binary_resolver=lambda: "fake_bin", runner=runner)
    assert out["divergence_mode"]["status"] == "FAIL"
    assert "CONTROLE" in out["divergence_mode"]["fails"][0]


def test_timeout_rend_not_measured(tmp_path):
    _manifest(tmp_path, [{"id": "mode", "adapter": "res://x.gd", "values": [0, 1]}])

    def runner(*_a, **_kw):
        return {"timeout": True}

    out = run_divergence_oracle(tmp_path, binary_resolver=lambda: "fake_bin", runner=runner)
    assert out["divergence_mode"]["status"] == "NOT_MEASURED"


def test_sortie_illisible_rend_not_measured(tmp_path):
    _manifest(tmp_path, [{"id": "mode", "adapter": "res://x.gd", "values": [0, 1]}])

    def runner(*_a, **_kw):
        return {"returncode": 1, "stdout": "no forge oracle line here", "stderr": ""}

    out = run_divergence_oracle(tmp_path, binary_resolver=lambda: "fake_bin", runner=runner)
    assert out["divergence_mode"]["status"] == "NOT_MEASURED"


def test_exception_du_runner_rend_not_measured_sans_bloquer(tmp_path):
    _manifest(tmp_path, [
        {"id": "mode", "adapter": "res://x.gd", "values": [0, 1]},
        {"id": "vitesse", "adapter": "res://y.gd", "values": [1, 2]},
    ])

    def runner(binary, game_dir, script, user_args, *, timeout_s):
        if "--param=mode" in user_args:
            raise RuntimeError("spawn KO")
        payload = {"ok": True, "fails": [],
                   "controle": {"ticks": 1, "ticks_divergents": 0, "cles": []},
                   "reel": {"ticks": 1, "ticks_divergents": 1, "cles": ["x"]}}
        return {"returncode": 0, "stdout": f"FORGE_ORACLE divergence_vitesse {json.dumps(payload)}\n", "stderr": ""}

    out = run_divergence_oracle(tmp_path, binary_resolver=lambda: "fake_bin", runner=runner)
    assert out["divergence_mode"]["status"] == "NOT_MEASURED"
    assert out["divergence_vitesse"]["status"] == "OK"


# =====================================================================================
# PALIER 2 — RÉEL, binaire Godot requis (skipif). Rejeu du CAS HISTORIQUE (sandbox
# défaut reconstitué) et du CAS CORRIGÉ (GAMES/pacman réel, lecture seule).
# =====================================================================================


def _godot_bin() -> Path | None:
    cfg = REPO / "forge" / "godot.config.json"
    if not cfg.is_file():
        return None
    p = Path(json.loads(cfg.read_text(encoding="utf-8")).get("godot_bin", ""))
    return p if p.is_file() else None


_GODOT_OK = _godot_bin() is not None
_FIXTURES_OK = ADAPTER.is_file() and SANDBOX_DEFECT.is_dir() and PACMAN_REAL.is_dir()


def _manifest_mode_param(root: Path, adapter_path: Path) -> None:
    _manifest(root, [{
        "id": "mode",
        "adapter": str(adapter_path).replace("\\", "/"),
        "values": [0, 1],
        "seed": 7,
        "ticks": 200,
        "ignore_keys": ["mode_jeu"],
    }])


@pytest.mark.gpu_window  # lance le VRAI binaire Godot (fenêtre) — T-GPU sur GO explicite seul
@pytest.mark.skipif(not _GODOT_OK, reason="binaire Godot absent (godot.config.json)")
@pytest.mark.skipif(not _FIXTURES_OK, reason="artefacts de preuve DIVERGENCE_ORACLE_V1 absents")
def test_reel_detecte_le_defaut_historique_mode_inerte():
    """Rejeu du défaut V5 (mode neutralisé dans le SANDBOX, hors GAMES/**, jamais le
    produit gelé) : l'oracle DOIT trouver 0 divergence réelle et rendre FAIL, nommant
    le paramètre."""
    _manifest_mode_param(SANDBOX_DEFECT, ADAPTER)
    out = run_divergence_oracle(SANDBOX_DEFECT, timeout_s=120)
    volet = out["divergence_mode"]
    assert volet["status"] == "FAIL", volet
    assert volet["controle"]["ticks_divergents"] == 0, "le contrôle doit rester propre"
    assert volet["reel"]["ticks_divergents"] == 0, "le défaut mesuré : mode inerte"
    assert any("mode" in f for f in volet["fails"])


@pytest.mark.gpu_window  # lance le VRAI binaire Godot (fenêtre) — T-GPU sur GO explicite seul
@pytest.mark.skipif(not _GODOT_OK, reason="binaire Godot absent (godot.config.json)")
@pytest.mark.skipif(not _FIXTURES_OK, reason="artefacts de preuve DIVERGENCE_ORACLE_V1 absents")
def test_reel_accepte_le_jeu_corrige_games_pacman_lecture_seule():
    """GAMES/pacman (produit gelé, JAMAIS écrit ici) accepté tel quel : le mode gouverne
    bien les vies depuis la correction V6. Le manifeste est déposé sous un dossier
    TEMPORAIRE (tmp_path) — jamais sous GAMES/pacman/07_TESTS/oracle/."""
    # `run_divergence_oracle` découvre son manifeste SOUS `game_dir` (convention) ; pour
    # vérifier GAMES/pacman SANS y écrire, ce test invoque le même chemin bas niveau que
    # la production suivrait une fois le manifeste déposé (fonction interne exposée
    # pour la preuve, jamais un fichier créé sous GAMES/pacman/**).
    from forge.product_oracle_godot import (
        _default_binary_resolver, _default_divergence_runner,
        _resolve_adapter_path, _parse_forge_oracle_line,
    )
    binary = _default_binary_resolver()
    user_args = [
        f"--adapter={_resolve_adapter_path(str(ADAPTER))}",
        "--param=mode", "--seed=7", "--ticks=200",
        "--value_a=0", "--value_b=1", "--ignore=mode_jeu",
    ]
    run_out = _default_divergence_runner(
        binary, PACMAN_REAL, DIVERGENCE_PROBE_PATH, user_args, timeout_s=120)
    parsed = _parse_forge_oracle_line(run_out["stdout"])
    assert parsed is not None, run_out
    payload = parsed["payload"]
    assert payload["ok"] is True, payload
    assert payload["controle"]["ticks_divergents"] == 0
    assert payload["reel"]["cles"] == ["vies"]
    assert payload["reel"]["ticks_divergents"] == 200

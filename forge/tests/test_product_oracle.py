"""Oracle PRODUIT (n3-oracle-produit-minimal) — les 3 volets déterministes qui
couvrent les 7 adaptateurs `system.adapter` sortis du gate mutation (décision
U-2, `forge.mutation_proof.MOTIF_EXCLUSION_PRESENTATION_RUNTIME`).

Discipline TDD stricte (contrat) : CHAQUE volet est montré ROUGE sur un cas
FABRIQUÉ (copie de fixture patchée) avant d'être accepté VERT sur le jeu réel
(GAMES/pong). Aucun test ici ne modifie GAMES/pong/** — les cas rouges
travaillent sur des COPIES écrites sous tmp_path (jamais git stash/checkout/
restore sur le dépôt réel).

NOT_MEASURED ≠ OK (garde-fou du contrat) : `check_visual_capture` ne rend
JAMAIS `status == "OK"` quand AUCUN volet n'a pu être mesuré.

W-2 (GO Pierre 2026-09-02) — l'agrégat porte désormais sur les volets APPLICABLES
(script présent) ET MESURÉS. Un moteur dont le script de capture est absent n'existe
pas pour ce jeu et n'entre pas dans l'agrégat ; un script présent mais non mesurable
reste listé dans `not_measured_volets` et n'emporte plus le statut. Motif : avant W-2,
un jeu purement web — 68 des 79 attentes `expected_proof.kind: visual` du dépôt — ne
pouvait jamais atteindre OK, la conjonction exigeant un volet Godot inapplicable.
"""
from __future__ import annotations

import json
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from forge.product_oracle import (  # noqa: E402
    check_auto_session,
    check_browser_import_safety,
    check_exit_stop_wiring,
    check_playable_speed_band,
    check_restart_offer_wiring,
    check_solo_ai_session,
    check_visual_capture,
    run_product_oracle,
)

_REPO_ROOT = Path(__file__).resolve().parents[2]
_PONG = _REPO_ROOT / "GAMES" / "pong"
_PRESENTATION = _PONG / "06_RUNTIME" / "adapters" / "presentation"

pytestmark = pytest.mark.skipif(
    shutil.which("node") is None, reason="node introuvable sur ce poste — oracle produit inexécutable")


# ============================================================================
# helpers de fixture — COPIENT le vrai code de Pong sous tmp_path (jamais de
# modification du dépôt réel), préservant la structure relative nécessaire aux
# imports ES relatifs.
# ============================================================================

def _copy(src: Path, dst: Path) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dst)


def _copy_browser_graph(tmp_path: Path) -> Path:
    """Copie le graphe RÉEL atteint depuis l'entrée navigateur (main.mjs + ses
    4 dépendances directes/transitives). Retourne le chemin de l'entrée copiée."""
    game = tmp_path / "pong_copy"
    pres = "06_RUNTIME/adapters/presentation"
    for rel in (
        f"{pres}/browser/main.mjs", f"{pres}/draw.mjs",
        f"{pres}/audio.mjs", f"{pres}/exit.mjs",
        "05_SYSTEMS/game_loop/loop.mjs", "05_SYSTEMS/game_state/state.mjs",
        "05_SYSTEMS/input/input.mjs",
    ):
        _copy(_PONG / rel, game / rel)
    return game / pres / "browser" / "main.mjs"


def _copy_pure_logic(tmp_path: Path) -> Path:
    """Copie SEULEMENT la logique pure (loop/state/input) — ce qu'utilise
    auto_session (3b), jamais un adaptateur de présentation."""
    game = tmp_path / "pong_copy"
    for rel in ("05_SYSTEMS/game_loop/loop.mjs", "05_SYSTEMS/game_state/state.mjs",
                "05_SYSTEMS/input/input.mjs"):
        _copy(_PONG / rel, game / rel)
    return game


def _copy_capture_graph(tmp_path: Path) -> Path:
    """Copie ce qu'exerce capture_browser.mjs (3c, volet navigateur) : lui-même,
    draw.mjs, raster.mjs, + la logique pure dont il dépend. PAS capture_godot.mjs
    (volontairement absent : ce test n'exerce QUE le volet navigateur)."""
    game = tmp_path / "pong_copy"
    pres = "06_RUNTIME/adapters/presentation"
    for rel in (
        f"{pres}/capture_browser.mjs", f"{pres}/draw.mjs", f"{pres}/raster.mjs",
        "05_SYSTEMS/game_loop/loop.mjs", "05_SYSTEMS/game_state/state.mjs",
        "05_SYSTEMS/input/input.mjs",
    ):
        _copy(_PONG / rel, game / rel)
    return game / pres


# ============================================================================
# 3a — browser_import_safety
# ============================================================================

def test_3a_rouge_import_node_reintroduit(tmp_path):
    """Réintroduit EXACTEMENT le défaut réel corrigé le 2026-07-26 : un import
    STATIQUE de `node:fs` dans un fichier atteint depuis l'entrée navigateur
    (audio.mjs). Le volet DOIT rougir — c'est le défaut que capture_browser.mjs
    ne pouvait structurellement pas voir (il ne charge jamais main.mjs)."""
    entry = _copy_browser_graph(tmp_path)
    audio_copy = entry.parent.parent / "audio.mjs"
    original = audio_copy.read_text(encoding="utf-8")
    bugged = "import { existsSync as _regression } from 'node:fs';\n" + original
    audio_copy.write_text(bugged, encoding="utf-8")

    result = check_browser_import_safety(entry)
    print("RED 3a (node: réintroduit):", json.dumps(result, ensure_ascii=False, indent=1))

    assert result["passed"] is False
    specs = {h["specifier"] for h in result["node_imports_atteignables"]}
    assert "node:fs" in specs
    assert any(str(audio_copy) == h["fichier"] for h in result["node_imports_atteignables"])


def test_3a_rouge_process_non_garde(tmp_path):
    """Réintroduit l'AUTRE défaut réel corrigé le 2026-07-26 : `process` référencé
    sans garde `typeof process !== 'undefined'` (exit.mjs avant fix)."""
    entry = _copy_browser_graph(tmp_path)
    exit_copy = entry.parent.parent / "exit.mjs"
    bugged = exit_copy.read_text(encoding="utf-8").replace(
        "if (typeof process !== 'undefined' && typeof process.exit === 'function') {\n"
        "    process.exit(0);\n"
        "  }",
        "process.exit(0);",
    )
    assert "process.exit(0);" in bugged and "typeof process.exit === 'function'" not in bugged
    exit_copy.write_text(bugged, encoding="utf-8")

    result = check_browser_import_safety(entry)
    print("RED 3a (process non gardé):", json.dumps(result, ensure_ascii=False, indent=1))

    assert result["passed"] is False
    assert any(str(exit_copy) == h["fichier"] for h in result["process_non_gardes"])


def test_3a_vert_sur_pong_reel():
    """Contrôle positif : le graphe RÉEL de Pong (post-fix 2026-07-26) est propre."""
    entry = _PRESENTATION / "browser" / "main.mjs"
    result = check_browser_import_safety(entry)
    print("GREEN 3a (Pong réel):", json.dumps(result, ensure_ascii=False, indent=1))

    assert result["passed"] is True
    assert result["node_imports_atteignables"] == []
    assert result["process_non_gardes"] == []
    # les 4 adaptateurs atteints depuis l'entrée navigateur sont bien scannés
    visited_names = {Path(f).name for f in result["fichiers_analyses"]}
    assert visited_names >= {"main.mjs", "draw.mjs", "audio.mjs", "exit.mjs"}
    # capture_browser.mjs/capture_godot.mjs/raster.mjs ne sont PAS atteints depuis
    # l'entrée navigateur (ce sont des outils Node séparés) — limite assumée du volet.
    assert "capture_browser.mjs" not in visited_names
    assert "raster.mjs" not in visited_names


def test_3a_entree_absente_blocked():
    result = check_browser_import_safety(Path("nawak/nexistepas/main.mjs"))
    assert result["passed"] is False
    assert result["checked"] is False


# ============================================================================
# 3b — auto_session
# ============================================================================

def test_3b_rouge_score_gele(tmp_path):
    """Fabrique un score GELÉ : le bloc d'incrémentation de score de loop.mjs est
    neutralisé (`if (false && scored)`), la partie ne peut plus jamais finir ni
    évoluer. max_ticks volontairement petit pour un test rapide."""
    game = _copy_pure_logic(tmp_path)
    loop_copy = game / "05_SYSTEMS" / "game_loop" / "loop.mjs"
    original = loop_copy.read_text(encoding="utf-8")
    assert "if (scored) {" in original
    bugged = original.replace("if (scored) {", "if (false && scored) {", 1)
    loop_copy.write_text(bugged, encoding="utf-8")

    result = check_auto_session(
        loop_copy, game / "05_SYSTEMS" / "game_state" / "state.mjs",
        game / "05_SYSTEMS" / "input" / "input.mjs",
        max_ticks=500, timeout_s=15,
    )
    print("RED 3b (score gelé):", json.dumps(result, ensure_ascii=False, indent=1))

    assert result["passed"] is False
    assert result["score_evolves"] is False
    assert result["finished"] is False


def test_3b_rouge_exception(tmp_path):
    """Fabrique une EXCEPTION à l'exécution (step() lève) : le volet doit la
    rapporter, jamais l'avaler en silence."""
    game = _copy_pure_logic(tmp_path)
    loop_copy = game / "05_SYSTEMS" / "game_loop" / "loop.mjs"
    original = loop_copy.read_text(encoding="utf-8")
    bugged = original.replace(
        "export function step(state, action = { p1: 0, p2: 0 }) {",
        "export function step(state, action = { p1: 0, p2: 0 }) {\n"
        "  throw new Error('regression fabriquee test 3b');",
        1,
    )
    loop_copy.write_text(bugged, encoding="utf-8")

    result = check_auto_session(
        loop_copy, game / "05_SYSTEMS" / "game_state" / "state.mjs",
        game / "05_SYSTEMS" / "input" / "input.mjs",
        max_ticks=500, timeout_s=15,
    )
    print("RED 3b (exception):", json.dumps(result, ensure_ascii=False, indent=1))

    assert result["passed"] is False
    assert result["no_exception"] is False
    assert "regression fabriquee test 3b" in (result["error"] or "")


def test_3b_vert_sur_pong_reel():
    result = check_auto_session(
        _PONG / "05_SYSTEMS" / "game_loop" / "loop.mjs",
        _PONG / "05_SYSTEMS" / "game_state" / "state.mjs",
        _PONG / "05_SYSTEMS" / "input" / "input.mjs",
        max_ticks=20000, timeout_s=30,
    )
    print("GREEN 3b (Pong réel):", json.dumps(result, ensure_ascii=False, indent=1))

    assert result["passed"] is True
    assert result["finished"] is True
    assert result["score_evolves"] is True
    assert result["no_exception"] is True
    assert result["duration_bounded"] is True
    assert result["final_score"]["p1"] + result["final_score"]["p2"] >= 3


def test_3b_fichier_absent_blocked(tmp_path):
    result = check_auto_session(tmp_path / "absent.mjs", tmp_path / "b.mjs", tmp_path / "c.mjs")
    assert result["passed"] is False
    assert result["checked"] is False


# ============================================================================
# 3c — visual_capture
# ============================================================================

def test_3c_rouge_captures_identiques(tmp_path):
    """Fabrique DEUX captures IDENTIQUES (capture_browser.mjs patché pour rendre
    le même état deux fois) : le critère pixel doit rougir. capture_godot.mjs
    est volontairement ABSENT de cette fixture — ce test isole le volet navigateur."""
    pres = _copy_capture_graph(tmp_path)
    cb = pres / "capture_browser.mjs"
    original = cb.read_text(encoding="utf-8")
    assert "const b = render(midGameState(1, 45));" in original
    bugged = original.replace(
        "const b = render(midGameState(1, 45));", "const b = render(boot(1));", 1)
    cb.write_text(bugged, encoding="utf-8")

    result = check_visual_capture(pres, timeout_s=60)
    print("RED 3c (captures identiques):", json.dumps(result, ensure_ascii=False, indent=1))

    assert result["status"] == "FAIL"
    assert result["passed"] is False
    assert result["browser"]["json"]["differ"] is False


def test_3c_moteur_absent_nentre_pas_dans_l_agregat(tmp_path):
    """W-2 (GO Pierre 2026-09-02) — `capture_godot.mjs` ABSENT : ce moteur n'existe pas
    pour ce jeu, il ne doit donc pas emporter le statut.

    AVANT W-2, ce cas rendait NOT_MEASURED : une capture navigateur parfaitement verte
    ne pouvait jamais valoir OK sur un jeu purement web — soit 68 des 79 attentes
    `expected_proof.kind: visual` du dépôt. Le volet était de ce fait inutilisable comme
    source de preuve visuelle pour le web."""
    pres = _copy_capture_graph(tmp_path)
    assert not (pres / "capture_godot.mjs").exists()

    result = check_visual_capture(pres, timeout_s=60)
    print("check 3c (godot absent de la fixture):", json.dumps(result, ensure_ascii=False, indent=1))

    assert result["browser"]["json"]["passed"] is True
    assert result["godot"]["ran"] is False
    assert result["volets"]["godot"]["applicable"] is False   # pas un moteur de ce jeu
    assert result["measured_volets"] == ["browser"]
    assert result["not_measured_volets"] == []               # rien d'applicable n'est resté non mesuré
    assert result["status"] == "OK"
    assert result["passed"] is True


def test_3c_moteur_present_mais_non_mesurable_reste_visible_et_nemporte_pas_le_statut(tmp_path):
    """W-2, l'autre moitié : un script PRÉSENT qu'on n'a pas su mesurer ne devient
    JAMAIS invisible. Il ne bloque plus le statut, mais il est listé — « moins
    d'autorité, même capacité de détection, signal observable »."""
    pres = _copy_capture_graph(tmp_path)
    (pres / "capture_godot.mjs").write_text(
        'console.log(JSON.stringify({adapter:"godot",passed:false,blocked:true,'
        'reason:"binaire Godot non configure (simule)"}));',
        encoding="utf-8")

    result = check_visual_capture(pres, timeout_s=60)

    assert result["volets"]["godot"]["applicable"] is True
    assert result["volets"]["godot"]["measured"] is False
    assert result["not_measured_volets"] == ["godot"]     # jamais effacé
    assert result["status"] == "OK"                        # ... mais n'emporte pas le statut
    assert result["passed"] is True


def test_3c_aucun_volet_mesure_ne_gagne_aucun_vert(tmp_path):
    """Garde anti-vert-par-vacuité : W-2 ne fabrique pas de preuve là où il n'y a
    AUCUN producteur. Un jeu sans aucun script de capture reste NOT_MEASURED — c'est
    exactement l'état des 8 jeux qui portent des attentes `visual` aujourd'hui."""
    pres = tmp_path / "presentation"
    pres.mkdir()
    result = check_visual_capture(pres, timeout_s=60)

    assert result["measured_volets"] == []
    assert result["status"] == "NOT_MEASURED"
    assert result["passed"] is False


def test_3c_rouge_mesure_reste_rouge(tmp_path):
    """W-2 ne relâche RIEN sur ce qui a été mesuré : un volet applicable, mesuré et
    rouge rend FAIL — jamais dilué par un autre volet vert."""
    pres = _copy_capture_graph(tmp_path)
    cb = pres / "capture_browser.mjs"
    cb.write_text(
        cb.read_text(encoding="utf-8").replace(
            "const b = render(midGameState(1, 45));", "const b = render(boot(1));", 1),
        encoding="utf-8")

    result = check_visual_capture(pres, timeout_s=60)
    assert result["status"] == "FAIL"
    assert result["passed"] is False


def test_3c_vert_sur_pong_reel():
    """Contrôle positif RÉEL : appelle les VRAIES capture_browser.mjs/capture_godot.mjs
    de Pong. Sur CE poste, un binaire Godot est configuré (forge/godot.config.json)
    et une fenêtre GPU réelle est disponible (RTX 5080, Vulkan) — donc mesuré, pas
    NOT_MEASURED. Si l'environnement change (Godot non configuré ailleurs), ce test
    est légitimement amené à voir godot passer en NOT_MEASURED : on l'assert donc de
    façon tolérante (jamais un FAIL confondu avec une absence de mesure)."""
    result = check_visual_capture(_PRESENTATION, timeout_s=150)
    print("GREEN 3c (Pong réel):", json.dumps(
        {k: v for k, v in result.items() if k != "godot"} |
        {"godot_summary": {kk: result["godot"].get(kk) for kk in ("ran", "returncode")}},
        ensure_ascii=False, indent=1))

    assert result["browser"]["json"]["passed"] is True
    assert result["status"] in ("OK", "NOT_MEASURED")
    assert result["status"] != "FAIL"


# ============================================================================
# 3d — restart_offer_wiring / exit_stop_wiring / playable_speed_band /
#      solo_ai_session (S1, contrat `s1-brancher-le-lecteur.yaml`, 2026-07-27) —
#      EXÉCUTEURS des 7 fichiers de preuve neufs du run pong_r3. Même discipline
#      TDD que 3a/3b/3c : ROUGE sur un cas FABRIQUÉ (fichier absent OU assertion
#      cassée sur une COPIE sous tmp_path, JAMAIS le dépôt réel), puis VERT sur
#      GAMES/pong réel.
# ============================================================================

def _copy_restart_graph(tmp_path: Path) -> Path:
    game = tmp_path / "pong_copy"
    pres = "06_RUNTIME/adapters/presentation"
    for rel in (
        "07_TESTS/unit/restart_offer.test.mjs",
        f"{pres}/browser/main.mjs", f"{pres}/draw.mjs", f"{pres}/audio.mjs", f"{pres}/exit.mjs",
        "05_SYSTEMS/game_loop/loop.mjs", "05_SYSTEMS/game_state/state.mjs",
        "05_SYSTEMS/input/input.mjs", "05_SYSTEMS/input/ai.mjs",
    ):
        _copy(_PONG / rel, game / rel)
    return game / "07_TESTS/unit/restart_offer.test.mjs"


def _copy_exit_graph(tmp_path: Path) -> Path:
    game = tmp_path / "pong_copy"
    pres = "06_RUNTIME/adapters/presentation"
    for rel in (
        "07_TESTS/unit/exit_stop.test.mjs",
        f"{pres}/browser/main.mjs", f"{pres}/draw.mjs", f"{pres}/audio.mjs", f"{pres}/exit.mjs",
        "05_SYSTEMS/game_loop/loop.mjs", "05_SYSTEMS/game_state/state.mjs",
        "05_SYSTEMS/input/input.mjs", "05_SYSTEMS/input/ai.mjs",
    ):
        _copy(_PONG / rel, game / rel)
    return game / "07_TESTS/unit/exit_stop.test.mjs"


def _copy_speed_graph(tmp_path: Path) -> Path:
    game = tmp_path / "pong_copy"
    for rel in (
        "07_TESTS/unit/playable_speed.test.mjs",
        "05_SYSTEMS/game_loop/loop.mjs", "05_SYSTEMS/game_state/state.mjs",
        "01_DESIGN/genre_bible.json",
    ):
        _copy(_PONG / rel, game / rel)
    return game / "07_TESTS/unit/playable_speed.test.mjs"


def _copy_solo_graph(tmp_path: Path) -> tuple[Path, Path]:
    game = tmp_path / "pong_copy"
    for rel in (
        "07_TESTS/unit/ai.test.mjs", "07_TESTS/oracle/solo_session.mjs",
        "05_SYSTEMS/game_loop/loop.mjs", "05_SYSTEMS/game_state/state.mjs",
        "05_SYSTEMS/input/input.mjs", "05_SYSTEMS/input/ai.mjs",
    ):
        _copy(_PONG / rel, game / rel)
    return (game / "07_TESTS/unit/ai.test.mjs", game / "07_TESTS/oracle/solo_session.mjs")


# --- restart_offer_wiring -----------------------------------------------------

def test_3d_restart_rouge_fichier_absent():
    result = check_restart_offer_wiring(Path("nawak/inexistant_restart.test.mjs"))
    assert result["passed"] is False
    assert result["checked"] is False


def test_3d_restart_rouge_assertion_cassee(tmp_path):
    test_copy = _copy_restart_graph(tmp_path)
    original = test_copy.read_text(encoding="utf-8")
    marker = "assert.deepEqual(c.state, boot(1), 'relance -> etat identique au premier demarrage');"
    assert marker in original
    test_copy.write_text(
        original.replace(marker, "assert.deepEqual(c.state, { fabrique: true }, 'CASSE (test)');", 1),
        encoding="utf-8",
    )
    result = check_restart_offer_wiring(test_copy, timeout_s=30)
    print("RED 3d (restart, assertion cassée):", json.dumps(result, ensure_ascii=False, indent=1))
    assert result["passed"] is False
    assert result["checked"] is True
    assert result["tests_fail"] == 1


def test_3d_restart_vert_sur_pong_reel():
    result = check_restart_offer_wiring(_PONG / "07_TESTS/unit/restart_offer.test.mjs", timeout_s=30)
    print("GREEN 3d (restart, Pong réel):", json.dumps(result, ensure_ascii=False, indent=1))
    assert result["passed"] is True
    assert result["tests_fail"] == 0
    assert result["tests_pass"] and result["tests_pass"] > 0
    assert any("clic navigateur réel" in l for l in result["limites"])


# --- exit_stop_wiring ----------------------------------------------------------

def test_3d_exit_rouge_fichier_absent():
    result = check_exit_stop_wiring(Path("nawak/inexistant_exit.test.mjs"))
    assert result["passed"] is False
    assert result["checked"] is False


def test_3d_exit_rouge_assertion_cassee(tmp_path):
    test_copy = _copy_exit_graph(tmp_path)
    original = test_copy.read_text(encoding="utf-8")
    assert "assert.equal(r.code, 0);" in original
    test_copy.write_text(original.replace("assert.equal(r.code, 0);", "assert.equal(r.code, 999);", 1),
                          encoding="utf-8")
    result = check_exit_stop_wiring(test_copy, timeout_s=30)
    print("RED 3d (exit, assertion cassée):", json.dumps(result, ensure_ascii=False, indent=1))
    assert result["passed"] is False
    assert result["tests_fail"] == 1


def test_3d_exit_vert_sur_pong_reel():
    result = check_exit_stop_wiring(_PONG / "07_TESTS/unit/exit_stop.test.mjs", timeout_s=30)
    print("GREEN 3d (exit, Pong réel):", json.dumps(result, ensure_ascii=False, indent=1))
    assert result["passed"] is True
    assert result["tests_fail"] == 0


# --- playable_speed_band -------------------------------------------------------

def test_3d_speed_rouge_fichier_absent():
    result = check_playable_speed_band(Path("nawak/inexistant_speed.test.mjs"))
    assert result["passed"] is False
    assert result["checked"] is False


def test_3d_speed_rouge_vitesse_hors_bande(tmp_path):
    test_copy = _copy_speed_graph(tmp_path)
    state_copy = test_copy.parent.parent.parent / "05_SYSTEMS" / "game_state" / "state.mjs"
    original = state_copy.read_text(encoding="utf-8")
    assert "export const BALL_VX = 1.25;" in original
    state_copy.write_text(original.replace("export const BALL_VX = 1.25;", "export const BALL_VX = 3;", 1),
                           encoding="utf-8")
    result = check_playable_speed_band(test_copy, timeout_s=30)
    print("RED 3d (speed, hors bande):", json.dumps(result, ensure_ascii=False, indent=1))
    assert result["passed"] is False
    assert result["tests_fail"] >= 1


def test_3d_speed_vert_sur_pong_reel():
    result = check_playable_speed_band(_PONG / "07_TESTS/unit/playable_speed.test.mjs", timeout_s=30)
    print("GREEN 3d (speed, Pong réel):", json.dumps(result, ensure_ascii=False, indent=1))
    assert result["passed"] is True
    assert result["tests_fail"] == 0


# --- solo_ai_session ------------------------------------------------------------

def test_3d_solo_rouge_fichier_absent():
    result = check_solo_ai_session(Path("nawak/a.mjs"), Path("nawak/b.mjs"))
    assert result["passed"] is False
    assert result["checked"] is False


def test_3d_solo_rouge_session_ne_termine_jamais(tmp_path):
    ai_test_copy, session_copy = _copy_solo_graph(tmp_path)
    original = session_copy.read_text(encoding="utf-8")
    marker = "export function playSoloGame(seed = 1, maxTicks = 200000) {"
    assert marker in original
    session_copy.write_text(
        original.replace(marker, "export function playSoloGame(seed = 1, maxTicks = 0) {", 1),
        encoding="utf-8",
    )
    result = check_solo_ai_session(ai_test_copy, session_copy, timeout_s=20)
    print("RED 3d (solo, session ne termine jamais):", json.dumps(result, ensure_ascii=False, indent=1))
    assert result["passed"] is False
    assert result["session"]["passed"] is False
    assert result["ai_logic"]["passed"] is True  # l'autre volet reste vert : isole le défaut


def test_3d_solo_vert_sur_pong_reel():
    result = check_solo_ai_session(
        _PONG / "07_TESTS/unit/ai.test.mjs", _PONG / "07_TESTS/oracle/solo_session.mjs",
        timeout_s=30,
    )
    print("GREEN 3d (solo, Pong réel):", json.dumps(result, ensure_ascii=False, indent=1))
    assert result["passed"] is True
    assert result["ai_logic"]["passed"] is True
    assert result["session"]["passed"] is True
    assert result["session"]["report"]["checks"]["ai_actually_plays"] is True


# ============================================================================
# Agrégat (utilisé par le driver, s10a)
# ============================================================================

def test_run_product_oracle_sur_pong_reel():
    result = run_product_oracle(_PONG, auto_session_timeout_s=30, visual_capture_timeout_s=150)
    assert set(result) == {
        "browser_import_safety", "auto_session", "visual_capture",
        "restart_offer_wiring", "exit_stop_wiring",
        "playable_speed_band_test", "solo_ai_session",
    }
    assert result["browser_import_safety"]["passed"] is True
    assert result["auto_session"]["passed"] is True
    assert result["visual_capture"]["status"] in ("OK", "NOT_MEASURED")
    assert result["restart_offer_wiring"]["passed"] is True
    assert result["exit_stop_wiring"]["passed"] is True
    assert result["playable_speed_band_test"]["passed"] is True
    assert result["solo_ai_session"]["passed"] is True


# ============================================================================
# Contre-vérification P7 (supervision, 2026-07-27) — NOT_MEASURED ≠ OK, appliqué
# STRICTEMENT : une entrée illisible/inexistante/non-fichier ne doit JAMAIS
# rendre `passed: true`. Défaut trouvé : `check_browser_import_safety(Path
# ('GAMES/pong'))` (un DOSSIER, pas un fichier) rendait `passed: true,
# checked: true` — la lecture échouait (PermissionError sur un dossier),
# `_read_text` avalait l'échec en `""`, un texte vide n'a "aucun defaut" par
# construction. Chaque test ci-dessous est ROUGE contre le code d'AVANT ce
# correctif (vérifié empiriquement par la supervision et reproduit ici), puis
# VERT après.
# ============================================================================

def test_p7_3a_dossier_comme_entree_jamais_vert():
    """LE défaut trouvé : un DOSSIER passé comme entrée navigateur (au lieu d'un
    fichier) ne doit JAMAIS rendre passed=True — la lecture échoue silencieusement
    et un texte vide n'a « aucun défaut » que par construction, pas par mesure."""
    result = check_browser_import_safety(_PONG)  # _PONG est un DOSSIER, pas un fichier
    print("P7 3a (dossier comme entrée):", json.dumps(result, ensure_ascii=False, indent=1))
    assert result["checked"] is False
    assert result["passed"] is False
    assert result["fichiers_analyses"] == []


def test_p7_3a_zero_fichier_analyse_jamais_vert(monkeypatch):
    """Garde-fou 2 explicite : même si l'entrée EST un fichier réel, si AUCUN
    fichier n'a pu être effectivement LU (permission refusée en cours de route,
    etc.), `fichiers_analyses` vide ne doit jamais valoir « aucun défaut trouvé »."""
    import forge.product_oracle as po
    monkeypatch.setattr(po, "_read_text", lambda path: None)
    entry = _PRESENTATION / "browser" / "main.mjs"
    assert entry.is_file()  # l'entrée EST un vrai fichier — seule la LECTURE échoue
    result = po.check_browser_import_safety(entry)
    print("P7 3a (zéro fichier lisible):", json.dumps(result, ensure_ascii=False, indent=1))
    assert result["checked"] is False
    assert result["passed"] is False


def test_p7_3b_dossier_comme_fichier_logique_checked_false():
    """Un DOSSIER passé comme fichier logique doit être rejeté EXPLICITEMENT
    (checked=False, motif clair) — pas seulement « accidentellement rouge » parce
    que Node lève une erreur ESM en aval (fragile : dépend du comportement d'
    import de Node, pas d'une vérification déterministe du driver)."""
    result = check_auto_session(_PONG, _PONG, _PONG, max_ticks=200, timeout_s=10)
    print("P7 3b (dossier comme fichier logique):", json.dumps(result, ensure_ascii=False, indent=1))
    assert result["passed"] is False
    assert result["checked"] is False


def test_p7_3c_entree_manquante_est_not_measured_jamais_ok_ni_fail():
    """Un `presentation_dir` inexistant (donc capture_browser.mjs introuvable) est
    une ABSENCE DE MESURE, pas un critère pixel rouge mesuré — le statut doit être
    NOT_MEASURED (jamais OK, et jamais FAIL non plus : FAIL affirmerait à tort
    qu'une mesure a eu lieu et a échoué)."""
    result = check_visual_capture(_REPO_ROOT / "GAMES" / "pong_does_not_exist_p7", timeout_s=10)
    print("P7 3c (presentation_dir inexistant):", json.dumps(
        {k: v for k, v in result.items() if k not in ("browser", "godot")},
        ensure_ascii=False, indent=1))
    assert result["status"] == "NOT_MEASURED"
    assert result["passed"] is False


def test_p7_driver_ne_lit_jamais_passed_seul(tmp_path):
    """Point 5 de la contre-vérification : le driver lit-il `passed` en ignorant
    `checked` ? Réponse mécanique : `detail["product_oracle"]` est porté TEL QUEL
    (`self.product_oracle_runner(self.game_dir)`, driver.py) sans qu'aucune ligne
    du driver ne teste `["passed"]` sur ce dict — grep négatif ci-dessous. Le
    driver ne consomme donc PAS ces champs pour décider quoi que ce soit (100%
    advisory, transmission brute) : le risque décrit au point 5 ne s'est pas
    encore matérialisé, mais le deviendra le jour où quelqu'un lira
    `detail["product_oracle"][...]["passed"]` sans vérifier `checked`/`status`
    d'abord — à surveiller à la promotion en gate dur (hors périmètre ici)."""
    driver_src = (_REPO_ROOT / "forge" / "driver.py").read_text(encoding="utf-8")
    # aucune ligne du driver n'indexe ["passed"] sur le résultat product_oracle
    assert 'product_oracle"]["passed"]' not in driver_src.replace("'", '"')
    assert "self.product_oracle_runner(self.game_dir)" in driver_src

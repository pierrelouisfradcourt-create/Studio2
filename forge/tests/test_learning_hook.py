"""forge.learning_hook — branchement best-effort de learning_metrics.mjs sur un run Forge
EN COURS.

LEARNING_SUBJECT_MODEL_V1 (studio_brain/decisions/PROPOSED_2026-07-26_ratifications.md) :
AVANT ce correctif, `record_learning_if_brick` exigeait que `project` matche un brick_id du
catalogue (entry_type=="brick") même pour un run de JEU (`is_game=True`) — exactement le
bug qui garantissait 0 ligne backfillée (un jeu n'est jamais une brique du catalogue). La
correction renomme la fonction en `record_learning_for_subject` : un run de JEU (is_game=True
+ game_dir présent sur disque) enregistre désormais `subject:{type:'game', id:project}` SANS
exiger de correspondance catalogue. Un run non-jeu (is_game=False) reste NON enregistré : ce
hook n'a aucune source de mesure de reuse_ratio pour une brique de bibliothèque (brancher
cette source est l'étape 2 du plan ratifié, hors périmètre ici).

Ne réimplémente rien (buildRecord/recordLearning/measureReuseRatio) — shell-oute vers les
scripts Node existants, testé ici avec le VRAI `node` (pas de mock du langage source)."""
import json
from pathlib import Path

import pytest

from forge import learning_hook

REPO_ROOT = Path(__file__).resolve().parents[2]


def _write_game(tmp_path: Path, name: str, files: dict[str, str]) -> Path:
    game_dir = tmp_path / "GAMES" / name
    game_dir.mkdir(parents=True, exist_ok=True)
    for rel, content in files.items():
        (game_dir / rel).write_text(content, encoding="utf-8")
    return game_dir


def test_jeu_avec_gamedir_present_enregistre_subject_game_sans_exiger_de_brique(tmp_path):
    # Verrouille le correctif : project="pong" ne matche AUCUNE brique catalogue et ça
    # n'a plus d'importance — un jeu n'a jamais eu besoin d'en être une pour être mesuré.
    game_dir = _write_game(tmp_path, "pong", {
        "game.mjs": "import { a } from '../../knowledge_base/systems/x/a.mjs';\n",
    })
    target = tmp_path / "learning_curve.jsonl"

    result = learning_hook.record_learning_for_subject(
        project="pong", game_dir=game_dir, is_game=True,
        oracle_iterations=3, target_path=target,
    )

    assert result["recorded"] is True, result
    lines = target.read_text(encoding="utf-8").strip().splitlines()
    assert len(lines) == 1
    record = json.loads(lines[0])
    assert record["subject"] == {"type": "game", "id": "pong"}
    assert record["oracle_iterations"] == 3
    assert record["joust_delta"] is None
    assert isinstance(record["reuse_ratio"], (int, float))


def test_reuse_ratio_est_reellement_mesure_par_reuse_ratio_mjs(tmp_path):
    game_dir = _write_game(tmp_path, "sys-fixture-hook-02", {
        "game.mjs": "import { a } from '../../knowledge_base/systems/x/a.mjs';\n",
    })
    target = tmp_path / "learning_curve.jsonl"

    result = learning_hook.record_learning_for_subject(
        project="sys-fixture-hook-02", game_dir=game_dir, is_game=True,
        oracle_iterations=1, target_path=target,
    )
    assert result["recorded"] is True, result
    # 1 fichier de logique, 1 module knowledge_base -> reuse_ratio = 1 / (1+1) = 0.5
    assert abs(result["reuse_ratio"] - 0.5) < 1e-9


def test_is_game_false_naugmente_rien(tmp_path):
    # Ni jeu ni brique instrumentée par ce pipeline : aucune source de reuse_ratio (étape 2
    # du plan ratifié, hors périmètre de ce hook).
    target = tmp_path / "learning_curve.jsonl"
    result = learning_hook.record_learning_for_subject(
        project="driver_smoke", game_dir=None, is_game=False,
        oracle_iterations=1, target_path=target,
    )
    assert result["recorded"] is False
    assert "is_game=false" in result["reason"]
    assert not target.exists()


def test_game_dir_none_naugmente_rien(tmp_path):
    target = tmp_path / "learning_curve.jsonl"
    result = learning_hook.record_learning_for_subject(
        project="sys-fixture-hook-03", game_dir=None, is_game=True,
        oracle_iterations=1, target_path=target,
    )
    assert result["recorded"] is False
    assert not target.exists()


def test_game_dir_absent_du_disque_naugmente_rien(tmp_path):
    ghost = tmp_path / "GAMES" / "sys-fixture-hook-04"  # jamais créé
    target = tmp_path / "learning_curve.jsonl"
    result = learning_hook.record_learning_for_subject(
        project="sys-fixture-hook-04", game_dir=ghost, is_game=True,
        oracle_iterations=1, target_path=target,
    )
    assert result["recorded"] is False
    assert "introuvable" in result["reason"]
    assert not target.exists()


def test_node_introuvable_est_avale_jamais_une_exception(tmp_path, monkeypatch):
    game_dir = _write_game(tmp_path, "sys-fixture-hook-07", {"game.mjs": "export function f(){}\n"})
    target = tmp_path / "learning_curve.jsonl"

    monkeypatch.setattr(learning_hook, "_node_exe", lambda: str(tmp_path / "no-such-node-binary"))

    result = learning_hook.record_learning_for_subject(
        project="sys-fixture-hook-07", game_dir=game_dir, is_game=True,
        oracle_iterations=1, target_path=target,
    )
    assert result["recorded"] is False  # jamais d'exception propagée
    assert not target.exists()


def test_exception_interne_najamais_propagee(tmp_path, monkeypatch):
    """Best-effort strict : une exception inattendue dans la mesure reuse_ratio ne doit
    JAMAIS remonter à l'appelant (même garantie que context_manifest, dispatch.py)."""
    game_dir = _write_game(tmp_path, "sys-fixture-hook-08", {"game.mjs": "export function f(){}\n"})
    target = tmp_path / "learning_curve.jsonl"

    def _boom(*a, **k):
        raise RuntimeError("panne simulée")

    monkeypatch.setattr(learning_hook, "_measure_reuse_ratio", _boom)

    result = learning_hook.record_learning_for_subject(
        project="sys-fixture-hook-08", game_dir=game_dir, is_game=True,
        oracle_iterations=1, target_path=target,
    )
    assert result["recorded"] is False
    assert not target.exists()


def test_defauts_pointent_vers_les_vrais_scripts():
    assert learning_hook._REUSE_RATIO_SCRIPT == REPO_ROOT / "forge" / "reuse_ratio.mjs"
    assert learning_hook._LEARNING_METRICS_SCRIPT == REPO_ROOT / "forge" / "learning_metrics.mjs"
    assert learning_hook._REUSE_RATIO_SCRIPT.exists()
    assert learning_hook._LEARNING_METRICS_SCRIPT.exists()


# --- Régression 2026-07-26 : cible par défaut monkeypatchable, jamais un chemin en dur ---
# Découverte par vérification indépendante : driver.py appelle record_learning_for_subject
# SANS jamais passer target_path (voir _record_learning_advisory). Avant ce correctif,
# target_path=None -> aucun --target passé au CLI -> le CLI Node retombe sur SON propre
# défaut (knowledge_base/learning_curve.jsonl, le fichier RÉEL versionné). N'importe quel
# test du driver qui ignore l'existence de ce hook (ex. test_standard_wiring_corrections.py,
# préexistant, hors périmètre de cette tâche) polluait donc silencieusement le dépôt à
# chaque exécution de la suite. Fix générique : _DEFAULT_LEARNING_CURVE_PATH est un
# attribut de MODULE (jamais un défaut de paramètre figé à la définition), donc
# monkeypatchable par une fixture autouse (forge/tests/conftest.py) qui protège
# TOUTE la suite sans connaître individuellement chaque test qui construit un ForgeDriver.

def test_defaut_pointe_vers_le_vrai_fichier_durable(monkeypatch):
    # La fixture autouse de conftest.py (_isolate_learning_curve_writes) monkeypatche déjà
    # _DEFAULT_LEARNING_CURVE_PATH pour TOUTE la suite (c'est précisément son rôle : protéger
    # le fichier durable réel). `monkeypatch.undo()` annule ce patch (même instance de fixture
    # que l'autouse, partagée pour ce test) afin de vérifier ici la VRAIE valeur calculée par
    # le module — sans quoi ce test verrait toujours le chemin de test substitué, jamais le réel.
    monkeypatch.undo()
    assert learning_hook._DEFAULT_LEARNING_CURVE_PATH == REPO_ROOT / "knowledge_base" / "learning_curve.jsonl"


def test_target_path_omis_resout_le_defaut_module_monkeypatchable(tmp_path, monkeypatch):
    # Le défaut est un ATTRIBUT DE MODULE relu à chaque appel (pas une valeur figée dans la
    # signature) : monkeypatcher learning_hook._DEFAULT_LEARNING_CURVE_PATH redirige l'écriture
    # sans jamais toucher le vrai fichier — c'est exactement le mécanisme utilisé par la
    # fixture autouse de conftest.py pour isoler toute la suite.
    fake_default = tmp_path / "isolated_learning_curve.jsonl"
    monkeypatch.setattr(learning_hook, "_DEFAULT_LEARNING_CURVE_PATH", fake_default)

    game_dir = _write_game(tmp_path, "sys-fixture-hook-09", {"game.mjs": "export function f(){}\n"})
    result = learning_hook.record_learning_for_subject(
        project="sys-fixture-hook-09", game_dir=game_dir, is_game=True, oracle_iterations=1,
        # target_path OMIS volontairement : c'est le cas réel de driver.py
    )
    assert result["recorded"] is True, result
    assert fake_default.exists()
    lines = fake_default.read_text(encoding="utf-8").strip().splitlines()
    assert len(lines) == 1
    record = json.loads(lines[0])
    assert record["subject"] == {"type": "game", "id": "sys-fixture-hook-09"}

"""forge.learning_hook — branchement best-effort de l'instrumentation d'apprentissage
(forge/learning_metrics.mjs) sur un run Forge EN COURS (driver.py).

Distinct de `backfill_learning_curve.mjs` (qui rejoue les runs déjà ARCHIVÉS) : ce module
est appelé UNE FOIS, en direct, quand l'étape s10a-oracle-code d'un run vient de tourner
verte — plan 4 étapes ratifié Pierre 2026-07-26, étape 1 (instrumentation -> avoir des
données), volet « un run futur alimente la courbe automatiquement ».

LEARNING_SUBJECT_MODEL_V1 (studio_brain/decisions/PROPOSED_2026-07-26_ratifications.md) :
cette fonction s'appelait `record_learning_if_brick` et exigeait que `project` matche un
brick_id du catalogue (knowledge_base/catalog.json, entry_type=="brick") MÊME pour un run
de jeu (`is_game=True`) — c'était exactement le bug qui garantissait le silence de ce hook :
tous les runs Forge forgent un JEU, jamais une brique de bibliothèque, donc cette exigence
ne pouvait jamais être remplie. Renommée `record_learning_for_subject` : un run de jeu
(is_game=True + game_dir présent sur disque) enregistre désormais
`subject: {type:'game', id:project}` SANS exiger de correspondance catalogue — un jeu n'est
pas une brique, il n'a jamais eu besoin d'en être une pour être mesuré (alternative
explicitement rejetée par la ratification : « promouvoir tous les jeux en briques du
catalogue »). Un run non-jeu (is_game=False) reste NON enregistré : ce hook n'a aucune
source équivalente à game_dir pour mesurer le reuse_ratio d'une brique de bibliothèque —
brancher une telle source est l'étape 2 du plan ratifié, pas celle-ci (« pas d'anticipation
d'étape »).

Advisory strict : `record_learning_for_subject` n'écrit RIEN durablement si le sujet n'est
pas mesurable et NE LÈVE JAMAIS — best-effort, même patron que `context_manifest` dans
`dispatch.py` (l'appelant driver.py enveloppe en plus l'appel dans un try/except par
défense en profondeur).

Ne réimplémente NI buildRecord/recordLearning (learning_metrics.mjs) NI measureReuseRatio
(reuse_ratio.mjs) : source unique de la mesure et du format en JS, ce module les invoque
via subprocess, il ne recalcule rien.
"""
from __future__ import annotations

import json
import logging
import shutil
import subprocess
from pathlib import Path

logger = logging.getLogger(__name__)

_REPO_ROOT = Path(__file__).resolve().parents[1]
_REUSE_RATIO_SCRIPT = Path(__file__).resolve().parent / "reuse_ratio.mjs"
_LEARNING_METRICS_SCRIPT = Path(__file__).resolve().parent / "learning_metrics.mjs"
_SUBPROCESS_TIMEOUT_S = 60

# Chemin par défaut de la courbe d'apprentissage — miroir Python du DEFAULT_LEARNING_CURVE_PATH
# JS (learning_metrics.mjs), même fichier réel. Déclaré comme ATTRIBUT DE MODULE (jamais comme
# valeur par défaut figée dans la signature de record_learning_for_subject) précisément pour
# rester monkeypatchable : régression 2026-07-26 (vérification indépendante) — driver.py
# n'appelle JAMAIS ce hook avec target_path, donc n'importe quel test qui construit un
# ForgeDriver réel avec is_game=True et laisse s10a-oracle-code atteindre OK écrivait
# silencieusement sur CE chemin (le fichier durable versionné). La fixture autouse de
# forge/tests/conftest.py redirige cet attribut vers un fichier jetable pour toute
# la suite, sans neutraliser le mécanisme lui-même (voir test_learning_hook.py).
_DEFAULT_LEARNING_CURVE_PATH = _REPO_ROOT / "knowledge_base" / "learning_curve.jsonl"


def _node_exe() -> str:
    return shutil.which("node") or "node"


def _measure_reuse_ratio(game_dir: Path) -> float | None:
    """Invoque reuse_ratio.mjs (source JS unique de la mesure) — jamais recalculé ici.
    Retourne None si le subprocess échoue/timeout/sortie non parsable (jamais une exception)."""
    try:
        proc = subprocess.run(
            [_node_exe(), str(_REUSE_RATIO_SCRIPT), str(game_dir)],
            capture_output=True, text=True, timeout=_SUBPROCESS_TIMEOUT_S, encoding="utf-8",
        )
    except (OSError, subprocess.SubprocessError):
        return None
    if proc.returncode != 0:
        return None
    try:
        parsed = json.loads(proc.stdout)
    except ValueError:
        return None
    ratio = parsed.get("reuseRatio") if isinstance(parsed, dict) else None
    return ratio if isinstance(ratio, (int, float)) else None


def record_learning_for_subject(
    *,
    project: str,
    game_dir: "Path | None",
    is_game: bool,
    oracle_iterations: int,
    target_path: "Path | None" = None,
) -> dict:
    """Enregistre une ligne learning_curve.jsonl SEULEMENT si `is_game` est vrai et
    `game_dir` existe — le sujet enregistré est alors `subject: {type:'game', id:project}`.
    Un run non-jeu n'est jamais enregistré par ce hook (aucune source de reuse_ratio pour
    une brique de bibliothèque dans ce pipeline — étape 2 du plan ratifié, hors périmètre).
    Retourne un diagnostic ``{"recorded": bool, "reason": str, ...}`` — ne lève JAMAIS
    (best-effort strict).
    """
    try:
        if not is_game or game_dir is None:
            return {"recorded": False,
                     "reason": "is_game=false ou game_dir absent — ce hook n'a aucune "
                                "source de reuse_ratio pour un run non-jeu (brancher une "
                                "source de brique de bibliothèque est l'étape 2 du plan "
                                "ratifié, hors périmètre ici)"}
        game_dir = Path(game_dir)
        if not game_dir.exists():
            return {"recorded": False, "reason": f"game_dir introuvable ({game_dir})"}

        reuse_ratio = _measure_reuse_ratio(game_dir)
        if reuse_ratio is None:
            return {"recorded": False, "reason": "reuse_ratio.mjs illisible/en échec"}

        # `target_path` résolu explicitement (jamais implicitement délégué au défaut du CLI
        # Node) : --target est TOUJOURS passé, avec le chemin fourni par l'appelant ou, à
        # défaut, l'attribut de module _DEFAULT_LEARNING_CURVE_PATH (monkeypatchable — voir
        # commentaire au niveau du module).
        resolved_target = Path(target_path) if target_path is not None else _DEFAULT_LEARNING_CURVE_PATH
        cmd = [
            _node_exe(), str(_LEARNING_METRICS_SCRIPT), "record",
            "--subject-type", "game",
            "--subject-id", project,
            "--reuse-ratio", str(reuse_ratio),
            "--oracle-iterations", str(oracle_iterations),
            "--target", str(resolved_target),
        ]
        proc = subprocess.run(
            cmd, capture_output=True, text=True, timeout=_SUBPROCESS_TIMEOUT_S, encoding="utf-8",
        )
        if proc.returncode != 0:
            return {"recorded": False,
                     "reason": f"learning_metrics.mjs record a échoué: {proc.stderr.strip()}"}
        return {"recorded": True, "reuse_ratio": reuse_ratio, "oracle_iterations": oracle_iterations}
    except Exception as exc:  # noqa: BLE001 — best-effort strict, ne remonte jamais à l'appelant
        logger.warning("learning_hook: échec best-effort (%s)", exc, exc_info=True)
        return {"recorded": False, "reason": f"exception best-effort: {exc}"}

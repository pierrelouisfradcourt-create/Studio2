"""Fournisseur de volets de preuve GODOT pour `check_observable_coverage`
(`standard_oracles.py`) — pendant du fournisseur WEB existant (`product_oracle.py`,
NON modifié par ce module).

CONTEXTE MESURÉ (à vérifier, pas à croire) : les oracles Godot EXISTENT DÉJÀ côté
jeu — `GAMES/snake/07_TESTS/oracle/*.gd` (10 fichiers, 2026-07-29) sont des scripts
`SceneTree` autonomes, un par ligne de wiremap, chacun émettant sur stdout UNE ligne
``FORGE_ORACLE <nom> {"ok": bool, "fails": [...], ...}`` puis ``quit(0 si vert sinon
1)``. Rien à écrire côté jeu ici (INTERDIT par la mission, aucune écriture sous
`GAMES/**`) : il manquait seulement un COLLECTEUR côté Forge qui les découvre, les
exécute, et rend un mapping plat `{nom_volet: résultat}` — exactement la forme que
`check_observable_coverage` attend (même contrat que `product_oracle.run_product_oracle`).

DEUX MODES D'EXÉCUTION, et deux notions à ne JAMAIS confondre (lot L0b, 2026-08-10) :

1. `forge:run_mode = gpu_window` — DIRECTIVE STATIQUE, lue dans la SOURCE du `.gd`
   AVANT toute exécution (`_gpu_window_declared`). Elle répond à « comment lancer ce
   volet », et c'est la SEULE autorité de routage. Elle est statique par nécessité
   mesurée, pas par commodité : un volet pixel lancé en `--headless` ne rend pas un
   marqueur, il rend un ROUGE FABRIQUÉ. Mesure du 2026-08-10 sur
   `GAMES/snake/07_TESTS/oracle/core_render_frame.gd`, même binaire, même volet :
       fenêtre GPU -> {"ok": true,  "fails": []}                       exit 0
       --headless  -> {"ok": false, "fails": ["capture nulle (...)"]}  exit 1
   Décider du mode APRÈS avoir lu la sortie serait donc décider après avoir déjà
   fabriqué le faux rouge.

2. `"requires_gpu_window": true` dans le PAYLOAD (`_GPU_WINDOW_MARKER_KEY`) — MARQUEUR
   D'EXÉCUTION. Il répond à « ce volet a-t-il pu mesurer quelque chose », et rend
   TOUJOURS `NOT_MEASURED` motivé, DANS LES DEUX MODES, même si `ok` vaut `false`
   (leçon `forge.oracle_fail_vs_not_measured_marker` : un oracle qui rend FAIL sur ce
   qu'il ne peut pas mesurer envoie réparer la mauvaise chose). Comportement INCHANGÉ
   par L0b — `GAMES/tetris/07_TESTS/oracle/core_render.gd` continue de rendre
   exactement `NOT_MEASURED`, conformément à l'option (a) ratifiée Pierre 2026-08-10.

Ce qui a été RETIRÉ par L0b : `GPU_WINDOW_REQUIRED_VOLETS`, liste de NOMS de volets en
dur (`{"core_render_frame"}`) qui faisait sauter le runner sans jamais l'exécuter. Ce
n'était pas une limite matérielle mais une POLITIQUE : elle était juste tant qu'aucun
mode GPU n'existait dans ce collecteur, et elle rendait la preuve pixel structurellement
inatteignable. Le mode GPU existant désormais, le nom du volet ne décide plus de rien —
c'est la déclaration du volet qui décide.

Chaque volet exécuté porte `mode_execution` (`"gpu_window"` | `"headless"`) dans son
résultat : le reçu dit COMMENT la mesure a été obtenue, pas seulement son verdict.

Discipline `NOT_MEASURED != OK` (invariant global ratifié Pierre, même que
`product_oracle.py`) partout : binaire Godot introuvable, sortie illisible, JSON
invalide, oracle absent, timeout => `NOT_MEASURED` motivé, JAMAIS une exception,
JAMAIS un vert ni un rouge fabriqué.

`binary_resolver`, `runner` et `gpu_runner` sont INJECTABLES (même patron que
`mutation_runner`/`product_oracle_runner` du driver) : aucun test de ce module n'exige
un vrai binaire Godot. NOTE DE FRAÎCHEUR — l'ancienne rédaction affirmait ici que le
binaire était « ABSENT de ce poste (`godot.config.json` pointe un chemin qui n'existe
plus, vérifié 2026-07-29) » : c'est FAUX depuis, vérifié le 2026-08-10 en exécutant le
binaire déclaré par `godot.config.json` (Godot 4.6.3, Vulkan 1.4.329, RTX 5080). Un fait
périmé en docstring fait re-conclure à l'impossibilité à chaque nouvelle session.
"""
from __future__ import annotations

import json
import logging
import re
import subprocess
import time
from pathlib import Path

from forge.static_oracles import _strip_gd_comments

logger = logging.getLogger(__name__)

# Marqueur de sortie partagé par tous les oracles `.gd` (cf. core_boot.gd,
# core_render_frame.gd...) : "FORGE_ORACLE <nom> {json}" sur une ligne stdout.
_FORGE_ORACLE_LINE = re.compile(r"^FORGE_ORACLE\s+(\S+)\s+(\{.*\})\s*$")

# Ligne observée dans TOUS les oracles `.gd` du studio à ce jour (core_render_frame.gd
# ligne 1, core_boot.gd commentaire d'en-tête...) : sert de discriminant de capacité
# ("ce fichier EST un oracle FORGE_ORACLE") sans jamais exécuter le fichier pour le
# savoir — lecture statique seulement, jamais un effet de bord.
_ORACLE_MARKER = "FORGE_ORACLE"

# DIRECTIVE STATIQUE de mode d'exécution (L0b). Un volet `.gd` la porte en commentaire
# d'en-tête pour déclarer qu'il exige une fenêtre GPU réelle :
#
#     # forge:run_mode = gpu_window
#
# Lue par LECTURE DE SOURCE, jamais par exécution (cf. docstring du module : décider
# après exécution revient à décider après avoir fabriqué un faux rouge). Tolère les
# espaces autour du `=`. C'est la SEULE autorité de routage — aucun nom de volet n'est
# codé en dur dans ce module.
_GPU_WINDOW_DIRECTIVE = re.compile(r"forge\s*:\s*run_mode\s*=\s*gpu_window", re.IGNORECASE)

# Drapeaux mesurés (2026-07-22, ré-exécutés 2026-08-10) qui produisent une fenêtre GPU
# réelle hors écran. DÉPENDANCE DE POSTE ASSUMÉE et déjà inscrite au standard : la
# preuve pixel Godot est liée à cette machine (`--display-driver windows` est spécifique
# à Windows ; `--headless` rend une texture NULLE, driver dummy). `-m` est écarté : ce
# n'est pas « minimized » mais `--maximized`, et le viewport sort alors à la taille de
# l'écran — dimensions non maîtrisées, donc capture non fiable.
GPU_WINDOW_FLAGS = (
    "--display-driver", "windows",
    "--rendering-driver", "vulkan",
    "--position", "-3000,-3000",
)

_GPU_MODE = "gpu_window"
_HEADLESS_MODE = "headless"
_STATIC_GUARD_MODE = "static_guard"

# Garde statique anti-gaming (Task 3, lot V3 « assemblage runtime », décision Pierre
# 2026-08-22) : un volet `07_TESTS/oracle/*.gd` doit charger la VRAIE scène principale
# du jeu (`res://main.tscn`) — pas se construire sa propre scène de substitution, ce qui
# permettrait de prouver un jeu qui n'existe pas (défaut mesuré run 5, kitten_clicker).
# Lue sur la source SANS commentaires (`_strip_gd_comments`, réutilisée depuis
# `static_oracles`, jamais copiée) : une mention en commentaire ne prouve rien, même
# discipline que `_GODOT_ANTI_FAKE_GREEN`.
_VOLET_REAL_SCENE = re.compile(
    r'(?:pre)?load\(\s*"res://main\.tscn"\s*\)|ResourceLoader\.load\(\s*"res://main\.tscn"|run/main_scene')

# Garde anti-contournement V4 (lot « game loop », décision Pierre 2026-08-22) :
# le bot-joueur (`player_loop.gd`) ne connaît QUE `InputEvent` + lecture de
# `Label` — un volet ou `solvability.gd` qui prouve la boucle par un AUTRE canal
# (appel direct de l'économie, de l'API interne, ou du runtime) valide un jeu que
# le joueur ne peut pas traverser. Lue sur la source SANS commentaires
# (`_strip_gd_comments`), même discipline que `_VOLET_REAL_SCENE` ci-dessus :
# une mention en commentaire ne prouve rien.
_LOOP_BYPASS_TOKENS = re.compile(
    r'\bEconomy\b|\bapi_buy_kitten\b|\bapi_buy_upgrade\b|\bapi_prestige\b|'
    r'preload\(\s*"res://05_SYSTEMS|\bruntime\.gd\b')

# Clé optionnelle que le PAYLOAD JSON d'un volet (la partie `{...}` de la ligne
# `FORGE_ORACLE <nom> {...}`, cf. `_FORGE_ORACLE_LINE`) peut porter pour déclarer
# LUI-MÊME n'avoir rien pu mesurer. MARQUEUR D'EXÉCUTION, à ne pas confondre avec la
# DIRECTIVE STATIQUE de mode ci-dessus : celle-ci décide COMMENT lancer le volet, ce
# marqueur décide de son VERDICT. Un volet qui déclare `"requires_gpu_window": true`
# est rendu `NOT_MEASURED` même si son `ok` vaut `false`, et cela DANS LES DEUX MODES —
# cf. leçon `forge.oracle_fail_vs_not_measured_marker` (« un oracle qui rend FAIL sur
# ce qu'il ne peut pas mesurer envoie réparer la mauvaise chose »).
# NOTE L0b : ce marqueur ne peut PAS servir de routage. Il n'est lisible qu'APRÈS
# exécution, or un volet pixel lancé en headless ne l'émet pas — il émet un ROUGE
# (mesure du 2026-08-10 sur snake/core_render_frame : headless -> ok:false, exit 1).
# Router sur lui reviendrait à décider du mode après avoir fabriqué le faux rouge.
_GPU_WINDOW_MARKER_KEY = "requires_gpu_window"


def _marker_gpu_window_reason(fichier: str, mode: str) -> str:
    """Raison NOT_MEASURED pour un volet qui s'est auto-déclaré `requires_gpu_window`
    dans son payload FORGE_ORACLE. Le nom de la leçon
    `oracle_fail_vs_not_measured_marker` DOIT apparaître littéralement dans cette
    raison : c'est le fil de traçabilité qu'Observer peut constater depuis la sortie
    produite par une exécution réelle. Le MODE réellement employé est cité — un volet
    qui se déclare non mesurable *alors qu'il tournait en fenêtre GPU* dit autre chose
    qu'un volet bridé par le headless, et le reçu doit permettre de les distinguer."""
    return (
        f"{fichier} déclare '{_GPU_WINDOW_MARKER_KEY}: true' dans son payload "
        f"FORGE_ORACLE (exécuté en mode '{mode}') — le volet déclare LUI-MÊME n'avoir "
        "rien pu mesurer. NOT_MEASURED (pas FAIL), conformément à la leçon "
        "forge.oracle_fail_vs_not_measured_marker : un oracle qui rend FAIL sur ce "
        "qu'il ne peut pas mesurer envoie réparer la mauvaise chose. Ce marqueur est "
        "une déclaration D'EXÉCUTION et fait autorité sur le verdict ; il ne décide "
        "PAS du mode de lancement (directive statique 'forge:run_mode = gpu_window')."
    )


def _gpu_window_declared(path: Path) -> bool:
    """Le volet déclare-t-il, DANS SA SOURCE, exiger une fenêtre GPU réelle ?
    Lecture statique seulement — jamais une exécution, jamais un effet de bord (même
    discipline que `discover_oracle_files`). Fichier illisible => `False` : on ne
    fabrique pas une exigence GPU à partir d'une erreur de lecture, on retombe sur le
    mode par défaut (headless), et l'échec éventuel sera nommé plus loin."""
    try:
        return bool(_GPU_WINDOW_DIRECTIVE.search(path.read_text(encoding="utf-8")))
    except (OSError, UnicodeDecodeError) as exc:
        logger.warning(
            "product_oracle_godot: lecture de directive échouée sur %s (%s)", path, exc)
        return False


def _not_measured(reason: str, **extra) -> dict:
    """Forme homogène `NOT_MEASURED` acceptée par `_volet_status`
    (`standard_oracles.py`) : `status` explicite, jamais un `passed` vert par défaut."""
    out = {"status": "NOT_MEASURED", "passed": False, "checked": False, "reason": reason}
    out.update(extra)
    return out


def discover_oracle_files(game_dir: Path) -> list[Path]:
    """Liste, TRIÉE (ordre déterministe, jamais dépendant du système de fichiers),
    les fichiers `.gd` de `<game_dir>/07_TESTS/oracle/` qui portent le marqueur
    `FORGE_ORACLE` (lecture statique seulement — jamais exécutés ici). C'est la
    mesure de CAPACITÉ (condition (b) de la correction Pierre ①) : des oracles
    Godot sont réellement présents sur disque pour ce jeu, indépendamment de toute
    déclaration de contrat."""
    oracle_dir = Path(game_dir) / "07_TESTS" / "oracle"
    if not oracle_dir.is_dir():
        return []
    found: list[Path] = []
    for path in sorted(oracle_dir.glob("*.gd")):
        try:
            text = path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError) as exc:
            logger.warning("product_oracle_godot: lecture échouée sur %s (%s)", path, exc)
            continue
        if _ORACLE_MARKER in text:
            found.append(path)
    return found


def has_godot_capacity(game_dir: Path) -> bool:
    """Condition (b), correction Pierre ① : la CAPACITÉ est constatée — au moins un
    oracle `FORGE_ORACLE` réellement présent sur disque pour ce jeu."""
    return bool(discover_oracle_files(game_dir))


def _default_binary_resolver() -> str:
    """Résolution RÉELLE (défaut, jamais utilisée par les tests de ce module) : même
    source que `godot_bin.mjs` (env `GODOT_BIN` puis `forge/godot.config.json`),
    réimplémentée ici côté Python pour ne pas dépendre de Node depuis ce collecteur.
    Lève `FileNotFoundError` si aucun binaire n'est configuré ou ne se trouve pas sur
    le disque — l'appelant (`run_godot_product_oracle`) traduit ceci en `NOT_MEASURED`
    motivé pour TOUS les volets, jamais une exception qui remonte."""
    import os

    env_bin = os.environ.get("GODOT_BIN")
    if env_bin:
        candidate = Path(env_bin)
        if candidate.is_file():
            return str(candidate)
        raise FileNotFoundError(
            f"GODOT_BIN={env_bin!r} déclaré mais introuvable sur le disque")

    config_path = Path(__file__).resolve().parent / "godot.config.json"
    if not config_path.is_file():
        raise FileNotFoundError(
            f"aucun binaire Godot configuré (ni GODOT_BIN, ni {config_path})")
    try:
        parsed = json.loads(config_path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        raise FileNotFoundError(f"{config_path} illisible/invalide : {exc}") from exc
    godot_bin = parsed.get("godot_bin") if isinstance(parsed, dict) else None
    if not isinstance(godot_bin, str) or not godot_bin:
        raise FileNotFoundError(f"{config_path} ne déclare pas de champ 'godot_bin'")
    repo_root = Path(__file__).resolve().parent.parent.parent
    candidate = (repo_root / godot_bin) if not Path(godot_bin).is_absolute() else Path(godot_bin)
    if not candidate.is_file():
        raise FileNotFoundError(
            f"binaire Godot introuvable sur le disque : {candidate} (déclaré par "
            f"{config_path})")
    return str(candidate)


def _default_runner(binary: str, game_dir: Path, script_res_path: str, *, timeout_s: int) -> dict:
    """Exécute réellement `godot --headless --path <game_dir> --script <res://...>` et
    relit la ligne `FORGE_ORACLE <nom> {json}` sur stdout. Jamais utilisé par les
    tests de ce module (`runner` injecté à la place)."""
    try:
        proc = subprocess.run(
            [binary, "--headless", "--path", str(game_dir), "--script", script_res_path],
            capture_output=True, text=True, timeout=timeout_s,
            encoding="utf-8", errors="replace",
        )
    except subprocess.TimeoutExpired:
        return {"ok": None, "timeout": True, "returncode": None, "stdout": "", "stderr": ""}
    except OSError as exc:
        return {"ok": None, "error": str(exc), "returncode": None, "stdout": "", "stderr": ""}
    return {
        "returncode": proc.returncode,
        "stdout": proc.stdout,
        "stderr": proc.stderr,
    }


def _default_gpu_runner(binary: str, game_dir: Path, script_res_path: str, *, timeout_s: int) -> dict:
    """Exécute réellement l'oracle en FENÊTRE GPU hors écran (`GPU_WINDOW_FLAGS`) au
    lieu de `--headless`, et relit la même ligne `FORGE_ORACLE <nom> {json}`. Même
    contrat de retour que `_default_runner` : la seule différence est le mode de
    lancement, jamais l'interprétation du résultat. Jamais utilisé par les tests de ce
    module (`gpu_runner` injecté à la place)."""
    try:
        proc = subprocess.run(
            [binary, *GPU_WINDOW_FLAGS, "--path", str(game_dir), "--script", script_res_path],
            capture_output=True, text=True, timeout=timeout_s,
            encoding="utf-8", errors="replace",
        )
    except subprocess.TimeoutExpired:
        return {"ok": None, "timeout": True, "returncode": None, "stdout": "", "stderr": ""}
    except OSError as exc:
        return {"ok": None, "error": str(exc), "returncode": None, "stdout": "", "stderr": ""}
    return {
        "returncode": proc.returncode,
        "stdout": proc.stdout,
        "stderr": proc.stderr,
    }


def _parse_forge_oracle_line(stdout: str) -> dict | None:
    """Retrouve la DERNIÈRE ligne `FORGE_ORACLE <nom> {json}` de stdout (le contrat
    n'exclut pas des logs avant elle) et parse son JSON. `None` si aucune ligne
    conforme ou JSON invalide — jamais une exception."""
    match = None
    for line in stdout.splitlines():
        m = _FORGE_ORACLE_LINE.match(line.strip())
        if m:
            match = m
    if match is None:
        return None
    try:
        payload = json.loads(match.group(2))
    except ValueError:
        return None
    if not isinstance(payload, dict):
        return None
    return {"volet_name": match.group(1), "payload": payload}


def run_godot_product_oracle(
    game_dir: Path,
    *,
    binary_resolver=None,
    runner=None,
    gpu_runner=None,
    timeout_s: int = 60,
) -> dict:
    """Découvre les oracles `FORGE_ORACLE` du jeu (`07_TESTS/oracle/*.gd`), les
    exécute (un process par fichier, `godot --headless --path <game_dir> --script
    res://07_TESTS/oracle/<fichier>`), et rend un mapping PLAT
    `{nom_volet: {"status": ..., "passed": ..., "fails": [...], ...}}` — même
    contrat que `product_oracle.run_product_oracle`, consommable tel quel par
    `check_observable_coverage`/`_volet_status` (`standard_oracles.py`, NON modifiés).

    - `binary_resolver()` (par défaut `_default_binary_resolver`, jamais appelé par
      les tests) doit renvoyer le chemin du binaire Godot ou lever `FileNotFoundError`.
      Binaire introuvable => TOUS les volets découverts sont `NOT_MEASURED`, raison
      nommée — jamais OK, jamais FAIL (l'absence de mesure n'est pas un échec de
      mesure, garde-fou explicite de la mission).
    - `runner(binary, game_dir, script_res_path, *, timeout_s) -> dict` (par défaut
      `_default_runner`, `--headless`) exécute UN oracle et renvoie
      `{returncode, stdout, stderr}` (ou `{ok: None, timeout: True, ...}` /
      `{ok: None, error: ..., ...}` sur échec de spawn).
    - `gpu_runner(...)` (même signature, par défaut `_default_gpu_runner`,
      `GPU_WINDOW_FLAGS`) exécute les volets qui portent la DIRECTIVE STATIQUE
      `forge:run_mode = gpu_window` dans leur source. Si seul `runner` est injecté
      (cas des tests), il sert aussi de `gpu_runner` : le routage reste observable via
      `mode_execution` sans exiger deux injections.
    - AUCUN nom de volet n'est codé en dur : le mode vient de la déclaration du `.gd`,
      jamais de `path.stem` (cf. docstring du module, retrait de
      `GPU_WINDOW_REQUIRED_VOLETS`).
    - Marqueur d'EXÉCUTION (autorité sur le verdict, indépendant du mode) : un volet
      dont le payload FORGE_ORACLE déclare `"requires_gpu_window": true` est rendu
      `NOT_MEASURED`, raison citant la leçon
      `forge.oracle_fail_vs_not_measured_marker`, MÊME SI `ok` vaut `false` et QUEL
      QUE SOIT le mode — jamais un FAIL fabriqué sur ce qui n'a pas pu être mesuré.
    - Chaque volet exécuté porte `mode_execution` ∈ {`"gpu_window"`, `"headless"`}.
    - Robustesse : sortie illisible, JSON invalide, oracle absent, timeout du process
      => `NOT_MEASURED` motivé, JAMAIS d'exception qui remonte à l'appelant.
    """
    game_dir = Path(game_dir)
    binary_resolver = binary_resolver or _default_binary_resolver
    # `gpu_runner` retombe sur le `runner` INJECTÉ (pas sur `_default_runner`) avant de
    # retomber sur le runner GPU réel : un test qui n'injecte qu'un runner n'ouvre
    # jamais une vraie fenêtre Godot par surprise.
    gpu_runner = gpu_runner or runner or _default_gpu_runner
    runner = runner or _default_runner

    oracle_files = discover_oracle_files(game_dir)
    if not oracle_files:
        return {}

    try:
        binary = binary_resolver()
    except Exception as exc:  # noqa: BLE001 — absence de mesure, jamais une exception
        reason = f"binaire Godot introuvable/non configuré : {exc}"
        logger.warning("product_oracle_godot: %s", reason)
        return {
            path.stem: _not_measured(reason, fichier=str(path))
            for path in oracle_files
        }

    result: dict = {}
    for path in oracle_files:
        volet_name = path.stem

        # GARDE STATIQUE (Task 3, avant toute exécution) : le volet doit charger la
        # VRAIE scène principale (`res://main.tscn`), sinon il est rejeté SANS spawn —
        # aucun process Godot lancé pour ce volet.
        try:
            source_sans_commentaires = _strip_gd_comments(path.read_text(encoding="utf-8"))
        except (OSError, UnicodeDecodeError) as exc:
            source_sans_commentaires = ""
            logger.warning(
                "product_oracle_godot: lecture échouée pour la garde statique sur %s (%s)",
                path, exc)
        if not _VOLET_REAL_SCENE.search(source_sans_commentaires):
            result[volet_name] = {
                "status": "FAIL",
                "passed": False,
                "checked": True,
                "mode_execution": _STATIC_GUARD_MODE,
                "fails": [
                    "volet construit sa propre scène : aucun chargement de "
                    "res://main.tscn (décision Pierre 2026-08-22)"
                ],
                "fichier": str(path),
                "payload": {},
            }
            continue

        # GARDE ANTI-CONTOURNEMENT V4 (avant tout spawn, même discipline que la
        # garde de scène ci-dessus) : ce volet prouve-t-il la boucle par un canal
        # que le joueur n'a pas (Economy/api_*/05_SYSTEMS/runtime.gd) ?
        bypass_match = _LOOP_BYPASS_TOKENS.search(source_sans_commentaires)
        if bypass_match:
            result[volet_name] = {
                "status": "FAIL",
                "passed": False,
                "checked": True,
                "mode_execution": _STATIC_GUARD_MODE,
                "fails": [
                    "boucle validée par un canal que le joueur n'a pas : "
                    f"{bypass_match.group(0)} (décision Pierre 2026-08-22)"
                ],
                "fichier": str(path),
                "payload": {},
            }
            continue

        # ROUTAGE : la directive statique du `.gd` décide du mode, jamais son nom.
        gpu = _gpu_window_declared(path)
        mode = _GPU_MODE if gpu else _HEADLESS_MODE
        chosen_runner = gpu_runner if gpu else runner

        script_res_path = f"res://07_TESTS/oracle/{path.name}"
        try:
            run_out = chosen_runner(binary, game_dir, script_res_path, timeout_s=timeout_s)
        except Exception as exc:  # noqa: BLE001 — best-effort, jamais bloquant
            logger.warning(
                "product_oracle_godot: exécution échouée pour %s (mode %s, %s)",
                path, mode, exc)
            result[volet_name] = _not_measured(
                f"exception levée en exécutant {path.name} (mode {mode}) : {exc}",
                fichier=str(path), mode_execution=mode)
            continue

        if not isinstance(run_out, dict):
            result[volet_name] = _not_measured(
                f"runner a renvoyé une valeur non exploitable pour {path.name} (mode {mode})",
                fichier=str(path), mode_execution=mode)
            continue
        if run_out.get("timeout"):
            result[volet_name] = _not_measured(
                f"timeout ({timeout_s}s) sur {path.name} (mode {mode})",
                fichier=str(path), mode_execution=mode)
            continue
        if run_out.get("error"):
            result[volet_name] = _not_measured(
                f"exécuteur Godot introuvable/inexécutable (mode {mode}) : {run_out['error']}",
                fichier=str(path), mode_execution=mode)
            continue

        stdout = run_out.get("stdout") or ""
        parsed = _parse_forge_oracle_line(stdout)
        if parsed is None:
            result[volet_name] = _not_measured(
                f"sortie FORGE_ORACLE illisible/absente pour {path.name} (mode {mode})",
                fichier=str(path), mode_execution=mode,
                returncode=run_out.get("returncode"),
                stdout_tail=stdout[-500:], stderr_tail=(run_out.get("stderr") or "")[-500:],
            )
            continue

        payload = parsed["payload"]

        if payload.get(_GPU_WINDOW_MARKER_KEY) is True:
            # Marqueur d'EXÉCUTION : le volet déclare lui-même n'avoir rien pu mesurer.
            # Vaut dans LES DEUX MODES — c'est une déclaration sur le résultat, pas sur
            # le mode de lancement (que la directive statique a déjà tranché plus haut).
            result[volet_name] = _not_measured(
                _marker_gpu_window_reason(path.name, mode),
                fichier=str(path), mode_execution=mode, payload=payload)
            continue

        ok = payload.get("ok")
        if not isinstance(ok, bool):
            result[volet_name] = _not_measured(
                f"champ 'ok' absent/non booléen dans la sortie FORGE_ORACLE de "
                f"{path.name} (mode {mode})",
                fichier=str(path), mode_execution=mode, payload=payload)
            continue

        result[volet_name] = {
            "status": "OK" if ok else "FAIL",
            "passed": ok,
            "checked": True,
            "fails": payload.get("fails", []),
            "fichier": str(path),
            "mode_execution": mode,
            "payload": payload,
        }

    return result


RUNTIME_ALIVE_PROBE = Path(__file__).resolve().parent / "godot_probes" / "runtime_alive.gd"


def run_runtime_alive(game_dir: Path, *, binary_resolver=None, gpu_runner=None,
                      timeout_s: int = 90) -> dict:
    """Charge la VRAIE scène principale du jeu en fenêtre GPU via la sonde externe
    `godot_probes/runtime_alive.gd` (jamais un volet du jeu : un volet peut se construire sa
    propre scène — décision Pierre 2026-08-22). NOT_MEASURED honnête sans binaire ; FAIL si la
    sonde ne rend aucune ligne FORGE_ORACLE (une sortie muette n'est pas une preuve)."""
    resolver = binary_resolver or _default_binary_resolver          # même résolveur que les volets
    try:
        binary = resolver()
    except Exception as exc:  # noqa: BLE001 — absence de mesure, jamais une exception
        binary = None
    base = {"fichier": str(RUNTIME_ALIVE_PROBE), "mode_execution": "gpu_window"}
    if not binary:
        return {**base, "status": "NOT_MEASURED", "passed": False, "checked": False,
                "fails": ["binaire Godot introuvable"], "payload": {}}
    runner = gpu_runner or _default_gpu_runner
    out = runner(binary, Path(game_dir), str(RUNTIME_ALIVE_PROBE), timeout_s=timeout_s)
    payload = _parse_forge_oracle_line(out.get("stdout", "")) if isinstance(out, dict) else None
    if payload is None:
        return {**base, "status": "FAIL", "passed": False, "checked": True,
                "fails": ["sonde sans ligne FORGE_ORACLE (sortie muette, rc=%s)" % (out.get("returncode") if isinstance(out, dict) else None)],
                "payload": {"stdout_tail": str(out.get("stdout", ""))[-400:] if isinstance(out, dict) else ""}}
    ok = bool(payload["payload"].get("ok"))
    return {**base, "status": "OK" if ok else "FAIL", "passed": ok, "checked": True,
            "fails": list(payload["payload"].get("fails", [])), "payload": payload["payload"]}


def check_loop_bypass(game_dir: Path) -> dict:
    """Garde anti-contournement V4 (décision Pierre 2026-08-22), STANDALONE : scanne
    `<game_dir>/07_TESTS/oracle/*.gd` ET `<game_dir>/solvability.gd` (lecture
    statique seule, jamais un spawn) à la recherche des tokens interdits
    (`_LOOP_BYPASS_TOKENS` — même liste que la garde par-volet de
    `run_godot_product_oracle`, jamais dupliquée). Rend `{passed, violations:
    [{fichier, token}]}` — `passed` faux dès qu'une violation existe. Un fichier
    illisible est ignoré (best-effort, jamais une exception)."""
    game_dir = Path(game_dir)
    files: list[Path] = []
    oracle_dir = game_dir / "07_TESTS" / "oracle"
    if oracle_dir.is_dir():
        files.extend(sorted(oracle_dir.glob("*.gd")))
    solvability = game_dir / "solvability.gd"
    if solvability.is_file():
        files.append(solvability)

    violations: list[dict] = []
    for path in files:
        try:
            source = _strip_gd_comments(path.read_text(encoding="utf-8"))
        except (OSError, UnicodeDecodeError) as exc:
            logger.warning("product_oracle_godot: lecture échouée pour check_loop_bypass sur %s (%s)", path, exc)
            continue
        seen: set[str] = set()
        for m in _LOOP_BYPASS_TOKENS.finditer(source):
            token = m.group(0)
            if token in seen:
                continue
            seen.add(token)
            violations.append({"fichier": str(path), "token": token})

    return {"passed": not violations, "violations": violations}


# Tokens économiques (Lot B, T3, plan `2026-08-23-forge-lot-b-game-master.md`,
# contrat s9 règle (14)) : un nom de `const`/`var` qui CONTIENT un de ces tokens
# est présumé porter un coût/seuil/bonus de gameplay — donc devoir venir du
# registre `03_WORLD/economy.json`, jamais d'une constante en dur. Substring,
# jamais un `\b` (des noms comme `PASSIVE_UNIT`, `KITTEN_STEP` n'ont pas de
# frontière de mot avant le token : `_` est un caractère de mot).
_ECONOMY_TOKENS = (
    "COST", "COUT", "PRICE", "PRIX", "THRESHOLD", "SEUIL", "BONUS", "MULT",
    "MULTIPLIER", "BASE_CLICK", "STEP", "RATE", "TAUX", "UNIT",
)

# Déclaration `const NOM ... = <nombre>` ou `var nom ... = <nombre>`, avec
# annotation de type optionnelle (`: int`, `: float`...). Ancrée en début de
# ligne (après indentation) : une mention du mot `const`/`var` ailleurs dans la
# ligne (commentaire déjà retiré par `_strip_gd_comments`) n'est pas une
# déclaration.
_ECONOMY_CONST_RE = re.compile(
    r'^\s*(?:static\s+)?(?:const|var)\s+(?P<name>[A-Za-z_][A-Za-z0-9_]*)'
    r'\s*(?::\s*[A-Za-z_][A-Za-z0-9_]*)?\s*=\s*(?P<value>-?\d+(?:\.\d+)?)\b')

# Chargement du registre économique — présence conjointe (n'importe où dans le
# fichier) d'un appel `load`/`FileAccess` ET de la chaîne `economy.json`. Couvre
# l'appel direct (`load(`) et l'appel de méthode chaînée (`FileAccess.open(`,
# `FileAccess.get_file_as_string(`).
_ECONOMY_JSON_LOAD_RE = re.compile(r'\bload\s*\(|\bFileAccess\s*\.\s*\w+\s*\(', re.IGNORECASE)


def _is_economic_token(name: str) -> bool:
    """Vrai si `name` (nom de constante/variable) contient un token économique
    (`_ECONOMY_TOKENS`) — substring insensible à la casse, jamais un `\\b`."""
    upper = name.upper()
    return any(token in upper for token in _ECONOMY_TOKENS)


def _loads_economy_registry(source: str) -> bool:
    """Vrai si le fichier (source SANS commentaires) charge le registre
    `economy.json` : un appel `load(`/`FileAccess...(` ET la chaîne littérale
    `economy.json` sont présents QUELQUE PART dans le fichier — pas
    nécessairement la même ligne (un chemin peut être construit en deux temps)."""
    return "economy.json" in source and bool(_ECONOMY_JSON_LOAD_RE.search(source))


def _referenced_via_dict(source: str, name: str) -> bool:
    """Vrai si `name` est référencé ailleurs dans le fichier via un accès de
    type dictionnaire (`dict["NOM"]`, `dict['NOM']`, `dict.get("NOM"`) — la
    preuve que la CONSTANTE elle-même n'est pas la source de vérité utilisée à
    l'exécution, mais une clé vers le registre chargé (`_loads_economy_registry`)."""
    escaped = re.escape(name)
    patterns = (
        rf'\[\s*"{escaped}"\s*\]',
        rf"\[\s*'{escaped}'\s*\]",
        rf'\.get\(\s*["\']{escaped}["\']',
    )
    return any(re.search(p, source) for p in patterns)


def check_economy_bypass(game_dir: Path, economy_json: Path | str | None = None) -> dict:
    """Garde statique anti-contournement ÉCONOMIE (Lot B, T3, contrat s9 règle
    (14)) : dans `<game_dir>/05_SYSTEMS/**/*.gd`, toute déclaration `const`/`var`
    dont le NOM contient un token économique (`_ECONOMY_TOKENS`) et une valeur
    NUMÉRIQUE littérale est une violation — SAUF si le fichier charge le
    registre `economy.json` (`_loads_economy_registry`) ET référence CETTE
    constante via un accès dictionnaire ailleurs dans le même fichier
    (`_referenced_via_dict`) : la constante nomme alors une CLÉ du registre,
    jamais la source de vérité. Même discipline lecture-seule que
    `check_loop_bypass` — aucun spawn, un fichier illisible est ignoré
    (best-effort, jamais une exception).

    Si `economy_json` (chemin DISQUE, typiquement `<run_dir>/economy.json`) est
    fourni : vérifie EN PLUS que `<game_dir>/03_WORLD/economy.json` existe et a
    le MÊME sha256 — `economy.json` est une PROJECTION déterministe déposée par
    le run, jamais réécrite par le builder (même garde que `run_player_loop`
    pour `03_WORLD/loop.json`). Absence/altération -> violation nommée
    `economy_json_absent`/`economy_json_altere`, jamais une exception.

    Rend `{passed, violations: [{fichier, ligne, nom, valeur}]}` — `passed` faux
    dès qu'une violation existe."""
    game_dir = Path(game_dir)
    violations: list[dict] = []

    systems_dir = game_dir / "05_SYSTEMS"
    files: list[Path] = sorted(systems_dir.rglob("*.gd")) if systems_dir.is_dir() else []
    for path in files:
        try:
            raw = path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError) as exc:
            logger.warning(
                "product_oracle_godot: lecture échouée pour check_economy_bypass sur %s (%s)",
                path, exc)
            continue
        source = _strip_gd_comments(raw)
        exempt_file = _loads_economy_registry(source)
        for lineno, line in enumerate(source.splitlines(), start=1):
            m = _ECONOMY_CONST_RE.match(line)
            if not m:
                continue
            name = m.group("name")
            if not _is_economic_token(name):
                continue
            if exempt_file and _referenced_via_dict(source, name):
                continue
            violations.append({
                "fichier": str(path), "ligne": lineno, "nom": name,
                "valeur": m.group("value"),
            })

    if economy_json is not None:
        run_economy = Path(economy_json)
        game_economy = game_dir / "03_WORLD" / "economy.json"
        if not run_economy.is_file():
            violations.append({
                "fichier": str(run_economy), "ligne": 0,
                "nom": "economy_json_absent", "valeur": None,
            })
        elif not game_economy.is_file():
            violations.append({
                "fichier": str(game_economy), "ligne": 0,
                "nom": "economy_json_absent", "valeur": None,
            })
        else:
            try:
                same = _sha256_bytes(run_economy) == _sha256_bytes(game_economy)
            except OSError as exc:
                violations.append({
                    "fichier": str(game_economy), "ligne": 0,
                    "nom": "economy_json_illisible", "valeur": str(exc),
                })
            else:
                if not same:
                    violations.append({
                        "fichier": str(game_economy), "ligne": 0,
                        "nom": "economy_json_altere", "valeur": None,
                    })

    return {"passed": not violations, "violations": violations}


PLAYER_LOOP_PROBE = Path(__file__).resolve().parent / "godot_probes" / "player_loop.gd"


def _sha256_bytes(path: Path) -> str:
    import hashlib
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run_player_loop(
    game_dir: Path,
    *,
    run_dir: Path | str | None = None,
    binary_resolver=None,
    gpu_runner=None,
    timeout_s: int = 180,
) -> dict:
    """Rejoue `loop.json` avec le bot-joueur générique `godot_probes/player_loop.gd`
    (jamais un volet du jeu — même discipline que `run_runtime_alive`). Même forme
    de retour que `run_runtime_alive`.

    AVANT tout spawn :
      - si `run_dir/loop.json` ET `<game_dir>/03_WORLD/loop.json` existent tous les
        deux et que leurs sha256 diffèrent -> `FAIL` sans spawn (« loop.json altéré » —
        `loop.json` est une PROJECTION déterministe du Prisme déposée par le run,
        jamais une source de vérité que le builder pourrait réécrire) ;
      - si `<game_dir>/03_WORLD/loop.json` est absent -> `SKIPPED` motivé (le jeu
        n'a pas encore de boucle projetée), le runner n'est JAMAIS appelé.

    NOT_MEASURED honnête sans binaire Godot ; FAIL si la sonde ne rend aucune ligne
    FORGE_ORACLE (sortie muette = pas une preuve), jamais une exception qui remonte."""
    game_dir = Path(game_dir)
    game_loop = game_dir / "03_WORLD" / "loop.json"
    base = {"fichier": str(PLAYER_LOOP_PROBE), "mode_execution": "gpu_window"}

    if run_dir is not None:
        run_dir_loop = Path(run_dir) / "loop.json"
        if run_dir_loop.is_file() and game_loop.is_file():
            try:
                sha_run = _sha256_bytes(run_dir_loop)
                sha_game = _sha256_bytes(game_loop)
            except OSError as exc:
                return {**base, "status": "NOT_MEASURED", "passed": False, "checked": False,
                        "fails": [], "reason": f"lecture sha impossible : {exc}", "payload": {}}
            if sha_run != sha_game:
                return {**base, "status": "FAIL", "passed": False, "checked": True,
                        "fails": [f"03_WORLD/loop.json altéré : sha != {run_dir_loop}"],
                        "payload": {}}

    if not game_loop.is_file():
        return {**base, "status": "SKIPPED", "checked": False, "passed": False,
                "reason": "pas de 03_WORLD/loop.json"}

    resolver = binary_resolver or _default_binary_resolver
    try:
        binary = resolver()
    except Exception:  # noqa: BLE001 — absence de mesure, jamais une exception
        binary = None
    if not binary:
        return {**base, "status": "NOT_MEASURED", "passed": False, "checked": False,
                "fails": ["binaire Godot introuvable"], "payload": {}}

    runner = gpu_runner or _default_gpu_runner
    out = runner(binary, game_dir, str(PLAYER_LOOP_PROBE), timeout_s=timeout_s)
    payload = _parse_forge_oracle_line(out.get("stdout", "")) if isinstance(out, dict) else None
    if payload is None:
        return {**base, "status": "FAIL", "passed": False, "checked": True,
                "fails": ["sonde sans ligne FORGE_ORACLE (sortie muette, rc=%s)" %
                          (out.get("returncode") if isinstance(out, dict) else None)],
                "payload": {"stdout_tail": str(out.get("stdout", ""))[-400:] if isinstance(out, dict) else ""}}
    ok = bool(payload["payload"].get("ok"))
    return {**base, "status": "OK" if ok else "FAIL", "passed": ok, "checked": True,
            "fails": list(payload["payload"].get("fails", [])), "payload": payload["payload"]}


# =====================================================================================
# ORACLE DE DIVERGENCE PRODUIT (P6, invariant INV-4 : tout paramètre déclaré doit
# produire un effet runtime mesurable).
#
# ┌───────────────────────────────────────────────────────────────────────────────────┐
# │ STATUT : PASSIVE / NOT_WIRED — ce sous-système n'est PAS une capacité active.      │
# └───────────────────────────────────────────────────────────────────────────────────┘
# Audit de réalité du 2026-08-10 (déclaration → producteur → consommateur → runtime →
# preuve). Ce qui est VRAI : le code existe, il est testé (17 tests verts dans
# `tests/test_product_oracle_godot_divergence.py`), et la convention d'emplacement est
# réelle — `07_TESTS/oracle/` existe déjà dans 5 jeux (breakout_v2, pacman, pong, snake,
# tetris). Ce qui MANQUE, mesuré :
#
#   · CONSOMMATEUR : aucun. `driver.py:70` n'importe que `has_godot_capacity` et
#     `run_godot_product_oracle`. `run_divergence_oracle`, `has_divergence_capacity` et
#     `discover_divergence_manifest` ne sont importés par personne hors leurs tests.
#   · DONNÉE D'ENTRÉE : aucune. AUCUN jeu du dépôt ne porte de `divergence_manifest.json`.
#     Même branché, ce mécanisme n'aurait rien à mesurer aujourd'hui.
#   · PRODUCTEUR DE MANIFESTE : aucun, et aucun n'est déclaré — ni contrat d'étape, ni
#     `standard/`, ni documentation. La prochaine étape n'est pas inscrite dans le dépôt.
#
# Pourquoi c'est écrit ici plutôt que corrigé : `IMPLEMENTED + TESTED + 0 consommateur
# + 0 donnée d'entrée = PASSIVE`, jamais une capacité opérationnelle. Des tests verts ne
# sont pas un critère de fin — c'est précisément le défaut architectural que la
# réparation de la boucle de revue (commit 314fe19) vient d'éliminer ailleurs, et le
# studio compte déjà plusieurs capteurs dans cette situation. Marquer le statut est la
# règle « déclaré ≠ exécuté » : un sous-système inerte doit se déclarer inerte, sinon la
# carte ment en silence.
#
# POUR L'ACTIVER, dans cet ordre : (1) décider qui produit `divergence_manifest.json` et
# l'inscrire dans un contrat d'étape ; (2) brancher `run_divergence_oracle` au point
# `s10a` de `driver.py`, où `run_godot_product_oracle` est déjà câblé ; (3) prouver sur
# un jeu réel. Tant que (1) n'est pas tranché par HumanGate, (2) et (3) sont prématurés.
#
# GÉNÉRALISATION du test différentiel écrit À LA MAIN une seule fois pour Pac-Man
# (`GAMES/pacman/07_TESTS/oracle/v6_p1_mode_governs_lives.gd`, lot V6, 2026-08-06) : le
# défaut mesuré alors — un mode de jeu déclaré, `godot_oracle` VERT à 2612 assertions,
# 0 divergence d'état sur 200 tics entre les deux modes — n'avait été trouvé par AUCUN
# oracle de la chaîne, seulement par une mesure différentielle ad hoc. Ce module la rend
# RÉUTILISABLE : un paramètre par entrée de manifeste, une sonde Godot générique
# (`godot_probes/divergence_probe.gd`, hors GAMES/**), deux campagnes par paramètre
# (CONTRÔLE + RÉEL), jamais réécrites à la main pour le prochain jeu.
#
# CONVENTION DE DÉCOUVERTE (nouvelle, lecture seule, même discipline que
# `discover_oracle_files` ci-dessus) : `<game_dir>/07_TESTS/oracle/divergence_manifest.json`
#   {"params": [{"id": "mode", "adapter": "res://.../adapter.gd" | "chemin/disque",
#                "values": [v_a, v_b], "seed": 7, "ticks": 200,
#                "ignore_keys": ["mode_jeu"]}, ...]}
# Absence de manifeste (jeu non retrofit, ex. GAMES/pacman — produit gelé, jamais
# modifié par ce module) => mapping VIDE, jamais une erreur : exactement le même
# comportement que `run_godot_product_oracle` sur un jeu sans oracle `.gd`.
#
# L'ADAPTATEUR (contrat documenté en tête de `divergence_probe.gd`) porte la
# connaissance PROPRE AU JEU (comment construire un état, l'avancer, le projeter) ; ce
# module et la sonde ne connaissent RIEN d'un jeu particulier — c'est ce qui rend la
# capacité réutilisable d'un jeu à l'autre sans dupliquer l'instrument de mesure.
#
# `adapter` peut être un chemin `res://` (adaptateur livré DANS le projet du jeu, comme
# les autres oracles `.gd`) ou un chemin DISQUE (relatif au repo racine, ou absolu) —
# utile pour les preuves reconstituées hors du jeu (`EVIDENCE/bundles/...`), sans
# jamais écrire sous `GAMES/**`. Vérifié 2026-08-07 : `load()` résout un chemin disque
# même sous un `--path` de projet différent.
#
# Discipline NOT_MEASURED != OK identique au reste du module : binaire absent, sortie
# illisible, timeout, déclaration incomplète => `NOT_MEASURED` motivé, jamais un vert ni
# un rouge fabriqué.

DIVERGENCE_PROBE_PATH = Path(__file__).resolve().parent / "godot_probes" / "divergence_probe.gd"
_DIVERGENCE_MANIFEST_REL = Path("07_TESTS") / "oracle" / "divergence_manifest.json"
_REPO_ROOT = Path(__file__).resolve().parent.parent.parent

# Budget par défaut si l'entrée du manifeste ne le déclare pas.
DEFAULT_DIVERGENCE_SEED = 7
DEFAULT_DIVERGENCE_TICKS = 200


def discover_divergence_manifest(game_dir: Path) -> dict | None:
    """Lit `<game_dir>/07_TESTS/oracle/divergence_manifest.json` (lecture seule).
    `None` si le fichier est absent, illisible, JSON invalide, de forme non-dict, ou
    sans clé `params` de type liste — JAMAIS une exception. L'absence de manifeste
    signifie « ce jeu n'a pas encore été retrofit sur cette capacité », pas une erreur :
    c'est la mesure de CAPACITÉ, symétrique de `discover_oracle_files`."""
    path = Path(game_dir) / _DIVERGENCE_MANIFEST_REL
    if not path.is_file():
        return None
    try:
        parsed = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        logger.warning("product_oracle_godot: manifeste de divergence illisible (%s)", exc)
        return None
    if not isinstance(parsed, dict):
        return None
    params = parsed.get("params")
    if not isinstance(params, list):
        return None
    return parsed


def has_divergence_capacity(game_dir: Path) -> bool:
    """CAPACITÉ constatée : au moins un paramètre déclaré dans le manifeste de
    divergence de ce jeu."""
    manifest = discover_divergence_manifest(game_dir)
    return bool(manifest and manifest.get("params"))


def _resolve_adapter_path(adapter: str) -> str:
    """`res://...` est laissé tel quel (résolu par Godot via `--path <game_dir>`).
    Toute autre valeur est traitée comme un chemin DISQUE : absolu tel quel, sinon
    résolu relativement à la racine du dépôt (convention des chemins de preuve sous
    `EVIDENCE/bundles/...`)."""
    if adapter.startswith("res://"):
        return adapter
    candidate = Path(adapter)
    if not candidate.is_absolute():
        candidate = (_REPO_ROOT / candidate)
    return str(candidate).replace("\\", "/")


def _default_divergence_runner(
    binary: str, game_dir: Path, probe_script: Path, user_args: list[str], *, timeout_s: int
) -> dict:
    """Exécute réellement `godot --headless --path <game_dir> --script
    <divergence_probe.gd absolu> -- <user_args>`. Jamais utilisé par les tests de ce
    module (`runner` injecté à la place)."""
    try:
        proc = subprocess.run(
            [binary, "--headless", "--path", str(game_dir), "--script", str(probe_script),
             "--", *user_args],
            capture_output=True, text=True, timeout=timeout_s,
            encoding="utf-8", errors="replace",
        )
    except subprocess.TimeoutExpired:
        return {"ok": None, "timeout": True, "returncode": None, "stdout": "", "stderr": ""}
    except OSError as exc:
        return {"ok": None, "error": str(exc), "returncode": None, "stdout": "", "stderr": ""}
    return {
        "returncode": proc.returncode,
        "stdout": proc.stdout,
        "stderr": proc.stderr,
    }


def run_divergence_oracle(
    game_dir: Path,
    *,
    binary_resolver=None,
    runner=None,
    timeout_s: int = 60,
    probe_script: Path | None = None,
) -> dict:
    """Découvre le manifeste de divergence du jeu, exécute la sonde générique
    `divergence_probe.gd` une fois PAR PARAMÈTRE déclaré (un process par paramètre), et
    rend un mapping PLAT `{"divergence_<id>": {...}}` — même contrat que
    `run_godot_product_oracle`, consommable par `check_observable_coverage`.

    Chaque volet résultat porte :
      - `status` : OK (contrôle à 0 ET réel > 0) | FAIL (contrôle bruité OU paramètre
        inerte) | NOT_MEASURED (binaire absent, déclaration incomplète, exécution
        illisible/timeout) ;
      - `fails` : raisons NOMMÉES (le paramètre, les clés d'état comparées) — jamais un
        simple booléen ;
      - `controle`/`reel` : `{ticks, ticks_divergents, cles}` des deux campagnes ;
      - `cout_ms` : durée mesurée côté sonde (Godot) ; `host_duration_ms` : durée
        mesurée côté appelant (inclut le lancement du process) — le COÛT PAR PARAMÈTRE
        que ce capteur devra payer à chaque lot, tel que demandé par la mission.
    """
    game_dir = Path(game_dir)
    binary_resolver = binary_resolver or _default_binary_resolver
    runner = runner or _default_divergence_runner
    probe_script = probe_script or DIVERGENCE_PROBE_PATH

    manifest = discover_divergence_manifest(game_dir)
    params = (manifest or {}).get("params") or []
    if not params:
        return {}

    try:
        binary = binary_resolver()
    except Exception as exc:  # noqa: BLE001 — absence de mesure, jamais une exception
        reason = f"binaire Godot introuvable/non configuré : {exc}"
        logger.warning("product_oracle_godot: %s", reason)
        return {
            f"divergence_{p.get('id') if isinstance(p, dict) else i}": _not_measured(reason)
            for i, p in enumerate(params)
        }

    result: dict = {}
    for i, raw in enumerate(params):
        if not isinstance(raw, dict):
            result[f"divergence_{i}"] = _not_measured(
                f"entrée #{i} du manifeste de divergence n'est pas un objet")
            continue

        param_id = str(raw.get("id") or f"param_{i}")
        volet_name = f"divergence_{param_id}"

        adapter = raw.get("adapter")
        values = raw.get("values")
        if not isinstance(adapter, str) or not adapter:
            result[volet_name] = _not_measured(
                f"paramètre '{param_id}' : champ 'adapter' manquant/invalide dans le manifeste")
            continue
        if not isinstance(values, list) or len(values) < 2:
            result[volet_name] = _not_measured(
                f"paramètre '{param_id}' : 'values' doit lister au moins 2 valeurs "
                f"(reçu {values!r}) — il faut au moins une valeur A et une valeur B à comparer")
            continue

        seed = raw.get("seed", DEFAULT_DIVERGENCE_SEED)
        ticks = raw.get("ticks", DEFAULT_DIVERGENCE_TICKS)
        ignore_keys = raw.get("ignore_keys") or []
        value_a, value_b = values[0], values[1]

        user_args = [
            f"--adapter={_resolve_adapter_path(adapter)}",
            f"--param={param_id}",
            f"--seed={int(seed)}",
            f"--ticks={int(ticks)}",
            f"--value_a={value_a}",
            f"--value_b={value_b}",
        ]
        if ignore_keys:
            user_args.append(f"--ignore={','.join(str(k) for k in ignore_keys)}")

        t0 = time.monotonic()
        try:
            run_out = runner(binary, game_dir, probe_script, user_args, timeout_s=timeout_s)
        except Exception as exc:  # noqa: BLE001 — best-effort, jamais bloquant
            logger.warning(
                "product_oracle_godot: exécution de la sonde de divergence échouée pour "
                "'%s' (%s)", param_id, exc)
            result[volet_name] = _not_measured(
                f"exception levée en exécutant la sonde de divergence pour '{param_id}' : {exc}")
            continue
        host_duration_ms = int((time.monotonic() - t0) * 1000)

        if not isinstance(run_out, dict):
            result[volet_name] = _not_measured(
                f"runner a renvoyé une valeur non exploitable pour '{param_id}'")
            continue
        if run_out.get("timeout"):
            result[volet_name] = _not_measured(
                f"timeout ({timeout_s}s) sur la sonde de divergence pour '{param_id}'")
            continue
        if run_out.get("error"):
            result[volet_name] = _not_measured(
                f"exécuteur Godot introuvable/inexécutable pour '{param_id}' : {run_out['error']}")
            continue

        stdout = run_out.get("stdout") or ""
        parsed = _parse_forge_oracle_line(stdout)
        if parsed is None:
            result[volet_name] = _not_measured(
                f"sortie FORGE_ORACLE illisible/absente pour la sonde de divergence de "
                f"'{param_id}'", returncode=run_out.get("returncode"),
                stdout_tail=stdout[-500:], stderr_tail=(run_out.get("stderr") or "")[-500:])
            continue

        payload = parsed["payload"]
        ok = payload.get("ok")
        if not isinstance(ok, bool):
            result[volet_name] = _not_measured(
                f"champ 'ok' absent/non booléen dans la sortie de la sonde de divergence "
                f"pour '{param_id}'", payload=payload)
            continue

        result[volet_name] = {
            "status": "OK" if ok else "FAIL",
            "passed": ok,
            "checked": True,
            "fails": payload.get("fails", []),
            "param": param_id,
            "controle": payload.get("controle"),
            "reel": payload.get("reel"),
            "cout_ms": payload.get("cout_ms"),
            "host_duration_ms": host_duration_ms,
            "payload": payload,
        }

    return result

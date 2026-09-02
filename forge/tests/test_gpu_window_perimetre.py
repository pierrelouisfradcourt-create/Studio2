# P0-4, restriction de perimetre 2026-08-16 (GO Pierre) — l'oracle n'inspecte QUE ce que
# le collecteur LANCE.
#
# Defaut mesure : `check_gpu_window_directive` parcourait TOUS les `.gd` du repertoire
# d'oracles. Or le collecteur ne LANCE que ceux qui portent le marqueur `FORGE_ORACLE`
# (product_oracle_godot.discover_oracle_files) ; les autres sont des SOUS-MODULES
# (`extends RefCounted`, aucun payload emis) agreges par un runner, jamais routes.
# Imposer une directive de ROUTAGE a un fichier qui n'est pas route n'a aucune realite.
#
# Chiffres du 2026-08-16 : pacman portait SIX « defauts » sur 104 fichiers dont ZERO n'est
# un volet reel ; et 4 des 7 directives posees en e02b010 se sont revelees inertes pour la
# meme raison. L'oracle mesurait un perimetre plus large que son autorite.
#
# AUCUNE REGLE REIMPLEMENTEE : `_ORACLE_MARKER` est importe du collecteur, comme
# `_GPU_WINDOW_DIRECTIVE` et `_GPU_WINDOW_MARKER_KEY` avant lui. Meme autorite, trois fois.
from __future__ import annotations

from pathlib import Path

import pytest

from forge.product_oracle_godot import _GPU_WINDOW_MARKER_KEY, _ORACLE_MARKER
from forge.standard_oracles import check_gpu_window_directive

REPO = Path(__file__).resolve().parents[2]

PROSE = "# Ce volet exige une fenetre GPU reelle pour prouver le rendu.\n"


def _volet_lance(dossier: Path, nom: str, extra: str = "") -> Path:
    """Un `.gd` que le collecteur LANCE : il porte le marqueur d'emission."""
    dossier.mkdir(parents=True, exist_ok=True)
    p = dossier / nom
    p.write_text(PROSE + extra + f'\nfunc run():\n\tprint("{_ORACLE_MARKER} x " + "{{}}")\n',
                 encoding="utf-8")
    return p


def _sous_module(dossier: Path, nom: str) -> Path:
    """Un `.gd` que le collecteur NE lance PAS : aucun marqueur d'emission."""
    dossier.mkdir(parents=True, exist_ok=True)
    p = dossier / nom
    p.write_text(PROSE + "extends RefCounted\nfunc mesure():\n\tpass\n", encoding="utf-8")
    return p


def test_un_sous_module_n_est_PAS_un_defaut(tmp_path):
    """LE CAS DE LA RESTRICTION : prose GPU dans un fichier jamais lance => hors sujet."""
    _sous_module(tmp_path, "v2_core_render.gd")
    r = check_gpu_window_directive(tmp_path)
    assert r["passed"] is True
    assert r["fichiers_en_defaut"] == []
    assert r["sous_modules_ignores"] == ["v2_core_render.gd"]
    assert r["fichiers_examines"] == 0, "un sous-module n'est meme pas EXAMINE"


def test_un_VOLET_LANCE_sans_directive_reste_un_defaut(tmp_path):
    """L'invariant d'origine ne bouge pas la ou il a un sens."""
    _volet_lance(tmp_path, "core_render_frame.gd")
    r = check_gpu_window_directive(tmp_path)
    assert r["passed"] is False
    assert r["verdict"] == "BLOCKED"
    assert r["fichiers_en_defaut"] == ["core_render_frame.gd"]
    assert r["fichiers_examines"] == 1


def test_le_perimetre_SEPARE_les_deux_populations(tmp_path):
    """Un repertoire mixte : seul le volet lance est juge, le sous-module est ecarte —
    et les deux sont RAPPORTES, jamais tus."""
    _volet_lance(tmp_path, "core_render_frame.gd")
    _sous_module(tmp_path, "render_maze_and_entities.gd")
    r = check_gpu_window_directive(tmp_path)
    assert r["fichiers_examines"] == 1
    assert r["fichiers_en_defaut"] == ["core_render_frame.gd"]
    assert r["sous_modules_ignores"] == ["render_maze_and_entities.gd"]


def test_les_trois_etats_survivent_a_la_restriction(tmp_path):
    """Directive / renoncement / defaut restent discrimines — sur les volets LANCES."""
    _volet_lance(tmp_path, "a.gd", "# forge:run_mode = gpu_window\n")
    _volet_lance(tmp_path, "b.gd", f'# "{_GPU_WINDOW_MARKER_KEY}": true\n')
    _volet_lance(tmp_path, "c.gd")
    r = check_gpu_window_directive(tmp_path)
    assert r["fichiers_examines"] == 3
    assert r["fichiers_avec_directive"] == 1
    assert r["fichiers_not_measured"] == ["b.gd"]
    assert r["fichiers_en_defaut"] == ["c.gd"]


def test_sur_le_depot_REEL_pacman_n_a_aucun_volet_lance():
    """Cas reel : les 104 `.gd` de pacman sont des sous-modules. Ses six « defauts »
    portaient sur des fichiers que le collecteur ne lance jamais."""
    d = REPO / "GAMES/pacman/07_TESTS/oracle"
    if not d.is_dir():
        pytest.skip("jeu pacman absent du depot")
    r = check_gpu_window_directive(d)
    assert r["fichiers_examines"] == 0
    assert len(r["sous_modules_ignores"]) > 100
    assert r["passed"] is True


def test_sur_le_depot_REEL_bomberman_garde_son_defaut():
    """Contre-epreuve : la restriction ne blanchit pas un defaut REEL. `core_audio.gd`
    de bomberman_3d EST un volet lance, et il reste en defaut."""
    d = REPO / "GAMES/bomberman_3d/07_TESTS/oracle"
    if not d.is_dir():
        pytest.skip("fixture bomberman_3d absente du depot")
    r = check_gpu_window_directive(d)
    assert r["passed"] is False
    assert "core_audio.gd" in r["fichiers_en_defaut"]

# P0-4, raffinement 2026-08-16 (GO Pierre) — l'oracle discrimine TROIS etats.
#
# Defaut mesure : `check_gpu_window_directive` confondait « exigence GPU non satisfaite »
# et « preuve volontairement NON MESUREE, avec raison structuree ». Consequence reelle :
# `GAMES/tetris/07_TESTS/oracle/core_render.gd` — SEUL volet du depot a porter le
# marqueur `requires_gpu_window`, avec une justification exemplaire — etait signale EN
# DEFAUT. L'oracle recalait le volet le plus rigoureux du depot.
#
# Contre-exemple qui rend la confusion FORMELLE : `pacman/v2_core_render.gd` asserte
# `mesurees == 0, "core.render: aucune capture mesuree sans fenetre GPU"`. Lui poser la
# directive le ferait tourner EN fenetre GPU et CASSERAIT son contrat. « Reparer » selon
# l'ancienne regle aurait donc detruit un test correct.
#
# AUCUNE CLE INVENTEE : `_GPU_WINDOW_MARKER_KEY` est deja la cle par laquelle le
# collecteur (product_oracle_godot) rend NOT_MEASURED motive. L'oracle cesse simplement
# de l'ignorer.
from __future__ import annotations

from pathlib import Path

import pytest

from forge.product_oracle_godot import _GPU_WINDOW_MARKER_KEY, _ORACLE_MARKER
from forge.standard_oracles import check_gpu_window_directive

REPO = Path(__file__).resolve().parents[2]

PROSE = "# Ce volet exige une fenetre GPU reelle pour prouver le rendu.\n"

# FIXTURES RENDUES FIDELES (2026-08-16, restriction de perimetre). Ces fixtures
# ecrivaient des `.gd` SANS le marqueur `FORGE_ORACLE` tout en se nommant « volet » et en
# asserttant des regles qui ne valent QUE pour un volet lance. Elles passaient parce que
# l'oracle partageait leur erreur de perimetre : il jugeait des fichiers que le collecteur
# ne lance pas. Le referent reel de ces cas — `GAMES/tetris/07_TESTS/oracle/core_render.gd`
# — porte bien le marqueur (mesure : 2 occurrences). La fixture est donc alignee sur son
# referent, pas l'inverse : on ne relache aucune assertion, on cesse de mentir sur l'objet.
_EMISSION = f'\nfunc run():\n\tprint("{_ORACLE_MARKER} nom " + "{{}}")\n'


def _volet(dossier: Path, nom: str, corps: str) -> Path:
    """Un volet REELLEMENT lance : le marqueur d'emission est ajoute a chaque fixture,
    car c'est lui — et lui seul — qui fait qu'un `.gd` est collecte."""
    dossier.mkdir(parents=True, exist_ok=True)
    p = dossier / nom
    p.write_text(corps + _EMISSION, encoding="utf-8")
    return p


def test_prose_seule_reste_un_defaut(tmp_path):
    """L'invariant d'origine ne bouge pas : une exigence en prose, sans rien de
    structure, reste un defaut."""
    _volet(tmp_path, "core_render_frame.gd", PROSE + "func test_x():\n\tpass\n")
    r = check_gpu_window_directive(tmp_path)
    assert r["passed"] is False
    assert r["verdict"] == "BLOCKED"
    assert r["fichiers_en_defaut"] == ["core_render_frame.gd"]


def test_directive_structuree_passe(tmp_path):
    _volet(tmp_path, "core_render_frame.gd",
           PROSE + "# forge:run_mode = gpu_window\nfunc test_x():\n\tpass\n")
    r = check_gpu_window_directive(tmp_path)
    assert r["passed"] is True
    assert r["fichiers_avec_directive"] == 1


def test_renoncement_structure_est_ACCEPTE(tmp_path):
    """LE CAS DU RAFFINEMENT : un volet qui declare LUI-MEME, en champ structure, ne pas
    pouvoir mesurer la preuve pixel n'est PAS en defaut. NOT_MEASURED motive est un etat
    a part entiere, ni FAIL ni PASS."""
    _volet(tmp_path, "core_render.gd",
           PROSE + 'func test_x():\n\tprint(JSON.stringify({"ok": false, '
                   f'"{_GPU_WINDOW_MARKER_KEY}": true}}))\n')
    r = check_gpu_window_directive(tmp_path)
    assert r["passed"] is True
    assert r["fichiers_en_defaut"] == []
    assert r["fichiers_not_measured"] == ["core_render.gd"]


def test_les_trois_etats_sont_DISTINCTS(tmp_path):
    """Les trois compteurs ne se recouvrent pas : un volet appartient a un seul etat."""
    _volet(tmp_path, "a_directive.gd", PROSE + "# forge:run_mode = gpu_window\n")
    _volet(tmp_path, "b_not_measured.gd", PROSE + f'"{_GPU_WINDOW_MARKER_KEY}": true\n')
    _volet(tmp_path, "c_defaut.gd", PROSE)
    r = check_gpu_window_directive(tmp_path)
    assert r["fichiers_examines"] == 3
    assert r["fichiers_avec_directive"] == 1
    assert r["fichiers_not_measured"] == ["b_not_measured.gd"]
    assert r["fichiers_en_defaut"] == ["c_defaut.gd"]
    assert r["passed"] is False, "un defaut reel doit toujours bloquer"


def test_la_directive_PRIME_sur_le_renoncement(tmp_path):
    """Un volet qui porte les DEUX est route en fenetre GPU : le routage decide, le
    renoncement n'est qu'un repli. Sinon un volet mesurable serait classe non mesure."""
    _volet(tmp_path, "core_render.gd",
           PROSE + "# forge:run_mode = gpu_window\n"
                   f'"{_GPU_WINDOW_MARKER_KEY}": true\n')
    r = check_gpu_window_directive(tmp_path)
    assert r["fichiers_avec_directive"] == 1
    assert r["fichiers_not_measured"] == []


def test_sur_l_artefact_REEL_tetris_cesse_d_etre_un_defaut():
    """Cas REEL, pas une fixture : le volet Tetris porte le marqueur et etait signale en
    defaut avant ce raffinement.

    CONDITIONNEL, et la raison compte. `GAMES/tetris/07_TESTS/oracle/core_render.gd`
    n'est PAS commite au 2026-08-16 (HEAD n'a qu'un fichier dans ce repertoire, le
    working tree en a neuf). Asserter dessus sans condition rendait ce test VERT dans le
    working tree et ROUGE sur l'etat commite — mesure par validation isolee. Un test qui
    depend d'un artefact non versionne ne mesure pas le depot, il mesure un poste.
    On SAUTE donc explicitement, avec le motif : mieux vaut un saut nomme qu'un vert
    trompeur ou un rouge d'environnement. Quand le volet Tetris entrera au depot, ce test
    couvrira le cas reel SANS modification — c'est pour cela qu'il est conserve."""
    volet = REPO / "GAMES/tetris/07_TESTS/oracle/core_render.gd"
    if not volet.is_file():
        pytest.skip("volet Tetris core_render.gd absent du depot — cas reel non couvrable ici")
    r = check_gpu_window_directive(volet.parent)
    assert "core_render.gd" not in r["fichiers_en_defaut"]
    assert "core_render.gd" in r["fichiers_not_measured"]
    assert r["passed"] is True, "la boucle produit de Tetris se ferme sans toucher au volet"

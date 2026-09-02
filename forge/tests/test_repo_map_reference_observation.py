# Categorie `reference.observation` de repo_map.yaml — gate Pierre 2026-08-10.
#
# Dette de preuve fermee ici. Le dossier d'observation amont (`GAME_REFERENCE/`, produit
# AVANT le jeu par le World Scan) n'avait aucune identite architecturale : il remontait en
# `dossiers_hors_structure` et faisait ECHOUER check_index. Mesure du 2026-08-16 sur le
# jeu reel `GAMES/tetris` (6 fichiers, tous commites) :
#     table sans la categorie -> passed=False, hors_structure=['GAME_REFERENCE']
#     table avec la categorie -> passed=True,  hors_structure=[]
# La reparation par DEPLACEMENT du dossier avait ete ECARTEE apres verification : son
# contenu differe de EVIDENCE/runs/tetris/GAME_REFERENCE/ sur 6 fichiers sur 6 — ce
# n'est pas un doublon, et deplacer « pour faire passer l'oracle » aurait detruit de
# l'information. On donne une identite a l'emplacement au lieu de le faire disparaitre.
#
# Ces tests portent sur ce que la table PROMET et sur l'effet MESURE, jamais sur une
# intention supposee.
from __future__ import annotations

from pathlib import Path

import yaml

from forge.standard_oracles import check_index

STANDARD_DIR = Path(__file__).resolve().parents[1] / "standard"


def _real_repo_map() -> dict:
    return yaml.safe_load(STANDARD_DIR.joinpath("repo_map.yaml").read_text(encoding="utf-8"))


def _write(root: Path, rel: str, content: str = "x\n") -> None:
    p = root / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(content, encoding="utf-8")


def _wiremap() -> dict:
    return {"lines": [
        {"id": "game_loop", "fichiers": ["05_SYSTEMS/game_loop/loop.mjs"],
         "address": "05_SYSTEMS/game_loop/"},
    ]}


def test_la_table_declare_la_categorie():
    mapping = _real_repo_map()["mapping"]
    assert mapping.get("reference.observation") == "GAME_REFERENCE/"


def test_dossier_d_observation_devient_LEGAL(tmp_path):
    """L'effet mesure : avec la table REELLE, un jeu qui porte GAME_REFERENCE/ passe."""
    _write(tmp_path, "05_SYSTEMS/game_loop/loop.mjs", "export function tick() {}\n")
    _write(tmp_path, "GAME_REFERENCE/tetris_nes.md", "# reference\n")
    rep = check_index(_wiremap(), tmp_path, repo_map=_real_repo_map())
    assert rep["dossiers_hors_structure"] == []


def test_SANS_la_categorie_le_dossier_est_hors_structure(tmp_path):
    """Falsification interne : la meme arborescence, une table PRIVEE de la categorie —
    le dossier redevient une violation. C'est la categorie qui le rend legal, pas un
    hasard d'exemption."""
    _write(tmp_path, "05_SYSTEMS/game_loop/loop.mjs", "export function tick() {}\n")
    _write(tmp_path, "GAME_REFERENCE/tetris_nes.md", "# reference\n")
    table = _real_repo_map()
    table["mapping"].pop("reference.observation", None)
    rep = check_index(_wiremap(), tmp_path, repo_map=table)
    assert rep["passed"] is False
    assert "GAME_REFERENCE" in rep["dossiers_hors_structure"]


def test_un_dossier_INCONNU_reste_une_violation(tmp_path):
    """La categorie legalise `GAME_REFERENCE/`, elle n'ouvre pas la structure : un
    dossier hors table reste refuse. Sinon on aurait echange un faux rouge contre un
    faux vert."""
    _write(tmp_path, "05_SYSTEMS/game_loop/loop.mjs", "export function tick() {}\n")
    _write(tmp_path, "GAME_REFERENCE/ref.md", "# reference\n")
    _write(tmp_path, "src/rogue.mjs", "export function rogue() {}\n")
    rep = check_index(_wiremap(), tmp_path, repo_map=_real_repo_map())
    assert rep["passed"] is False
    assert rep["dossiers_hors_structure"] == ["src"]


def test_gabarit_de_DOSSIER_donc_hors_scope_de_la_regle_d_identite():
    """Forme volontaire : dossier fixe, sans `{id}`. L'obligation d'identite a pour
    portee `test.*` et `asset.*` uniquement — cette categorie n'y entre pas, et ne
    change donc pas le compte fige par
    test_repo_map_reel_tous_les_gabarits_test_et_asset_portent_un_id."""
    mapping = _real_repo_map()["mapping"]
    gabarit = mapping["reference.observation"]
    assert gabarit.endswith("/")
    assert "{id}" not in gabarit
    en_scope = [c for c in mapping if c.startswith(("test.", "asset."))]
    assert "reference.observation" not in en_scope

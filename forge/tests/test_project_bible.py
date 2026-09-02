"""Project Bible — mémoire de DÉCISION par projet, lue en s0, écrite en propose-only.

Ferme le trou « chaque run reconstruit sa vision » (audit cognitif 2026-07-14, levier L2) :
la bible d'un projet persiste ENTRE les runs et est injectée au cadrage (s0-contrat).
Gouvernance : un agent PROPOSE (propose_bible_entry) ; Pierre ratifie (édite le .md).
"""
import json
from pathlib import Path

import pytest

from forge import studio_link as sl


def test_project_bible_lit_le_fichier_quand_present(tmp_path):
    runs = tmp_path / "forge_runs"
    (runs / "shmup").mkdir(parents=True)
    (runs / "shmup" / "PROJECT_BIBLE.md").write_text(
        "# PROJECT BIBLE — shmup\n## 2. Piliers\n- lisibilité des projectiles\n",
        encoding="utf-8",
    )
    txt = sl.project_bible("shmup", runs_root=runs)
    assert "lisibilité des projectiles" in txt


def test_project_bible_absente_retourne_vide_sans_exception(tmp_path):
    runs = tmp_path / "forge_runs"
    runs.mkdir()
    # projet neuf : aucune bible — "" et surtout PAS de crash (précondition douce de s0)
    assert sl.project_bible("jamais_forge", runs_root=runs) == ""


def test_propose_bible_entry_depose_une_proposition_validated(tmp_path):
    p = tmp_path / "bible_prop.jsonl"
    rec = sl.propose_bible_entry(
        "shmup", "validated", "canvas-only pour les assets",
        "aucun générateur câblé, voie prouvée", proposals_path=p,
    )
    assert rec["status"] == "PROPOSED"
    assert rec["kind"] == "validated"
    on_disk = json.loads(p.read_text(encoding="utf-8").strip())
    assert on_disk["project"] == "shmup"
    assert on_disk["decision"] == "canvas-only pour les assets"
    assert on_disk["rationale"]


def test_propose_bible_entry_capture_une_voie_abandonnee(tmp_path):
    """La mémoire la plus précieuse : une voie écartée + sa raison, pour ne pas la re-proposer."""
    p = tmp_path / "bible_prop.jsonl"
    sl.propose_bible_entry(
        "shmup", "abandoned", "ingestion d'assets réseau au run",
        "gate Pierre requise, hors scope du slice", proposals_path=p,
    )
    on_disk = json.loads(p.read_text(encoding="utf-8").strip())
    assert on_disk["kind"] == "abandoned"
    assert "gate Pierre" in on_disk["rationale"]


def test_propose_bible_entry_rejette_un_kind_invalide(tmp_path):
    p = tmp_path / "bible_prop.jsonl"
    with pytest.raises(ValueError):
        sl.propose_bible_entry("shmup", "peut-être", "x", "y", proposals_path=p)
    assert not p.exists()  # rien déposé sur un kind refusé


def test_propose_bible_entry_est_propose_only(tmp_path):
    """Le canal n'écrit que la proposition — jamais la bible de référence elle-même."""
    runs = tmp_path / "forge_runs"
    (runs / "shmup").mkdir(parents=True)
    p = tmp_path / "bible_prop.jsonl"
    sl.propose_bible_entry("shmup", "validated", "d", "r", proposals_path=p)
    # la bible de référence n'a PAS été créée par la proposition
    assert not (runs / "shmup" / "PROJECT_BIBLE.md").exists()
    assert p.exists()

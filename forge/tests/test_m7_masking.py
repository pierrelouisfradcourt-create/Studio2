"""RUN 2 V1 — point A2 (docs/forge/RUN2_PROTOCOLE_V1_PROPOSED.md). Masquage V2
par BLOCS STRUCTURÉS, jamais par mot interdit ligne-à-ligne. Le test central
(`test_gain_clic_line_survives_masking`) est la non-régression obligatoire du
bug du pilote : une ligne à valeur de gameplay qui vit dans un bloc de
contenu normal doit SURVIVRE, là où le masquage V1 (mots-interdits) l'avait
tuée parce qu'un mot de la ligne matchait accidentellement la liste noire de
provenance."""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT))

from forge import m7_masking  # noqa: E402
from forge.m7_masking import is_gameplay_value_line, mask_document, verify_masking  # noqa: E402


DOC = """# Charter Kitten Clicker

## Provenance

Source : run pilote 2026-08-30, généré par gm_worldscan.
Auteur original : bras L1.

## Design

gain_clic: 1  # valeur de base du clic (structure imposée)
cout_amelioration: 10
tick_rate: 0.5

## Meta expérimentale

Protocole de pré-enregistrement, cf. documentation associée du sas.
Date : 2026-08-30.
"""


def test_gain_clic_line_survives_masking():
    """LE test central : la ligne gain_clic vit dans le bloc ## Design, jamais
    strippé -- elle doit rester identique dans le document masqué."""
    masked, report = mask_document(DOC, blocks_to_strip=["Provenance", "Meta"])

    assert "gain_clic: 1  # valeur de base du clic (structure imposée)" in masked
    assert "cout_amelioration: 10" in masked
    assert "tick_rate: 0.5" in masked

    verify = verify_masking(DOC, masked, report["exceptions"])
    assert verify["ok"] is True, verify["violations"]


def test_provenance_block_stripped_and_reported():
    masked, report = mask_document(DOC, blocks_to_strip=["Provenance", "Meta"])

    assert "run pilote 2026-08-30" not in masked
    assert "bras L1" not in masked
    assert "Protocole RUN2 V1" not in masked

    headings = {b["heading"] for b in report["stripped_blocks"]}
    assert "Provenance" in headings
    assert "Meta expérimentale" in headings


def test_verify_masking_flags_violation_when_value_line_disappears_without_exception():
    """Simule un masquage BUGUÉ qui aurait, par erreur, aussi retiré la ligne
    gain_clic (ex. une regex de bloc trop large) : verify_masking doit
    détecter la perte, sans exception déclarée."""
    buggy_masked = DOC.replace("gain_clic: 1  # valeur de base du clic (structure imposée)\n", "")

    verify = verify_masking(DOC, buggy_masked, exceptions=[])
    assert verify["ok"] is False
    lost = [v["line"] for v in verify["violations"]]
    assert any("gain_clic" in ln for ln in lost)


def test_verify_masking_accepts_justified_exception():
    """Un bloc de calibration en clair, explicitement listé avec justification,
    peut légitimement retirer une ligne à valeur -- verify_masking l'accepte
    SEULEMENT si la justification est non vide."""
    doc_with_calibration = DOC + "\n## Calibration interne\n\nvaleur_test_debug: 42\n"

    masked, report = mask_document(
        doc_with_calibration,
        blocks_to_strip=[
            "Provenance",
            "Meta",
            {"pattern": "Calibration", "justification": "bloc de calibration interne, jamais lu par les bras — retrait volontaire ratifié"},
        ],
    )

    assert "valeur_test_debug: 42" not in masked
    exc_headings = {e["heading"] for e in report["exceptions"]}
    assert "Calibration interne" in exc_headings

    verify = verify_masking(doc_with_calibration, masked, report["exceptions"])
    assert verify["ok"] is True, verify["violations"]


def test_exception_without_justification_does_not_excuse_violation():
    """Une exception SANS justification (None/vide) ne couvre RIEN -- fail
    closed : mieux vaut un faux FAIL qu'un vrai masquage silencieux."""
    doc_with_calibration = DOC + "\n## Calibration interne\n\nvaleur_test_debug: 42\n"

    masked, report = mask_document(
        doc_with_calibration,
        blocks_to_strip=["Provenance", "Meta", {"pattern": "Calibration", "justification": ""}],
    )

    verify = verify_masking(doc_with_calibration, masked, report["exceptions"])
    assert verify["ok"] is False
    assert any("valeur_test_debug" in v["line"] for v in verify["violations"])


def test_is_gameplay_value_line_heuristic():
    assert is_gameplay_value_line("gain_clic: 1  # valeur de base du clic") is True
    assert is_gameplay_value_line("cout_amelioration: 10") is True

    # ancres pures -- ne comptent pas comme valeur de gameplay
    assert is_gameplay_value_line("Date : 2026-08-30 · Statut : PROPOSED") is False
    assert is_gameplay_value_line("12. Point de la checklist") is False
    assert is_gameplay_value_line("cf. IMP-234 pour le contexte") is False
    assert is_gameplay_value_line("## 3. Titre de section numéroté") is False
    assert is_gameplay_value_line("commit 6e5e7da appliqué") is False

    # "L1" est traitée comme une ancre de référence (pas une valeur de gameplay)
    assert is_gameplay_value_line("Auteur original : bras L1") is False


def test_v1_bug_non_regression_word_match_inside_kept_block_never_strips_line():
    """Reproduit le bug V1 : une ligne dans un bloc ## Design contient le mot
    'provenance' au milieu d'un commentaire -- le V1 ligne-à-mots l'aurait
    tuée par simple présence du mot interdit. Le V2, structuré par bloc, ne
    regarde JAMAIS le contenu des lignes d'un bloc non strippé."""
    doc = (
        "# Charter\n\n"
        "## Design\n\n"
        "gain_clic: 1  # provenance historique de cette formule (structure imposée)\n"
        "cout_amelioration: 10\n"
    )
    masked, report = mask_document(doc, blocks_to_strip=["Provenance"])

    assert "gain_clic: 1  # provenance historique de cette formule (structure imposée)" in masked
    verify = verify_masking(doc, masked, report["exceptions"])
    assert verify["ok"] is True, verify["violations"]


def test_cli_writes_output_and_exits_zero_on_clean_masking(tmp_path):
    in_path = tmp_path / "charter.md"
    out_path = tmp_path / "charter.masked.md"
    in_path.write_text(DOC, encoding="utf-8")

    rc = m7_masking._main([str(in_path), str(out_path), "--strip", "Provenance,Meta"])

    assert rc == 0
    assert out_path.exists()
    masked_text = out_path.read_text(encoding="utf-8")
    assert "gain_clic: 1  # valeur de base du clic (structure imposée)" in masked_text
    assert "run pilote 2026-08-30" not in masked_text


def test_cli_exits_nonzero_and_does_not_write_when_verify_fails(tmp_path, monkeypatch):
    """Force un mask_document dont le report d'exceptions est vidé après coup
    pour simuler un verify qui échoue -- via un motif de strip trop large qui
    avale le bloc Design entier (aucune justification fournie)."""
    in_path = tmp_path / "charter.md"
    out_path = tmp_path / "charter.masked.md"
    in_path.write_text(DOC, encoding="utf-8")

    # motif "Design" strippe le bloc porteur de gain_clic SANS justification -> doit refuser
    rc = m7_masking._main([str(in_path), str(out_path), "--strip", "Provenance,Meta,Design"])

    assert rc == 1
    assert not out_path.exists()


def test_cli_requires_two_positional_paths():
    proc = subprocess.run(
        [sys.executable, "-m", "forge.m7_masking"],
        cwd=str(REPO_ROOT),
        env={**__import__("os").environ, "PYTHONPATH": str(REPO_ROOT)},
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert proc.returncode != 0

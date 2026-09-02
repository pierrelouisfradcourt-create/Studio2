"""Oracle du refactor « journal d'erreurs par domaine » (connecteur 6).

Le journal monolithe PILOU devient des journaux PAR DOMAINE + un index + le scope
global. But : éviter qu'un agent lise un monolithe indifférencié et tire une leçon
hors-sujet (un run rust ne doit pas hériter des leçons d'un jeu html).

Fichier NOUVEAU : ne touche à aucun test existant. Tout est isolé sous tmp_path via
`reports_dir` / `journal_path`. claim_verdict: NO_CLAIM_ALLOWED.
"""
from __future__ import annotations

import json
from pathlib import Path

from forge import studio_link as sl


def _rows(path: Path) -> list[dict]:
    if not path.exists():
        return []
    return [json.loads(l) for l in path.read_text(encoding="utf-8").splitlines() if l.strip()]


def _journal(reports_dir: Path, domaine: str) -> Path:
    return reports_dir / "error_journal" / f"{domaine}.jsonl"


def test_record_error_routes_by_domain(tmp_path, monkeypatch):
    """record_error(domain="rust") écrit dans le fichier rust, PAS ailleurs."""
    monkeypatch.setattr(sl, "DOMAIN_JOURNAL_DIR", tmp_path / "error_journal")
    sl.record_error("r1", "s4-archi", "unwrap() sans SAFETY", project="rocky", domain="rust")

    rust = tmp_path / "error_journal" / "rust.jsonl"
    rows = _rows(rust)
    assert len(rows) == 1
    assert rows[0]["error"] == "unwrap() sans SAFETY"
    assert rows[0]["project"] == "rocky"
    # aucun autre journal de domaine n'a été créé
    for autre in ("python", "html", "godot", "forge", "_global_"):
        assert not (tmp_path / "error_journal" / f"{autre}.jsonl").exists()


def test_record_fix_routes_by_domain(tmp_path, monkeypatch):
    """record_fix(domain="godot") écrit une entrée fixed dans le fichier godot."""
    monkeypatch.setattr(sl, "DOMAIN_JOURNAL_DIR", tmp_path / "error_journal")
    sl.record_fix("r1", "s9-build", "signal non connecté", "connecté via @onready",
                  project="jeu_godot", domain="godot")
    rows = _rows(tmp_path / "error_journal" / "godot.jsonl")
    assert len(rows) == 1
    assert rows[0]["status"] == "fixed"
    assert rows[0]["resolution"] == "connecté via @onready"


def test_premortem_domain_reads_domain_plus_global_not_others(tmp_path, monkeypatch):
    """premortem(domain="rust") lit rust + _global_, PAS python."""
    monkeypatch.setattr(sl, "DOMAIN_JOURNAL_DIR", tmp_path / "error_journal")
    # legacy monolithe isolé et vide, pour ne pas polluer (fallback rust = jamais lu)
    monkeypatch.setattr(sl, "DEFAULT_ERROR_JOURNAL", tmp_path / "monolithe_absent.jsonl")

    sl.record_error("r1", "s4-archi", "bug rust spécifique", project="rocky", domain="rust")
    sl.record_error("r2", "s9-build", "bug python spécifique", project="ml", domain="python")
    sl.record_global_lesson("s10a", "oracle doit tester la solvabilité")

    pm = sl.premortem("rocky", domain="rust")
    assert any("bug rust spécifique" in x for x in pm)
    assert any("solvabilité" in x for x in pm)          # leçon globale présente
    assert not any("bug python spécifique" in x for x in pm)  # domaine python filtré


def test_global_lesson_appears_for_any_domain(tmp_path, monkeypatch):
    """Une leçon _global_ apparaît quel que soit le domaine demandé (préfixe ⚑)."""
    monkeypatch.setattr(sl, "DOMAIN_JOURNAL_DIR", tmp_path / "error_journal")
    monkeypatch.setattr(sl, "DEFAULT_ERROR_JOURNAL", tmp_path / "monolithe_absent.jsonl")
    sl.record_global_lesson("s12", "toujours passer evidence_path")

    for domaine in ("rust", "python", "html", "godot", "forge"):
        pm = sl.premortem("un_projet", domain=domaine)
        ligne = next((x for x in pm if "evidence_path" in x), None)
        assert ligne is not None, f"leçon globale absente pour domaine {domaine}"
        assert ligne.startswith("⚑ ")


def test_global_lesson_present_even_without_domain(tmp_path, monkeypatch):
    """Sans domaine précisé, les leçons globales restent surfacées."""
    monkeypatch.setattr(sl, "DOMAIN_JOURNAL_DIR", tmp_path / "error_journal")
    monkeypatch.setattr(sl, "DEFAULT_ERROR_JOURNAL", tmp_path / "monolithe_absent.jsonl")
    sl.record_global_lesson("s10a", "jamais de >= tautologique")
    pm = sl.premortem("un_projet")  # domain=None
    assert any("tautologique" in x for x in pm)


def test_journal_path_explicit_is_backward_compatible(tmp_path):
    """Rétrocompat : un appel avec journal_path= explicite se comporte comme avant.

    Écriture ET lecture ciblent CE fichier unique (projet + global dedans), le routage
    par domaine est ignoré — les tests historiques passant journal_path= restent verts.
    """
    j = tmp_path / "legacy.jsonl"
    sl.record_error("r1", "s9-build", "erreur projet", project="leviathan", journal_path=j)
    sl.record_error("_method_", "s10a", "leçon globale héritée",
                    project=sl.GLOBAL_SCOPE, journal_path=j)
    # tout est allé dans le fichier explicite, pas dans un journal de domaine
    assert len(_rows(j)) == 2
    pm = sl.premortem("leviathan", journal_path=j)
    assert any("erreur projet" in x for x in pm)
    assert any("leçon globale héritée" in x for x in pm)


def test_premortem_legacy_fallback_for_html_domain(tmp_path, monkeypatch):
    """NON-DESTRUCTIF : le monolithe historique est relu en fallback pour html/forge."""
    monkeypatch.setattr(sl, "DOMAIN_JOURNAL_DIR", tmp_path / "error_journal")
    legacy = tmp_path / "forge_error_journal.jsonl"
    monkeypatch.setattr(sl, "DEFAULT_ERROR_JOURNAL", legacy)
    # entrée réelle « historique » d'un jeu html, écrite au format monolithe
    legacy.write_text(json.dumps(
        {"run_id": "collect_runner-1", "etape": "s10a", "project": "collect_runner",
         "error": "jeu injouable alors qu'oracle vert", "resolution": None,
         "status": "open", "ts": 1.0}, ensure_ascii=False) + "\n", encoding="utf-8")

    # domaine html → le fallback ramène la leçon historique
    pm_html = sl.premortem("collect_runner", domain="html")
    assert any("injouable" in x for x in pm_html)
    # domaine rust → pas de fallback : la leçon html ne pollue PAS un run rust
    pm_rust = sl.premortem("collect_runner", domain="rust")
    assert not any("injouable" in x for x in pm_rust)


def test_list_journals_counts_entries_per_domain(tmp_path, monkeypatch):
    """list_journals compte correctement les entrées par domaine."""
    monkeypatch.setattr(sl, "DOMAIN_JOURNAL_DIR", tmp_path / "error_journal")
    sl.record_error("r1", "s4", "e1", project="a", domain="rust")
    sl.record_error("r2", "s4", "e2", project="b", domain="rust")
    sl.record_error("r3", "s9", "e3", project="c", domain="python")

    idx = {j["domaine"]: j for j in sl.list_journals(reports_dir=tmp_path)}
    assert idx["rust"]["entries"] == 2
    assert idx["rust"]["existe"] is True
    assert idx["python"]["entries"] == 1
    # domaine connu mais jamais écrit : 0 entrée, n'existe pas
    assert idx["godot"]["entries"] == 0
    assert idx["godot"]["existe"] is False
    # tous les domaines connus sont recensés
    for domaine in sl.KNOWN_DOMAINS:
        assert domaine in idx


def test_generate_journal_index_is_deterministic(tmp_path, monkeypatch):
    """L'index Markdown est déterministe (aucun horodatage) : deux rendus identiques."""
    monkeypatch.setattr(sl, "DOMAIN_JOURNAL_DIR", tmp_path / "error_journal")
    sl.record_error("r1", "s4", "e1", project="a", domain="rust")
    md1 = sl.generate_journal_index(reports_dir=tmp_path)
    md2 = sl.generate_journal_index(reports_dir=tmp_path)
    assert md1 == md2
    assert "rust" in md1
    assert "| domaine |" in md1


def test_write_journal_index_writes_file(tmp_path, monkeypatch):
    """write_journal_index écrit error_journal/INDEX.generated.md."""
    monkeypatch.setattr(sl, "DOMAIN_JOURNAL_DIR", tmp_path / "error_journal")
    sl.record_error("r1", "s4", "e1", project="a", domain="html")
    path = sl.write_journal_index(reports_dir=tmp_path)
    assert path.exists()
    assert path.name == "INDEX.generated.md"
    assert "html" in path.read_text(encoding="utf-8")

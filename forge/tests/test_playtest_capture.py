"""Oracle capture playtest -> canal pré-mortem (R2, FORGE_V2_CONSOLIDATION.md §4-A).

Avant R2, un retour de playtest Pierre était une conversation qui s'évaporait (0
fichier, jamais consigné — constat P6). `record_playtest` route ce type de
connaissance vers error_journal(domain=playtest), et `premortem` doit le resservir
au run SUIVANT — quel que soit le domaine (html/forge/rust/godot) demandé par ce
run, sinon la capture reste filtrée hors de vue et le retour s'évapore quand même.
Isolé sous tmp_path (DOMAIN_JOURNAL_DIR/DEFAULT_ERROR_JOURNAL monkeypatchés), aucun
test existant touché. NO_CLAIM_ALLOWED.
"""
from __future__ import annotations

import json
from pathlib import Path

from forge import studio_link as sl


def _rows(path: Path) -> list[dict]:
    if not path.exists():
        return []
    return [json.loads(l) for l in path.read_text(encoding="utf-8").splitlines() if l.strip()]


def test_record_playtest_routes_to_playtest_domain(tmp_path, monkeypatch):
    monkeypatch.setattr(sl, "DOMAIN_JOURNAL_DIR", tmp_path / "error_journal")
    sl.record_playtest("leviathan", "0 or au démarrage, combat jamais lancé",
                       "la préparation doit garantir au moins 1 unité posable au round 1")

    playtest = tmp_path / "error_journal" / "playtest.jsonl"
    rows = _rows(playtest)
    assert len(rows) == 1
    assert rows[0]["project"] == "leviathan"
    assert rows[0]["error"] == "0 or au démarrage, combat jamais lancé"
    assert rows[0]["resolution"] == "la préparation doit garantir au moins 1 unité posable au round 1"
    assert rows[0]["status"] == "fixed"  # même mécanisme que record_fix (2e colonne renseignée)


def test_premortem_serves_playtest_regardless_of_requested_domain(tmp_path, monkeypatch):
    """Le point central de R2 : un run 'rust' (domaine différent) voit quand même
    le retour de playtest du même projet — sinon il s'évapore silencieusement."""
    monkeypatch.setattr(sl, "DOMAIN_JOURNAL_DIR", tmp_path / "error_journal")
    monkeypatch.setattr(sl, "DEFAULT_ERROR_JOURNAL", tmp_path / "monolithe_absent.jsonl")

    sl.record_playtest("rocky", "shuffle en ouverture au lieu de développer",
                       "ne jamais jouer un coup de bord en ouverture sans raison tactique")

    pm_rust = sl.premortem("rocky", domain="rust")
    assert any("shuffle" in x for x in pm_rust)
    assert any("RÉPARÉ" in x and "bord en ouverture" in x for x in pm_rust)

    pm_none = sl.premortem("rocky")  # domain=None
    assert any("shuffle" in x for x in pm_none)


def test_premortem_playtest_not_duplicated_when_domain_is_playtest(tmp_path, monkeypatch):
    monkeypatch.setattr(sl, "DOMAIN_JOURNAL_DIR", tmp_path / "error_journal")
    monkeypatch.setattr(sl, "DEFAULT_ERROR_JOURNAL", tmp_path / "monolithe_absent.jsonl")
    sl.record_playtest("jeu", "constat X", "règle Y")

    pm = sl.premortem("jeu", domain="playtest")
    occurrences = sum(1 for x in pm if "constat X" in x)
    assert occurrences == 1  # pas dupliqué (domain==PLAYTEST_DOMAIN -> pas de 2e lecture)


def test_premortem_playtest_filters_by_project(tmp_path, monkeypatch):
    monkeypatch.setattr(sl, "DOMAIN_JOURNAL_DIR", tmp_path / "error_journal")
    monkeypatch.setattr(sl, "DEFAULT_ERROR_JOURNAL", tmp_path / "monolithe_absent.jsonl")
    sl.record_playtest("jeu_a", "constat A", "règle A")
    sl.record_playtest("jeu_b", "constat B", "règle B")

    pm_a = sl.premortem("jeu_a", domain="godot")
    assert any("constat A" in x for x in pm_a)
    assert not any("constat B" in x for x in pm_a)


def test_playtest_visible_in_journal_index(tmp_path, monkeypatch):
    monkeypatch.setattr(sl, "DOMAIN_JOURNAL_DIR", tmp_path / "error_journal")
    sl.record_playtest("jeu", "constat", "règle")
    idx = {j["domaine"]: j for j in sl.list_journals(reports_dir=tmp_path)}
    assert idx["playtest"]["entries"] == 1
    assert idx["playtest"]["existe"] is True

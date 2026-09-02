"""Oracle P2 (lot dégel 2, docs/forge/FORGE_CONTEXT_COMPACT_V1.md §07) : le
pré-mortem d'un run JEU (`ForgeDriver._premortem`) lit AUSSI le journal
`playtest` (studio_link.PLAYTEST_DOMAIN), en plus du domaine `_domain()`
(figé "html" pour un jeu, d'avant Godot). ADDITIF pur : `_domain()` n'est PAS
modifié (l'écriture reste routée exactement comme avant) et `studio_link.py`
n'est pas touché — seul `driver._premortem()` concatène une lecture
supplémentaire, best-effort strict.

Isolation : `studio_link.DOMAIN_JOURNAL_DIR` est monkeypatché vers `tmp_path`
pour qu'aucun test n'écrive ni ne lise le corpus RÉEL du dépôt
(EVIDENCE/reports/error_journal/). Fichier NEUF (forge/tests/**, régime
studio normal) — n'altère aucun test existant. NO_CLAIM_ALLOWED.
"""
from __future__ import annotations

import pytest

from forge import studio_link
from forge.driver import ForgeDriver

PLAYTEST_TEXT = "bande de vitesse jouable — afficher un repère visuel"


@pytest.fixture
def isolated_domain_dir(tmp_path, monkeypatch):
    """Redirige error_journal/<domaine>.jsonl vers tmp_path — zéro écriture ni
    lecture du corpus réel du dépôt pendant ces tests."""
    domain_dir = tmp_path / "error_journal"
    monkeypatch.setattr(studio_link, "DOMAIN_JOURNAL_DIR", domain_dir)
    return domain_dir


def _driver(tmp_path, is_game):
    return ForgeDriver("snake", "snake-1", profile="micro",
                       run_dir=tmp_path / "run", is_game=is_game)


def test_un_jeu_recoit_la_lecon_playtest_dans_son_premortem(tmp_path, isolated_domain_dir):
    studio_link.record_playtest(
        "snake", "le joueur perd le fil sans indice de vitesse", PLAYTEST_TEXT,
    )
    d = _driver(tmp_path, is_game=True)
    lines = d._premortem()
    assert any(PLAYTEST_TEXT in l for l in lines)


def test_un_non_jeu_ne_recoit_pas_la_lecon_playtest(tmp_path, isolated_domain_dir):
    """`is_game=False` ne déclenche jamais la lecture additive playtest."""
    studio_link.record_playtest(
        "snake", "le joueur perd le fil sans indice de vitesse", PLAYTEST_TEXT,
    )
    d = _driver(tmp_path, is_game=False)
    lines = d._premortem()
    assert not any(PLAYTEST_TEXT in l for l in lines)


def test_domain_reste_html_pour_un_jeu_ecriture_inchangee(tmp_path, isolated_domain_dir):
    """Non-régression explicite : `_domain()` n'est PAS touché par ce lot."""
    d = _driver(tmp_path, is_game=True)
    assert d._domain() == "html"


def test_lecture_playtest_qui_leve_reste_silencieuse(tmp_path, isolated_domain_dir, monkeypatch):
    """Best-effort strict : une exception à la lecture playtest ne doit jamais
    se propager — le pré-mortem se dégrade en liste vide sur ce volet, jamais
    un crash du driver."""
    def _boom(project, domain=None, journal_path=None, limit=5):
        if domain == "playtest":
            raise RuntimeError("playtest KO (simulé)")
        return []

    monkeypatch.setattr("forge.driver.premortem", _boom)
    d = _driver(tmp_path, is_game=True)
    assert d._premortem() == []


def test_lecture_playtest_qui_leve_ne_touche_pas_un_non_jeu(tmp_path, isolated_domain_dir, monkeypatch):
    """Un non-jeu n'appelle jamais la branche playtest : une panne simulée sur
    ce seul domaine n'a donc aucun effet pour lui."""
    def _boom(project, domain=None, journal_path=None, limit=5):
        if domain == "playtest":
            raise RuntimeError("playtest KO (simulé) — ne doit jamais être atteint ici")
        return ["base"]

    monkeypatch.setattr("forge.driver.premortem", _boom)
    d = _driver(tmp_path, is_game=False)
    assert d._premortem() == ["base"]

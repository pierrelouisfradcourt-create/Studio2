"""Acceptation : la garde e2e reproduit le verdict de l'audit de re-forge —
legacy (avec e2e) verts, re-forges fraîches (sans e2e) rouges."""
from pathlib import Path

import pytest

from forge.static_oracles import check_e2e_harness

REPO_ROOT = Path(__file__).resolve().parents[2]
# Fixture V1 migrée le 2026-09-05 sous `EVIDENCE/_V1_FIXTURES/` (GO Pierre) : ces
# artefacts viennent de runs V1 jamais rejoués, ils ne sont PAS des preuves V2 et
# vivent donc à l'écart de `EVIDENCE/runs/`. Voir le README de ce dossier.
GAMES = REPO_ROOT / "EVIDENCE" / "_V1_FIXTURES" / "GAMES"


def test_sentinelle_jeux_reels_presents():
    # Anti-vacuité : si les jeux de référence disparaissent (renommage/purge), les
    # cas paramétrés ci-dessous se skippent silencieusement -> ce test échoue au lieu
    # de laisser la suite passer verte sans rien prouver.
    assert (GAMES / "collect_runner_legacy").exists(), "jeu de référence e2e absent"
    assert (GAMES / "collect_runner_r1").exists(), "re-forge de référence absente"


@pytest.mark.parametrize("jeu", ["collect_runner_legacy", "survival_arena_legacy"])
def test_legacy_avec_e2e_passe(jeu):
    if not (GAMES / jeu).exists():
        pytest.skip(f"{jeu} absent")
    res = check_e2e_harness(GAMES / jeu)
    assert res["passed"] is True, res["raisons"]


@pytest.mark.parametrize("jeu", ["collect_runner_r1", "collect_runner_r2", "survival_arena_r1"])
def test_reforge_sans_e2e_bloquee(jeu):
    if not (GAMES / jeu).exists():
        pytest.skip(f"{jeu} absent")
    res = check_e2e_harness(GAMES / jeu)
    assert res["passed"] is False
    assert res["raisons"]

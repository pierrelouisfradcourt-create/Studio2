# P1 2026-08-15 — troncature amont : le bloc ```json``` terminal doit SURVIVRE.
#
# Défaut mesuré (code review 2026-08-15) : `content[:UPSTREAM_MAX_CHARS]` gardait la
# TÊTE et détruisait la FIN — or les tâches exigent le bloc ```json``` EN FIN de
# réponse ("Termine ta réponse par UN bloc ```json```"). 5+ artefacts réels > 15k
# (s2-worldscan.txt jusqu'à 27 742 car.) étaient injectés en aval sans leur bloc.
# Correctif : _truncate_preserve_terminal_json (même convention "dernier bloc
# VALIDE" que extract_json_payload). Ce test fige les deux comportements :
# sous la borne rien ne change, au-dessus le bloc terminal valide est préservé.
from __future__ import annotations

import json

import pytest

from forge.run_real import (
    UPSTREAM_MAX_CHARS,
    _truncate_preserve_terminal_json,
    upstream_artifacts_section,
)


def _fence(obj: dict) -> str:
    return "```json\n" + json.dumps(obj) + "\n```"


def test_sous_la_borne_contenu_intact(tmp_path):
    # upstream_artifacts_section ne tronque pas un artefact sous la borne.
    (tmp_path / "artifacts").mkdir()
    petit = "narratif court\n" + _fence({"games": ["pong"]})
    (tmp_path / "artifacts" / "s2-worldscan.txt").write_text(petit, encoding="utf-8")
    section = upstream_artifacts_section("s1-prisme", tmp_path)
    assert petit in section
    assert "[tronqué]" not in section


def test_au_dessus_de_la_borne_le_bloc_terminal_survit():
    bloc = _fence({"games": [{"game": "tetris", "loops": {"minute_1": "poser"}}]})
    contenu = ("N" * (UPSTREAM_MAX_CHARS + 5000)) + "\n" + bloc
    coupe = _truncate_preserve_terminal_json(contenu)
    # bloc présent, parsable, et la sortie reste bornée (borne + bloc + marqueur).
    assert bloc in coupe
    assert "[tronqué]" in coupe
    assert len(coupe) <= UPSTREAM_MAX_CHARS + len("\n[tronqué]\n") + len(bloc)
    extrait = coupe.split("```json", 1)[1].rsplit("```", 1)[0]
    assert json.loads(extrait)["games"][0]["game"] == "tetris"


def test_le_narratif_est_tronque_pas_le_bloc():
    bloc = _fence({"k": "v"})
    contenu = ("A" * 20000) + "\nZONE_PERDUE\n" + ("B" * 20000) + "\n" + bloc
    coupe = _truncate_preserve_terminal_json(contenu)
    assert bloc in coupe
    assert coupe.startswith("A")            # tête narrative conservée
    assert "B" * 100 not in coupe            # milieu sacrifié, pas le bloc


def test_dernier_bloc_VALIDE_prime_sur_un_dernier_bloc_casse():
    # même convention que extract_json_payload : dernier bloc VALIDE.
    valide = _fence({"ok": True})
    casse = "```json\n{pas du json\n```"
    contenu = ("N" * 20000) + valide + "\n" + casse
    coupe = _truncate_preserve_terminal_json(contenu)
    assert valide in coupe


def test_sans_bloc_json_comportement_historique():
    contenu = "X" * 20000
    coupe = _truncate_preserve_terminal_json(contenu)
    assert coupe == "X" * UPSTREAM_MAX_CHARS + "\n[tronqué]"


def test_bloc_deja_dans_la_tete_comportement_historique():
    bloc = _fence({"tot": 1})
    contenu = bloc + "\n" + ("N" * 20000)
    coupe = _truncate_preserve_terminal_json(contenu)
    assert coupe.endswith("\n[tronqué]")
    assert bloc in coupe


def test_aucun_artefact_etranger(tmp_path):
    # la préservation n'introduit rien qui ne vienne pas du contenu source.
    bloc = _fence({"seul": "bloc"})
    contenu = ("N" * 20000) + "\n" + bloc
    coupe = _truncate_preserve_terminal_json(contenu)
    residu = coupe.replace("\n[tronqué]\n", "")
    assert residu == contenu[: len(residu) - len(bloc)] + bloc

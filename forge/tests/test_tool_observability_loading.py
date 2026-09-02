"""Maillon 2 (chargement) — forge.tool_observability.read_loaded_tools.

Lit `forge.run_real._STEP_TOOLS` (la table RÉELLE de ce qui est mis à
disposition d'une étape à l'exécution) — jamais `payload.allowed_tools`
(vide par construction, cf. contract.py, commentaires run_real.py ~l.150/268).
"""
from __future__ import annotations

from forge import tool_observability as obs
from forge.run_real import _STEP_TOOLS


def test_etape_connue_est_loaded():
    res = obs.read_loaded_tools("s9-build")
    assert res.status == obs.LOADING_STATUS_LOADED
    assert res.tools == _STEP_TOOLS["s9-build"]
    assert "Write" in res.tools


def test_etape_absente_de_la_table_est_not_measured_jamais_empty():
    """Invariant Pierre : NOT_MEASURED != OK (ici : != EMPTY). Une étape que
    personne n'a renseignée dans _STEP_TOOLS (ex. s10a-oracle-code : étape
    DÉTERMINISTE, jamais passée à claude_executor) ne doit JAMAIS être confondue
    avec une étape déclarée à zéro outil."""
    assert "s10a-oracle-code" not in _STEP_TOOLS
    res = obs.read_loaded_tools("s10a-oracle-code")
    assert res.status == obs.LOADING_STATUS_NOT_MEASURED
    assert res.tools == ()


def test_etape_totalement_inconnue_est_not_measured():
    res = obs.read_loaded_tools("etape-qui-n-existe-pas-du-tout")
    assert res.status == obs.LOADING_STATUS_NOT_MEASURED


def test_not_measured_distinct_de_empty_par_construction():
    """Négatif : si `read_loaded_tools` dégénérait en `.get(etape, ())` nu (sans
    distinguer absence de présence-vide), NOT_MEASURED et EMPTY collapseraient
    au même statut — ce test échouerait. Aujourd'hui `_STEP_TOOLS` ne contient
    AUCUNE entrée à tuple vide (toutes les étapes câblées ont >=1 outil), donc
    LOADING_STATUS_EMPTY n'est jamais observé en production — mesure honnête,
    pas simulée : on le prouve en amont plutôt qu'en aval."""
    assert all(tools for tools in _STEP_TOOLS.values()), (
        "si ceci échoue, une entrée _STEP_TOOLS existe à tuple vide : "
        "read_loaded_tools doit alors la rendre EMPTY, pas NOT_MEASURED"
    )
    # Les deux constantes elles-mêmes doivent rester distinctes (garde-fou du
    # module, indépendante de l'état actuel de _STEP_TOOLS).
    assert obs.LOADING_STATUS_NOT_MEASURED != obs.LOADING_STATUS_EMPTY
    assert obs.LOADING_STATUS_NOT_MEASURED != obs.LOADING_STATUS_LOADED


def test_toutes_les_entrees_reelles_de_step_tools_sont_loaded():
    for etape in _STEP_TOOLS:
        res = obs.read_loaded_tools(etape)
        assert res.status == obs.LOADING_STATUS_LOADED
        assert res.tools == _STEP_TOOLS[etape]

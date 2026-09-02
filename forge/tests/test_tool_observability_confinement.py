"""Maillon 3 (confinement) — forge.tool_observability.assert_tool_allowed.

PROUVÉ SANS MODÈLE : chaque test appelle la fonction DIRECTEMENT — aucun
subprocess, aucun `claude -p`, aucun réseau. Le refus est une propriété du
CODE, jamais un comportement observé d'un agent (patron qwen-file-worker :
liste constante + défaut refus, testé par appel direct).
"""
from __future__ import annotations

import pytest

from forge import tool_observability as obs
from forge.run_real import _STEP_TOOLS


def test_outil_declare_est_autorise():
    # Aucune exception = passe.
    obs.assert_tool_allowed("s9-build", "Write")
    obs.assert_tool_allowed("s9-build", "Read")


def test_outil_prefixe_bash_node_est_autorise():
    """'Bash(node:*)' dans la table couvre un appel concret 'Bash(node:ls)'."""
    assert "Bash(node:*)" in _STEP_TOOLS["s9-build"]
    obs.assert_tool_allowed("s9-build", "Bash(node:ls)")


def test_outil_inconnu_est_refuse_par_le_code():
    """LE test du maillon 3 : un nom d'outil hors de la table est refusé —
    déterministe, sans modèle, sans subprocess. Ce test ÉCHOUERAIT si le
    garde était un no-op (preuve négative explicite)."""
    with pytest.raises(obs.ToolNotAllowed):
        obs.assert_tool_allowed("s9-build", "Bash(git:push)")


def test_bash_git_est_refuse_meme_prefixe_partiel_dangereux():
    """'Bash(git:*)' n'est PAS dans la table de s9-build (deny côté
    _STEP_DISALLOWED) — le garde maillon 3 le refuse aussi, INDÉPENDAMMENT du
    mécanisme CLI --disallowedTools (une preuve de plus, pas un doublon
    inutile : celle-ci est vérifiable sans lancer aucun processus)."""
    with pytest.raises(obs.ToolNotAllowed):
        obs.assert_tool_allowed("s9-build", "Bash(git:*)")


def test_outil_pour_etape_non_mesuree_est_refuse_par_defaut():
    """Défaut REFUS, pas défaut PASSAGE : une étape absente de _STEP_TOOLS
    (NOT_MEASURED) refuse TOUT nom — jamais un laissez-passer par omission."""
    with pytest.raises(obs.ToolNotAllowed) as exc:
        obs.assert_tool_allowed("etape-inconnue", "Write")
    assert "NOT_MEASURED" in str(exc.value)


def test_correspondance_exacte_pas_de_sous_chaine_permissive():
    """'WriteExtra' ne doit PAS matcher 'Write' par simple `in`/sous-chaîne —
    seule une égalité exacte ou un préfixe explicite '<Tool>(prefix:*)' compte."""
    assert "Write" in _STEP_TOOLS["s9-build"]
    with pytest.raises(obs.ToolNotAllowed):
        obs.assert_tool_allowed("s9-build", "WriteExtra")


def test_tool_name_matches_est_pure_aucune_io():
    """Fonction interne pure : mêmes entrées -> même sortie, aucun effet de
    bord observable (garantie explicite de 'sans modèle, sans subprocess')."""
    allowed = ("Write", "Bash(node:*)")
    assert obs._tool_name_matches("Write", allowed) is True
    assert obs._tool_name_matches("Bash(node:test.mjs)", allowed) is True
    assert obs._tool_name_matches("Bash(python:*)", allowed) is False
    assert obs._tool_name_matches("Edit", allowed) is False

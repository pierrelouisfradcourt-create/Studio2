"""Tests du générateur de carte des composants (déterministe, non-LLM, read-only).

On fabrique des modules Python factices dans un tmp dir et on vérifie l'extraction
``ast`` (responsabilité = 1re phrase de docstring ; interface = publics seulement ;
deps = imports ``forge.*``) ainsi que le déterminisme (deux générations identiques).
"""
from __future__ import annotations

from pathlib import Path

from forge.component_design import (
    build_component_design,
    extract_module_facts,
    generate_component_table,
)

# --- Modules factices ---------------------------------------------------------

_WITH_DOC = '''\
"""Fait la chose importante. Deuxième phrase ignorée par le résumé.

Détails supplémentaires.
"""
from forge.oracle import run_oracle
import forge.verdict
import json


def public_fn():
    pass


def _private_fn():
    pass


class PublicClass:
    def method(self):
        pass


class _PrivateClass:
    pass
'''

_NO_DOC = """\
import os


def helper():
    pass
"""

_SELF_IMPORT = '''\
"""Un module qui n'importe que lui-même et la stdlib."""
import forge.alpha
from forge.beta import thing
'''


def _write(tmp_path: Path, name: str, content: str) -> Path:
    p = tmp_path / f"{name}.py"
    p.write_text(content, encoding="utf-8")
    return p


def test_extract_responsabilite_first_sentence():
    facts = extract_module_facts(_WITH_DOC, "alpha")
    assert facts["responsabilite"] == "Fait la chose importante."


def test_extract_interface_excludes_privates():
    facts = extract_module_facts(_WITH_DOC, "alpha")
    # Publics uniquement, triés ; les _private sont exclus.
    assert facts["interface"] == ["PublicClass", "public_fn"]


def test_extract_deps_only_forge_modules_sorted():
    facts = extract_module_facts(_WITH_DOC, "alpha")
    # forge.oracle + forge.verdict ; json/import stdlib ignorés.
    assert facts["deps"] == ["oracle", "verdict"]


def test_module_without_docstring():
    facts = extract_module_facts(_NO_DOC, "beta")
    assert facts["responsabilite"] == "(sans docstring)"
    assert facts["interface"] == ["helper"]
    assert facts["deps"] == []


def test_self_dep_excluded():
    # Un module ne se liste jamais lui-même dans ses deps.
    facts = extract_module_facts(_SELF_IMPORT, "alpha")
    assert "alpha" not in facts["deps"]
    assert facts["deps"] == ["beta"]


def test_build_component_design_sorted_and_ignores_init(tmp_path):
    _write(tmp_path, "zeta", _NO_DOC)
    _write(tmp_path, "alpha", _WITH_DOC)
    _write(tmp_path, "__init__", '"""paquet"""\n')
    rows = build_component_design(tmp_path)
    modules = [r["module"] for r in rows]
    assert modules == ["alpha", "zeta"]  # trié, __init__ ignoré


def test_generation_is_deterministic(tmp_path):
    _write(tmp_path, "alpha", _WITH_DOC)
    _write(tmp_path, "beta", _NO_DOC)
    first = generate_component_table(tmp_path)
    second = generate_component_table(tmp_path)
    assert first == second
    # Pas d'horodatage : aucune année ne doit apparaître dans la sortie.
    assert "2026" not in first
    # Contenu attendu présent.
    assert "| `alpha` |" in first
    assert "Fait la chose importante." in first
    assert "COMPONENT DESIGN" in first


def test_pipe_in_docstring_is_escaped(tmp_path):
    _write(tmp_path, "gamma", '"""Gère a | b la table."""\n')
    md = generate_component_table(tmp_path)
    # Le pipe de la docstring est échappé pour ne pas casser la table markdown.
    assert "a \\| b" in md

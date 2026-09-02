"""Carte des COMPOSANTS du code Forge — générateur déterministe, non-LLM, read-only.

Même esprit que ``studio_selfaudit.mjs`` / ``master_index.mjs`` (fonctions pures
exportées, flag ``--write``, sortie Markdown SANS horodatage → déterministe,
``main()`` gardé, tests), mais la SOURCE ici est du **Python**. On parse donc les
modules ``forge/*.py`` avec le module ``ast`` de la lib standard — bien
plus robuste que du regex — pour extraire, pour chaque module :

  - responsabilité : 1re ligne/phrase de la docstring de module (``ast.get_docstring``),
    ou ``(sans docstring)`` ;
  - interface publique : ``def``/``class`` de niveau module NON privés (sans ``_``
    initial), triés ;
  - dépend de : les autres modules ``forge.*`` importés (``ImportFrom``/``Import``), triés.

La table DÉCRIT, elle ne JUGE pas — ``claim_verdict: NO_CLAIM_ALLOWED``.

Usage : python -m forge.component_design [--write] [<repoRoot>]
Sortie : JSON sur stdout + résumé lisible sur stderr.
Le fichier généré (``docs/forge/COMPONENT_DESIGN.generated.md``) ne porte AUCUN
horodatage → il ne change que si la réalité du code change (zéro bruit git).
"""
from __future__ import annotations

import argparse
import ast
import json
import logging
import sys
from pathlib import Path
from typing import Optional

logger = logging.getLogger(__name__)

# forge/component_design.py -> parents[2] == repo root
REPO_ROOT = Path(__file__).resolve().parents[1]
GENERATED_FILE = "docs/forge/COMPONENT_DESIGN.generated.md"

# Modules à ignorer : ré-exports/vides et le générateur lui-même n'apportent rien
# à une carte des composants « métier » de la Forge.
_IGNORED_STEMS = frozenset({"__init__"})


def _first_sentence(docstring: str) -> str:
    """Réduit une docstring à sa 1re ligne/phrase (le résumé), espaces normalisés.

    On coupe à la première ligne non vide ; si cette ligne contient un point suivi
    d'un espace, on garde jusqu'au point inclus. Aucune analyse de prose fragile.
    """
    for raw_line in docstring.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        dot = line.find(". ")
        if dot != -1:
            return line[: dot + 1].strip()
        return line
    return ""


def extract_module_facts(source: str, module_stem: str) -> dict:
    """Extrait responsabilité / interface / deps d'UN module Python via ``ast``.

    Fonction pure : prend le texte source et le nom court du module, rend un dict
    ``{module, responsabilite, interface, deps}``. Robuste aux docstrings absentes
    et aux deux formes d'import (``from forge.x import ...`` et ``import forge.x``).
    """
    tree = ast.parse(source)

    doc = ast.get_docstring(tree)
    responsabilite = _first_sentence(doc) if doc else "(sans docstring)"
    if not responsabilite:
        responsabilite = "(sans docstring)"

    interface: set[str] = set()
    deps: set[str] = set()

    for node in tree.body:
        # Interface : def/class de NIVEAU MODULE, non privés (sans '_' initial).
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
            if not node.name.startswith("_"):
                interface.add(node.name)

    # Deps : on parcourt TOUT l'arbre (imports parfois locaux à une fonction).
    for node in ast.walk(tree):
        if isinstance(node, ast.ImportFrom):
            mod = node.module or ""
            dep = _forge_dep_of(mod)
            if dep and dep != module_stem:
                deps.add(dep)
        elif isinstance(node, ast.Import):
            for alias in node.names:
                dep = _forge_dep_of(alias.name)
                if dep and dep != module_stem:
                    deps.add(dep)

    return {
        "module": module_stem,
        "responsabilite": responsabilite,
        "interface": sorted(interface),
        "deps": sorted(deps),
    }


def _forge_dep_of(dotted: str) -> Optional[str]:
    """Rend le sous-module ``forge.<x>`` d'un chemin d'import pointé, sinon None.

    ``forge.contract`` -> ``contract`` · ``forge.contract.sub`` -> ``contract``
    · ``forge`` (le paquet nu) -> None · ``json`` -> None.
    """
    parts = dotted.split(".")
    if len(parts) >= 2 and parts[0] == "forge":
        return parts[1]
    return None


def build_component_design(forge_dir: Path) -> list[dict]:
    """Construit la carte des composants pour tous les modules ``forge_dir/*.py``.

    Fonction pure (aucune écriture). Ignore ``__init__`` et le générateur lui-même,
    ainsi que tout ``tests/`` / ``__pycache__`` (jamais scannés : on ne liste que
    les .py directs de ``forge_dir``). Trié par module → déterministe.
    """
    forge_dir = Path(forge_dir)
    rows: list[dict] = []
    for path in sorted(forge_dir.glob("*.py")):
        stem = path.stem
        if stem in _IGNORED_STEMS or stem == Path(__file__).stem:
            continue
        source = path.read_text(encoding="utf-8")
        rows.append(extract_module_facts(source, stem))
    rows.sort(key=lambda r: r["module"])
    return rows


def _fmt_cell(text: str) -> str:
    """Échappe le pipe pour ne pas casser la table markdown ; espaces normalisés."""
    return " ".join(text.split()).replace("|", "\\|")


def _fmt_names(names: list[str]) -> str:
    """Formate une liste de noms en cellule markdown (backticks, ``—`` si vide)."""
    if not names:
        return "—"
    return ", ".join(f"`{n}`" for n in names)


def generate_component_table(forge_dir: Path) -> str:
    """Génère la table des composants en markdown déterministe (SANS horodatage).

    Colonnes : Module | Responsabilité | Interface publique | Dépend de.
    """
    rows = build_component_design(forge_dir)

    lines: list[str] = []
    lines.append("# COMPONENT DESIGN — carte des composants du code Forge (auto-généré)")
    lines.append("")
    lines.append("> ⚠ Fichier **AUTO-GÉNÉRÉ, ne pas éditer à la main.**")
    lines.append("> Produit par `python -m forge.component_design --write`. Chaque ligne est")
    lines.append("> extraite des modules `forge/*.py` via le module `ast` (docstring de")
    lines.append("> module → responsabilité ; `def`/`class` publics → interface ; imports")
    lines.append("> `forge.*` → dépendances). Déterministe, non-LLM, sans horodatage → il ne")
    lines.append("> change que si le code change (zéro bruit git). La table DÉCRIT, elle ne")
    lines.append("> JUGE pas. `claim_verdict: NO_CLAIM_ALLOWED`.")
    lines.append("")
    lines.append("| Module | Responsabilité | Interface publique | Dépend de |")
    lines.append("|---|---|---|---|")
    for r in rows:
        module = f"`{r['module']}`"
        resp = _fmt_cell(r["responsabilite"])
        interface = _fmt_names(r["interface"])
        deps = _fmt_names(r["deps"])
        lines.append(f"| {module} | {resp} | {interface} | {deps} |")
    lines.append("")
    without_doc = sum(1 for r in rows if r["responsabilite"] == "(sans docstring)")
    lines.append(
        f"**Modules cartographiés** : {len(rows)} · **sans docstring de module** : {without_doc}"
    )
    lines.append("")
    return "\n".join(lines)


def main(argv: Optional[list[str]] = None) -> int:
    parser = argparse.ArgumentParser(
        description="Carte des composants du code Forge (déterministe, non-LLM, read-only)."
    )
    parser.add_argument("repo_root", nargs="?", default=None, help="Racine du repo (défaut : auto).")
    parser.add_argument("--write", action="store_true", help=f"Écrit {GENERATED_FILE}.")
    args = parser.parse_args(argv)

    repo_root = Path(args.repo_root).resolve() if args.repo_root else REPO_ROOT
    forge_dir = repo_root / "forge"
    rows = build_component_design(forge_dir)
    without_doc = sum(1 for r in rows if r["responsabilite"] == "(sans docstring)")

    print(f"=== COMPONENT DESIGN — {forge_dir} ===\n", file=sys.stderr)
    for r in rows:
        print(
            f"  {r['module']:16} interface={len(r['interface']):2} deps={len(r['deps'])}"
            f"  {r['responsabilite'][:60]}",
            file=sys.stderr,
        )
    print(
        f"\nModules cartographiés : {len(rows)} · sans docstring : {without_doc}",
        file=sys.stderr,
    )

    if args.write:
        out = repo_root / GENERATED_FILE
        out.write_text(generate_component_table(forge_dir) + "\n", encoding="utf-8")
        print(f"\n📝 carte des composants régénérée → {GENERATED_FILE}", file=sys.stderr)

    print(json.dumps({"forge_dir": str(forge_dir), "components": rows}, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

"""Lecteur de `forge/test_surfaces.yaml` — surfaces de test protégées et régime.

DONNÉES -> BORNAGE. Ce module est le SEUL consommateur de la déclaration ; aucun chemin
de test n'est écrit en dur ici (même patron que `forge.reference_guard`, ratifié).

Nommé `protected_surfaces` et non `test_surfaces` DÉLIBÉRÉMENT : le dépôt n'a aucune
configuration pytest, donc la collecte par défaut ramasse tout `test_*.py` sous le chemin
visé — un module `forge/test_surfaces.py` serait collecté comme fichier de test. Aucun
précédent dans le tronc, le piège est réel. La déclaration garde son nom : un `.yaml`
n'est jamais collecté.

RÉGIME `create_allowed_modify_denied` : on refuse `Edit(<surface>)`, JAMAIS
`Write(<surface>)`. Le builder Forge PRODUIT des tests (`logic.test.mjs`,
`properties.test.mjs` : livrables versionnés du slice v2_breakout_slice) et l'oracle Godot
EXIGE `GAMES/<jeu>/tests/run_tests.gd` — refuser Write rejouerait l'incident mesuré du run
snake-s9r (2026-07-28), où le forgeron n'a pas pu déposer ce fichier.

LIMITE DÉCLARÉE, non refermable ici : `Write` qui ÉCRASE un fichier existant n'est pas
distinguable, au niveau outil, de `Write` qui crée. Le régime « modifier non » est donc
APPROCHÉ par ce bornage et COMPLÉTÉ par l'empreinte (`forge.reference_guard`), jamais
garanti par le seul deny.
"""
from __future__ import annotations

import logging
from pathlib import Path

logger = logging.getLogger(__name__)

REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CONFIG_PATH = REPO_ROOT / "forge" / "test_surfaces.yaml"
SCHEMA = "forge.test_surfaces.v1"
REGIME_CREATE_ALLOWED_MODIFY_DENIED = "create_allowed_modify_denied"
KNOWN_REGIMES = (REGIME_CREATE_ALLOWED_MODIFY_DENIED,)

# Fail-safe : déclaration absente ou illisible -> déni TOTAL de l'outil d'édition, jamais
# un fail-open. Même politique que `_effective_step_tools` (« borne totale, jamais
# fail-open ») : un builder garde `Write` et reste capable de créer, mais ne peut plus
# éditer nulle part. La déclaration est versionnée à côté du code — son absence est une
# corruption du dépôt, pas un état normal.
FAIL_SAFE_SPECS: tuple[str, ...] = ("Edit",)


class ProtectedSurfacesError(Exception):
    """Déclaration absente, illisible ou mal formée. JAMAIS avalée silencieusement."""


def load_surfaces(config_path: "Path | str | None" = None) -> dict:
    """Lit et VALIDE la déclaration. Lève `ProtectedSurfacesError` sur toute anomalie —
    une surface vide ou un régime inconnu donnerait un bornage muet, donc un vert
    silencieux."""
    path = Path(config_path) if config_path else DEFAULT_CONFIG_PATH
    if not path.exists():
        raise ProtectedSurfacesError(f"déclaration introuvable : {path}")
    try:
        import yaml
        data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    except (OSError, ValueError) as exc:
        raise ProtectedSurfacesError(f"déclaration illisible ({path}) : {exc}") from exc
    if not isinstance(data, dict):
        raise ProtectedSurfacesError(f"déclaration mal formée ({path}) : objet attendu")
    if data.get("schema") != SCHEMA:
        raise ProtectedSurfacesError(
            f"schéma inattendu ({path}) : {data.get('schema')!r} != {SCHEMA!r}")
    surfaces = data.get("surfaces")
    if not isinstance(surfaces, list) or not surfaces:
        raise ProtectedSurfacesError(f"`surfaces` vide ou non-liste ({path})")
    if not all(isinstance(s, str) and s.strip() for s in surfaces):
        raise ProtectedSurfacesError(f"`surfaces` contient une entrée non-texte ({path})")
    regime = data.get("regime")
    if regime not in KNOWN_REGIMES:
        raise ProtectedSurfacesError(f"régime inconnu ({path}) : {regime!r}")
    return {
        "surfaces": [s.strip() for s in surfaces],
        "regime": regime,
        "derogation_path": data.get("derogation_path"),
        "source_path": str(path),
    }


def disallowed_specs(config_path: "Path | str | None" = None) -> tuple[str, ...]:
    """Spécificateurs de déni DÉRIVÉS de la déclaration, un par surface.

    Forme `Edit(<surface>)` : c'est la syntaxe vérifiée de `--disallowedTools`
    (`Tool(glob/**)`), la même que les entrées déjà en place pour `forge/contracts/**`.
    Aucun `Write(...)` n'est émis — voir le régime dans le docstring du module.

    LIMITE DÉCLARÉE : les motifs à `*` médian (`GAMES/*/tests/**`) n'ont PAS été vérifiés
    contre l'interprétation réelle du harnais. La sémantique mesurée le 2026-07-28 porte
    sur le segment unique et sur la barre oblique initiale, pas sur le joker médian. Cette
    dérivation est donc prouvée EXACTE en sortie de fonction, et NON PROUVÉE en effet tant
    qu'un run réel n'a pas montré le déni posé.
    """
    config = load_surfaces(config_path)
    return tuple(f"Edit({surface})" for surface in config["surfaces"])


def disallowed_specs_fail_safe(config_path: "Path | str | None" = None) -> tuple[str, ...]:
    """Variante non-levante pour les points d'appel qui ne peuvent pas casser (l'exécuteur
    borne CHAQUE étape). Sur anomalie : trace explicite + déni total de `Edit`."""
    try:
        return disallowed_specs(config_path)
    except ProtectedSurfacesError as exc:
        logger.warning(
            "surfaces de test illisibles (%s) -> fail-safe : déni total de Edit", exc)
        return FAIL_SAFE_SPECS

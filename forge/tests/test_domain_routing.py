"""Oracle du routage de domaine du journal d'erreurs (`ForgeDriver._domain`).

Lot A, réparation 1 (post-mortem pacman, studio_brain/journal/2026-08-07_
postmortem_pacman_forge.md §2) : avant ce correctif, `_domain()` routait TOUT jeu
vers "html" (`"html" if self.is_game else "forge"`), y compris un jeu Godot
(pacman, profils `full_godot`/`standard_godot`) — le domaine "godot" existe dans
`KNOWN_DOMAINS` (studio_link.py) mais restait structurellement vide.

Fichier NOUVEAU : ne touche à aucun test existant. Instancie `ForgeDriver`
directement (aucun `.run()`) — `_domain()` ne dépend que de `self.is_game` et
`self.order` (dérivé de `self.profile` par le constructeur), aucun état run n'est
nécessaire. claim_verdict: NO_CLAIM_ALLOWED.
"""
from __future__ import annotations

from forge.driver import ForgeDriver


def _driver(tmp_path, *, profile: str, is_game: bool) -> ForgeDriver:
    return ForgeDriver(
        "proj", "proj-1", run_dir=tmp_path / "run", profile=profile, is_game=is_game,
    )


def test_godot_game_routes_to_godot_domain(tmp_path):
    """Un jeu dont le profil résout une étape de build Godot route vers 'godot',
    pas 'html' — le bug mesuré sur pacman (profil full_godot)."""
    d = _driver(tmp_path, profile="full_godot", is_game=True)
    assert d._domain() == "godot"


def test_standard_godot_game_routes_to_godot_domain(tmp_path):
    """Même correction pour le profil dédié standard_godot (curriculum de jeux)."""
    d = _driver(tmp_path, profile="standard_godot", is_game=True)
    assert d._domain() == "godot"


def test_html_game_still_routes_to_html_domain(tmp_path):
    """Comportement HISTORIQUE inchangé pour un jeu web/JS (pong, snake, breakout —
    profil standard, sans étape de build Godot)."""
    d = _driver(tmp_path, profile="standard", is_game=True)
    assert d._domain() == "html"


def test_full_profile_game_still_routes_to_html_domain(tmp_path):
    """Le profil greenfield générique 'full' (s9-build web/JS) reste 'html'."""
    d = _driver(tmp_path, profile="full", is_game=True)
    assert d._domain() == "html"


def test_non_game_run_routes_to_forge_domain_regardless_of_profile(tmp_path):
    """is_game=False route toujours vers 'forge', même sur un profil Godot —
    is_game reste le premier discriminant, godot le second."""
    d = _driver(tmp_path, profile="full_godot", is_game=False)
    assert d._domain() == "forge"


def test_micro_and_patch_profiles_non_game_route_to_forge(tmp_path):
    """Profils de plomberie usuels (non-jeu) : domaine 'forge' inchangé."""
    for profile in ("micro", "patch"):
        d = _driver(tmp_path, profile=profile, is_game=False)
        assert d._domain() == "forge"

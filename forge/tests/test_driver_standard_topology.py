"""ForgeDriver._standard_topology — ensemble NOMME de profils, pas une egalite
de chaine unique (correction 2026-07-28, snake).

Fait mesure : `standard_godot` (jumeau Godot de `standard`, ratifie Pierre
2026-07-28) tombait dans la branche LEGACY parce que `_standard_topology`
testait `self.profile == "standard"` — egalite stricte. Consequence mesuree
dans le recu signe du run snake-s9p : garde e2e rouge ("run-oracle.mjs
absent"), gate mutation BLOCKED ("fichiers logiques inconnus"),
reuse_ratio_wired rouge. La correction fait reconnaitre les deux profils par
`_STANDARD_TOPOLOGY_PROFILES` (frozenset), jamais par une liste codee en dur
au point d'appel.
"""
from forge.driver import ForgeDriver, _STANDARD_TOPOLOGY_PROFILES


def _driver(tmp_path, profile):
    return ForgeDriver(
        "jeu", "jeu-1", run_dir=tmp_path / "run", profile=profile, is_game=True,
    )


def test_profile_standard_is_standard_topology(tmp_path):
    assert _driver(tmp_path, "standard")._standard_topology() is True


def test_profile_standard_godot_is_standard_topology(tmp_path):
    assert _driver(tmp_path, "standard_godot")._standard_topology() is True


def test_profile_full_is_not_standard_topology(tmp_path):
    assert _driver(tmp_path, "full")._standard_topology() is False


def test_profile_micro_is_not_standard_topology(tmp_path):
    assert _driver(tmp_path, "micro")._standard_topology() is False


def test_standard_topology_profiles_is_exactly_the_three_expected():
    # Verrou explicite de l'ensemble : toute extension future passe par ce test,
    # jamais par une modification silencieuse ailleurs.
    #
    # EXTENSION 2026-08-17 (GO Pierre) : `proof_only` entre ici, et c'est PAR CE TEST que
    # l'extension passe — exactement ce que ce verrou exige. Motif : `proof_only` remesure
    # un projet DEJA construit en topologie standard sans le reconstruire ; hors de cet
    # ensemble il tomberait en branche LEGACY et fabriquerait les trois rouges
    # d'instrumentation mesures sur snake-s9p. Le verrou n'est pas affaibli : il compte
    # toujours exactement, et le nom du test dit combien.
    assert _STANDARD_TOPOLOGY_PROFILES == frozenset(
        {"standard", "standard_godot", "proof_only"})

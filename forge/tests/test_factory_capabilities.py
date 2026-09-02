"""Registre USINE + profil `oracle_only` — les deux decisions Pierre du 2026-08-10.

Fichier NEUF : aucun test existant n'est modifie (test_standard_oracles.py et
test_dispatch.py restent intacts, y compris test_standard_step_wiring qui fige un
ordre sous gate).

Le livrable, ce sont les echecs : pour chaque regle, le cas qui DOIT rougir.
"""
from pathlib import Path

import yaml

from forge.dispatch import (
    DEDICATED_PROFILE_STEPS,
    ORDER,
    PROFILES,
    order_for_profile,
    prepare_dispatch,
)
from forge.standard_oracles import check_collisions
from forge.studio_link import propose_capability_gap

STANDARD_DIR = Path(__file__).resolve().parents[1] / "standard"

# --- fixtures minimales ------------------------------------------------------

GAME_REG = {"capabilities": [{"id": "game.state", "statement": "s", "single_owner": True}]}
FACTORY_REG = {
    "factory_capabilities": [
        {"id": "probe.state_snapshot", "statement": "s", "single_owner": True}
    ]
}


def _wiremap(lines):
    return {"schema_version": 1, "lines": lines}


def _line(lid, provides=(), requires=(), owner=True):
    return {"id": lid, "provides": list(provides), "requires": list(requires), "owner": owner}


# --- registre usine : le comportement demande --------------------------------


def test_identifiant_usine_connu_nest_plus_inconnu():
    """Le defaut d'origine : `debug.observation_point` declarait une sonde, et le
    registre produit la refusait faute d'y avoir sa place."""
    wm = _wiremap([_line("debug.observation_point", provides=["probe.state_snapshot"])])
    sans = check_collisions(wm, GAME_REG)
    avec = check_collisions(wm, GAME_REG, FACTORY_REG)
    assert sans["identifiants_inconnus"] == ["debug.observation_point:probe.state_snapshot"]
    assert avec["identifiants_inconnus"] == []
    assert avec["passed"] is True


def test_capacites_usine_utilisees_est_expose():
    """Visibilite : on doit pouvoir LIRE quelles capacites d'usine un jeu emploie."""
    wm = _wiremap([
        _line("debug.observation_point", provides=["probe.state_snapshot"]),
        _line("core.game_state", provides=["game.state"]),
    ])
    r = check_collisions(wm, GAME_REG, FACTORY_REG)
    assert r["capacites_usine_utilisees"] == ["probe.state_snapshot"]
    assert r["passed"] is True


def test_identifiant_absent_des_deux_registres_reste_un_echec():
    """Separer les gouvernances ne cree AUCUNE zone franche : le vocabulaire reste ferme."""
    wm = _wiremap([_line("x", provides=["invente.au.hasard"])])
    r = check_collisions(wm, GAME_REG, FACTORY_REG)
    assert r["identifiants_inconnus"] == ["x:invente.au.hasard"]
    assert r["passed"] is False


def test_regles_structurelles_s_appliquent_aussi_a_l_usine():
    """Un id d'usine n'echappe pas au single_owner ni au double proprietaire."""
    wm = _wiremap([
        _line("sonde.a", provides=["probe.state_snapshot"]),
        _line("sonde.b", provides=["probe.state_snapshot"]),
    ])
    r = check_collisions(wm, GAME_REG, FACTORY_REG)
    assert r["collisions"] == ["probe.state_snapshot"]
    assert r["doubles_proprietaires"] == ["probe.state_snapshot"]
    assert r["passed"] is False


def test_id_declare_dans_les_deux_registres_est_ambigu_jamais_arbitre():
    """Gouvernance : si un id vit des deux cotes, personne ne sait plus qui le ratifie.
    Signale, et FAIL — pas de priorite silencieuse."""
    game = {"capabilities": [{"id": "probe.state_snapshot", "statement": "s"}]}
    wm = _wiremap([_line("x", provides=["probe.state_snapshot"])])
    r = check_collisions(wm, game, FACTORY_REG)
    assert r["identifiants_ambigus"] == ["probe.state_snapshot"]
    assert r["passed"] is False


def test_retro_compatibilite_sans_registre_usine():
    """Un appelant qui ne passe pas le 3e argument retrouve le comportement d'avant."""
    wm = _wiremap([_line("core.game_state", provides=["game.state"])])
    assert check_collisions(wm, GAME_REG) == check_collisions(wm, GAME_REG, None)


def test_registre_usine_reel_est_lisible_et_bien_forme():
    """Le fichier livre parse, et respecte le schema attendu par _collect."""
    reg = yaml.safe_load((STANDARD_DIR / "factory_capabilities.yaml").read_text(encoding="utf-8"))
    assert reg["schema_version"] == 1
    entries = reg["factory_capabilities"]
    assert entries, "registre usine vide : l'amorce Tetris doit y etre"
    for e in entries:
        assert isinstance(e["id"], str) and e["id"]
        assert isinstance(e["statement"], str) and e["statement"].strip()


def test_aucun_id_partage_entre_les_deux_registres_reels():
    """Invariant de table sur les fichiers REELS, pas sur des fixtures."""
    game = yaml.safe_load((STANDARD_DIR / "capabilities.yaml").read_text(encoding="utf-8"))
    fact = yaml.safe_load((STANDARD_DIR / "factory_capabilities.yaml").read_text(encoding="utf-8"))
    game_ids = {c["id"] for c in game["capabilities"]}
    fact_ids = {c["id"] for c in fact["factory_capabilities"]}
    assert game_ids.isdisjoint(fact_ids)


# --- profil oracle_only ------------------------------------------------------


def test_oracle_only_est_s10s_seul():
    """Portee strictement limitee : une etape, aucun build, aucune variante."""
    assert order_for_profile("oracle_only") == ["s10s-oracle-standard"]


def test_oracle_only_ne_contient_aucun_build_ni_verdict():
    """La condition de la ratification. Un build reconstruirait le jeu mesure ;
    un verdict ferait passer une mesure de capitalisation pour une baseline."""
    steps = order_for_profile("oracle_only")
    assert not any(s.startswith("s9-build") for s in steps)
    assert "s12-verdict" not in steps


def test_oracle_only_respecte_l_invariant_de_profil():
    """Meme garde que tous les autres profils : aucune etape mystere."""
    assert set(order_for_profile("oracle_only")).issubset(set(ORDER) | set(DEDICATED_PROFILE_STEPS))


def test_oracle_only_est_reellement_dispatchable(tmp_path):
    """Le defaut « profil declare, jamais atteignable » deja rencontre sur `standard`."""
    for etape in order_for_profile("oracle_only"):
        payload = prepare_dispatch(
            etape, run_id="t-oracle-only", profile="oracle_only",
            audit_path=tmp_path / "audit.jsonl",
        )
        assert payload.model


def test_oracle_only_ne_fuit_pas_dans_full():
    """s10s reste dedie : l'ajout d'un profil ne doit pas le faire entrer dans full."""
    assert "s10s-oracle-standard" not in order_for_profile("full")
    assert "oracle_only" in PROFILES


# --- routage produit / usine des propositions --------------------------------

NS = ("probe.", "proof.", "bot.", "solvability.", "factory.")


def _routed(tmp_path, cap_id, namespaces=NS):
    """Depose une proposition et rend (n_produit, n_usine)."""
    prod = tmp_path / "produit.jsonl"
    fact = tmp_path / "usine.jsonl"
    propose_capability_gap(
        "run-1", "pacman", cap_id, "une.ligne",
        proposals_path=prod, factory_namespaces=namespaces, factory_proposals_path=fact,
    )
    n_p = len(prod.read_text(encoding="utf-8").splitlines()) if prod.exists() else 0
    n_f = len(fact.read_text(encoding="utf-8").splitlines()) if fact.exists() else 0
    return n_p, n_f


def test_identifiant_usine_part_dans_la_file_usine(tmp_path):
    """Le point de la decision : ne pas polluer la file que Pierre arbitre."""
    assert _routed(tmp_path / "a", "proof.input_parity") == (0, 1)
    assert _routed(tmp_path / "b", "probe.observable") == (0, 1)
    assert _routed(tmp_path / "c", "bot.solvability") == (0, 1)


def test_identifiant_de_jeu_reste_dans_la_file_produit(tmp_path):
    assert _routed(tmp_path / "a", "maze.walkable") == (1, 0)
    assert _routed(tmp_path / "b", "game.tick") == (1, 0)


def test_sans_namespaces_tout_part_en_produit(tmp_path):
    """Retro-compatibilite stricte : un appelant qui n'active pas le routage
    retrouve exactement le comportement d'avant."""
    assert _routed(tmp_path / "a", "proof.input_parity", namespaces=None) == (1, 0)
    assert _routed(tmp_path / "b", "proof.input_parity", namespaces=()) == (1, 0)


def test_le_record_est_identique_dans_les_deux_files(tmp_path):
    """Seule la destination change : un lecteur n'a rien de special a apprendre."""
    import json as _json

    prod, fact = tmp_path / "p.jsonl", tmp_path / "f.jsonl"
    a = propose_capability_gap("r", "pacman", "game.tick", "l",
                               proposals_path=prod, factory_namespaces=NS,
                               factory_proposals_path=fact)
    b = propose_capability_gap("r", "pacman", "proof.replay", "l",
                               proposals_path=prod, factory_namespaces=NS,
                               factory_proposals_path=fact)
    assert sorted(a.keys()) == sorted(b.keys())
    assert a["type"] == b["type"] == "capability_gap"
    assert _json.loads(fact.read_text(encoding="utf-8").splitlines()[0])["capability_id"] == (
        "proof.replay"
    )


def test_namespaces_du_registre_reel_sont_un_champ_structure():
    """La liste vit dans une DONNEE validee, pas dans un commentaire (regle 2026-07-23)."""
    reg = yaml.safe_load((STANDARD_DIR / "factory_capabilities.yaml").read_text(encoding="utf-8"))
    ns = reg["namespaces"]
    assert isinstance(ns, list) and ns
    for p in ns:
        assert isinstance(p, str) and p.endswith("."), f"prefixe malforme : {p!r}"


def test_l_amorce_du_registre_respecte_ses_propres_namespaces():
    """Un id du registre usine doit appartenir a l'un de ses espaces de noms —
    sinon le routage et le registre se contrediraient."""
    reg = yaml.safe_load((STANDARD_DIR / "factory_capabilities.yaml").read_text(encoding="utf-8"))
    prefixes = tuple(reg["namespaces"])
    for entry in reg["factory_capabilities"]:
        assert entry["id"].startswith(prefixes), (
            f"{entry['id']} n'appartient a aucun espace de noms declare"
        )

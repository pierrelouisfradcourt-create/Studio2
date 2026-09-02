# Profil `proof_only` (GO Pierre 2026-08-17) — REMESURER SANS RECONSTRUIRE.
#
# BESOIN MESURE : les reçus produit Godot du depot datent de juillet. Les rafraichir
# exigeait jusqu'ici `standard` / `standard_godot` / `full_godot`, tous porteurs d'un
# BUILDER et d'une RED-TEAM. Reconstruire un jeu pour rafraichir son certificat de preuve
# est disproportionne, et cela reecrit `GAMES/**` — y compris les volets sur lesquels
# ea4e407 s'appuie comme referents.
#
# POURQUOI CE COUPLE ET PAS UNE ETAPE : `s10s` ne PRODUIT pas le reçu produit, il le LIT
# dans le detail de `s10a` (`state["steps"]["s10a-oracle-code"]["detail"]
# ["product_oracle_godot"]`). Le profil `oracle_only` existant, qui lance `s10s` SEUL,
# recalculerait donc `observable_coverage` sur le reçu PERIME — un fichier date d'aujourd'hui
# derive de mesures de juillet. C'est la fausse continuite explicitement ecartee par Pierre :
# producteur et consommateur doivent etre rejoues ENSEMBLE ou pas du tout.
#
# TOPOLOGIE : le point non evident, et le vrai motif de ce fichier. `_standard_topology()`
# decide par APPARTENANCE A UN ENSEMBLE NOMME. Un profil absent de cet ensemble tombe en
# branche LEGACY, dont l'effet est DOCUMENTE et MESURE (driver.py:2140, run snake-s9p,
# 2026-07-28) : garde e2e rouge « run-oracle.mjs absent », gate mutation BLOCKED « fichiers
# logiques inconnus », `reuse_ratio_wired` rouge. TROIS rouges d'INSTRUMENTATION — sur un
# profil dont l'objet est precisement d'en supprimer. Le meme defaut a deja frappe
# `standard_godot` une fois ; ce test existe pour qu'il ne frappe pas une troisieme.
from __future__ import annotations

from pathlib import Path

from forge.dispatch import PROFILES, order_for_profile
from forge.driver import _STANDARD_TOPOLOGY_PROFILES, ForgeDriver

BUILDERS = ("s9-build", "s9-build-standard", "s9-build-godot-standard")


def _driver(tmp_path: Path, profile: str) -> ForgeDriver:
    return ForgeDriver(project="p", run_id="r", run_dir=tmp_path, profile=profile,
                       executor=lambda *a, **k: {})


def test_proof_only_enchaine_le_producteur_PUIS_le_consommateur():
    """L'ordre n'est pas cosmetique : s10a produit le reçu, s10s le consomme."""
    assert order_for_profile("proof_only") == ["s10a-oracle-code", "s10s-oracle-standard"]


def test_proof_only_ne_RECONSTRUIT_rien():
    """LA raison d'etre du profil : aucun builder, donc aucune ecriture sous `GAMES/**`."""
    etapes = order_for_profile("proof_only")
    assert not [e for e in etapes if e in BUILDERS], "un builder reecrirait le jeu"
    assert "s11-redteam-code" not in etapes, "la red-team est une etape LLM, hors perimetre"


def test_proof_only_ne_signe_AUCUN_verdict():
    """`s12-verdict` est absent : ce profil REMESURE, il ne juge pas. Un `software_verdict`
    exige des reçus d'oracle verifies au sens de CLAUDE.md:81 — pas ce profil."""
    assert "s12-verdict" not in order_for_profile("proof_only")


def test_proof_only_est_de_topologie_STANDARD():
    """LE CAS QUI FALSIFIE. Sans cette appartenance, le profil tombe en branche LEGACY et
    fabrique les trois rouges d'instrumentation mesures sur snake-s9p."""
    assert "proof_only" in _STANDARD_TOPOLOGY_PROFILES


def test_proof_only_ne_tombe_PAS_dans_la_branche_legacy(tmp_path):
    """Meme invariant, verifie sur le DRIVER et non sur l'ensemble — c'est `_standard_topology`
    qui decide reellement, l'ensemble n'est que sa table."""
    assert _driver(tmp_path, "proof_only")._standard_topology() is True


def test_les_profils_EXISTANTS_sont_intacts():
    """Un ajout ne se paie pas d'une derive ailleurs."""
    assert order_for_profile("oracle_only") == ["s10s-oracle-standard"]
    assert order_for_profile("standard") == [
        "s9-build-standard", "s10a-oracle-code", "s10s-oracle-standard",
        "s11-redteam-code", "s12-verdict"]
    assert _driver(Path("."), "full")._standard_topology() is False


def test_proof_only_est_un_SOUS_ENSEMBLE_de_standard():
    """Garde-fou d'invention : ce profil ne cree AUCUNE etape neuve, il decoupe une chaine
    deja ratifiee. Toute etape de `proof_only` existe dans `standard`."""
    assert set(PROFILES["proof_only"]) <= set(PROFILES["standard"])

"""Tests de `forge/standard/target_capabilities.yaml` — le registre CIBLE.

Ce registre reserve des domaines que l'architecture devra savoir accueillir. Une reservation
qui n'est verifiee par rien n'est pas une reservation : c'est une intention. Ces tests sont
donc l'ORACLE DE RESERVATION, et ils portent sur les deux moities du piege :

  - une entree ACTIF doit NOMMER un artefact qui existe reellement (sinon la preuve est un
    mot) ;
  - une entree PREVU ne doit avoir cree AUCUN dossier (sinon on a un dossier vide, qui donne
    l'apparence de la frontiere sans la contrainte — le defaut mesure sur bomberman_3d).

Et l'invariant qui tient les trois registres separes : aucun identifiant commun, aucun
espace de noms partage.
"""

from __future__ import annotations

from pathlib import Path

import pytest
import yaml

RACINE = Path(__file__).resolve().parents[2]
CIBLE = RACINE / "forge/standard/target_capabilities.yaml"
PRODUIT = RACINE / "forge/standard/capabilities.yaml"
USINE = RACINE / "forge/standard/factory_capabilities.yaml"

ETATS = {"PREVU", "ACTIF"}
CLASSES = {"A", "B", "C", "D"}


def _charger(chemin: Path) -> dict:
    return yaml.safe_load(chemin.read_text(encoding="utf-8"))


@pytest.fixture(scope="module")
def registre() -> dict:
    return _charger(CIBLE)


@pytest.fixture(scope="module")
def entrees(registre: dict) -> list[dict]:
    return registre["target_capabilities"]


def _concret(emplacement: str) -> bool:
    """Un emplacement CIBLE est concret s'il ne porte ni gabarit ni commentaire.

    `05_SYSTEMS/inventory/` est concret ; `05_SYSTEMS/<domaine>_validator/` et
    `05_SYSTEMS/world_state/ (portee ZONE deja declaree)` ne le sont pas.
    """
    return "<" not in emplacement and "(" not in emplacement and " " not in emplacement.strip()


# --- forme du registre ----------------------------------------------------------------

def test_registre_bien_forme(registre: dict) -> None:
    assert registre["schema_version"] == 1
    assert registre["namespaces"] == ["target."]
    assert isinstance(registre["target_capabilities"], list)
    assert len(registre["target_capabilities"]) >= 20


def test_identifiants_uniques_et_dans_l_espace_de_noms(entrees: list[dict]) -> None:
    ids = [e["id"] for e in entrees]
    assert len(ids) == len(set(ids)), "identifiant en double"
    for i in ids:
        assert i.startswith("target."), f"hors espace de noms : {i}"
        assert i.count(".") >= 2, f"identifiant sans domaine : {i} (attendu target.<domaine>.<capacite>)"


def test_chaque_entree_porte_son_sens_son_emplacement_et_son_oracle(entrees: list[dict]) -> None:
    for e in entrees:
        assert len(e.get("statement", "")) > 30, f"statement absent ou creux : {e['id']}"
        assert e.get("emplacement_cible"), f"emplacement cible absent : {e['id']}"
        assert len(e.get("oracle", "")) > 20, f"oracle absent ou creux : {e['id']}"


def test_etat_dans_le_vocabulaire_ferme(entrees: list[dict]) -> None:
    for e in entrees:
        assert e.get("etat") in ETATS, f"etat hors vocabulaire : {e['id']} -> {e.get('etat')}"


# --- l'oracle de reservation, ses deux moities ----------------------------------------

def test_actif_nomme_un_artefact_qui_existe(entrees: list[dict]) -> None:
    """Une capacite declaree ACTIF sans artefact reel serait une preuve par affirmation."""
    actifs = [e for e in entrees if e["etat"] == "ACTIF"]
    assert actifs, "un registre cible sans aucun mecanisme demontre ne mesure rien"
    for e in actifs:
        ref = e.get("demontre_par")
        assert ref, f"ACTIF sans demontre_par : {e['id']}"
        for morceau in ref.split(" + "):
            chemin = RACINE / morceau.strip()
            assert chemin.exists(), f"{e['id']} : demontre_par introuvable -> {morceau.strip()}"


def jeux_portant(jeux: list[Path], emplacement: str) -> list[str]:
    """Jeux ou l'emplacement cible existe deja comme dossier. Predicat isole pour etre
    FALSIFIABLE : un oracle dont on n'a jamais vu la moitie echouer ne mesure qu'a moitie."""
    return [j.name for j in jeux if (j / emplacement).is_dir()]


def test_prevu_n_a_cree_aucun_dossier(entrees: list[dict]) -> None:
    """LE PIEGE DU DOSSIER VIDE. Declarer un domaine n'est pas le construire.

    Si le dossier apparait, ce n'est pas au registre de se taire : c'est a l'entree de
    passer a ACTIF avec son `demontre_par`.
    """
    jeux = [p.parent for p in (RACINE / "GAMES").glob("*/project.godot")]
    assert jeux, "aucun projet Godot : le test ne mesurerait rien"
    for e in entrees:
        if e["etat"] != "PREVU":
            continue
        emplacement = e["emplacement_cible"]
        if not _concret(emplacement):
            continue
        porteurs = jeux_portant(jeux, emplacement)
        assert not porteurs, (
            f"{e['id']} est PREVU mais {porteurs} porte(nt) deja {emplacement} — "
            "dossier vide, ou etat perime : passer l'entree a ACTIF avec demontre_par")


def test_le_predicat_du_dossier_vide_sait_dire_oui(tmp_path: Path) -> None:
    """Controle POSITIF du predicat : sans lui, `test_prevu_n_a_cree_aucun_dossier`
    passerait aussi bien si le predicat rendait toujours la liste vide."""
    jeu = tmp_path / "jeu_fictif"
    (jeu / "05_SYSTEMS/inventory").mkdir(parents=True)
    assert jeux_portant([jeu], "05_SYSTEMS/inventory") == ["jeu_fictif"]
    assert jeux_portant([jeu], "05_SYSTEMS/quests") == []


def test_emplacement_gabarit_est_bien_ignore() -> None:
    """Les emplacements a gabarit ne sont pas verifiables : les traiter comme concrets
    ferait passer le test pour une mauvaise raison."""
    assert _concret("05_SYSTEMS/inventory/")
    assert not _concret("05_SYSTEMS/<domaine>_validator/")
    assert not _concret("05_SYSTEMS/world_state/ (portee ZONE deja declaree)")


def test_prevu_porte_une_classe_d_activation_et_pas_de_preuve(entrees: list[dict]) -> None:
    for e in entrees:
        if e["etat"] != "PREVU":
            continue
        assert e.get("classe") in CLASSES, f"classe absente ou hors vocabulaire : {e['id']}"
        assert "demontre_par" not in e, f"PREVU avec demontre_par : {e['id']} (etat perime ?)"


def test_actif_ne_porte_pas_de_classe_d_activation(entrees: list[dict]) -> None:
    """La classe est un COUT D'ACTIVATION : elle n'a plus de sens une fois active."""
    for e in entrees:
        if e["etat"] == "ACTIF":
            assert "classe" not in e, f"ACTIF avec une classe d'activation : {e['id']}"


def test_aucune_classe_d_reste_dans_la_cible(entrees: list[dict]) -> None:
    """Un D est le signal d'une mauvaise architecture cible : il doit etre traite, pas garde.

    target.world.multi_zone etait le seul D mesure le 2026-09-09 ; il est passe en B par
    target.state.scope. Si un D reapparait, c'est une decision a prendre, pas une ligne a
    ranger.
    """
    d = [e["id"] for e in entrees if e.get("classe") == "D"]
    assert not d, f"classe D dans le registre cible : {d}"


# --- separation des trois registres ---------------------------------------------------

def test_aucune_collision_avec_les_deux_autres_registres(entrees: list[dict]) -> None:
    cibles = {e["id"] for e in entrees}
    produit = {c["id"] for c in _charger(PRODUIT)["capabilities"]}
    usine = {c["id"] for c in _charger(USINE)["factory_capabilities"]}
    assert not (cibles & produit), f"collision avec capabilities.yaml : {cibles & produit}"
    assert not (cibles & usine), f"collision avec factory_capabilities.yaml : {cibles & usine}"


def test_les_espaces_de_noms_ne_se_recouvrent_pas() -> None:
    """`target.` ne doit apparaitre dans aucun des deux autres registres, et reciproquement."""
    produit = {c["id"] for c in _charger(PRODUIT)["capabilities"]}
    usine_doc = _charger(USINE)
    usine = {c["id"] for c in usine_doc["factory_capabilities"]}
    for i in produit | usine:
        assert not i.startswith("target."), f"identifiant `target.` hors du registre cible : {i}"
    for prefixe in usine_doc["namespaces"]:
        for i in {e["id"] for e in _charger(CIBLE)["target_capabilities"]}:
            assert not i.startswith(prefixe), f"{i} empiete sur l'espace de noms usine {prefixe}"

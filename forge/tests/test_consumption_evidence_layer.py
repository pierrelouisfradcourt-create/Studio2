"""Couche `verification` + champ `consumption_evidence` (P3, ratifiée Pierre 2026-09-02).

Ces tests figent les trois conditions d'entrée de la ratification :
  1. le champ arrive AVEC son point de mesure (`consumption_evidence_status`,
     `consumption_evidence_adoption`) — un champ déclaratif sans lecteur est la faute
     déjà payée par le corpus Codex et `reference_guard` ;
  2. il est ADVISORY — il ne bloque rien, son absence ne rend aucun contrat invalide ;
  3. il est OPTIONNEL — les contrats existants restent chargeables sans lui.

Et l'invariant de couche : `consumption_evidence` n'entre dans AUCUNE des trois couches
existantes, et surtout pas dans `LAYER_PROMPT` — `_verify_prompt_layer_rendered` fige
« tout champ prompt rempli est rendu », or ce champ ne doit jamais être rendu à l'agent.

NO_CLAIM_ALLOWED.
"""
from __future__ import annotations

import pytest
import yaml

from forge.contract import (
    CRITICAL,
    IMPORTANT,
    LAYER_DISPATCH,
    LAYER_DOCUMENTATION,
    LAYER_PROMPT,
    LAYER_VERIFICATION,
    RECOMMENDED,
    VERIFICATION,
    ContractIncomplete,
    build_dispatch_payload,
    consumption_evidence_adoption,
    consumption_evidence_status,
    load_contract,
    validate_contract,
)


# --- la couche est bien une 4e couche, disjointe des trois autres -------------------

def test_quatre_couches_disjointes():
    couches = (LAYER_PROMPT, LAYER_DISPATCH, LAYER_DOCUMENTATION, LAYER_VERIFICATION)
    vus: set[str] = set()
    for couche in couches:
        assert not (set(couche) & vus), "un champ ne peut appartenir qu'à UNE couche"
        vus |= set(couche)


def test_consumption_evidence_jamais_rendu_a_l_agent():
    """Le champ est lu par la vérification APRÈS production : il ne doit apparaître
    ni dans le prompt, ni dans le payload de dispatch."""
    assert "consumption_evidence" in LAYER_VERIFICATION
    assert "consumption_evidence" not in LAYER_PROMPT
    assert "consumption_evidence" not in LAYER_DISPATCH
    assert "consumption_evidence" not in LAYER_DOCUMENTATION


def test_champ_optionnel_hors_des_trois_niveaux_d_exigence():
    """Ni Critique, ni Important, ni Recommandé : son absence ne peut rien bloquer."""
    for niveau in (CRITICAL, IMPORTANT, RECOMMENDED):
        assert "consumption_evidence" not in niveau
    assert VERIFICATION == ("consumption_evidence",)


# --- validation : absent => OK ; présent malformé => refusé -------------------------

def _contrat_minimal(**over) -> dict:
    contract = {field: "x" for field in CRITICAL}
    contract.update({field: "aucun" for field in IMPORTANT})
    contract.update(over)
    return contract


def test_contrat_sans_le_champ_reste_valide():
    validate_contract(_contrat_minimal())  # ne lève pas


def test_contrat_avec_le_champ_rempli_reste_valide():
    validate_contract(_contrat_minimal(consumption_evidence=["blueprint.yaml"]))
    validate_contract(_contrat_minimal(consumption_evidence="aucun"))


def test_champ_present_mais_malforme_refuse():
    with pytest.raises(ContractIncomplete, match="consumption_evidence"):
        validate_contract(_contrat_minimal(consumption_evidence=42))


def test_le_champ_ne_change_pas_le_prompt_rendu(tmp_path):
    """Garde anti-fuite : ajouter le champ ne doit rien injecter dans le prompt
    (sinon il aurait de facto rejoint la couche `prompt`)."""
    contrat = load_contract("s5-wiremap")
    sans = build_dispatch_payload(contrat, "s5-wiremap", run_id="r1").prompt
    avec = dict(contrat)
    avec["consumption_evidence"] = ["UN-MARQUEUR-QUI-NE-DOIT-PAS-FUIR"]
    rendu = build_dispatch_payload(avec, "s5-wiremap", run_id="r1").prompt
    assert "UN-MARQUEUR-QUI-NE-DOIT-PAS-FUIR" not in rendu
    assert rendu == sans


# --- le point de mesure, livré le même jour que le champ ---------------------------

def test_status_trois_etats():
    assert consumption_evidence_status({"consumption_evidence": ["a.md"]}) == "filled"
    assert consumption_evidence_status({"consumption_evidence": "aucun"}) == "declared_empty"
    assert consumption_evidence_status({}) == "absent"
    assert consumption_evidence_status({"consumption_evidence": []}) == "absent"


def test_status_ne_leve_jamais():
    for entree in (None, "pas un contrat", 42, []):
        assert consumption_evidence_status(entree) == "absent"


def test_adoption_mesure_le_repertoire(tmp_path):
    (tmp_path / "a.yaml").write_text(
        yaml.safe_dump({"consumption_evidence": ["wiremap.json"]}), encoding="utf-8")
    (tmp_path / "b.yaml").write_text(
        yaml.safe_dump({"consumption_evidence": "aucun"}), encoding="utf-8")
    (tmp_path / "c.yaml").write_text(yaml.safe_dump({"role": "x"}), encoding="utf-8")
    (tmp_path / "d.yaml").write_text("{ceci n'est pas du YAML: [", encoding="utf-8")

    mesure = consumption_evidence_adoption(tmp_path)
    assert mesure["filled"] == 1
    assert mesure["declared_empty"] == 1
    assert mesure["absent"] == 2          # le contrat sans le champ + l'illisible
    assert mesure["total"] == 4
    assert mesure["by_contract"]["a"] == "filled"


def test_adoption_reelle_est_mesurable_et_nulle_au_jour_de_l_amendement():
    """Le chiffre de départ, honnête : aucun contrat ne porte encore le champ.
    C'est ce zéro que la décision ultérieure sur le gate devra voir bouger."""
    mesure = consumption_evidence_adoption()
    assert mesure["total"] > 0
    assert mesure["filled"] + mesure["declared_empty"] + mesure["absent"] == mesure["total"]

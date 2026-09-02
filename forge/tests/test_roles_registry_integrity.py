"""Integrite de `forge/contracts/roles.yaml` — le registre de resolution Forge.

NE PAS LIRE COMME UNE PRECAUTION THEORIQUE. Le 2026-08-06, un backtick place en tete
d'un scalaire YAML a rendu ce fichier ILLISIBLE. Consequence immediate et silencieuse :
`control_plane.registry` a echoue, chaque role s'est resolu a `None`, et un worker est
parti appeler LM Studio avec `model: null` — l'erreur remontee etait un « HTTP 400 »,
qui ne dit rien du vrai defaut. Aucun test ne gardait la parsabilite de ce fichier.

Ces tests ferment exactement ce trou :
  1. le fichier parse ;
  2. tout role declare dans `runtime_contracts` et adosse a un modele se resout ;
  3. un runtime qui declare un modele ne peut pas se resoudre a rien.
"""
from __future__ import annotations

import sys
from pathlib import Path

import pytest

yaml = pytest.importorskip("yaml")

REPO = Path(__file__).resolve().parents[2]
ROLES = REPO / "forge" / "contracts" / "roles.yaml"


@pytest.fixture(scope="module")
def registre() -> dict:
    """Le simple fait de charger ce fichier EST le premier test."""
    assert ROLES.is_file(), f"registre absent : {ROLES}"
    try:
        data = yaml.safe_load(ROLES.read_text(encoding="utf-8"))
    except yaml.YAMLError as exc:
        pytest.fail(f"roles.yaml n'est plus parsable — le registry entier tombe : {exc}")
    assert isinstance(data, dict), "roles.yaml doit etre un mapping"
    return data


def test_le_registre_parse(registre):
    assert "models" in registre and isinstance(registre["models"], list)
    assert registre["models"], "aucun modele declare : plus aucun role ne peut se resoudre"


def test_chaque_modele_declare_les_champs_de_resolution(registre):
    for m in registre["models"]:
        assert m.get("id"), f"modele sans id : {m}"
        assert m.get("provider"), f"modele sans provider : {m.get('id')}"
        assert isinstance(m.get("roles"), list), f"modele sans roles : {m.get('id')}"


def test_aucun_role_declare_deux_fois_sur_deux_modeles(registre):
    """Le registry rend le PREMIER modele qui declare un role (registry.py:39).

    Un role declare deux fois rendrait la seconde declaration silencieusement morte —
    une decision qui vit a cote d'une donnee qui la contredit.
    """
    vus: dict[str, str] = {}
    doublons = []
    for m in registre["models"]:
        for r in (m.get("roles") or []):
            if r in vus:
                doublons.append(f"{r} : {vus[r]} puis {m['id']}")
            else:
                vus[r] = m["id"]
    assert not doublons, f"roles declares plusieurs fois (le 2e est mort) : {doublons}"


def _resolve(role: str):
    sys.path.insert(0, str(REPO))
    from control_plane.registry import get_model_for_role, get_provider_for_role
    return get_model_for_role(role, ROLES), get_provider_for_role(role, ROLES)


@pytest.mark.parametrize("role", ["asset_spec_author", "repair_runtime",
                                  "redteam_reviewer", "run_orchestrator"])
def test_les_roles_critiques_se_resolvent(role):
    """Si l'un d'eux rend None, un worker partirait avec un modele nul."""
    modele, provider = _resolve(role)
    assert modele, f"role {role!r} non resolu — le registry est casse ou le role a disparu"
    assert provider, f"role {role!r} sans provider"


def test_un_runtime_qui_declare_un_modele_doit_se_resoudre(registre):
    """Coherence entre `runtime_contracts.<r>.implementation.model` et la resolution.

    Un runtime qui ANNONCE un modele dans son contrat mais que le registry ne resout
    pas est un contrat qui ment sur sa propre execution.
    """
    for nom, rc in (registre.get("runtime_contracts") or {}).items():
        declare = (rc.get("implementation") or {}).get("model")
        if not declare or declare == "aucun":
            continue  # runtime deterministe / procedural : rien a resoudre
        modele, _ = _resolve(nom)
        assert modele, (f"runtime {nom!r} declare le modele {declare!r} mais le registry "
                        f"ne resout pas ce role — ajouter {nom!r} aux `roles:` du modele")
        assert modele in declare, (f"runtime {nom!r} : contrat declare {declare!r}, "
                                   f"registry resout {modele!r}")


def test_les_runtimes_documentent_leurs_limites(registre):
    """Un runtime sans `limits` se lirait comme sans limite — jamais vrai ici."""
    for nom, rc in (registre.get("runtime_contracts") or {}).items():
        assert "limits" in rc, f"runtime {nom!r} sans limites declarees"
        assert "production_ready" in rc["limits"], f"runtime {nom!r} sans production_ready"

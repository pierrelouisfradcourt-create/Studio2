"""Oracle non-LLM du dispatcher de contrat Forge (C1 gate + C2 prompt borné).

Prouve : un agent sans contrat complet est REFUSÉ (C1), et un contrat complet
produit un prompt borné qui injecte le role, force le modèle, n'autorise que les
outils déclarés, et porte la RÈGLE DE RESTITUTION (C2). Aucun spawn ici.
"""
import copy
from pathlib import Path

import pytest

from forge.contract import (
    CRITICAL,
    IMPORTANT,
    RECOMMENDED,
    ContractIncomplete,
    DispatchPayload,
    RoleUnresolved,
    build_dispatch_payload,
    field_state,
    load_contract,
    resolve_runtime,
)

FIXTURE = "s4-archi"  # contrat réel gravé dans forge/contracts/


@pytest.fixture
def contract():
    """Le contrat-fixture réel, complet au schéma (16 champs)."""
    return load_contract(FIXTURE)


# --- field_state : les 3 états (rempli / déclaré-vide / absent) ---

def test_field_state_filled():
    assert field_state("un vrai texte") == "filled"
    assert field_state(["a", "b"]) == "filled"


def test_field_state_declared_empty():
    assert field_state("aucun") == "declared_empty"
    assert field_state("AUCUN") == "declared_empty"
    assert field_state(["aucun"]) == "declared_empty"


def test_field_state_absent():
    assert field_state(None) == "absent"
    assert field_state("") == "absent"
    assert field_state("   ") == "absent"
    assert field_state([]) == "absent"


# --- Le contrat-fixture réel est valide et complet ---

def test_real_contract_is_complete(contract):
    for f in CRITICAL:
        assert field_state(contract.get(f)) == "filled", f"Critique {f} non rempli"
    for f in IMPORTANT + RECOMMENDED:
        assert field_state(contract.get(f)) != "absent", f"{f} absent"


# --- C2 : le payload borné ---

def test_build_payload_returns_dispatch_payload(contract):
    payload = build_dispatch_payload(contract, etape=FIXTURE)
    assert isinstance(payload, DispatchPayload)


def test_role_critique_injecte_dans_payload(contract):
    """VERROU 1 : le role est injecté dans le payload, pas seulement utilisé."""
    payload = build_dispatch_payload(contract, etape=FIXTURE)
    assert payload.role == contract["role"]
    assert contract["role"] in payload.prompt


def test_model_resolu_par_registry(contract):
    """VERROU 2 (ADR-002 gate 1) : le modèle vient du registry local via
    capability_role — jamais écrit en dur dans le contrat."""
    payload = build_dispatch_payload(contract, etape=FIXTURE)
    assert "modele" not in contract  # aucun modèle en dur
    assert payload.model == resolve_runtime(contract)
    assert payload.model  # rôle résolu => non vide
    # s4-archi = capability_role 'architect' -> Claude Opus (roles.yaml)
    assert "opus" in payload.model.lower()


def test_capability_role_non_resolu_refuse(contract):
    """Un rôle que le registry ne résout pas => contrat non activable."""
    bad = copy.deepcopy(contract)
    bad["capability_role"] = "role_inexistant_xyz"
    with pytest.raises(RoleUnresolved):
        build_dispatch_payload(bad, etape=FIXTURE)


def test_prompt_porte_le_cadre_et_la_regle_de_restitution(contract):
    payload = build_dispatch_payload(contract, etape=FIXTURE)
    for champ in ("objectif", "in_scope", "out_of_scope", "gardeFou",
                  "success_criteria", "output_contract"):
        assert contract[champ] in payload.prompt, f"{champ} absent du prompt"
    assert "NO_CLAIM_ALLOWED" in payload.prompt
    assert "HumanGate" in payload.prompt  # la règle de restitution


def test_seuls_les_outils_declares_sont_autorises(contract):
    payload = build_dispatch_payload(contract, etape=FIXTURE)
    # le contrat-fixture a skill + plugin remplis
    assert contract["skill"] in payload.allowed_tools
    assert contract["plugin"] in payload.allowed_tools


def test_mandatory_read_present_dans_payload(contract):
    payload = build_dispatch_payload(contract, etape=FIXTURE)
    assert tuple(contract["mandatory_read"]) == payload.mandatory_read


# --- R2 (audit branchements 2026-07-24) : marqueur FORGE_DISPATCH injecté ---

def test_prompt_porte_le_marqueur_forge_dispatch_matchant_la_regex_du_hook(contract):
    """Avant ce correctif, le marqueur FORGE_DISPATCH:<etape>:<run_id> attendu par
    hook_guard.MARKER était apposé À LA MAIN par l'orchestrateur — build_dispatch_
    payload (donc _render_prompt) ne l'injectait pas. Avec run_id fourni, le prompt
    DOIT contenir exactement un marqueur valide, avec les vraies valeurs."""
    from forge.hook_guard import MARKER, marker_key
    payload = build_dispatch_payload(contract, etape=FIXTURE, run_id="run-42")
    matches = MARKER.findall(payload.prompt)
    assert len(matches) == 1, f"un seul marqueur attendu, trouvé: {matches}"
    # Le rendu émet la forme 2-champs ; `marker_key` la normalise en triplet avec
    # attempt=0 (rétro-compat assumée par hook_guard.MARKER, 3e groupe optionnel).
    assert marker_key(payload.prompt) == (FIXTURE, "run-42", 0)


def test_marqueur_absent_sans_run_id_comportement_inchange(contract):
    """Sans run_id (comme tous les appels directs existants, ex. tests C1/C2 ci-
    dessus) : aucun marqueur — comportement STRICTEMENT inchangé pour un appel de
    build_dispatch_payload hors du contexte d'un run réel."""
    from forge.hook_guard import MARKER_TOKEN
    payload = build_dispatch_payload(contract, etape=FIXTURE)
    assert MARKER_TOKEN not in payload.prompt


# --- C1 : la porte qui bloque ---

def test_critique_absent_refuse(contract):
    bad = copy.deepcopy(contract)
    del bad["permissions"]  # un Critique
    with pytest.raises(ContractIncomplete):
        build_dispatch_payload(bad, etape=FIXTURE)


def test_critique_declare_vide_refuse(contract):
    """Un Critique à `aucun` = oubli déguisé : refusé."""
    bad = copy.deepcopy(contract)
    bad["objectif"] = "aucun"
    with pytest.raises(ContractIncomplete):
        build_dispatch_payload(bad, etape=FIXTURE)


def test_critique_vide_refuse(contract):
    bad = copy.deepcopy(contract)
    bad["gardeFou"] = ""
    with pytest.raises(ContractIncomplete):
        build_dispatch_payload(bad, etape=FIXTURE)


def test_optionnel_absent_refuse(contract):
    """skill/plugin peuvent valoir `aucun` mais jamais être absents."""
    bad = copy.deepcopy(contract)
    del bad["skill"]
    with pytest.raises(ContractIncomplete):
        build_dispatch_payload(bad, etape=FIXTURE)


def test_optionnel_declare_vide_passe(contract):
    ok = copy.deepcopy(contract)
    ok["skill"] = "aucun"
    payload = build_dispatch_payload(ok, etape=FIXTURE)
    # `aucun` n'apparaît pas comme outil autorisé
    assert "aucun" not in [t.lower() for t in payload.allowed_tools]


# --- VERROU 4 : aucun spawn en C1/C2 ---

def test_aucun_spawn_dans_le_module():
    """Le module produit un payload ou refuse — il ne lance jamais de process/agent."""
    source = Path(__file__).resolve().parents[1].joinpath("contract.py").read_text(encoding="utf-8")
    for interdit in ("subprocess", "Popen", "os.system", "Agent(", "run_oracle"):
        assert interdit not in source, f"spawn interdit détecté : {interdit}"

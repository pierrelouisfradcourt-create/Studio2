"""Capstone — prouve que TOUTE la chaîne Forge est gouvernée par contrat.

Chaque étape-agent a un contrat complet + activable (runtime résolu : modèle LLM
pour les producteurs/reviewer, 'non-llm' pour les étapes déterministes). Un contrat
dont on vide un Critique est refusé. Aucun spawn.
"""
import copy

import pytest

from forge.contract import (
    CONTRACTS_DIR,
    ContractIncomplete,
    build_dispatch_payload,
    load_contract,
)

# Les 13 étapes-agents de la chaîne Forge (chacune a un contrat).
CHAIN = [
    "s0-contrat",
    "s1-prisme",
    "s2-worldscan",
    "s3-decompo",
    "s4-archi",
    "s5-wiremap",
    "s6-redteam-plan",
    "s9-build",
    "s10a-oracle-code",
    "s10b-oracle-archi",
    "s10c-oracle-wiremap",
    "s11-redteam-code",
    "s12-verdict",
]

DETERMINISTIC = {"s10a-oracle-code", "s10b-oracle-archi", "s10c-oracle-wiremap", "s12-verdict"}


def test_chain_files_present():
    on_disk = {p.stem for p in CONTRACTS_DIR.glob("*.yaml") if p.stem != "roles"}
    missing = set(CHAIN) - on_disk
    assert not missing, f"contrats manquants: {missing}"


@pytest.mark.parametrize("cid", CHAIN)
def test_chain_contract_activable(cid):
    payload = build_dispatch_payload(load_contract(cid), etape=cid)
    assert payload.model, f"{cid}: runtime non résolu"
    if cid in DETERMINISTIC:
        assert payload.model == "non-llm", f"{cid}: étape déterministe doit résoudre 'non-llm'"
    else:
        assert payload.model != "non-llm", f"{cid}: étape LLM ne doit pas être 'non-llm'"
    assert payload.role in payload.prompt
    assert "NO_CLAIM_ALLOWED" in payload.prompt


@pytest.mark.parametrize("cid", CHAIN)
def test_chain_contract_refuses_when_broken(cid):
    broken = copy.deepcopy(load_contract(cid))
    broken["objectif"] = ""  # un Critique vidé => oubli
    with pytest.raises(ContractIncomplete):
        build_dispatch_payload(broken, etape=cid)

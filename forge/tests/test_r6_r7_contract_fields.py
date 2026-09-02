"""Oracle des renforcements de contrat R6/R7 (FORGE_V2_CONSOLIDATION.md §4-A).

R6 : s3-decompo/s4-archi lisent le knowledge_packet du run (mandatory_read, advisory)
-- ferme l'orphelinat structurel constaté (recherches web citées jamais routées).
R7 : s0-contrat exige un design-intent (plateforme_cible/reference_jeu/criteres_demo[])
au charter -- reference_jeu choisi par PIERRE, jamais par un agent, sinon fog HumanGate.

Ces tests lisent les VRAIS fichiers de contrat sur disque (pas de copie) et prouvent
que prepare_dispatch reste activable après édition -- même charge de preuve que
test_contract_chain.py/test_dispatch.py (qui couvrent déjà les 13 étapes canoniques,
donc ces 3 contrats), simplement ciblée sur le contenu ajouté. NO_CLAIM_ALLOWED.
"""
from forge.contract import build_dispatch_payload, load_contract
from forge.dispatch import prepare_dispatch


# --- R6 : knowledge_packet routé au mandatory_read de s3/s4 ------------------------

def test_s3_decompo_mandatory_read_cites_knowledge_packet():
    contract = load_contract("s3-decompo")
    reads = contract["mandatory_read"]
    assert any("knowledge_packet.json" in r for r in reads)
    assert any("ADVISORY" in r for r in reads)  # jamais prescriptif


def test_s4_archi_mandatory_read_cites_knowledge_packet():
    contract = load_contract("s4-archi")
    reads = contract["mandatory_read"]
    assert any("knowledge_packet.json" in r for r in reads)
    assert any("ADVISORY" in r for r in reads)


def test_s3_decompo_still_activable_after_r6(tmp_path):
    audit = tmp_path / "audit.jsonl"
    payload = prepare_dispatch("s3-decompo", run_id="r6-s3", audit_path=audit)
    assert payload.model
    assert any("knowledge_packet" in r for r in payload.mandatory_read)


def test_s4_archi_still_activable_after_r6(tmp_path):
    audit = tmp_path / "audit.jsonl"
    payload = prepare_dispatch("s4-archi", run_id="r6-s4", audit_path=audit)
    assert payload.model
    assert any("knowledge_packet" in r for r in payload.mandatory_read)


# --- R7 : design-intent obligatoire au charter (s0-contrat) ------------------------

def test_s0_contrat_objectif_requires_design_intent_fields():
    contract = load_contract("s0-contrat")
    for champ in ("plateforme_cible", "reference_jeu", "criteres_demo"):
        assert champ in contract["objectif"], f"{champ} absent de l'objectif"
        assert champ in contract["output_contract"], f"{champ} absent de output_contract"


def test_s0_contrat_gardefou_forbids_agent_invented_reference_jeu():
    contract = load_contract("s0-contrat")
    garde = contract["gardeFou"]
    assert "reference_jeu" in garde
    assert "fog HumanGate" in garde
    assert "Pierre" in garde


def test_s0_contrat_still_activable_after_r7(tmp_path):
    audit = tmp_path / "audit.jsonl"
    payload = prepare_dispatch("s0-contrat", run_id="r7-s0", audit_path=audit)
    assert payload.model
    assert "reference_jeu" in payload.prompt
    assert "plateforme_cible" in payload.prompt
    assert "criteres_demo" in payload.prompt
    assert "NO_CLAIM_ALLOWED" in payload.prompt


def test_s0_contrat_still_refuses_when_a_critical_field_is_emptied():
    """Non-régression : le renfort R7 ne doit pas assouplir la porte C1 — un Critique
    vidé (ex. objectif) refuse toujours le dispatch."""
    import copy

    from forge.contract import ContractIncomplete

    broken = copy.deepcopy(load_contract("s0-contrat"))
    broken["objectif"] = ""
    try:
        build_dispatch_payload(broken, etape="s0-contrat")
        assert False, "un objectif vide aurait dû être refusé"
    except ContractIncomplete:
        pass

"""Oracle de la primitive `skipped_validation[]` (ratification Pierre 2026-07-26,
primitive 1 du salvage Codex — `studio_brain/decisions/
PROPOSED_2026-07-26_ratifications.md`).

Généralise aux 21 contrats une exigence déjà présente en prose dans un seul
(`orchestrator.yaml` : « ce que je n'ai PAS prouvé »). Deux livrables, prouvés ici :

1. `contract.RESTITUTION_RULE` (injectée verbatim dans les 21 prompts) exige une
   section finale SKIPPED_VALIDATION structurée : item / périmètre / statut / raison
   par validation sautée, sentinelle `aucun` autorisée quand rien n'a été sauté.
2. `skipped_validation.skipped_validation_status` mesure l'ADOPTION réelle sur la
   sortie texte d'un agent : "filled" / "declared_empty" / "absent" — le point de
   mesure qui manquait au corpus Codex (déclaratif sans lecteur => mort).

ADVISORY UNIQUEMENT : aucun test ici ne touche software_verdict/gate/verify_run.
"""
from forge.contract import build_dispatch_payload, load_contract, RESTITUTION_RULE
from forge.skipped_validation import skipped_validation_status

FIXTURE = "s4-archi"  # même contrat-fixture réel que test_contract.py


# --- 1. La règle de restitution porte l'exigence, verbatim, dans les 21 prompts ---

def test_restitution_rule_mentions_skipped_validation_header():
    assert "SKIPPED_VALIDATION" in RESTITUTION_RULE


def test_restitution_rule_requires_item_perimetre_statut_raison():
    for mot in ("item", "périmètre", "statut", "raison"):
        assert mot in RESTITUTION_RULE, f"{mot!r} absent de RESTITUTION_RULE"


def test_restitution_rule_permits_sentinelle_aucun():
    assert "SKIPPED_VALIDATION: aucun" in RESTITUTION_RULE


def test_prompt_reel_porte_la_section_skipped_validation():
    """Preuve d'intégration : un vrai contrat, via la vraie porte, porte la
    section dans son prompt final — pas seulement dans la constante isolée."""
    contract = load_contract(FIXTURE)
    payload = build_dispatch_payload(contract, etape=FIXTURE)
    assert "SKIPPED_VALIDATION" in payload.prompt
    # les marqueurs existants (NO_CLAIM_ALLOWED, HumanGate) restent intacts
    assert "NO_CLAIM_ALLOWED" in payload.prompt
    assert "HumanGate" in payload.prompt


# --- 2. skipped_validation_status : la mesure d'adoption --------------------------

# absent — silence pur, ou entrées dégénérées

def test_absent_quand_aucune_section():
    texte = "## RAPPORT FINAL\nsoftware_verdict: OK\nevidence_verdict: MECHANICAL_VALIDATION_ONLY\n"
    assert skipped_validation_status(texte) == "absent"


def test_absent_quand_sortie_vide():
    assert skipped_validation_status("") == "absent"
    assert skipped_validation_status("   \n\t  ") == "absent"


def test_absent_quand_sortie_none():
    assert skipped_validation_status(None) == "absent"


def test_absent_quand_mot_mentionne_hors_section():
    texte = (
        "Je n'ai pas structuré skipped_validation cette fois-ci, "
        "je le ferai au prochain run.\n"
    )
    assert skipped_validation_status(texte) == "absent"


def test_absent_quand_header_present_mais_corps_vide():
    """Header présent mais rien dessous == oubli, PAS une déclaration assumée."""
    texte = "## SKIPPED_VALIDATION\n\n## AUTRE SECTION\ncontenu sans rapport\n"
    assert skipped_validation_status(texte) == "absent"


# declared_empty — la sentinelle `aucun`, sous ses variantes

def test_declared_empty_forme_en_ligne():
    texte = "Tout est prouvé.\nSKIPPED_VALIDATION: aucun\n"
    assert skipped_validation_status(texte) == "declared_empty"


def test_declared_empty_section_avec_corps_aucun():
    texte = "## SKIPPED_VALIDATION\naucun\n\n## AUTRE\nsuite\n"
    assert skipped_validation_status(texte) == "declared_empty"


def test_declared_empty_casse_et_ponctuation_variables():
    for variante in (
        "skipped_validation: AUCUN",
        "Skipped_Validation: Aucun.",
        "SKIPPED VALIDATION: aucun",  # espace au lieu d'underscore
    ):
        assert skipped_validation_status(variante) == "declared_empty", variante


def test_declared_empty_puce_markdown_autour_de_la_sentinelle():
    texte = "## skipped_validation\n- aucun\n"
    assert skipped_validation_status(texte) == "declared_empty"


# filled — au moins une entrée réelle

def test_filled_une_entree():
    texte = (
        "## SKIPPED_VALIDATION\n"
        "- item: perf régression | périmètre: search.rs | statut: non fait | "
        "raison: hors délai de la session\n"
    )
    assert skipped_validation_status(texte) == "filled"


def test_filled_plusieurs_entrees():
    texte = (
        "## SKIPPED_VALIDATION\n"
        "- item: test e2e visuel | périmètre: godot | statut: non fait | raison: pas de GPU dispo\n"
        "- item: mutation testing | périmètre: engine | statut: partiel | raison: timeout CI\n"
        "- item: solvabilité 5 volets | périmètre: R9 | statut: non fait | raison: hors scope de ce run\n"
    )
    assert skipped_validation_status(texte) == "filled"


def test_filled_section_bornee_par_le_prochain_header():
    """Le corps s'arrête au prochain header markdown : pas de fuite inter-sections."""
    texte = (
        "## SKIPPED_VALIDATION\n"
        "- item: audit sécurité | périmètre: api | statut: non fait | raison: hors scope\n"
        "\n## RAPPORT FINAL\nsoftware_verdict: OK\n"
    )
    assert skipped_validation_status(texte) == "filled"

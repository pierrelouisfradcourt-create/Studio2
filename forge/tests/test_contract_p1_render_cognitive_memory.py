"""Oracle P1 (lot dégel 2, docs/forge/FORGE_CONTEXT_COMPACT_V1.md §05.2 /
§07 P1) : `exigences_cognitives` et `memoire` sont CRITIQUES (contrat REFUSÉ
si vides, `contract.py::CRITICAL`) mais n'atteignaient jamais le prompt rendu
par `_render_prompt` — validés puis jetés. Prouve que le texte RÉEL de ces
deux champs atteint le prompt final, dans l'ordre CRITICAL (juste après
`role`, avant `objectif`), en respectant la règle des 3 états (`aucun`/
declared_empty => section omise), et sans régresser les sections existantes
(ordre, marqueur FORGE_DISPATCH).

Fichier NEUF (forge/tests/**, régime studio normal) — n'altère aucun
test existant. NO_CLAIM_ALLOWED.
"""
from __future__ import annotations

import copy

from forge.contract import build_dispatch_payload, load_contract

# Contrat réel gravé dans le dépôt : mandatory_read (2bis) le décrit comme le
# "patron à calquer" pour les jeux Godot — memoire non triviale, distinctive.
GODOT_FIXTURE = "s9-build-godot-standard"
# Contrat réel déjà utilisé par la suite existante (test_contract.py) — sert
# de témoin de non-régression sur les sections déjà rendues.
ARCHI_FIXTURE = "s4-archi"


def test_le_texte_memoire_du_contrat_s9_atteint_le_prompt_rendu():
    """Preuve de complétion : le texte RÉEL de `memoire` (s9-build-godot-standard,
    pas un extrait fabriqué) est présent tel quel dans le prompt produit."""
    contract = load_contract(GODOT_FIXTURE)
    payload = build_dispatch_payload(contract, etape=GODOT_FIXTURE)
    assert contract["memoire"] in payload.prompt
    assert "C'est le patron à calquer, pas à réinventer." in payload.prompt
    assert "## MÉMOIRE DE TRAVAIL" in payload.prompt


def test_le_texte_exigences_cognitives_du_contrat_s9_atteint_le_prompt_rendu():
    contract = load_contract(GODOT_FIXTURE)
    payload = build_dispatch_payload(contract, etape=GODOT_FIXTURE)
    assert contract["exigences_cognitives"] in payload.prompt
    assert "## EXIGENCES COGNITIVES" in payload.prompt


def test_les_deux_sections_sont_rendues_juste_apres_le_role_avant_objectif():
    """Ordre CRITICAL : role -> exigences_cognitives -> memoire -> ... -> objectif."""
    contract = load_contract(GODOT_FIXTURE)
    payload = build_dispatch_payload(contract, etape=GODOT_FIXTURE)
    prompt = payload.prompt
    i_role = prompt.index("## RÔLE")
    i_exig = prompt.index("## EXIGENCES COGNITIVES")
    i_mem = prompt.index("## MÉMOIRE DE TRAVAIL")
    i_obj = prompt.index("## OBJECTIF")
    assert i_role < i_exig < i_mem < i_obj


def test_valeur_aucun_ne_produit_pas_de_section_exigences_cognitives():
    """Règle des 3 états : une valeur declared_empty (`aucun`) est une décision
    assumée — elle ne doit PAS apparaître comme section de prompt."""
    contract = copy.deepcopy(load_contract(GODOT_FIXTURE))
    contract["exigences_cognitives"] = "aucun"
    contract["memoire"] = "aucun"
    from forge.contract import _render_prompt
    prompt = _render_prompt(contract)
    assert "## EXIGENCES COGNITIVES" not in prompt
    assert "## MÉMOIRE DE TRAVAIL" not in prompt


def test_valeur_absente_ne_produit_pas_de_section_mais_le_contrat_est_refuse_en_amont():
    """Un champ CRITIQUE absent refuse le contrat AVANT le rendu (C1) — mais
    `_render_prompt` elle-même, appelée directement (hors porte), ne doit
    jamais planter ni halluciner une section sur une valeur absente."""
    contract = copy.deepcopy(load_contract(GODOT_FIXTURE))
    del contract["memoire"]
    from forge.contract import _render_prompt
    prompt = _render_prompt(contract)
    assert "## MÉMOIRE DE TRAVAIL" not in prompt


# --- non-régression : sections existantes, ordre, marqueur FORGE_DISPATCH -------

def test_sections_existantes_toujours_presentes_et_dans_leur_ordre_relatif():
    contract = load_contract(ARCHI_FIXTURE)
    payload = build_dispatch_payload(contract, etape=ARCHI_FIXTURE)
    prompt = payload.prompt
    ordered_markers = [
        "## RÔLE", "## OBJECTIF", "## DANS LE PÉRIMÈTRE (in_scope)",
        "## HORS PÉRIMÈTRE (out_of_scope)", "## PERMISSIONS", "## GARDE-FOU",
        "## CRITÈRES DE RÉUSSITE", "## ORACLES / TESTS", "## CONTRAT DE SORTIE",
        "## RAPPORT FINAL", "## À LIRE OBLIGATOIREMENT AVANT TOUTE ACTION",
    ]
    positions = [prompt.index(m) for m in ordered_markers]
    assert positions == sorted(positions), "l'ordre relatif des sections existantes a régressé"
    for champ in ("objectif", "in_scope", "out_of_scope", "gardeFou",
                  "success_criteria", "output_contract"):
        assert contract[champ] in prompt, f"{champ} absent du prompt (régression)"


def test_marqueur_forge_dispatch_toujours_injecte_avec_run_id():
    from forge.hook_guard import MARKER, marker_key
    contract = load_contract(ARCHI_FIXTURE)
    payload = build_dispatch_payload(contract, etape=ARCHI_FIXTURE, run_id="run-p1-nonreg")
    matches = MARKER.findall(payload.prompt)
    assert len(matches) == 1, f"un seul marqueur attendu, trouvé: {matches}"
    assert marker_key(payload.prompt) == (ARCHI_FIXTURE, "run-p1-nonreg", 0)

"""Mission A1 (paquet A décision 1, ratifiée Pierre 2026-08-28) : les 2 contrats YAML
manquants des étapes asset.

CONTEXTE DU DÉFAUT : `asset_dispatch.py:57` (ETAPE="s-asset-produce") et `:62`
(ETAPE_SPEC="s-asset-spec") définissent ces deux étapes EN DUR et 96 spawns réels
signés existent dans `EVIDENCE/bundles/dispatch_audit.jsonl` — sans aucun contrat
YAML sous `forge/contracts/`. Violation de l'invariant ADR-002 « aucun
sous-agent sans contrat validé ». Ce test prouve que les 2 contrats écrits sous A1
CHARGENT, VALIDENT et RENDENT correctement via la porte `forge.contract` — mais ne
prouve PAS que `asset_dispatch.py` les consomme : ce module a son PROPRE chemin de
résolution (`resolve_role`/`resolve_runtime` locaux, jamais `forge.contract`), donc
la porte réelle continue de ne pas charger ces 2 contrats tant qu'aucun câblage
n'est fait côté `asset_dispatch.py` — hors périmètre strict de cette mission (voir
rapport A1).
"""
from __future__ import annotations

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

CONTRACTS_DIR = Path(__file__).resolve().parents[1] / "contracts"


# --- 1. Les 2 fichiers existent (chemins exacts qu'`asset_dispatch.py` nomme en dur) ---

def test_s_asset_produce_file_exists():
    assert (CONTRACTS_DIR / "s-asset-produce.yaml").is_file()


def test_s_asset_spec_file_exists():
    assert (CONTRACTS_DIR / "s-asset-spec.yaml").is_file()


# --- 2. load_contract("s-asset-produce") / ("s-asset-spec") passe ---
# (`load_contract` mappe nom -> fichier par simple concat "<etape>.yaml" -- pas
# d'alias de round ici puisqu'aucun de ces deux noms ne matche `-r<N>`, cf.
# `forge.contract.base_step`.)

@pytest.fixture
def produce_contract() -> dict:
    return load_contract("s-asset-produce")


@pytest.fixture
def spec_contract() -> dict:
    return load_contract("s-asset-spec")


def test_load_contract_s_asset_produce(produce_contract):
    assert isinstance(produce_contract, dict)


def test_load_contract_s_asset_spec(spec_contract):
    assert isinstance(spec_contract, dict)


# --- 3. validate_contract OK (aucun Critique non-filled) ---
# `validate_contract` lève ContractIncomplete si un problème existe -- on prouve
# l'absence de levée, et en prime on prouve mécaniquement l'état exact de chaque
# champ (miroir de test_real_contract_is_complete dans test_contract.py).

def _assert_schema_complete(contract: dict) -> None:
    for f in CRITICAL:
        assert field_state(contract.get(f)) == "filled", f"Critique {f!r} non rempli"
    for f in IMPORTANT + RECOMMENDED:
        assert field_state(contract.get(f)) != "absent", f"{f!r} absent"


def test_produce_contract_schema_complete(produce_contract):
    _assert_schema_complete(produce_contract)


def test_spec_contract_schema_complete(spec_contract):
    _assert_schema_complete(spec_contract)


def test_produce_contract_validate_ok(produce_contract):
    from forge.contract import validate_contract
    validate_contract(produce_contract)  # ne lève pas => OK


def test_spec_contract_validate_ok(spec_contract):
    from forge.contract import validate_contract
    validate_contract(spec_contract)  # ne lève pas => OK


# --- 4. resolve_runtime ---
# s-asset-spec : capability_role=asset_spec_author, déjà déclaré dans roles.yaml
# (rôle du worker Qwen réel, cf. asset_dispatch.py::author_spec / SPEC_RUNTIME_ID) —
# se résout réellement.
#
# s-asset-produce : capability_role=asset_producer, déclaré comme MISSION/CONTRAT
# D'E-S dans `roles.yaml::runtime_contracts.asset_producer` (mission réelle :
# géométrie procédurale Blender, `implementation.model: aucun`) mais PAS dans la
# liste `models:` que consomme `control_plane.registry.get_model_for_role` — ce
# rôle ne s'est JAMAIS résolu par ce canal. Documenté ici comme un GAP RÉEL, non
# corrigé par cette mission (périmètre strict A1 : écrire les contrats, pas
# modifier roles.yaml sans nécessité pour `validate_contract`, qui n'en a pas
# besoin -- voir rapport A1). Le test fige ce gap plutôt que de le masquer.

def test_spec_contract_resolve_runtime_resolves(spec_contract):
    model = resolve_runtime(spec_contract)
    assert model, "capability_role de s-asset-spec doit se résoudre via le registry"


def test_produce_contract_capability_role_is_asset_producer(produce_contract):
    assert produce_contract["capability_role"] == "asset_producer"


def test_produce_contract_resolve_runtime_currently_unresolved(produce_contract):
    """GAP DOCUMENTÉ (pas corrigé ici) : `asset_producer` n'est déclaré nulle part
    dans `roles.yaml::models[].roles` -- seulement sous `runtime_contracts`, une
    section informative pour `control_plane.registry` (qui ne lit que `models`).
    Si ce test se met à passer un jour (`asset_producer` ajouté aux `models:`),
    c'est le signal que le gap a été comblé -- il faudra alors mettre à jour ce
    test, pas le supprimer silencieusement."""
    with pytest.raises(RoleUnresolved):
        resolve_runtime(produce_contract)


# --- 5. _render_prompt rend sans erreur, avec un marqueur ---
# `build_dispatch_payload` appelle validate_contract + resolve_runtime + _render_prompt
# + _verify_prompt_layer_rendered dans cet ordre -- pour s-asset-produce, l'appel
# doit échouer précisément sur resolve_runtime (RoleUnresolved), PAS avant (ce qui
# prouverait que validate_contract/le rendu de prompt ont un défaut indépendant du
# gap de rôle). On appelle donc `_render_prompt` directement pour prouver le rendu
# et le marqueur, en contournant `resolve_runtime` -- exactement ce que
# `build_dispatch_payload` NE peut pas faire pour ce contrat aujourd'hui.

from forge.contract import _render_prompt, _verify_prompt_layer_rendered  # noqa: E402


def test_spec_contract_build_dispatch_payload_full_chain(spec_contract):
    """s-asset-spec : la chaîne COMPLÈTE (C1+C2, comme la vraie porte) réussit."""
    payload = build_dispatch_payload(spec_contract, etape="s-asset-spec",
                                     run_id="a1-test-run", attempt=0)
    assert isinstance(payload, DispatchPayload)
    assert payload.role == spec_contract["role"]
    assert "FORGE_DISPATCH:s-asset-spec:a1-test-run:0" in payload.prompt


def test_produce_contract_render_prompt_direct(produce_contract):
    """s-asset-produce : _render_prompt seul (hors resolve_runtime, cf. gap ci-dessus)
    rend sans erreur et porte le marqueur de dispatch quand etape/run_id sont fournis."""
    prompt = _render_prompt(produce_contract, etape="s-asset-produce",
                            run_id="a1-test-run", attempt=0)
    assert isinstance(prompt, str) and prompt
    assert "FORGE_DISPATCH:s-asset-produce:a1-test-run:0" in prompt
    # couche prompt : tout champ LAYER_PROMPT rempli doit être rendu (même garde que
    # la vraie porte -- ne lève pas si le contrat est honnête).
    _verify_prompt_layer_rendered(produce_contract, prompt)


def test_produce_contract_build_dispatch_payload_raises_role_unresolved(produce_contract):
    """La chaîne complète échoue au bon endroit (résolution du rôle), pas ailleurs."""
    with pytest.raises(RoleUnresolved):
        build_dispatch_payload(produce_contract, etape="s-asset-produce",
                               run_id="a1-test-run", attempt=0)


# --- 6. Contenu fidèle à la réalité du mécanisme (pas une fiction) ---
# Ancrages factuels contre le vrai code, pour empêcher une dérive doc<->réalité
# future (même esprit que test_roles_registry_integrity / test_asset_worker_contract).

ASSET_DISPATCH = (Path(__file__).resolve().parents[1] / "asset_producer" / "asset_dispatch.py")


def test_produce_contract_cites_real_oracle(produce_contract):
    assert "forge/asset_geometry/oracle.py" in produce_contract["tests_oracles"]


def test_produce_contract_cites_real_entrypoint(produce_contract):
    joined = " ".join(str(produce_contract.get(k, "")) for k in
                      ("memoire", "objectif", "in_scope"))
    assert "build_asset.py" in joined or "asset_dispatch" in joined


def test_spec_contract_cites_real_worker(spec_contract):
    joined = " ".join(str(spec_contract.get(k, "")) for k in
                      ("memoire", "objectif", "in_scope"))
    assert "qwen_spec.py" in joined


def test_asset_dispatch_still_bypasses_the_contract_gate():
    """Fige le constat CONTEXTE du rapport A1 : `asset_dispatch.py` ne référence
    JAMAIS `forge.contract` -- la porte reste parallèle tant qu'aucun câblage n'est
    fait. Si ce test échoue un jour, c'est que le câblage a été fait ailleurs (bien)
    -- mettre à jour ce test pour refléter la nouvelle réalité, pas le supprimer."""
    src = ASSET_DISPATCH.read_text(encoding="utf-8")
    assert "forge.contract" not in src
    assert "load_contract" not in src
    assert "build_dispatch_payload" not in src

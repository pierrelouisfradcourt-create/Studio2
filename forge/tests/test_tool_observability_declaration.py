"""Maillon 1 (déclaration, typée) — forge.tool_observability.read_declared_tools /
classify_declared_value / scan_all_contracts.

Ne modifie ni ne relit `forge.contract._declared_tools` (trou I4, laissé ouvert
par mandat) : ce module a sa PROPRE lecture, sur les mêmes champs de contrat.
"""
from __future__ import annotations

from forge import tool_observability as obs
from forge.contract import load_contract


def test_sentinelle_aucun_est_empty():
    assert obs.classify_declared_value("aucun") == obs.DECLARATION_KIND_EMPTY


def test_absent_est_empty():
    assert obs.classify_declared_value(None) == obs.DECLARATION_KIND_EMPTY
    assert obs.classify_declared_value("") == obs.DECLARATION_KIND_EMPTY


def test_slug_sans_espace_est_identifier():
    for value in ("forge", "world-scan", "architecture-review", "plugin:skill_x"):
        assert obs.classify_declared_value(value) == obs.DECLARATION_KIND_IDENTIFIER, value


def test_phrase_avec_espaces_est_prose():
    """C'est le cœur du maillon 1 : une phrase française n'est PAS un
    identifiant d'outil, même si `contract.field_state` la dit 'filled'."""
    value = "graph-coloring anti-collision (_ceo_assign_lanes ressuscité) pour l'ownership."
    assert obs.classify_declared_value(value) == obs.DECLARATION_KIND_PROSE


def test_negatif_une_classification_naive_confondrait_prose_et_identifiant():
    """Test NÉGATIF du maillon 1 : si la fonction se contentait de vérifier
    `field_state(...) == 'filled'` (le comportement actuel de
    `contract._declared_tools`, trou I4), la phrase ci-dessus ET un vrai slug
    seraient logés IDENTIQUEMENT — ce test échouerait si `classify_declared_value`
    dégénérait en un simple alias de `field_state`."""
    from forge.contract import field_state

    prose = "graph-coloring anti-collision (_ceo_assign_lanes ressuscité) pour l'ownership."
    identifier = "architecture-review"
    # Les deux sont 'filled' au sens de contract.field_state — la distinction
    # PROSE vs IDENTIFIER n'existe QUE dans classify_declared_value.
    assert field_state(prose) == field_state(identifier) == "filled"
    assert obs.classify_declared_value(prose) != obs.classify_declared_value(identifier)
    assert obs.classify_declared_value(prose) == obs.DECLARATION_KIND_PROSE
    assert obs.classify_declared_value(identifier) == obs.DECLARATION_KIND_IDENTIFIER


def test_read_declared_tools_sur_contrat_reel_s4_archi():
    """Mesure de PRODUCTION (contrat réel, pas une fixture inventée) : s4-archi
    porte skill='architecture-review' (identifiant réel) ET plugin=une PHRASE
    (prose réelle) — trouvaille concrète du trou I4, observée ici, pas corrigée."""
    contract = load_contract("s4-archi")
    fields = {f.field: f for f in obs.read_declared_tools(contract)}
    assert fields["skill"].kind == obs.DECLARATION_KIND_IDENTIFIER
    assert fields["skill"].raw == "architecture-review"
    assert fields["plugin"].kind == obs.DECLARATION_KIND_PROSE
    assert " " in fields["plugin"].raw  # c'est une phrase, pas un token


def test_read_declared_tools_sur_contrat_reel_s9_build_tout_vide():
    """La majorité des contrats réels (44) déclarent skill/plugin='aucun' —
    EMPTY, jamais confondu avec 'chargé' (c'est le maillon 2 qui répond à ça)."""
    contract = load_contract("s9-build")
    fields = {f.field: f for f in obs.read_declared_tools(contract)}
    assert fields["skill"].kind == obs.DECLARATION_KIND_EMPTY
    assert fields["skill"].field_state == "declared_empty"
    assert fields["plugin"].kind == obs.DECLARATION_KIND_EMPTY


def test_scan_all_contracts_mesure_de_production():
    """Preuve exigée #5 : chiffres réels, pas une impression. Recompte
    manuellement les 3 identifiants connus (orchestrator/skill, s2-worldscan/
    skill, s4-archi/skill) + le SEUL exemple de prose connu (s4-archi/plugin)."""
    results = obs.scan_all_contracts()
    assert results  # au moins un contrat scanné
    assert all("error" not in r for r in results), [r for r in results if "error" in r]

    counts = {obs.DECLARATION_KIND_EMPTY: 0, obs.DECLARATION_KIND_IDENTIFIER: 0,
              obs.DECLARATION_KIND_PROSE: 0}
    prose_hits = []
    identifier_hits = []
    for r in results:
        for f in r["fields"]:
            counts[f["kind"]] += 1
            if f["kind"] == obs.DECLARATION_KIND_PROSE:
                prose_hits.append((r["etape"], f["field"]))
            if f["kind"] == obs.DECLARATION_KIND_IDENTIFIER:
                identifier_hits.append((r["etape"], f["field"], f["raw"]))

    # Mesure figée le 2026-07-30 (46 contrats : 3 identifiants, 1 prose), RE-FIGÉE
    # le 2026-08-28 après le Paquet A ratifié Pierre (décisions 1 et 7) : +2 contrats
    # asset (s-asset-produce porte `skill: asset-generator`, 4e identifiant) et 25
    # one-shot déplacés vers contracts/archive/ (hors scan, tous EMPTY — n'affectait
    # pas ces comptes). Cf. CLI `python -m forge.tool_observability scan-contracts`.
    assert ("s4-archi", "plugin") in prose_hits
    assert len(prose_hits) == 1, prose_hits
    assert ("orchestrator", "skill", "forge") in identifier_hits
    assert ("s2-worldscan", "skill", "world-scan") in identifier_hits
    assert ("s4-archi", "skill", "architecture-review") in identifier_hits
    assert ("s-asset-produce", "skill", "asset-generator") in identifier_hits
    assert len(identifier_hits) == 4, identifier_hits
    # Le reste (empty) domine largement — le rapport chiffré exact vit dans le
    # rapport de mission (compte total dépendant du nombre de contrats présents).
    assert counts[obs.DECLARATION_KIND_EMPTY] > counts[obs.DECLARATION_KIND_IDENTIFIER]
    assert counts[obs.DECLARATION_KIND_EMPTY] > counts[obs.DECLARATION_KIND_PROSE]


def test_scan_all_contracts_exclut_roles_yaml():
    results = obs.scan_all_contracts()
    assert all(r["etape"] != "roles" for r in results)

"""Jointure expected <-> actual, branchée en ADVISORY (sas 3, J-1, GO Pierre 2026-09-02).

Mesure du sas 3 : `check_wiremap_contract.mjs` fonctionne, rend `exit 1` et nomme la
faute (« omission silencieuse ») — mais **personne ne lisait son verdict**. Des étapes
`s5-wiremap` sont OK avec 0 capacité sur 20 couverte.

Ces tests figent les deux moitiés du branchement :
  - la jointure est MESURÉE et LISIBLE (`join_check` dans le détail de l'étape) ;
  - elle n'a AUCUNE autorité — `advisory: True`, aucun statut modifié, aucun verdict.

Et la discipline d'honnêteté : outil injoignable ou sortie inexploitable rendent
`NOT_MEASURED`, jamais un vert par défaut.

NO_CLAIM_ALLOWED.
"""
from __future__ import annotations

import json
import shutil

import pytest

from forge.run_real import check_wiremap_join

_NODE_ABSENT = shutil.which("node") is None


def _featuremap(cap_ids):
    return {
        "systemes": [{
            "id": "SYS", "features": [{
                "id": "FEAT", "capacites": [
                    {"id": c, "capacite": "c", "source_ref": "R1",
                     "expected_proof": {"kind": "oracle", "statement": "s"}}
                    for c in cap_ids
                ],
            }],
        }],
    }


def _wiremap(couvre_par_ligne):
    return {"features": [
        {"feature": f"L{i}", "fonction": "f", "fichiers": ["a.mjs"],
         "preuve": "p", "version": "1", "statut": "implemented", "couvre": couvre}
        for i, couvre in enumerate(couvre_par_ligne)
    ]}


def _run(tmp_path, fm=None, wm=None):
    if fm is not None:
        (tmp_path / "featuremap.json").write_text(json.dumps(fm), encoding="utf-8")
    if wm is not None:
        (tmp_path / "wiremap.json").write_text(json.dumps(wm), encoding="utf-8")
    return tmp_path


# --- rien à joindre : ne pas inventer de reçu ----------------------------------------

def test_artefact_manquant_rend_none(tmp_path):
    assert check_wiremap_join(tmp_path) is None
    assert check_wiremap_join(_run(tmp_path, fm=_featuremap(["cap_a"]))) is None


# --- la mesure elle-même --------------------------------------------------------------

@pytest.mark.skipif(_NODE_ABSENT, reason="node indisponible")
def test_jointure_tenue(tmp_path):
    run = _run(tmp_path, _featuremap(["cap_a", "cap_b"]),
               _wiremap([["cap_a"], ["cap_b"]]))
    recu = check_wiremap_join(run)
    assert recu["status"] == "JOINED"
    assert recu["capacites_couvertes"] == 2
    assert recu["capacites_non_couvertes"] == 0
    assert recu["couverture_fantome"] == 0


@pytest.mark.skipif(_NODE_ABSENT, reason="node indisponible")
def test_couvre_rempli_avec_des_ids_fantomes(tmp_path):
    """LE mode dominant mesuré : `couvre` non vide — donc conforme à la lettre du
    contrat — mais citant des noms de fonctions. La forme passe, la jointure est vide."""
    run = _run(tmp_path, _featuremap(["cap_a", "cap_b"]),
               _wiremap([["currentObjective"], ["renderHearth"]]))
    recu = check_wiremap_join(run)
    assert recu["status"] == "NOT_JOINED"
    assert recu["capacites_couvertes"] == 0
    assert recu["capacites_non_couvertes"] == 2      # omission silencieuse
    assert recu["couverture_fantome"] == 2           # couvre sans référent
    assert recu["lignes_sans_couvre"] == 0           # ... et pourtant « rempli »
    assert any("cap_a" in e or "currentObjective" in e for e in recu["exemples"])


@pytest.mark.skipif(_NODE_ABSENT, reason="node indisponible")
def test_capacite_non_couverte(tmp_path):
    run = _run(tmp_path, _featuremap(["cap_a", "cap_b"]), _wiremap([["cap_a"]]))
    recu = check_wiremap_join(run)
    assert recu["status"] == "NOT_JOINED"
    assert recu["capacites_couvertes"] == 1
    assert recu["capacites_non_couvertes"] == 1


# --- ADVISORY : aucune autorité --------------------------------------------------------

@pytest.mark.skipif(_NODE_ABSENT, reason="node indisponible")
def test_le_recu_est_advisory_et_ne_porte_aucun_blocage(tmp_path):
    run = _run(tmp_path, _featuremap(["cap_a"]), _wiremap([["fantome"]]))
    recu = check_wiremap_join(run)
    assert recu["advisory"] is True
    assert recu["exit_code"] == 1                    # l'oracle, lui, échoue
    assert "blocked" not in recu                     # ... et n'emporte rien
    assert set(recu) & {"software_verdict", "status_etape"} == set()


# --- honnêteté : jamais un vert par défaut ---------------------------------------------

def test_node_indisponible_rend_not_measured(tmp_path, monkeypatch):
    run = _run(tmp_path, _featuremap(["cap_a"]), _wiremap([["cap_a"]]))
    monkeypatch.setattr("forge.run_real.shutil.which", lambda *_a, **_k: None)
    recu = check_wiremap_join(run)
    assert recu["status"] == "NOT_MEASURED"
    assert recu["advisory"] is True


def test_outil_injoignable_rend_not_measured(tmp_path, monkeypatch):
    run = _run(tmp_path, _featuremap(["cap_a"]), _wiremap([["cap_a"]]))
    monkeypatch.setattr("forge.run_real.shutil.which", lambda *_a, **_k: "node")

    def _raise(*_a, **_k):
        raise FileNotFoundError("node introuvable (simulé)")
    monkeypatch.setattr("forge.run_real.subprocess.run", _raise)
    assert check_wiremap_join(run)["status"] == "NOT_MEASURED"


def test_sortie_sans_json_rend_not_measured(tmp_path, monkeypatch):
    run = _run(tmp_path, _featuremap(["cap_a"]), _wiremap([["cap_a"]]))
    monkeypatch.setattr("forge.run_real.shutil.which", lambda *_a, **_k: "node")

    class _Proc:
        returncode = 0
        stdout = "pas de JSON ici"
        stderr = ""
    monkeypatch.setattr("forge.run_real.subprocess.run", lambda *_a, **_k: _Proc())
    recu = check_wiremap_join(run)
    assert recu["status"] == "NOT_MEASURED"
    assert "JSON" in recu["reason"]


# --- J-2 : cinq régimes, pour que la forme ne puisse plus se lire comme conformité ---

@pytest.mark.skipif(_NODE_ABSENT, reason="node indisponible")
def test_regime_void_forme_tenue_jointure_vide(tmp_path):
    """LE cas piégeux, mesuré sur 6 runs : chaque ligne porte un `couvre` non vide —
    la LETTRE du contrat est satisfaite — et pas une capacité n'est résolue."""
    run = _run(tmp_path, _featuremap(["cap_a", "cap_b"]),
               _wiremap([["currentObjective"], ["renderHearth"]]))
    recu = check_wiremap_join(run)
    assert recu["regime"] == "VOID"
    assert recu["forme_satisfaite"] is True      # ... et c'est exactement le problème
    assert recu["capacites_couvertes"] == 0


@pytest.mark.skipif(_NODE_ABSENT, reason="node indisponible")
def test_regime_not_applicable_rien_a_couvrir(tmp_path):
    """Les 4 runs d'ancienne génération : 0 capacité identifiée. Rien à couvrir, donc
    rien à manquer — ne doit PAS se lire comme la même faute que VOID."""
    run = _run(tmp_path, _featuremap([]), _wiremap([["peu_importe"]]))
    assert check_wiremap_join(run)["regime"] == "NOT_APPLICABLE"


@pytest.mark.skipif(_NODE_ABSENT, reason="node indisponible")
def test_regime_empty_form_lettre_du_contrat_violee(tmp_path):
    wm = _wiremap([["x"]])
    del wm["features"][0]["couvre"]
    run = _run(tmp_path, _featuremap(["cap_a"]), wm)
    recu = check_wiremap_join(run)
    assert recu["regime"] == "EMPTY_FORM"
    assert recu["forme_satisfaite"] is False


@pytest.mark.skipif(_NODE_ABSENT, reason="node indisponible")
def test_regime_partial(tmp_path):
    run = _run(tmp_path, _featuremap(["cap_a", "cap_b"]), _wiremap([["cap_a"]]))
    assert check_wiremap_join(run)["regime"] == "PARTIAL"


@pytest.mark.skipif(_NODE_ABSENT, reason="node indisponible")
def test_regime_partial_si_un_seul_fantome(tmp_path):
    """Couverture complète mais un `couvre` sans référent : ce n'est pas JOINED."""
    run = _run(tmp_path, _featuremap(["cap_a"]), _wiremap([["cap_a"], ["fantome"]]))
    recu = check_wiremap_join(run)
    assert recu["couverture_fantome"] == 1
    assert recu["regime"] == "PARTIAL"


@pytest.mark.skipif(_NODE_ABSENT, reason="node indisponible")
def test_regime_joined(tmp_path):
    run = _run(tmp_path, _featuremap(["cap_a", "cap_b"]),
               _wiremap([["cap_a"], ["cap_b"]]))
    assert check_wiremap_join(run)["regime"] == "JOINED"


def test_regime_not_measured_quand_l_outil_manque(tmp_path, monkeypatch):
    run = _run(tmp_path, _featuremap(["cap_a"]), _wiremap([["cap_a"]]))
    monkeypatch.setattr("forge.run_real.shutil.which", lambda *_a, **_k: None)
    assert check_wiremap_join(run)["regime"] == "NOT_MEASURED"


def test_les_regimes_sont_exclusifs_et_declares():
    from forge.run_real import JOIN_REGIMES, _join_regime
    vus = set()
    for stats, fant in (
        ({"capacites": 0, "capacites_couvertes": 0, "lignes": 2, "lignes_sans_couvre": 0}, 0),
        ({"capacites": 2, "capacites_couvertes": 0, "lignes": 2, "lignes_sans_couvre": 2}, 0),
        ({"capacites": 2, "capacites_couvertes": 0, "lignes": 2, "lignes_sans_couvre": 0}, 2),
        ({"capacites": 2, "capacites_couvertes": 1, "lignes": 2, "lignes_sans_couvre": 0}, 0),
        ({"capacites": 2, "capacites_couvertes": 2, "lignes": 2, "lignes_sans_couvre": 0}, 0),
    ):
        regime, _ = _join_regime(stats, fant)
        assert regime in JOIN_REGIMES
        vus.add(regime)
    assert vus == set(JOIN_REGIMES)          # les cinq régimes sont atteignables


def test_join_regime_ne_leve_jamais_sur_des_stats_absurdes():
    from forge.run_real import _join_regime
    for stats in ({}, {"capacites": None}, {"capacites": "deux"}, {"lignes": -5}):
        regime, forme = _join_regime(stats, 0)
        assert isinstance(regime, str) and isinstance(forme, bool)

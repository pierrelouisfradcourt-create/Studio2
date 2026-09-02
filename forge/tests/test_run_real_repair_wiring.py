"""Câblage de REPAIR_LOOP_V1 dans l'exécuteur réel.

Ce que ces tests protègent :
- la boucle est branchée sur les 5 étapes AMONT, et sur elles seules ;
- elle ne tourne JAMAIS sur une étape post-build (s10b/s10c gardent leurs oracles
  de preuve finale, `check_architecture` / `check_wiremap`) ;
- elle ne peut pas faire tomber l'étape qu'elle est censée améliorer : node absent,
  réparateur injoignable, sortie illisible => None, comportement inchangé ;
- elle est désactivable (FORGE_REPAIR=0) sans toucher au code.

    PYTHONPATH=scripts .venv312/Scripts/python.exe -m pytest \
        forge/tests/test_run_real_repair_wiring.py -v

ISOLATION DE LA PREUVE (2026-08-19) — chaque appel redirige `audit_path` / `results_path`
vers `tmp_path`. CE N'EST PAS DECORATIF : mesure avant correction, un simple `pytest` de
CE fichier ajoutait 12 lignes a `EVIDENCE/bundles/dispatch_audit.jsonl` et 4 a
`repair_results.jsonl` — les VRAIS artefacts de preuve. `announce()` etant emis AVANT le
sous-processus, meme les cas qui rendent None ecrivaient. Cumul historique : 1048 des 3462
lignes de `dispatch_audit.jsonl`, toutes sans `run_id` (un test n'en fournit pas), reparties
s2-worldscan 696 / s4-archi 176 / s5-wiremap 176 — soit exactement les appels ci-dessous.
Ne JAMAIS ajouter un appel sans ces deux destinations : `test_evidence_isolation.py` echoue.
"""
import json
import subprocess

import pytest

import forge.run_real as run_real


# --- périmètre du branchement -------------------------------------------------------

def test_les_5_etapes_amont_sont_branchees_et_elles_seules():
    assert run_real._REPAIR_STEP_BY_STEP == {
        "s2-worldscan": "s2-worldscan",
        "s1-prisme": "s1-prisme",
        "s3-decompo": "s3-decompo",
        "s4-archi": "s4-archi-contract",
        "s5-wiremap": "s5-wiremap-contract",
    }


@pytest.mark.parametrize("etape", ["s10b-oracle-archi", "s10c-oracle-wiremap",
                                   "s9-build", "s11-redteam-code", "s0-contrat"])
def test_aucune_etape_post_build_ne_declenche_la_boucle(etape, tmp_path, monkeypatch):
    """Les oracles de preuve finale ne se « réparent » pas : on corrige le code."""
    def jamais(*a, **k):
        raise AssertionError("aucun sous-processus ne doit être lancé pour cette étape")
    monkeypatch.setattr(subprocess, "run", jamais)
    assert run_real.run_repair_step(etape, tmp_path, audit_path=tmp_path / "audit.jsonl",
                                results_path=tmp_path / "res.jsonl") is None


def test_s4_et_s5_visent_l_oracle_de_CONTRAT_pas_celui_d_apres_build(tmp_path, monkeypatch):
    vues = []

    def faux_run(cmd, **kwargs):
        vues.append(cmd)
        return subprocess.CompletedProcess(cmd, 0, stdout=json.dumps({"STATUS": "OK_SANS_REPARATION"}), stderr="")

    monkeypatch.setattr(subprocess, "run", faux_run)
    run_real.run_repair_step("s4-archi", tmp_path, audit_path=tmp_path / "audit.jsonl",
                                results_path=tmp_path / "res.jsonl")
    run_real.run_repair_step("s5-wiremap", tmp_path, audit_path=tmp_path / "audit.jsonl",
                                results_path=tmp_path / "res.jsonl")
    assert "s4-archi-contract" in vues[0]
    assert "s5-wiremap-contract" in vues[1]


# --- robustesse : la boucle ne peut pas faire tomber l'étape ------------------------

def test_node_absent_rend_None_sans_lever(tmp_path, monkeypatch):
    def boom(*a, **k):
        raise FileNotFoundError("node introuvable")
    monkeypatch.setattr(subprocess, "run", boom)
    assert run_real.run_repair_step("s2-worldscan", tmp_path, audit_path=tmp_path / "audit.jsonl",
                                results_path=tmp_path / "res.jsonl") is None


def test_timeout_rend_None_sans_lever(tmp_path, monkeypatch):
    def boom(*a, **k):
        raise subprocess.TimeoutExpired(cmd="node", timeout=1)
    monkeypatch.setattr(subprocess, "run", boom)
    assert run_real.run_repair_step("s2-worldscan", tmp_path, audit_path=tmp_path / "audit.jsonl",
                                results_path=tmp_path / "res.jsonl") is None


def test_sortie_illisible_rend_None_sans_lever(tmp_path, monkeypatch):
    monkeypatch.setattr(subprocess, "run", lambda cmd, **k: subprocess.CompletedProcess(
        cmd, 1, stdout="pas du json", stderr=""))
    assert run_real.run_repair_step("s2-worldscan", tmp_path, audit_path=tmp_path / "audit.jsonl",
                                results_path=tmp_path / "res.jsonl") is None


def test_sortie_json_non_dict_rend_None(tmp_path, monkeypatch):
    monkeypatch.setattr(subprocess, "run", lambda cmd, **k: subprocess.CompletedProcess(
        cmd, 0, stdout="[1, 2, 3]", stderr=""))
    assert run_real.run_repair_step("s2-worldscan", tmp_path, audit_path=tmp_path / "audit.jsonl",
                                results_path=tmp_path / "res.jsonl") is None


def test_un_echec_de_reparation_reste_une_mesure_pas_une_exception(tmp_path, monkeypatch):
    """ESCALADE est un RÉSULTAT rendu à l'appelant, jamais une panne."""
    mesure = {"STATUS": "ESCALADE", "PROBLEMS_BEFORE": 2, "PROBLEMS_AFTER": 2,
              "TOKENS": 40, "FIELDS_CHANGED": [], "REGRESSION": []}
    monkeypatch.setattr(subprocess, "run", lambda cmd, **k: subprocess.CompletedProcess(
        cmd, 1, stdout=json.dumps(mesure), stderr=""))
    r = run_real.run_repair_step("s2-worldscan", tmp_path, audit_path=tmp_path / "audit.jsonl",
                                results_path=tmp_path / "res.jsonl")
    assert r["STATUS"] == "ESCALADE"
    assert r["PROBLEMS_AFTER"] == 2


# --- interrupteur ------------------------------------------------------------------

def test_forge_repair_0_desactive_la_boucle(tmp_path, monkeypatch):
    def jamais(*a, **k):
        raise AssertionError("la boucle doit être désactivée")
    monkeypatch.setenv("FORGE_REPAIR", "0")
    monkeypatch.setattr(subprocess, "run", jamais)
    assert run_real.run_repair_step("s2-worldscan", tmp_path, audit_path=tmp_path / "audit.jsonl",
                                results_path=tmp_path / "res.jsonl") is None


def test_active_par_defaut(tmp_path, monkeypatch):
    monkeypatch.delenv("FORGE_REPAIR", raising=False)
    monkeypatch.setattr(subprocess, "run", lambda cmd, **k: subprocess.CompletedProcess(
        cmd, 0, stdout=json.dumps({"STATUS": "OK_SANS_REPARATION"}), stderr=""))
    assert run_real.run_repair_step("s2-worldscan", tmp_path, audit_path=tmp_path / "audit.jsonl",
                                results_path=tmp_path / "res.jsonl") is not None


# --- le script existe et déclare bien les 5 étapes ---------------------------------

def test_le_script_de_reparation_existe_et_declare_les_5_etapes():
    assert run_real._REPAIR_SCRIPT.exists(), f"script absent : {run_real._REPAIR_SCRIPT}"
    src = run_real._REPAIR_SCRIPT.read_text(encoding="utf-8")
    for etape in run_real._REPAIR_STEP_BY_STEP.values():
        assert f"'{etape}'" in src, f"étape non déclarée dans repair_step.mjs : {etape}"
    # garde-fou : les oracles post-build ne doivent jamais y apparaître comme cibles
    assert "checkArchitecture" not in src

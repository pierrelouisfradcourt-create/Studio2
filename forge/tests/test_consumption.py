"""Point de mesure de l'acquittement (P1, ratifiée Pierre 2026-09-02).

Ce que ces tests figent, et qui est le coeur de la décision :

  - l'acquittement se mesure sur l'artefact DÉSIGNÉ, pas « quelque part dans le run ».
    Une référence qui n'apparaît que dans `context/prompt_*.txt` — parce qu'on l'a
    SERVIE à la capacité — ne vaut PAS acquittement (faux positif F-2) ;
  - trois états seulement, ceux de la spécification ratifiée ;
  - ADVISORY : jamais d'exception, aucun verdict lu ni écrit, le pire résultat possible
    est `no_evidence_declared` ;
  - la distinction que le vocabulaire à trois états ne sait pas porter — « a désigné un
    artefact mais ne l'a pas produit » — est visible dans le détail, jamais inventée
    dans un 4e état non ratifié.

NO_CLAIM_ALLOWED.
"""
from __future__ import annotations

import yaml

from forge.consumption import (
    CONSUMED,
    NOT_CONSUMED,
    NO_EVIDENCE_DECLARED,
    consumption_adoption,
    consumption_detail,
    consumption_status,
    declared_evidence,
)

REF = "AMD-P1-1"


def _msg(**over) -> dict:
    base = {
        "id": REF,
        "type": "amendment",
        "from": "fable",
        "to": ["s4-archi"],
        "subject": "sujet",
        "reason": "raison",
        "issued_at": "2026-09-02T10:00:00Z",
    }
    base.update(over)
    return base


def _contracts(tmp_path, **par_capacite):
    """Répertoire de contrats jetable : la mesure ne doit jamais dépendre des 28
    contrats réels, qui n'ont pas encore adopté le champ."""
    directory = tmp_path / "contracts"
    directory.mkdir(exist_ok=True)
    for capability, evidence in par_capacite.items():
        data = {"role": "x"}
        if evidence is not None:
            data["consumption_evidence"] = evidence
        (directory / f"{capability}.yaml").write_text(
            yaml.safe_dump(data, allow_unicode=True), encoding="utf-8")
    return directory


def _run(tmp_path, files: dict[str, str]):
    run = tmp_path / "run"
    for rel, content in files.items():
        path = run / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")
    run.mkdir(parents=True, exist_ok=True)
    return run


# --- no_evidence_declared ------------------------------------------------------------

def test_capacite_sans_declaration(tmp_path):
    contracts = _contracts(tmp_path, **{"s4-archi": None})
    run = _run(tmp_path, {"blueprint.md": f"cite {REF}"})
    assert consumption_status(_msg(), "s4-archi", run, contracts) == NO_EVIDENCE_DECLARED


def test_sentinelle_aucun_vaut_rien_de_declare(tmp_path):
    contracts = _contracts(tmp_path, **{"s4-archi": "aucun"})
    run = _run(tmp_path, {"blueprint.md": f"cite {REF}"})
    assert declared_evidence("s4-archi", contracts) == []
    assert consumption_status(_msg(), "s4-archi", run, contracts) == NO_EVIDENCE_DECLARED


def test_contrat_inexistant_ne_leve_jamais(tmp_path):
    contracts = _contracts(tmp_path)
    run = _run(tmp_path, {"a.md": "x"})
    assert consumption_status(_msg(), "capacite-fantome", run, contracts) == NO_EVIDENCE_DECLARED


# --- consumed / not_consumed ---------------------------------------------------------

def test_reference_dans_l_artefact_designe(tmp_path):
    contracts = _contracts(tmp_path, **{"s4-archi": ["blueprint.md"]})
    run = _run(tmp_path, {"blueprint.md": f"Architecture revue suite a {REF}."})
    detail = consumption_detail(_msg(), "s4-archi", run, contracts)
    assert detail["status"] == CONSUMED
    assert detail["found_in"] == ["blueprint.md"]


def test_a_produit_mais_ne_cite_pas(tmp_path):
    contracts = _contracts(tmp_path, **{"s4-archi": ["blueprint.md"]})
    run = _run(tmp_path, {"blueprint.md": "Architecture revue, sans citer quoi que ce soit."})
    detail = consumption_detail(_msg(), "s4-archi", run, contracts)
    assert detail["status"] == NOT_CONSUMED
    assert detail["artifacts_checked"] == ["blueprint.md"]
    assert detail["artifacts_missing"] == []


# --- LE point : le prompt ne vaut pas acquittement (F-2) -----------------------------

def test_reference_seulement_dans_le_prompt_ne_vaut_pas_acquittement(tmp_path):
    """`knowledge_trace --verify` rendrait FOUND ici : la référence EST dans le run.
    Elle n'y est que parce qu'on l'a servie à la capacité. Ce module dit NON."""
    contracts = _contracts(tmp_path, **{"s4-archi": ["blueprint.md"]})
    run = _run(tmp_path, {
        "context/prompt_s4-archi_a0.txt": f"À LIRE OBLIGATOIREMENT : {REF}",
        "blueprint.md": "Architecture revue, sans reprendre la référence.",
    })
    assert consumption_status(_msg(), "s4-archi", run, contracts) == NOT_CONSUMED


def test_le_prompt_n_est_jamais_retenu_meme_s_il_est_designe(tmp_path):
    contracts = _contracts(tmp_path, **{"s4-archi": ["prompt_s4-archi_a0.txt"]})
    run = _run(tmp_path, {"context/prompt_s4-archi_a0.txt": f"{REF}"})
    detail = consumption_detail(_msg(), "s4-archi", run, contracts)
    assert detail["status"] == NOT_CONSUMED
    assert detail["artifacts_checked"] == []
    assert detail["artifacts_missing"] == ["prompt_s4-archi_a0.txt"]


def test_la_trace_elle_meme_ne_vaut_pas_acquittement(tmp_path):
    """La trace CONTIENT la référence par construction — l'émetteur l'y a écrite."""
    contracts = _contracts(tmp_path, **{"s4-archi": ["knowledge_trace.json"]})
    run = _run(tmp_path, {"knowledge_trace.json": f'{{"items":[{{"ref":"{REF}"}}]}}'})
    assert consumption_status(_msg(), "s4-archi", run, contracts) == NOT_CONSUMED


# --- l'angle mort du vocabulaire, rendu visible --------------------------------------

def test_artefact_designe_mais_jamais_produit(tmp_path):
    contracts = _contracts(tmp_path, **{"s4-archi": ["blueprint.md"]})
    run = _run(tmp_path, {"autre.md": f"cite {REF} mais ce n'est pas l'artefact désigné"})
    detail = consumption_detail(_msg(), "s4-archi", run, contracts)
    assert detail["status"] == NOT_CONSUMED           # le vocabulaire ratifié s'arrête là
    assert detail["artifacts_missing"] == ["blueprint.md"]   # ... le détail, lui, le dit
    assert detail["artifacts_checked"] == []


def test_run_dir_absent_ne_leve_jamais(tmp_path):
    contracts = _contracts(tmp_path, **{"s4-archi": ["blueprint.md"]})
    detail = consumption_detail(_msg(), "s4-archi", tmp_path / "nexiste_pas", contracts)
    assert detail["status"] == NOT_CONSUMED
    assert detail["artifacts_missing"] == ["blueprint.md"]


# --- résolution de l'artefact déclaré ------------------------------------------------

def test_resolution_par_sous_chemin(tmp_path):
    contracts = _contracts(tmp_path, **{"s4-archi": ["blueprint.md"]})
    run = _run(tmp_path, {"artifacts/04_ARCHI/blueprint.md": f"suite a {REF}"})
    assert consumption_status(_msg(), "s4-archi", run, contracts) == CONSUMED


def test_plusieurs_artefacts_designes_un_seul_suffit(tmp_path):
    contracts = _contracts(tmp_path, **{"s4-archi": ["blueprint.md", "decisions.md"]})
    run = _run(tmp_path, {"blueprint.md": "rien", "decisions.md": f"acte : {REF}"})
    detail = consumption_detail(_msg(), "s4-archi", run, contracts)
    assert detail["status"] == CONSUMED
    assert detail["found_in"] == ["decisions.md"]


# --- la mesure d'adoption (matière de M) ---------------------------------------------

def test_adoption_compte_les_couples_message_capacite(tmp_path):
    contracts = _contracts(tmp_path, **{
        "s4-archi": ["blueprint.md"],
        "s5-wiremap": ["wiremap.json"],
        "s3-decompo": None,
    })
    run = _run(tmp_path, {
        "blueprint.md": f"suite a {REF}",
        "wiremap.json": "{}",
    })
    messages = [_msg(to=["s4-archi", "s5-wiremap", "s3-decompo"])]
    mesure = consumption_adoption(messages, run, contracts)
    assert mesure[CONSUMED] == 1
    assert mesure[NOT_CONSUMED] == 1
    assert mesure[NO_EVIDENCE_DECLARED] == 1
    assert mesure["pairs"] == 3


def test_adoption_sur_population_vide(tmp_path):
    assert consumption_adoption([], tmp_path)["pairs"] == 0
    assert consumption_adoption(None, tmp_path)["pairs"] == 0

"""Journal d'amendements (J1, ratifiée Pierre 2026-09-02).

Ces tests figent les DEUX moitiés de J1 :
  - l'emplacement : le journal refuse d'être écrit sous `EVIDENCE/runs/`, parce qu'un
    journal DANS le corpus d'un run fabriquerait un faux `FOUND` (F-1) — la référence
    s'y trouverait par construction, sans que la capacité ait rien incorporé ;
  - la discipline : append-only, non destructif, rien n'est écrit si le message est
    refusé (même règle que `validateTraceItems`).

ADVISORY — aucun verdict lu ni modifié. NO_CLAIM_ALLOWED.
"""
from __future__ import annotations

import json

import pytest

from forge.amendment_log import (
    AmendmentLogError,
    RUNS_ZONE,
    append_message,
    journal_path,
    new_message_id,
    read_messages,
    validate_message,
)


def _msg(**over) -> dict:
    base = {
        "id": "AMD-1",
        "type": "amendment",
        "from": "fable",
        "to": ["s4-archi"],
        "subject": "économie dérivée du GM",
        "reason": "O-1 : economy.json dépend d'une capacité optionnelle",
        "issued_at": "2026-09-02T10:00:00Z",
    }
    base.update(over)
    return base


# --- schéma : refusé => RIEN n'est écrit -------------------------------------------

@pytest.mark.parametrize("bad", [
    {"id": ""},
    {"type": "rumeur"},
    {"to": []},
    {"to": ["ok", ""]},
    {"reason": "   "},
    {"blocking": "oui"},
    {"impact": [1, 2]},
])
def test_message_invalide_refuse_et_rien_ecrit(tmp_path, bad):
    assert validate_message(_msg(**bad))
    with pytest.raises(AmendmentLogError):
        append_message(_msg(**bad), journal_dir=tmp_path)
    assert not journal_path(tmp_path).exists()


def test_message_non_dict_refuse():
    assert validate_message("pas un objet")
    assert validate_message(None)


# --- append-only --------------------------------------------------------------------

def test_append_only_conserve_l_ordre_et_les_entrees(tmp_path):
    append_message(_msg(id="AMD-1", type="question"), journal_dir=tmp_path)
    append_message(_msg(id="AMD-2", type="objection"), journal_dir=tmp_path)
    append_message(_msg(id="AMD-3"), journal_dir=tmp_path)
    got = read_messages(tmp_path)
    assert [m["id"] for m in got] == ["AMD-1", "AMD-2", "AMD-3"]
    # une objection conservée, jamais effacée (C1 : non destructif)
    assert got[1]["type"] == "objection"


def test_id_deja_present_refuse(tmp_path):
    append_message(_msg(id="AMD-1"), journal_dir=tmp_path)
    with pytest.raises(AmendmentLogError, match="append-only"):
        append_message(_msg(id="AMD-1", subject="autre sujet"), journal_dir=tmp_path)
    assert len(read_messages(tmp_path)) == 1


def test_valeurs_par_defaut_materialisees(tmp_path):
    append_message(_msg(), journal_dir=tmp_path)
    entry = read_messages(tmp_path)[0]
    assert entry["impact"] == []
    assert entry["evidence_ref"] == []
    assert entry["blocking"] is False


# --- emplacement : le coeur de J1 ---------------------------------------------------

def test_journal_refuse_sous_forge_runs(tmp_path):
    """Symétrique de la garde de `writeTrace` : la trace DOIT être sous
    `EVIDENCE/runs/`, le journal doit en être DEHORS. Deux fichiers, deux zones."""
    interdit = RUNS_ZONE / "un_run_quelconque" / "amendments"
    with pytest.raises(AmendmentLogError, match="emplacement interdit"):
        append_message(_msg(), journal_dir=interdit)
    assert not journal_path(interdit).exists()


def test_journal_hors_zone_accepte(tmp_path):
    path = append_message(_msg(), journal_dir=tmp_path)
    assert path.exists()
    assert json.loads(path.read_text(encoding="utf-8").splitlines()[0])["id"] == "AMD-1"


# --- lecture tolérante, jamais corrective -------------------------------------------

def test_journal_absent_rend_liste_vide(tmp_path):
    assert read_messages(tmp_path) == []


def test_ligne_illisible_ignoree_jamais_effacee(tmp_path):
    append_message(_msg(id="AMD-1"), journal_dir=tmp_path)
    path = journal_path(tmp_path)
    with open(path, "a", encoding="utf-8") as fh:
        fh.write("{ceci n'est pas du JSON\n")
    append_message(_msg(id="AMD-2"), journal_dir=tmp_path)
    assert [m["id"] for m in read_messages(tmp_path)] == ["AMD-1", "AMD-2"]
    # la ligne fautive est TOUJOURS dans le fichier : lire ne répare pas
    assert "ceci n'est pas du JSON" in path.read_text(encoding="utf-8")


# --- identifiant déterministe (C1) --------------------------------------------------

def test_id_deterministe(tmp_path):
    a = new_message_id("économie dérivée du GM", issued_at="2026-09-02T10:00:00Z")
    b = new_message_id("économie dérivée du GM", issued_at="2026-09-02T10:00:00Z")
    assert a == b
    assert a.startswith("AMD-")
    assert new_message_id("", issued_at="2026-09-02T10:00:00Z").startswith("AMD-")

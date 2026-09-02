"""Émetteur de notifications (E, ratifiée Pierre 2026-09-02).

Ces tests figent ce qui fait de E un geste vérifiable plutôt qu'une écriture de plus :

  - DEUX écritures distinctes — le message au journal (hors run_dir), les items dans la
    trace du run. Jamais confondues : c'est ce qui rend l'acquittement mesurable.
  - MERGE, jamais écrasement — `writeTrace` réécrit le fichier entier ; l'émetteur relit
    et écrit l'union. Une seconde notification ne doit pas effacer la première.
  - NON DESTRUCTIF — une trace illisible fait échouer l'écriture au lieu de l'écraser.
  - REFUS TOTAL en amont — message invalide ou sans destinataire : rien n'est écrit.
  - HONNÊTETÉ EN CAS D'ÉCHEC PARTIEL — si la trace échoue après le journal, l'erreur dit
    exactement ce qui a été écrit et ce qui ne l'a pas été. Le message n'est pas retiré :
    append-only vaut aussi quand la suite se passe mal.

ADVISORY — aucun verdict lu ni modifié. NO_CLAIM_ALLOWED.
"""
from __future__ import annotations

import json
import os
import shutil

import pytest

from forge.amendment_log import read_messages
from forge.emitter import (
    EmitterError,
    REPO_ROOT,
    TRACE_FILENAME,
    build_trace_items,
    notify,
    read_existing_items,
    write_trace_items,
)

_NODE_ABSENT = shutil.which("node") is None
pytestmark = pytest.mark.skipif(_NODE_ABSENT, reason="node indisponible")


@pytest.fixture()
def run_dir(tmp_path):
    """Un vrai run_dir sous `EVIDENCE/runs/` : `writeTrace` refuse par garde toute
    écriture ailleurs, ce chemin ne peut donc pas être simulé par un tmp_path."""
    target = REPO_ROOT / "EVIDENCE" / "runs" / f"_emitter_test_{os.getpid()}"
    target.mkdir(parents=True, exist_ok=True)
    try:
        yield target
    finally:
        shutil.rmtree(target, ignore_errors=True)


def _msg(**over) -> dict:
    base = {
        "id": "AMD-E-1",
        "type": "amendment",
        "from": "fable",
        "to": ["s4-archi", "s5-wiremap"],
        "subject": "economie derivee du GM",
        "reason": "O-1",
        "issued_at": "2026-09-02T10:00:00Z",
    }
    base.update(over)
    return base


# --- composition des items (aucune écriture) ---------------------------------------

def test_un_item_par_capacite_convoquee():
    items = build_trace_items(_msg())
    assert len(items) == 2
    assert {i["ref"] for i in items} == {"AMD-E-1"}
    assert all(i["source"] == "mandatory_read" for i in items)
    assert "s4-archi" in items[0]["reason"] and "s5-wiremap" in items[1]["reason"]


def test_provenance_par_type_de_message():
    assert build_trace_items(_msg(type="amendment"))[0]["provenance"] == "HUMAN_RATIFIED"
    assert build_trace_items(_msg(type="objection"))[0]["provenance"] == "ADVISORY"
    assert build_trace_items(_msg(type="question"))[0]["provenance"] == "ADVISORY"


# --- refus en amont : rien n'est écrit ----------------------------------------------

def test_message_invalide_refuse_avant_toute_ecriture(tmp_path, run_dir):
    with pytest.raises(EmitterError, match="rien n'a été écrit"):
        notify(_msg(type="rumeur"), run_dir, journal_dir=tmp_path)
    assert read_messages(tmp_path) == []
    assert not (run_dir / TRACE_FILENAME).exists()


def test_sans_destinataire_refuse(tmp_path, run_dir):
    with pytest.raises(EmitterError, match="destinataire"):
        notify(_msg(), run_dir, capabilities=[], journal_dir=tmp_path)
    assert read_messages(tmp_path) == []
    assert not (run_dir / TRACE_FILENAME).exists()


# --- le geste complet : deux écritures ----------------------------------------------

def test_notify_ecrit_le_journal_et_la_trace(tmp_path, run_dir):
    res = notify(_msg(), run_dir, journal_dir=tmp_path)

    journal = read_messages(tmp_path)
    assert [m["id"] for m in journal] == ["AMD-E-1"]

    trace = json.loads((run_dir / TRACE_FILENAME).read_text(encoding="utf-8"))
    assert len(trace["items"]) == 2
    assert res["items_added"] == 2
    assert res["notified"] == ["s4-archi", "s5-wiremap"]

    # le message vit HORS du run_dir : sa référence ne doit pas être dans le corpus
    # par construction (F-1), seule la trace la porte
    assert tmp_path.resolve() not in run_dir.resolve().parents


# --- merge : une seconde notification n'efface pas la première ----------------------

def test_seconde_notification_preserve_la_premiere(tmp_path, run_dir):
    notify(_msg(id="AMD-E-1"), run_dir, journal_dir=tmp_path)
    res = notify(_msg(id="AMD-E-2", to=["s3-decompo"]), run_dir, journal_dir=tmp_path)

    trace = json.loads((run_dir / TRACE_FILENAME).read_text(encoding="utf-8"))
    refs = [i["ref"] for i in trace["items"]]
    assert refs.count("AMD-E-1") == 2      # préservés
    assert refs.count("AMD-E-2") == 1      # ajouté
    assert res["items_preserved"] == 2 and res["items_added"] == 1


def test_reemission_identique_ne_duplique_rien(run_dir):
    items = build_trace_items(_msg())
    write_trace_items(run_dir, items)
    res = write_trace_items(run_dir, items)
    assert res["items_added"] == 0
    assert res["items_total"] == 2


# --- non destructif ------------------------------------------------------------------

def test_trace_illisible_refuse_l_ecriture_au_lieu_d_ecraser(run_dir):
    corrompue = "{ceci n'est pas du JSON"
    (run_dir / TRACE_FILENAME).write_text(corrompue, encoding="utf-8")
    with pytest.raises(EmitterError, match="illisible"):
        read_existing_items(run_dir)
    with pytest.raises(EmitterError, match="illisible"):
        write_trace_items(run_dir, build_trace_items(_msg()))
    # la preuve qu'on ne sait pas relire est TOUJOURS là
    assert (run_dir / TRACE_FILENAME).read_text(encoding="utf-8") == corrompue


# --- échec partiel : dire exactement ce qui a été écrit ------------------------------

def test_run_dir_hors_zone_echoue_apres_le_journal_et_le_dit(tmp_path):
    hors_zone = tmp_path / "pas_un_run"
    hors_zone.mkdir()
    with pytest.raises(EmitterError) as exc:
        notify(_msg(), hors_zone, journal_dir=tmp_path)
    detail = str(exc.value)
    assert "ÉCRIT au journal" in detail and "trace NON écrite" in detail
    # append-only : le message n'est PAS retiré du journal parce que la suite a échoué
    assert [m["id"] for m in read_messages(tmp_path)] == ["AMD-E-1"]

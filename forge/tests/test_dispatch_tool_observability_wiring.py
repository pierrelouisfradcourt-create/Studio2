"""Câblage additif de `forge.tool_observability` dans `forge.dispatch
.prepare_dispatch` — ferme le risque de dormance (maillons 1+2+5 auraient sinon
un module testé mais AUCUN consommateur de production ; un vrai dispatch écrit
maintenant la trace, sans y dépendre pour rien).

Neutralité exigée (doctrine §6.2) : rejouer le même dispatch doit rendre le
MÊME `DispatchPayload` et la MÊME ligne d'audit — avec un fichier de trace en
plus, rien d'autre. Best-effort strict : une panne du nouveau bloc ne doit
JAMAIS faire échouer un dispatch déjà validé (même garantie que le Context
Manifest, précédent immédiat dans le même corps de fonction).
"""
from __future__ import annotations

import json

import pytest

from forge import tool_observability as obs
from forge.dispatch import prepare_dispatch


def test_prepare_dispatch_ecrit_la_trace_tool_observability(tmp_path):
    audit = tmp_path / "audit.jsonl"
    run_dir = tmp_path / "run"
    prepare_dispatch("s4-archi", run_id="run-tools-1", audit_path=audit, run_dir=run_dir)

    recs = obs.read_tool_observability_records(run_dir, "s4-archi")
    assert len(recs) == 1
    rec = recs[0]
    assert rec["run_id"] == "run-tools-1"
    assert rec["etape"] == "s4-archi"
    # Contenu réel : s4-archi porte la prose I4 observée par ailleurs (maillon 1).
    declared = {f["field"]: f for f in rec["declared"]}
    assert declared["plugin"]["kind"] == obs.DECLARATION_KIND_PROSE
    assert obs.verify_tool_observability_record(rec) is True  # clé par défaut (.forge_key)


def test_neutralite_payload_et_audit_inchanges(tmp_path):
    """Preuve de neutralité (doctrine §6.2) : le payload retourné et la ligne
    d'audit signée sont EXACTEMENT ce qu'ils étaient avant ce chantier — le
    nouveau bloc n'ajoute qu'un fichier, jamais un effet sur la décision."""
    audit = tmp_path / "audit.jsonl"
    run_dir = tmp_path / "run"
    payload = prepare_dispatch("s4-archi", run_id="run-neutral", audit_path=audit, run_dir=run_dir)

    assert payload.model  # runtime résolu comme avant
    audit_rec = json.loads(audit.read_text(encoding="utf-8").strip())
    assert audit_rec["etape"] == "s4-archi"
    assert audit_rec["run_id"] == "run-neutral"
    assert audit_rec["model"] == payload.model
    # Champ historiquement stable : allowed_tools de l'audit reste le PAYLOAD
    # (vide par construction pour un contrat skill/plugin 'aucun'/'aucun'),
    # jamais enrichi par ce chantier — I4 n'est PAS corrigé ici.
    assert audit_rec["allowed_tools"] == list(payload.allowed_tools)


def test_panne_du_bloc_tool_observability_ne_casse_pas_le_dispatch(tmp_path, monkeypatch):
    """Best-effort : si `append_tool_observability_record` lève, `prepare_dispatch`
    doit quand même retourner un payload valide et avoir écrit son audit — un
    dispatch déjà validé n'est jamais cassé par une mesure advisory."""
    def _boom(*args, **kwargs):
        raise RuntimeError("panne simulée du bloc advisory")

    monkeypatch.setattr(obs, "append_tool_observability_record", _boom)

    audit = tmp_path / "audit.jsonl"
    run_dir = tmp_path / "run"
    payload = prepare_dispatch("s4-archi", run_id="run-panne", audit_path=audit, run_dir=run_dir)
    assert payload.model
    assert audit.exists()
    # La panne étant dans append_tool_observability_record lui-même, aucun
    # fichier de trace n'apparaît — mesuré, pas juste supposé.
    assert obs.read_tool_observability_records(run_dir, "s4-archi") == ()


def test_deux_dispatches_de_la_meme_etape_accumulent_deux_lignes(tmp_path):
    audit = tmp_path / "audit.jsonl"
    run_dir = tmp_path / "run"
    prepare_dispatch("s9-build", run_id="run-a", audit_path=audit, run_dir=run_dir)
    prepare_dispatch("s9-build", run_id="run-b", audit_path=audit, run_dir=run_dir)
    recs = obs.read_tool_observability_records(run_dir, "s9-build")
    assert {r["run_id"] for r in recs} == {"run-a", "run-b"}


def test_unknown_step_raises_avant_toute_ecriture_de_trace(tmp_path):
    """Un contrat invalide/inexistant est refusé par la porte (C1) AVANT que le
    bloc advisory n'ait quoi que ce soit à observer — comportement hérité,
    inchangé (test jumeau de test_unknown_step_raises dans test_dispatch.py)."""
    run_dir = tmp_path / "run"
    with pytest.raises(FileNotFoundError):
        prepare_dispatch("s99-inexistant", run_id="x", audit_path=tmp_path / "a.jsonl",
                         run_dir=run_dir)
    assert obs.read_tool_observability_records(run_dir, "s99-inexistant") == ()

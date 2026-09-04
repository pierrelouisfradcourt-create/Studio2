"""Lot 6 (spec 2026-09-04, GO Pierre) — contrat de re-convocation : identité de section et
acquittement structuré.

Forme de production réelle : Blueprint importé de la baseline M ter, feature_maps réellement produites
par les convocations de `decompose` (baseline, lot5), wiremap réelle de la baseline. Aucun appel LLM.
NO_CLAIM_ALLOWED.
"""
from __future__ import annotations

import json
import shutil
from pathlib import Path

import pytest

from forge import acknowledgement as ack
from forge import blueprint as bp
from forge import capability as cap
from forge import identity as idt
from forge.amendment_log import MESSAGE_TYPES, append_message, read_messages, validate_message
from forge.blueprint_import import import_run_dir

_REPO_ROOT = Path(__file__).resolve().parents[2]
_RUN_DIR = _REPO_ROOT / "EVIDENCE" / "runs" / "runm_breakout"
_BRIEF = _REPO_ROOT / "EVIDENCE" / "briefs" / "runm_breakout" / "project_brief.yaml"
_FM_BASELINE = _RUN_DIR / "featuremap.json"
_FM_LOT5 = _REPO_ROOT / "EVIDENCE" / "runs" / "lot5_transport_probe" / "featuremap.json"

pytestmark = [
    pytest.mark.skipif(not (_RUN_DIR / "state.json").exists(), reason="baseline M ter absente"),
    pytest.mark.skipif(shutil.which("node") is None, reason="node absent"),
]

_FM_KEY = "systemes[].features[].capacites[].id"


@pytest.fixture
def blueprint():
    return import_run_dir(_RUN_DIR, brief_path=_BRIEF, project="runm_breakout")


def _fm(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


# --- Task 1 : registre et extraction ------------------------------------------------------------


def test_le_registre_declare_une_cle_d_identite_canonique_par_section():
    doc = idt.load_identity()
    assert doc["feature_map"]["key"] == _FM_KEY
    for section, decl in doc.items():
        assert isinstance(decl.get("key"), str) and decl["key"], section
        for ref in decl.get("referenced_by") or []:
            assert set(ref) == {"section", "path"}, section


def test_l_identite_de_la_wiremap_delegue_a_la_production():
    """Mesure du Lot 6 : deux schémas, UNE règle — celle de `frozen_features_from_wiremap`.
    Le registre nomme le résolveur au lieu de recopier un chemin (pas de seconde vérité)."""
    decl = idt.identity_of("wiremap.design")
    assert decl is not None and decl["key"] == "@frozen_features_from_wiremap"
    v1 = {"features": [{"feature": "R1 balle"}, {"feature": "R2 raquette"}]}
    v2 = {"schema_version": 2, "lines": [{"id": "L1"}, {"id": "L2"}]}
    assert idt.extract_ids(v1, decl["key"]) == ["R1 balle", "R2 raquette"]
    assert idt.extract_ids(v2, decl["key"]) == ["L1", "L2"]


def test_une_section_sans_cle_mesuree_ne_gouverne_rien():
    """Un UNKNOWN honnête : identity_of rend None, aucune règle ne s'applique (spec §3.2)."""
    assert idt.identity_of("gameplay") is None
    assert idt.identity_of("section_inexistante") is None


def test_la_frontiere_du_contrat_est_declaree_pas_subie():
    """`wiremap.built` (écrite par le builder) n'est PAS déclarée : aucune règle d'identité ne s'y
    applique en v0. C'est un choix — le gel des règles la couvre déjà par un STOP dur en s10c
    (check_feature_set_frozen) — et non un oubli silencieux."""
    doc = idt.load_identity()
    assert "wiremap.built" not in doc
    assert idt.identity_of("wiremap.built", doc) is None
    assert set(doc) == {"feature_map", "architecture_contract", "wiremap.design"}


def test_les_deux_schemas_d_ids_reellement_produits_sont_extraits():
    baseline = idt.extract_ids(_fm(_FM_BASELINE), _FM_KEY)
    lot5 = idt.extract_ids(_fm(_FM_LOT5), _FM_KEY)
    assert baseline[0] == "R1c1_hud_objectif_nonvide" and len(baseline) == 10
    assert lot5[0] == "CAP_objectif_hud" and len(lot5) == 10
    assert set(baseline).isdisjoint(lot5), "les deux runs ont bien renommé toutes les entrées"


def test_extract_ids_ignore_la_declaration_de_retrait_et_ne_leve_jamais():
    content = {"identity": {"retired": [{"id": "R9c1", "reason": "fusionnée"}]},
               "systemes": [{"features": [{"capacites": [{"id": "A"}, {"pas_d_id": 1}]}]}]}
    assert idt.extract_ids(content, _FM_KEY) == ["A"]
    assert idt.extract_ids({}, _FM_KEY) == []
    assert idt.extract_ids(None, _FM_KEY) == []
    assert idt.declared_retired(content) == [{"id": "R9c1", "reason": "fusionnée"}]
    assert idt.declared_retired({}) == [] and idt.declared_retired(None) == []


# --- Task 2 : comparaison et règle de refus -------------------------------------------------------


def _cmp(before_ids, after_ids, *, downstream=(), retired=()):
    def tree(ids):
        return {"systemes": [{"features": [{"capacites": [{"id": i} for i in ids]}]}]}
    return idt.compare(tree(before_ids), tree(after_ids), key=_FM_KEY,
                       downstream=set(downstream), retired=[{"id": r, "reason": "test"} for r in retired])


def test_un_renommage_cite_en_aval_est_refuse():
    r = _cmp(["A", "B"], ["A", "Z"], downstream={"A", "B"})
    assert r["referenced_dropped"] == ["B"] and r["ok"] is False
    assert r["added"] == ["Z"] and r["kept"] == ["A"]
    assert r["renamed_suspected"] == [("B", "Z")]   # informatif, jamais un verdict


def test_un_retrait_declare_sans_reference_aval_est_accepte():
    r = _cmp(["A", "B"], ["A"], downstream={"A"}, retired=["B"])
    assert r["retired_declared"] == ["B"] and r["referenced_dropped"] == [] and r["ok"] is True


def test_un_retrait_declare_ENCORE_cite_est_refuse():
    """Correction 1 de Pierre : déclarer un retrait ne suffit pas — sinon un renommage implicite
    devient une suppression déclarée."""
    r = _cmp(["A", "B"], ["A"], downstream={"A", "B"}, retired=["B"])
    assert r["referenced_dropped"] == ["B"] and r["ok"] is False
    assert "B" not in r["retired_declared"]


def test_un_retrait_non_declare_sans_reference_aval_passe_mais_reste_au_rapport():
    r = _cmp(["A", "B"], ["A"], downstream={"A"})
    assert r["dropped"] == ["B"] and r["ok"] is True and r["retired_declared"] == []


def test_un_ajout_est_toujours_libre():
    r = _cmp(["A"], ["A", "B", "C"], downstream={"A"})
    assert r["added"] == ["B", "C"] and r["ok"] is True


def test_les_references_aval_sont_lues_dans_le_blueprint_reel(blueprint):
    """Les deux sous-entrées déclarées au registre citent, ensemble, les 10 ids de la feature_map.

    État RÉEL de la baseline, encodé ici plutôt que masqué : `wiremap.design` est la sortie brute de
    l'agent s5, SANS `couvre` (le régime EMPTY_FORM du run M ter) ; c'est `wiremap.built`, réparée,
    qui les porte. La règle d'identité doit donc lire les DEUX, sinon un renommage passerait
    inaperçu tant que le design n'a pas encore joint."""
    decl = idt.identity_of("feature_map")
    ids = idt.downstream_ids(blueprint, decl["referenced_by"])
    fm_ids = set(idt.extract_ids(blueprint["sections"]["feature_map"]["content"], _FM_KEY))
    assert ids and ids == fm_ids
    wm = blueprint["sections"]["wiremap"]["content"]
    design_only = idt.downstream_ids(blueprint, [{"section": "wiremap.design", "path": "features[].couvre[]"}])
    assert design_only == set(), "la wiremap de design de la baseline n'a pas de couvre (EMPTY_FORM)"
    assert wm["built"]["content"]["features"][0]["couvre"]


def test_l_identite_de_regle_resolue_est_exactement_celle_que_le_gel_oppose(blueprint):
    """Preuve du résolveur : `@frozen_features_from_wiremap` sur la wiremap rend EXACTEMENT le
    contenu de wiremap_frozen.json (sous-entrée `frozen_names`) — un renommage de ligne casserait
    donc `check_feature_set_frozen`, arrêt dur de s10c."""
    wm = blueprint["sections"]["wiremap"]["content"]
    resolues = idt.extract_ids(wm["design"]["content"], "@frozen_features_from_wiremap")
    gelees = idt.extract_ids(wm["frozen_names"]["content"], "features[]")
    assert resolues and set(resolues) == set(gelees)


# --- Task 3 : branchement au point d'écriture -----------------------------------------------------


def _executor_returning(fm: dict, calls: list | None = None, suffix: str = ""):
    payload = "Rapport.\n\n```json\n" + json.dumps(fm, ensure_ascii=False) + "\n```\n" + suffix

    def executor(prompt, sp, pl):
        if calls is not None:
            calls.append({"prompt": prompt, "etape": sp["etape"]})
        return {"ok": True, "output": payload, "tokens": 0, "duration_s": 0.0, "cost_usd": 0.0}
    return executor


def _renamed(fm: dict) -> dict:
    out = json.loads(json.dumps(fm))
    n = 0
    for s in out["systemes"]:
        for f in s["features"]:
            for c in f["capacites"]:
                n += 1
                c["id"] = f"RENOMME_{n}"
    return out


def test_la_reconvocation_recoit_sa_production_precedente(blueprint, tmp_path):
    calls: list = []
    fm = blueprint["sections"]["feature_map"]["content"]
    res = cap.invoke_capability("decompose", blueprint, tmp_path / "run", run_id="lot6-t3", attempt=2,
                                executor=_executor_returning(fm, calls), audit_path=tmp_path / "a.jsonl")
    assert res["ok"], res["problems"]
    prompt = calls[0]["prompt"]
    assert "## TA PRODUCTION PRÉCÉDENTE — feature_map v1" in prompt
    assert "R1c1_hud_objectif_nonvide" in prompt
    assert "identity.retired" in prompt and "RÈGLE D'IDENTITÉ" in prompt
    assert res["identity"]["ok"] is True and res["identity"]["added"] == []
    assert len(res["identity"]["kept"]) == 10


def test_une_section_neuve_n_a_pas_de_production_precedente(blueprint, tmp_path):
    neuf = json.loads(json.dumps(blueprint))
    neuf["sections"]["feature_map"] = bp.empty_section("feature_map")
    calls: list = []
    res = cap.invoke_capability("decompose", neuf, tmp_path / "run", run_id="lot6-t3b", attempt=1,
                                executor=_executor_returning(_fm(_FM_BASELINE), calls),
                                audit_path=tmp_path / "a.jsonl")
    assert res["ok"] and res["identity"] is None
    assert "TA PRODUCTION PRÉCÉDENTE" not in calls[0]["prompt"]


def test_un_renommage_cite_par_la_wiremap_refuse_l_ecriture_et_laisse_la_section_intacte(blueprint, tmp_path):
    avant = (blueprint["sections"]["feature_map"]["version"],
             blueprint["sections"]["feature_map"]["content_sha256"])
    fm = _renamed(blueprint["sections"]["feature_map"]["content"])
    res = cap.invoke_capability("decompose", blueprint, tmp_path / "run", run_id="lot6-t3c", attempt=2,
                                executor=_executor_returning(fm), audit_path=tmp_path / "a.jsonl")
    assert res["ok"] is False
    pb = [p for p in res["problems"] if p["code"] == idt.ID_REFERENCED_DROPPED]
    assert len(pb) == 1 and pb[0]["producer"] == "identity_check" and pb[0]["path"] == "feature_map"
    assert pb[0]["suggested_action"] == "reconvoke"
    assert len(res["identity"]["referenced_dropped"]) == 10
    # la section n'a PAS bougé ; l'artefact reste sur disque pour inspection
    apres = (blueprint["sections"]["feature_map"]["version"],
             blueprint["sections"]["feature_map"]["content_sha256"])
    assert apres == avant
    assert (tmp_path / "run" / "featuremap.json").exists()
    link = [json.loads(l) for l in (tmp_path / "run" / "context" / "spawn_links.jsonl")
            .read_text(encoding="utf-8").splitlines() if l.strip()][-1]
    assert link["status"] == "HALTED"


def test_un_retrait_declare_et_libere_est_accepte(blueprint, tmp_path):
    """La wiremap ne cite plus l'id retiré (c'est `built` qui porte les couvre sur la baseline) :
    le retrait déclaré passe."""
    b = json.loads(json.dumps(blueprint))
    cible = "R9c1_window_game_expose"
    for f in b["sections"]["wiremap"]["content"]["built"]["content"]["features"]:
        f["couvre"] = [c for c in (f.get("couvre") or []) if c != cible]
    fm = json.loads(json.dumps(b["sections"]["feature_map"]["content"]))
    for s in fm["systemes"]:
        for f in s["features"]:
            f["capacites"] = [c for c in f["capacites"] if c["id"] != cible]
        # une feature sans feuille est refusée par _validate_featuremap : un vrai retrait remonte
        # l'arbre, il ne laisse pas de branche vide derrière lui
        s["features"] = [f for f in s["features"] if f["capacites"]]
    fm["systemes"] = [s for s in fm["systemes"] if s["features"]]
    fm["identity"] = {"retired": [{"id": cible, "reason": "capacité fusionnée dans R1c1"}]}
    res = cap.invoke_capability("decompose", b, tmp_path / "run", run_id="lot6-t3d", attempt=2,
                                executor=_executor_returning(fm), audit_path=tmp_path / "a.jsonl")
    assert res["ok"], res["problems"]
    assert res["identity"]["retired_declared"] == [cible] and res["identity"]["referenced_dropped"] == []
    assert b["sections"]["feature_map"]["version"] == 2


# --- Task 4 : acquittement, cinq statuts ----------------------------------------------------------


_MSG = {"id": "AMD-x-1", "type": "objection", "from": "director", "to": ["decompose"],
        "subject": "s", "reason": "r", "issued_at": "2026-09-04T00:00:00Z", "run_id": "lot6-t4"}


def _out(block: dict | None) -> str:
    if block is None:
        return "Rapport sans acquittement.\n"
    return "Rapport.\n\n```acquittement\n" + json.dumps(block, ensure_ascii=False) + "\n```\n"


def _judge(block, *, effect="CHANGED", capability="decompose", run_id="lot6-t4", deja=()):
    return ack.judge(block, message=_MSG, capability=capability, run_id=run_id, effect=effect,
                     already_acknowledged=set(deja))


def test_applied_avec_effet_est_acquitte():
    b, _ = ack.extract_block(_out({"message_id": "AMD-x-1", "action": "applied", "changes": ["ids conservés"]}))
    r = _judge(b)
    assert r["status"] == ack.ACKNOWLEDGED and r["message_id"] == "AMD-x-1" and r["action"] == "applied"


def test_applied_sans_effet_est_une_pretention_sans_effet():
    b, _ = ack.extract_block(_out({"message_id": "AMD-x-1", "action": "applied", "changes": ["rien"]}))
    assert _judge(b, effect="NO_EFFECT")["status"] == ack.CLAIMED_WITHOUT_EFFECT


def test_partial_avec_effet_est_acquitte_et_garde_sa_raison():
    b, _ = ack.extract_block(_out({"message_id": "AMD-x-1", "action": "partial",
                                   "changes": ["2 sur 3"], "reason": "la 3e dépend de la wiremap"}))
    r = _judge(b)
    assert r["status"] == ack.ACKNOWLEDGED and r["reason"].startswith("la 3e")


def test_rejected_avec_raison_est_un_desaccord():
    b, _ = ack.extract_block(_out({"message_id": "AMD-x-1", "action": "rejected",
                                   "changes": [], "reason": "l'oracle impose main.tscn sur un jeu web"}))
    assert _judge(b)["status"] == ack.REJECTED


def test_rejected_sans_raison_n_est_pas_un_acquittement():
    b, _ = ack.extract_block(_out({"message_id": "AMD-x-1", "action": "rejected", "changes": []}))
    assert _judge(b)["status"] == ack.NOT_ACKNOWLEDGED


def test_message_inconnu_autre_capacite_ou_autre_run():
    b, _ = ack.extract_block(_out({"message_id": "AMD-INCONNU", "action": "applied"}))
    assert _judge(b)["status"] == ack.UNKNOWN_MESSAGE
    b2, _ = ack.extract_block(_out({"message_id": "AMD-x-1", "action": "applied"}))
    assert _judge(b2, capability="wiremap")["status"] == ack.UNKNOWN_MESSAGE
    assert _judge(b2, run_id="autre_run")["status"] == ack.UNKNOWN_MESSAGE


def test_un_second_acquittement_du_meme_message_est_refuse():
    b, _ = ack.extract_block(_out({"message_id": "AMD-x-1", "action": "applied"}))
    assert _judge(b, deja={"AMD-x-1"})["status"] == ack.UNKNOWN_MESSAGE


def test_absence_de_bloc_bloc_illisible_et_action_inconnue():
    b, why = ack.extract_block(_out(None))
    assert b is None and "aucun fence" in why
    assert _judge(b)["status"] == ack.NOT_ACKNOWLEDGED
    b2, why2 = ack.extract_block("Rapport.\n\n```acquittement\npas du json\n```\n")
    assert b2 is None and why2
    b3, _ = ack.extract_block(_out({"message_id": "AMD-x-1", "action": "vu"}))
    assert _judge(b3)["status"] == ack.NOT_ACKNOWLEDGED


def test_le_dernier_bloc_seul_fait_foi():
    out = (_out({"message_id": "AMD-x-1", "action": "rejected", "reason": "brouillon"})
           + _out({"message_id": "AMD-x-1", "action": "applied", "changes": ["final"]}))
    b, _ = ack.extract_block(out)
    assert b["action"] == "applied"


# --- Task 5 : le désaccord (correction 3 de Pierre) ------------------------------------------------


def _rejected_judgment():
    b, _ = ack.extract_block(_out({"message_id": "AMD-x-1", "action": "rejected", "changes": [],
                                   "reason": "l'oracle impose main.tscn sur un jeu web"}))
    return _judge(b)


def test_un_desaccord_est_une_objection_en_sens_inverse_recevable_par_le_journal(tmp_path):
    d = ack.disagreement_message(_rejected_judgment(), capability="decompose", run_id="lot6-t5", message=_MSG)
    assert d["type"] == "objection" and d["type"] in MESSAGE_TYPES
    assert d["from"] == "decompose" and d["to"] == ["director"]
    assert d["in_reply_to"] == "AMD-x-1" and d["run_id"] == "lot6-t5"
    assert validate_message(d) == []
    append_message(d, journal_dir=tmp_path / "amendments")
    lu = read_messages(tmp_path / "amendments")[-1]
    assert lu["in_reply_to"] == "AMD-x-1" and lu["from"] == "decompose"


def test_les_trois_objets_restent_distinguables(tmp_path):
    """Question initiale, objection du Director, réponse négative de la capacité : trois choses."""
    from forge import director as dr
    state = dr.new_state("lot6-t5", "runm_breakout")
    objection_director = dr._objection(state, "decompose", dr.JOIN_GHOST_COVERAGE,
                                       {"regime": "VOID"}, {"last_effect": "CHANGED"})
    desaccord = ack.disagreement_message(_rejected_judgment(), capability="decompose",
                                         run_id="lot6-t5", message=_MSG)
    assert objection_director["from"] == "director" and objection_director["to"] == ["decompose"]
    assert desaccord["from"] == "decompose" and desaccord["to"] == ["director"]
    assert "in_reply_to" not in objection_director and desaccord["in_reply_to"] == "AMD-x-1"
    q = ack.question_entry(_rejected_judgment(), capability="decompose", run_id="lot6-t5",
                           disagreement_id=desaccord["id"])
    assert q["blocking"] is False and q["from"] == "decompose"
    assert set(q["to"]) == {"director", "pierre"} and q["evidence_ref"] == [desaccord["id"]]


def test_la_politique_impute_le_refus_d_identite_a_l_ecrivain_de_la_section(blueprint):
    """Le responsable vient du REGISTRE (qui écrit cette section), jamais de diagnose_join — qui
    dirait `wiremap` — ni du champ `writer` (encore `importer` après un refus). Test de POLITIQUE :
    `next_action` est une fonction pure de (blueprint, state, mesure)."""
    from forge import director as dr
    state = dr.new_state("lot6-t6b", "runm_breakout")
    state["last_problems"] = [{"code": idt.ID_REFERENCED_DROPPED, "producer": "identity_check",
                               "path": "feature_map",
                               "message": "identifiants encore cités en aval : R1c1_hud_objectif_nonvide"}]
    action = dr.next_action(blueprint, state, dr.measure(blueprint))
    assert action["code"] == idt.ID_REFERENCED_DROPPED and action["kind"] == "reconvoke"
    assert action["capability"] == "decompose", "l'objection va à l'écrivain, pas à wiremap"
    assert blueprint["sections"]["feature_map"]["writer"] == "importer"   # le piège évité
    assert "R1c1_hud_objectif_nonvide" in json.dumps(action["message"], ensure_ascii=False)
    assert action["message"]["from"] == "director" and action["message"]["to"] == ["decompose"]
    assert action["message"]["run_id"] == "lot6-t6b"


def test_le_resultat_porte_le_bloc_extrait_sans_le_juger(blueprint, tmp_path):
    fm = blueprint["sections"]["feature_map"]["content"]
    res = cap.invoke_capability(
        "decompose", blueprint, tmp_path / "run", run_id="lot6-t6", attempt=2,
        executor=_executor_returning(fm, suffix=_out({"message_id": "AMD-x-1", "action": "applied",
                                                      "changes": ["ids conservés"]})),
        audit_path=tmp_path / "a.jsonl")
    assert res["ok"], res["problems"]
    assert res["acknowledgement_block"]["block"]["action"] == "applied"
    assert res["acknowledgement_block"]["diagnostic"] == ""
    assert "status" not in res["acknowledgement_block"], "invoke n'a pas à juger (spec §5)"


def test_le_director_journalise_le_desaccord_et_ouvre_la_question(blueprint, tmp_path):
    """L'exécuteur lit l'id du message DANS LE PROMPT (le Director l'y écrit) et le rejette —
    même chemin qu'un agent réel, aucun identifiant deviné par le test."""
    import re

    from forge import director as dr
    fm = blueprint["sections"]["feature_map"]["content"]

    def executor(prompt, sp, pl):
        m = re.search(r"MESSAGE DU DIRECTOR — \w+ (AMD-[^\s\n]+)", prompt)
        bloc = _out({"message_id": m.group(1) if m else "AUCUN", "action": "rejected", "changes": [],
                     "reason": "l'oracle impose main.tscn sur un jeu web"})
        return {"ok": True, "output": "Rapport.\n\n```json\n" + json.dumps(fm, ensure_ascii=False)
                + "\n```\n" + bloc, "tokens": 0, "duration_s": 0.0, "cost_usd": 0.0}

    d = dr.Director(blueprint, tmp_path / "run", run_id="lot6-t6c", executor=executor,
                    audit_path=tmp_path / "a.jsonl", journal_dir=tmp_path / "amendments")
    d.state["last_problems"] = [{"code": idt.ID_REFERENCED_DROPPED, "producer": "identity_check",
                                 "path": "feature_map", "message": "ids cités en aval : R1c1_hud_objectif_nonvide"}]
    r = d.step()
    assert r["decision"]["measure"]["acknowledgement"]["status"] == ack.REJECTED
    desaccords = [m for m in read_messages(tmp_path / "amendments")
                  if m.get("from") == "decompose" and m.get("to") == ["director"]]
    assert len(desaccords) == 1 and desaccords[0]["in_reply_to"] == r["action"]["message"]["id"]
    questions = blueprint["sections"]["questions"]["content"] or []
    assert any(q.get("evidence_ref") == [desaccords[0]["id"]] for q in questions)


def test_un_message_ne_peut_etre_acquitte_deux_fois_dans_un_run():
    """Le second acquittement du même message tombe en unknown_message (spec §4.2)."""
    b, _ = ack.extract_block(_out({"message_id": "AMD-x-1", "action": "applied"}))
    assert _judge(b, deja={"AMD-x-1"})["status"] == ack.UNKNOWN_MESSAGE


def test_le_libelle_s3_n_invite_plus_au_renommage():
    from forge.run_real import default_task_by_step
    t = default_task_by_step("p", ".", profile="full")["s3-decompo"]
    assert "R1..Rn" not in t
    assert "stable" in t.lower()


def test_la_question_est_appendue_a_la_section_questions(blueprint):
    q = ack.question_entry(_rejected_judgment(), capability="decompose", run_id="lot6-t5",
                           disagreement_id="AMD-d-1")
    avant = list(blueprint["sections"]["questions"]["content"] or [])
    bp.write_section(blueprint, "questions", avant + [q], writer="decompose",
                     source={"path": None, "sha256": None, "status": "JOURNAL", "run_id": "lot6-t5"})
    assert blueprint["sections"]["questions"]["content"][-1]["id"] == q["id"]

"""Gate mutation « 100% ou survivant justifié » (C1/C2)."""
import json

from forge.static_oracles import check_mutation_gate, load_mutation_triage


def _res(total, survivors):
    killed = total - len(survivors)
    return {"total": total, "killed": killed, "survived": len(survivors),
            "score": round(killed / total, 3) if total else 1.0, "survivors": survivors}


def test_cent_pourcent_passe():
    res = _res(10, [])
    out = check_mutation_gate(res, None)
    assert out["passed"] is True and out["checked"] is True
    assert out["survivants_non_tries"] == []


def test_survivant_sans_triage_echoue():
    res = _res(10, [{"name": "cmp>=->>", "line": 3}])
    out = check_mutation_gate(res, None)
    assert out["passed"] is False
    assert out["survivants_non_tries"] == ["cmp>=->>@L3"]


def test_survivant_justifie_passe():
    res = _res(10, [{"name": "cmp>=->>", "line": 3}])
    triage = [{"name": "cmp>=->>", "line": 3, "justification": "mutant équivalent : borne inclusive jamais atteinte"}]
    out = check_mutation_gate(res, triage)
    assert out["passed"] is True
    assert out["survivants_non_tries"] == []


def test_justification_vide_echoue():
    res = _res(10, [{"name": "cmp>=->>", "line": 3}])
    triage = [{"name": "cmp>=->>", "line": 3, "justification": "   "}]
    out = check_mutation_gate(res, triage)
    assert out["passed"] is False
    assert out["survivants_non_tries"] == ["cmp>=->>@L3"]


def test_total_zero_checked_false():
    res = _res(0, [])
    out = check_mutation_gate(res, None)
    assert out["passed"] is False and out["checked"] is False


def test_triage_perime_note_non_bloquant():
    # Survivant unique justifié => PASS ; une entrée de triage sans survivant => périmée.
    res = _res(10, [{"name": "A", "line": 3}])
    triage = [
        {"name": "A", "line": 3, "justification": "équivalent"},
        {"name": "B", "line": 9, "justification": "tué depuis / disparu"},
    ]
    out = check_mutation_gate(res, triage)
    assert out["passed"] is True
    assert out["triage_perimes"] == ["B@L9"]


def test_cle_ambigue_non_triable_echoue():
    # Deux mutants distincts partagent (name,line) : un seul triage ne peut pas les
    # justifier tous les deux sans masquer un vrai bug => reste non justifié (ambigu).
    res = _res(10, [{"name": "ge->gt", "line": 5}, {"name": "ge->gt", "line": 5}])
    triage = [{"name": "ge->gt", "line": 5, "justification": "équivalent"}]
    out = check_mutation_gate(res, triage)
    assert out["passed"] is False
    assert any("ambigu" in r for r in out["survivants_non_tries"])


def test_triage_liste_vide_equivaut_a_none():
    res = _res(10, [{"name": "A", "line": 3}])
    assert check_mutation_gate(res, [])["passed"] is False
    assert check_mutation_gate(res, None)["passed"] is False


def test_survivant_sans_line():
    # line manquante => clé (name, None) ; un triage même clé le justifie.
    res = _res(10, [{"name": "A"}])
    assert check_mutation_gate(res, None)["passed"] is False
    triage = [{"name": "A", "line": None, "justification": "équivalent"}]
    assert check_mutation_gate(res, triage)["passed"] is True


def test_load_triage(tmp_path):
    entries = [{"name": "A", "line": 3, "justification": "x"}]
    (tmp_path / "mutation_triage.json").write_text(json.dumps(entries), encoding="utf-8")
    assert load_mutation_triage(tmp_path) == entries


def test_load_triage_absent_none(tmp_path):
    assert load_mutation_triage(tmp_path) is None


def test_load_triage_corrompu_none(tmp_path):
    (tmp_path / "mutation_triage.json").write_text("{pas json", encoding="utf-8")
    assert load_mutation_triage(tmp_path) is None


def test_load_triage_non_liste_none(tmp_path):
    (tmp_path / "mutation_triage.json").write_text(json.dumps({"a": 1}), encoding="utf-8")
    assert load_mutation_triage(tmp_path) is None

# -*- coding: utf-8 -*-
"""FRONTIERE 2 — le diagnostic de solvabilite devient RE-INSTRUABLE depuis `state.json`
(GO Pierre 2026-08-18).

AVANT : la Forge sait qu'un oracle a echoue.
APRES : elle sait POURQUOI, COMBIEN, sur QUELLES GRAINES, avec QUEL BUDGET, avec QUELLE
PREUVE — et peut re-instruire la decision depuis son propre recu.

LA MESURE EXISTE DEJA, c'est sa CAUSALITE qui se perdait :

    solvability.gd -> recu JSON -> godot_oracle -> FORGE_ORACLE_SUMMARY   (abd0504)
                                                       |
                                    stdout -> evidence/oracle_<jeu>.log   (.gitignore:81)
                                                       X
                             driver ne garde que returncode + evidence_path

ON NE RECOPIE PAS LE STDOUT. Le lot precedent a etabli un resume STRUCTURE ; c'est LUI qui
voyage. Recopier le flux brut ferait entrer banniere moteur et warnings dans un detail SIGNE.

QUATRE ROLES DISTINCTS, conserves separement (doctrine de lignee causale) :
    verdict  ce que le GATE decide          -> `software_verdict`, inchange
    mesure   ce qui s'est REELLEMENT produit -> `solvability_measures` (ce lot)
    preuve   OU cela se verifie              -> `evidence_path`, inchange
    reason   POURQUOI le verdict existe      -> porte par la mesure quand elle en a une

CONTRAINTE DE SIGNATURE (lecon e48801c) : `Verdict` est signe par `asdict` — un champ de plus
y invaliderait les signatures DEJA EMISES. Le transport passe donc par `OracleResult` puis
`GateResult`, NON signes, et atterrit dans le `detail` du pas — dictionnaire libre, ou une
cle neuve n'affecte que les recus futurs.
"""
from __future__ import annotations

import dataclasses
import json

from forge.gate import GateResult
from forge.oracle import OracleResult, extract_summary


RESUME_OK = ('FORGE_ORACLE_SUMMARY {"mecanique":true,"solvabilite":'
             '{"verdict":"OK","trials":14,"won":14,"lost":0,"failed_seeds":[]}}')
RESUME_FAIL = ('FORGE_ORACLE_SUMMARY {"mecanique":true,"solvabilite":'
               '{"verdict":"FAIL","trials":14,"won":5,"lost":9,"failed_seeds":[1,2,4]}}')
RESUME_BLOCKED = ('FORGE_ORACLE_SUMMARY {"mecanique":true,"solvabilite":'
                  '{"verdict":"BLOCKED","trials":20,"trials_executes":11,"won":3,"lost":8,'
                  '"failed_seeds":[1,2],"reason":"budget total epuise (total_timeout_s=200)"}}')


# --- extraction depuis un flux bruite ----------------------------------------------------


def test_SUCCES_les_mesures_sont_extraites():
    s = extract_summary("Godot Engine v4.6.3\n[godot_oracle] OK\n" + RESUME_OK)
    assert s["solvabilite"]["verdict"] == "OK"
    assert s["solvabilite"]["won"] == 14
    assert s["mecanique"] is True


def test_ECHEC_les_mesures_disent_COMBIEN_et_sur_QUELLES_GRAINES():
    """Le coeur de la capacite : un FAIL cesse d'etre un mot. 5/14 et les graines nommees."""
    s = extract_summary(RESUME_FAIL)
    m = s["solvabilite"]
    assert (m["won"], m["lost"], m["trials"]) == (5, 9, 14)
    assert m["failed_seeds"] == [1, 2, 4]


def test_INTERRUPTION_le_partiel_SURVIT_avec_sa_raison():
    """Un BLOCKED doit dire ce qu'il a mesure AVANT de s'arreter, et pourquoi il s'est
    arrete — c'est toute la difference avec une mort de processus, qui ne rend rien."""
    m = extract_summary(RESUME_BLOCKED)["solvabilite"]
    assert m["verdict"] == "BLOCKED"
    assert m["trials"] == 20 and m["trials_executes"] == 11, "declare ET realise"
    assert (m["won"], m["lost"]) == (3, 8), "les essais deja mesures survivent"
    assert "budget" in m["reason"]


def test_absence_de_resume_rend_None_jamais_une_exception():
    """Best-effort strict : un oracle qui n'emet pas de resume (jeu non-Godot, version
    anterieure) ne doit pas devenir un echec de parsing."""
    for flux in ("", None, "Godot Engine\nrien d interessant\n", "FORGE_ORACLE_SUMMARY {casse"):
        assert extract_summary(flux) is None


def test_le_DERNIER_resume_gagne():
    assert extract_summary(RESUME_OK + "\n" + RESUME_FAIL)["solvabilite"]["verdict"] == "FAIL"


# --- transport jusqu'au consommateur ------------------------------------------------------


def test_OracleResult_PORTE_le_resume():
    champs = {f.name for f in dataclasses.fields(OracleResult)}
    assert "summary" in champs
    assert OracleResult(spec=None, passed=True, returncode=0,
                        evidence_path="e.log").summary is None


def test_GateResult_PROPAGE_le_resume():
    """Le maillon que le driver voit reellement : sans lui, la mesure s'arreterait au gate."""
    champs = {f.name for f in dataclasses.fields(GateResult)}
    assert "summary" in champs


def test_la_FORME_SIGNEE_de_Verdict_est_INCHANGEE():
    """Lecon e48801c : `sign_verdict` signe `asdict(verdict)`. Un champ nouveau y
    invaliderait les signatures DEJA EMISES — le transport passe donc a cote."""
    from forge.verdict import Verdict
    assert {f.name for f in dataclasses.fields(Verdict)} == {
        "project", "software_verdict", "evidence_verdict", "claim_verdict",
        "returncode", "evidence_path"}


def test_les_mesures_restent_du_JSON_serialisable():
    """Elles atterrissent dans un `detail` qui sera SIGNE : tout doit etre serialisable et
    stable a l'ordre des cles (`json.dumps(..., sort_keys=True)` du HMAC)."""
    s = extract_summary(RESUME_BLOCKED)
    assert json.loads(json.dumps(s, sort_keys=True)) == s

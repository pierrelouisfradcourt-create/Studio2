# UN PROCESSUS INTERROMPU N'A PAS RENDU DE VERDICT (GO Pierre 2026-08-17).
#
# Quatrieme question de la regle ratifiee : « le processus a-t-il rendu un verdict valide ? ».
# `verdict.py:42` repondait avec un booleen a deux etats — `"OK" if passed else "FAIL"` — alors
# que `oracle.py` produit `passed=False` dans DEUX situations de nature OPPOSEE :
#     l'oracle a JUGE et condamne        -> FAIL legitime
#     l'oracle est MORT avant de juger   -> rien n'est prouve, donc BLOCKED
#
# CAS REEL MESURE le 2026-08-17, bomberman_3d, run `proof3` (commit c19add3) :
#   evidence/oracle_bomberman_3d.log : "--- TIMEOUT after 300s ---"
#   et AVANT la mort : "=== RESULT: 691 passed, 0 failed ===" puis "[godot_oracle] OK :
#   run_tests.gd (mecanique)" — la seule mesure ABOUTIE etait VERTE. Le processus est mort
#   pendant la solvabilite, dont le budget declare (20 essais x 60 s = jusqu'a 1200 s) est
#   arithmetiquement incompatible avec la limite de 300 s. Appeler cela un echec PRODUIT
#   serait faux deux fois : aucun verdict rendu, et la seule mesure obtenue est verte.
#
# LE FAIT EXISTAIT DEJA A LA SOURCE, il etait DISSOUS. `oracle.py` sait qu'il s'agit d'un
# timeout — il l'ecrit en clair dans le journal — mais l'encode dans `returncode = -2`, un
# NOMBRE MAGIQUE, et `OracleResult` ne portait aucun champ dedie. Motif « mesure puis perdu »,
# ici entre deux MODULES et non entre deux etapes.
#
# CONTRAINTE DE CONCEPTION, verifiee AVANT d'ecrire : `sign_verdict` signe `asdict(verdict)`
# — TOUT le dataclass. Ajouter un champ a `Verdict` changerait la charge signee et
# invaliderait les signatures DEJA EMISES. Le fait voyage donc dans `OracleResult` (NON
# signe) et n'influence que la VALEUR de `software_verdict`. La forme de `Verdict` est
# inchangee : c'est l'objet de `test_la_forme_signee_de_Verdict_est_INCHANGEE`.
#
# VOCABULAIRE : rien d'invente. `BLOCKED` est deja dans `RECEIPT_STATUSES` (verdict.py:106) et
# porte deja cette semantique ailleurs — `driver.py:2953` : « etape jamais terminee : rien de
# prouve » ; `driver.py:1682` : « hypothese inconnue = BLOCKED » pour `src_root` absent.
from __future__ import annotations

import dataclasses
import subprocess
from pathlib import Path

from forge.oracle import OracleResult, OracleSpec, run_oracle
from forge.verdict import Verdict, build_verdict


def _spec(tmp_path: Path) -> OracleSpec:
    return OracleSpec(project="p", cwd=tmp_path, command=["python", "-c", "pass"])


# --- le verdict a TROIS etats, plus deux ---------------------------------------------


def test_un_timeout_rend_BLOCKED_jamais_FAIL(tmp_path):
    """LE CAS QUI FALSIFIE : mort du processus => rien n'est prouve."""
    v = build_verdict("p", passed=False, returncode=-2,
                      evidence_path=tmp_path / "e.log", timed_out=True)
    assert v.software_verdict == "BLOCKED"


def test_un_ECHEC_REEL_rend_toujours_FAIL(tmp_path):
    """CONTRE-EPREUVE INDISPENSABLE : sans ce test, on aurait blanchi TOUS les echecs
    d'oracle. Un oracle qui a juge et condamne garde son FAIL."""
    v = build_verdict("p", passed=False, returncode=1,
                      evidence_path=tmp_path / "e.log", timed_out=False)
    assert v.software_verdict == "FAIL"


def test_un_succes_reste_OK(tmp_path):
    v = build_verdict("p", passed=True, returncode=0, evidence_path=tmp_path / "e.log")
    assert v.software_verdict == "OK"


def test_le_defaut_est_NON_TIMEOUT(tmp_path):
    """Retrocompatibilite : un appelant qui ignore le nouveau parametre garde l'ancien
    comportement exact. Aucun appel existant n'est silencieusement requalifie."""
    v = build_verdict("p", passed=False, returncode=1, evidence_path=tmp_path / "e.log")
    assert v.software_verdict == "FAIL"


# --- la contrainte de signature -------------------------------------------------------


def test_la_forme_signee_de_Verdict_est_INCHANGEE(tmp_path):
    """`sign_verdict` signe `asdict(verdict)` : tout champ NOUVEAU invaliderait les
    signatures deja emises. Le fait « timeout » ne doit donc PAS entrer dans `Verdict` —
    il n'en change que la VALEUR de `software_verdict`."""
    champs = {f.name for f in dataclasses.fields(Verdict)}
    assert champs == {"project", "software_verdict", "evidence_verdict", "claim_verdict",
                      "returncode", "evidence_path"}
    assert "timed_out" not in champs, "un champ signe de plus casserait les verdicts emis"


# --- le fait est NOMME, plus un nombre magique ----------------------------------------


def test_OracleResult_porte_le_fait_EXPLICITEMENT(tmp_path):
    """`returncode == -2` etait la SEULE trace du timeout : un nombre magique, que rien
    n'obligeait l'aval a interpreter. Le fait devient un champ nomme."""
    champs = {f.name for f in dataclasses.fields(OracleResult)}
    assert "timed_out" in champs
    assert OracleResult(spec=_spec(tmp_path), passed=True, returncode=0,
                        evidence_path=tmp_path / "e.log").timed_out is False


def test_run_oracle_MARQUE_un_vrai_timeout(tmp_path, monkeypatch):
    """Bout de chaine reel : c'est `oracle.run_oracle` qui doit poser le marqueur quand
    `subprocess` leve `TimeoutExpired` — pas un appelant qui devinerait depuis `-2`."""
    def _timeout(*a, **k):
        raise subprocess.TimeoutExpired(cmd=["x"], timeout=1, output="partiel", stderr="")

    monkeypatch.setattr(subprocess, "run", _timeout)
    res = run_oracle(_spec(tmp_path), evidence_dir=tmp_path, timeout=1)
    assert res.timed_out is True
    assert res.passed is False
    assert res.returncode == -2, "le code historique est CONSERVE, il n'est plus SEUL"


def test_un_echec_ordinaire_n_est_PAS_marque_timeout(tmp_path):
    """Contre-epreuve du marqueur : un oracle qui sort en non-zero SANS mourir n'est pas
    un timeout. Sinon le marqueur ne discriminerait rien."""
    spec = OracleSpec(project="p", cwd=tmp_path,
                      command=["python", "-c", "import sys; sys.exit(3)"])
    res = run_oracle(spec, evidence_dir=tmp_path, timeout=60)
    assert res.timed_out is False
    assert res.passed is False and res.returncode == 3

# -*- coding: utf-8 -*-
"""Le sceau `evidence_sha256` survit-il au commit ? (GO Pierre 2026-08-20)

DEFAUT MESURE : **1 sceau valide sur 90** dans `EVIDENCE/runs/`. Aucune donnee n'avait ete
alteree — c'est git qui reecrivait les octets.

    producteur ecrit du CRLF (mode texte Windows)
        -> `.gitattributes` : `*.json text eol=lf` renormalise en LF au commit
        -> `evidence_sha256` hache les OCTETS (`read_bytes`)
        -> sceau INVALIDE des le commit

Familles scellees mesurees : `.json` et `.txt` sont normalises (donc casses), `.log`
ne l'est pas — son probleme est autre : il n'est pas versionne (37 recus sur 90).

`.gitattributes` n'est PAS en cause et n'est pas touche : sa regle vient d'un incident reel
(2026-06-27, un seul fichier CRLF -> diff de 3500 lignes). C'est le PRODUCTEUR qui doit
respecter la convention du depot.

CE QUE CE FICHIER TESTE, ET POURQUOI PAS AUTRE CHOSE. Verifier « le fichier ne contient pas
de CRLF » ne prouverait que la moitie : ce qui compte est que le sceau tienne APRES le
passage par git, filtres compris. On fait donc traverser la frontiere a la preuve —
`git hash-object --path=<chemin>` applique les VRAIS attributs du depot, `git cat-file` rend
les octets REELLEMENT stockes, et on compare les deux sha256.
"""
from __future__ import annotations

import hashlib
import subprocess
import sys
from pathlib import Path

import pytest

RACINE = Path(__file__).resolve().parents[2]
if str(RACINE / "scripts") not in sys.path:
    sys.path.insert(0, str(RACINE / "scripts"))

from forge.mutation_proof import TRIAGE_FILENAME, emit_mutation_receipt  # noqa: E402
from forge.oracle import OracleSpec, run_oracle  # noqa: E402
from forge.verdict import sha256_file  # noqa: E402

# Chemin FICTIF mais realiste : il ne sert qu'a faire appliquer les attributs du depot
# (`*.json text eol=lf`). Aucun fichier n'est ecrit a cet endroit.
CHEMIN_ATTRIBUTS_JSON = "EVIDENCE/runs/sonde/evidence/mutation_sonde.json"
CHEMIN_ATTRIBUTS_LOG = "EVIDENCE/runs/sonde/evidence/oracle_sonde.log"


def _octets_stockes_par_git(fichier: Path, chemin_pour_attributs: str) -> bytes:
    """Ce que git STOCKERAIT reellement pour ce contenu a ce chemin, filtres appliques."""
    sha = subprocess.run(
        ["git", "hash-object", "-w", "--path", chemin_pour_attributs, str(fichier)],
        capture_output=True, cwd=RACINE, check=True).stdout.strip().decode()
    return subprocess.run(["git", "cat-file", "-p", sha],
                          capture_output=True, cwd=RACINE, check=True).stdout


def _assert_sceau_survit(fichier: Path, chemin_attributs: str) -> None:
    """LE controle du lot : le sceau calcule sur le disque vaut celui des octets stockes."""
    sur_disque = sha256_file(fichier)
    assert sur_disque, "fichier illisible : le test ne prouverait rien"
    stocke = hashlib.sha256(_octets_stockes_par_git(fichier, chemin_attributs)).hexdigest()
    assert sur_disque == stocke, (
        "le sceau ne survit pas au commit : git a reecrit les octets "
        f"({fichier.read_bytes().count(bytes([13, 10]))} CRLF dans le fichier)")


@pytest.fixture()
def evidence_mutation(tmp_path):
    jeu = tmp_path / "jeu"
    jeu.mkdir()
    (jeu / "main.py").write_text("x = 1\n", encoding="utf-8")
    (jeu / TRIAGE_FILENAME).write_text("{}", encoding="utf-8")
    ev = tmp_path / "ev"
    emit_mutation_receipt("sonde-sceau", jeu, ["main.py"],
                          {"total": 2, "killed": 2, "survivors": []}, evidence_dir=ev)
    fichiers = sorted(ev.glob("*.json"))
    assert fichiers, "le producteur n'a ecrit aucune evidence : test muet"
    return fichiers[0]


def test_le_sceau_de_l_evidence_MUTATION_survit_au_commit(evidence_mutation):
    _assert_sceau_survit(evidence_mutation, CHEMIN_ATTRIBUTS_JSON)


def test_l_evidence_MUTATION_est_ecrite_en_LF(evidence_mutation):
    """Le POURQUOI du test precedent, isole : c'est le CRLF qui cassait le sceau."""
    assert bytes([13, 10]) not in evidence_mutation.read_bytes()


def test_le_LOG_D_ORACLE_est_ecrit_en_LF(tmp_path):
    """Le log est scelle lui aussi (37 des 90 recus mesures) — mais PAS pour la meme raison.

    MESURE QUI A CORRIGE MA PREMIERE REDACTION : `.gitattributes` ne declare AUCUNE regle
    pour `*.log` (`text: unspecified`). Git ne renormalise donc pas ces fichiers, et leur
    sceau survit au commit MEME ecrit en CRLF. Ma premiere version assertait la survie du
    sceau : elle restait VERTE quand on retirait `newline=""` — un test qui ne pouvait pas
    rougir, decouvert en falsifiant le correctif, pas en le relisant.

    L'assertion porte donc sur ce qui change reellement : le log sort en LF. Le correctif
    reste justifie sans defaut mesure, et la raison est nommee — le sceau ne doit pas
    dependre de l'ABSENCE d'une regle dans `.gitattributes`. Ajouter `*.log text eol=lf`
    demain casserait 37 sceaux en silence ; ecrire en LF rend cette question sans objet.
    """
    ev = tmp_path / "ev"
    res = run_oracle(
        OracleSpec(project="sonde", command=[sys.executable, "-c", "print('une ligne')"],
                   cwd=tmp_path),
        evidence_dir=ev, timeout=60)
    fichier = Path(res.evidence_path)
    assert fichier.is_file(), "aucun log ecrit : test muet"
    assert bytes([13, 10]) not in fichier.read_bytes(), \
        "le log sort en CRLF : son sceau dependrait de l'absence de regle `*.log`"
    # et il reste bien scelle-compatible aujourd'hui
    _assert_sceau_survit(fichier, CHEMIN_ATTRIBUTS_LOG)


def test_le_controle_SAIT_VOIR_un_fichier_CRLF(tmp_path):
    """CONTROLE NEGATIF. Sans lui, les trois tests ci-dessus pourraient etre verts parce que
    le controle est inerte — et non parce que le sceau tient. On fabrique donc exactement le
    defaut d'origine : un JSON ecrit en mode texte Windows."""
    faux = tmp_path / "faux.json"
    faux.write_bytes(b'{\r\n "a": 1\r\n}\r\n')
    with pytest.raises(AssertionError, match="ne survit pas au commit"):
        _assert_sceau_survit(faux, CHEMIN_ATTRIBUTS_JSON)

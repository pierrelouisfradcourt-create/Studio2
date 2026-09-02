# -*- coding: utf-8 -*-
"""La validite d'une preuve ne depend plus du repertoire courant (GO Pierre 2026-08-20).

DEFAUT MESURE. `sha256_file(receipt.evidence_path)` resolvait un chemin RELATIF contre le
`cwd` du process. Meme recu, meme fichier, deux repertoires :

    cwd = racine du depot  ->  RESOUT
    cwd = ailleurs         ->  VIDE   (donc « evidence alteree/absente »)

Une preuve dont la validite depend de l'endroit d'ou on la verifie n'est pas une preuve.

TEMPS 1 — LE LECTEUR SEUL. Aucun producteur n'est touche, aucun recu n'est modifie. 63 des
90 recus existants portent un chemin ABSOLU : ils doivent continuer de verifier a
l'identique. Rendre la forme STOCKEE canonique est le temps 2, avec son rayon d'impact
propre (42 fichiers de test, dont un qui asserte la forme absolue).
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

import pytest

RACINE = Path(__file__).resolve().parents[2]
if str(RACINE / "scripts") not in sys.path:
    sys.path.insert(0, str(RACINE / "scripts"))

from forge.verdict import (  # noqa: E402
    REPO_ROOT, resolve_evidence_path, sha256_evidence, sha256_file,
)


@pytest.fixture()
def evidence(tmp_path, monkeypatch):
    """Une evidence REELLE sous la racine du depot, nettoyee ensuite."""
    d = REPO_ROOT / "EVIDENCE" / "reports" / "_sonde_resolution"
    d.mkdir(parents=True, exist_ok=True)
    f = d / "evidence.json"
    f.write_bytes(b'{"sonde": 1}\n')
    yield f
    f.unlink(missing_ok=True)
    try:
        d.rmdir()
    except OSError:
        pass


def _relatif(f: Path) -> str:
    return f.relative_to(REPO_ROOT).as_posix()


def test_un_chemin_RELATIF_se_resout_contre_la_RACINE_pas_le_cwd(evidence, tmp_path):
    """LE test du lot. Il rougit si l'on revient a `sha256_file`."""
    attendu = sha256_file(evidence)
    assert attendu, "fixture illisible : le test ne prouverait rien"
    origine = os.getcwd()
    try:
        os.chdir(tmp_path)                      # DELIBEREMENT ailleurs
        assert sha256_evidence(_relatif(evidence)) == attendu
    finally:
        os.chdir(origine)


def test_l_ANCIEN_comportement_echouait_bien_ailleurs(evidence, tmp_path):
    """CONTROLE NEGATIF. Sans lui, le test precedent pourrait etre vert parce que le `cwd`
    n'a aucun effet ici — et non parce que la resolution est corrigee. On rejoue donc
    l'ancien appel, qui doit ECHOUER depuis un autre repertoire."""
    origine = os.getcwd()
    try:
        os.chdir(tmp_path)
        assert sha256_file(_relatif(evidence)) == "", \
            "l'ancien appel resout encore : le test precedent ne prouve rien"
    finally:
        os.chdir(origine)


def test_un_chemin_ABSOLU_est_rendu_TEL_QUEL(evidence, tmp_path):
    """63 des 90 recus existants en portent un : ce lot ne doit en casser aucun."""
    assert resolve_evidence_path(evidence) == evidence
    origine = os.getcwd()
    try:
        os.chdir(tmp_path)
        assert sha256_evidence(str(evidence)) == sha256_file(evidence)
    finally:
        os.chdir(origine)


def test_un_chemin_absolu_HORS_du_depot_n_est_pas_reancre(tmp_path):
    """Un chemin hors depot reste hors depot : on resout, on ne DEPLACE pas."""
    dehors = tmp_path / "ailleurs.json"
    dehors.write_bytes(b"{}")
    assert resolve_evidence_path(dehors) == dehors


def test_une_evidence_ABSENTE_rend_une_chaine_VIDE(tmp_path):
    """Comportement conserve : illisible => '' , et l'appelant conclut « alteree/absente ».
    Le changer ferait passer une absence pour une correspondance."""
    assert sha256_evidence("EVIDENCE/reports/_sonde_inexistante/rien.json") == ""

# --- CABLAGE : le VRAI verificateur passe-t-il par le resolveur ? --------------------------
#
# Les tests ci-dessus prouvent que `sha256_evidence` resout correctement. Ils ne prouvent PAS
# que les consommateurs l'appellent : en les remettant a `sha256_file`, la suite restait
# VERTE. Meme trou que pour un cablage d'outil — la fonction est testee, le branchement non.
# Celui-ci fait tourner le verificateur REEL avec un recu a chemin RELATIF, depuis un AUTRE
# repertoire courant. Il rougit si le consommateur cesse de passer par l'autorite.
from forge.mutation_proof import (  # noqa: E402
    TRIAGE_FILENAME, emit_mutation_receipt, verify_mutation_receipt,
)
from forge.verdict import sign_receipt  # noqa: E402
from dataclasses import replace  # noqa: E402


@pytest.fixture()
def recu_a_chemin_relatif(tmp_path):
    """Un recu REEL dont `evidence_path` est RELATIF a la racine du depot.

    On re-signe apres avoir rendu le chemin relatif : sans cela le recu serait invalide pour
    une raison ETRANGERE au sujet (signature rompue), et le test ne dirait rien de la
    resolution. Re-signer une fixture n'est pas falsifier une preuve historique — rien de ce
    qui est produit ici ne quitte le test.
    """
    jeu = REPO_ROOT / "EVIDENCE" / "reports" / "_sonde_cablage"
    (jeu / "evidence").mkdir(parents=True, exist_ok=True)
    (jeu / "main.py").write_bytes(b"x = 1\n")
    (jeu / TRIAGE_FILENAME).write_bytes(b"{}")
    signe = emit_mutation_receipt(
        "sonde-cablage", jeu, ["main.py"],
        {"total": 2, "killed": 2, "survivors": []}, evidence_dir=jeu / "evidence")
    # ROBUSTE AUX DEUX FORMES : depuis le temps 2 le producteur ecrit deja du relatif ;
    # avant, il ecrivait de l absolu. La fixture veut un chemin RELATIF, quelle que soit
    # la forme rendue — l ancrer sur une seule l aurait cassee au lot suivant.
    relatif = canonical_evidence_path(signe.receipt.evidence_path)
    recu = replace(signe.receipt, evidence_path=relatif)
    yield recu, sign_receipt(recu), jeu
    for f in sorted(jeu.rglob("*"), reverse=True):
        f.unlink() if f.is_file() else f.rmdir()
    jeu.rmdir()


def test_CABLAGE_le_verificateur_REEL_resout_depuis_un_autre_repertoire(
        recu_a_chemin_relatif, tmp_path):
    from dataclasses import asdict
    recu, signature, jeu = recu_a_chemin_relatif
    origine = os.getcwd()
    try:
        os.chdir(tmp_path)
        res = verify_mutation_receipt(asdict(recu), signature, "sonde-cablage", jeu)
    finally:
        os.chdir(origine)
    fautes = [r for r in res["raisons"] if "vidence" in r]
    assert not fautes, (
        "le verificateur ne passe PAS par le resolveur : il a juge l'evidence "
        f"absente depuis un autre repertoire -> {fautes}")

# --- CABLAGE 2/2 : le controle de PROVENANCE de l'agregat ----------------------------------
#
# La falsification a montre que le site de `verdict.py` restait NON GARDE : le remettre a
# `sha256_file` laissait la suite verte. Un cablage qu'aucun test ne surveille est un
# cablage qui se detachera sans bruit.
from forge.verdict import build_aggregate_verdict, make_signed_receipt  # noqa: E402


def _recu(nom, chemin_relatif):
    return make_signed_receipt(nom, "sonde-agg", "OK", {"x": 1},
                               evidence_path=chemin_relatif)


def test_CABLAGE_AGREGAT_la_provenance_resout_depuis_un_autre_repertoire(evidence, tmp_path):
    """Le sceau est calcule A LA CREATION et re-verifie a l'agregation. Les deux doivent
    parler du MEME fichier, quel que soit le repertoire courant de chacun."""
    rel = _relatif(evidence)
    origine = os.getcwd()
    try:
        os.chdir(tmp_path)                       # creation ET agregation depuis AILLEURS
        code, archi, wiremap = (_recu(n, rel) for n in ("code", "archi", "wiremap"))
        agg = build_aggregate_verdict(
            "sonde", "sonde-agg", code, archi, wiremap, "personne", redteam_ran=False)
    finally:
        os.chdir(origine)
    rompues = [f for f in agg.humangate_flags if "provenance rompue" in f]
    assert not rompues, (
        "l'agregat juge la provenance rompue depuis un autre repertoire : "
        f"le controle ne passe pas par le resolveur -> {rompues}")

# --- TEMPS 2 : la forme STOCKEE devient CANONIQUE -----------------------------------------
#
# Le temps 1 a rendu le LECTEUR capable des deux formes. Ces tests portent sur ce que le
# PRODUCTEUR ecrit desormais. Les 63 recus existants ne sont PAS reecrits : leur forme
# absolue reste lisible, et c est ce qui rend ce lot sur.
from forge.verdict import canonical_evidence_path  # noqa: E402


def test_CANONIQUE_un_chemin_sous_la_racine_devient_RELATIF(evidence):
    can = canonical_evidence_path(evidence)
    assert not Path(can).is_absolute(), "la forme stockee reste absolue"
    assert can == _relatif(evidence)
    assert chr(92) not in can, "separateurs Windows : la forme stockee doit etre POSIX"


def test_CANONIQUE_un_chemin_HORS_du_depot_est_rendu_TEL_QUEL(tmp_path):
    """Inventer une forme relative pour un chemin hors depot masquerait qu il est ailleurs."""
    dehors = tmp_path / "ailleurs.json"
    assert canonical_evidence_path(dehors) == str(dehors)


def test_CANONIQUE_et_RESOLVE_sont_SYMETRIQUES(evidence):
    """L invariant du couple : ce qu on stocke doit se relire sur le MEME fichier."""
    assert resolve_evidence_path(canonical_evidence_path(evidence)) == evidence.resolve()


def test_CABLAGE_le_PRODUCTEUR_REEL_ecrit_desormais_du_RELATIF():
    """Preuve de CABLAGE : ce n est pas la fonction qu on teste, c est ce que le vrai
    emetteur de recu inscrit dans `evidence_path`."""
    jeu = REPO_ROOT / "EVIDENCE" / "reports" / "_sonde_t2"
    (jeu / "evidence").mkdir(parents=True, exist_ok=True)
    (jeu / "main.py").write_bytes(b"x = 1\n")
    (jeu / TRIAGE_FILENAME).write_bytes(b"{}")
    try:
        signe = emit_mutation_receipt(
            "sonde-t2", jeu, ["main.py"],
            {"total": 2, "killed": 2, "survivors": []}, evidence_dir=jeu / "evidence")
        stocke = signe.receipt.evidence_path
        assert not Path(stocke).is_absolute(), (
            f"le producteur ecrit encore un chemin absolu : {stocke}")
        assert stocke.startswith("EVIDENCE/reports/_sonde_t2/")
        # et le sceau porte bien le fichier DESIGNE
        assert sha256_evidence(stocke) == signe.receipt.evidence_sha256
    finally:
        for f in sorted(jeu.rglob("*"), reverse=True):
            f.unlink() if f.is_file() else f.rmdir()
        jeu.rmdir()

def test_CABLAGE_make_signed_receipt_ecrit_lui_aussi_du_RELATIF(evidence):
    """DERNIER producteur non garde, trouve en falsifiant — pas en relisant.

    `test_CABLAGE_le_PRODUCTEUR_REEL...` passe par `mutation_proof` : remettre les
    producteurs de `verdict.py` a `str()` laissait la suite VERTE. Et `test_provenance.py`
    ne peut pas les attraper non plus : il ecrit dans `tmp_path`, donc HORS du depot, ou la
    forme canonique EST le chemin absolu.

    Il faut donc une evidence SOUS LA RACINE pour que la difference existe.
    """
    sr = make_signed_receipt("code", "sonde-vp", "OK", {"returncode": 0},
                             evidence_path=str(evidence))
    assert not Path(sr.receipt.evidence_path).is_absolute(), (
        f"`make_signed_receipt` ecrit encore un chemin absolu : {sr.receipt.evidence_path}")
    assert sr.receipt.evidence_path == _relatif(evidence)
    # le sceau doit toujours designer le bon fichier
    assert sr.receipt.evidence_sha256 == sha256_file(evidence)

# -*- coding: utf-8 -*-
"""Un recu ne scelle QUE ce que le depot peut honorer (OPTION A, GO Pierre 2026-08-20).

CONTRADICTION TRANCHEE. Deux regles ratifiees se contredisaient :
  · le RECU posait un `evidence_sha256` sur `oracle_<jeu>.log` — donc le declarait PREUVE ;
  · `.gitignore:81` (`*.log`) l'exclut — donc le declare BRUIT.
Mesure : 71 logs d'oracle sur disque, 0 suivis par git, 37 recus versionnes les citant. Sur
un clone frais, ces 37 sceaux ne peuvent QUE echouer.

CRITERE RETENU : `.gitignore` lui-meme, pas une liste d'extensions. Il ENCODE DEJA la
distinction, exceptions comprises — verifie ici meme :
    oracle_<jeu>.log            IGNORE        -> flux, non scelle
    mutation_*.json             versionnable  -> preuve, scelle
    knowledge_base/proofs/*.log versionnable  -> exception ratifiee 2026-07-13, scelle

Doctrine appliquee (OPTION C, ratifiee 2026-08-04) : « un registre versionne qui cite un
fichier ignore cree une reference que le depot ne peut pas honorer ».
"""
from __future__ import annotations

import sys
from pathlib import Path

import pytest

RACINE = Path(__file__).resolve().parents[2]
if str(RACINE / "scripts") not in sys.path:
    sys.path.insert(0, str(RACINE / "scripts"))

from forge.verdict import (  # noqa: E402
    REPO_ROOT, SEAL_SKIP_KEY, evidence_is_sealable, make_signed_receipt, sha256_file,
    verify_receipt,
)


@pytest.fixture()
def deux_evidences():
    """Un FLUX et une PREUVE, cote a cote dans le meme dossier d'evidence REEL."""
    d = REPO_ROOT / "EVIDENCE" / "runs" / "_sonde_optiona" / "evidence"
    d.mkdir(parents=True, exist_ok=True)
    flux = d / "oracle_sonde.log"
    flux.write_bytes(b"sortie d oracle\n")
    preuve = d / "mutation_sonde.json"
    preuve.write_bytes(b'{"a": 1}\n')
    yield flux, preuve
    for f in (flux, preuve):
        f.unlink(missing_ok=True)
    d.rmdir()
    d.parent.rmdir()


def test_le_critere_est_GITIGNORE_pas_une_liste_d_extensions(deux_evidences):
    """Le meme suffixe `.log` donne deux reponses OPPOSEES selon l'emplacement — c'est la
    preuve que le critere n'est pas l'extension."""
    flux, preuve = deux_evidences
    assert not evidence_is_sealable(flux), "un flux ignore ne devrait pas etre scellable"
    assert evidence_is_sealable(preuve)
    # l'exception ratifiee du 2026-07-13 est honoree SANS etre codee en dur ici
    assert evidence_is_sealable("knowledge_base/proofs/grid_nav_probe.log")


def test_un_FLUX_n_est_PAS_scelle_et_le_recu_DIT_pourquoi(deux_evidences):
    """Un sceau vide SANS motif serait indiscernable d'un calcul rate. Le motif voyage donc
    avec le recu (patron `checked:false` + `reason`, ratifie 2026-08-17)."""
    flux, _ = deux_evidences
    sr = make_signed_receipt("code", "r-flux", "OK", {"x": 1}, evidence_path=str(flux))
    assert sr.receipt.evidence_sha256 == "", "un flux ne doit porter AUCUN sceau"
    marque = sr.receipt.detail.get(SEAL_SKIP_KEY)
    assert marque and marque["sealed"] is False
    assert marque["reason"] == "FLUX_D_EXPLOITATION_IGNORE_PAR_GIT"
    # le POINTEUR reste : on cesse de PROMETTRE, on ne cesse pas de TRACER
    assert sr.receipt.evidence_path.endswith("oracle_sonde.log")


def test_une_PREUVE_reste_scellee(deux_evidences):
    """Option A ne desarme pas le scellement : elle le limite a ce qui est honorable."""
    _, preuve = deux_evidences
    sr = make_signed_receipt("code", "r-preuve", "OK", {"x": 1}, evidence_path=str(preuve))
    assert sr.receipt.evidence_sha256 == sha256_file(preuve)
    assert SEAL_SKIP_KEY not in sr.receipt.detail


def test_le_recu_d_un_flux_reste_SIGNE_et_verifiable(deux_evidences):
    """Ne rien sceller n'est pas ne rien signer : le recu garde son authenticite."""
    flux, _ = deux_evidences
    sr = make_signed_receipt("code", "r-flux", "OK", {"x": 1}, evidence_path=str(flux))
    assert verify_receipt(sr.receipt, sr.signature) is True


def test_un_flux_MODIFIE_ne_declenche_AUCUNE_rupture_de_provenance(deux_evidences):
    """LE controle du lot. Avant : le sceau echouait des le clone et criait « evidence
    alteree/absente » pour un fichier dont personne n'avait jamais promis la persistance.
    Maintenant : rien n'est promis, donc rien ne peut etre rompu."""
    from forge.mutation_proof import verify_mutation_receipt
    from dataclasses import asdict
    flux, _ = deux_evidences
    sr = make_signed_receipt("mutation", "r-flux", "OK", {"x": 1}, evidence_path=str(flux))
    flux.write_bytes(b"contenu DIFFERENT\n")          # le flux bouge : c'est sa nature
    res = verify_mutation_receipt(asdict(sr.receipt), sr.signature, "r-flux", REPO_ROOT)
    assert not [r for r in res["raisons"] if "vidence" in r], (
        f"une rupture d'evidence est signalee pour un flux non scelle : {res['raisons']}")


def test_une_PREUVE_alteree_declenche_TOUJOURS_la_rupture(deux_evidences):
    """CONTROLE NEGATIF. Sans lui, le test precedent pourrait etre vert parce que le
    controle de provenance est devenu INERTE — et non parce qu'un flux n'est pas scelle."""
    from forge.mutation_proof import verify_mutation_receipt
    from dataclasses import asdict
    _, preuve = deux_evidences
    sr = make_signed_receipt("mutation", "r-preuve", "OK", {"x": 1}, evidence_path=str(preuve))
    preuve.write_bytes(b'{"a": 999}\n')               # une preuve, elle, ne doit PAS bouger
    res = verify_mutation_receipt(asdict(sr.receipt), sr.signature, "r-preuve", REPO_ROOT)
    assert [r for r in res["raisons"] if "vidence" in r], (
        "une evidence SCELLEE alteree passe inapercue : le controle est inerte")

# LEVER L'AMBIGUITE DE `detail["solvability"]["passed"]` (GO Pierre 2026-08-17).
#
# DEFAUT MESURE, et il trompe le LECTEUR, pas le programme. Le reçu d'un run porte :
#     "solvability": {"checked": true, "passed": true, ...}
# alors que l'execution reelle de la solvabilite de tetris rend `won: 0, lost: 50`. Les deux
# sont VRAIS : `passed` vient de `check_solvability_wired`, qui mesure le CABLAGE (l'entree
# declaree existe-t-elle, le wrapper la reference-t-il), jamais si le jeu est solvable.
# L'homonymie fait le reste.
#
# LE CODE, LUI, NE SE TROMPE PAS — mesure des 3 consommateurs (driver.py:1920, 2086, 2120) :
# `solvability["passed"]` y est aligne sur `e2e_ok` et `harness_flags["passed"]`, deux mesures
# d'outillage. Le commentaire de la l.2082 le dit : « final combine les autres volets du gate
# s10a (e2e/solvabilite/harnais) ». Aucun consommateur ne lit ce booleen comme « jeu solvable ».
#
# D'OU LA FORME DU LOT : PAS de renommage. Le nom `solvability` est deja dans 33 `state.json`
# COMMITES et dans leurs `verdict.partial.json`. Renommer creerait DEUX vocabulaires selon la
# date du run sans reecrire le passe — l'ambiguite serait deplacee, pas levee. On AJOUTE une
# cle soeur, comme e48801c a ajoute `timed_out` SANS retirer `returncode = -2`.
#
# CLE SOEUR ET NON CHAMP INTERNE, et c'est mesure : deux tests figent la forme du reçu en
# EGALITE STRICTE (`test_driver_solvability.py:177`, `test_solvability_wired_descriptor.py:146`).
# Ils assertent sur la VALEUR de `detail["solvability"]`, pas sur l'ensemble des cles de
# `detail` : une cle soeur ne les casse donc pas, et la forme du reçu d'oracle reste intacte.
#
# CE QUE LE LOT NE PEUT PAS FAIRE, et qui est dit dans le champ lui-meme : porter le RESULTAT.
# `won`/`trials` sont imprimes par `solvability_godot.mjs` sur stdout, captures dans
# `evidence/oracle_<jeu>.log` — exclu par `.gitignore:81` — et AUCUN parseur Python ne les lit.
# Le driver ne conserve de l'oracle que `returncode` et `evidence_path`. Le reçu peut donc
# dire ce que son booleen NE dit PAS ; il ne peut pas dire ce qu'il en est.
from __future__ import annotations

from pathlib import Path

from forge.driver import SOLVABILITY_MESURE, ForgeDriver


def _driver(tmp_path: Path) -> ForgeDriver:
    return ForgeDriver(project="p", run_id="r", run_dir=tmp_path, profile="standard",
                       executor=lambda *a, **k: {}, src_root=tmp_path)


def test_la_cle_soeur_dit_CE_QUI_EST_MESURE():
    assert SOLVABILITY_MESURE["mesure"] == "cablage_du_harnais"


def test_elle_dit_AUSSI_ce_qui_n_est_PAS_mesure():
    """Le coeur du lot : un lecteur doit comprendre que `passed: true` ne prouve pas que le
    jeu est solvable. Le dire explicitement vaut mieux que l'esperer du nom."""
    ne_mesure_pas = SOLVABILITY_MESURE["ne_mesure_pas"]
    assert "solvab" in ne_mesure_pas.lower()
    assert "won" in ne_mesure_pas or "trials" in ne_mesure_pas


def test_elle_NOMME_ou_vit_le_resultat_reel_et_son_absence_du_depot():
    """Un champ qui dit « ce n'est pas ici » doit dire OU c'est — et avouer que ce porteur
    n'est pas versionne, sinon il envoie chercher une preuve introuvable."""
    r = SOLVABILITY_MESURE["resultat_reel"]
    assert "evidence" in r and "log" in r
    assert "versionn" in r.lower(), "l'absence du depot doit etre DITE"


def test_c_est_une_STRUCTURE_pas_de_la_prose_en_commentaire():
    """Regle studio ratifiee 2026-07-23 : aucune decision — ni aucune semantique — dans un
    commentaire. Le sens du booleen voyage dans un CHAMP, donc dans le reçu signe."""
    assert isinstance(SOLVABILITY_MESURE, dict)
    assert set(SOLVABILITY_MESURE) == {"mesure", "ne_mesure_pas", "resultat_reel"}
    assert all(isinstance(v, str) and v for v in SOLVABILITY_MESURE.values())


def test_la_cle_soeur_est_POSEE_dans_le_detail_du_run(tmp_path):
    """Cablage : un champ qu'aucun reçu ne porte serait un « producteur sans consommateur ».
    On verifie que le driver l'ecrit A COTE de `solvability`, jamais DEDANS."""
    detail: dict = {}
    _driver(tmp_path)._poser_mesure_solvabilite(detail)
    assert detail["solvability_mesure"] == SOLVABILITY_MESURE


def test_la_cle_soeur_NE_TOUCHE_PAS_au_reçu_de_l_oracle(tmp_path):
    """CONTRE-EPREUVE : deux tests figent `detail["solvability"]` en egalite stricte. Le lot
    ne doit rien y ajouter — sinon il casse la forme du reçu d'oracle."""
    detail: dict = {"solvability": {"passed": True, "raisons": [], "checked": True}}
    _driver(tmp_path)._poser_mesure_solvabilite(detail)
    assert detail["solvability"] == {"passed": True, "raisons": [], "checked": True}


def test_le_voisinage_alphabetique_rend_la_cle_DECOUVRABLE():
    """`solvability_mesure` suit immediatement `solvability` dans un JSON trie (le driver
    serialise avec `sort_keys`). Un lecteur du reçu la voit sans la chercher — c'est la
    raison du nom, pas un hasard."""
    cles = sorted(["solvability", "solvability_mesure", "solvabilite_autre", "status"])
    assert cles.index("solvability_mesure") == cles.index("solvability") + 1
